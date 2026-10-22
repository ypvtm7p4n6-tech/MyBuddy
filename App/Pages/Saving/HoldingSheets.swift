import SwiftUI

// De bladen van een belegging: de waarde bijwerken en de belegging toevoegen of bewerken. Beide hebben `hasChanges`: met niet-bewaarde
// invoer is veeg-om-te-sluiten uit en vraagt "Annuleer" om bevestiging. Wat "Bewaar" met de gegevens doet staat zonder SwiftUI in
// `HoldingForm.save` (App/UI/PotDisplay.swift), met tests.

// MARK: - Waarde bijwerken

/// De waarde van een belegging bijwerken: een waarde-update van vandaag.
struct ValueUpdateSheet: View {
    let holding: Holding
    @Environment(AppStore.self) private var store
    @State private var value = 0.0
    @State private var invested = 0.0
    /// De beginwaarden van het formulier, om te weten of er iets is veranderd.
    @State private var startValue = 0.0
    @State private var startInvested = 0.0

    private var hasChanges: Bool {
        value != startValue || invested != startInvested
    }

    var body: some View {
        SheetScaffold(title: "Waarde bijwerken", canSave: value >= 0, hasChanges: hasChanges, onSave: { save() }) {
            Section {
                NumberRow(title: "Waarde nu", value: $value)
                NumberRow(title: "Totaal ingelegd", value: $invested)
            } footer: {
                Text("Elke waarde-update wordt een punt in de groeigrafiek. De winst is de waarde min wat je hebt ingelegd.")
            }
        }
        .onAppear {
            let state = store.data.holdingStateNow(holding, current: store.now, today: store.today)
            value = state?.value ?? 0
            invested = state?.invested ?? holding.investedTotal
            startValue = value
            startInvested = invested
        }
    }

    private func save() {
        let id = holding.id
        let v = value
        let i = invested
        store.mutate { $0.addSnapshot(holdingID: id, value: v, invested: i) }
    }
}

// MARK: - Een belegging toevoegen of bewerken

/// Belegging toevoegen of bewerken, met zoeken op naam of ticker. Met "Belegd sinds", "Totaal ingelegd" en de inleg tekent de app
/// de groei zonder dat je een waarde invult (een geschatte lijn); met "Huidige waarde" krijg je de echte waarde.
struct HoldingEditSheet: View {
    let holding: Holding?

    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var kind: HoldingKind = .etf
    @State private var ticker = ""
    @State private var units = 0.0
    @State private var invested = 0.0
    /// De huidige waarde die je intikt. Leeg (0) laat de waarde zoals ze is: bij een nieuwe belegging een lijn uit je inleg, bij
    /// een gevolgde belegging koers maal aantal zodra de koers binnen is.
    @State private var manualValue = 0.0
    @State private var startMonth = YearMonth.current()
    @State private var expectedReturn = HoldingKind.etf.defaultReturn
    @State private var annualCost = HoldingKind.etf.defaultCost
    @State private var monthly = 0.0
    // Inleg: een vast bedrag (`monthly`) of een percentage van het inkomen (0...100, twee decimalen).
    @State private var mode: ContributionMode = .fixed
    @State private var percent = 0.0
    @State private var basis: IncomeBasis = .salary
    /// Eigen overschrijfdag voor de inleg. nil = je salarisdag.
    @State private var transferDay: Int?

    @State private var query = ""
    @State private var results: [SymbolMatch] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var preview: String?
    @State private var loaded = false
    /// De waarden vlak na het laden, om te weten of er iets is veranderd.
    @State private var loadedSignature: String?
    /// Vaste id voor een nieuwe belegging, zodat de voorvertoning van de waarschuwingen en het bewaren dezelfde belegging zijn.
    @State private var draftID = UUID()

