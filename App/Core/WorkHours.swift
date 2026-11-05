import Foundation

// MARK: - Werkuren uit de agenda: instellingen, afgeleide diensten en de uren van een uitbetaling
//
// Foundation-only (docs/work/plan.md par. 3). Rekenregels, op één plek:
//
//  1. Een uitbetaling betaalt de uren van een PERIODE (`WorkPeriods`): bij een salaris per maand de kalendermaand van de uitbetaling
//     of de maand ervoor; bij om de N weken of dagen de N weken of dagen die op de uitbetaaldag eindigen of de periode daarvoor.
//  2. De uren in de periode zijn de betaalde minuten van de diensten (pauze eraf, per kalenderdag gesplitst) met de factor van die
//     dag. Het bedrag is uurloon × (minuten × factor) / 60, EENMAAL afgerond op hele centen (half omhoog, exact in decimalen), net
//     als de bestaande salariscode. Het uurloon is dat van de maand van de uitbetaling (`salarySettings(forPayoutOn:)`).
//  3. Waar de agenda niets weet (dagen NA de laatste dienst en NA de dag van de laatste verversing) rekent de periode met de
//     handmatige uren per week (`SalarySettings.hoursPerCycle`), naar verhouding van het aantal dagen. Een periode die helemaal in
//     dat gebied valt geeft precies het handmatige bedrag (`SalarySettings.payoutAmount()`).
//  4. De uitkomst hangt alleen van de opgeslagen gegevens af, nooit van de klok: `today` bepaalt alleen "gewerkt" of "gepland".
//  5. Een eigen salaris of eigen uren van een maand gaan voor (eigen uren rekenen uren × uurloon, zonder toeslagen).

enum HoursSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Uren per week uit de salarisinstellingen (zoals altijd).
    case manual
    /// De uren van elke uitbetaling uit de agenda.
    case calendar

    var id: String { rawValue }
}

/// Welke uren een uitbetaling betaalt.
enum HoursPeriodBasis: String, Codable, CaseIterable, Identifiable, Sendable {
    /// De uren van de periode waarin de uitbetaling valt.
    case current
    /// De uren van de periode daarvoor (achteraf betaald).
    case previous

    var id: String { rawValue }
}

/// De diensten zoals de agenda ze het laatst gaf (afgeleid, zonder titels), en wat er is opgehaald.
struct WorkSnapshot: Codable, Equatable, Sendable {
    /// Oplopend en zonder overlap (`WorkShift.normalized`).
    var shifts: [WorkShift]
    /// Het opgehaalde venster (eerste en laatste dag).
    var from: CalendarDay
    var through: CalendarDay
    /// De dag van de laatste geslaagde verversing: tot en met die dag is de agenda "bekend", ook als er geen dienst meer staat.
    var fetchedDay: CalendarDay
    /// De agendanaam waarvoor dit is opgehaald.
    var calendarTitle: String

    enum CodingKeys: String, CodingKey { case shifts, from, through, fetchedDay, calendarTitle }

    init(shifts: [WorkShift], from: CalendarDay, through: CalendarDay, fetchedDay: CalendarDay, calendarTitle: String) {
        self.shifts = WorkShift.normalized(shifts)
        self.from = from
        self.through = through
        self.fetchedDay = fetchedDay
        self.calendarTitle = calendarTitle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = (try? c.decodeIfPresent(LossyArray<WorkShift>.self, forKey: .shifts))?.elements ?? []
        shifts = WorkShift.normalized(list)
        from = try c.decode(CalendarDay.self, forKey: .from)
        through = try c.decode(CalendarDay.self, forKey: .through)
        fetchedDay = try c.decode(CalendarDay.self, forKey: .fetchedDay)
        calendarTitle = (try? c.decodeIfPresent(String.self, forKey: .calendarTitle)) ?? ""
    }
}

/// Alle instellingen rond werkuren. Staat in `FinanceData.work` (dus in de back-up en de synchronisatie). Alleen wat afwijkt van de
/// standaard wordt geschreven: standaard schrijft niets (`{}`).
struct WorkSettings: Codable, Equatable, Sendable {
    var hoursSource: HoursSource = .manual
    /// De NAAM van de agenda (niet het id: dat verschilt per apparaat). Hoofdletters en accenten tellen niet.
    var calendarTitle: String = "werken"
    var periodBasis: HoursPeriodBasis = .current
    /// nil: hele-dag-afspraken negeren. Anders telt elke hele dag als een dienst van zoveel uur (vanaf 09:00), de pauzeregels gelden.
    var allDayShiftHours: Double?
    var rules = WorkRules()
    var snapshot: WorkSnapshot?

