import SwiftUI

// Aankoopcheck: is een product je werkuren waard?
// Drie stappen: 1. wat wil je kopen, 2. hoeveel uur wil je ervoor werken, 3. wat het kost.
// Voor de knop "Laat zien wat het kost" staat er nergens hoeveel uur het kost.

// MARK: - Kleuren en symbolen

extension PurchaseVerdict {
    /// Kleur van de uitspraak "kan het?".
    var tint: Color {
        switch self {
        case .easy: return Theme.positive
        case .tight: return Theme.warning
        case .notNow: return Theme.negative
        case .unknown: return Color.secondary
        }
    }
}

extension PurchaseNoteKind {
    var symbol: String {
        switch self {
        case .positive: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .neutral: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .positive: return Theme.positive
        case .warning: return Theme.warning
        case .neutral: return Color.secondary
        }
    }
}

// MARK: - Wie is er ingelogd

// MARK: - Blok op de Tools-pagina

/// Tegel op de Tools-pagina: korte uitleg en je uurloon. Toont nooit wat iets kost.
struct PurchaseBlock: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        // Dezelfde account-id als de Buffer en het spaardoel (zie `accountPrefsID`).
        let account = accountPrefsID(auth: auth, cloud: cloud)
        PurchaseBlockContent(key: AccountPrefs.key(PurchaseCalc.wageStorageKey, account: account))
    }
}

private struct PurchaseBlockContent: View {
    @Environment(AppStore.self) private var store
    @AppStorage private var manualWage: Double

    init(key: String) {
        _manualWage = AppStorage(wrappedValue: 0, key)
    }

    var body: some View {
        let wage = PurchaseCalc.resolvedWage(manual: manualWage, data: store.data)
        LinkedBlock(title: "Aankoopcheck", symbol: "cart", subtitle: "Is het je werkuren waard?", destination: .purchase) {
            Text("Zet een aankoop tegenover je werktijd en kijk of je er genoeg uren voor over hebt.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let wage = wage {
                StatTile(title: "Je uurloon", value: Fmt.euroExact(wage) + " per uur", caption: "netto")
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "pencil.line")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Je uurloon").font(.caption).foregroundStyle(.secondary)
                        Text("Vul je uurloon in om te beginnen")
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .tile()
            }
        }
    }
}

// MARK: - Stappen

enum PurchaseStep: Int, CaseIterable, Identifiable {
    case product, hours, outcome

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .product: return "Product"
        case .hours: return "Uren"
        case .outcome: return "Uitkomst"
        }
    }
}

/// Drie streepjes met de naam van de stap; het streepje van de huidige en eerdere stappen is gevuld.
struct PurchaseStepBar: View {
    let current: PurchaseStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PurchaseStep.allCases) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(item.rawValue <= current.rawValue ? Theme.accent : Theme.accent.opacity(0.22))
                        .frame(height: 5)
                    Text("\(item.rawValue + 1). \(item.shortTitle)")
                        .font(.caption.weight(item == current ? .semibold : .regular))
                        .foregroundStyle(item == current ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 4)
        .animation(Theme.motion, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stap \(current.rawValue + 1) van \(PurchaseStep.allCases.count): \(current.shortTitle)")
    }
}

/// Tegel met een soort product (icoon en naam).
struct PurchaseCategoryTile: View {
    let category: PurchaseCategory
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
        VStack(spacing: 6) {
            Image(systemName: category.symbol)
                .font(.title3)
                .foregroundStyle(Theme.accent)
            Text(category.shortTitle)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.horizontal, 6)
        .background(selected ? Theme.accent.opacity(0.26) : Color.primary.opacity(0.07), in: shape)
        .overlay { shape.strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 1.5) }
        .contentShape(shape)
        .animation(Theme.quickMotion, value: selected)
    }
}