    private var hasTicker: Bool { !ticker.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Alle invoer in een tekst: gelijk aan die van vlak na het laden betekent dat er niets is veranderd.
    private var signature: String {
        let parts: [String] = [
            name, kind.rawValue, ticker, String(units), String(invested), String(manualValue), startMonth.key,
            String(expectedReturn), String(annualCost), String(monthly), String(describing: mode), String(percent),
            String(describing: basis), String(describing: transferDay)
        ]
        return parts.joined(separator: "|")
    }

    private var hasChanges: Bool {
        guard let loadedSignature else { return false }
        return loadedSignature != signature
    }

    var body: some View {
        SheetScaffold(title: holding == nil ? "Belegging toevoegen" : "Belegging bewerken",
                      canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                      hasChanges: hasChanges,
                      onSave: { save() }) {
            nameSection
            quoteSection
            amountsSection
            expectationSection
        }
        .task(id: query) { await search() }
        .onChange(of: kind) { _, newKind in
            if holding == nil && loaded {
                expectedReturn = newKind.defaultReturn
                annualCost = newKind.defaultCost
            }
        }
        .onAppear { load() }
    }

    // MARK: Naam en soort

    private var nameSection: some View {
        Section("Naam en soort") {
            TextField("Bijvoorbeeld Wereld ETF", text: $name)
            Picker("Soort", selection: $kind) {
                ForEach(HoldingKind.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        }
    }

    // MARK: Live koers

    private var quoteSection: some View {
        Section {
            searchFields
            tickerField
            if hasTicker {
                tickerFields
            }
        } header: {
            Text("Live koers")
        } footer: {
            Text("Met een ticker en een aantal haalt de app de koers op (Yahoo Finance) en rekent om naar euro. Voorbeelden: VWCE.DE, AAPL, BTC-EUR.")
        }
    }

    /// Het zoekveld met de voortgang, een eventuele fout en de treffers.
    @ViewBuilder
    private var searchFields: some View {
        TextField("Zoek op naam of ticker, bijv. VWCE of bitcoin", text: $query)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            #endif
        if searching {
            HStack {
                ProgressView().controlSize(.small)
                Text("Zoeken…").foregroundStyle(Theme.textSecondary)
            }
        }
        if let searchError {
            Text(searchError).font(.footnote).foregroundStyle(Theme.negative)
        }
        ForEach(results.prefix(6)) { match in
            resultRow(match)
        }
    }

    private var tickerField: some View {
        TextField("Ticker (laat leeg voor handmatige waarde)", text: $ticker)
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            #endif
    }

    private func resultRow(_ match: SymbolMatch) -> some View {
        Button { choose(match) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(match.name)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text([match.symbol, match.exchange, match.type].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
        }
    }

    @ViewBuilder
    private var tickerFields: some View {
        NumberRow(title: "Aantal stuks", value: $units, unit: .plain("st."), maxDigits: 6)
        if HoldingForm.needsUnitsHint(ticker: ticker, units: units) {
            Text(HoldingForm.unitsHint)
                .font(.footnote)
                .foregroundStyle(Theme.warning)
        }
        if let preview {
            Text(preview)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        Button("Koers controleren") { Task { await fetchPreview() } }
    }

    // MARK: Bedragen

    private var amountsSection: some View {
        Section {
            Picker("Belegd sinds", selection: $startMonth) {
                ForEach(HoldingForm.startMonthChoices(current: store.now, selected: startMonth), id: \.self) { month in
                    Text(Fmt.month(month)).tag(month)
                }
            }
            .pickerStyle(.menu)
            NumberRow(title: "Totaal ingelegd", value: $invested)
            valueFields
            contributionFields
            Toggle("Eigen overschrijfdag", isOn: animated(Binding(
                get: { transferDay != nil },
                set: { on in transferDay = on ? store.data.salaryDay(in: store.now) : nil }
            )))
            if let day = transferDay {
                Stepper(value: Binding(get: { day }, set: { transferDay = $0 }), in: 1...31) {
                    HStack {
                        Text("Overschrijfdag")
                        Spacer()
                        Text(PotFormat.dayName(day)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        } header: {
            Text("Bedragen")
        } footer: {
            amountsFooter
        }
    }

    /// "Huidige waarde": ook bij een belegging met ticker en bij bewerken. Leeg betekent: de waarde blijft zoals ze is.
    @ViewBuilder
    private var valueFields: some View {
        NumberRow(title: "Huidige waarde", value: $manualValue)
        if let note = currentValueNote {
            Text(note)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        if HoldingForm.isTracked(ticker: ticker, units: units) {
            Text(HoldingForm.trackedValueHint)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Wat de belegging nu waard is (bij een bestaande belegging), onder het veld "Huidige waarde".
    private var currentValueNote: String? {
        guard let existing = holding else { return nil }
        let latest = store.data.holding(existing.id) ?? existing
        return HoldingForm.currentValueNote(store.data.holdingStateNow(latest, current: store.now, today: store.today))
    }

    /// Uitleg onder de bedragen: hoe de lijn zonder waarde ontstaat, hoe de inleg werkt en wanneer ze wordt overgeschreven.
    private var amountsFooter: some View {
        let d = store.data
        let payDay = PotFormat.dayName(d.salaryDay(in: store.now))
        // Bij een salaris om de zoveel weken of dagen is "de salarisdag" de eerste uitbetaling van de maand.
        let payText = d.salary.isMonthly ? "je salarisdag (\(payDay))" : "de eerste salarisdag van de maand (\(payDay))"
        return VStack(alignment: .leading, spacing: 6) {
            Text(HoldingForm.estimateHint)
            if mode == .percentage {
                Text("Een percentage rekent over het inkomen van die maand: gaat je salaris omhoog, dan gaat de inleg vanzelf mee.")
            } else {
                Text("De inleg per maand verschijnt in je maandverdeling.")
            }
            Text("Op de overschrijfdag gaat de inleg van je bankrekening naar de belegging. Zonder eigen dag is dat \(payText). Een verdeling die je voor één maand maakt, kan een eigen dag hebben; die gaat voor.")
        }
    }

    // MARK: Verwachting

    private var expectationSection: some View {
        Section {
            NumberRow(title: "Rendement per jaar", value: $expectedReturn, unit: .percent, maxDigits: 2)
            NumberRow(title: "Kosten per jaar", value: $annualCost, unit: .percent, maxDigits: 2)
        } header: {
            Text("Verwachting")
        } footer: {
            Text("Hiermee rekent de app de toekomst door. Dit is een aanname, geen belofte.")
        }
    }

    // MARK: Inleg

    /// De inleg: een vast bedrag of een percentage van je inkomen, met de grondslag. Wat het percentage in euro's oplevert
    /// komt uit de rekenmotor (`ContributionPreview`), precies zoals de verdeling het straks uitrekent.
    @ViewBuilder
    private var contributionFields: some View {
        let preview: ContributionPreview.Result? = mode == .percentage
            ? ContributionPreview.resolve(store.data, percent: percent, basis: basis, month: store.now)
            : nil
        ContributionFields(mode: modeBinding, amount: $monthly, percent: $percent, basis: $basis,
                           amountTitle: "Inleg per maand", percentTitle: "Percentage van je inkomen",
                           resolvedAmount: preview?.amount, resolvedNote: preview?.note, footnote: preview?.footnote,
                           subject: name)
        // Samen meer dan 100% van je inkomen, of meer dan er te verdelen is: de motor meldt het al voor je bewaart.
        if mode == .percentage {
            ForEach(ContributionPreview.warnings(store.data, holding: draftHolding(), month: store.now), id: \.message) { warning in
                AllocationWarningLabel(warning: warning)
                    .transition(.opacity)
            }
        }
    }

    private var modeBinding: Binding<ContributionMode> {
        Binding(
            get: { mode },
            set: { newMode in
                withAnimation(reduceMotion ? nil : Theme.motion) {
                    prefill(for: newMode)
                    mode = newMode
                }
            }
        )
    }

    /// Bij een andere inlegwijze begint het veld bij wat de inleg nu is (zie `PotEditSheet.prefill`): zo verspringt de
    /// inleg niet. De rekenmotor doet de omrekening.
    private func prefill(for newMode: ContributionMode) {
        let d = store.data
        let month = store.now
        switch newMode {
        case .percentage:
            if percent == 0, monthly > 0, let start = d.percent(forAmount: monthly, of: basis, in: month) { percent = start }
        case .fixed:
            if monthly == 0, percent > 0 { monthly = d.percentAmount(percent, of: basis, in: month) }
        }
    }

    /// Dezelfde binding, maar een wijziging beweegt zacht (rijen die verschijnen of verdwijnen), tenzij Verlaag beweging aan staat.
    private func animated<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                withAnimation(reduceMotion ? nil : Theme.motion) { binding.wrappedValue = newValue }
            }
        )
    }

    // MARK: Zoeken

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            searchError = nil
            return
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        if Task.isCancelled { return }
        searching = true
        do {
            let found = try await store.searchSymbols(q)
            if Task.isCancelled { return }
            results = found
            searchError = found.isEmpty ? "Niets gevonden. Probeer een andere naam of vul de ticker zelf in." : nil
        } catch {
            if !Task.isCancelled { searchError = "Zoeken mislukt: \(error.localizedDescription)" }
        }
        searching = false
    }

    private func choose(_ match: SymbolMatch) {
        ticker = match.symbol
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = match.name }
        let type = match.type.lowercased()
        if type.contains("etf") || type.contains("fund") {
            kind = .etf
        } else if type.contains("crypto") {
            kind = .crypto
        } else if type.contains("equity") || type.contains("stock") {
            kind = .stocks
        }
        results = []
        query = ""
        Task { await fetchPreview() }
    }

    private func fetchPreview() async {
        let t = ticker.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        preview = "Koers ophalen…"
        do {
            let q = try await store.previewQuote(ticker: t)
            var text = "Koers nu: \(Fmt.euroExact(q.priceEUR))"
            if q.nativeCurrency != "EUR" { text += " (\(Fmt.input(q.nativePrice)) \(q.nativeCurrency))" }
            if units > 0 { text += " · waarde \(Fmt.euro(q.priceEUR * units))" }
            preview = text
        } catch {
            preview = "Koers ophalen mislukt: \(error.localizedDescription)"
        }
    }

    // MARK: Laden en bewaren

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let h = holding {
            name = h.name
            kind = h.kind
            ticker = h.ticker ?? ""
            units = h.units ?? 0
            invested = h.investedTotal
            startMonth = h.startMonth
            expectedReturn = h.expectedReturn
            annualCost = h.annualCost
            monthly = h.monthlyContribution
            mode = h.contributionMode
            percent = h.contributionPercent
            basis = h.contributionBasis
            transferDay = h.transferDay
        } else {
            // Een nieuwe belegging begint in de huidige maand; met een eerdere maand tekent de app de groei vanaf dan.
            startMonth = store.now
        }
        loadedSignature = signature
    }

    /// De belegging zoals hij na bewaren is: voor de voorvertoning en om te bewaren.
    private func draftHolding() -> Holding {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespaces)
        let tracked = !trimmedTicker.isEmpty
        var h = holding ?? Holding(name: "", startMonth: startMonth)
        if holding == nil { h.id = draftID }
        h.name = name.trimmingCharacters(in: .whitespaces)
        h.kind = kind
        h.ticker = tracked ? trimmedTicker : nil
        h.units = tracked && units > 0 ? units : nil
        h.investedTotal = invested.cents
        h.startMonth = startMonth
        h.expectedReturn = expectedReturn
        h.annualCost = annualCost
        h.monthlyContribution = monthly.cents
        h.contributionMode = mode
        // Het percentage zoals de rekenmotor het gebruikt: 0...100 op twee decimalen.
        h.contributionPercent = AllocationMath.cleanPercent(percent)
        h.contributionBasis = basis
        h.transferDay = transferDay
        return h
    }

    private func save() {
        let now = store.now
        let result = draftHolding()
        let isNew = holding == nil
        let entered = manualValue
        store.mutate { HoldingForm.save(result, isNew: isNew, enteredValue: entered, into: &$0, current: now) }
        if result.hasTicker {
            Task { await store.refreshPrices(force: true) }
        }
    }
}