    init() {}

    enum CodingKeys: String, CodingKey { case hoursSource, calendarTitle, periodBasis, allDayShiftHours, rules, snapshot }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hoursSource = (try? c.decodeIfPresent(HoursSource.self, forKey: .hoursSource)) ?? .manual
        calendarTitle = (try? c.decodeIfPresent(String.self, forKey: .calendarTitle)) ?? "werken"
        periodBasis = (try? c.decodeIfPresent(HoursPeriodBasis.self, forKey: .periodBasis)) ?? .current
        if let hours = try? c.decodeIfPresent(Double.self, forKey: .allDayShiftHours), hours.isFinite {
            allDayShiftHours = min(max(hours, 0.25), 16)
        }
        rules = (try? c.decodeIfPresent(WorkRules.self, forKey: .rules)) ?? WorkRules()
        snapshot = try? c.decodeIfPresent(WorkSnapshot.self, forKey: .snapshot)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if hoursSource != .manual { try c.encode(hoursSource, forKey: .hoursSource) }
        if calendarTitle != "werken" { try c.encode(calendarTitle, forKey: .calendarTitle) }
        if periodBasis != .current { try c.encode(periodBasis, forKey: .periodBasis) }
        if let hours = allDayShiftHours, hours.isFinite { try c.encode(hours, forKey: .allDayShiftHours) }
        if rules != WorkRules() { try c.encode(rules, forKey: .rules) }
        try c.encodeIfPresent(snapshot, forKey: .snapshot)
    }

    /// Heeft de gebruiker iets ingesteld? De afgeleide diensten tellen niet (die komen vanzelf uit de agenda).
    var hasUserContent: Bool {
        var copy = self
        copy.snapshot = nil
        return copy != WorkSettings()
    }
}

// MARK: - Perioden

enum WorkPeriods {
    /// De dagen (dagnummers, `CalendarDay.dayNumber`) waarvan de uren een uitbetaling op `day` betalen. Maandelijks: de kalendermaand
    /// van de uitbetaling (`.current`) of de maand ervoor (`.previous`). Om de N weken of dagen: de `7 N` (of `N`) dagen die OP de
    /// uitbetaaldag eindigen, of de periode daarvoor. `salary` geeft het schema.
    static func period(forPayoutOn day: CalendarDay, salary: SalarySettings, basis: HoursPeriodBasis) -> ClosedRange<Int> {
        guard let cycle = salary.cycleDays else {
            let month = basis == .current ? day.yearMonth : day.yearMonth.adding(-1)
            return month.firstDayNumber...(month.firstDayNumber + month.dayCount - 1)
        }
        let end = basis == .current ? day.dayNumber : day.dayNumber - cycle
        return (end - cycle + 1)...end
    }
}

// MARK: - De uren per dag

/// De betaalde uren per kalenderdag, uitgerekend uit de diensten en de regels. Eén keer bouwen per stand van de gegevens.
struct WorkLedger {
    struct Day: Equatable {
        /// Betaalde minuten (na pauze).
        var paidMinutes = 0
        var breakMinutes = 0
        /// Betaalde minuten × factor in honderdsten (60 minuten met factor 1,5 is 9 000).
        var weighted100 = 0
        /// Het aantal diensten dat op deze dag begint.
        var shifts = 0
        /// Betaalde minuten per factor in honderdsten (150 -> 420 minuten).
        var byFactor: [Int: Int] = [:]
    }

    private(set) var days: [Int: Day] = [:]
    /// Het dagnummer van de laatste dag met een dienst.
    private(set) var lastShiftDay: Int?

    init(shifts: [WorkShift], rules: WorkRules, calendar: Calendar) {
        for shift in WorkShift.normalized(shifts) {
            let pieces = shift.pieces(calendar: calendar)
            // De onbetaalde pauze volgt de duur van de HELE dienst en wordt evenredig over de dagen verdeeld.
            let breaks = WorkMath.distribute(rules.breakMinutes(forShiftMinutes: shift.durationMinutes), over: pieces.map { $0.minutes })
            for (index, piece) in pieces.enumerated() {
                let paid = max(0, piece.minutes - breaks[index])
                let factor = rules.factorHundredths(on: piece.day)
                var day = days[piece.day.dayNumber] ?? Day()
                day.paidMinutes += paid
                day.breakMinutes += min(breaks[index], piece.minutes)
                day.weighted100 += paid * factor
                day.shifts += index == 0 ? 1 : 0
                day.byFactor[factor, default: 0] += paid
                days[piece.day.dayNumber] = day
                lastShiftDay = max(lastShiftDay ?? piece.day.dayNumber, piece.day.dayNumber)
            }
        }
    }

