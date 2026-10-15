import Foundation

// Aankoopcheck: is een product je werkuren waard?
// Alles in dit bestand is rekenwerk zonder klok en zonder netwerk, zodat het testbaar is.
// De app zoekt zelf niets op internet: `PurchaseSearch` bouwt alleen zoeklinks.

// MARK: - Uurloon

extension FinanceData {
    /// Effectief netto uurloon uit je salarisinstellingen.
    /// - Uurloon: het ingestelde uurloon (bij elk salarisschema hetzelfde).
    /// - Vast bedrag: het GEMIDDELDE maandsalaris gedeeld door het gemiddeld aantal uren per maand. Bij het maandelijkse
    ///   schema is dat maandsalaris / (uren per week × 52 / 12); bij een schema om de zoveel weken of dagen is het bedrag
    ///   per uitbetaling gedeeld door de uren van één cyclus (beide delen krijgen dezelfde gemiddelde maand).
    /// nil als dat niet te berekenen is (geen uren per week of geen salaris): dan vult de gebruiker zelf een uurloon in.
    func effectiveHourlyWage() -> Double? {
        let wage: Double
        switch salary.mode {
        case .hourly:
            wage = salary.hourlyRate
        case .fixed:
            let monthlyHours = salary.defaultMonthlyHours
            guard salary.hoursPerWeek > 0, monthlyHours.isFinite, monthlyHours > 0 else { return nil }
            wage = salary.averageMonthlyFixedAmount / monthlyHours
        }
        guard wage.isFinite, wage > 0 else { return nil }
        let rounded = wage.cents
        return rounded > 0 ? rounded : nil
    }
}

// MARK: - Soort aankoop

/// Hoe nodig een soort aankoop meestal is. Bepaalt de toon van de feedback.
enum PurchaseNeedLevel: String, Equatable {
    case need, mixed, want

    var title: String {
        switch self {
        case .need: return "Nodig"
        case .mixed: return "Deels nodig"
        case .want: return "Verlangen"
        }
    }

    /// Toon als de uren hoger zijn dan nodig (groen).
    var toneWhenWorth: String {
        switch self {
        case .need: return "Dit heb je gewoon nodig, dus het is een logische uitgave."
        case .mixed: return "Deels nodig, deels leuk: dat is een prima afweging."
        case .want: return "Het is een verlangen, en dat mag. Jij vindt het de uren waard."
        }
    }

    /// Toon als de uren gelijk of lager zijn dan nodig (rood).
    var toneWhenNotWorth: String {
        switch self {
        case .need: return "Zoiets heb je soms gewoon nodig. Zoek dan een goedkopere of tweedehands variant."
        case .mixed: return "Vraag je af of een eenvoudigere variant ook genoeg is."
        case .want: return "Het is een leuke extra, maar niet de werktijd die het kost."
        }
    }
}

