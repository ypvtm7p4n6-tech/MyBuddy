import Foundation

/// Soort gebeurtenis op een dag.
enum DayEventKind: String, Codable {
    case salary, income, expense, toPot, toHolding, interest, bankEntry
}

/// Eén gebeurtenis op een dag: geld dat binnenkomt, weggaat of wordt overgeschreven.
struct DayEvent: Identifiable, Equatable {
    var id: String
    /// Op de dag zelf, 12:00. Alleen handmatige bankboekingen houden hun eigen tijdstip.
    var date: Date
    var day: Int
    var title: String
    var kind: DayEventKind
    /// Effect op de bankrekening (+ erbij, − eraf; 0 voor het potdeel van een uitgave en voor rente).
    var bankAmount: Double
    /// Effect op een spaarpot (0 als geen pot). Bij handmatige stortingen en opnames 0: de pot-boeking
    /// staat al in zijn eigen geschiedenis.
    var potAmount: Double
    var potID: UUID?
    var holdingID: UUID?
    var lineID: UUID?
    /// De dag van deze gebeurtenis ligt na de dag van `asOf` van `dayEvents` (per kalenderdag, niet per tijdstip:
    /// alles op de dag van vandaag geldt als al gebeurd, ook als het voor 12:00 is).
    var isPlanned: Bool
}

/// Eén uitbetaling van het salaris.
struct SalaryPayout: Equatable {
    /// Vast id van deze uitbetaling (hetzelfde op elk apparaat en bij elke berekening): per maand bij het maandelijkse
    /// schema, per datum bij een schema om de zoveel weken of dagen.
    var id: String
    /// Dag van de maand (1...dagen in de maand).
    var day: Int
    var cents: Int
}

/// Het saldo van de bankrekening aan het eind van een dag, met wat er die dag gebeurde.
struct BankDayPoint: Identifiable, Equatable {
    var date: Date
    var balance: Double
    var events: [DayEvent]
    var id: Date { date }
}

extension FinanceData {
    // MARK: Gebeurtenissen

    /// Alle gebeurtenissen van een maand, gesorteerd op datum. `isPlanned` is waar voor alles op een dag na de dag van
    /// `today` (per kalenderdag: de hele dag van vandaag telt als gebeurd).
    /// Maanden vóór de startmaand hebben geen geplande gebeurtenissen.
    func dayEvents(in month: YearMonth, asOf today: Date = Date()) -> [DayEvent] {
        dayEventsByMonth(from: month, to: month, asOf: today)[month] ?? []
    }

