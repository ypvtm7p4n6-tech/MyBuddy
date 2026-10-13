import Foundation

// MARK: - Terugkerende regels als reeks
//
// Een terugkerende uitgave of extra inkomst (`MoneyLine.isRecurring`) is een REEKS: alle maanden delen een stabiel
// reeks-id (`MoneyLine.seriesID`). De regel van een maand staat in het maandplan; wat een maand niet zelf heeft, komt uit
// de reeks.
//
// Waarom dit model (de oude fout): een maand die was vastgelegd (opgeslagen) kreeg alleen wat in zijn eigen plan stond,
// en een maand die niet was vastgelegd kreeg de terugkerende regels van het laatst opgeslagen plan ervoor. Voegde je
// dus een terugkerende regel toe terwijl een latere maand al was vastgelegd of bewerkt, dan ontbrak hij daar en in alle
// maanden erna. Afwezigheid betekende bovendien twee dingen (verwijderd of nooit doorgegeven), dus de regel kon niet
// veilig terugkomen.
//
// Regels van het model:
//
// 1. Eén bron van waarheid: `FinanceData.plan(for:)` en alles wat plek voor plek rekent (maandcijfers, de dagboekhouding,
//    de spaarpotten, de projectie) halen de regels van een maand uit `SeriesIndex.completed`.
// 2. Een maand heeft de regels die in zijn plan staan (opgeslagen) plus elke reeks die in die maand loopt maar daar niet
//    staat. Zo'n reeks begint in zijn eerste maand, loopt door tot hij is gestopt, en neemt de laatste regel van de reeks
//    vóór de maand over. Het id van zo'n afgeleide regel is `MoneyLine.seriesLineID(reeks, maand)`: altijd hetzelfde.
// 3. Afwezigheid is niet meer dubbelzinnig: een maand overslaan zet het reeks-id in `MonthPlan.skippedSeries`; stoppen
//    vanaf een maand zet het in `MonthPlan.endedSeries` (de "grafsteen"). Zonder zo'n teken komt de regel gewoon terug.
// 4. "Alleen deze maand" bewerken geeft de regel `isException`: zo'n regel bepaalt de volgende maanden niet. "Deze en alle
//    volgende maanden" past de regel van die maand en de al opgeslagen latere regels van de reeks aan.
// 5. Oude data (regels zonder `seriesID`): de reeks wordt afgeleid uit de keten van afgeleide id's
//    (`line|<vorig id>|<maand>`), zoals de oude motor ze maakte. `migrateRecurringSeries()` schrijft die afleiding weg
//    (gebeurt in `materialize`); zonder migratie geeft de afleiding hetzelfde antwoord.

/// Reikwijdte van een bewerking of verwijdering van een terugkerende regel.
enum SeriesScope: String, Codable, CaseIterable, Identifiable {
    /// Alleen deze maand: de reeks loopt daarna gewoon door.
    case thisMonth
    /// Deze en alle volgende maanden.
    case thisAndFollowing

    var id: String { rawValue }
    var title: String { self == .thisMonth ? "Alleen deze maand" : "Deze en alle volgende maanden" }
}

/// Wat de UI wil weten over de reeks waar een regel bij hoort.
struct SeriesInfo: Equatable {
    var seriesID: UUID
    var kind: FinanceData.LineKind
    /// De eerste maand van de reeks.
    var firstMonth: YearMonth
    /// De laatste maand waarin de reeks nog loopt; nil als hij onbeperkt doorloopt.
    var lastMonth: YearMonth?
    /// Maanden waarin de reeks is overgeslagen (alleen die uit het opgeslagen plan).
    var skippedMonths: [YearMonth]
    /// De regel in de gevraagde maand wijkt af van de reeks ("alleen deze maand" bewerkt).
    var isException: Bool
    /// De laatste regel van de reeks (naam, bedrag, dag), zoals de volgende maand hem overneemt.
    var latest: MoneyLine

    var isOpenEnded: Bool { lastMonth == nil }
}