enum PurchaseCategory: String, CaseIterable, Identifiable {
    case electronics, clothing, home, hobby, entertainment, transport, health, gifts, food, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .electronics: return "Elektronica"
        case .clothing: return "Kleding en schoenen"
        case .home: return "Huis en inrichting"
        case .hobby: return "Hobby en sport"
        case .entertainment: return "Entertainment en uitgaan"
        case .transport: return "Vervoer"
        case .health: return "Gezondheid en verzorging"
        case .gifts: return "Cadeaus"
        case .food: return "Eten en drinken"
        case .other: return "Overig"
        }
    }

    /// Korte naam voor in een kleine tegel.
    var shortTitle: String {
        switch self {
        case .electronics: return "Elektronica"
        case .clothing: return "Kleding"
        case .home: return "Huis"
        case .hobby: return "Hobby en sport"
        case .entertainment: return "Uitgaan"
        case .transport: return "Vervoer"
        case .health: return "Gezondheid"
        case .gifts: return "Cadeaus"
        case .food: return "Eten en drinken"
        case .other: return "Overig"
        }
    }

    /// SF Symbol.
    var symbol: String {
        switch self {
        case .electronics: return "laptopcomputer"
        case .clothing: return "tshirt"
        case .home: return "sofa"
        case .hobby: return "figure.run"
        case .entertainment: return "ticket"
        case .transport: return "car"
        case .health: return "cross.case"
        case .gifts: return "gift"
        case .food: return "fork.knife"
        case .other: return "bag"
        }
    }

    /// Korte, nuttige tip bij dit soort aankoop.
    var tip: String {
        switch self {
        case .electronics:
            return "Wacht 7 dagen en kijk ook naar refurbished: dat is vaak een stuk goedkoper met bijna dezelfde garantie."
        case .clothing:
            return "Reken in kosten per keer dragen: de prijs gedeeld door het aantal keren dat je het aantrekt. Past het bij kleding die je al hebt?"
        case .home:
            return "Meet eerst na en kijk ook tweedehands of in de kringloop. Meubels gaan jaren mee, kies liever kwaliteit dan de laagste prijs."
        case .hobby:
            return "Huur of leen het eerst. Doe je het na een paar keer nog steeds, dan loont kopen."
        case .entertainment:
            return "Dit geld is daarna op. Spreek een vast bedrag per maand af, dan loopt het nooit uit de hand."
        case .transport:
            return "Kijk naar de kosten per jaar, niet alleen naar de aanschaf. Onderhoud, verzekering en stalling tellen mee."
        case .health:
            return "Gezondheid gaat voor. Check eerst wat je zorgverzekering of aanvullende dekking vergoedt."
        case .gifts:
            return "Het gaat om het gebaar, niet om het bedrag. Spreek zo nodig een vast budget per persoon af."
        case .food:
            return "Koop met een lijstje en plan je maaltijden. Uit eten? Vergelijk even met zelf koken."
        case .other:
            return "Wacht 3 dagen. Is de zin dan weg, dan was het een opwelling."
        }
    }

    /// Hoeveel jaar je er ongeveer plezier van hebt. nil bij verbruik of een eenmalige uitgave.
    var lifespanYears: Double? {
        switch self {
        case .electronics: return 4
        case .clothing: return 3
        case .home: return 10
        case .hobby: return 5
        case .entertainment: return nil
        case .transport: return 5
        case .health: return nil
        case .gifts: return nil
        case .food: return nil
        case .other: return 3
        }
    }

    /// Hoe nodig dit soort aankoop meestal is: 0 (puur een verlangen) tot 1 (noodzaak).
    var need: Double {
        switch self {
        case .electronics: return 0.4
        case .clothing: return 0.4
        case .home: return 0.5
        case .hobby: return 0.2
        case .entertainment: return 0.1
        case .transport: return 0.8
        case .health: return 0.9
        case .gifts: return 0.4
        case .food: return 0.7
        case .other: return 0.3
        }
    }

    var needLevel: PurchaseNeedLevel {
        if need >= 0.7 { return .need }
        if need >= 0.35 { return .mixed }
        return .want
    }

    /// Toon als de uren gelijk of lager zijn dan nodig (rood). Meestal die van het niveau, maar tweedehands past
    /// niet bij eten en gezondheid: daar past alleen vergelijken en een goedkopere variant.
    var toneWhenNotWorth: String {
        switch self {
        case .food:
            return "Zoiets heb je gewoon nodig. Vergelijk prijzen of kies een goedkopere variant."
        case .health:
            return "Zoiets heb je soms gewoon nodig. Vergelijk prijzen en kijk wat je zorgverzekering vergoedt."
        default:
            return needLevel.toneWhenNotWorth
        }
    }

    /// Aantal dagen wachten voor je koopt. 0 = geen wachttijd nodig.
    var waitDays: Int {
        switch self {
        case .electronics: return 7
        case .clothing: return 1
        case .home: return 7
        case .hobby: return 3
        case .entertainment: return 1
        case .transport: return 3
        case .health: return 0
        case .gifts: return 0
        case .food: return 0
        case .other: return 3
        }
    }

    /// "24 uur" of "7 dagen". nil zonder wachttijd.
    var waitText: String? {
        switch waitDays {
        case ...0: return nil
        case 1: return "24 uur"
        default: return "\(waitDays) dagen"
        }
    }

    /// Rustige tip om even te wachten. nil zonder wachttijd.
    var waitNote: String? {
        guard let wait = waitText else { return nil }
        return "Wacht \(wait) voor je koopt. Is de zin dan nog net zo groot, dan was het geen opwelling."
    }
}

// MARK: - Invoer en uitkomst

enum PurchaseNoteKind: String, Equatable {
    case positive, warning, neutral
}

/// Eén regel feedback.
struct PurchaseNote: Identifiable, Equatable {
    var text: String
    var kind: PurchaseNoteKind

    var id: String { kind.rawValue + "|" + text }
}

struct PurchaseInput: Equatable {
    var name: String = ""
    var category: PurchaseCategory = .other
    var price: Double = 0
    var shipping: Double = 0
    /// Hoeveel uur je er voor wilt werken.
    var hoursWilling: Double = 0
    /// Netto uurloon.
    var hourlyWage: Double = 0
    /// Goedkopere prijs die de gebruiker zelf vond. nil = niets gevonden.
    var cheaperPrice: Double?
    /// Verzendkosten bij die prijs. nil telt als gratis verzending.
    var cheaperShipping: Double?
}

/// Wat de app van jou weet, om te kunnen zeggen of de aankoop financieel kan.
struct PurchasePotOption: Identifiable, Equatable {
    var id: UUID
    var name: String
    var balance: Double
    var goalAmount: Double?
    /// Wat er deze maand in gaat.
    var monthlyContribution: Double
    var isBuffer: Bool

    init(id: UUID = UUID(), name: String, balance: Double, goalAmount: Double? = nil,
         monthlyContribution: Double = 0, isBuffer: Bool = false) {
        self.id = id
        self.name = name
        self.balance = balance
        self.goalAmount = goalAmount
        self.monthlyContribution = monthlyContribution
        self.isBuffer = isBuffer
    }
}

