import SwiftUI

// De planken Doelen en Hulpmiddelen op Home. Ze lezen hun bewaarde keuzes per account op dit apparaat (het concept van de
// spaardoel-calculator, de opzet van de noodbuffer en het zelf ingevulde uurloon), precies zoals de oude kaarten van Plannen, en
// rekenen met dezelfde bronnen: `GoalMath.hubSubtitle`, `analyze`, `BufferCalc.summary`, `accelerators(for:)`, `Growth.projection`
// en `PurchaseCalc.resolvedWage`. Hier wordt niets zelf uitgerekend.

// MARK: - Doelen

/// Eén tegel op de plank Doelen: een levensdoel, de uitnodiging om een eerste doel te maken, of de rekentegel.
struct HomeGoalItem: Identifiable {
    enum Kind {
        case goal(LifeGoal)
        case first
        case calculator(SavingsGoalPlan?)
    }

    let id: String
    let kind: Kind

    /// Hoeveel doelen de plank toont: met de rekentegel erbij blijft het bij hoogstens acht tegels.
    static let maxGoals = 7

    /// De doelen, dan "Spaardoel berekenen". Zonder doelen komt "Maak je eerste doel" voor de rekentegel.
    static func items(goals: [LifeGoal], plan: SavingsGoalPlan?) -> [HomeGoalItem] {
        var list: [HomeGoalItem] = []
        if goals.isEmpty {
            list.append(HomeGoalItem(id: "first", kind: .first))
        } else {
            for goal in goals.prefix(maxGoals) {
                list.append(HomeGoalItem(id: "goal-" + goal.id.uuidString, kind: .goal(goal)))
            }
        }
        list.append(HomeGoalItem(id: "calculator", kind: .calculator(plan)))
        return list
    }
}

/// De plank Doelen. Het concept van de spaardoel-calculator staat per account op dit apparaat bewaard, dus de sleutel hangt van het
/// account af (`accountPrefsID`).
struct HomeGoalsShelf: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        let account = accountPrefsID(auth: auth, cloud: cloud)
        HomeGoalsContent(draftKey: SavingsGoalDraft.storageKey(account: account))
    }
}

private struct HomeGoalsContent: View {
    @Environment(AppStore.self) private var store
    @AppStorage private var storedDraft: String

    init(draftKey: String) {
        _storedDraft = AppStorage(wrappedValue: "", draftKey)
    }

    var body: some View {
        let d = store.data
        let plan = savingsPlan(d)
        // Alleen een berekend spaardoel en nog geen levensdoelen: ga meteen naar de calculator, niet naar een lege lijst.
        let destination: Destination = (d.goals.isEmpty && plan != nil) ? .savingsGoal : .goals
        let subtitle = GoalMath.hubSubtitle(goalCount: d.goals.count, hasSavingsGoal: plan != nil)
        let items = HomeGoalItem.items(goals: d.goals, plan: plan)
        Shelf("Doelen", subtitle: subtitle, showAll: destination, showAllLabel: "Toon alle doelen", orderID: "goals",
              items: items) { item in
            HomeGoalTile(item: item)
        }
    }

    /// Het plan uit de spaardoel-calculator, zodra je daar zelf iets hebt ingevuld.
    private func savingsPlan(_ d: FinanceData) -> SavingsGoalPlan? {
        guard let draft = SavingsGoalDraft.decode(storedDraft), draft.edited else { return nil }
        let plan = draft.plan(savingsRate: d.settings.savingsRate, inflation: d.settings.inflation, now: store.now)
        return plan.cleanGoal > 0 ? plan : nil
    }
}

private struct HomeGoalTile: View {
    let item: HomeGoalItem

    var body: some View {
        switch item.kind {
        case .goal(let goal):
            HomeGoalPoster(goal: goal)
        case .first:
            PosterCard(symbol: "flag.checkered", hue: .mustard, title: "Maak je eerste doel",
                       subtitle: "Pensioen, vakantie of parttime werken", destination: .goals)
        case .calculator(let plan):
            HomeCalculatorPoster(plan: plan)
        }
    }
}