extension MoneyLine {
    /// Het id van de regel die een reeks in `month` heeft als hij daar niet is opgeslagen. Altijd hetzelfde id voor
    /// dezelfde reeks en maand, op elk apparaat. (Dezelfde afleiding als de oude `line|<id>|<maand>`; bij de eerste
    /// maand na de beginregel is het dus ook hetzelfde id als vroeger.)
    static func seriesLineID(_ series: UUID, in month: YearMonth) -> UUID {
        StableID.Prefix("line|\(series.uuidString)|").uuid(addingKeyOf: month)
    }
}

// MARK: - Index van alle reeksen

/// Alle opgeslagen regels van terugkerende reeksen, per reeks gesorteerd op maand. Hiermee is voor elke maand te bepalen
/// welke regels een reeks daar heeft.
struct SeriesIndex {
    /// Een regel van een reeks zoals die in een opgeslagen maandplan staat.
    struct Occurrence {
        var month: YearMonth
        /// Plek in de lijst van die maand (voor een vaste volgorde).
        var position: Int
        var line: MoneyLine
    }

    struct Series {
        var id: UUID
        /// Oplopend op maand en plek.
        var occurrences: [Occurrence] = []
        /// De eerste maand waarin de reeks niet meer loopt (de "grafsteen"); nil = loopt door.
        var endedFrom: YearMonth?
        var skipped: [YearMonth] = []

        var firstMonth: YearMonth { occurrences[0].month }

        /// De regel die `month` van de reeks overneemt: de laatste regel vóór `month` die niet "alleen die maand" afwijkt;
        /// is er alleen zo'n afwijking, dan die. nil als de reeks nog niet begonnen is.
        func template(before month: YearMonth) -> Occurrence? {
            var lo = 0
            var hi = occurrences.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if occurrences[mid].month < month { lo = mid + 1 } else { hi = mid }
            }
            guard lo > 0 else { return nil }
            var i = lo - 1
            while i >= 0 {
                if !occurrences[i].line.isException { return occurrences[i] }
                i -= 1
            }
            return occurrences[lo - 1]
        }

        /// Is er vóór `month` een opgeslagen regel die de volgende maanden bepaalt?
        func hasTemplate(before month: YearMonth) -> Bool {
            occurrences.contains { $0.month < month && !$0.line.isException }
        }

        /// De opgeslagen regels van de reeks in `month`.
        func occurrences(in month: YearMonth) -> [Occurrence] {
            occurrences.filter { $0.month == month }
        }