    /// De gebeurtenissen van de dag waar `date` in valt.
    func eventsOnDay(_ date: Date, asOf today: Date = Date()) -> [DayEvent] {
        let cal = YearMonth.calendar
        let month = YearMonth(date: date, calendar: cal)
        return dayEvents(in: month, asOf: today).filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    /// Gebeurtenissen die de bankrekening raken: plan en handmatige boekingen (zonder rente, die raakt de bank niet).
    func bankFlowEvents(in month: YearMonth) -> [DayEvent] {
        planEvents(in: month) + bankEntryEvents(in: month)
    }

    /// Gebeurtenissen uit het maandplan: salaris, extra inkomsten, uitgaven, verdeling over potten en beleggingen.
    func planEvents(in month: YearMonth) -> [DayEvent] {
        guard month >= startMonth else { return [] }
        let plan = self.plan(for: month)
        let cal = YearMonth.calendar
        var out: [DayEvent] = []

        func add(id: String, day: Int, title: String, kind: DayEventKind, bank: Int, pot: Int = 0,
                 potID: UUID? = nil, holdingID: UUID? = nil, lineID: UUID? = nil) {
            let d = min(max(day, 1), month.dayCount)
            // Wat vóór de startdag valt bestaat niet (in een gewone maand telt elke dag).
            guard counts(day: d, in: month) else { return }
            out.append(DayEvent(id: id, date: month.date(day: d, calendar: cal), day: d, title: title, kind: kind,
                                bankAmount: CentsMath.value(bank), potAmount: CentsMath.value(pot),
                                potID: potID, holdingID: holdingID, lineID: lineID, isPlanned: false))
        }

        // Elke uitbetaling is een eigen gebeurtenis op haar eigen dag. Het dagboek (`monthLedger`) telt ze allemaal mee;
        // het maakt dus niet uit hoeveel er in een maand zijn.
        for payout in salaryPayouts(in: month, plan: plan) where payout.cents != 0 {
            add(id: payout.id, day: payout.day, title: "Salaris", kind: .salary, bank: payout.cents)
        }

        for line in plan.extraIncome {
            let cents = CentsMath.int(line.amount)
            guard cents != 0 else { continue }
            add(id: "income-\(line.id.uuidString)-\(month.key)", day: incomeDay(of: line, in: month),
                title: line.name.isEmpty ? "Inkomsten" : line.name, kind: .income, bank: cents, lineID: line.id)
        }

        for line in plan.expenses {
            let split = expenseSplit(of: line)
            let day = expenseDay(of: line)
            let name = line.name.isEmpty ? "Uitgave" : line.name
            if split.bankCents != 0 {
                add(id: "expense-\(line.id.uuidString)-\(month.key)", day: day, title: name, kind: .expense,
                    bank: -split.bankCents, lineID: line.id)
            }
            for payment in split.pots {
                let potName = pot(payment.potID)?.name ?? "spaarpot"
                add(id: "expense-\(line.id.uuidString)-\(payment.shareID.uuidString)-\(month.key)", day: day,
                    title: "\(name) (uit \(potName))", kind: .expense, bank: 0, pot: -payment.cents,
                    potID: payment.potID, lineID: line.id)
            }
        }

        // De inleg komt uit DEZELFDE som als de maandcijfers en de spaarpotten (`allocationCents`: een vast bedrag, of een
        // percentage van het inkomen van deze maand). Het inkomen wordt hooguit één keer per maand uitgerekend, en alleen
        // als er een percentage is; een eigen aanroep per pot zou het plan van de maand steeds opnieuw opbouwen.
        let storedPlan = months[month.key]
        var bases: IncomeBases?
        func incomeOfMonth() -> IncomeBases {
            if let known = bases { return known }
            let made = incomeBases(of: plan, in: month)
            bases = made
            return made
        }
        for pot in pots {
            let cents = allocationCents(pot, key: pot.id.uuidString, in: month, storedPlan: storedPlan, basesFor: incomeOfMonth)
            guard cents != 0 else { continue }
            add(id: "toPot-\(pot.id.uuidString)-\(month.key)", day: transferDay(for: pot.id, in: month),
                title: "Naar \(pot.name)", kind: .toPot, bank: -cents, pot: cents, potID: pot.id)
        }
        for holding in holdings {
            let cents = allocationCents(holding, key: holding.id.uuidString, in: month, storedPlan: storedPlan,
                                        basesFor: incomeOfMonth)
            guard cents != 0 else { continue }
            add(id: "toHolding-\(holding.id.uuidString)-\(month.key)", day: transferDay(for: holding.id, in: month),
                title: "Naar \(holding.name)", kind: .toHolding, bank: -cents, holdingID: holding.id)
        }
        return out
    }

    /// De uitbetalingen van het salaris in `month`: dag van de maand, bedrag in hele centen en een vast id per uitbetaling.
    /// Bij het maandelijkse schema is dat één uitbetaling per maand op de salarisdag (id `salary-2026-10`); bij een schema
    /// om de zoveel weken of dagen 0, 1, 2 of meer, elk op zijn eigen dag met het id van die datum (`salary-2026-10-23`).
    /// De som van de bedragen is het salaris in `monthFigures` (`salaryCents(in:plan:)`): dat controleert
    /// `MonthLedger.overviewReconciles`.
    func salaryPayouts(in month: YearMonth, plan: MonthPlan) -> [SalaryPayout] {
        let monthly = salary.isMonthly
        return salaryPayoutCents(in: month, plan: plan).map { payout in
            let id = monthly ? "salary-\(month.key)" : "salary-\(CalendarDay(month: month, day: payout.day).key)"
            return SalaryPayout(id: id, day: payout.day, cents: payout.cents)
        }
    }

    /// Handmatige boekingen op de bankrekening in een maand. Een overboeking naar of van een spaarpot heeft
    /// al een eigen pot-boeking; het pot-effect staat hier daarom op 0.
    func bankEntryEvents(in month: YearMonth) -> [DayEvent] {
        let cal = YearMonth.calendar
        var out: [DayEvent] = []
        for entry in countedBankEntries where YearMonth(date: entry.date, calendar: cal) == month {
            let cents = CentsMath.int(entry.amount)
            guard cents != 0 else { continue }
            out.append(DayEvent(id: "bank-\(entry.id.uuidString)", date: entry.date,
                                day: DayMath.dayNumber(of: entry.date, calendar: cal),
                                title: entry.note.isEmpty ? entry.kind.title : entry.note, kind: .bankEntry,
                                bankAmount: CentsMath.value(cents), potAmount: 0, potID: entry.potID,
                                holdingID: nil, lineID: nil, isPlanned: false))
        }
        return out
    }

    /// Gebeurtenissen van alle maanden `first ... last`, per maand gesorteerd. Rente wordt per pot één keer
    /// berekend: opgeslagen uitbetalingen en verwachte uitbetalingen, nooit dubbel.
    func dayEventsByMonth(from first: YearMonth, to last: YearMonth, asOf today: Date) -> [YearMonth: [DayEvent]] {
        dayEventsByMonth(from: first, to: last, asOf: today, flows: nil)
    }

    /// Zoals `dayEventsByMonth(from:to:asOf:)`. Met `flows` (per pot, t/m `last` berekend met `potFlows`) hoeft de
    /// rente niet nog eens te worden uitgerekend; de dagboekhouding gebruikt dezelfde flows voor de potsaldi.
    func dayEventsByMonth(from first: YearMonth, to last: YearMonth, asOf today: Date,
                          flows given: [UUID: PotFlows]?) -> [YearMonth: [DayEvent]] {
        var result: [YearMonth: [DayEvent]] = [:]
        guard first <= last else { return result }
        let cal = YearMonth.calendar

        var m = first
        var count = 0
        while m <= last && count < 2_400 {
            result[m] = bankFlowEvents(in: m)
            m = m.adding(1)
            count += 1
        }

        // Alleen uitbetalingen binnen de gevraagde maanden worden een gebeurtenis (de rest valt toch buiten `place`).
        let lowerBound = first.firstDay
        let upperBound = last.endExclusive

        func place(_ event: DayEvent) {
            let month = YearMonth(date: event.date, calendar: cal)
            guard month >= first && month <= last else { return }
            result[month, default: []].append(event)
        }

        // Alleen een pot met rente heeft uitbetalingen; de rest hoeft zijn saldoverloop hier niet op te bouwen.
        var flowsByPot = given ?? [:]
        if given == nil {
            let interestPots = pots.filter { InterestRules.isActive($0) }
            if !interestPots.isEmpty { flowsByPot = potFlows(for: interestPots, throughMonth: last) }
        }

        for pot in pots {
            let flows: PotFlows? = InterestRules.isActive(pot) ? (flowsByPot[pot.id] ?? potFlows(pot, throughMonth: last)) : nil
            let managed = flows?.managedIDs ?? []
            if let flows {
                for payment in flows.payments where payment.date >= lowerBound && payment.date < upperBound {
                    place(DayEvent(id: payment.id, date: payment.date, day: DayMath.dayNumber(of: payment.date, calendar: cal),
                                   title: "Rente \(pot.name)", kind: .interest, bankAmount: 0, potAmount: payment.amount,
                                   potID: pot.id, holdingID: nil, lineID: nil, isPlanned: false))
                }
            }
            // Rente-boekingen die niet bij het rooster horen (handmatig of van een eerdere instelling).
            for e in countedPotEntries where e.potID == pot.id && e.kind == .interest && !managed.contains(e.id)
                && e.date >= lowerBound && e.date < upperBound {
                place(DayEvent(id: "potentry-\(e.id.uuidString)", date: e.date, day: DayMath.dayNumber(of: e.date, calendar: cal),
                               title: "Rente \(pot.name)", kind: .interest, bankAmount: 0, potAmount: e.amount,
                               potID: pot.id, holdingID: nil, lineID: nil, isPlanned: false))
            }
        }

        // Per kalenderdag: gepland is alles vanaf het begin van de dag na `today`.
        let planLimit = DayMath.planLimit(for: today, calendar: cal)
        for (month, events) in result {
            var list = events
            for i in list.indices { list[i].isPlanned = list[i].date >= planLimit }
            list.sort(by: FinanceData.eventOrder)
            result[month] = list
        }
        return result
    }

    private static func eventRank(_ kind: DayEventKind) -> Int {
        switch kind {
        case .salary: return 0
        case .income: return 1
        case .bankEntry: return 2
        case .interest: return 3
        case .expense: return 4
        case .toPot: return 5
        case .toHolding: return 6
        }
    }

    private static func eventOrder(_ a: DayEvent, _ b: DayEvent) -> Bool {
        if a.date != b.date { return a.date < b.date }
        let ra = eventRank(a.kind)
        let rb = eventRank(b.kind)
        if ra != rb { return ra < rb }
        if a.title != b.title { return a.title < b.title }
        return a.id < b.id
    }

    // MARK: Saldo per dag

    /// Saldo aan het EIND van die dag. nil zolang er geen saldo bekend is (voor het eerste meetpunt).
    ///
    /// Eén dag kost een berekening van alles vanaf het laatste meetpunt (in een debug-build ongeveer 2 ms, bij jaren
    /// geschiedenis meer). Voor een lijst met een rij per dag: gebruik `monthLedger(_:asOf:)` (alle dagen van een maand in één
    /// keer, tientallen keren sneller) of `bankDailySeries(from:to:asOf:)`, en roep dit niet per dag aan.
    func bankBalance(on date: Date) -> Double? {
        let limit = DayMath.nextDayStart(after: date)
        let timeline = BankTimeline(self, firstLimit: limit, lastLimit: limit, events: { self.bankFlowEvents(in: $0) })
        return timeline.balance(before: limit)
    }

    /// Eén punt per dag van `from` t/m `to` (maximaal 800 dagen), alleen vanaf de eerste dag waarvoor het saldo bekend is.
    func bankDailySeries(from: Date, to: Date, asOf today: Date = Date()) -> [BankDayPoint] {
        let cal = YearMonth.calendar
        let firstDay = cal.startOfDay(for: from)
        let lastWanted = cal.startOfDay(for: to)
        guard lastWanted >= firstDay else { return [] }

        var days: [Date] = []
        var d = firstDay
        while d <= lastWanted && days.count < 800 {
            days.append(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        guard let lastDay = days.last else { return [] }

        let firstLimit = DayMath.nextDayStart(after: firstDay, calendar: cal)
        let lastLimit = DayMath.nextDayStart(after: lastDay, calendar: cal)
        guard let firstMonth = BankTimeline.startMonth(for: self, firstLimit: firstLimit, lastLimit: lastLimit) else { return [] }
        let lastMonth = YearMonth(date: lastDay, calendar: cal)
        let byMonth = dayEventsByMonth(from: firstMonth, to: lastMonth, asOf: today)
        let timeline = BankTimeline(self, firstLimit: firstLimit, lastLimit: lastLimit, events: { byMonth[$0] ?? [] })

        var points: [BankDayPoint] = []
        for day in days {
            let limit = DayMath.nextDayStart(after: day, calendar: cal)
            guard let balance = timeline.balance(before: limit) else { continue }
            let month = YearMonth(date: day, calendar: cal)
            let number = DayMath.dayNumber(of: day, calendar: cal)
            let events = (byMonth[month] ?? []).filter { $0.day == number }
            points.append(BankDayPoint(date: month.date(day: number, calendar: cal), balance: balance, events: events))
        }
        return points
    }

    /// Het laagste dagsaldo van de maand (voor "let op: je gaat onder nul"). Bij gelijke saldi de eerste dag.
    /// nil als er in die maand nog geen saldo bekend is.
    func lowestBankPoint(in month: YearMonth) -> BankDayPoint? {
        let points = bankDailySeries(from: month.firstDay, to: month.date(day: month.dayCount))
        var lowest: BankDayPoint?
        for point in points where lowest == nil || point.balance < lowest!.balance {
            lowest = point
        }
        return lowest
    }
}
