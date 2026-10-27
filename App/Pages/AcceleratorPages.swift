import SwiftUI

// MARK: - Versnellers

/// Een versneller die de gebruiker wil toepassen, met de beschrijving van wat er dan verandert.
private struct PendingApplication: Identifiable {
    let accelerator: Accelerator
    let plan: AcceleratorPlan
    var id: String { accelerator.id }
}

/// Een regel tekst met een vaste plek, om een lijst zinnen te tonen.
private struct NumberedText: Identifiable {
    let id: Int
    let text: String

    static func list(_ texts: [String]) -> [NumberedText] {
        texts.enumerated().map { NumberedText(id: $0.offset, text: $0.element) }
    }
}

/// Looptijd in gewone woorden, of "niet haalbaar".
private func durationText(_ months: Int?) -> String {
    months.map { Fmt.duration(months: $0) } ?? "niet haalbaar"
}

extension Accelerator {
    /// Wat de versneller oplevert, in woorden: "3 jaar eerder" of "haalbaar in 5 jaar". Leeg als er niets te zeggen valt.
    var planningGainText: String {
        if let saved = monthsSaved { return "\(Fmt.duration(months: saved)) eerder" }
        if let months = newMonths { return "haalbaar in \(Fmt.duration(months: months))" }
        return ""
    }
}

// MARK: - De sectie Versnellers (op de pagina van een doel en op de pagina Versnellers)

struct AcceleratorsSection: View {
    let goal: LifeGoal
    /// Toon onderaan ook de sectie "Toegepast" van dit doel.
    var showsApplied: Bool = true
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Set<String> = []
    @State private var pending: PendingApplication?
    @State private var confirmation: String?

    init(goal: LifeGoal, showsApplied: Bool = true) {
        self.goal = goal
        self.showsApplied = showsApplied
    }

    var body: some View {
        VStack(spacing: Theme.pageSpacing) {
            acceleratorsBlock
            if showsApplied {
                AppliedAcceleratorsBlock(goalID: goal.id)
            }
        }
        .sheet(item: $pending) { item in
            AcceleratorApplySheet(accelerator: item.accelerator, plan: item.plan) {
                apply(item.accelerator)
            }
        }
    }