struct PurchaseContext: Equatable {
    /// Inkomen van deze maand. 0 = onbekend.
    var monthlyIncome: Double = 0
    /// Wat deze maand nog te verdelen is (kan negatief zijn). nil = geen maandplan ingevuld, of nog geen inkomen.
    var remainingThisMonth: Double?
    /// `remainingThisMonth` is het restant van een GEMIDDELDE maand (bij een salaris om de zoveel weken of dagen) en niet van
    /// deze ene maand. De teksten zeggen dat dan ("In een gemiddelde maand ..."), zodat het getal niet tegenspreekt wat
    /// "Nog te verdelen" voor deze maand toont.
    var isAverageMonth: Bool = false
    /// Zijn de uitgaven van de bank deze maand al hoger dan het inkomen? Dan komt een negatief restant
    /// niet doordat je te veel verdeelde, maar doordat de uitgaven hoger zijn dan het inkomen.
    var expensesExceedIncome: Bool = false
    /// Saldo van de bankrekening nu. nil = geen saldo bekend.
    var bankBalance: Double?
    /// Wat er boven de bankbuffer staat (nooit negatief). nil = geen saldo bekend.
    var bankSurplus: Double?
    /// De gewenste bankbuffer. Nodig om te zeggen hoever je onder de buffer komt als je saldo er al onder staat.
    /// nil = onbekend: dan geldt alleen `bankSurplus`.
    var bankBuffer: Double?
    var pots: [PurchasePotOption] = []
}

extension PurchaseContext {
    /// Haalt de gegevens van de gebruiker op uit de app.
    /// `bufferPotID`: de pot die de gebruiker op de Buffer-pagina als buffer koos. Bestaat die pot niet (meer)
    /// of is er niets gekozen, dan geldt de pot die "Buffer" heet.
    static func make(from data: FinanceData, current: YearMonth, today: Date = Date(),
                     bufferPotID: UUID? = nil) -> PurchaseContext {
        var context = PurchaseContext()
        // Een GEMIDDELDE maand (`estimated...`): bij een salaris om de zoveel weken of dagen is een maand met nul of twee
        // uitbetalingen geen maat voor wat je gewoonlijk per maand hebt. Bij het maandelijkse schema is het deze maand.
        let income = data.estimatedMonthlyIncome(in: current)
        context.monthlyIncome = max(0, income)
        // Zonder inkomen zegt het maandplan niets: het restant is dan alleen min de uitgaven, en misschien is het
        // salaris gewoon nog niet ingevuld. Dan laten we het maandplan buiten de uitspraak.
        context.isAverageMonth = !data.salary.isMonthly
        if income > 0 {
            context.remainingThisMonth = data.estimatedRemaining(in: current)
            context.expensesExceedIncome = CentsMath.int(income) - CentsMath.int(data.expensesFromBank(in: current)) < 0
        }
        if let balance = data.bankBalanceNowIfKnown(current: current, today: today) {
            context.bankBalance = balance
            context.bankSurplus = data.bankSurplusAboveBuffer(current: current, today: today)
            context.bankBuffer = data.bankBuffer(current: current)
        }
        let chosenID = bufferPotID.flatMap { data.pot($0)?.id }
        let bufferID = chosenID ?? BufferCalc.bufferPot(in: data)?.id
        var options: [PurchasePotOption] = []
        for pot in data.pots {
            options.append(PurchasePotOption(id: pot.id,
                                             name: pot.name,
                                             balance: max(0, data.potBalanceNow(pot.id, current: current, today: today)),
                                             goalAmount: pot.goalAmount,
                                             monthlyContribution: data.estimatedAllocation(pot.id, in: current),
                                             isBuffer: pot.id == bufferID))
        }
        context.pots = options
        return context
    }
}

/// Wat de aankoop doet met het doel van een spaarpot, als je het uit die pot betaalt.
enum PurchaseGoalImpact: Equatable {
    /// Geen doel (of niet in te schatten).
    case none
    /// Het doel schuift niet op.
    case unaffected
    /// Het doel wordt zoveel maanden later gehaald.
    case delayed(months: Int)
    /// Het doel wordt niet meer gehaald omdat er geen inleg meer is.
    case unreachable
}

enum PurchaseVerdict: String, Equatable {
    case easy, tight, notNow, unknown

    var title: String {
        switch self {
        case .easy: return "Kan zonder pijn"
        case .tight: return "Kan, maar het gaat ten koste van je buffer of spaarpot"
        case .notNow: return "Kan nu niet"
        case .unknown: return "Nog niet te zeggen"
        }
    }

