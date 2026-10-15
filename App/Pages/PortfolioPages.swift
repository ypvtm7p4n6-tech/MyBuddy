import SwiftUI

// MARK: - Beleggingen

struct PortfolioPage: View {
    @Environment(AppStore.self) private var store
    @State private var monthsBack = 12
    @State private var showNew = false
    @State private var showPicker = false

    var body: some View {
        let d = store.data
        let now = store.now
        let value = d.portfolioValue(current: now)
        let invested = d.portfolioInvested(current: now)
        let gain = d.portfolioGain(current: now)
        let series = d.portfolioSeries(from: now.adding(-monthsBack), count: monthsBack + 13, current: now).map { TimePoint($0) }
        let slices = d.valueByKind(current: now)

        PageScaffold(title: "Beleggingen") {
            VStack(spacing: Theme.pageSpacing) {
                if let message = store.priceMessage {
                    NoticeBanner(text: message, symbol: "wifi.exclamationmark")
                }

                GlassBlock(title: "Waarde", symbol: "chart.line.uptrend.xyaxis", tint: Theme.olive.opacity(0.3)) {
                    if d.holdings.isEmpty {
                        EmptyHint(symbol: "chart.line.uptrend.xyaxis", title: "Nog geen beleggingen",
                                  message: "Voeg een ETF, aandeel, crypto of spaarrekening toe.",
                                  actionTitle: "Belegging toevoegen") { showNew = true }
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            BigAmount(value: value)
                            Spacer()
                            if invested > 0 { GainLabel(gain: gain, fraction: gain / invested) }
                        }
                        HStack(spacing: 8) {
                            StatTile(title: "Ingelegd", value: Fmt.euroWhole(invested))
                            StatTile(title: "Rendement", value: Fmt.euroWhole(gain),
                                     color: gain >= 0 ? Theme.positive : Theme.negative)
                            // Wat je verdeling deze maand naar beleggingen stuurt: dezelfde som als "Belegd" in het Overzicht
                            // en bij Verdelen, en de optelling van de "Inleg deze maand" op de pagina van elke belegging.
                            StatTile(title: "Inleg deze maand", value: Fmt.euroWhole(d.investedTotal(in: now)))
                        }
                        priceStatus
                    }
                }

                if !d.holdings.isEmpty {
                    GlassBlock(title: "Groei", symbol: "waveform.path.ecg") {
                        Picker("Terugkijken", selection: $monthsBack) {
                            Text("6 mnd").tag(6)
                            Text("1 jaar").tag(12)
                            Text("3 jaar").tag(36)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        if series.count > 1 {
                            TimeLineChart(points: series, height: 190)
                            Text("Gestippeld is verwacht: je huidige waarde plus geplande inleg en verwacht rendement.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("De grafiek groeit mee zodra er meer meetpunten zijn. Elke keer dat koersen worden vernieuwd of je een waarde bijwerkt, komt er een punt bij.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if slices.count > 1 {
                        GlassBlock(title: "Verdeling", symbol: "chart.pie.fill") {
                            AllocationDonut(slices: slices, height: 170)
                        }
                    }

                    GlassBlock(title: "Mijn beleggingen", symbol: "list.bullet") {
                        VStack(spacing: 10) {
                            ForEach(d.holdings) { h in HoldingRow(holding: h) }
                        }
                        HStack(spacing: 10) {
                            ChipButton(title: "Toevoegen", symbol: "plus") { showNew = true }
                            ChipButton(title: "Kies voor Home", symbol: "slider.horizontal.3") { showPicker = true }
                        }
                    }
                }
            }
        }
        .refreshable { await store.refreshPrices(force: true) }
        .sheet(isPresented: $showNew) { HoldingEditSheet(holding: nil) }
        .sheet(isPresented: $showPicker) { HoldingPickerSheet() }
    }

    @ViewBuilder
    private var priceStatus: some View {
        if store.hasTrackedHoldings {
            HStack(spacing: 8) {
                if store.isRefreshingPrices {
                    ProgressView().controlSize(.small)
                    Text("Koersen ophalen…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "bolt.horizontal.fill").foregroundStyle(Theme.accent).font(.caption)
                    Text(store.lastPriceRefresh.map { "Koersen bijgewerkt \(Fmt.dateTime($0))" } ?? "Koersen worden bij het openen opgehaald")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ChipButton(title: "Koersen vernieuwen", symbol: "arrow.clockwise") {
                Task { await store.refreshPrices(force: true) }
            }
        }
    }
}

struct HoldingRow: View {
    @Environment(AppStore.self) private var store
    let holding: Holding

    var body: some View {
        let state = store.data.holdingStateNow(holding, current: store.now)
        let color = Theme.color(HoldingKind.allCases.firstIndex(of: holding.kind) ?? 0)
        NavigationLink(value: Destination.holding(holding.id)) {
            HStack(spacing: 12) {
                SymbolBadge(symbol: holding.kind.symbol, color: color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(holding.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    // Een inleg als percentage van je inkomen: wat het deze maand is (zoals bij een spaarpot).
                    if let line = ContributionInfo.listLine(store.data, id: holding.id, month: store.now) {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.euro(state?.value ?? 0)).font(.subheadline.weight(.semibold))
                    if let fraction = state?.gainFraction {
                        Text((fraction >= 0 ? "+" : "-") + Fmt.percent(abs(fraction)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(fraction >= 0 ? Theme.positive : Theme.negative)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .tile()
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if holding.isTracked, let t = holding.ticker {
            // De koers is een eenheidsprijs: met centen (een koers van 0,52 is geen "€ 1").
            if let price = holding.lastPrice { return "\(t) · \(Fmt.euroExact(price))" }
            return t
        }
        return holding.kind.title
    }
}

// MARK: - Eén belegging

struct HoldingDetailPage: View {
    let holdingID: UUID
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showValue = false
    @State private var confirmDelete = false
    @State private var history: [PricePoint] = []
    @State private var historyError: String?
    @State private var backfillMessage: String?

    var body: some View {
        if let holding = store.data.holding(holdingID) {
            content(holding)
        } else {
            PageScaffold(title: "Belegging") {
                EmptyHint(symbol: "questionmark.folder", title: "Deze belegging bestaat niet meer")
            }
        }
    }

    @ViewBuilder
    private func content(_ holding: Holding) -> some View {
        let d = store.data
        let now = store.now
        let state = d.holdingStateNow(holding, current: now)
        let snapshots = holding.snapshots.sorted { $0.date > $1.date }
        let valueSeries = d.portfolioSeries(from: now.adding(-12), count: 25, current: now, only: [holding.id]).map { TimePoint($0) }
        let priceSeries = history.enumerated().map { TimePoint(id: "p\($0.offset)", date: $0.element.date, value: $0.element.close, projected: false) }
        let color = Theme.color(HoldingKind.allCases.firstIndex(of: holding.kind) ?? 0)
        // De opbouw van de maandelijkse inleg (een bedrag of een percentage van je inkomen), uit de rekenmotor.
        let contribution = ContributionInfo(d, id: holding.id, month: now)

        PageScaffold(title: holding.name) {
            VStack(spacing: Theme.pageSpacing) {
                GlassBlock(title: holding.kind.title, symbol: holding.kind.symbol, tint: color.opacity(0.28)) {
                    HStack(alignment: .firstTextBaseline) {
                        BigAmount(value: state?.value ?? 0)
                        Spacer()
                        if let state, state.invested > 0 {
                            GainLabel(gain: state.gain, fraction: state.gainFraction)
                        }
                    }
                    HStack(spacing: 8) {
                        StatTile(title: "Ingelegd", value: Fmt.euroWhole(state?.invested ?? 0))
                        StatTile(title: "Rendement", value: Fmt.euroWhole(state?.gain ?? 0),
                                 color: (state?.gain ?? 0) >= 0 ? Theme.positive : Theme.negative)
                    }
                    if holding.isTracked {
                        trackedInfo(holding)
                    }
                }

                if holding.isTracked && !priceSeries.isEmpty {
                    GlassBlock(title: "Koers laatste jaar", symbol: "chart.xyaxis.line") {
                        TimeLineChart(points: priceSeries, tint: color, height: 170)
                    }
                } else if valueSeries.count > 1 {
                    GlassBlock(title: "Waarde", symbol: "chart.xyaxis.line") {
                        TimeLineChart(points: valueSeries, tint: color, height: 170)
                    }
                }
                if let historyError, holding.isTracked {
                    NoticeBanner(text: historyError, symbol: "wifi.exclamationmark")
                }

                GlassBlock(title: "Uitgangspunten", symbol: "slider.horizontal.3") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        StatTile(title: "Verwacht rendement", value: Fmt.percent(holding.expectedReturn))
                        StatTile(title: "Kosten per jaar", value: Fmt.percent(holding.annualCost, digits: 2))
                    }
                    HStack(spacing: 10) {
                        ChipButton(title: "Instellingen", symbol: "pencil") { showEdit = true }
                        if !holding.isTracked {
                            ChipButton(title: "Waarde bijwerken", symbol: "arrow.triangle.2.circlepath") { showValue = true }
                        } else {
                            ChipButton(title: "Historie aanvullen", symbol: "clock.arrow.circlepath") {
                                Task { backfillMessage = await store.backfillHistory(holdingID: holding.id) }
                            }
                        }
                    }
                    if let backfillMessage {
                        Text(backfillMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if holding.isTracked {
                        Text("Historie aanvullen neemt aan dat je het afgelopen jaar evenveel stuks had als nu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassBlock(title: "Inleg", symbol: "calendar", subtitle: "Wat er elke maand naar deze belegging gaat") {
                    // De opbouw van de inleg: de standaardregel (een bedrag of een percentage van je inkomen) en wat daar in
                    // deze maand uit volgt. Alles uit de rekenmotor (`ContributionInfo`).
                    if let contribution {
                        ContributionSummary(info: contribution)
                    }
                    if let note = contribution?.transferNote(to: "van je rekening naar deze belegging") {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    ChipGrid {
                        ChipButton(title: "Inleg aanpassen", symbol: "pencil") { showEdit = true }
                        // De inleg hoort bij deze maand: de verdeelpagina opent op de huidige maand.
                        ChipButton(title: "Verdelen", symbol: "square.split.2x2") {
                            router.showCurrentMonth(store.now)
                            router.open(.distribute)
                        }
                    }
                }

                GlassBlock(title: "Meetpunten", symbol: "list.bullet.rectangle") {
                    if snapshots.isEmpty {
                        Text("Nog geen meetpunten. Werk de waarde bij of ververs de koers.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(snapshots.prefix(24)) { snap in
                            HStack {
                                Text(Fmt.date(snap.date)).font(.subheadline)
                                Spacer()
                                Text(Fmt.euro(snap.value)).font(.subheadline.weight(.semibold))
                                Menu {
                                    Button("Verwijder meetpunt", role: .destructive) {
                                        let hid = holding.id
                                        let sid = snap.id
                                        store.mutate { $0.deleteSnapshot(holdingID: hid, snapshotID: sid) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                            .padding(.vertical, 8)
                            if snap.id != snapshots.prefix(24).last?.id { Divider() }
                        }
                    }
                }

                ChipButton(title: "Belegging verwijderen", symbol: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .task(id: holding.ticker ?? "") { await loadHistory(holding) }
        .sheet(isPresented: $showEdit) { HoldingEditSheet(holding: holding) }
        .sheet(isPresented: $showValue) { ValueUpdateSheet(holding: holding) }
        .confirmationDialog("Deze belegging verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder \(holding.name)", role: .destructive) {
                let id = holding.id
                store.mutate { $0.deleteHolding(id) }
                dismiss()
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            // Wat de belegging nu waard is, verdwijnt uit je vermogen: dat moet je vooraf zien.
            if CentsMath.int(state?.value ?? 0) > 0 {
                Text("De waarde van \(Fmt.euro(state?.value ?? 0)) verdwijnt uit je vermogen. Ook de meetpunten en de geplande inleg verdwijnen.")
            } else {
                Text("Ook de meetpunten en de geplande inleg verdwijnen.")
            }
        }
    }

    @ViewBuilder
    private func trackedInfo(_ holding: Holding) -> some View {
        HStack(spacing: 8) {
            StatTile(title: "Aantal", value: Fmt.input(holding.units ?? 0, maxDigits: 6))
            StatTile(title: "Koers", value: holding.lastPrice.map { Fmt.euroExact($0) } ?? "–",
                     caption: holding.ticker)
        }
        HStack(spacing: 8) {
            if store.isRefreshingPrices {
                ProgressView().controlSize(.small)
            } else if let date = holding.lastPriceDate {
                Text("Bijgewerkt \(Fmt.dateTime(date))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        ChipButton(title: "Koers vernieuwen", symbol: "arrow.clockwise") {
            Task { await store.refreshPrices(force: true) }
        }
    }

    private func loadHistory(_ holding: Holding) async {
        guard holding.isTracked, let ticker = holding.ticker else {
            history = []
            return
        }
        do {
            history = try await store.priceHistory(ticker: ticker, range: "1y", interval: "1d")
            historyError = nil
        } catch {
            historyError = "Koershistorie ophalen mislukt: \(error.localizedDescription)"
        }
    }
}

// MARK: - Sheets

/// Waarde van een handmatige belegging bijwerken.
struct ValueUpdateSheet: View {
    let holding: Holding
    @Environment(AppStore.self) private var store
    @State private var value = 0.0
    @State private var invested = 0.0

    var body: some View {
        SheetScaffold(title: "Waarde bijwerken", canSave: value >= 0, onSave: {
            let id = holding.id
            let v = value
            let i = invested
            store.mutate { $0.addSnapshot(holdingID: id, value: v, invested: i) }
        }) {
            Section {
                NumberRow(title: "Waarde nu", value: $value)
                NumberRow(title: "Totaal ingelegd", value: $invested)
            } footer: {
                Text("Elke update wordt een punt in de groeigrafiek. Het rendement is de waarde min wat je hebt ingelegd.")
            }
        }
        .onAppear {
            let state = store.data.holdingStateNow(holding, current: store.now)
            value = state?.value ?? 0
            invested = state?.invested ?? holding.investedTotal
        }
    }
}

/// Belegging toevoegen of wijzigen, met zoeken op naam of ticker.
struct HoldingEditSheet: View {
    let holding: Holding?

    @Environment(AppStore.self) private var store
    @State private var name = ""
    @State private var kind: HoldingKind = .etf
    @State private var ticker = ""
    @State private var units = 0.0
    @State private var invested = 0.0
    @State private var manualValue = 0.0
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
    /// Vaste id voor een nieuwe belegging, zodat de voorvertoning van de waarschuwingen en het bewaren dezelfde belegging zijn.
    @State private var draftID = UUID()

    private var hasTicker: Bool { !ticker.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SheetScaffold(title: holding == nil ? "Belegging toevoegen" : "Belegging aanpassen",
                      canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                      onSave: { save() }) {
            Section("Naam en soort") {
                TextField("Bijvoorbeeld Wereld ETF", text: $name)
                Picker("Soort", selection: $kind) {
                    ForEach(HoldingKind.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                TextField("Zoek op naam of ticker, bijv. VWCE of bitcoin", text: $query)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                if searching {
                    HStack { ProgressView().controlSize(.small); Text("Zoeken…").foregroundStyle(.secondary) }
                }
                if let searchError {
                    Text(searchError).font(.footnote).foregroundStyle(Theme.negative)
                }
                ForEach(results.prefix(6)) { match in
                    Button { choose(match) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(match.name).foregroundStyle(.primary).lineLimit(1)
                            Text([match.symbol, match.exchange, match.type].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                TextField("Ticker (laat leeg voor handmatige waarde)", text: $ticker)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    #endif
                if hasTicker {
                    NumberRow(title: "Aantal stuks", value: $units, unit: .plain("st."), maxDigits: 6)
                    if let preview {
                        Text(preview).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Koers controleren") { Task { await fetchPreview() } }
                }
            } header: {
                Text("Live koers")
            } footer: {
                Text("Met een ticker en een aantal haalt de app de koers op (Yahoo Finance) en rekent om naar euro. Voorbeelden: VWCE.DE, AAPL, BTC-EUR.")
            }

            Section {
                if !hasTicker && holding == nil {
                    NumberRow(title: "Huidige waarde", value: $manualValue)
                }
                NumberRow(title: "Totaal ingelegd", value: $invested)
                contributionFields
                Toggle("Eigen overschrijfdag", isOn: animated(Binding(
                    get: { transferDay != nil },
                    set: { on in transferDay = on ? store.data.salaryDay(in: store.now) : nil }
                )))
                if let day = transferDay {
                    Stepper(value: Binding(get: { day }, set: { transferDay = $0 }), in: 1...31) {
                        HStack {
                            Text("Overschrijfdag inleg")
                            Spacer()
                            Text(PotFormat.dayName(day)).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Bedragen")
            } footer: {
                moneyFooter
            }

            Section {
                NumberRow(title: "Verwacht rendement per jaar", value: $expectedReturn, unit: .percent, maxDigits: 2)
                NumberRow(title: "Kosten per jaar", value: $annualCost, unit: .percent, maxDigits: 2)
            } header: {
                Text("Verwachting")
            } footer: {
                Text("Hiermee rekent de app de toekomst door. Dit is een aanname, geen belofte.")
            }
        }
        .task(id: query) { await search() }
        .onChange(of: kind) { _, newKind in
            if holding == nil && loaded {
                expectedReturn = newKind.defaultReturn
                annualCost = newKind.defaultCost
            }
        }
        .onAppear {
            guard !loaded else { return }
            if let h = holding {
                name = h.name
                kind = h.kind
                ticker = h.ticker ?? ""
                units = h.units ?? 0
                invested = h.investedTotal
                expectedReturn = h.expectedReturn
                annualCost = h.annualCost
                monthly = h.monthlyContribution
                mode = h.contributionMode
                percent = h.contributionPercent
                basis = h.contributionBasis
                transferDay = h.transferDay
            }
            loaded = true
        }
    }

    /// Uitleg onder de bedragen. Zelfde opbouw als bij een spaarpot.
    private var moneyFooter: some View {
        let d = store.data
        let payDay = PotFormat.dayName(d.salaryDay(in: store.now))
        // Bij een salaris om de zoveel weken of dagen is "de salarisdag" de eerste uitbetaling van de maand.
        let payText = d.salary.isMonthly ? "je salarisdag (\(payDay))" : "de eerste salarisdag van de maand (\(payDay))"
        return VStack(alignment: .leading, spacing: 6) {
            if mode == .percentage {
                Text("Het totaal ingelegd gebruikt de app voor het rendement. Een percentage rekent over het inkomen van die maand: gaat je salaris omhoog, dan gaat de inleg vanzelf mee.")
            } else {
                Text("Het totaal ingelegd gebruikt de app voor het rendement. De inleg per maand verschijnt in je maandverdeling.")
            }
            Text("Op de overschrijfdag gaat de inleg van je bankrekening naar de belegging. Zonder eigen dag is dat \(payText). Een verdeling die je voor één maand maakt, kan een eigen dag hebben; die gaat voor.")
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
                withAnimation(Theme.motion) {
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

    /// Dezelfde binding, maar een wijziging beweegt zacht (rijen die verschijnen of verdwijnen).
    private func animated<T>(_ binding: Binding<T>) -> Binding<T> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                withAnimation(Theme.motion) { binding.wrappedValue = newValue }
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
        if type.contains("etf") || type.contains("fund") { kind = .etf }
        else if type.contains("crypto") { kind = .crypto }
        else if type.contains("equity") || type.contains("stock") { kind = .stocks }
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

    // MARK: Opslaan

    /// De belegging zoals hij na bewaren is: voor de voorvertoning en om te bewaren.
    private func draftHolding() -> Holding {
        let trimmedTicker = ticker.trimmingCharacters(in: .whitespaces)
        let tracked = !trimmedTicker.isEmpty
        var h = holding ?? Holding(name: "", startMonth: store.now)
        if holding == nil { h.id = draftID }
        h.name = name.trimmingCharacters(in: .whitespaces)
        h.kind = kind
        h.ticker = tracked ? trimmedTicker : nil
        h.units = tracked && units > 0 ? units : nil
        h.investedTotal = invested.cents
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
        let tracked = result.ticker != nil

        if holding == nil {
            let initial: Double? = (!tracked && manualValue > 0) ? manualValue : nil
            store.mutate { $0.addHolding(result, initialValue: initial) }
        } else {
            store.mutate { $0.updateHolding(result, current: now) }
        }
        if result.isTracked {
            Task { await store.refreshPrices(force: true) }
        }
    }
}