/// Een regel feedback met een icoon dat past bij de soort.
struct PurchaseNoteRow: View {
    let note: PurchaseNote

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: note.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(note.kind.tint)
                .frame(width: 22)
            Text(note.text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Zoekknop die een webadres opent in de browser (zelfde uiterlijk en hoogte als de andere knoppen).
struct PurchaseURLChip: View {
    let link: PurchaseSearchLink
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(link.url)
        } label: {
            ChipLabel(title: link.title, symbol: link.symbol)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opent een zoekopdracht in je browser")
    }
}

// MARK: - Pagina

struct PurchasePage: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.cloudAccount) private var cloud

    var body: some View {
        // Uurloon en buffer staan onder dezelfde account-id (zie `accountPrefsID`): de Buffer-pagina bewaart zijn
        // keuzes onder dezelfde sleutel, en hier lezen we ze om te weten welke pot jouw buffer is.
        let account = accountPrefsID(auth: auth, cloud: cloud)
        PurchasePageContent(wageKey: AccountPrefs.key(PurchaseCalc.wageStorageKey, account: account),
                            bufferKey: AccountPrefs.key(BufferSetup.storageKey, account: account))
    }
}

private struct PurchasePageContent: View {
    @Environment(AppStore.self) private var store
    /// Je eigen uurloon, per account bewaard. 0 = niet ingevuld.
    @AppStorage private var manualWage: Double
    /// De keuzes van de Buffer-pagina (JSON), om te weten welke pot jouw buffer is.
    @AppStorage private var storedBuffer: String

    @State private var step: PurchaseStep = .product
    @State private var name = ""
    @State private var searchTerm = ""
    @State private var category: PurchaseCategory?
    @State private var price = 0.0
    @State private var shipping = 0.0
    @State private var hours = 0.0
    @State private var foundPrice = 0.0
    @State private var foundShipping = 0.0
    @State private var context = PurchaseContext()
    /// Telt op als een invulveld opnieuw getekend moet worden (een veld met focus ververst anders zijn tekst niet).
    @State private var fieldReset = 0

    private let topID = "purchase-top"
    private let quickHours: [Double] = [1, 4, 8, 20, 40]

    init(wageKey: String, bufferKey: String) {
        _manualWage = AppStorage(wrappedValue: 0, wageKey)
        _storedBuffer = AppStorage(wrappedValue: "", bufferKey)
    }

    var body: some View {
        PageScaffold(title: "Aankoopcheck") {
            ScrollViewReader { proxy in
                VStack(spacing: Theme.pageSpacing) {
                    PurchaseStepBar(current: step)
                        .id(topID)
                    ZStack(alignment: .top) {
                        switch step {
                        case .product:
                            productStep.transition(stepTransition)
                        case .hours:
                            hoursStep.transition(stepTransition)
                        case .outcome:
                            outcomeStep.transition(stepTransition)
                        }
                    }
                }
                .frame(maxWidth: 640)
                .onChange(of: step) { _, _ in
                    withAnimation(Theme.motion) { proxy.scrollTo(topID, anchor: .top) }
                }
            }
        }
        .onAppear { refreshContext() }
        .onChange(of: store.data) { _, _ in refreshContext() }
        .onChange(of: storedBuffer) { _, _ in refreshContext() }
        .onChange(of: name) { oldName, newName in
            // De zoekterm volgt de naam, tot je hem zelf aanpast.
            if searchTerm.isEmpty || searchTerm == oldName { searchTerm = newName }
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity)
    }

    // MARK: Gegevens

    private var autoWage: Double? { store.data.effectiveHourlyWage() }

    /// Het uurloon waarmee gerekend wordt: zelf ingevuld, anders uit je salaris.
    private var wage: Double {
        PurchaseCalc.resolvedWage(manual: manualWage, data: store.data) ?? 0
    }

    /// Invulveld: toont het salaris-uurloon zolang je niets zelf invult; typen bewaart je eigen waarde.
    private var wageBinding: Binding<Double> {
        Binding(
            get: { manualWage > 0 ? manualWage : (autoWage ?? 0) },
            set: { manualWage = max(0, $0) }
        )
    }