        /// Loopt de reeks in `month` (begonnen en niet gestopt)?
        func isActive(in month: YearMonth) -> Bool {
            guard let first = occurrences.first, first.month <= month else { return false }
            if let e = endedFrom, month >= e { return false }
            return true
        }
    }

    private(set) var income: [UUID: Series] = [:]
    private(set) var expense: [UUID: Series] = [:]

    var isEmpty: Bool { income.isEmpty && expense.isEmpty }

    func series(_ id: UUID, income isIncome: Bool) -> Series? {
        isIncome ? income[id] : expense[id]
    }

    /// Bouwt de index uit de maandplannen, oplopend op maand. Regels van oude data zonder reeks-id krijgen hier hun reeks
    /// (`normalize`): de regel waarvan het id de afgeleide van een regel in het vorige opgeslagen plan is, hoort bij
    /// die reeks, anders begint een nieuwe reeks met het id van de regel zelf.
    /// `plans` wordt daarbij aangevuld met de afgeleide reeks-id's; `markers` zijn de tekens (overgeslagen, gestopt).
    fileprivate init(sorted plans: inout [(month: YearMonth, plan: MonthPlan)]) {
        var previousIncome: [MoneyLine] = []
        var previousExpense: [MoneyLine] = []
        for index in plans.indices {
            let month = plans[index].month
            SeriesIndex.link(&plans[index].plan.extraIncome, previous: previousIncome, month: month)
            SeriesIndex.link(&plans[index].plan.expenses, previous: previousExpense, month: month)
            let plan = plans[index].plan
            for (i, line) in plan.extraIncome.enumerated() where line.isRecurring {
                if let sid = line.seriesID {
                    income[sid, default: Series(id: sid)].occurrences.append(Occurrence(month: month, position: i, line: line))
                }
            }
            for (i, line) in plan.expenses.enumerated() where line.isRecurring {
                if let sid = line.seriesID {
                    expense[sid, default: Series(id: sid)].occurrences.append(Occurrence(month: month, position: i, line: line))
                }
            }
            for sid in plan.endedSeries {
                if income[sid] != nil, income[sid]!.endedFrom == nil { income[sid]!.endedFrom = month }
                if expense[sid] != nil, expense[sid]!.endedFrom == nil { expense[sid]!.endedFrom = month }
            }
            for sid in plan.skippedSeries {
                if income[sid] != nil { income[sid]!.skipped.append(month) }
                if expense[sid] != nil { expense[sid]!.skipped.append(month) }
            }
            // Alleen terugkerende regels kunnen in de volgende maand worden afgeleid.
            previousIncome = plan.extraIncome.filter { $0.isRecurring }
            previousExpense = plan.expenses.filter { $0.isRecurring }
        }
    }

    /// Geeft elke terugkerende regel zonder reeks-id zijn reeks (zie `init(sorted:)`).
    private static func link(_ lines: inout [MoneyLine], previous: [MoneyLine], month: YearMonth) {
        guard lines.contains(where: { $0.isRecurring && $0.seriesID == nil }) else { return }
        var derived: [UUID: UUID] = [:]
        for c in previous {
            guard let sid = c.seriesID else { continue }
            derived[MoneyLine.seriesLineID(c.id, in: month)] = sid
        }
        for i in lines.indices where lines[i].isRecurring && lines[i].seriesID == nil {
            lines[i].seriesID = derived[lines[i].id] ?? lines[i].id
        }
    }

    // MARK: Een maand aanvullen

    /// De regels van `month`: de opgeslagen regels `explicit`, aangevuld met elke reeks die in die maand loopt maar niet
    /// in `explicit` staat en niet is overgeslagen. `skipped` zijn de reeksen die in `month` zijn overgeslagen.
    ///
    /// Zonder `deriveIDs` houden de aangevulde regels het id van hun voorganger (sneller; voor wie alleen de bedragen
    /// nodig heeft).
    func completed(_ explicit: [MoneyLine], income isIncome: Bool, in month: YearMonth, skipped: [UUID] = [],
                   deriveIDs: Bool = true) -> [MoneyLine] {
        let all = isIncome ? income : expense
        guard !all.isEmpty else { return explicit }
        var present = Set<UUID>()
        for line in explicit where line.isRecurring {
            if let sid = line.seriesID { present.insert(sid) }
        }
        var extra: [(month: Int, position: Int, id: String, line: MoneyLine)] = []
        for (sid, series) in all where !present.contains(sid) {
            if !skipped.isEmpty, skipped.contains(sid) { continue }
            if let e = series.endedFrom, month >= e { continue }
            guard let template = series.template(before: month) else { continue }
            var line = template.line
            if deriveIDs { line.id = MoneyLine.seriesLineID(sid, in: month) }
            line.seriesID = sid
            line.isRecurring = true
            line.isException = false
            extra.append((template.month.index, template.position, sid.uuidString, line))
        }
        guard !extra.isEmpty else { return explicit }
        extra.sort { a, b in
            if a.month != b.month { return a.month < b.month }
            if a.position != b.position { return a.position < b.position }
            return a.id < b.id
        }
        return explicit + extra.map { $0.line }
    }
}

// MARK: - Opgeslagen plannen

/// De opgeslagen maandplannen oplopend op maand, met de index van de reeksen. Voor lussen over veel maanden: zo hoeft
/// het laatste plan vóór een maand en de reeksen niet bij elke maand opnieuw te worden gezocht. De regels zijn
/// genormaliseerd: elke terugkerende regel heeft een reeks-id.
struct StoredPlans {
    private var keys: [YearMonth] = []
    private var plans: [MonthPlan] = []
    /// De reeksen in de opgeslagen plannen.
    let series: SeriesIndex