/// Een levensdoel: tegel in mosterd met het symbool van de soort, naam, haalbaarheid in woorden, het percentage en de voortgang.
/// Het saldo van vandaag (`store.today`) telt mee, zoals op de doelpagina en bij de versnellers.
private struct HomeGoalPoster: View {
    let goal: LifeGoal
    @Environment(AppStore.self) private var store

    var body: some View {
        let analysis = store.data.analyze(goal, current: store.now, today: store.today)
        let hasTarget = analysis.outlook != .notSet
        let percent = Fmt.percent(min(analysis.progress, 9.99), digits: 0)
        PosterCard(symbol: goal.kind.symbol, hue: .mustard, title: goal.name, subtitle: analysis.outlook.homeLabel,
                   value: hasTarget ? percent : nil, progress: hasTarget ? analysis.progress : nil,
                   destination: .goal(goal.id))
    }
}

/// De rekentegel "Spaardoel berekenen", altijd aanwezig, met een samenvatting van je berekening als je er een hebt.
private struct HomeCalculatorPoster: View {
    let plan: SavingsGoalPlan?

    var body: some View {
        PosterCard(symbol: "function", hue: .mustard, title: "Spaardoel berekenen", subtitle: subtitle, value: value,
                   destination: .savingsGoal)
    }

    private var subtitle: String {
        guard let plan else { return "Bereken hoeveel je per maand spaart" }
        if plan.isReached { return "Het spaardoel van " + Fmt.euro(plan.cleanGoal) + " is al bereikt" }
        return "Spaar " + Fmt.euro(plan.cleanGoal) + " in " + Fmt.duration(months: plan.months)
    }

    private var value: String? {
        guard let plan, !plan.isReached else { return nil }
        return Fmt.euro(plan.requiredMonthlyWhole) + " per maand"
    }
}

private extension GoalOutlook {
    /// Korte tekst voor een tegel; dezelfde woorden als op de doelpagina.
    var homeLabel: String {
        switch self {
        case .notSet: return "Nog geen doelbedrag"
        case .reached: return "Bereikt"
        case .onTrack(let months): return "Op schema, over \(Fmt.duration(months: months))"
        case .behind(let months): return "Loopt achter, over \(Fmt.duration(months: months))"
        case .reachable(let months): return "Over \(Fmt.duration(months: months))"
        case .unreachable: return "Niet haalbaar"
        }
    }
}

// MARK: - Hulpmiddelen

/// Eén tegel op de plank Hulpmiddelen: de pagina, een regel eronder en eventueel een waarde en voortgang. Titel, symbool en
/// tegelkleur komen uit `PageCatalog`.
struct HomeToolItem: Identifiable {
    let destination: Destination
    let subtitle: String?
    let value: String?
    let progress: Double?

    var id: String { String(describing: destination) }
}

/// De ondertitels en waarden van de vier hulpmiddelen, uit de bronnen van de oude kaarten op Plannen.
enum HomeToolFigures {
    static func items(_ d: FinanceData, now: YearMonth, today: Date, bufferSetupJSON: String,
                      manualWage: Double) -> [HomeToolItem] {
        return [
            buffer(d, now: now, today: today, setupJSON: bufferSetupJSON),
            accelerators(d, now: now, today: today),
            projection(d, now: now),
            purchase(d, manualWage: manualWage)
        ]
    }

    /// "Noodbuffer": "n maanden aan uitgaven" en hoeveel maanden de buffer nu dekt, met de voortgang naar het doel. Zonder
    /// uitgaven de uitnodiging ze in te vullen.
    static func buffer(_ d: FinanceData, now: YearMonth, today: Date, setupJSON: String) -> HomeToolItem {
        let setup = BufferSetup.fromJSON(setupJSON) ?? BufferCalc.initialSetup(for: d, current: now)
        // Met het saldo van vandaag (`today`): dezelfde bank en spaarpot als op de pagina Noodbuffer.
        let r = BufferCalc.summary(for: d, setup: setup, current: now, today: today)
        if !r.hasTarget {
            return HomeToolItem(destination: .buffer, subtitle: "Vul je uitgaven in", value: nil, progress: nil)
        }
        var covered: String? = nil
        if let coverage = r.coverageMonths { covered = "Dekt " + months(coverage) }
        return HomeToolItem(destination: .buffer, subtitle: "\(r.months) maanden aan uitgaven", value: covered,
                            progress: r.progress)
    }

