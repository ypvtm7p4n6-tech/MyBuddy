import Foundation

/// Instellingen voor inloggen en synchroniseren via Firebase (zonder Firebase-SDK).
///
/// Zo zet je het aan:
/// 1. Open de Firebase-console, kies je project, en ga naar Project settings > Algemeen.
/// 2. Kopieer de "Web API-sleutel".
/// 3. Plak hem hieronder tussen de aanhalingstekens bij `apiKey`.
/// 4. Start de app opnieuw.
///
/// Zolang `apiKey` leeg is, werkt de app precies zoals voorheen: met accounts die alleen op dit apparaat staan.
/// De app hangt dus nooit af van deze sleutel om te kunnen bouwen of starten.
/// Stap voor stap (ook voor de regels in de console): zie firebase/README.md.
enum FirebaseConfig {
    /// Je Web API-sleutel uit de Firebase-console. Leeg = alleen lokale accounts.
    static let apiKey = ""

    /// Het adres van je Realtime Database (regio europe-west1).
    static let databaseURL = "https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app"

    static let projectID = "my-buddy-finance"

    /// De bundle-ID van de app. Dezelfde waarde zet je (optioneel) in de beperking van de API-sleutel.
    static let bundleID = "nl.mybuddy.app"

    /// Is er een sleutel ingevuld? Dan loggen gebruikers in via Firebase en synchroniseert de app.
    static var isConfigured: Bool { !apiKey.isEmpty }
}
