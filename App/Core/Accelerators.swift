import Foundation

/// Een aanpassing aan het basisscenario van een doel. Meerdere aanpassingen kunnen worden opgeteld.
struct ScenarioChange: Equatable {
    var extraMonthly: Double = 0
    var extraReturn: Double = 0
    var oneOff: Double = 0
    var stepUp: Double = 0
    var targetFactor: Double = 1

    func combined(with other: ScenarioChange) -> ScenarioChange {
        ScenarioChange(extraMonthly: extraMonthly + other.extraMonthly,
                       extraReturn: extraReturn + other.extraReturn,
                       oneOff: oneOff + other.oneOff,
                       stepUp: stepUp + other.stepUp,
                       targetFactor: targetFactor * other.targetFactor)
    }

    var isEmpty: Bool { self == ScenarioChange() }
}

/// Een manier om een doel sneller te halen, afgeleid van jouw eigen gegevens.
struct Accelerator: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var change: ScenarioChange
    /// Nieuwe looptijd in maanden met alleen deze versneller; nil = nog steeds niet binnen 100 jaar.
    var newMonths: Int?
    /// Maanden eerder dan nu. nil als het doel nu niet gehaald wordt.
    var monthsSaved: Int?
    /// Het doel wordt met deze versneller wel haalbaar (binnen 100 jaar).
    var makesReachable: Bool
}

struct GoalCurves {
    var baseline: [Double]
    var scenario: [Double]
    var target: Double
    var scenarioTarget: Double
}

extension FinanceData {
    /// Looptijd van een doel met aanpassingen.
    func scenarioMonths(_ inputs: GoalInputs, change: ScenarioChange) -> Int? {
        Growth.monthsToReach(target: inputs.target * change.targetFactor,
                             start: inputs.start,
                             monthly: inputs.monthly + change.extraMonthly,
                             annualReturn: inputs.effectiveReturn + change.extraReturn,
                             stepUp: change.stepUp,
                             oneOff: change.oneOff)
    }

    func combine(_ accelerators: [Accelerator]) -> ScenarioChange {
        accelerators.reduce(ScenarioChange()) { $0.combined(with: $1.change) }
    }

    /// Grafiekdata: basis en scenario, beide t/m `months` maanden.
    func goalCurves(for goal: LifeGoal, change: ScenarioChange, months: Int, current: YearMonth) -> GoalCurves {
        let inputs = goalInputs(for: goal, current: current)
        let base = Growth.monthlySeries(start: inputs.start, monthly: inputs.monthly,
                                        annualReturn: inputs.effectiveReturn, months: months)
        let scen = Growth.monthlySeries(start: inputs.start, monthly: inputs.monthly + change.extraMonthly,
                                        annualReturn: inputs.effectiveReturn + change.extraReturn,
                                        months: months, stepUp: change.stepUp, oneOff: change.oneOff)
        return GoalCurves(baseline: base, scenario: scen, target: inputs.target,
                          scenarioTarget: inputs.target * change.targetFactor)
    }