    /// Bij een vast maandsalaris is het uurloon salaris gedeeld door je uren: die uren moeten dus ergens in te vullen zijn.
    private var showsWeeklyHours: Bool {
        store.data.salary.mode == .fixed && store.data.salary.fixedMonthly > 0
    }

    private var weeklyHoursBinding: Binding<Double> {
        Binding(
            get: { store.data.salary.hoursPerWeek },
            set: { newValue in
                let weekly = newValue.isFinite ? min(max(0, newValue), 168) : 0
                store.mutate { $0.salary.hoursPerWeek = weekly }
            }
        )
    }

    private var productName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Je aankoop" : trimmed
    }

    private var input: PurchaseInput {
        PurchaseInput(name: name,
                      category: category ?? .other,
                      price: price,
                      shipping: shipping,
                      hoursWilling: hours,
                      hourlyWage: wage,
                      cheaperPrice: foundPrice > 0 ? foundPrice : nil,
                      cheaperShipping: foundPrice > 0 ? foundShipping : nil)
    }

    private var canContinue: Bool {
        category != nil && price > 0 && wage > 0
    }

    private var missingText: String {
        if category == nil { return "Kies eerst een soort product." }
        if price <= 0 { return "Vul de prijs in." }
        return "Vul je uurloon in."
    }

    /// De pot die jij op de Buffer-pagina als buffer koos (alleen als de buffer uit een pot komt).
    private var chosenBufferPotID: UUID? {
        guard let setup = BufferSetup.fromJSON(storedBuffer), setup.source.usesPot else { return nil }
        return BufferCalc.resolvedPot(in: store.data, preferred: setup.potID)?.id
    }

    private func refreshContext() {
        context = PurchaseContext.make(from: store.data, current: store.now, today: store.today,
                                       bufferPotID: chosenBufferPotID)
    }

    private func go(to target: PurchaseStep) {
        withAnimation(Theme.motion) { step = target }
    }

    private func restart() {
        withAnimation(Theme.motion) {
            step = .product
            name = ""
            searchTerm = ""
            category = nil
            price = 0
            shipping = 0
            hours = 0
            foundPrice = 0
            foundShipping = 0
        }
        fieldReset += 1
    }

    // MARK: Stap 1: wat wil je kopen

    @ViewBuilder
    private var productStep: some View {
        GlassBlock(title: "Wat wil je kopen?", symbol: "cart", subtitle: "Stap 1 van 3") {
            TextField("Naam van het product", text: $name)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
                .padding(.horizontal, 12)
                .frame(minHeight: Theme.buttonHeight)
                .tile()

            Text("Soort product").font(.subheadline.weight(.semibold))
            // Twee kolommen: tien soorten vormen zo altijd vijf volle rijen, op elk scherm.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(PurchaseCategory.allCases) { item in
                    Button {
                        withAnimation(Theme.quickMotion) { category = item }
                    } label: {
                        PurchaseCategoryTile(category: item, selected: category == item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }
            if let selected = category {
                Label {
                    Text(selected.tip)
                } icon: {
                    Image(systemName: "lightbulb")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .id(selected)
                .transition(.opacity)
            }

            VStack(spacing: 10) {
                NumberRow(title: "Prijs", value: $price)
                NumberRow(title: "Verzendkosten", value: $shipping)
                NumberRow(title: "Netto uurloon", value: wageBinding)
                    .id(fieldReset)
                if showsWeeklyHours {
                    NumberRow(title: "Uren per week", value: weeklyHoursBinding, unit: .plain("uur"), maxDigits: 1)
                }
            }
            .padding(12)
            .tile()
            wageHint

            if !canContinue {
                Text(missingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ChipButton(title: "Verder", symbol: "arrow.right") { go(to: .hours) }
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.45)
                .animation(Theme.quickMotion, value: canContinue)
        }
        .animation(Theme.motion, value: category)
        .animation(Theme.motion, value: canContinue)
        .animation(Theme.motion, value: manualWage > 0)
    }

    @ViewBuilder
    private var wageHint: some View {
        if manualWage > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Je eigen uurloon. Het wordt onthouden voor de volgende keer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if autoWage != nil {
                    ChipButton(title: "Gebruik mijn salaris", symbol: "arrow.counterclockwise") {
                        withAnimation(Theme.motion) { manualWage = 0 }
                        fieldReset += 1
                    }
                }
            }
        } else if autoWage != nil {
            Text("Voorgevuld uit je salaris. Typ een ander bedrag om het zelf te bepalen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if showsWeeklyHours {
            Text("Vul je uren per week in, dan reken ik je uurloon uit je maandsalaris (uren per week × 52 ÷ 12). Of typ zelf je netto uurloon.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Typ je netto (gemiddelde) uurloon. Vul je uurloon of salaris in bij Salaris & inkomsten, dan staat het hier voortaan al klaar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Stap 2: hoeveel uur

    private func workdaysText(_ value: Double) -> String {
        if value <= 0 { return "Schuif om het aantal uur te kiezen" }
        let days = value / PurchaseCalc.hoursPerWorkday
        if days < 1 { return "Minder dan een werkdag van 8 uur" }
        let rounded = (days * 10).rounded() / 10
        if rounded == 1 { return "Precies 1 werkdag" }
        return "Ongeveer \(Fmt.input(rounded, maxDigits: 1)) werkdagen"
    }

    /// Kiest een aantal uren (ook meer dan de schuif aankan), op 0,1 uur afgerond.
    private func setHours(_ value: Double) {
        let clamped = PurchaseCalc.sanitizedHours(value)
        withAnimation(Theme.quickMotion) { hours = clamped }
        fieldReset += 1
    }

    /// De schuif gaat tot 200 uur; een getypt hoger aantal laat hem op het uiteinde staan.
    private var sliderBinding: Binding<Double> {
        Binding(
            get: { min(hours, PurchaseCalc.hoursRange.upperBound) },
            set: { hours = $0 }
        )
    }

    /// Invulveld voor het aantal uren: begrensd en afgerond op 0,1 uur.
    private var hoursBinding: Binding<Double> {
        Binding(
            get: { hours },
            set: { hours = PurchaseCalc.sanitizedHours($0) }
        )
    }

    @ViewBuilder
    private var hoursStep: some View {
        let ready = hours > 0
        GlassBlock(title: "Hoeveel uur wil je ervoor werken?", symbol: "clock", subtitle: "Stap 2 van 3") {
            Label(productName, systemImage: (category ?? .other).symbol)
                .font(.subheadline.weight(.semibold))
            Text("Beslis eerst, voordat je ziet wat het kost. Hoeveel uur van je werktijd is dit je eerlijk waard?")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(PurchaseCalc.hoursText(hours))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(workdaysText(hours))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .tile()

            hoursControls

            ChipGrid(minimumWidth: 150) {
                ChipButton(title: "Terug", symbol: "arrow.left") { go(to: .product) }
                ChipButton(title: "Laat zien wat het kost", symbol: "eye") { go(to: .outcome) }
                    .disabled(!ready)
                    .opacity(ready ? 1 : 0.45)
                    .animation(Theme.quickMotion, value: ready)
            }
            if !ready {
                Text("Kies eerst hoeveel uur je ervoor wilt werken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Schuif, getypt aantal en snelknoppen.
    @ViewBuilder
    private var hoursControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Slider(value: sliderBinding, in: PurchaseCalc.hoursRange, step: PurchaseCalc.hoursStep,
                   onEditingChanged: { editing in
                       // Na het schuiven toont een invulveld met focus anders nog het oude getal.
                       if !editing { fieldReset += 1 }
                   })
                .accessibilityLabel("Aantal uur werken")

            VStack(spacing: 10) {
                NumberRow(title: "Of typ het aantal uur", value: hoursBinding, unit: .plain("uur"), maxDigits: 1)
                    .id(fieldReset)
            }
            .padding(12)
            .tile()
            Text("De schuif gaat tot \(Fmt.input(PurchaseCalc.hoursRange.upperBound, maxDigits: 0)) uur. Voor een groter bedrag typ je het aantal uur zelf.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ChipGrid(minimumWidth: 150) {
                ChipButton(title: "Een half uur minder", symbol: "minus") { setHours(hours - PurchaseCalc.hoursStep) }
                ChipButton(title: "Een half uur meer", symbol: "plus") { setHours(hours + PurchaseCalc.hoursStep) }
            }

            Text("Snel kiezen, in uren")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Vijf even brede knoppen in één rij, zodat er nooit een eenzame knop op een tweede regel staat.
            HStack(spacing: 8) {
                ForEach(quickHours, id: \.self) { quick in
                    ChipButton(title: Fmt.input(quick, maxDigits: 0)) { setHours(quick) }
                        .accessibilityLabel("\(Fmt.input(quick, maxDigits: 0)) uur")
                }
            }
        }
    }

    // MARK: Stap 3: uitkomst

    private func tone(for r: PurchaseResult) -> Color {
        if !r.hasWage { return Color.secondary }
        return r.isWorthIt ? Theme.positive : Theme.negative
    }

    private func verdictTitle(_ r: PurchaseResult) -> String {
        if !r.hasWage { return "Vul eerst je uurloon in" }
        return r.isWorthIt ? "Het is het je waard" : "Eigenlijk vind je het niet waard"
    }

    private func verdictSymbol(_ r: PurchaseResult) -> String {
        if !r.hasWage { return "questionmark.circle.fill" }
        return r.isWorthIt ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private func differenceText(_ r: PurchaseResult) -> String? {
        guard r.hasWage else { return nil }
        let diff = r.hoursDifference
        if diff > 0 { return "\(PurchaseCalc.hoursText(diff)) meer dan nodig" }
        if diff < 0 { return "\(PurchaseCalc.hoursText(-diff)) te weinig" }
        return "precies gelijk"
    }

    @ViewBuilder
    private var outcomeStep: some View {
        let result = PurchaseCalc.evaluate(input, context: context)
        VStack(spacing: Theme.pageSpacing) {
            outcomeBlock(result)
            affordabilityBlock(result.affordability)
            cheaperBlock(result)
            ChipGrid(minimumWidth: 150) {
                ChipButton(title: "Uren aanpassen", symbol: "slider.horizontal.3") { go(to: .hours) }
                ChipButton(title: "Opnieuw", symbol: "arrow.counterclockwise") { restart() }
            }
        }
        .animation(Theme.motion, value: result)
    }

    private func outcomeBlock(_ r: PurchaseResult) -> some View {
        let color = tone(for: r)
        let shippingShown = PurchaseCalc.sanitizedAmount(r.usesCheaper ? foundShipping : shipping)
        return GlassBlock(title: productName, symbol: (category ?? .other).symbol, subtitle: category?.title) {
            VStack(spacing: 6) {
                Text(Fmt.euro(r.totalCost))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if r.usesCheaper {
                    HStack(spacing: 6) {
                        Text(Fmt.euro(r.originalTotal))
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Text("Je bespaart \(PurchaseCalc.moneyText(r.savedByCheaper))")
                            .foregroundStyle(Theme.positive)
                    }
                    .font(.footnote.weight(.semibold))
                } else {
                    Text(shippingShown > 0 ? "Totaal, inclusief \(Fmt.euro(shippingShown)) verzendkosten" : "Totaalprijs")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Label(verdictTitle(r), systemImage: verdictSymbol(r))
                    .font(.headline)
                    .foregroundStyle(color)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .tile(tint: color)

            HStack(spacing: 10) {
                StatTile(title: "Het kost je", value: PurchaseCalc.costHoursText(r.hoursNeeded) + " werken",
                         color: color, caption: PurchaseCalc.workdaysCaption(days: r.daysOfWork))
                StatTile(title: "Jij wilde", value: PurchaseCalc.hoursText(r.hoursWilling) + " werken",
                         caption: differenceText(r))
            }

            if r.hasWage {
                Text("Gerekend met een netto uurloon van \(Fmt.euroExact(r.hourlyWage)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let share = r.shareOfMonthlyIncome, share < PurchaseCalc.incomeWarningShare,
               let shareText = PurchaseCalc.incomeShareText(share) {
                Text(shareText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(r.feedback) { note in
                    PurchaseNoteRow(note: note)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .tile()
        }
    }

    private func affordabilityBlock(_ a: PurchaseAffordability) -> some View {
        GlassBlock(title: "Kan het?", symbol: "banknote", subtitle: "Past het in jouw geld?") {
            Label(a.verdict.title, systemImage: a.verdict.symbol)
                .font(.headline)
                .foregroundStyle(a.verdict.tint)
                .fixedSize(horizontal: false, vertical: true)
            Text(a.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !a.details.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(a.details) { note in
                        PurchaseNoteRow(note: note)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .tile()
            }
        }
    }

    /// Tekst voor "deze aanbieding is niet goedkoper": met centen als de afgeronde bedragen anders gelijk lijken.
    private func offerComparison(found: Double, original: Double) -> String {
        let sameWhole = Fmt.euro(found) == Fmt.euro(original)
        let foundText = sameWhole ? Fmt.euroExact(found) : Fmt.euro(found)
        let originalText = sameWhole ? Fmt.euroExact(original) : Fmt.euro(original)
        return "Deze aanbieding is \(foundText) inclusief verzending. Dat is niet goedkoper dan \(originalText), dus ik reken met de eerste prijs."
    }

    private func cheaperBlock(_ r: PurchaseResult) -> some View {
        let links = PurchaseSearch.links(for: searchTerm, category: category)
        let foundTotal = PurchaseCalc.total(price: foundPrice, shipping: foundShipping)
        return GlassBlock(title: "Goedkoper te vinden?", symbol: "tag", subtitle: "Zoek zelf en vul de beste prijs in") {
            Text("De app zoekt niet zelf en haalt geen prijzen op. De knoppen openen een zoekopdracht in je browser. Vul daarna de beste prijs en verzendkosten in die je vindt, dan reken ik meteen opnieuw.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Zoekterm, bijvoorbeeld merk en model", text: $searchTerm)
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 12)
                .frame(minHeight: Theme.buttonHeight)
                .tile()

            if links.isEmpty {
                Text("Vul een zoekterm in om de zoekknoppen te zien.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ChipGrid(minimumWidth: 150) {
                    ForEach(links) { link in
                        PurchaseURLChip(link: link)
                    }
                }
            }

            VStack(spacing: 10) {
                NumberRow(title: "Beste prijs gevonden", value: $foundPrice)
                    .id(fieldReset)
                NumberRow(title: "Verzendkosten daar", value: $foundShipping)
                    .id(fieldReset)
            }
            .padding(12)
            .tile()
            Text("Gratis verzending? Laat de verzendkosten leeg.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if foundPrice > 0 {
                if r.usesCheaper {
                    Label("Goedkoper: \(Fmt.euro(foundTotal)) inclusief verzending. Je bespaart \(PurchaseCalc.moneyText(r.savedByCheaper)).",
                          systemImage: "arrow.down.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.positive)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(offerComparison(found: foundTotal, original: r.originalTotal),
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ChipButton(title: "Wis gevonden prijs", symbol: "xmark") {
                    withAnimation(Theme.motion) {
                        foundPrice = 0
                        foundShipping = 0
                    }
                    fieldReset += 1
                }
            }
        }
    }
}