    /// De som over de dagen `range` (dagnummers). Een bereik van meer dan 800 dagen geeft niets (zo lang is geen periode).
    func total(_ range: ClosedRange<Int>) -> Day {
        var sum = Day()
        guard range.count <= 800 else { return sum }
        for number in range {
            guard let day = days[number] else { continue }
            sum.paidMinutes += day.paidMinutes
            sum.breakMinutes += day.breakMinutes
            sum.weighted100 += day.weighted100
            sum.shifts += day.shifts
            for (factor, minutes) in day.byFactor { sum.byFactor[factor, default: 0] += minutes }
        }
        return sum
    }
}

// MARK: - Het rapport van één uitbetaling

/// Wat een uitbetaling uit de agenda betaalt, voor het bedrag en voor de uitleg op het scherm.
struct WorkHoursReport: Equatable {
    /// Betaalde minuten bij één factor (in honderdsten: 150 is anderhalf keer het uurloon).
    struct FactorMinutes: Equatable {
        var factor: Int
        var minutes: Int
    }

    /// De dagen (dagnummers) waarvan de uren gelden.
    var period: ClosedRange<Int>
    /// Uren uit de agenda op dagen tot en met `asOf` (gewerkt) en daarna (gepland), in betaalde minuten.
    var workedMinutes = 0
    var plannedMinutes = 0
    /// Minuten die de agenda niet kent en die uit het gemiddelde komen (factor 1,0).
    var expectedMinutes = 0
    var breakMinutes = 0
    /// Betaalde minuten uit de agenda per factor in honderdsten (oplopend op factor).
    var byFactor: [FactorMinutes] = []
    var shiftCount = 0
    var amountCents = 0

    init(period: ClosedRange<Int>) {
        self.period = period
    }

    var agendaMinutes: Int { workedMinutes + plannedMinutes }
    var paidMinutes: Int { agendaMinutes + expectedMinutes }
    var paidHours: Double { Double(paidMinutes) / 60 }
    /// Geen enkele dag van de periode komt uit de agenda: het bedrag is het handmatige gemiddelde.
    var isAllExpected: Bool { agendaMinutes == 0 && shiftCount == 0 && expectedMinutes > 0 }

    /// De eerste en laatste dag van de periode als kalenderdagen.
    var firstDay: CalendarDay { CalendarDay(dayNumber: period.lowerBound) }
    var lastDay: CalendarDay { CalendarDay(dayNumber: period.upperBound) }

    /// De uren zoals ze in de dagboekhouding en op de uitbetaling komen.
    var payoutHours: PayoutHours { PayoutHours(paidMinutes: paidMinutes, expectedMinutes: expectedMinutes) }
}

/// De uren van een uitbetaling uit de agenda, voor de uitleg bij het salaris (`SalaryPayout.hours`, `DayEvent.detail`).
struct PayoutHours: Equatable, Sendable {
    /// Alle betaalde minuten van de periode: wat uit de agenda komt plus wat verwacht wordt.
    var paidMinutes: Int
    /// Daarvan de minuten die de agenda nog niet kent en die uit je gemiddelde komen.
    var expectedMinutes: Int

    init(paidMinutes: Int, expectedMinutes: Int) {
        self.paidMinutes = max(0, paidMinutes)
        self.expectedMinutes = min(max(0, expectedMinutes), max(0, paidMinutes))
    }

    /// De minuten uit de agenda.
    var agendaMinutes: Int { paidMinutes - expectedMinutes }
    /// Niets komt uit de agenda: alles is verwacht uit je gemiddelde.
    var isAllExpected: Bool { agendaMinutes == 0 && expectedMinutes > 0 }

    /// "uit agenda: 38,5 uur"; gemengd "uit agenda: 24 uur, plus 14,5 uur uit je gemiddelde"; helemaal verwacht "verwacht uit je gemiddelde:
    /// 38,5 uur". Dezelfde zin die `WorkText.payoutDetail` geeft: Dag voor dag en Home tonen hem bij de salarisgebeurtenis.
    var detailText: String {
        if expectedMinutes == 0 { return "uit agenda: \(Fmt.hours(minutes: paidMinutes))" }
        if agendaMinutes == 0 { return "verwacht uit je gemiddelde: \(Fmt.hours(minutes: expectedMinutes))" }
        return "uit agenda: \(Fmt.hours(minutes: agendaMinutes)), plus \(Fmt.hours(minutes: expectedMinutes)) uit je gemiddelde"
    }
}