    @ViewBuilder
    private var acceleratorsBlock: some View {
        let d = store.data
        let now = store.now
        // Alles met het saldo van vandaag (`store.today`): dezelfde start en inleg als op de pagina van het doel.
        let inputs = d.goalInputs(for: goal, current: now, today: store.today)
        let baseline = Growth.monthsToReach(target: inputs.target, start: inputs.start,
                                            monthly: inputs.monthly, annualReturn: inputs.effectiveReturn)
        let list = d.accelerators(for: goal, current: now, today: store.today)
        // Wat al is toegepast (voor dit doel of een ander) telt niet meer mee in de berekening: het zit al in je gegevens.
        let locked = lockedRecords(in: list, data: d, current: now)
        let chosen = list.filter { selected.contains($0.id) && locked[$0.id] == nil }
        let change = d.combine(chosen)
        let scenario = d.scenarioMonths(inputs, change: change)

        Card(title: "Versnellers", symbol: "bolt", domain: .goals, subtitle: "Op basis van jouw gegevens") {
            if let confirmation {
                PlanningConfirmation(text: confirmation) { closeConfirmation() }
            }
            if baseline == 0 {
                Label("Je hebt dit doel al bereikt.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            } else if list.isEmpty {
                PlanningFootnote(emptyText(data: d))
            } else {
                resultRow(baseline: baseline, scenario: scenario, hasSelection: !chosen.isEmpty)
                if !chosen.isEmpty {
                    let curves = d.goalCurves(for: goal, change: change,
                                              months: horizon(baseline: baseline, scenario: scenario),
                                              current: now, today: store.today)
                    TrendChart(model: GoalCurveTrend.model(curves: curves, goalName: goal.name, start: now), size: .regular)
                }
                acceleratorRows(list: list, locked: locked, data: d)
                ActionGroup {
                    ActionButton(title: "Alles kiezen", symbol: "checkmark.circle") {
                        selected = Set(list.filter { locked[$0.id] == nil }.map(\.id))
                    }
                    ActionButton(title: "Niets kiezen", symbol: "circle") {
                        selected = []
                    }
                }
                PlanningFootnote("\(PlanningText.tap) op de versnellers die je wilt combineren. De berekening telt ze bij elkaar op. Met Toepassen voer je een versneller echt door in je gegevens; je kunt hem daarna herstellen.")
            }
            if baseline != 0, d.hasOneOffExpensesWorthCutting(current: now) {
                PlanningFootnote("Uitgaven worden hier alleen voorgesteld als ze terugkerend zijn, want een eenmalige uitgave levert geen vaste maandinleg op. Zet bij een uitgave \"Terugkerend, elke maand\" aan om hem hier te zien.")
            }
        }
    }

    /// De lijst met versnellers: elke rij met zijn keuze, status en knop "Toepassen".
    private func acceleratorRows(list: [Accelerator], locked: [String: AppliedAccelerator], data d: FinanceData) -> some View {
        VStack(spacing: 8) {
            ForEach(list) { acc in
                AcceleratorRow(accelerator: acc,
                               isOn: selected.contains(acc.id) && locked[acc.id] == nil,
                               isApplied: locked[acc.id]?.goalID == goal.id,
                               appliedElsewhere: elsewhereName(locked[acc.id], data: d),
                               toggle: { toggle(acc.id) },
                               apply: { prepareApply(acc) })
                    .transition(.opacity)
            }
        }
        .animated(by: selected, quick: true)
    }

    /// Per versneller de toepassing waardoor hij nu niet nog eens kan (zie `FinanceData.applicationBlocking`).
    private func lockedRecords(in list: [Accelerator], data d: FinanceData, current: YearMonth) -> [String: AppliedAccelerator] {
        var result: [String: AppliedAccelerator] = [:]
        for acc in list {
            if let record = d.applicationBlocking(acc, for: goal.id, current: current) { result[acc.id] = record }
        }
        return result
    }

    /// De naam van het andere doel waarvoor een versneller al is toegepast (nil als het dit doel is of niets is toegepast).
    private func elsewhereName(_ record: AppliedAccelerator?, data d: FinanceData) -> String? {
        guard let record, record.goalID != goal.id else { return nil }
        return record.goalID.flatMap { d.goal($0)?.name } ?? "een ander doel"
    }

    private func emptyText(data d: FinanceData) -> String {
        if d.appliedAccelerators(for: goal.id).isEmpty {
            return "Geen versnellers gevonden. Vul je inkomen, uitgaven, banksaldo en beleggingen in; dan zoekt de app wat je doel sneller maakt."
        }
        return "Er zijn nu geen andere versnellers. Wat je hebt toegepast, staat bij Toegepast."
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Opent de bevestiging met precies wat er verandert.
    private func prepareApply(_ acc: Accelerator) {
        let plan = store.data.applyPlan(acc, for: goal, current: store.now, now: store.today)
        pending = PendingApplication(accelerator: acc, plan: plan)
    }

    /// Voert de versneller door in je gegevens. Alles wat uit de gegevens wordt afgeleid, volgt vanzelf.
    private func apply(_ acc: Accelerator) {
        let target = goal
        let current = store.now
        let date = store.today
        var appliedTitle: String?
        store.mutate { data in
            appliedTitle = data.apply(acc, for: target, current: current, now: date)?.title
        }
        selected.remove(acc.id)
        // De bevestiging liet vooraf al zien of er iets te doen valt (`plan.message` legt uit waarom niet).
        if let appliedTitle { confirmation = "Toegepast: \(appliedTitle)" }
    }

    /// De bevestiging blijft staan tot je hem sluit (ACC-8).
    private func closeConfirmation() {
        withAnimation(reduceMotion ? nil : Theme.motion) { confirmation = nil }
    }

    private func horizon(baseline: Int?, scenario: Int?) -> Int {
        var h = max(baseline ?? 0, scenario ?? 0)
        if baseline == nil && scenario == nil { h = 120 }
        return min(600, max(24, h + 12))
    }

    @ViewBuilder
    private func resultRow(baseline: Int?, scenario: Int?, hasSelection: Bool) -> some View {
        FigureRow {
            StatTile(title: "Nu", value: durationText(baseline))
            if hasSelection {
                StatTile(title: "Met je keuze", value: durationText(scenario),
                         color: Theme.positive,
                         caption: savedText(baseline: baseline, scenario: scenario))
            }
        }
    }

    private func savedText(baseline: Int?, scenario: Int?) -> String? {
        switch (baseline, scenario) {
        case (let b?, let s?): return s < b ? "\(Fmt.duration(months: b - s)) eerder" : nil
        case (nil, _?): return "wordt haalbaar"
        default: return nil
        }
    }
}

// MARK: - Eén versneller

struct AcceleratorRow: View {
    let accelerator: Accelerator
    let isOn: Bool
    /// Deze versneller is al toegepast (en nog niet hersteld).
    var isApplied: Bool = false
    /// Naam van het doel waarvoor hij al is toegepast, als dat een ander doel is. Dan kan hij hier niet nog eens.
    var appliedElsewhere: String? = nil
    let toggle: () -> Void
    /// Opent de bevestiging om de versneller toe te passen. nil = geen knop.
    var apply: (() -> Void)? = nil

    private var isLocked: Bool { isApplied || appliedElsewhere != nil }

    private var leadingSymbol: String {
        if isLocked { return "checkmark.seal.fill" }
        return isOn ? "checkmark.circle.fill" : "circle"
    }

    private var leadingColor: Color {
        if isLocked { return Theme.positive }
        return isOn ? Theme.accent : Theme.textSecondary
    }

    /// De jaarlijkse verhoging bestaat niet in de app: toepassen verhoogt de inleg eenmalig. De knop zegt dat.
    private var applyTitle: String {
        AcceleratorKind(id: accelerator.id) == .stepUp ? "Eenmalig toepassen" : "Toepassen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            selectionButton
            statusLine
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(tint: isOn ? Theme.accent : nil)
        .animated(by: isOn, quick: true)
        .animated(by: isLocked)
    }

    /// De rij zelf: een tik kiest de versneller of haalt hem weer weg. Het vinkje staat er ook voor wie geen kleur ziet.
    private var selectionButton: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: leadingSymbol)
                    .font(.title3)
                    .foregroundStyle(leadingColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Label(accelerator.title, systemImage: accelerator.symbol)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    if !isLocked {
                        Text(accelerator.planningGainText)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.positive)
                    }
                    Text(accelerator.detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanningPressStyle())
        .disabled(isLocked)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var statusLine: some View {
        if isApplied {
            Label("Toegepast. Herstel hem hieronder als je het weer terug wilt.", systemImage: "checkmark.seal.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positive)
        } else if let appliedElsewhere {
            Label("Al toegepast voor \(appliedElsewhere). Herstel hem eerst om hem hier toe te passen.", systemImage: "checkmark.seal.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.positive)
        } else if let apply {
            ActionButton(title: applyTitle, symbol: "checkmark.circle", action: apply)
        }
    }
}

// MARK: - Bevestiging

/// Laat precies zien wat er verandert (oud naar nieuw) en vraagt om bevestiging: "Annuleer" links, "Toepassen" rechts. Het blad
/// heeft de systeemachtergrond (`SheetScaffold`).
struct AcceleratorApplySheet: View {
    let accelerator: Accelerator
    let plan: AcceleratorPlan
    let onApply: () -> Void

    var body: some View {
        SheetScaffold(title: "Versneller toepassen", saveTitle: "Toepassen", canSave: !plan.isEmpty, onSave: onApply) {
            Section {
                Label(accelerator.title, systemImage: accelerator.symbol)
                    .font(.headline)
            } header: {
                Text(plan.isEmpty ? "Hier valt niets te doen" : "Dit verandert er in je gegevens")
            }
            if plan.isEmpty {
                emptySection
            } else {
                changeSections
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Waarom er niets te doen valt.
    private var emptySection: some View {
        Section {
            Label(plan.message ?? "Hier valt niets te doen.", systemImage: "info.circle")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var changeSections: some View {
        if let headline = plan.headline {
            Section {
                Label(headline, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
        Section {
            ForEach(plan.lines) { line in
                AcceleratorPlanRow(line: line)
            }
        }
        Section {
            AmountRow(title: "Looptijd nu", value: durationText(plan.monthsBefore))
            AmountRow(title: "Looptijd daarna", value: durationText(plan.monthsAfter), detail: savedText, color: Theme.positive)
        }
        Section {
            ForEach(NumberedText.list(plan.notes)) { note in
                PlanningFootnote(note.text)
            }
            PlanningFootnote("Je kunt dit altijd herstellen: dan staat alles weer zoals het was.")
        }
    }

    private var savedText: String? {
        switch (plan.monthsBefore, plan.monthsAfter) {
        case (let b?, let a?): return a < b ? "\(Fmt.duration(months: b - a)) eerder" : nil
        case (nil, _?): return "wordt haalbaar"
        default: return nil
        }
    }
}

/// Eén verandering in de bevestiging: wat het is, de oude en de nieuwe waarde.
struct AcceleratorPlanRow: View {
    let line: AcceleratorPlanLine

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(line.title, systemImage: line.symbol)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
            if line.oldValue != nil || line.newValue != nil {
                values
            }
            if !line.detail.isEmpty {
                PlanningFootnote(line.detail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.sentence.isEmpty ? line.title : line.sentence)
    }

    private var values: some View {
        HStack(spacing: 6) {
            if let old = line.oldValue {
                Text(old).foregroundStyle(Theme.textSecondary)
            }
            if line.oldValue != nil && line.newValue != nil {
                Image(systemName: "arrow.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            if let new = line.newValue {
                Text(new)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.positive)
            }
        }
        .font(.subheadline)
    }
}

// MARK: - Toegepast en herstellen

/// De versnellers die zijn toegepast, met een knop om ze te herstellen. Zonder toepassingen verdwijnt het blok.
/// `goalID` nil = alle toepassingen (pagina Versnellers), anders alleen die van dat doel.
struct AppliedAcceleratorsBlock: View {
    var goalID: UUID? = nil
    @Environment(AppStore.self) private var store
    @State private var restoring: AppliedAccelerator?
    @State private var restoringAll = false

    init(goalID: UUID? = nil) {
        self.goalID = goalID
    }

    private var records: [AppliedAccelerator] {
        let all = store.data.appliedAccelerators
        guard let goalID else { return all }
        return all.filter { $0.goalID == goalID }
    }

    var body: some View {
        let d = store.data
        let list = Array(records.reversed())
        let restorable = d.restorableAcceleratorCount(for: goalID)
        if !list.isEmpty {
            Card(title: "Toegepast", symbol: "arrow.uturn.backward.circle", domain: .goals,
                 subtitle: "Zet ze terug, de nieuwste eerst") {
                VStack(spacing: 8) {
                    ForEach(list) { record in
                        AppliedAcceleratorRow(record: record, goalName: goalName(of: record),
                                              blockedBy: waitingFor(record, data: d)) {
                            restoring = record
                        }
                        .transition(.opacity)
                    }
                }
                if list.count > 1, restorable > 0 {
                    ActionButton(title: "Alles herstellen", symbol: "arrow.uturn.backward.circle") {
                        restoringAll = true
                    }
                }
            }
            .confirmationDialog("Dit herstellen?", isPresented: restoringBinding, titleVisibility: .visible,
                                presenting: restoring) { record in
                Button("Herstel", role: .destructive) { restore(record) }
                Button("Annuleer", role: .cancel) {}
            } message: { record in
                Text("\(record.title) gaat terug zoals het was. Wat je daarna in andere dingen veranderde, blijft staan. Heb je ditzelfde bedrag of dezelfde uitgave daarna zelf nog aangepast, dan gaat ook dat terug.")
            }
            .confirmationDialog("Alles herstellen?", isPresented: $restoringAll, titleVisibility: .visible) {
                Button("Herstel alles", role: .destructive) { restoreAll() }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text(restoreAllMessage(restorable: restorable, total: list.count))
            }
        }
    }

    private var restoringBinding: Binding<Bool> {
        Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })
    }

    /// Bij alle toepassingen (pagina Versnellers) staat erbij voor welk doel.
    private func goalName(of record: AppliedAccelerator) -> String? {
        guard goalID == nil else { return nil }
        guard let id = record.goalID else { return nil }
        return store.data.goal(id)?.name ?? "Verwijderd doel"
    }

    /// De toepassing die eerst terug moet voordat deze kan (zelfde pot, belegging of doel), als tekst voor in de rij.
    private func waitingFor(_ record: AppliedAccelerator, data d: FinanceData) -> String? {
        guard let blocker = d.restoreBlocker(for: record.id) else { return nil }
        if blocker.goalID != record.goalID, let name = blocker.goalID.flatMap({ d.goal($0)?.name }) {
            return "\(blocker.title) (\(name))"
        }
        return blocker.title
    }

    private func restoreAllMessage(restorable: Int, total: Int) -> String {
        if restorable >= total { return "Alle \(total) toegepaste versnellers gaan terug zoals het was." }
        return "Hiermee herstel je \(restorable) van de \(total) toegepaste versnellers. De rest kan pas terug als een nieuwere toepassing van een ander doel eerst is hersteld."
    }

    private func restore(_ record: AppliedAccelerator) {
        let id = record.id
        store.mutate { data in
            _ = data.restoreAccelerator(id)
        }
    }

    private func restoreAll() {
        let scope = goalID
        store.mutate { data in
            if let scope {
                // Nieuwste eerst; wat een nieuwere toepassing van een ander doel nodig heeft, blijft staan.
                _ = data.restoreAccelerators(for: scope)
            } else {
                data.restoreAllAccelerators()
            }
        }
    }
}

struct AppliedAcceleratorRow: View {
    let record: AppliedAccelerator
    var goalName: String? = nil
    /// Titel van de nieuwere toepassing die eerst hersteld moet worden. Dan staat er geen Herstel-knop.
    var blockedBy: String? = nil
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(record.title, systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(Fmt.date(record.date))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if let goalName {
                    Text("Voor \(goalName)")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ForEach(NumberedText.list(record.summary)) { line in
                PlanningFootnote(line.text)
            }
            if let blockedBy {
                Label("Herstel eerst: \(blockedBy)", systemImage: "arrow.uturn.backward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ActionButton(title: "Herstel", symbol: "arrow.uturn.backward", action: onRestore)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }
}

// MARK: - Pagina

/// Eigen pagina voor Versnellers: kies een doel en bekijk wat het sneller maakt. "Herstel" blijft bereikbaar, ook zonder doel en
/// bij meer dan een doel (onderaan staat alles wat is toegepast).
struct AcceleratorsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var chosenID: UUID?

    var body: some View {
        let d = store.data
        let goal = chosenID.flatMap { d.goal($0) } ?? d.goals.first
        PageScaffold(title: "Versnellers") {
            VStack(spacing: Theme.pageSpacing) {
                if d.goals.isEmpty {
                    Card(title: "Eerst een doel", symbol: "flag.checkered", domain: .goals) {
                        EmptyHint(symbol: "flag.checkered", title: "Maak een doel",
                                  message: "Versnellers laten zien wat je doel sneller maakt. Daarvoor heeft de app een doel nodig.",
                                  actionTitle: "Doel maken", action: { router.open(.goals) })
                    }
                } else if let goal {
                    if d.goals.count > 1 {
                        Card(title: "Voor welk doel?", symbol: "flag.checkered", domain: .goals) {
                            Picker("Doel", selection: Binding(get: { goal.id }, set: { chosenID = $0 })) {
                                ForEach(d.goals) { Text($0.name).tag($0.id) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                    AcceleratorsSection(goal: goal, showsApplied: false)
                        .id(goal.id)
                }
                // Onderaan alles wat is toegepast, ook voor andere doelen.
                AppliedAcceleratorsBlock(goalID: nil)
            }
            .frame(maxWidth: Theme.readableWidth)
        }
    }
}