    init(_ months: [String: MonthPlan]) {
        // Eerst alleen de sleutels sorteren; de plannen (groot) worden pas daarna op volgorde opgehaald.
        var list: [(month: YearMonth, key: String)] = []
        list.reserveCapacity(months.count)
        for key in months.keys {
            if let m = YearMonth(key: key) { list.append((m, key)) }
        }
        list.sort { $0.month < $1.month }
        var sorted: [(month: YearMonth, plan: MonthPlan)] = []
        sorted.reserveCapacity(list.count)
        for item in list {
            if let plan = months[item.key] { sorted.append((item.month, plan)) }
        }
        series = SeriesIndex(sorted: &sorted)
        keys = sorted.map { $0.month }
        plans = sorted.map { $0.plan }
    }

    /// Het laatst opgeslagen plan vóór `month`.
    func latest(before month: YearMonth) -> MonthPlan? {
        let lo = firstIndex(notBefore: month)
        return lo == 0 ? nil : plans[lo - 1]
    }

    /// Het opgeslagen plan van precies `month` (met reeks-id's op de terugkerende regels).
    func plan(at month: YearMonth) -> MonthPlan? {
        let lo = firstIndex(notBefore: month)
        return lo < keys.count && keys[lo] == month ? plans[lo] : nil
    }

    /// Alle opgeslagen plannen, oplopend op maand.
    var all: [(month: YearMonth, plan: MonthPlan)] {
        zip(keys, plans).map { (month: $0, plan: $1) }
    }