extension SalarySettings {
    /// uurloon × (minuten × factor) / 60 op hele centen (half omhoog), exact in decimalen. `weightedMinutes100` is minuten × factor
    /// in honderdsten: 60 minuten met factor 1,5 is 9 000. 14,35 × 8,5 uur × 1,5 is 182,9625 en dus 182,96. Bij onleesbare of
    /// absurde getallen valt het terug op gewoon rekenen met afronden.
    static func exactPayCents(rate: Double, weightedMinutes100: Int) -> Int {
        func fallback() -> Int { CentsMath.int(rate * Double(weightedMinutes100) / 6_000) }
        guard rate.isFinite, abs(rate) < 1e6, weightedMinutes100 >= 0, weightedMinutes100 < 100_000_000 else { return fallback() }
        let text = "\(rate)"
        guard !text.contains("e"), !text.contains("E"), let r = Decimal(string: text) else { return fallback() }
        var exact = r * Decimal(weightedMinutes100) / Decimal(6_000)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 2, .plain)
        // Via hele centen naar een Int: `NSDecimalNumber.doubleValue` geeft op sommige platforms 1804,0700000000002.
        return Int(NSDecimalNumber(decimal: rounded * 100).int64Value)
    }
}

// MARK: - Koppeling met de salarisuitbetalingen

extension FinanceData {
    /// Rekent het uurloon met uren uit de agenda (en niet met "uren per week")? Alleen bij een uurloon met de bron "agenda"; een vast
    /// salaris negeert de agenda. De SOORT van het salaris is schema (`salary.mode`) en verandert niet per maand.
    var usesCalendarHours: Bool { salary.mode == .hourly && work.hoursSource == .calendar }

    /// De uren en het bedrag van de uitbetaling op `day`, of nil als het salaris geen uurloon uit de agenda is. Het uurloon en de
    /// uren per week voor wat de agenda niet kent zijn die van de maand van de uitbetaling (`salarySettings(forPayoutOn:)`): een
    /// periode die over de maandgrens loopt rekent helemaal met het loon van de maand waarin de uitbetaling valt. `today` bepaalt
    /// alleen wat "gewerkt" en wat "gepland" heet, nooit het bedrag.
    func workReport(forPayoutOn day: CalendarDay, asOf today: Date = Date()) -> WorkHoursReport? {
        guard usesCalendarHours else { return nil }
        let calendar = YearMonth.calendar
        let wage = salarySettings(forPayoutOn: day)
        let range = WorkPeriods.period(forPayoutOn: day, salary: salary, basis: work.periodBasis)
        let ledger = workLedger
        let snapshot = work.snapshot
        // Tot en met deze dag kent de agenda alles; daarna is het gemiddelde.
        let known: Int = snapshot.map { max($0.fetchedDay.dayNumber, ledger.lastShiftDay ?? Int.min) } ?? Int.min
        let knownEnd = min(known, range.upperBound)
        var report = WorkHoursReport(period: range)
        if knownEnd >= range.lowerBound {
            let todayNumber = CalendarDay(date: today, calendar: calendar).dayNumber
            var worked = WorkLedger.Day()
            var planned = WorkLedger.Day()
            let workedEnd = min(knownEnd, todayNumber)
            if workedEnd >= range.lowerBound { worked = ledger.total(range.lowerBound...workedEnd) }
            let plannedStart = max(range.lowerBound, todayNumber &+ 1)
            if plannedStart <= knownEnd { planned = ledger.total(plannedStart...knownEnd) }
            report.workedMinutes = worked.paidMinutes
            report.plannedMinutes = planned.paidMinutes
            report.breakMinutes = worked.breakMinutes + planned.breakMinutes
            report.shiftCount = worked.shifts + planned.shifts
            var factors: [Int: Int] = worked.byFactor
            for (factor, minutes) in planned.byFactor { factors[factor, default: 0] += minutes }
            report.byFactor = factors.keys.sorted().map { WorkHoursReport.FactorMinutes(factor: $0, minutes: factors[$0] ?? 0) }
            var weighted = worked.weighted100 + planned.weighted100
            // De dagen na `knownEnd`: het gemiddelde, naar verhouding van het aantal dagen van de periode.
            let unknownDays = range.upperBound - knownEnd
            if unknownDays > 0 {
                let share = Double(unknownDays) / Double(range.count)
                report.expectedMinutes = Int((wage.hoursPerCycle * 60 * share).rounded())
                weighted += report.expectedMinutes * 100
            }
            report.amountCents = SalarySettings.exactPayCents(rate: wage.hourlyRate, weightedMinutes100: weighted)
        } else {
            // De hele periode ligt voorbij wat de agenda weet: precies het handmatige bedrag.
            report.expectedMinutes = Int((wage.hoursPerCycle * 60).rounded())
            report.amountCents = CentsMath.int(wage.payoutAmount())
        }
        return report
    }

