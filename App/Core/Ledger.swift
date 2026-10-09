import Foundation

// MARK: - De dagboekhouding
//
// Per kalenderdag: wat komt er binnen, wat gaat eruit, wat wordt overgeschreven naar spaarpotten en beleggingen,
// en hoeveel heb je dan (bankrekening en spaarpotten). Alle schermen (Overzicht, "te verdelen", spaarpotten,
// bankrekening, dagoverzicht) lezen dezelfde cijfers: de dagen zijn opgebouwd uit dezelfde gebeurtenissen en
// dezelfde saldi als de rest van de rekenmotor. Alles gebeurt PER KALENDERDAG, niet per tijdstip.
//
// Rekenregels, alles in hele centen (`CentsMath`):
//
//   saldo bank, eind van de dag = saldo eind vorige dag + inflow - outflow - toPots - toHoldings + bankCorrection
//   saldo spaarpotten, eind van de dag = vorige dag + planToPots + potEntriesNet + interest - paidFromPots
//
// `bankCorrection` is het verschil tussen een ingevuld banksaldo (`BankSnapshot`) en wat de app voor die dag zelf
// had uitgerekend. Zonder ingevuld saldo op die dag is het 0.

/// De cijfers van één kalenderdag.
///
/// De bedragen zijn positieve getallen, tenzij anders vermeld. `inflow`, `outflow`, `toPots` en `toHoldings`
/// zijn de optelsom van een geplande en een handmatige kant; die staan apart zodat je ze eerlijk kunt tonen.
struct DayTotals: Identifiable, Equatable {
    /// 12:00 van die dag (zoals `YearMonth.date(day:)`).
    var date: Date
    /// Dag van de maand (1...31).
    var day: Int
    /// Wat er die dag op de bankrekening binnenkomt: salaris en extra inkomsten (plan) plus handmatige stortingen.
    var inflow: Double
    /// Wat er die dag van de bankrekening afgaat: het bankdeel van uitgaven (plan) plus handmatige opnames.
    var outflow: Double
    /// Wat er die dag naar spaarpotten gaat: geplande inleg plus handmatige overboekingen van bank naar pot, min
    /// handmatige overboekingen van pot naar bank. Kan negatief zijn.
    var toPots: Double
    /// Geplande inleg die dag naar beleggingen.
    var toHoldings: Double
    /// Het deel van de uitgaven dat die dag uit spaarpotten wordt betaald (de bank betaalt dat niet).
    var paidFromPots: Double
    /// Rente die die dag in een spaarpot wordt bijgeschreven (opgeslagen of verwacht).
    var interest: Double
    /// Saldo van de bankrekening aan het EIND van de dag. nil zolang er geen saldo bekend is.
    var bankBalance: Double?
    /// Totaal van alle spaarpotten aan het EIND van de dag.
    var potsTotal: Double
    /// De "nog te verdelen" van deze maand t/m deze dag: inkomsten tot nu toe min bankuitgaven tot nu toe min wat tot
    /// nu toe naar spaarpotten en beleggingen is overgeschreven (alleen het maandplan). Op de laatste dag van de
    /// maand gelijk aan `FinanceData.remaining(in:)`.
    var remainingSoFar: Double
    /// Alle gebeurtenissen van de dag, gesorteerd.
    var events: [DayEvent]
    /// De dag ligt na vandaag.
    var isPlanned: Bool
    /// Het is vandaag.
    var isToday: Bool
    /// Er gebeurt iets op deze dag: een gebeurtenis, een handmatige potboeking of een saldocorrectie.
    var hasActivity: Bool

    // MARK: Opbouw (geplande en handmatige delen apart)