    private func firstIndex(notBefore month: YearMonth) -> Int {
        var lo = 0
        var hi = keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if keys[mid] < month { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

/// Tussenopslag van `StoredPlans` bij een `FinanceData`, zodat een reeks aanvragen niet elke keer alle plannen opnieuw
/// doorloopt. Niet opgeslagen en altijd "gelijk" (het zijn afgeleide gegevens). `FinanceData.months` zet bij elke
/// wijziging een nieuwe, lege opslag neer; kopieën delen de opslag alleen zolang hun plannen gelijk zijn.
struct DerivedPlans: Equatable {
    final class Box {
        let lock = NSLock()
        var stored: StoredPlans?
    }

    let box = Box()

    static func == (lhs: DerivedPlans, rhs: DerivedPlans) -> Bool { true }
}

extension FinanceData {
    /// De opgeslagen plannen met hun reeksen, uit de tussenopslag (één keer gebouwd per stand van `months`).
    var storedPlans: StoredPlans {
        let box = derivedPlans.box
        box.lock.lock()
        if let known = box.stored {
            box.lock.unlock()
            return known
        }
        box.lock.unlock()
        let built = StoredPlans(months)
        box.lock.lock()
        box.stored = built
        box.lock.unlock()
        return built
    }
}

// MARK: - Opzoeken en vragen aan de reeks

extension FinanceData {
    /// Hoort de regel bij een reeks, en tot wanneer loopt die? nil voor een eenmalige regel (of een regel die niet te
    /// vinden is). `line` mag een regel uit `plan(for: month)` zijn.
    func seriesInfo(of line: MoneyLine, in month: YearMonth) -> SeriesInfo? {
        guard line.isRecurring else { return nil }
        let stored = storedPlans
        let resolved = plan(for: month, using: stored)
        // De regel zoals de maand hem heeft: dat geeft de reeks ook voor een regel uit oude data (zonder reeks-id).
        let inMonth = (resolved.extraIncome + resolved.expenses).first { $0.id == line.id }
        guard let sid = inMonth?.seriesID ?? line.seriesID else { return nil }
        let isIncome = stored.series.income[sid] != nil
        guard let series = stored.series.series(sid, income: isIncome) else { return nil }
        return Self.info(of: series, income: isIncome, isException: inMonth?.isException ?? line.isException)
    }

    /// Alle reeksen van één soort, oudste eerst: voor een lijst "Terugkerend".
    func recurringSeries(kind: LineKind) -> [SeriesInfo] {
        let stored = storedPlans
        let isIncome = kind == .income
        let all = isIncome ? stored.series.income : stored.series.expense
        let sorted = all.values.sorted { a, b in
            if a.firstMonth != b.firstMonth { return a.firstMonth < b.firstMonth }
            return a.id.uuidString < b.id.uuidString
        }
        return sorted.map { Self.info(of: $0, income: isIncome, isException: false) }
    }

    private static func info(of series: SeriesIndex.Series, income: Bool, isException: Bool) -> SeriesInfo {
        let latest = series.occurrences.last { !$0.line.isException } ?? series.occurrences[series.occurrences.count - 1]
        return SeriesInfo(seriesID: series.id, kind: income ? .income : .expense, firstMonth: series.firstMonth,
                          lastMonth: series.endedFrom.map { $0.adding(-1) },
                          skippedMonths: series.skipped.sorted(), isException: isException, latest: latest.line)
    }

    /// Schrijft de afgeleide reeks-id's van oude data weg in de opgeslagen plannen. Geeft het aantal plannen dat is
    /// aangepast. Herhaald aanroepen verandert niets meer. De rekenmotor geeft ook zonder deze stap hetzelfde antwoord
    /// (de reeks wordt dan bij het lezen afgeleid), maar na het wegschrijven is dat sneller en ligt het vast.
    @discardableResult
    mutating func migrateRecurringSeries() -> Int {
        let stored = storedPlans
        var changed = 0
        for item in stored.all {
            let key = item.month.key
            if let old = months[key], old != item.plan {
                months[key] = item.plan
                changed += 1
            }
        }
        return changed
    }

    // MARK: Plannen aanvullen

    /// De regels van een maand op de plek van `plan`: de opgeslagen regels plus de reeksen die daar lopen.
    func completedPlan(_ base: MonthPlan, in month: YearMonth, using stored: StoredPlans, deriveIDs: Bool = true) -> MonthPlan {
        var plan = base
        plan.extraIncome = stored.series.completed(base.extraIncome, income: true, in: month, skipped: base.skippedSeries,
                                                   deriveIDs: deriveIDs)
        plan.expenses = stored.series.completed(base.expenses, income: false, in: month, skipped: base.skippedSeries,
                                                deriveIDs: deriveIDs)
        return plan
    }

    // MARK: Bewerken

    /// Voegt een terugkerende regel toe vanaf `month`: hij komt elke volgende maand terug op zijn eigen dag, ook in maanden
    /// die al zijn opgeslagen. Geeft de regel zoals hij is opgeslagen (met reeks-id).
    @discardableResult
    mutating func addRecurringLine(_ line: MoneyLine, kind: LineKind, in month: YearMonth) -> MoneyLine {
        var new = line
        new.isRecurring = true
        new.isException = false
        new.seriesID = line.seriesID ?? line.id
        updateLine(new, kind: kind, in: month, scope: .thisAndFollowing)
        return new
    }

    /// Slaat een regel op in `month`: een nieuwe regel wordt toegevoegd, een bestaande (zelfde id) vervangen.
    ///
    /// - Eenmalige regel: alleen deze maand, `scope` doet er niet toe.
    /// - Terugkerende regel, `.thisAndFollowing`: de regel van deze maand wordt de regel van de reeks vanaf nu. Wat er
    ///   anders aan is dan voorheen (naam, bedrag, dag, soort, potdelen) gaat ook in de al opgeslagen latere maanden mee;
    ///   maanden die niet zijn opgeslagen volgen vanzelf.
    /// - Terugkerende regel, `.thisMonth`: alleen deze maand wijkt af; de reeks gaat er daarna gewoon mee door.
    /// - Een terugkerende regel die niet meer terugkerend is: `.thisAndFollowing` stopt de reeks vanaf deze maand (deze
    ///   regel blijft als eenmalige staan), `.thisMonth` slaat alleen deze maand van de reeks over.
    mutating func updateLine(_ line: MoneyLine, kind: LineKind, in month: YearMonth, scope: SeriesScope = .thisAndFollowing) {
        let stored = storedPlans
        let current = plan(for: month, using: stored)
        let lines = kind == .income ? current.extraIncome : current.expenses
        let existing = lines.first { $0.id == line.id }
        let oldSeries: UUID? = (existing?.isRecurring == true) ? existing?.seriesID : nil
        let isIncome = kind == .income
        var new = line

        // Niet (meer) terugkerend.
        guard new.isRecurring else {
            new.seriesID = nil
            new.isException = false
            if let sid = oldSeries, let old = existing {
                switch scope {
                case .thisAndFollowing:
                    stopSeries(sid, from: month, income: isIncome, using: stored)
                case .thisMonth:
                    keepTemplate(of: old, series: sid, income: isIncome, skipping: month, using: stored)
                }
            }
            writeLine(new, kind: kind, in: month)
            return
        }

        let sid = new.seriesID ?? oldSeries ?? new.id
        new.seriesID = sid
        guard let old = existing, oldSeries == sid else {
            // Een nieuwe reeks (of een regel die nog geen reeks had): begint in deze maand.
            new.isException = false
            writeLine(new, kind: kind, in: month)
            return
        }

        switch scope {
        case .thisAndFollowing:
            new.isException = false
            writeLine(new, kind: kind, in: month)
            propagate(from: old, to: new, series: sid, income: isIncome, after: month, using: stored)
        case .thisMonth:
            // Was deze regel de enige die de volgende maanden bepaalde, dan houdt de volgende maand de oude regel.
            let isAnchor = !old.isException && stored.plan(at: month).map { plan in
                (isIncome ? plan.extraIncome : plan.expenses).contains { $0.id == old.id }
            } == true
            let needsAnchor = isAnchor && stored.series.series(sid, income: isIncome)?.hasTemplate(before: month) == false
            new.isException = true
            writeLine(new, kind: kind, in: month)
            if needsAnchor { placeAnchor(old, series: sid, income: isIncome, after: month, using: stored) }
        }
    }

    /// Haalt een regel weg uit `month`.
    ///
    /// - Eenmalige regel: weg uit deze maand.
    /// - Terugkerende regel, `.thisMonth`: de reeks wordt in deze maand overgeslagen en loopt daarna door.
    /// - Terugkerende regel, `.thisAndFollowing`: de reeks stopt vanaf deze maand (een "grafsteen": hij komt niet meer
    ///   terug, ook niet in maanden die al waren opgeslagen).
    mutating func removeLine(id: UUID, kind: LineKind, in month: YearMonth, scope: SeriesScope = .thisAndFollowing) {
        let stored = storedPlans
        let current = plan(for: month, using: stored)
        let lines = kind == .income ? current.extraIncome : current.expenses
        let isIncome = kind == .income
        guard let line = lines.first(where: { $0.id == id }) else {
            // Niet te vinden: haal een eventuele opgeslagen regel met dit id toch weg.
            deleteStoredLine(id: id, kind: kind, in: month)
            return
        }
        guard line.isRecurring, let sid = line.seriesID else {
            deleteStoredLine(id: id, kind: kind, in: month)
            return
        }
        switch scope {
        case .thisAndFollowing:
            stopSeries(sid, from: month, income: isIncome, using: stored)
        case .thisMonth:
            keepTemplate(of: line, series: sid, income: isIncome, skipping: month, using: stored)
            deleteStoredLine(id: id, kind: kind, in: month)
        }
    }

    /// Zet een overgeslagen maand van een reeks terug: de regel is er in die maand weer.
    mutating func restoreSkippedLine(seriesID: UUID, in month: YearMonth) {
        guard var plan = months[month.key], plan.skippedSeries.contains(seriesID) else { return }
        plan.skippedSeries.removeAll { $0 == seriesID }
        months[month.key] = plan
    }

    // MARK: Bouwstenen

    /// Zet `line` in de lijst van `month` (vervangt dezelfde id, anders achteraan) en legt de maand vast.
    private mutating func writeLine(_ line: MoneyLine, kind: LineKind, in month: YearMonth) {
        editPlan(month) { plan in
            switch kind {
            case .income:
                if let i = plan.extraIncome.firstIndex(where: { $0.id == line.id }) { plan.extraIncome[i] = line } else { plan.extraIncome.append(line) }
            case .expense:
                if let i = plan.expenses.firstIndex(where: { $0.id == line.id }) { plan.expenses[i] = line } else { plan.expenses.append(line) }
            }
        }
    }

    /// Haalt een regel uit de lijst van `month`. Een regel van een reeks krijgt daarbij het teken "overgeslagen"
    /// (zie `editPlan`).
    private mutating func deleteStoredLine(id: UUID, kind: LineKind, in month: YearMonth) {
        editPlan(month) { plan in
            switch kind {
            case .income: plan.extraIncome.removeAll { $0.id == id }
            case .expense: plan.expenses.removeAll { $0.id == id }
            }
        }
    }

    /// Past de al opgeslagen latere regels van de reeks aan met wat er in `new` anders is dan in `old`.
    private mutating func propagate(from old: MoneyLine, to new: MoneyLine, series sid: UUID, income isIncome: Bool,
                                    after month: YearMonth, using stored: StoredPlans) {
        guard let series = stored.series.series(sid, income: isIncome) else { return }
        let changeName = old.name != new.name
        let changeAmount = old.amount != new.amount
        let changeKind = old.kind != new.kind
        let changeDay = old.day != new.day
        let changeShares = old.potShares != new.potShares
        guard changeName || changeAmount || changeKind || changeDay || changeShares else { return }
        var later: [String: Set<UUID>] = [:]
        for occ in series.occurrences where occ.month > month && !occ.line.isException {
            later[occ.month.key, default: []].insert(occ.line.id)
        }
        for (key, ids) in later {
            guard var plan = months[key] else { continue }
            func apply(_ lines: inout [MoneyLine]) {
                for i in lines.indices where ids.contains(lines[i].id) {
                    if changeName { lines[i].name = new.name }
                    if changeAmount { lines[i].amount = new.amount }
                    if changeKind { lines[i].kind = new.kind }
                    if changeDay { lines[i].day = new.day }
                    if changeShares { lines[i].potShares = new.potShares }
                }
            }
            if isIncome { apply(&plan.extraIncome) } else { apply(&plan.expenses) }
            months[key] = plan
        }
    }

    /// Stopt de reeks vanaf `month`: de regels van de reeks in die en alle latere opgeslagen maanden verdwijnen, en de
    /// maand krijgt het teken "gestopt". Staat er vóór `month` niets van de reeks, dan verdwijnt hij helemaal.
    private mutating func stopSeries(_ sid: UUID, from month: YearMonth, income isIncome: Bool, using stored: StoredPlans) {
        guard let series = stored.series.series(sid, income: isIncome) else { return }
        var remove: [String: Set<UUID>] = [:]
        for occ in series.occurrences where occ.month >= month {
            remove[occ.month.key, default: []].insert(occ.line.id)
        }
        for (key, ids) in remove {
            guard var plan = months[key] else { continue }
            if isIncome { plan.extraIncome.removeAll { ids.contains($0.id) } } else { plan.expenses.removeAll { ids.contains($0.id) } }
            months[key] = plan
        }
        // Tekens van de reeks vanaf deze maand horen bij een reeks die er niet meer is.
        for key in Array(months.keys) {
            guard let m = YearMonth(key: key), m >= month, var plan = months[key] else { continue }
            let hadSkip = plan.skippedSeries.contains(sid)
            let hadEnd = plan.endedSeries.contains(sid)
            guard hadSkip || hadEnd else { continue }
            plan.skippedSeries.removeAll { $0 == sid }
            plan.endedSeries.removeAll { $0 == sid }
            months[key] = plan
        }
        let hasEarlier = series.occurrences.contains { $0.month < month }
        if hasEarlier {
            var plan = months[month.key] ?? MonthPlan()
            plan.endedSeries = FinanceData.insertingMarker(sid, into: plan.endedSeries)
            months[month.key] = plan
        }
    }

    /// Slaat `month` over voor de reeks. Bepaalde `line` de volgende maanden (de enige opgeslagen regel van de reeks),
    /// dan krijgt de eerstvolgende maand waarin de reeks loopt die regel, zodat de reeks niet verdwijnt.
    private mutating func keepTemplate(of line: MoneyLine, series sid: UUID, income isIncome: Bool, skipping month: YearMonth,
                                       using stored: StoredPlans) {
        guard let series = stored.series.series(sid, income: isIncome) else { return }
        let isStoredHere = series.occurrences(in: month).contains { $0.line.id == line.id }
        if isStoredHere, !line.isException, !series.hasTemplate(before: month) {
            placeAnchor(line, series: sid, income: isIncome, after: month, using: stored)
        }
        var plan = months[month.key] ?? MonthPlan()
        plan.skippedSeries = FinanceData.insertingMarker(sid, into: plan.skippedSeries)
        months[month.key] = plan
    }

    /// Zet `template` als opgeslagen regel van de reeks in de eerste maand na `month` waarin de reeks loopt en nog geen
    /// regel heeft. Zo behoudt de reeks een regel die de volgende maanden bepaalt.
    private mutating func placeAnchor(_ template: MoneyLine, series sid: UUID, income isIncome: Bool, after month: YearMonth,
                                      using stored: StoredPlans) {
        guard let series = stored.series.series(sid, income: isIncome) else { return }
        var m = month.adding(1)
        for _ in 0..<1_200 {
            if let e = series.endedFrom, m >= e { return }
            let skippedHere = stored.plan(at: m)?.skippedSeries.contains(sid) == true
            let here = series.occurrences(in: m)
            if skippedHere || (!here.isEmpty && here.allSatisfy { $0.line.isException }) {
                m = m.adding(1)
                continue
            }
            if !here.isEmpty { return }   // er staat al een regel die de reeks voortzet
            var anchor = template
            anchor.id = MoneyLine.seriesLineID(sid, in: m)
            anchor.seriesID = sid
            anchor.isRecurring = true
            anchor.isException = false
            var plan = months[m.key] ?? MonthPlan()
            if isIncome { plan.extraIncome.append(anchor) } else { plan.expenses.append(anchor) }
            months[m.key] = plan
            return
        }
    }

    /// Voegt een reeks-id toe aan een lijst met tekens (zonder dubbelen, vaste volgorde).
    static func insertingMarker(_ id: UUID, into list: [UUID]) -> [UUID] {
        guard !list.contains(id) else { return list }
        return (list + [id]).sorted { $0.uuidString < $1.uuidString }
    }
}

// MARK: - Na een bewerking van een maandplan

extension FinanceData {
    /// Na `editPlan`: geeft nieuwe terugkerende regels een reeks (een regel die de bewerking al kende houdt zijn reeks),
    /// maakt eenmalige regels los van elke reeks, en zet het teken "overgeslagen" voor elke reeks die de bewerking uit de
    /// maand haalde. Zo is een verwijderde regel nooit te verwarren met een regel die nog niet was doorgegeven.
    static func settleSeries(in plan: inout MonthPlan, before: MonthPlan) {
        var known: [UUID: UUID] = [:]   // regel-id -> reeks, zoals de maand ze had
        var knownSeries = Set<UUID>()
        for line in before.extraIncome + before.expenses where line.isRecurring {
            if let sid = line.seriesID {
                known[line.id] = sid
                knownSeries.insert(sid)
            }
        }
        func settle(_ lines: inout [MoneyLine]) -> Set<UUID> {
            var present = Set<UUID>()
            for i in lines.indices {
                if lines[i].isRecurring {
                    let sid = lines[i].seriesID ?? known[lines[i].id] ?? lines[i].id
                    lines[i].seriesID = sid
                    present.insert(sid)
                } else {
                    lines[i].seriesID = nil
                    lines[i].isException = false
                }
            }
            return present
        }
        var now = settle(&plan.extraIncome)
        now.formUnion(settle(&plan.expenses))
        // Een reeks die in deze maand een regel heeft, is niet overgeslagen en niet voor deze maand gestopt.
        var skipped = plan.skippedSeries.filter { !now.contains($0) }
        plan.endedSeries.removeAll { now.contains($0) }
        for sid in knownSeries.subtracting(now) where !plan.endedSeries.contains(sid) && !skipped.contains(sid) {
            skipped.append(sid)
        }
        plan.skippedSeries = skipped.sorted { $0.uuidString < $1.uuidString }
    }
}