    /// Alleen het bedrag van de uitbetaling op `day` in hele centen (het rapport zonder de splitsing gewerkt/gepland); 0 als het
    /// salaris geen uurloon uit de agenda is.
    func workPayoutCents(on day: CalendarDay) -> Int {
        workReport(forPayoutOn: day, asOf: Date(timeIntervalSince1970: 0))?.amountCents ?? 0
    }

    /// De uren per dag van de huidige diensten en regels (één keer per stand van `work` en per tijdzone gebouwd).
    var workLedger: WorkLedger {
        let box = derivedWork.box
        let zone = YearMonth.calendar.timeZone.identifier
        box.lock.lock()
        if let known = box.ledger, box.zone == zone {
            box.lock.unlock()
            return known
        }
        box.lock.unlock()
        let built = WorkLedger(shifts: work.snapshot?.shifts ?? [], rules: work.rules, calendar: YearMonth.calendar)
        box.lock.lock()
        box.ledger = built
        box.zone = zone
        box.lock.unlock()
        return built
    }

    /// Komt de uitbetaling op `day` echt uit de agenda? Dan het rapport (uren, toeslagen, pauze, bedrag); nil als het salaris geen uurloon
    /// uit de agenda is of als de maand van de uitbetaling een eigen salaris of eigen uren heeft (die gaan voor). Voor de uitleg bij de
    /// volgende uitbetalingen op Salaris en Werkuren.
    func agendaPayoutReport(on day: CalendarDay, asOf today: Date = Date()) -> WorkHoursReport? {
        guard usesCalendarHours else { return nil }
        let plan = plan(for: day.yearMonth)
        guard plan.salaryOverride == nil, plan.hoursOverride == nil else { return nil }
        return workReport(forPayoutOn: day, asOf: today)
    }

    /// De dagen van de eerstvolgende `count` uitbetalingen na de dag van `date` (strikt later, zoals `nextPayDate(after:)`), oplopend; nooit
    /// vóór de startdag. Voor "de volgende twee uitbetalingen".
    func upcomingPayoutDays(count: Int = 2, after date: Date = Date()) -> [CalendarDay] {
        let calendar = YearMonth.calendar
        var days: [CalendarDay] = []
        var cursor = date
        while days.count < min(max(count, 0), 60), let next = nextPayDate(after: cursor) {
            days.append(CalendarDay(date: next, calendar: calendar))
            cursor = next
        }
        return days
    }

    /// De betaalde uren per week, gemiddeld over de laatste volle weken (maandag t/m zondag) vóór de week van `today` waarvan de agenda
    /// alles kent (vanaf het begin van wat is opgehaald), hoogstens `weeks` weken. Voor de knop "Gemiddelde uit je agenda invullen".
    /// Afgerond op 0,1 uur; nil zonder gelezen agenda of zonder één volle week.
    func averageAgendaHoursPerWeek(weeks: Int = 12, asOf today: Date = Date()) -> Double? {
        guard weeks > 0, let snapshot = work.snapshot else { return nil }
        let todayDay = CalendarDay(date: today, calendar: YearMonth.calendar)
        // De maandag van deze week; weekdag 1 is zondag, dus maandag is 2.
        let thisMonday = todayDay.dayNumber - (todayDay.weekday + 5) % 7
        // Alleen weken die de agenda geheel kent: niet vóór het begin van wat is opgehaald en niet na de dag van de laatste
        // verversing; de laatste volle week eindigt op de laatste zondag daarvoor.
        let known = min(snapshot.fetchedDay.dayNumber, thisMonday - 1)
        let lastSunday = known - (CalendarDay(dayNumber: known).weekday - 1)
        let count = min(weeks, 100, (lastSunday - snapshot.from.dayNumber + 1) / 7)
        guard count > 0 else { return nil }
        let minutes = workLedger.total((lastSunday - 7 * count + 1)...lastSunday).paidMinutes
        let hours = Double(minutes) / 60 / Double(count)
        return (hours * 10).rounded() / 10
    }
}

/// Tussenopslag van het `WorkLedger` bij een `FinanceData` (zoals `DerivedPlans`): niet opgeslagen, altijd "gelijk", leeg zodra `work`
/// verandert.
struct DerivedWork: Equatable {
    final class Box {
        let lock = NSLock()
        var ledger: WorkLedger?
        var zone = ""
    }

    let box = Box()

    static func == (lhs: DerivedWork, rhs: DerivedWork) -> Bool { true }
}