    /// Salaris en extra inkomsten volgens het maandplan.
    var planInflow: Double = 0
    /// Handmatige stortingen op de bankrekening.
    var manualInflow: Double = 0
    /// Het bankdeel van de uitgaven volgens het maandplan.
    var planOutflow: Double = 0
    /// Handmatige opnames van de bankrekening.
    var manualOutflow: Double = 0
    /// Geplande inleg naar spaarpotten (ook het bedrag dat de potten er die dag bij krijgen).
    var planToPots: Double = 0
    /// Handmatige overboekingen bank -> pot (positief) min pot -> bank (negatief), gezien vanaf de bankrekening.
    var manualToPots: Double = 0
    /// Alle handmatige boekingen op spaarpotten van die dag (storting, opname, overboeking, correctie), zonder rente.
    /// Dit is wat de potten er naast de geplande inleg bij krijgen (of kwijtraken).
    var potEntriesNet: Double = 0
    /// Verschil tussen het ingevulde banksaldo van die dag en wat de app zelf had uitgerekend. 0 zonder ingevuld
    /// saldo op die dag (en op de eerste dag waarvoor een saldo bekend is).
    var bankCorrection: Double = 0
    /// Saldo van de bankrekening aan het begin van de dag (eind van de vorige dag). nil als dat nog niet bekend was.
    var openingBank: Double?
    /// Totaal van de spaarpotten aan het begin van de dag.
    var openingPots: Double = 0
    /// De bankcijfers van deze dag sluiten: begin + inflow - outflow - toPots - toHoldings + correctie = eind.
    /// Waar als het begin- of eindsaldo nog niet bekend is.
    var bankReconciles: Bool = true
    /// De potcijfers van deze dag sluiten: begin + planToPots + potEntriesNet + interest - paidFromPots = eind.
    var potsReconciles: Bool = true

    var id: Date { date }

    /// Wat er die dag netto op de bankrekening verandert: inflow - outflow - toPots - toHoldings + correctie.
    var bankChange: Double {
        CentsMath.value(CentsMath.int(inflow) - CentsMath.int(outflow) - CentsMath.int(toPots)
                        - CentsMath.int(toHoldings) + CentsMath.int(bankCorrection))
    }

    /// Wat er die dag netto in de spaarpotten verandert.
    var potsChange: Double {
        CentsMath.value(CentsMath.int(planToPots) + CentsMath.int(potEntriesNet)
                        + CentsMath.int(interest) - CentsMath.int(paidFromPots))
    }
}

/// De dagen van een maand met de totalen, en de controle dat alles sluit.
struct MonthLedger: Identifiable, Equatable {
    var month: YearMonth
    /// Alle dagen van de maand, ook die zonder gebeurtenissen.
    var days: [DayTotals]
    /// Saldo aan het eind van de laatste dag van de vorige maand. nil als dat nog niet bekend was.
    var openingBank: Double?
    /// Saldo aan het eind van de laatste dag van de maand (`bankBalance(at:)`). nil als het niet bekend is.
    var closingBank: Double?
    /// Totaal van de spaarpotten aan het eind van de vorige maand.
    var openingPots: Double
    /// Totaal van de spaarpotten aan het eind van de maand.
    var closingPots: Double

    // Som over de dagen.
    var inflow: Double
    var outflow: Double
    var toPots: Double
    var toHoldings: Double
    var paidFromPots: Double
    var interest: Double
    /// Alle handmatige potboekingen in de maand, zonder rente.
    var potEntriesNet: Double

    /// Salaris en extra inkomsten volgens het maandplan (`income(in:)`).
    var income: Double
    /// Alle uitgaven van de maand, bankdeel en potdeel samen (`expensesTotal(in:)`).
    var expensesTotal: Double
    /// Wat er nog te verdelen is (`remaining(in:)`).
    var remaining: Double

    /// Sluit het banksaldo? Elke dag sluit, en (als het beginsaldo bekend is) ook de hele maand:
    /// begin + inflow - outflow - toPots - toHoldings + correcties = eind.
    var bankReconciles: Bool
    /// Sluiten de spaarpotten? Elke dag sluit, en de hele maand:
    /// begin + planToPots + potEntriesNet + interest - paidFromPots = eind.
    var potsReconciles: Bool
    /// Komt het dagboek overeen met het maandoverzicht (inkomen, uitgaven, gespaard, belegd, over)?
    /// Zie `MonthLedger` in Ledger.swift voor de afzonderlijke vergelijkingen.
    var overviewReconciles: Bool

    // MARK: Opbouw (geplande en handmatige delen apart)

