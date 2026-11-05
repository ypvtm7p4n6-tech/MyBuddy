import Foundation

// MARK: - Loon per maand
//
// Het loon (netto uurloon, vast bedrag per uitbetaling, uren per week) kan per maand veranderen: "vanaf november is mijn uurloon
// 15,20 in plaats van 14,35". Een wijziging (`SalaryChange`) geldt vanaf haar maand en blijft gelden tot de volgende wijziging.
// `FinanceData.salary` blijft het loon van het begin en alles wat niet met het bedrag te maken heeft: de soort (uurloon of vast
// bedrag), het schema, de salarisdag en de ankerdatum. Wie die verandert doet dat met `SalaryScheduleEdit` (dat het verleden
// vastlegt). Een bestand zonder wijzigingen rekent precies als altijd en codeert byte voor byte gelijk.
//
// WELKE MAAND? Het loon van een uitbetaling is dat van de kalendermaand waarin de uitbetaling op je rekening komt (de dag van
// de uitbetaling), ook als een deel van de uren in de maand ervoor is gewerkt en ook bij uren uit de agenda: de hele uitbetaling
// rekent met het loon van die maand. De app rekent per maand; "salaris in november" krijgt het loon van november. Dit staat op
// ÉÉN plek: `salarySettings(forPayoutOn:)`. Kiest de gebruiker later liever het loon van de gewerkte dagen, dan verandert alleen
// die ene functie.
//
// Een eigen salaris van een maand (`MonthPlan.salaryOverride`) is het totaal en gaat voor; eigen uren (`hoursOverride`) rekenen
// met het loon van die maand. Alles wat het loon van een maand nodig heeft leest `salarySettings(in:)`: de plekken die het SCHEMA
// lezen (`isMonthly`, `payDay`, `anchor`, `schedule`, `mode`) blijven `salary`.

/// Een wijziging van het loon vanaf een maand. Alleen de ingevulde velden veranderen; de rest blijft wat het was.
struct SalaryChange: Codable, Equatable, Identifiable {
    /// De eerste maand waarin de uitbetalingen dit loon hebben.
    var from: YearMonth
    /// Nieuw netto uurloon (bij `.hourly`). nil = onveranderd.
    var hourlyRate: Double?
    /// Nieuw vast bedrag per uitbetaling (bij `.fixed`; de naam is gebleven voor oude bestanden). nil = onveranderd.
    var fixedMonthly: Double?
    /// Nieuwe uren per week. nil = onveranderd.
    var hoursPerWeek: Double?

    var id: String { from.key }

    init(from: YearMonth, hourlyRate: Double? = nil, fixedMonthly: Double? = nil, hoursPerWeek: Double? = nil) {
        self.from = from
        self.hourlyRate = hourlyRate
        self.fixedMonthly = fixedMonthly
        self.hoursPerWeek = hoursPerWeek
    }

    enum CodingKeys: String, CodingKey { case from, hourlyRate, fixedMonthly, hoursPerWeek }

