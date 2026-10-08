import Foundation
import CommonCrypto
import Security

/// Wachtwoord omzetten naar een hash die niet terug te rekenen is: PBKDF2 met HMAC-SHA256,
/// een eigen willekeurig zout per account en veel herhalingen, zodat raden duur wordt.
/// Het wachtwoord zelf wordt nooit bewaard.
enum PasswordHasher {
    static let defaultIterations = 150_000
    static let keyLength = 32
    static let saltLength = 16

    /// 16 willekeurige bytes uit de beveiligde generator van het systeem.
    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        let count = bytes.count
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status != errSecSuccess {
            // Zou niet moeten gebeuren. De standaard generator van Swift is ook cryptografisch veilig.
            for index in 0..<count {
                bytes[index] = UInt8.random(in: 0...255)
            }
        }
        return Data(bytes)
    }

    /// Geeft de afgeleide sleutel van 32 bytes. Een leeg resultaat betekent dat de berekening mislukte.
    /// Het wachtwoord wordt eerst in een vaste Unicode-vorm gezet, zodat "é" van elk toetsenbord hetzelfde geeft.
    static func hash(password: String, salt: Data, iterations: Int = PasswordHasher.defaultIterations) -> Data {
        let normalized = password.precomposedStringWithCanonicalMapping
        let passwordLength = normalized.utf8.count
        let saltBytes = [UInt8](salt)
        let saltCount = saltBytes.count
        let derivedLength = keyLength
        var derived = [UInt8](repeating: 0, count: derivedLength)
        let rounds = UInt32(clamping: max(1, iterations))
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            normalized,
            passwordLength,
            saltBytes,
            saltCount,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            rounds,
            &derived,
            derivedLength
        )
        guard status == Int32(kCCSuccess) else { return Data() }
        return Data(derived)
    }

    /// Klopt dit wachtwoord met de bewaarde hash? De vergelijking kost altijd evenveel tijd.
    static func verify(password: String, salt: Data, iterations: Int, expected: Data) -> Bool {
        let candidate = hash(password: password, salt: salt, iterations: iterations)
        guard !candidate.isEmpty, !expected.isEmpty else { return false }
        return constantTimeEquals(candidate, expected)
    }

    /// Vergelijkt twee reeksen bytes zonder eerder te stoppen bij het eerste verschil.
    static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        let left = [UInt8](lhs)
        let right = [UInt8](rhs)
        var difference = left.count ^ right.count
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a: UInt8 = index < left.count ? left[index] : 0
            let b: UInt8 = index < right.count ? right[index] : 0
            difference |= Int(a ^ b)
        }
        return difference == 0
    }
}