    /// Salaris en extra inkomsten volgens de dagen (moet gelijk zijn aan `income`).
    var planInflow: Double = 0
    var manualInflow: Double = 0
    /// Het bankdeel van de uitgaven volgens de dagen (moet gelijk zijn aan `expensesFromBank`).
    var planOutflow: Double = 0
    var manualOutflow: Double = 0
    /// Geplande inleg naar spaarpotten volgens de dagen (moet gelijk zijn aan `saved`).
    var planToPots: Double = 0
    var manualToPots: Double = 0
    /// Som van de saldocorrecties door ingevulde banksaldi.
    var bankCorrections: Double = 0
    /// `savedTotal(in:)`: wat het maandplan naar spaarpotten verdeelt.
    var saved: Double = 0
    /// `investedTotal(in:)`: wat het maandplan naar beleggingen verdeelt.
    var invested: Double = 0
    /// `expensesFromBank(in:)` en `expensesFromPots(in:)`.
    var expensesFromBank: Double = 0
    var expensesFromPots: Double = 0

    var id: String { month.key }

    /// Alles sluit: bank, spaarpotten en maandoverzicht.
    var allReconciles: Bool { bankReconciles && potsReconciles && overviewReconciles }
}

extension FinanceData {
    /// De cijfers van één kalenderdag. Rekent de hele maand uit en pakt daar de dag uit; heb je meer dagen van
    /// dezelfde maand nodig, gebruik dan `monthLedger(_:asOf:)`.
    func dayTotals(on date: Date, asOf today: Date = Date()) -> DayTotals {
        let cal = YearMonth.calendar
        let month = YearMonth(date: date, calendar: cal)
        let ledger = monthLedger(month, asOf: today)
        let number = DayMath.dayNumber(of: date, calendar: cal)
        return ledger.days[min(max(number, 1), ledger.days.count) - 1]
    }

