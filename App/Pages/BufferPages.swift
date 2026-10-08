import SwiftUI
import Charts

/// "2,5 maanden", "1 maand".
private func bufferMonthsText(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    let unit = rounded == 1 ? "maand" : "maanden"
    return "\(Fmt.input(rounded, maxDigits: 1)) \(unit)"
}

// MARK: - Blok op de Savings-pagina

/// Samenvatting: doelbuffer, wat er al is, voortgang en hoeveel maanden het dekt.
/// Gebruikt de keuzes die in de calculator zijn bewaard, zodat de cijfers kloppen met de pagina.
struct BufferBlock: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        let accountID: String = auth.currentAccount?.id.uuidString ?? "demo"
        BufferBlockContent(key: BufferSetup.storageKey + "." + accountID)
    }
}

private struct BufferBlockContent: View {
    @Environment(AppStore.self) private var store
    @AppStorage private var storedSetup: String

    init(key: String) {
        _storedSetup = AppStorage(wrappedValue: "", key)
    }

    var body: some View {
        let d = store.data
        let now = store.now
        let setup = BufferSetup.fromJSON(storedSetup) ?? BufferCalc.initialSetup(for: d, current: now)
        let r = BufferCalc.summary(for: d, setup: setup, current: now)
        LinkedBlock(title: "Buffer", symbol: "shield.lefthalf.filled",
                    subtitle: r.hasTarget ? "\(r.months) maanden aan uitgaven" : nil,
                    destination: .buffer) {
            if r.hasTarget {
                BigAmount(value: r.target, font: .system(.title, design: .rounded, weight: .bold))
                ProgressBar(progress: r.progress, tint: r.isFull ? Theme.positive : Theme.accent, height: 10)
                HStack(spacing: 8) {
                    Text("Nu \(Fmt.euroWhole(r.current))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if let coverage = r.coverageMonths {
                        Text("Dekt \(bufferMonthsText(coverage))")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                Text("Vul je uitgaven in, dan rekent de app uit hoeveel buffer bij je past.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - De calculator

struct BufferPage: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        let accountID: String = auth.currentAccount?.id.uuidString ?? "demo"
        BufferPageContent(key: BufferSetup.storageKey + "." + accountID)
    }
}

private struct BufferPageContent: View {
    @Environment(AppStore.self) private var store
    @AppStorage private var storedSetup: String

    init(key: String) {
        _storedSetup = AppStorage(wrappedValue: "", key)
    }

    @State private var setup = BufferSetup()
    @State private var monthlySaving: Double = 0
    @State private var fillMonths: Double = 12
    @State private var didStart = false
    @State private var potMessage: String?

    private let tileColumns = [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)]
    private let chipColumns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        let d = store.data
        let now = store.now
        let input = BufferCalc.inputs(from: d, setup: setup, current: now,
                                      monthlySaving: monthlySaving, fillWithin: Int(fillMonths.rounded()))
        let result = BufferCalc.calculate(input)

        PageScaffold(title: "Buffer") {
            VStack(spacing: Theme.pageSpacing) {
                situationBlock()
                expensesBlock(d, now: now, result: result)
                currentBlock(d, now: now, result: result)
                resultBlock(result)
                speedBlock(d, now: now, result: result)
                chartBlock(result, now: now)
                potBlock(d, result: result)
            }
        }
        .onAppear { startOnce() }
        .onChange(of: setup) { _, newValue in storedSetup = newValue.json }
    }

    // MARK: Begin en bindingen

    /// Eén keer: haal de bewaarde keuzes (of slimme beginwaarden uit de app-gegevens) op.
    private func startOnce() {
        guard !didStart else { return }
        didStart = true
        let d = store.data
        let now = store.now
        let loaded = BufferSetup.fromJSON(storedSetup) ?? BufferCalc.initialSetup(for: d, current: now)
        setup = loaded
        monthlySaving = BufferCalc.defaultMonthlySaving(in: d, setup: loaded, current: now)
    }

    private func bind<T>(_ keyPath: WritableKeyPath<BufferSetup, T>) -> Binding<T> {
        Binding(get: { setup[keyPath: keyPath] },
                set: { newValue in setup[keyPath: keyPath] = newValue })
    }

    private func potBinding(_ d: FinanceData) -> Binding<UUID?> {
        Binding(get: { BufferCalc.resolvedPot(in: d, preferred: setup.potID)?.id },
                set: { newValue in setup.potID = newValue })
    }

    // MARK: Situatie

    @ViewBuilder
    private func situationBlock() -> some View {
        let advice = setup.situation.recommendation
        GlassBlock(title: "Jouw situatie", symbol: "person.2.fill",
                   subtitle: "Aanbevolen: \(advice.months) maanden") {
            BufferPickerRow(title: "Werk", selection: bind(\.situation.employment)) {
                ForEach(BufferEmployment.allCases) { item in Text(item.title).tag(item) }
            }
            BufferPickerRow(title: "Huishouden", selection: bind(\.situation.household)) {
                ForEach(BufferHousehold.allCases) { item in Text(item.title).tag(item) }
            }
            Stepper(value: bind(\.situation.children), in: 0...10) {
                Text("Kinderen: \(setup.situation.children)")
            }
            Toggle("Eigen woning", isOn: bind(\.situation.isHomeowner))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(advice.lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .tile()
        }
    }

    // MARK: Noodzakelijke uitgaven

    @ViewBuilder
    private func expensesBlock(_ d: FinanceData, now: YearMonth, result r: BufferResult) -> some View {
        let overview = d.expenseOverview(in: now)
        let known = overview.fixed + overview.variable > 0
        let income: Double = d.income(in: now)
        let share = BufferCalc.clampedShare(setup.variableShare)
        let sharePercent = Fmt.percent(share, digits: 0)
        GlassBlock(title: "Noodzakelijke uitgaven", symbol: "cart.fill",
                   subtitle: known ? "Uit je uitgaven van \(Fmt.month(now))" : "Nog geen uitgaven ingevuld") {
            if known {
                LazyVGrid(columns: tileColumns, spacing: 8) {
                    StatTile(title: "Inkomen", value: Fmt.euroWhole(income))
                    StatTile(title: "Vaste uitgaven", value: Fmt.euroWhole(overview.fixed))
                    StatTile(title: "Variabele uitgaven", value: Fmt.euroWhole(overview.variable))
                }
                if income > 0 {
                    Text("Je uitgaven zijn \(Fmt.percent((overview.fixed + overview.variable) / income, digits: 0)) van je inkomen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Variabel dat je meetelt")
                        Spacer(minLength: 8)
                        Text(sharePercent).foregroundStyle(.secondary)
                    }
                    Slider(value: bind(\.variableShare), in: 0...1, step: 0.05)
                }
                Text("Vast \(Fmt.euro(r.fixedPart)) + \(sharePercent) van variabel \(Fmt.euro(overview.variable)) = \(Fmt.euro(r.essentialMonthly)) per maand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Je hebt voor \(Fmt.month(now)) nog geen uitgaven ingevuld. Vul ze in bij Uitgaven, of typ hieronder wat je per maand minstens nodig hebt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NumberRow(title: "Noodzakelijk per maand", value: bind(\.manualEssential))
            }
        }
    }

    // MARK: Huidige buffer

    @ViewBuilder
    private func currentBlock(_ d: FinanceData, now: YearMonth, result r: BufferResult) -> some View {
        let bank = BufferCalc.bankAmount(in: d, current: now)
        let chosenPot = BufferCalc.resolvedPot(in: d, preferred: setup.potID)
        let potValue = BufferCalc.potAmount(in: d, setup: setup, current: now)
        GlassBlock(title: "Wat heb je al?", symbol: "building.columns.fill", subtitle: "Waar staat je buffer nu") {
            BufferPickerRow(title: "Bron", selection: bind(\.source)) {
                ForEach(BufferSource.allCases) { item in Text(item.title).tag(item) }
            }
            if setup.source.usesPot {
                if d.pots.isEmpty {
                    Text("Je hebt nog geen spaarpot. Maak er onderaan een aan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    BufferPickerRow(title: "Spaarpot", selection: potBinding(d)) {
                        ForEach(d.pots) { item in Text(item.name).tag(Optional(item.id)) }
                    }
                }
            }
            if setup.source == .manual {
                NumberRow(title: "Huidige buffer", value: bind(\.manualCurrent))
            } else {
                LazyVGrid(columns: tileColumns, spacing: 8) {
                    if setup.source.usesBank {
                        StatTile(title: "Bankrekening", value: Fmt.euroWhole(bank))
                    }
                    if setup.source.usesPot, let potItem = chosenPot {
                        StatTile(title: potItem.name, value: Fmt.euroWhole(potValue))
                    }
                    StatTile(title: "Totaal in buffer", value: Fmt.euroWhole(r.current), color: Theme.accent)
                }
            }
            if setup.source.usesBank && !d.hasBankBalance {
                Text("Je hebt nog geen banksaldo ingevuld bij Bankrekening. Tot die tijd telt de bank als 0.")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    // MARK: Uitkomst

    @ViewBuilder
    private func resultBlock(_ r: BufferResult) -> some View {
        let statusText: String = r.isFull ? "Doel bereikt" : "Nog \(Fmt.euroWhole(r.gap))"
        GlassBlock(title: "Jouw buffer", symbol: "shield.lefthalf.filled",
                   subtitle: "\(r.months) maanden aan noodzakelijke uitgaven",
                   tint: Theme.olive.opacity(0.3)) {
            if r.hasTarget {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Doelbuffer").font(.caption).foregroundStyle(.secondary)
                    BigAmount(value: r.target)
                }
                ProgressBar(progress: r.progress, tint: r.isFull ? Theme.positive : Theme.accent, height: 10)
                HStack(spacing: 8) {
                    Text("\(Fmt.percent(r.progress, digits: 0)) van je doel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(r.isFull ? Theme.positive : Color.primary)
                }
                LazyVGrid(columns: tileColumns, spacing: 8) {
                    StatTile(title: "Nu in buffer", value: Fmt.euroWhole(r.current))
                    StatTile(title: "Nog nodig", value: Fmt.euroWhole(r.gap),
                             color: r.isFull ? Theme.positive : Color.primary)
                    StatTile(title: "Uitgaven per maand", value: Fmt.euroWhole(r.essentialMonthly))
                    StatTile(title: "Dekking nu", value: r.coverageMonths.map { bufferMonthsText($0) } ?? "-")
                }
                coverageSentence(r)
            } else {
                EmptyHint(symbol: "shield.lefthalf.filled", title: "Nog geen doel",
                          message: "Vul je uitgaven in, dan rekent de app uit hoeveel buffer bij je past.")
            }
        }
    }

    @ViewBuilder
    private func coverageSentence(_ r: BufferResult) -> some View {
        if let coverage = r.coverageMonths {
            Label("Je buffer dekt nu \(bufferMonthsText(coverage)).",
                  systemImage: r.isFull ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(r.isFull ? Theme.positive : Color.primary)
        }
    }

    // MARK: Hoe snel

    @ViewBuilder
    private func speedBlock(_ d: FinanceData, now: YearMonth, result r: BufferResult) -> some View {
        let defaultSaving = BufferCalc.defaultMonthlySaving(in: d, setup: setup, current: now)
        let isDefault = abs(monthlySaving - defaultSaving) < 0.005
        let rateText = Fmt.percent(d.settings.savingsRate)
        GlassBlock(title: "Hoe snel?", symbol: "hourglass", subtitle: "Wat je spaart bepaalt de tijd") {
            NumberRow(title: "Sparen per maand", value: $monthlySaving)
            Toggle("Spaarrente meerekenen (\(rateText))", isOn: bind(\.useInterest))
            // Even grote knoppen: naast elkaar als er ruimte is, anders onder elkaar.
            LazyVGrid(columns: chipColumns, spacing: 10) {
                ChipButton(title: "Standaard bedrag", symbol: "arrow.uturn.backward") {
                    monthlySaving = defaultSaving
                }
                .disabled(isDefault)
                ChipButton(title: "Gebruik benodigd", symbol: "equal.circle") {
                    monthlySaving = r.monthlyNeeded
                }
                .disabled(!r.hasTarget || r.isFull)
            }
            fillSentence(r, now: now)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Of: alles binnen")
                    Spacer(minLength: 8)
                    Text(Fmt.duration(months: r.fillWithin)).foregroundStyle(.secondary)
                }
                Slider(value: $fillMonths, in: 1...60, step: 1)
            }
            if r.hasTarget && !r.isFull {
                StatTile(title: "Nodig per maand", value: Fmt.euro(r.monthlyNeeded),
                         caption: "om binnen \(Fmt.duration(months: r.fillWithin)) klaar te zijn")
            }
        }
    }

    @ViewBuilder
    private func fillSentence(_ r: BufferResult, now: YearMonth) -> some View {
        if !r.hasTarget {
            Text("Vul eerst je uitgaven in, dan weet de app hoeveel buffer je nodig hebt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if r.isFull {
            Label("Je buffer is al op niveau. Je hoeft niets meer te sparen.", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.positive)
        } else if let months = r.monthsToFill {
            VStack(alignment: .leading, spacing: 3) {
                Label("Bij \(Fmt.euro(r.monthlySaving)) per maand ben je er over \(Fmt.duration(months: months)).",
                      systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
                Text("Dat is in \(Fmt.month(now.adding(months))).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            let message: String = r.monthlySaving > 0
                ? "Met dit bedrag haal je je doel niet binnen 100 jaar."
                : "Vul in hoeveel je per maand kunt sparen."
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)
        }
    }

    // MARK: Grafiek

    @ViewBuilder
    private func chartBlock(_ r: BufferResult, now: YearMonth) -> some View {
        GlassBlock(title: "Verloop", symbol: "chart.xyaxis.line", subtitle: "Je buffer tegenover je doel") {
            if r.hasTarget {
                BufferChart(points: BufferCalc.series(r, start: now))
            } else {
                Text("Zodra je uitgaven bekend zijn, zie je hier hoe je buffer groeit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Spaarpot Buffer

    @ViewBuilder
    private func potBlock(_ d: FinanceData, result r: BufferResult) -> some View {
        let existing = BufferCalc.bufferPot(in: d)
        let goalText: String = existing?.goalAmount.map { Fmt.euroWhole($0) } ?? "geen doel"
        let explanation: String = existing == nil
            ? "Maak een spaarpot met dit doelbedrag. Je volgt de voortgang dan ook bij je andere spaarpotten."
            : "Je spaarpot Buffer heeft nu \(goalText) als doel. Pas het aan naar het doel van deze calculator."
        let buttonTitle: String = existing == nil
            ? "Maak spaarpot Buffer van dit doel"
            : "Werk spaarpot Buffer bij met dit doel"
        GlassBlock(title: "Spaarpot Buffer", symbol: "shield.lefthalf.filled",
                   subtitle: existing == nil ? "Nog niet aangemaakt" : "Bestaat al") {
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                createOrUpdatePot(target: r.target)
            } label: {
                Label(buttonTitle, systemImage: existing == nil ? "plus.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            }
            .glassButton(prominent: true)
            .disabled(!r.hasTarget)
            if let potMessage {
                Text(potMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.positive)
            }
        }
    }

    /// Maakt de spaarpot Buffer met het doelbedrag, of past het doel van de bestaande pot aan.
    private func createOrUpdatePot(target: Double) {
        let now = store.now
        if let existing = BufferCalc.bufferPot(in: store.data) {
            var updated = existing
            updated.goalAmount = target
            store.mutate { $0.updatePot(updated, current: now) }
            potMessage = "Spaarpot Buffer is bijgewerkt: doel \(Fmt.euroWhole(target))."
        } else {
            let pot = Pot(name: "Buffer", symbol: "shield.lefthalf.filled", colorIndex: 0,
                          goalAmount: target, goalDate: nil, monthlyContribution: 0, startMonth: now)
            store.mutate { $0.addPot(pot) }
            potMessage = "Spaarpot Buffer is gemaakt met een doel van \(Fmt.euroWhole(target)). Verdeel er geld over bij Verdelen."
        }
    }
}

// MARK: - Kleine onderdelen

/// Keuzemenu met de titel erboven, zodat het ook op een smal scherm past.
private struct BufferPickerRow<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BufferChartItem: Identifiable {
    let id: String
    let date: Date
    let kind: String
    let value: Double
}

/// Doellijn (gestippeld) en verwachte buffer per maand.
struct BufferChart: View {
    let points: [BufferPoint]
    var height: CGFloat = 200

    static let targetName = "Doelbuffer"
    static let projectedName = "Verwachte buffer"

    private var items: [BufferChartItem] {
        var list: [BufferChartItem] = []
        for p in points {
            let date = p.month.firstDay
            list.append(BufferChartItem(id: p.id + "-doel", date: date, kind: BufferChart.targetName, value: p.target))
            list.append(BufferChartItem(id: p.id + "-buffer", date: date, kind: BufferChart.projectedName, value: p.projected))
        }
        return list
    }

    private var topValue: Double {
        var top = 1.0
        for p in points { top = max(top, p.target, p.projected) }
        return top * 1.05
    }

    var body: some View {
        Chart(items) { item in
            LineMark(x: .value("Maand", item.date), y: .value("Bedrag", item.value))
                .foregroundStyle(by: .value("Soort", item.kind))
                .lineStyle(StrokeStyle(lineWidth: 2.5, dash: item.kind == BufferChart.targetName ? [6, 4] : []))
        }
        .chartForegroundStyleScale(domain: [BufferChart.targetName, BufferChart.projectedName],
                                   range: [Theme.warning, Theme.accent])
        .chartYScale(domain: 0...topValue)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Fmt.compact(v)).font(.caption2) }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: height)
        .accessibilityLabel("Grafiek van je buffer tegenover je doel")
    }
}