    /// Mild lezen: de maand is verplicht, een veld dat geen (eindig, niet-negatief) getal is blijft leeg (het volgt dan het loon van
    /// daarvoor). Een wijziging zonder leesbare maand wordt door de lijst overgeslagen (`LossyBox`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(YearMonth.self, forKey: .from)
        hourlyRate = SalaryChange.clean(try? c.decodeIfPresent(Double.self, forKey: .hourlyRate))
        fixedMonthly = SalaryChange.clean(try? c.decodeIfPresent(Double.self, forKey: .fixedMonthly))
        hoursPerWeek = SalaryChange.clean(try? c.decodeIfPresent(Double.self, forKey: .hoursPerWeek))
    }

    /// Elk veld alleen als het is ingevuld en een eindig getal is (de JSON-encoder weigert `NaN` en oneindig).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from)
        if let hourlyRate, hourlyRate.isFinite { try c.encode(hourlyRate, forKey: .hourlyRate) }
        if let fixedMonthly, fixedMonthly.isFinite { try c.encode(fixedMonthly, forKey: .fixedMonthly) }
        if let hoursPerWeek, hoursPerWeek.isFinite { try c.encode(hoursPerWeek, forKey: .hoursPerWeek) }
    }

    /// Verandert deze wijziging niets (geen enkel veld ingevuld)?
    var isEmpty: Bool { hourlyRate == nil && fixedMonthly == nil && hoursPerWeek == nil }

    /// Een bedrag of aantal uren dat telt: eindig en niet negatief. Alles anders is "niet ingevuld".
    static func clean(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

extension FinanceData {
    /// De salarisinstellingen zoals ze gelden voor de uitbetalingen van `month`: `salary` met alle wijzigingen vanaf die maand of
    /// eerder erover (op volgorde van maand, per veld wint de laatste). Zonder wijzigingen is het `salary` zelf.
    func salarySettings(in month: YearMonth) -> SalarySettings {
        guard !salaryChanges.isEmpty else { return salary }
        var settings = salary
        for change in salaryChanges where change.from <= month {
            if let value = change.hourlyRate { settings.hourlyRate = value }
            if let value = change.fixedMonthly { settings.fixedMonthly = value }
            if let value = change.hoursPerWeek { settings.hoursPerWeek = value }
        }
        return settings
    }

    /// De salarisinstellingen voor een uitbetaling op `day`: die van de maand waarin ze op je rekening komt. DÉ plek waar die keuze
    /// staat (zie het begin van dit bestand): de uitbetalingen, ook die uit de agenda (`workReport(forPayoutOn:asOf:)`), rekenen
    /// hiermee het uurloon.
    func salarySettings(forPayoutOn day: CalendarDay) -> SalarySettings {
        salarySettings(in: day.yearMonth)
    }

    /// De instellingen na de laatste wijziging, voor een beginwaarde of een tekst waar geen maand bij is. Zonder wijzigingen `salary`.
    var latestSalarySettings: SalarySettings {
        guard let last = salaryChanges.last else { return salary }
        return salarySettings(in: last.from)
    }

    /// De wijziging die voor `month` het laatst is ingegaan (de rij "Nu" in de lijst). nil als er (nog) geen is.
    func salaryChange(effectiveIn month: YearMonth) -> SalaryChange? {
        salaryChanges.last { $0.from <= month }
    }

    /// De wijziging die precies in `month` ingaat.
    func salaryChange(startingIn month: YearMonth) -> SalaryChange? {
        salaryChanges.first { $0.from == month }
    }

    // MARK: Wijzigen

    /// Zet een wijziging in de lijst: een wijziging van dezelfde maand wordt vervangen en de lijst blijft op maand gesorteerd. Een
    /// wijziging zonder ingevulde velden haalt die van die maand weg. Onzinnige bedragen (negatief, geen getal) worden niet bewaard.
    mutating func setSalaryChange(_ change: SalaryChange) {
        var clean = change
        clean.hourlyRate = SalaryChange.clean(change.hourlyRate)
        clean.fixedMonthly = SalaryChange.clean(change.fixedMonthly)
        clean.hoursPerWeek = SalaryChange.clean(change.hoursPerWeek)
        var list = salaryChanges
        list.removeAll { $0.from == clean.from }
        if !clean.isEmpty { list.append(clean) }
        list.sort { $0.from < $1.from }
        salaryChanges = list
    }

    /// Haalt de wijziging die in `month` ingaat weg: die maand rekent weer met het loon van daarvoor.
    mutating func removeSalaryChange(from month: YearMonth) {
        guard salaryChanges.contains(where: { $0.from == month }) else { return }
        salaryChanges.removeAll { $0.from == month }
    }

    /// Viel er in een maand vóór `current` (vanaf de startmaand) een salaris? Dan moet een nieuw loon die maanden met rust laten.
    func hasSalary(before current: YearMonth) -> Bool {
        guard startMonth < current else { return false }
        let stored = storedPlans
        var month = startMonth
        var count = 0
        while month < current && count < 1_200 {
            if salaryCents(in: month, plan: plan(for: month, using: stored)) != 0 { return true }
            month = month.adding(1)
            count += 1
        }
        return false
    }

    /// Wijzigt het loon vanaf de lopende maand `current`: de maanden ervoor houden hun loon, zonder dat er iets wordt vastgelegd
    /// (anders dan `SalaryScheduleEdit.edit`, dat voor het schema blijft bestaan). Alleen de meegegeven velden veranderen. Is er
    /// niets om te beschermen (er is nog geen wijziging en er viel in de maanden ervoor geen salaris), dan wordt het loon zelf
    /// aangepast, zoals vroeger: wie zijn salaris voor het eerst invult krijgt zo geen wijziging in de lijst.
    mutating func setWage(current: YearMonth, hourlyRate: Double? = nil, fixedMonthly: Double? = nil, hoursPerWeek: Double? = nil) {
        if salaryChanges.isEmpty, !hasSalary(before: current) {
            if let hourlyRate { salary.hourlyRate = hourlyRate }
            if let fixedMonthly { salary.fixedMonthly = fixedMonthly }
            if let hoursPerWeek { salary.hoursPerWeek = hoursPerWeek }
            return
        }
        var change = salaryChange(startingIn: current) ?? SalaryChange(from: current)
        if let hourlyRate { change.hourlyRate = hourlyRate }
        if let fixedMonthly { change.fixedMonthly = fixedMonthly }
        if let hoursPerWeek { change.hoursPerWeek = hoursPerWeek }
        setSalaryChange(change)
    }
}

/// Leest één element van een lijst of niets, zodat één onleesbaar element de rest van de lijst niet meeneemt.
struct LossyBox<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
