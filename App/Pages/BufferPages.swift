import SwiftUI

/// "2,5 maanden", "1 maand".
private func bufferMonthsText(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    let unit = rounded == 1 ? "maand" : "maanden"
    return "\(Fmt.input(rounded, maxDigits: 1)) \(unit)"
}

// MARK: - De pagina

/// De noodbuffer als rekenpagina: de uitkomst met het verloop bovenaan, daaronder de invoer in vier blokken en de spaarpot.
struct BufferPage: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        let account = accountPrefsID(auth: auth, cloud: cloud)
        BufferPageContent(key: AccountPrefs.key(BufferSetup.storageKey, account: account))
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

    var body: some View {
        let d = store.data
        let now = store.now
        // Met het saldo van vandaag (`store.today`): de bank en de spaarpot zoals ze er nu voor staan.
        let input = BufferCalc.inputs(from: d, setup: setup, current: now,
                                      monthlySaving: monthlySaving, fillWithin: SafeInt.clamped(fillMonths, to: 1...60),
                                      today: store.today)
        let result = BufferCalc.calculate(input)

        PageScaffold(title: "Noodbuffer") {
            VStack(spacing: Theme.pageSpacing) {
                resultCard(result, now: now)
                situationCard()
                expensesCard(d, now: now, result: result)
                currentCard(d, now: now, result: result)
                speedCard(d, now: now, result: result)
                potCard(d, result: result)
            }
            .frame(maxWidth: Theme.readableWidth)
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

    // MARK: Uitkomst

    @ViewBuilder
    private func resultCard(_ r: BufferResult, now: YearMonth) -> some View {
        Card(title: "Uitkomst", symbol: "shield.lefthalf.filled", domain: .goals,
             subtitle: "\(r.months) maanden aan noodzakelijke uitgaven") {
            if r.hasTarget {
                resultFigures(r)
            }
            // Zonder doel toont de grafiek zijn eigen lege staat met uitleg.
            TrendChart(model: BufferTrend.model(r, start: now), size: .regular)
        }
    }

    private func resultFigures(_ r: BufferResult) -> some View {
        let statusText: String = r.isFull ? "Doel bereikt" : "Nog \(Fmt.euro(r.gap))"
        let progressText = "\(Fmt.percent(r.progress, digits: 0)) van je doel"
        return VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Doel noodbuffer")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                BigAmount(value: r.target)
            }
            .accessibilityElement(children: .combine)
            ProgressMeter(value: r.progress, tint: r.isFull ? Theme.positive : Theme.accent, style: .bar(height: 10),
                          label: "Voortgang noodbuffer", valueText: Fmt.percent(r.progress, digits: 0))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(progressText)
                    Spacer(minLength: 4)
                    Text(statusText).fontWeight(.semibold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(progressText)
                    Text(statusText).fontWeight(.semibold)
                }
            }
            .font(.footnote)
            .foregroundStyle(r.isFull ? Theme.positive : Color.primary)
            FigureRow {
                StatTile(title: "Nu in noodbuffer", value: Fmt.euro(r.current))
                StatTile(title: "Nog nodig", value: Fmt.euro(r.gap),
                         color: r.isFull ? Theme.positive : Color.primary)
                StatTile(title: "Uitgaven per maand", value: Fmt.euro(r.essentialMonthly))
                StatTile(title: "Dekking nu", value: r.coverageMonths.map { bufferMonthsText($0) } ?? "-")
            }
            coverageSentence(r)
        }
    }

    @ViewBuilder
    private func coverageSentence(_ r: BufferResult) -> some View {
        if let coverage = r.coverageMonths {
            Label("Je noodbuffer dekt nu \(bufferMonthsText(coverage)).",
                  systemImage: r.isFull ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(r.isFull ? Theme.positive : Color.primary)
        }
    }

    // MARK: Situatie

    @ViewBuilder
    private func situationCard() -> some View {
        let advice = setup.situation.recommendation
        Card(title: "Jouw situatie", symbol: "person.2", domain: .goals,
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
            .frame(minHeight: Theme.minTapTarget)
            Toggle("Eigen woning", isOn: bind(\.situation.isHomeowner))
                .frame(minHeight: Theme.minTapTarget)
            adviceNote(advice)
        }
    }

    private func adviceNote(_ advice: BufferRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(advice.lines, id: \.self) { line in
                PlanningFootnote(line)
            }
        }
        .padding(10)
        .tile()
    }

    // MARK: Noodzakelijke uitgaven

    @ViewBuilder
    private func expensesCard(_ d: FinanceData, now: YearMonth, result r: BufferResult) -> some View {
        let overview = d.expenseOverview(in: now)
        let known = overview.fixed + overview.variable > 0
        Card(title: "Noodzakelijke uitgaven", symbol: "cart", domain: .goals,
             subtitle: known ? "Uit je uitgaven van \(Fmt.month(now))" : "Nog geen uitgaven ingevuld") {
            if known {
                knownExpenses(d, now: now, overview: overview, result: r)
            } else {
                PlanningFootnote("Je hebt voor \(Fmt.month(now)) nog geen uitgaven ingevuld. Vul ze in bij Uitgaven, of typ hieronder wat je per maand minstens nodig hebt.")
                ActionLink(title: "Uitgaven invullen", symbol: "creditcard", destination: .expenses)
                NumberRow(title: "Noodzakelijk per maand", value: bind(\.manualEssential))
            }
        }
    }

    @ViewBuilder
    private func knownExpenses(_ d: FinanceData, now: YearMonth, overview: ExpenseOverview, result r: BufferResult) -> some View {
        // Een buffer rekent met een gewone maand: bij een salaris om de zoveel weken of dagen is dat het gemiddelde inkomen
        // per maand (`estimatedMonthlyIncome`), niet de maand met twee uitbetalingen. Bij het maandelijkse schema is het
        // inkomen van deze maand.
        let income: Double = d.estimatedMonthlyIncome(in: now)
        let share = BufferCalc.clampedShare(setup.variableShare)
        let sharePercent = Fmt.percent(share, digits: 0)
        FigureRow {
            StatTile(title: d.salary.isMonthly ? "Inkomen" : "Gemiddeld inkomen", value: Fmt.euro(income))
            StatTile(title: "Vaste uitgaven", value: Fmt.euro(overview.fixed))
            StatTile(title: "Variabele uitgaven", value: Fmt.euro(overview.variable))
        }
        if income > 0 {
            PlanningFootnote("Je uitgaven zijn \(Fmt.percent((overview.fixed + overview.variable) / income, digits: 0)) van je inkomen.")
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Variabel dat je meetelt")
                Spacer(minLength: 8)
                Text(sharePercent).foregroundStyle(Theme.textSecondary)
            }
            Slider(value: bind(\.variableShare), in: 0...1, step: 0.05)
                .accessibilityLabel("Variabel dat je meetelt")
                .accessibilityValue(sharePercent)
        }
        PlanningFootnote("Vast \(Fmt.euro(r.fixedPart)) + \(sharePercent) van variabel \(Fmt.euro(overview.variable)) = \(Fmt.euro(r.essentialMonthly)) per maand.")
    }

    // MARK: Huidige noodbuffer

    @ViewBuilder
    private func currentCard(_ d: FinanceData, now: YearMonth, result r: BufferResult) -> some View {
        let today = store.today
        Card(title: "Wat heb je al?", symbol: "building.columns", domain: .goals, subtitle: "Waar staat je noodbuffer nu") {
            BufferPickerRow(title: "Bron", selection: bind(\.source)) {
                ForEach(BufferSource.allCases) { item in Text(item.title).tag(item) }
            }
            if setup.source.usesPot {
                potChoice(d)
            }
            if setup.source == .manual {
                NumberRow(title: "Huidige noodbuffer", value: bind(\.manualCurrent))
            } else {
                currentFigures(d, now: now, today: today, result: r)
            }
            // Het saldo van vandaag moet bekend zijn: een saldo dat pas later begint zegt niets over nu.
            if setup.source.usesBank && !d.hasBankBalanceNow(current: now, today: today) {
                Label(d.hasBankBalance
                      ? "Je banksaldo van vandaag is nog niet bekend: wat je invulde begint pas later. Tot die tijd telt de bank als 0."
                      : "Je hebt nog geen banksaldo ingevuld bij Bankrekening. Tot die tijd telt de bank als 0.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
        }
    }

    @ViewBuilder
    private func potChoice(_ d: FinanceData) -> some View {
        if d.pots.isEmpty {
            PlanningFootnote("Je hebt nog geen spaarpot. Maak er onderaan een aan.")
        } else {
            BufferPickerRow(title: "Spaarpot", selection: potBinding(d)) {
                ForEach(d.pots) { item in Text(item.name).tag(Optional(item.id)) }
            }
        }
    }

    private func currentFigures(_ d: FinanceData, now: YearMonth, today: Date, result r: BufferResult) -> some View {
        let bank = BufferCalc.bankAmount(in: d, current: now, today: today)
        let chosenPot = BufferCalc.resolvedPot(in: d, preferred: setup.potID)
        let potValue = BufferCalc.potAmount(in: d, setup: setup, current: now, today: today)
        return FigureRow {
            if setup.source.usesBank {
                StatTile(title: "Bankrekening", value: Fmt.euro(bank))
            }
            if setup.source.usesPot, let potItem = chosenPot {
                StatTile(title: potItem.name, value: Fmt.euro(potValue))
            }
            StatTile(title: "Totaal in noodbuffer", value: Fmt.euro(r.current), color: Theme.accent)
        }
    }

    // MARK: Hoe snel

    @ViewBuilder
    private func speedCard(_ d: FinanceData, now: YearMonth, result r: BufferResult) -> some View {
        let defaultSaving = BufferCalc.defaultMonthlySaving(in: d, setup: setup, current: now)
        let isDefault = abs(monthlySaving - defaultSaving) < 0.005
        let rateText = Fmt.percent(d.settings.savingsRate)
        Card(title: "Hoe snel?", symbol: "hourglass", domain: .goals, subtitle: "Wat je spaart bepaalt de tijd") {
            NumberRow(title: "Sparen per maand", value: $monthlySaving)
            Toggle("Spaarrente meerekenen (\(rateText))", isOn: bind(\.useInterest))
                .frame(minHeight: Theme.minTapTarget)
            if !d.salary.isMonthly {
                PlanningFootnote("Het standaard bedrag rekent met een gemiddelde maand, omdat je salaris niet elke maand even vaak binnenkomt.")
            }
            ActionGroup {
                ActionButton(title: "Standaard bedrag", symbol: "arrow.uturn.backward") {
                    monthlySaving = defaultSaving
                }
                .disabled(isDefault)
                ActionButton(title: "Neem benodigd bedrag over", symbol: "equal.circle") {
                    monthlySaving = r.monthlyNeeded
                }
                .disabled(!r.hasTarget || r.isFull)
            }
            fillSentence(r, now: now)
            fillSlider(r)
            if r.hasTarget && !r.isFull {
                StatTile(title: "Nodig per maand", value: Fmt.euro(r.monthlyNeeded),
                         caption: "om binnen \(Fmt.duration(months: r.fillWithin)) klaar te zijn")
            }
        }
    }

    private func fillSlider(_ r: BufferResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Of: alles binnen")
                Spacer(minLength: 8)
                Text(Fmt.duration(months: r.fillWithin)).foregroundStyle(Theme.textSecondary)
            }
            Slider(value: $fillMonths, in: 1...60, step: 1)
                .accessibilityLabel("Alles binnen")
                .accessibilityValue(Fmt.duration(months: r.fillWithin))
        }
    }

    @ViewBuilder
    private func fillSentence(_ r: BufferResult, now: YearMonth) -> some View {
        if !r.hasTarget {
            PlanningFootnote("Vul eerst je uitgaven in, dan weet de app hoeveel noodbuffer je nodig hebt.")
        } else if r.isFull {
            Label("Je noodbuffer is al op niveau. Je hoeft niets meer te sparen.", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.positive)
        } else if let months = r.monthsToFill {
            VStack(alignment: .leading, spacing: 3) {
                Label("Bij \(Fmt.euro(r.monthlySaving)) per maand ben je er over \(Fmt.duration(months: months)).",
                      systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
                PlanningFootnote("Dat is in \(Fmt.month(now.adding(months))).")
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

    // MARK: Spaarpot Noodbuffer

    @ViewBuilder
    private func potCard(_ d: FinanceData, result r: BufferResult) -> some View {
        let existing = BufferCalc.bufferPot(in: d)
        let goalText: String = existing?.goalAmount.map { Fmt.euro($0) } ?? "geen doel"
        let explanation: String = existing == nil
            ? "Maak een spaarpot met dit doelbedrag. Je volgt de voortgang dan ook bij je andere spaarpotten."
            : "Je spaarpot voor de noodbuffer heeft nu \(goalText) als doel. Pas het aan naar het doel van deze berekening."
        let buttonTitle: String = existing == nil
            ? "Maak een spaarpot van dit doel"
            : "Werk de spaarpot bij met dit doel"
        Card(title: "Spaarpot Noodbuffer", symbol: "shield.lefthalf.filled", domain: .goals,
             subtitle: existing == nil ? "Nog niet aangemaakt" : "Bestaat al") {
            PlanningFootnote(explanation)
            ActionButton(title: buttonTitle, symbol: existing == nil ? "plus.circle.fill" : "arrow.triangle.2.circlepath",
                         prominent: true) {
                createOrUpdatePot(target: r.target)
            }
            .disabled(!r.hasTarget)
            if let potMessage {
                Label(potMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            }
        }
    }

    /// Maakt de spaarpot met het doelbedrag, of past het doel van de bestaande pot aan. De pot heet "Buffer": de rekenmotor vindt
    /// hem op die naam (`BufferCalc.bufferPot`), dus de naam blijft zo tot de rekenmotor ook "Noodbuffer" herkent.
    private func createOrUpdatePot(target: Double) {
        let now = store.now
        if let existing = BufferCalc.bufferPot(in: store.data) {
            var updated = existing
            updated.goalAmount = target
            store.mutate { $0.updatePot(updated, current: now) }
            potMessage = "De spaarpot is bijgewerkt: doel \(Fmt.euro(target))."
        } else {
            let pot = Pot(name: "Buffer", symbol: "shield.lefthalf.filled", colorIndex: 0,
                          goalAmount: target, goalDate: nil, monthlyContribution: 0, startMonth: now)
            store.mutate { $0.addPot(pot) }
            potMessage = "Spaarpot gemaakt met een doel van \(Fmt.euro(target)). Verdeel er geld over bij Verdelen."
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
                .foregroundStyle(Theme.textSecondary)
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