    /// Alle versnellers die voor dit doel iets opleveren, met de grootste winst bovenaan.
    func accelerators(for goal: LifeGoal, current: YearMonth) -> [Accelerator] {
        let inputs = goalInputs(for: goal, current: current)
        let baseline = Growth.monthsToReach(target: inputs.target, start: inputs.start,
                                            monthly: inputs.monthly, annualReturn: inputs.effectiveReturn)
        if baseline == 0 { return [] }

        var candidates: [(id: String, title: String, detail: String, symbol: String, change: ScenarioChange)] = []

        // 1. Vrije ruimte van deze maand
        let free = remaining(in: current)
        if free >= 10 {
            candidates.append(("free", "Zet je vrije ruimte in",
                               "Deze maand heb je \(Fmt.euro(free)) nog niet verdeeld. Elke maand extra inleggen versnelt je doel.",
                               "tray.and.arrow.down",
                               ScenarioChange(extraMonthly: free)))
        }

        // 2. 5% van het inkomen
        let monthlyIncome = income(in: current)
        let fivePercent = (monthlyIncome * 0.05).cents
        if monthlyIncome > 0, fivePercent >= 10 {
            candidates.append(("income5", "Leg 5% van je inkomen extra in",
                               "Dat is \(Fmt.euro(fivePercent)) per maand op een inkomen van \(Fmt.euro(monthlyIncome)).",
                               "percent",
                               ScenarioChange(extraMonthly: fivePercent)))
        }

        // 3. Grootste uitgaven 10% omlaag
        let topExpenses = plan(for: current).expenses.filter { $0.amount >= 20 }
            .sorted { $0.amount > $1.amount }.prefix(3)
        for line in topExpenses {
            let saving = (line.amount * 0.10).cents
            candidates.append(("expense-\(line.id.uuidString)", "Verlaag \(line.name) met 10%",
                               "\(line.name) kost \(Fmt.euro(line.amount)) per maand. 10% minder is \(Fmt.euro(saving)) per maand voor je doel.",
                               "scissors",
                               ScenarioChange(extraMonthly: saving)))
        }

        // 4. Overtollig geld op de bankrekening
        let surplus = bankSurplusAboveBuffer(current: current)
        if surplus >= 100 {
            candidates.append(("bank", "Zet overtollig bankgeld in",
                               "Je rekening staat op \(Fmt.euro(bankBalanceNow(current: current))). Je buffer van \(Fmt.duration(months: Int(settings.bankBufferMonths))) aan uitgaven is \(Fmt.euro(bankBuffer(current: current))). De overige \(Fmt.euro(surplus)) kan werken.",
                               "building.columns",
                               ScenarioChange(oneOff: surplus)))
        }

        // 5. Spaarpotten boven hun doel
        for pot in pots {
            if case .pot(let fundingID) = goal.funding, fundingID == pot.id { continue }
            guard let g = pot.goalAmount, g > 0 else { continue }
            let over = (potBalance(pot.id, at: current) - g).cents
            if over >= 50 {
                candidates.append(("pot-\(pot.id.uuidString)", "Overschot in \(pot.name) inzetten",
                                   "Spaarpot \(pot.name) staat \(Fmt.euro(over)) boven het doel van \(Fmt.euro(g)).",
                                   pot.symbol,
                                   ScenarioChange(oneOff: over)))
            }
        }

        // 6 en 7 gelden alleen als het doel uit je beleggingen komt
        if case .portfolio = goal.funding {
            let total = portfolioValue(current: current)
            let valued = holdings.map { ($0, holdingValueNow($0, current: current)) }.filter { $0.1 > 0 }

            // 6. Hoge kosten
            if total > 0 {
                var best: (Holding, Double)?
                for (h, v) in valued where h.annualCost > 0.0035 {
                    let gain = (v / total) * (h.annualCost - 0.002)
                    if best == nil || gain > best!.1 { best = (h, gain) }
                }
                if let (h, gain) = best, gain >= 0.0003 {
                    candidates.append(("costs", "Verlaag de kosten van \(h.name)",
                                       "\(h.name) kost \(Fmt.percent(h.annualCost, digits: 2)) per jaar. Een gelijkwaardig product met 0,20% kosten levert je portefeuille gemiddeld \(Fmt.percent(gain, digits: 2)) extra rendement per jaar op.",
                                       "eurosign.arrow.circlepath",
                                       ScenarioChange(extraReturn: gain)))
                }

                // 7. Herverdelen naar hoger rendement
                if valued.count >= 2,
                   let low = valued.min(by: { $0.0.netReturn < $1.0.netReturn }),
                   let high = valued.max(by: { $0.0.netReturn < $1.0.netReturn }),
                   low.0.id != high.0.id {
                    let share = low.1 / total
                    let spread = high.0.netReturn - low.0.netReturn
                    if share >= 0.10, spread >= 0.02 {
                        let gain = 0.5 * share * spread
                        candidates.append(("shift", "Verschuif deel van \(low.0.name) naar \(high.0.name)",
                                           "\(low.0.name) verwacht \(Fmt.percent(low.0.netReturn)) en is \(Fmt.percent(share, digits: 0)) van je portefeuille; \(high.0.name) verwacht \(Fmt.percent(high.0.netReturn)). De helft verschuiven levert ongeveer \(Fmt.percent(gain, digits: 2)) extra per jaar op. Let op: een hoger verwacht rendement gaat meestal samen met meer risico.",
                                           "arrow.left.arrow.right",
                                           ScenarioChange(extraReturn: gain)))
                    }
                }
            }
        }

        // 8. Meer uren werken (bij uurloon)
        if salary.mode == .hourly, salary.hourlyRate > 0 {
            let extra = (salary.hourlyRate * 2 * 52 / 12).cents
            if extra >= 10 {
                candidates.append(("hours", "Werk 2 uur extra per week",
                                   "Bij je uurloon van \(Fmt.euro(salary.hourlyRate)) levert dat ongeveer \(Fmt.euro(extra)) extra per maand op.",
                                   "clock.badge.plus",
                                   ScenarioChange(extraMonthly: extra)))
            }
        }

        // 9. Inleg jaarlijks verhogen
        if inputs.monthly > 0 {
            candidates.append(("stepup", "Verhoog je inleg elk jaar met 3%",
                               "Past bij een jaarlijkse loonsverhoging. Je begint bij \(Fmt.euro(inputs.monthly)) per maand en groeit mee.",
                               "chart.line.uptrend.xyaxis",
                               ScenarioChange(stepUp: 0.03)))
        }

        // 10. Doel 10% lager
        if inputs.target > 0 {
            let lower = (inputs.target * 0.9).cents
            let title: String
            let detail: String
            switch goal.kind {
            case .retirement:
                title = "Leef in je pensioen van 10% minder"
                detail = "Het benodigde kapitaal daalt van \(Fmt.euroWhole(inputs.target)) naar \(Fmt.euroWhole(lower))."
            case .partTime:
                title = "Houd het inkomensgat 10% kleiner"
                detail = "Het benodigde kapitaal daalt van \(Fmt.euroWhole(inputs.target)) naar \(Fmt.euroWhole(lower))."
            default:
                title = "Kies een doel dat 10% goedkoper is"
                detail = "Het doelbedrag daalt van \(Fmt.euroWhole(inputs.target)) naar \(Fmt.euroWhole(lower))."
            }
            candidates.append(("target", title, detail, "target", ScenarioChange(targetFactor: 0.9)))
        }

        var result: [Accelerator] = []
        for c in candidates {
            let months = scenarioMonths(inputs, change: c.change)
            var saved: Int?
            var reachable = false
            switch (baseline, months) {
            case (let b?, let m?):
                if m < b { saved = b - m } else { continue }
            case (nil, _?):
                reachable = true
            default:
                continue
            }
            result.append(Accelerator(id: c.id, title: c.title, detail: c.detail, symbol: c.symbol,
                                      change: c.change, newMonths: months, monthsSaved: saved,
                                      makesReachable: reachable))
        }

        return result.sorted { a, b in
            if a.makesReachable != b.makesReachable { return a.makesReachable }
            let sa = a.monthsSaved ?? (a.newMonths.map { -$0 } ?? Int.min)
            let sb = b.monthsSaved ?? (b.newMonths.map { -$0 } ?? Int.min)
            return sa > sb
        }
    }
}
