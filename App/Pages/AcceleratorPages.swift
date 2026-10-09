import SwiftUI
import Charts

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

struct AcceleratorsSection: View {
    let goal: LifeGoal
    /// Toon onderaan ook de sectie "Toegepast" van dit doel.
    var showsApplied: Bool = true
    @Environment(AppStore.self) private var store
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
        // De bevestiging verdwijnt na een paar seconden vanzelf.
        .task(id: confirmation) { await hideConfirmationSoon() }
    }

    private func hideConfirmationSoon() async {
        guard confirmation != nil else { return }
        do {
            try await Task.sleep(nanoseconds: 4_000_000_000)
        } catch {
            return
        }
        withAnimation(Theme.motion) { confirmation = nil }
    }

    @ViewBuilder
    private var acceleratorsBlock: some View {
        let d = store.data
        let now = store.now
        let inputs = d.goalInputs(for: goal, current: now)
        let baseline = Growth.monthsToReach(target: inputs.target, start: inputs.start,
                                            monthly: inputs.monthly, annualReturn: inputs.effectiveReturn)
        let list = d.accelerators(for: goal, current: now)
        // Wat al is toegepast (voor dit doel of een ander) telt niet meer mee in de berekening: het zit al in je gegevens.
        let locked = lockedRecords(in: list, data: d, current: now)
        let chosen = list.filter { selected.contains($0.id) && locked[$0.id] == nil }
        let change = d.combine(chosen)
        let scenario = d.scenarioMonths(inputs, change: change)

        GlassBlock(title: "Versnellers", symbol: "bolt.fill", subtitle: "Op basis van jouw gegevens") {
            if let confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .tile(tint: Theme.positive)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if baseline == 0 {
                Label("Je hebt dit doel al bereikt.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            } else if list.isEmpty {
                Text(emptyText(data: d))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                resultRow(baseline: baseline, scenario: scenario, hasSelection: !chosen.isEmpty)
                if !chosen.isEmpty {
                    GoalCurveChart(curves: d.goalCurves(for: goal, change: change,
                                                        months: horizon(baseline: baseline, scenario: scenario), current: now,
                                                        today: store.today),
                                   start: now)
                        .transition(.opacity)
                }
                VStack(spacing: 8) {
                    ForEach(list) { acc in
                        AcceleratorRow(accelerator: acc,
                                       isOn: selected.contains(acc.id) && locked[acc.id] == nil,
                                       isApplied: locked[acc.id]?.goalID == goal.id,
                                       appliedElsewhere: elsewhereName(locked[acc.id], data: d),
                                       toggle: { toggle(acc.id) },
                                       apply: { prepareApply(acc) })
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                ChipGrid {
                    ChipButton(title: "Alles kiezen", symbol: "checkmark.circle") {
                        withAnimation(Theme.motion) { selected = Set(list.filter { locked[$0.id] == nil }.map(\.id)) }
                    }
                    ChipButton(title: "Niets kiezen", symbol: "circle") {
                        withAnimation(Theme.motion) { selected = [] }
                    }
                }
                Text("Tik op de versnellers die je wilt combineren. De berekening telt ze bij elkaar op. Met Toepassen voer je een versneller echt door in je gegevens; je kunt hem daarna herstellen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if baseline != 0, d.hasOneOffExpensesWorthCutting(current: now) {
                Text("Uitgaven worden hier alleen voorgesteld als ze terugkerend zijn, want een eenmalige uitgave levert geen vaste maandinleg op. Zet bij een uitgave \"Terugkerend, elke maand\" aan om hem hier te zien.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(Theme.motion, value: selected)
        .animation(Theme.motion, value: confirmation)
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
        withAnimation(Theme.quickMotion) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        }
    }

    /// Opent de bevestiging met precies wat er verandert.
    private func prepareApply(_ acc: Accelerator) {
        let plan = store.data.applyPlan(acc, for: goal, current: store.now)
        pending = PendingApplication(accelerator: acc, plan: plan)
    }

    /// Voert de versneller door in je gegevens. Alles wat uit de gegevens wordt afgeleid, volgt vanzelf.
    private func apply(_ acc: Accelerator) {
        let target = goal
        let current = store.now
        let date = Date()
        var appliedTitle: String?
        withAnimation(Theme.motion) {
            store.mutate { data in
                appliedTitle = data.apply(acc, for: target, current: current, now: date)?.title
            }
            selected.remove(acc.id)
            if let appliedTitle { confirmation = "Toegepast: \(appliedTitle)" }
        }
    }

    private func horizon(baseline: Int?, scenario: Int?) -> Int {
        var h = max(baseline ?? 0, scenario ?? 0)
        if baseline == nil && scenario == nil { h = 120 }
        return min(600, max(24, h + 12))
    }

    @ViewBuilder
    private func resultRow(baseline: Int?, scenario: Int?, hasSelection: Bool) -> some View {
        HStack(spacing: 8) {
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
        return isOn ? Theme.accent : Color.secondary
    }

    /// De jaarlijkse verhoging bestaat niet in de app: toepassen verhoogt de inleg eenmalig. De knop zegt dat.
    private var applyTitle: String {
        AcceleratorKind(id: accelerator.id) == .stepUp ? "Eenmalig toepassen" : "Toepassen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: leadingSymbol)
                        .font(.title3)
                        .foregroundStyle(leadingColor)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(accelerator.title, systemImage: accelerator.symbol)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            if !isLocked {
                                Text(AcceleratorBadge.text(for: accelerator))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.positive)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        Text(accelerator.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLocked)

            if isApplied {
                Label("Toegepast. Herstel hem hieronder als je het weer terug wilt.", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            } else if let appliedElsewhere {
                Label("Al toegepast voor \(appliedElsewhere). Herstel hem eerst om hem hier toe te passen.", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            } else if let apply {
                ChipButton(title: applyTitle, symbol: "checkmark.circle", action: apply)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile(tint: isOn ? Theme.accent : nil)
        .animation(Theme.quickMotion, value: isOn)
        .animation(Theme.motion, value: isLocked)
    }
}

// MARK: - Bevestiging

/// Laat precies zien wat er verandert (oud naar nieuw) en vraagt om bevestiging.
struct AcceleratorApplySheet: View {
    let accelerator: Accelerator
    let plan: AcceleratorPlan
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassBlock(title: accelerator.title, symbol: accelerator.symbol,
                           subtitle: plan.isEmpty ? "Hier valt niets te doen" : "Dit verandert er in je gegevens") {
                    if plan.isEmpty {
                        Label(plan.message ?? "Hier valt niets te doen.", systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        if let headline = plan.headline {
                            Label(headline, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .tile(tint: Theme.warning)
                        }
                        VStack(spacing: 8) {
                            ForEach(plan.lines) { line in
                                AcceleratorPlanRow(line: line)
                            }
                        }
                        HStack(spacing: 8) {
                            StatTile(title: "Looptijd nu", value: durationText(plan.monthsBefore))
                            StatTile(title: "Looptijd daarna", value: durationText(plan.monthsAfter),
                                     color: Theme.positive, caption: savedText)
                        }
                        ForEach(NumberedText.list(plan.notes)) { note in
                            Text(note.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Je kunt dit altijd herstellen: dan staat alles weer zoals het was.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ChipGrid {
                        ChipButton(title: "Annuleren", symbol: "xmark") { dismiss() }
                        if !plan.isEmpty {
                            ChipButton(title: "Toepassen", symbol: "checkmark.circle.fill") {
                                onApply()
                                dismiss()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: Theme.pageMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background { MeshBackground() }
            .navigationTitle("Versneller toepassen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: line.symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                if line.oldValue != nil || line.newValue != nil {
                    HStack(spacing: 6) {
                        if let old = line.oldValue {
                            Text(old).foregroundStyle(.secondary)
                        }
                        if line.oldValue != nil && line.newValue != nil {
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let new = line.newValue {
                            Text(new)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.positive)
                        }
                    }
                    .font(.subheadline)
                }
                if !line.detail.isEmpty {
                    Text(line.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
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
            GlassBlock(title: "Toegepast", symbol: "arrow.uturn.backward.circle",
                       subtitle: "Zet ze terug, de nieuwste eerst") {
                VStack(spacing: 8) {
                    ForEach(list) { record in
                        AppliedAcceleratorRow(record: record, goalName: goalName(of: record),
                                              blockedBy: waitingFor(record, data: d)) {
                            restoring = record
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                if list.count > 1, restorable > 0 {
                    ChipButton(title: "Alles herstellen", symbol: "arrow.uturn.backward.circle") {
                        restoringAll = true
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .confirmationDialog("Dit herstellen?", isPresented: restoringBinding, titleVisibility: .visible,
                                presenting: restoring) { record in
                Button("Herstel", role: .destructive) { restore(record) }
                Button("Annuleren", role: .cancel) {}
            } message: { record in
                Text("\(record.title) gaat terug zoals het was. Wat je daarna in andere dingen veranderde, blijft staan. Heb je ditzelfde bedrag of dezelfde uitgave daarna zelf nog aangepast, dan gaat ook dat terug.")
            }
            .confirmationDialog("Alles herstellen?", isPresented: $restoringAll, titleVisibility: .visible) {
                Button("Herstel alles", role: .destructive) { restoreAll() }
                Button("Annuleren", role: .cancel) {}
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
        withAnimation(Theme.motion) {
            store.mutate { data in
                _ = data.restoreAccelerator(id)
            }
        }
    }

    private func restoreAll() {
        let scope = goalID
        withAnimation(Theme.motion) {
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
}

struct AppliedAcceleratorRow: View {
    let record: AppliedAccelerator
    var goalName: String? = nil
    /// Titel van de nieuwere toepassing die eerst hersteld moet worden. Dan staat er geen Herstel-knop.
    var blockedBy: String? = nil
    let onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(record.title, systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Text(Fmt.date(record.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let goalName {
                Text("Voor \(goalName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(NumberedText.list(record.summary)) { line in
                Text(line.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let blockedBy {
                Label("Herstel eerst: \(blockedBy)", systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ChipButton(title: "Herstel", symbol: "arrow.uturn.backward", action: onRestore)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tile()
    }
}

// MARK: - Grafiek

/// Basis (nu) tegenover het scenario met gekozen versnellers.
struct GoalCurveChart: View {
    let curves: GoalCurves
    let start: YearMonth

    private struct Item: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
    }

    private var items: [Item] {
        let count = curves.baseline.count
        let step = max(1, count / 100)
        var list: [Item] = []
        var i = 0
        while i < count {
            let date = start.adding(i).firstDay
            list.append(Item(id: "b\(i)", date: date, value: curves.baseline[i], series: "Nu"))
            if i < curves.scenario.count {
                list.append(Item(id: "s\(i)", date: date, value: curves.scenario[i], series: "Met versnellers"))
            }
            i += step
        }
        return list
    }

    var body: some View {
        Chart {
            ForEach(items) { item in
                LineMark(x: .value("Maand", item.date), y: .value("Waarde", item.value),
                         series: .value("Reeks", item.series))
                    .foregroundStyle(by: .value("Reeks", item.series))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("Doel", curves.scenarioTarget))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Doel").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale(domain: ["Nu", "Met versnellers"], range: [Color.gray, Theme.accent])
        .chartAxes(shown: true)
        .frame(height: 190)
        .animation(Theme.motion, value: curves)
    }
}

// MARK: - Pagina

/// Eigen pagina voor het Versnellers-blok: kies een doel en bekijk wat het sneller maakt.
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
                    GlassBlock(title: "Eerst een doel") {
                        EmptyHint(symbol: "flag.checkered", title: "Maak een doel",
                                  message: "Versnellers laten zien wat je doel sneller maakt. Daarvoor heeft de app een doel nodig.",
                                  actionTitle: "Doel maken") { router.toolsPath.append(.goals) }
                    }
                } else if let goal {
                    if d.goals.count > 1 {
                        GlassBlock(title: "Voor welk doel?", symbol: "flag.checkered") {
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
        }
    }
}
