import Foundation

// MARK: - De bankrekening als bestemming van de verdeling (D3)
//
// In Verdelen kun je naast spaarpotten en beleggingen ook een deel van je inkomen aan de BANKREKENING toewijzen: "dit blijft op mijn
// rekening". Zo kan "Nog te verdelen" op precies nul uitkomen. Het is een toewijzing, geen overboeking: er beweegt niets, het saldo
// van de bank, de potten en het dagboek veranderen niet (docs/work/plan2.md par. 1, besluit D3.1 t/m D3.4).
//
// De bankrekening gedraagt zich als een pot met een vast pseudo-id (`BankShare.id`): dezelfde regels (vast bedrag, of een percentage
// plus een extra bedrag), dezelfde standaard en dezelfde afwijking per maand in `MonthPlan.allocations` en `percentAllocations`
// onder de sleutel van dat id. Alle functies die een verdeling op id lezen of schrijven werken zo ook voor de bank. Verschil met een
// pot: geen extra overschrijfdata en geen gebeurtenis op een dag (er gaat geen geld over).
//
// Rekenregels, in hele centen (`MonthFigures`):
//   remaining  = inkomen - bankuitgaven - gespaard - belegd           (wat er op de rekening blijft: ongewijzigd, ook in het verleden)
//   toBank     = het deel van `remaining` dat je aan de bankrekening toewees (telt als verdeeld)
//   unassigned = remaining - toBank                                    ("Nog te verdelen" in de huidige en komende maanden)

struct BankShare: Codable, Equatable, ContributionSource {
    /// Vast pseudo-id van de bankrekening in de verdeling. Geen enkele pot of belegging heeft dit id.
    static let id = UUID(uuidString: "00000000-0000-4000-8000-00000000BA4C")!
    /// De sleutel in `MonthPlan.allocations` en `percentAllocations`.
    static let key = id.uuidString

    var id: UUID { BankShare.id }
    /// De bankrekening bestaat altijd: de regel geldt vanaf de eerste maand van de gegevens (de motor knipt maanden vóór de
    /// startmaand zelf af).
    var startMonth: YearMonth { YearMonth(year: 1, month: 1) }
    var monthlyContribution: Double = 0
    var contributionMode: ContributionMode = .fixed
    var contributionPercent: Double = 0
    var contributionBasis: IncomeBasis = .salary
    var contributionExtra: Double = 0
    var extraTransfers: [TransferPart] { [] }

    enum CodingKeys: String, CodingKey {
        case monthlyContribution, contributionMode, contributionPercent, contributionBasis, contributionExtra
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthlyContribution = c.decodeLenient(Double.self, forKey: .monthlyContribution, default: 0)
        contributionMode = c.decodeLenient(ContributionMode.self, forKey: .contributionMode, default: .fixed)
        contributionPercent = c.decodeLenient(Double.self, forKey: .contributionPercent, default: 0)
        contributionBasis = c.decodeLenient(IncomeBasis.self, forKey: .contributionBasis, default: .salary)
        contributionExtra = c.decodeLenient(Double.self, forKey: .contributionExtra, default: 0)
    }

    /// Alleen wat afwijkt van niets schrijven: een bestand zonder bankdeel blijft byte voor byte gelijk.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if monthlyContribution.isFinite, monthlyContribution != 0 { try c.encode(monthlyContribution, forKey: .monthlyContribution) }
        if contributionMode != .fixed { try c.encode(contributionMode, forKey: .contributionMode) }
        if contributionPercent.isFinite, contributionPercent != 0 { try c.encode(contributionPercent, forKey: .contributionPercent) }
        if contributionBasis != .salary { try c.encode(contributionBasis, forKey: .contributionBasis) }
        if AllocationMath.extraCents(contributionExtra) != 0 { try c.encode(AllocationMath.cleanExtra(contributionExtra), forKey: .contributionExtra) }
    }
}

extension MonthFigures {
    /// Het deel van `remaining` dat je aan de bankrekening toewees. Zie `FinanceData.monthFigures`.
    /// Wat er nog te verdelen is: wat er op de rekening blijft min wat je daarvan aan de bankrekening toewees (kan negatief zijn).
    var unassigned: Int { remaining - toBank }
}

extension FinanceData {
    /// Is er een standaard voor de bankrekening ingesteld (of een maand die ervan afwijkt)?
    var hasBankShare: Bool {
        if bankShare != BankShare() { return true }
        return months.values.contains { $0.allocations[BankShare.key] != nil || $0.percentAllocations[BankShare.key] != nil }
    }

    /// Het bedrag dat in `month` aan de bankrekening is toegewezen, in euro's (hetzelfde getal als `monthFigures(month).toBank`).
    func bankShareAmount(in month: YearMonth) -> Double {
        CentsMath.value(monthFigures(month).toBank)
    }

    /// Wat er in `month` nog niet is toegewezen: het getal bij het label "Nog te verdelen" (`MonthFigures.unassigned`), in euro's.
    /// Alles wat "nog te verdelen" of "nog niet verdeeld" zegt (Aankoopcheck, Noodbuffer, versnellers) leest dit; wat geld
    /// verplaatst (`BankTimeline`, het dagboek, de export) blijft op `remaining(in:)`.
    func unassigned(in month: YearMonth) -> Double {
        CentsMath.value(monthFigures(month).unassigned)
    }

    /// Zoals `unassigned(in:)`, voor een gemiddelde maand (`estimatedFigures`): bij een salaris om de zoveel weken of dagen is een
    /// maand met nul of twee uitbetalingen geen maat voor wat je gewoonlijk hebt.
    func estimatedUnassigned(in month: YearMonth) -> Double {
        CentsMath.value(estimatedFigures(month).unassigned)
    }

    /// Legt in al opgeslagen maanden van de startmaand tot `current` zonder eigen regel voor de bankrekening de regel `rule` vast,
    /// zodat een nieuwe standaard het verleden niet verandert (een pot krijgt zijn regel vastgelegd door `materialize`; voor de
    /// bankrekening, die er standaard niet in staat, gebeurt dat hier).
    mutating func freezePastBankShare(rule: AllocationRule, before current: YearMonth) {
        for monthKey in Array(months.keys) {
            guard let m = YearMonth(key: monthKey), m < current, m >= startMonth,
                  months[monthKey]?.allocations[BankShare.key] == nil,
                  months[monthKey]?.percentAllocations[BankShare.key] == nil else { continue }
            switch rule {
            case .amount(let value): months[monthKey]?.allocations[BankShare.key] = value
            case .percent(let percent): months[monthKey]?.percentAllocations[BankShare.key] = percent
            }
        }
    }

    /// Wijst wat er nog te verdelen is toe aan de bankrekening (als vast bedrag): "Rest naar bankrekening". Doet niets als er niets
    /// te verdelen is.
    mutating func sendRemainingToBank(in month: YearMonth) {
        let left = monthFigures(month).unassigned
        guard left > 0 else { return }
        let current = CentsMath.int(allocation(BankShare.id, in: month))
        setAllocation(BankShare.id, in: month, amount: CentsMath.value(CentsMath.add(current, left)))
    }
}