    var symbol: String {
        switch self {
        case .easy: return "checkmark.circle.fill"
        case .tight: return "exclamationmark.triangle.fill"
        case .notNow: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// "Kan het?": past de aankoop in jouw geld?
struct PurchaseAffordability: Equatable {
    var verdict: PurchaseVerdict
    /// Eén zin die uitlegt hoe je het betaalt of waarom het niet kan.
    var summary: String
    var details: [PurchaseNote] = []
    /// De pot waaruit je het het beste betaalt (alleen bij `.tight`).
    var potID: UUID?
    var potName: String?
    var goalImpact: PurchaseGoalImpact = .none

    /// Aantal maanden dat het doel van die pot later wordt gehaald.
    var goalDelayMonths: Int? {
        if case .delayed(let months) = goalImpact { return months }
        return nil
    }
}

struct PurchaseResult: Equatable {
    /// Beste prijs inclusief verzending (de goedkopere, als die lager is).
    var totalCost: Double
    /// Prijs inclusief verzending van het eerste product.
    var originalTotal: Double
    var usesCheaper: Bool
    var savedByCheaper: Double
    var hasWage: Bool
    var hourlyWage: Double
    /// Uren werken die het kost, afgerond op 0,1 uur.
    var hoursNeeded: Double
    var hoursNeededOriginal: Double
    var hoursWilling: Double
    /// Alleen waard als je er meer uren voor over hebt dan het kost. Gelijk is niet waard.
    var isWorthIt: Bool
    /// Uren nodig / 8.
    var daysOfWork: Double
    /// Deel van je maandinkomen. nil als het inkomen niet bekend is.
    var shareOfMonthlyIncome: Double?
    /// Kosten per jaar bij de gemiddelde levensduur. nil bij verbruik.
    var costPerYear: Double?
    var hoursPerYear: Double?
    /// Prijs die bij de gekozen uren past (uren × uurloon).
    var maxWorthPrice: Double
    var affordability: PurchaseAffordability
    var feedback: [PurchaseNote]

    /// Gekozen uren min nodige uren. Positief = je houdt uren over.
    var hoursDifference: Double { ((hoursWilling - hoursNeeded) * 10).rounded() / 10 }
}

// MARK: - Rekenregels

enum PurchaseCalc {
    /// Sleutel voor het zelf ingevulde uurloon (@AppStorage).
    static let wageStorageKey = "purchase.manualHourlyWage.v1"

    /// Sleutel per account, zoals de rest van de app (zonder account: "demo"). Zo ziet een tweede account
    /// op hetzelfde apparaat niet het uurloon van de eerste.
    static func accountWageKey(_ accountID: String?) -> String {
        wageStorageKey + "." + (accountID ?? "demo")
    }
    static let maxAmount: Double = 1_000_000_000
    static let maxWage: Double = 100_000
    static let maxHours: Double = 100_000
    static let hoursPerWorkday: Double = 8
    /// Bereik en stap van de keuze "hoeveel uur wil je ervoor werken".
    static let hoursRange: ClosedRange<Double> = 0...200
    static let hoursStep: Double = 0.5
    /// Onder dit bedrag is een wachttijd-tip overdreven.
    static let waitThreshold: Double = 25
    /// Vanaf dit deel van je maandinkomen krijg je er een waarschuwing bij.
    static let incomeWarningShare: Double = 0.25

    // MARK: Invoer opschonen

    /// Bedrag: geen getal of negatief wordt 0, extreem groot wordt `maxAmount`, op centen.
    static func sanitizedAmount(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        return min(max(0, value), maxAmount).cents
    }

    static func sanitizedWage(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        return min(max(0, value), maxWage).cents
    }

    /// Uren: geen getal of negatief wordt 0, afgerond op 0,1 uur.
    static func sanitizedHours(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        let clamped = min(max(0, value), maxHours)
        return (clamped * 10).rounded() / 10
    }

    /// Prijs plus verzending, op hele centen opgeteld (nooit meer dan `maxAmount`).
    static func total(price: Double, shipping: Double) -> Double {
        let cents = CentsMath.int(sanitizedAmount(price)) + CentsMath.int(sanitizedAmount(shipping))
        return CentsMath.value(min(cents, CentsMath.int(maxAmount)))
    }

    /// Het uurloon waarmee gerekend wordt: een zelf ingevuld uurloon gaat voor, anders het salaris. nil = onbekend.
    static func resolvedWage(manual: Double, data: FinanceData) -> Double? {
        let own = sanitizedWage(manual)
        if own > 0 { return own }
        return data.effectiveHourlyWage()
    }

    /// Uren werken die een bedrag kost, afgerond op 0,1 uur. 0 zonder uurloon.
    /// Rekent in hele centen, zodat een grens als precies 5,5 uur niet door afrondingsruis verschuift.
    static func hoursNeeded(total: Double, wage: Double) -> Double {
        let wageCents = CentsMath.int(sanitizedWage(wage))
        guard wageCents > 0 else { return 0 }
        let totalCents = CentsMath.int(sanitizedAmount(total))
        return (Double(totalCents) * 10 / Double(wageCents)).rounded() / 10
    }

    static func hoursText(_ hours: Double) -> String {
        "\(Fmt.input(hours, maxDigits: 1)) uur"
    }

    /// Uren die iets kost. Is het minder dan 0,1 uur (afgerond 0), dan staat er dat in plaats van "0 uur".
    static func costHoursText(_ hours: Double) -> String {
        hours > 0 ? hoursText(hours) : "minder dan 0,1 uur"
    }

    /// Korte vorm van `costHoursText` voor een smalle tegel: "< 0,1 uur" past, "minder dan 0,1 uur werken" niet.
    static func costHoursShortText(_ hours: Double) -> String {
        hours > 0 ? hoursText(hours) : "< 0,1 uur"
    }

    /// Bedrag in een zin: hele euro's, maar onder één euro met centen ("€ 0,40"), zodat er nooit "€ 0" staat
    /// bij een bedrag dat er wel is.
    static func moneyText(_ value: Double) -> String {
        value >= 0.01 && value < 1 ? Fmt.euroExact(value) : Fmt.euro(value)
    }

    /// Hoeveel werkdagen een aantal dagen is, bijvoorbeeld "ongeveer 2,5 werkdagen". Onder één dag zonder "ongeveer".
    static func workdaysCaption(days: Double) -> String {
        let rounded = (max(0, days) * 10).rounded() / 10
        if rounded < 1 { return "minder dan een werkdag" }
        if rounded == 1 { return "ongeveer 1 werkdag" }
        return "ongeveer \(Fmt.input(rounded, maxDigits: 1)) werkdagen"
    }

    /// "Dat is 3% van je maandinkomen." nil onder 1%: dat is geen nieuws en zou "0%" worden.
    static func incomeShareText(_ share: Double) -> String? {
        guard share.isFinite, share >= 0.01 else { return nil }
        return "Dat is \(Fmt.percent(share, digits: 0)) van je maandinkomen."
    }

    // MARK: Uitkomst

    static func evaluate(_ input: PurchaseInput, context: PurchaseContext = PurchaseContext()) -> PurchaseResult {
        let category = input.category
        let wage = sanitizedWage(input.hourlyWage)
        let hasWage = wage > 0
        let willing = sanitizedHours(input.hoursWilling)
        let original = total(price: input.price, shipping: input.shipping)

        // Goedkoper vervangt het origineel alleen als prijs plus verzending samen lager is.
        var best = original
        var usesCheaper = false
        if let cheaperPrice = input.cheaperPrice {
            let alternative = total(price: cheaperPrice, shipping: input.cheaperShipping ?? 0)
            if CentsMath.int(alternative) < CentsMath.int(original) {
                best = alternative
                usesCheaper = true
            }
        }
        let saved = usesCheaper ? CentsMath.value(CentsMath.int(original) - CentsMath.int(best)) : 0

        let needed = hoursNeeded(total: best, wage: wage)
        let neededOriginal = hoursNeeded(total: original, wage: wage)
        let worth = hasWage && willing > needed

        let income = sanitizedAmount(context.monthlyIncome)
        let share: Double? = income > 0 ? best / income : nil

        var perYear: Double?
        var hoursPerYear: Double?
        if let life = category.lifespanYears, life > 0, best > 0 {
            perYear = (best / life).cents
            hoursPerYear = hasWage ? (needed / life * 10).rounded() / 10 : nil
        }

        let maxWorth = CentsMath.value(Int((Double(CentsMath.int(wage)) * willing).rounded()))
        let affordability = self.affordability(totalCost: best, context: context)

        var result = PurchaseResult(totalCost: best,
                                    originalTotal: original,
                                    usesCheaper: usesCheaper,
                                    savedByCheaper: saved,
                                    hasWage: hasWage,
                                    hourlyWage: wage,
                                    hoursNeeded: needed,
                                    hoursNeededOriginal: neededOriginal,
                                    hoursWilling: willing,
                                    isWorthIt: worth,
                                    daysOfWork: needed / hoursPerWorkday,
                                    shareOfMonthlyIncome: share,
                                    costPerYear: perYear,
                                    hoursPerYear: hoursPerYear,
                                    maxWorthPrice: maxWorth,
                                    affordability: affordability,
                                    feedback: [])
        result.feedback = feedback(for: result, input: input)
        return result
    }

    // MARK: Feedback

    private static func feedback(for r: PurchaseResult, input: PurchaseInput) -> [PurchaseNote] {
        let category = input.category
        var notes: [PurchaseNote] = []

        guard r.hasWage else {
            return [PurchaseNote(text: "Vul eerst je uurloon in, dan reken ik uit hoeveel uur dit kost.", kind: .neutral)]
        }
        guard r.totalCost > 0 else {
            return [PurchaseNote(text: "Vul een prijs in, dan reken ik uit hoeveel uur dit kost.", kind: .neutral)]
        }

        if r.isWorthIt {
            notes.append(PurchaseNote(
                text: "Je vindt dit \(hoursText(r.hoursWilling)) werken waard en het kost \(costHoursText(r.hoursNeeded)). Je houdt \(hoursText(r.hoursDifference)) over.",
                kind: .positive))
            notes.append(PurchaseNote(text: category.needLevel.toneWhenWorth, kind: .positive))
            if r.usesCheaper {
                var text = "Goedkoper gevonden: dat scheelt \(moneyText(r.savedByCheaper))."
                if r.hoursWilling <= r.hoursNeededOriginal {
                    text += " Zo past het wel binnen de uren die je ervoor over had."
                }
                notes.append(PurchaseNote(text: text, kind: .positive))
            }
            switch r.affordability.verdict {
            case .easy:
                notes.append(PurchaseNote(text: "\(r.affordability.verdict.title). \(r.affordability.summary)", kind: .positive))
            case .tight, .notNow:
                notes.append(PurchaseNote(text: "\(r.affordability.verdict.title). \(r.affordability.summary)", kind: .warning))
            case .unknown:
                break
            }
        } else {
            let gap = ((r.hoursNeeded - r.hoursWilling) * 10).rounded() / 10
            if r.hoursWilling <= 0 {
                notes.append(PurchaseNote(
                    text: "Je wilde er geen uur voor werken, maar het kost \(costHoursText(r.hoursNeeded)).",
                    kind: .warning))
            } else if gap > 0 {
                notes.append(PurchaseNote(
                    text: "Je wilde er \(hoursText(r.hoursWilling)) voor werken, maar het kost \(hoursText(r.hoursNeeded)). Dat is \(hoursText(gap)) meer dan je ervoor over hebt.",
                    kind: .warning))
            } else {
                notes.append(PurchaseNote(
                    text: "Het kost precies de \(hoursText(r.hoursWilling)) die je ervoor wilde werken. Gelijk is niet genoeg: eigenlijk vind je het niet waard.",
                    kind: .warning))
            }
            if r.hoursWilling > 0 {
                notes.append(PurchaseNote(
                    text: "Bij \(hoursText(r.hoursWilling)) werken hoort een prijs onder ongeveer \(moneyText(r.maxWorthPrice)). Vind je het daaronder, dan is het je wel waard.",
                    kind: .neutral))
            }
            notes.append(PurchaseNote(text: category.toneWhenNotWorth, kind: .neutral))
            if r.usesCheaper {
                notes.append(PurchaseNote(
                    text: "Goedkoper gevonden scheelt \(moneyText(r.savedByCheaper)), maar het blijft meer dan je ervoor over hebt.",
                    kind: .neutral))
            }
        }

        if let share = r.shareOfMonthlyIncome, share >= incomeWarningShare {
            notes.append(PurchaseNote(text: "Dit is \(Fmt.percent(share, digits: 0)) van je maandinkomen.", kind: .warning))
        }
        // Onder één euro per jaar of 0,1 uur per jaar is de regel alleen maar rommelig.
        if let perYear = r.costPerYear, perYear >= 1, let life = category.lifespanYears {
            var text = "Gebruik je het ongeveer \(Fmt.input(life, maxDigits: 0)) jaar, dan kost het \(Fmt.euro(perYear)) per jaar"
            if let hoursPerYear = r.hoursPerYear, hoursPerYear >= 0.1 {
                text += ", zo'n \(hoursText(hoursPerYear)) werken per jaar."
            } else {
                text += "."
            }
            notes.append(PurchaseNote(text: text, kind: .neutral))
        }
        if r.totalCost >= waitThreshold, let wait = category.waitNote {
            notes.append(PurchaseNote(text: wait, kind: .neutral))
        }

        // Geen dubbele regels (de regels hebben een id op basis van hun tekst).
        var seen = Set<String>()
        return notes.filter { seen.insert($0.id).inserted }
    }

    // MARK: Kan het?

    /// Past de aankoop in wat je deze maand nog te verdelen hebt, boven je bankbuffer, of moet het uit een spaarpot?
    static func affordability(totalCost: Double, context: PurchaseContext) -> PurchaseAffordability {
        let cost = sanitizedAmount(totalCost)
        let costCents = CentsMath.int(cost)
        let month = context.remainingThisMonth
        let surplus = context.bankSurplus
        let balance = context.bankBalance
        var pots: [PurchasePotOption] = []
        for pot in context.pots {
            var copy = pot
            copy.balance = max(0, pot.balance)
            pots.append(copy)
        }

        guard month != nil || surplus != nil || balance != nil || !pots.isEmpty else {
            return PurchaseAffordability(
                verdict: .unknown,
                summary: "Vul je inkomsten, banksaldo of spaarpotten in, dan check ik ook of het financieel kan.")
        }
        guard costCents > 0 else {
            return PurchaseAffordability(verdict: .easy, summary: "Er valt niets te betalen.")
        }

        let fitsMonth = month.map { CentsMath.int($0) >= costCents } ?? false
        let fitsSurplus = surplus.map { CentsMath.int($0) >= costCents } ?? false
        let bankCovers = balance.map { CentsMath.int($0) >= costCents } ?? false
        // Kan de bank het nu niet betalen, dan is "zonder pijn" onwaar, ook al past het in het maandplan
        // (bijvoorbeeld vlak voor de uitbetaaldag, als het salaris nog moet komen).
        let bankShort = balance != nil && !bankCovers
        let isEasy = fitsSurplus || (fitsMonth && !bankShort)
        let planWaitsForBank = fitsMonth && !isEasy
        let best = bestPot(costCents: costCents, cost: cost, pots: pots)
        let potsTotalCents = pots.reduce(0) { $0 + CentsMath.int($1.balance) }
        let combinedPots = !pots.isEmpty && potsTotalCents >= costCents

        var details: [PurchaseNote] = []

        // Deze maand, of bij een salaris om de zoveel weken of dagen een gemiddelde maand (het restant komt dan uit
        // `estimatedRemaining` en is niet het getal van "Nog te verdelen" voor deze ene maand).
        let average = context.isAverageMonth
        let have = average ? "In een gemiddelde maand heb je nog" : "Je hebt deze maand nog"
        if let month = month {
            if fitsMonth {
                let left = CentsMath.value(CentsMath.int(month) - costCents)
                let text = left >= 1
                    ? "\(have) \(Fmt.euro(month)) te verdelen. Hier blijft \(Fmt.euro(left)) van over."
                    : "\(have) \(Fmt.euro(month)) te verdelen: precies genoeg."
                details.append(PurchaseNote(text: text, kind: .positive))
            } else if month > 0 {
                let missing = CentsMath.value(costCents - CentsMath.int(month))
                details.append(PurchaseNote(
                    text: "\(have) \(Fmt.euro(month)) te verdelen. Dat is \(PurchaseCalc.moneyText(missing)) te weinig.",
                    kind: .warning))
            } else if month < 0 {
                let text = average
                    ? "In een gemiddelde maand verdeel je al meer dan je hebt, er is niets vrij."
                    : "Deze maand heb je al meer verdeeld dan je hebt, er is niets vrij."
                details.append(PurchaseNote(text: text, kind: .warning))
            } else {
                let text = average
                    ? "In een gemiddelde maand is alles al verdeeld, er is niets vrij voor deze aankoop."
                    : "Deze maand is alles al verdeeld, er is niets vrij voor deze aankoop."
                details.append(PurchaseNote(text: text, kind: .warning))
            }
        }

        // Bankrekening boven de buffer.
        if fitsSurplus, let surplus = surplus {
            details.append(PurchaseNote(
                text: "Op je rekening staat \(Fmt.euro(surplus)) boven je buffer. Dit past erin.",
                kind: .positive))
        } else if let balance = balance {
            if bankCovers {
                let below = CentsMath.value(costCents - CentsMath.int(surplus ?? 0))
                if fitsMonth {
                    details.append(PurchaseNote(
                        text: "Je saldo is genoeg. Je komt dan \(moneyText(below)) onder je bankbuffer, maar het past wel in je maandplan.",
                        kind: .neutral))
                } else {
                    details.append(PurchaseNote(
                        text: "Je saldo is genoeg, maar je komt dan \(moneyText(below)) onder je bankbuffer.",
                        kind: .warning))
                }
            } else {
                details.append(PurchaseNote(
                    text: "Je banksaldo is \(Fmt.euro(balance)). Dat is te weinig voor deze aankoop.",
                    kind: .warning))
            }
        }

        // Spaarpotten: alleen als het niet vanzelf past.
        if !isEasy {
            if let best = best {
                let name = best.pot.name.isEmpty ? "spaarpot" : best.pot.name
                details.append(PurchaseNote(text: "Uit je pot \(name) (nu \(Fmt.euro(best.pot.balance))) kan het wel.", kind: .neutral))
                if best.pot.isBuffer {
                    details.append(PurchaseNote(text: "Let op: dit is je buffer. Houd die liever vrij voor tegenvallers.", kind: .warning))
                }
                switch best.impact {
                case .delayed(let months):
                    details.append(PurchaseNote(
                        text: "Je doel voor \(name) wordt daardoor \(Fmt.duration(months: months)) later gehaald.",
                        kind: .warning))
                case .unaffected:
                    details.append(PurchaseNote(text: "Je doel voor \(name) schuift niet op.", kind: .neutral))
                case .unreachable:
                    details.append(PurchaseNote(
                        text: "Je haalt het doel voor \(name) daarna niet meer: er gaat geen inleg meer in.",
                        kind: .warning))
                case .none:
                    break
                }
            } else if combinedPots {
                details.append(PurchaseNote(
                    text: "Geen enkele spaarpot heeft genoeg alleen, alle potten samen wel (\(Fmt.euro(CentsMath.value(potsTotalCents)))).",
                    kind: .neutral))
            } else if !pots.isEmpty {
                let largest = pots.map { CentsMath.int($0.balance) }.max() ?? 0
                details.append(PurchaseNote(
                    text: "Geen enkele spaarpot heeft genoeg. De grootste heeft \(Fmt.euro(CentsMath.value(largest))).",
                    kind: .warning))
            }
        }

        // Uitspraak.
        if isEasy {
            let summary = fitsMonth
                ? (average ? "Het past in wat je in een gemiddelde maand nog te verdelen hebt."
                           : "Het past in wat je deze maand nog te verdelen hebt.")
                : "Het past in wat je op je rekening boven je buffer hebt."
            return PurchaseAffordability(verdict: .easy, summary: summary, details: details)
        }
        if planWaitsForBank {
            let lead = "Het past in je maandplan, maar je banksaldo is er nu nog niet voor."
            if let best = best, !best.pot.isBuffer {
                let name = best.pot.name.isEmpty ? "spaarpot" : best.pot.name
                return PurchaseAffordability(verdict: .tight, summary: "\(lead) Uit je spaarpot \(name) kan het nu wel.",
                                             details: details, potID: best.pot.id, potName: best.pot.name,
                                             goalImpact: best.impact)
            }
            return PurchaseAffordability(verdict: .notNow, summary: "\(lead) Wacht tot er geld bij je saldo komt.",
                                         details: details)
        }
        if let best = best, !best.pot.isBuffer {
            let name = best.pot.name.isEmpty ? "spaarpot" : best.pot.name
            return PurchaseAffordability(verdict: .tight, summary: "Je betaalt het uit je spaarpot \(name).",
                                         details: details, potID: best.pot.id, potName: best.pot.name,
                                         goalImpact: best.impact)
        }
        if bankCovers {
            return PurchaseAffordability(verdict: .tight, summary: "Je komt onder je bankbuffer.", details: details,
                                         potID: best?.pot.id, potName: best?.pot.name, goalImpact: best?.impact ?? PurchaseGoalImpact.none)
        }
        if let best = best {
            return PurchaseAffordability(verdict: .tight, summary: "Je betaalt het uit je buffer.", details: details,
                                         potID: best.pot.id, potName: best.pot.name, goalImpact: best.impact)
        }
        if combinedPots {
            return PurchaseAffordability(verdict: .tight, summary: "Je moet het uit meerdere spaarpotten halen.", details: details)
        }
        return PurchaseAffordability(verdict: .notNow,
                                     summary: "Je hebt er nu niet genoeg voor vrij; spaar er eerst voor.",
                                     details: details)
    }

    /// De pot waaruit je het het beste betaalt: niet de buffer, met zo min mogelijk gevolgen voor het doel,
    /// en de kleinste pot die genoeg heeft (zodat grote potten intact blijven).
    private static func bestPot(costCents: Int, cost: Double,
                                pots: [PurchasePotOption]) -> (pot: PurchasePotOption, impact: PurchaseGoalImpact)? {
        var best: (pot: PurchasePotOption, impact: PurchaseGoalImpact)?
        var bestRank: (Int, Int, Int, String, String)?
        for pot in pots where CentsMath.int(pot.balance) >= costCents {
            let impact = goalImpact(of: pot, spending: cost)
            let delay: Int
            switch impact {
            case .none, .unaffected: delay = 0
            case .delayed(let months): delay = months
            case .unreachable: delay = Int.max / 2
            }
            let rank = (pot.isBuffer ? 1 : 0, delay, CentsMath.int(pot.balance), pot.name, pot.id.uuidString)
            if bestRank == nil || rank < bestRank! {
                bestRank = rank
                best = (pot, impact)
            }
        }
        return best
    }

    /// Eenvoudige schatting op basis van de maandinleg (zonder rente): hoeveel maanden later is het doel van de pot
    /// gehaald als je `cost` uit de pot betaalt?
    static func goalImpact(of pot: PurchasePotOption, spending cost: Double) -> PurchaseGoalImpact {
        guard let goal = pot.goalAmount, goal > 0 else { return .none }
        let goalCents = CentsMath.int(goal)
        let contribution = CentsMath.int(max(0, pot.monthlyContribution))
        let before = CentsMath.int(max(0, pot.balance))
        let after = before - CentsMath.int(sanitizedAmount(cost))

        func monthsToGoal(from balance: Int) -> Int? {
            let gap = goalCents - balance
            if gap <= 0 { return 0 }
            guard contribution > 0 else { return nil }
            let months = (gap + contribution - 1) / contribution
            return months > 12_000 ? nil : months
        }

        switch (monthsToGoal(from: before), monthsToGoal(from: after)) {
        case (let b?, let a?):
            return a > b ? .delayed(months: a - b) : .unaffected
        case (_?, nil):
            return .unreachable
        case (nil, _):
            return PurchaseGoalImpact.none
        }
    }
}

// MARK: - Goedkoper zoeken

struct PurchaseSearchLink: Identifiable, Equatable {
    var id: String
    var title: String
    /// SF Symbol.
    var symbol: String
    var url: URL
}

/// De app zoekt zelf niets op en leest geen prijzen van internet. Deze links openen alleen een zoekopdracht
/// op een vergelijkingssite; de gebruiker vult de beste prijs zelf in.
enum PurchaseSearch {
    static let maxQueryLength = 120

    /// Zonder witruimte aan de randen, dubbele spaties samengevoegd, niet te lang.
    static func cleanedQuery(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = words.joined(separator: " ")
        return String(joined.precomposedStringWithCanonicalMapping.prefix(maxQueryLength))
            .trimmingCharacters(in: .whitespaces)
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Percent-codering van tekst voor in een webadres: alles behalve letters, cijfers en - . _ ~ wordt %XX (UTF-8).
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Zoeklinks voor een productnaam. Lege naam geeft geen links.
    /// Elektronica gaat naar Tweakers Pricewatch, de rest naar Kieskeurig.
    static func links(for name: String, category: PurchaseCategory? = nil) -> [PurchaseSearchLink] {
        let query = cleanedQuery(name)
        guard !query.isEmpty else { return [] }
        let q = encode(query)

        var specs: [(id: String, title: String, symbol: String, address: String)] = [
            ("beslist", "Beslist.nl", "magnifyingglass", "https://www.beslist.nl/products/r/\(q)/"),
            ("google", "Google Shopping", "cart", "https://www.google.com/search?tbm=shop&hl=nl&gl=nl&q=\(q)")
        ]
        if category == .electronics {
            specs.append(("tweakers", "Tweakers Pricewatch", "cpu", "https://tweakers.net/pricewatch/zoeken/?keyword=\(q)"))
        } else {
            specs.append(("kieskeurig", "Kieskeurig", "checklist", "https://www.kieskeurig.nl/zoeken?q=\(q)"))
        }

        var links: [PurchaseSearchLink] = []
        for spec in specs {
            if let url = URL(string: spec.address) {
                links.append(PurchaseSearchLink(id: spec.id, title: spec.title, symbol: spec.symbol, url: url))
            }
        }
        return links
    }
}