    /// "Versnellers": voor je eerste doel, met wat de beste versneller oplevert ("3 jaar eerder").
    static func accelerators(_ d: FinanceData, now: YearMonth, today: Date) -> HomeToolItem {
        guard let goal = d.goals.first else {
            return HomeToolItem(destination: .accelerators, subtitle: "Maak eerst een doel", value: nil, progress: nil)
        }
        let list = d.accelerators(for: goal, current: now, today: today)
        var gain: String? = nil
        if let best = list.first, !best.planningGainText.isEmpty { gain = best.planningGainText }
        return HomeToolItem(destination: .accelerators, subtitle: "Voor \(goal.name)", value: gain, progress: nil)
    }

    /// "Toekomstschatting": wat je beleggingen over 10 jaar waard zijn met je huidige inleg en rendement.
    static func projection(_ d: FinanceData, now: YearMonth) -> HomeToolItem {
        let start = d.portfolioValue(current: now)
        // Een schatting: wat er per maand wordt ingelegd (bij een salaris om de zoveel weken of dagen een gemiddelde maand).
        let monthly = d.monthlyInvestment(current: now)
        if start == 0 && monthly == 0 {
            return HomeToolItem(destination: .projection, subtitle: "Wat is het over x jaar?", value: nil, progress: nil)
        }
        let rate = d.weightedNetReturn(current: now)
        let result = Growth.projection(start: start, monthly: monthly, annualReturn: rate, months: 120,
                                       inflation: d.settings.inflation)
        return HomeToolItem(destination: .projection, subtitle: "Over 10 jaar", value: Fmt.euro(result.total), progress: nil)
    }

    /// "Aankoopcheck": je uurloon, of de uitnodiging het in te vullen.
    static func purchase(_ d: FinanceData, manualWage: Double) -> HomeToolItem {
        guard let wage = PurchaseCalc.resolvedWage(manual: manualWage, data: d) else {
            return HomeToolItem(destination: .purchase, subtitle: "Vul je uurloon in", value: nil, progress: nil)
        }
        return HomeToolItem(destination: .purchase, subtitle: "Je uurloon, netto", value: Fmt.euroExact(wage) + " per uur",
                            progress: nil)
    }

    /// "2,5 maanden", "1 maand".
    static func months(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let unit = rounded == 1 ? "maand" : "maanden"
        return "\(Fmt.input(rounded, maxDigits: 1)) \(unit)"
    }
}

/// De plank Hulpmiddelen: de vier rekenpagina's als tegels. De opzet van de noodbuffer en het uurloon staan per account op dit
/// apparaat bewaard.
struct HomeToolsShelf: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        let account = accountPrefsID(auth: auth, cloud: cloud)
        HomeToolsContent(bufferKey: AccountPrefs.key(BufferSetup.storageKey, account: account),
                         wageKey: AccountPrefs.key(PurchaseCalc.wageStorageKey, account: account))
    }
}

private struct HomeToolsContent: View {
    @Environment(AppStore.self) private var store
    @AppStorage private var storedSetup: String
    @AppStorage private var manualWage: Double

    init(bufferKey: String, wageKey: String) {
        _storedSetup = AppStorage(wrappedValue: "", bufferKey)
        _manualWage = AppStorage(wrappedValue: 0, wageKey)
    }

    var body: some View {
        let items = HomeToolFigures.items(store.data, now: store.now, today: store.today, bufferSetupJSON: storedSetup,
                                          manualWage: manualWage)
        Shelf("Hulpmiddelen", showAll: .tools, showAllLabel: "Toon alle hulpmiddelen", orderID: "tools", items: items) { item in
            HomeToolTile(item: item)
        }
    }
}

private struct HomeToolTile: View {
    let item: HomeToolItem

    var body: some View {
        let info = PageCatalog.info(item.destination)
        PosterCard(symbol: info?.symbol ?? "wrench.and.screwdriver", hue: info?.hue ?? .plum, title: info?.title ?? "Hulpmiddel",
                   subtitle: item.subtitle, value: item.value, progress: item.progress, destination: item.destination)
    }
}