    /// De dagboekhouding van een maand: alle dagen, de totalen en de controle dat alles sluit.
    ///
    /// Loopt één keer door de dagen. De gebeurtenissen komen uit `dayEventsByMonth`, het banksaldo per dag uit
    /// `BankTimeline` (hetzelfde als `bankBalance(on:)`), het potsaldo per dag uit `potFlows` (hetzelfde als
    /// `potBalance(_:asOf:)`) en de maandcijfers uit `monthFigures`. De controles vergelijken die onafhankelijke
    /// wegen met elkaar.
    ///
    /// `today` bepaalt alleen `isPlanned` en `isToday` (per kalenderdag); de bedragen hangen er niet van af.
    func monthLedger(_ month: YearMonth, asOf today: Date = Date()) -> MonthLedger {
        let cal = YearMonth.calendar
        let n = month.dayCount
        let monthStart = month.firstDay
        let monthEnd = month.endExclusive

        // Het eind (exclusief) van elke dag: limits[d] is het begin van dag d + 1, limits[0] het begin van de maand.
        var limits: [Date] = [monthStart]
        limits.reserveCapacity(n + 1)
        for d in 1...n {
            limits.append(DayMath.nextDayStart(after: month.date(day: d, calendar: cal), calendar: cal))
        }

        // Spaarpotten: één keer per pot opbouwen (dag voor dag saldo, en de rente voor de gebeurtenissen).
        let flows = allPotFlows(throughMonth: month)

        let events = dayEventsByMonth(from: month, to: month, asOf: today, flows: flows)[month] ?? []
        var eventsByDay = [[DayEvent]](repeating: [], count: n)

        // Alles in hele centen, per dag (index = dag - 1).
        var planIn = [Int](repeating: 0, count: n)
        var planOut = [Int](repeating: 0, count: n)
        var planPots = [Int](repeating: 0, count: n)
        var planHold = [Int](repeating: 0, count: n)
        var fromPots = [Int](repeating: 0, count: n)
        var interest = [Int](repeating: 0, count: n)
        var manIn = [Int](repeating: 0, count: n)
        var manOut = [Int](repeating: 0, count: n)
        var manPots = [Int](repeating: 0, count: n)
        var potNet = [Int](repeating: 0, count: n)

        for event in events {
            let i = min(max(event.day, 1), n) - 1
            eventsByDay[i].append(event)
            switch event.kind {
            case .salary, .income:
                planIn[i] = CentsMath.add(planIn[i], CentsMath.int(event.bankAmount))
            case .expense:
                planOut[i] = CentsMath.add(planOut[i], -CentsMath.int(event.bankAmount))
                fromPots[i] = CentsMath.add(fromPots[i], -CentsMath.int(event.potAmount))
            case .toPot:
                planPots[i] = CentsMath.add(planPots[i], -CentsMath.int(event.bankAmount))
            case .toHolding:
                planHold[i] = CentsMath.add(planHold[i], -CentsMath.int(event.bankAmount))
            case .interest:
                interest[i] = CentsMath.add(interest[i], CentsMath.int(event.potAmount))
            case .bankEntry:
                break // handmatig: hieronder uit de boekingen zelf, met hun soort
            }
        }

        // Handmatige bankboekingen van de maand (dezelfde selectie als `bankEntryEvents`).
        var entryItems: [(day: Int, date: Date, cents: Int)] = []
        for entry in bankEntries where entry.date >= monthStart && entry.date < monthEnd {
            let cents = CentsMath.int(entry.amount)
            guard cents != 0 else { continue }
            let i = min(max(DayMath.dayNumber(of: entry.date, calendar: cal), 1), n) - 1
            entryItems.append((i, entry.date, cents))
            switch entry.kind {
            case .deposit, .withdrawal:
                if cents > 0 { manIn[i] = CentsMath.add(manIn[i], cents) } else { manOut[i] = CentsMath.add(manOut[i], -cents) }
            case .toPot, .fromPot:
                manPots[i] = CentsMath.add(manPots[i], -cents)
            }
        }

        // Handmatige potboekingen van de maand zonder rente (rente staat in `interest`). Rente-boekingen van het
        // rooster zitten in de uitbetalingen en tellen daar al mee.
        for entry in potEntries where entry.date >= monthStart && entry.date < monthEnd {
            guard flows[entry.potID] != nil, entry.kind != .interest,
                  !(flows[entry.potID]?.managedIDs.contains(entry.id) ?? false) else { continue }
            let i = min(max(DayMath.dayNumber(of: entry.date, calendar: cal), 1), n) - 1
            potNet[i] = CentsMath.add(potNet[i], CentsMath.int(entry.amount))
        }

        // Saldo van de bank aan het eind van elke dag (en van de vorige maand): één tijdlijn voor alle dagen.
        let timeline = BankTimeline(self, firstLimit: monthStart, lastLimit: monthEnd,
                                    events: { $0 == month ? events : self.bankFlowEvents(in: $0) })
        let bankOpeningCents = timeline.balanceCents(entriesBefore: monthStart, planBefore: monthStart)
        var bankClosing = [Int?](repeating: nil, count: n)
        for d in 0..<n {
            bankClosing[d] = timeline.balanceCents(entriesBefore: limits[d + 1], planBefore: limits[d + 1])
        }

        // Ingevulde banksaldi: het laatste van de dag geldt (zoals in `BankTimeline`).
        let snapshots = sortedBankSnapshots
        var snapshotOfDay = [Int?](repeating: nil, count: n)
        for (index, snapshot) in snapshots.enumerated() where snapshot.date >= monthStart && snapshot.date < monthEnd {
            snapshotOfDay[min(max(DayMath.dayNumber(of: snapshot.date, calendar: cal), 1), n) - 1] = index
        }

        // Saldo van de potten aan het eind van elke dag (en van de vorige maand).
        var potsOpeningCents = 0
        var potsClosing = [Int](repeating: 0, count: n)
        for pot in pots {
            guard let f = flows[pot.id] else { continue }
            potsOpeningCents = CentsMath.add(potsOpeningCents, f.cents(before: monthStart))
            for d in 0..<n { potsClosing[d] = CentsMath.add(potsClosing[d], f.cents(before: limits[d + 1])) }
        }

        // De cijfers van de maand uit het plan (de andere weg).
        let figures = monthFigures(month)

        let todayMonth = YearMonth(date: today, calendar: cal)
        let todayNumber = DayMath.dayNumber(of: today, calendar: cal)

        var days: [DayTotals] = []
        days.reserveCapacity(n)
        var previousBank = bankOpeningCents
        var previousPots = potsOpeningCents
        var cumulativeRemaining = 0
        var sumIn = 0, sumOut = 0, sumPots = 0, sumHold = 0, sumFromPots = 0, sumInterest = 0, sumPotNet = 0
        var sumPlanIn = 0, sumPlanOut = 0, sumPlanPots = 0, sumManIn = 0, sumManOut = 0, sumManPots = 0, sumCorrections = 0
        var allBankDaysReconcile = true
        var allPotDaysReconcile = true

        for d in 0..<n {
            let inflow = CentsMath.add(planIn[d], manIn[d])
            let outflow = CentsMath.add(planOut[d], manOut[d])
            let toPots = CentsMath.add(planPots[d], manPots[d])
            let planFlow = CentsMath.add(CentsMath.add(planIn[d], -planOut[d]), CentsMath.add(-planPots[d], -planHold[d]))

            // Een ingevuld saldo op deze dag: wat verwachtte de app voor het einde van de dag? Het saldo is het saldo
            // aan het eind van de dag voor alle geplande boekingen van die dag; handmatige boekingen van vóór het
            // meetmoment zitten er al in, die van erna komen er nog bij.
            var correction = 0
            if let si = snapshotOfDay[d], let before = previousBank, bankClosing[d] != nil {
                let snapshot = snapshots[si]
                var manualBefore = 0
                for item in entryItems where item.day == d && item.date <= snapshot.date {
                    manualBefore = CentsMath.add(manualBefore, item.cents)
                }
                let expected = CentsMath.add(before, CentsMath.add(planFlow, manualBefore))
                correction = CentsMath.add(CentsMath.int(snapshot.balance), -expected)
            }

            // Sluit de dag?
            var bankOK = true
            if let before = previousBank, let after = bankClosing[d] {
                let change = CentsMath.add(CentsMath.add(inflow, -outflow),
                                           CentsMath.add(CentsMath.add(-toPots, -planHold[d]), correction))
                bankOK = after == CentsMath.add(before, change)
            }
            let potsChange = CentsMath.add(CentsMath.add(planPots[d], potNet[d]), CentsMath.add(interest[d], -fromPots[d]))
            let potsOK = potsClosing[d] == CentsMath.add(previousPots, potsChange)
            allBankDaysReconcile = allBankDaysReconcile && bankOK
            allPotDaysReconcile = allPotDaysReconcile && potsOK

            cumulativeRemaining = CentsMath.add(cumulativeRemaining, planFlow)
            let number = d + 1
            let isToday = month == todayMonth && number == todayNumber
            let isPlanned = month > todayMonth || (month == todayMonth && number > todayNumber)
            let dayEvents = eventsByDay[d]

            days.append(DayTotals(
                date: month.date(day: number, calendar: cal),
                day: number,
                inflow: CentsMath.value(inflow),
                outflow: CentsMath.value(outflow),
                toPots: CentsMath.value(toPots),
                toHoldings: CentsMath.value(planHold[d]),
                paidFromPots: CentsMath.value(fromPots[d]),
                interest: CentsMath.value(interest[d]),
                bankBalance: bankClosing[d].map { CentsMath.value($0) },
                potsTotal: CentsMath.value(potsClosing[d]),
                remainingSoFar: CentsMath.value(cumulativeRemaining),
                events: dayEvents,
                isPlanned: isPlanned,
                isToday: isToday,
                hasActivity: !dayEvents.isEmpty || potNet[d] != 0 || correction != 0,
                planInflow: CentsMath.value(planIn[d]),
                manualInflow: CentsMath.value(manIn[d]),
                planOutflow: CentsMath.value(planOut[d]),
                manualOutflow: CentsMath.value(manOut[d]),
                planToPots: CentsMath.value(planPots[d]),
                manualToPots: CentsMath.value(manPots[d]),
                potEntriesNet: CentsMath.value(potNet[d]),
                bankCorrection: CentsMath.value(correction),
                openingBank: previousBank.map { CentsMath.value($0) },
                openingPots: CentsMath.value(previousPots),
                bankReconciles: bankOK,
                potsReconciles: potsOK))

            sumIn = CentsMath.add(sumIn, inflow)
            sumOut = CentsMath.add(sumOut, outflow)
            sumPots = CentsMath.add(sumPots, toPots)
            sumHold = CentsMath.add(sumHold, planHold[d])
            sumFromPots = CentsMath.add(sumFromPots, fromPots[d])
            sumInterest = CentsMath.add(sumInterest, interest[d])
            sumPotNet = CentsMath.add(sumPotNet, potNet[d])
            sumPlanIn = CentsMath.add(sumPlanIn, planIn[d])
            sumPlanOut = CentsMath.add(sumPlanOut, planOut[d])
            sumPlanPots = CentsMath.add(sumPlanPots, planPots[d])
            sumManIn = CentsMath.add(sumManIn, manIn[d])
            sumManOut = CentsMath.add(sumManOut, manOut[d])
            sumManPots = CentsMath.add(sumManPots, manPots[d])
            sumCorrections = CentsMath.add(sumCorrections, correction)

            previousBank = bankClosing[d]
            previousPots = potsClosing[d]
        }

        let bankClosingCents = bankClosing[n - 1]

        // De hele maand: begin + bewegingen + correcties = eind (alleen als het beginsaldo bekend is).
        var bankMonthOK = allBankDaysReconcile
        if let opening = bankOpeningCents, let closing = bankClosingCents {
            let change = CentsMath.add(CentsMath.add(sumIn, -sumOut), CentsMath.add(CentsMath.add(-sumPots, -sumHold), sumCorrections))
            bankMonthOK = bankMonthOK && closing == CentsMath.add(opening, change)
        }
        let potsClosingCents = potsClosing[n - 1]
        let potsMonthChange = CentsMath.add(CentsMath.add(sumPlanPots, sumPotNet), CentsMath.add(sumInterest, -sumFromPots))
        let potsMonthOK = allPotDaysReconcile && potsClosingCents == CentsMath.add(potsOpeningCents, potsMonthChange)

        // Het dagboek tegenover het maandoverzicht.
        let dayRemaining = CentsMath.add(CentsMath.add(sumPlanIn, -sumPlanOut), CentsMath.add(-sumPlanPots, -sumHold))
        let overviewOK = figures.income == sumPlanIn
            && figures.expenses == CentsMath.add(sumPlanOut, sumFromPots)
            && figures.fromPots == sumFromPots
            && figures.saved == sumPlanPots
            && figures.invested == sumHold
            && figures.remaining == dayRemaining
            && CentsMath.int(days[n - 1].remainingSoFar) == figures.remaining

        return MonthLedger(
            month: month,
            days: days,
            openingBank: bankOpeningCents.map { CentsMath.value($0) },
            closingBank: bankClosingCents.map { CentsMath.value($0) },
            openingPots: CentsMath.value(potsOpeningCents),
            closingPots: CentsMath.value(potsClosingCents),
            inflow: CentsMath.value(sumIn),
            outflow: CentsMath.value(sumOut),
            toPots: CentsMath.value(sumPots),
            toHoldings: CentsMath.value(sumHold),
            paidFromPots: CentsMath.value(sumFromPots),
            interest: CentsMath.value(sumInterest),
            potEntriesNet: CentsMath.value(sumPotNet),
            income: CentsMath.value(figures.income),
            expensesTotal: CentsMath.value(figures.expenses),
            remaining: CentsMath.value(figures.remaining),
            bankReconciles: bankMonthOK,
            potsReconciles: potsMonthOK,
            overviewReconciles: overviewOK,
            planInflow: CentsMath.value(sumPlanIn),
            manualInflow: CentsMath.value(sumManIn),
            planOutflow: CentsMath.value(sumPlanOut),
            manualOutflow: CentsMath.value(sumManOut),
            planToPots: CentsMath.value(sumPlanPots),
            manualToPots: CentsMath.value(sumManPots),
            bankCorrections: CentsMath.value(sumCorrections),
            saved: CentsMath.value(figures.saved),
            invested: CentsMath.value(figures.invested),
            expensesFromBank: CentsMath.value(CentsMath.add(figures.expenses, -figures.fromPots)),
            expensesFromPots: CentsMath.value(figures.fromPots))
    }
}
