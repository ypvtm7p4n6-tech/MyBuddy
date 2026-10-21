import SwiftUI

// Invoervelden en het blad voor formulieren. Elke rij heeft minstens `Theme.minTapTarget` hoogte, laat het label wrappen
// en stapelt label en veld onder elkaar bij toegankelijkheidsformaten van Dynamic Type.

// MARK: - Getalveld

enum NumberUnit {
    case euro
    case percent
    case plain(String)

    var suffix: String {
        switch self {
        case .euro: return "€"
        case .percent: return "%"
        case .plain(let s): return s
        }
    }

    /// Weergave = waarde × schaal (percentages worden als breuk bewaard).
    var scale: Double {
        switch self {
        case .percent: return 100
        default: return 1
        }
    }
}

/// Invulveld voor bedragen, percentages en aantallen. Leest "12,5" en "1.234,56".
/// Wat geen geldig getal is (letters, "inf", e-notatie, meer dan een biljoen) verandert de waarde niet.
/// Een leeg veld is 0. Voor bedragen die negatief mogen zijn (een saldo, geld terug) zet je `allowsNegative` aan:
/// het decimale toetsenbord van de iPhone heeft geen minteken.
struct NumberRow: View {
    let title: String
    @Binding var value: Double
    var unit: NumberUnit = .euro
    var maxDigits: Int = 2
    var allowsNegative: Bool = false
    /// Het bereik dat het veld toelaat (bijvoorbeeld 0...100 voor een percentage). Een getal daarbuiten wordt meteen
    /// teruggezet op de dichtstbijzijnde grens. nil = geen grens.
    var range: ClosedRange<Double>? = nil

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Label en veld naast elkaar, of onder elkaar bij toegankelijkheidsformaten.
    private var rowLayout: AnyLayout {
        if typeSize.isAccessibilitySize {
            return AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        }
        return AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    var body: some View {
        rowLayout {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                TextField("0", text: $text)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                    #endif
                    .focused($focused)
                    .submitLabel(.next)
                    .frame(minWidth: 70, maxWidth: 150)
                    .accessibilityLabel(title)
                Text(unit.suffix)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 14, alignment: .leading)
            }
        }
        .frame(minHeight: Theme.minTapTarget)
        .onAppear { text = display(value) }
        .onChange(of: text) { _, newText in
            guard let parsed = NumberRow.value(from: newText, unit: unit) else { return }
            let newValue = NumberRow.clamped(parsed, to: range)
            // Buiten het bereik: het veld toont meteen de grens, zodat je geen 150% ziet staan.
            if newValue != parsed { text = display(newValue) }
            if abs(newValue - value) > 1e-9 { value = newValue }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = display(value) }
        }
        .onChange(of: value) { _, _ in
            if !focused { text = display(value) }
        }
    }

    /// De waarde bij een getypte tekst. Leeg is 0. nil als de tekst geen geldig getal (meer) is, bijvoorbeeld
    /// "-" halverwege het typen, letters of een getal boven een biljoen: dan blijft de huidige waarde staan.
    static func value(from text: String, unit: NumberUnit) -> Double? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        guard let parsed = AmountParser.parse(text), parsed.isFinite, abs(parsed) <= AmountParser.maxAbsolute else {
            return nil
        }
        return parsed / unit.scale
    }

    /// `value` binnen `range` gebracht (zonder bereik ongewijzigd).
    static func clamped(_ value: Double, to range: ClosedRange<Double>?) -> Double {
        guard let range else { return value }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func display(_ v: Double) -> String {
        guard v.isFinite, v != 0 else { return "" }
        return Fmt.input(v * unit.scale, maxDigits: maxDigits)
    }
}

/// Invulveld voor een geheel getal binnen een bereik, met een stapper ernaast: "Om de 4 weken". Typen mag (bij een
/// schema om de zoveel dagen is 1...366 stap voor stap te veel), de stapper ook. Wat buiten het bereik valt of geen
/// getal is, verandert niets of wordt op de grens gezet.
struct IntStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// Eenheid achter het getal: "weken", "dagen".
    var unit: String = ""

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 12)
            TextField("1", text: $text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .focused($focused)
                .frame(minWidth: 44, maxWidth: 70)
                .accessibilityLabel(title)
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(Theme.textSecondary)
            }
            Stepper(title, value: clampedValue, in: range)
                .labelsHidden()
        }
        .frame(minHeight: Theme.minTapTarget)
        .onAppear { text = IntStepperRow.display(value, in: range) }
        .onChange(of: text) { _, newText in
            guard let parsed = IntStepperRow.value(from: newText, in: range) else { return }
            if parsed != value { value = parsed }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = IntStepperRow.display(value, in: range) }
        }
        .onChange(of: value) { _, _ in
            if !focused { text = IntStepperRow.display(value, in: range) }
        }
    }

    /// De waarde voor de stapper, altijd binnen het bereik (ook als de opgeslagen waarde er buiten valt).
    private var clampedValue: Binding<Int> {
        Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    /// Het getal bij een getypte tekst, op de grenzen van het bereik gezet. nil als de tekst geen getal (meer) is, bijvoorbeeld
    /// halverwege het typen of bij letters: dan blijft de huidige waarde staan. Leeg is de ondergrens.
    static func value(from text: String, in range: ClosedRange<Int>) -> Int? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return range.lowerBound }
        guard let parsed = AmountParser.parse(text), parsed.isFinite else { return nil }
        return SafeInt.clamped(parsed, to: range)
    }

    /// De tekst die bij een waarde hoort (altijd binnen het bereik).
    static func display(_ value: Int, in range: ClosedRange<Int>) -> String {
        "\(min(max(value, range.lowerBound), range.upperBound))"
    }
}

/// Zet een Double veilig om naar een Int. `Int(x)` stopt de app bij NaN, oneindig en getallen buiten het bereik
/// van een Int (bijvoorbeeld 1e999 uit een invulveld); dit begrenst eerst op `range` en rondt dan af.
enum SafeInt {
    static func clamped(_ value: Double, to range: ClosedRange<Int>) -> Int {
        guard !value.isNaN else { return range.lowerBound }
        let rounded = value.rounded()
        if rounded <= Double(range.lowerBound) { return range.lowerBound }
        if rounded >= Double(range.upperBound) { return range.upperBound }
        return Int(rounded)
    }
}

/// Optioneel bedrag met een aan/uit-schakelaar (bijv. een doelbedrag).
struct OptionalNumberRow: View {
    let title: String
    @Binding var value: Double?
    var unit: NumberUnit = .euro
    var defaultValue: Double = 1000
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { value != nil },
            set: { newValue in
                withAnimation(reduceMotion ? nil : Theme.motion) { value = newValue ? (value ?? defaultValue) : nil }
            }
        ))
        .frame(minHeight: Theme.minTapTarget)
        if value != nil {
            NumberRow(title: "Bedrag", value: Binding(get: { value ?? 0 }, set: { value = $0 }), unit: unit)
        }
    }
}

/// Optionele datum met een aan/uit-schakelaar.
struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?
    /// Standaard een jaar vanaf nu, op kalenderdagen gerekend (een jaar is niet 365 x 86.400 seconden: schrikkeljaar en
    /// zomertijd verschuiven de dag).
    var defaultDate: Date = OptionalDateRow.oneYearFromNow()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func oneYearFromNow(now: Date = Date()) -> Date {
        YearMonth.calendar.date(byAdding: .year, value: 1, to: now) ?? now
    }

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { newValue in
                withAnimation(reduceMotion ? nil : Theme.motion) { date = newValue ? (date ?? defaultDate) : nil }
            }
        ))
        .frame(minHeight: Theme.minTapTarget)
        if date != nil {
            DatePicker("Datum", selection: Binding(get: { date ?? defaultDate }, set: { date = $0 }),
                       displayedComponents: .date)
                .frame(minHeight: Theme.minTapTarget)
        }
    }
}

/// Een keuze in een lijstje met één antwoord: bolletje, titel en uitleg.
struct ChoiceRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget, alignment: .leading)
            .tile(tint: isSelected ? Theme.accent : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animated(by: isSelected, quick: true)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Inleg: bedrag of percentage

/// De invoer voor de inleg van een spaarpot of belegging: een vast bedrag of een percentage van het inkomen, met de
/// grondslag (alleen salaris of alle inkomsten). Dit is alleen invoer: wat een percentage in euro's oplevert komt van de
/// aanroeper uit de rekenmotor (`resolvedAmount`), zodat hier niets wordt uitgerekend en elk scherm hetzelfde bedrag toont.
/// Werkt in een `Form` (elke regel een rij) en in een blok (de regels onder elkaar).
struct ContributionFields: View {
    @Binding var mode: ContributionMode
    @Binding var amount: Double
    /// 0...100, maximaal twee decimalen (de rekenmotor rondt het zelf ook zo af).
    @Binding var percent: Double
    @Binding var basis: IncomeBasis
    var amountTitle = "Bedrag"
    var percentTitle = "Percentage"
    /// Een bedrag onder nul betekent geld terug naar de rekening (alleen bij de verdeling van een maand).
    var allowsNegativeAmount = false
    /// Het bedrag in euro's dat het percentage nu oplevert, uit de rekenmotor. nil = niet tonen.
    var resolvedAmount: Double? = nil
    /// Korte tekst naast dat bedrag, bijvoorbeeld "10% van je salaris".
    var resolvedNote: String? = nil
    /// Extra uitleg onder het percentage, bijvoorbeeld dat er in die maand geen inkomen is.
    var footnote: String? = nil
    /// Waar het over gaat (de naam van de pot of belegging): VoiceOver leest hem bij de keuzes voor.
    var subject: String? = nil

    private func label(_ text: String) -> String {
        guard let subject, !subject.isEmpty else { return text }
        return text + " " + subject
    }

    var body: some View {
        Group {
            Picker(label("Inlegwijze"), selection: $mode) {
                Text("Bedrag").tag(ContributionMode.fixed)
                Text("Percentage").tag(ContributionMode.percentage)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch mode {
            case .fixed:
                NumberRow(title: amountTitle, value: $amount, allowsNegative: allowsNegativeAmount)
            case .percentage:
                NumberRow(title: percentTitle, value: $percent, unit: .plain("%"), maxDigits: 2, range: 0...100)
                Picker(label("Percentage van"), selection: $basis) {
                    ForEach(IncomeBasis.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if let resolvedAmount {
                    HStack(spacing: 8) {
                        if let resolvedNote {
                            Text(resolvedNote)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text("= " + Fmt.euro(resolvedAmount))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animated(by: resolvedAmount)
                    }
                }
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Sheets

/// Een vraag bij "Bewaar": in plaats van meteen op te slaan vraagt het blad eerst iets, bijvoorbeeld voor welke maanden
/// een wijziging van een terugkerende regel geldt. Elke keuze slaat op (met zijn eigen actie) en sluit het blad;
/// "Annuleer" laat het blad open.
struct SaveChoices {
    struct Option: Identifiable {
        let id: String
        let title: String
        var role: ButtonRole? = nil
        let action: () -> Void
    }

    var title: String
    var message: String? = nil
    var options: [Option]
}

/// Standaard opzet voor invulschermen: titel, annuleren en bewaren. Met `saveChoices` vraagt "Bewaar" eerst om een keuze
/// (zie `SaveChoices`) en wordt `onSave` niet gebruikt.
///
/// Met `hasChanges` is veeg-om-te-sluiten uit en vraagt "Annuleer" of je de wijzigingen wilt bewaren, weggooien of verder
/// wilt bewerken. Het blad heeft de systeemachtergrond, bewaart met Return en geeft een lichte bevestiging (`.success`).
struct SheetScaffold<Content: View>: View {
    let title: String
    var saveTitle: String = "Bewaar"
    var canSave: Bool = true
    var hasChanges: Bool = false
    let onSave: () -> Void
    var saveChoices: SaveChoices? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    /// De keuzes bij "Bewaar" (alleen met `saveChoices`).
    @State private var asking = false
    /// De vraag bij "Annuleer" met niet-bewaarde wijzigingen.
    @State private var confirmingCancel = false
    /// Loopt op bij elke bewaring en geeft de bevestigende haptiek.
    @State private var savedCount = 0

    var body: some View {
        NavigationStack {
            Form { content }
                .formStyle(.grouped)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuleer") { cancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveTitle) { save() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canSave)
                    }
                }
                .confirmationDialog("Wijzigingen bewaren?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                    if canSave {
                        Button(saveTitle) { saveAfterDialog() }
                    }
                    Button("Gooi weg", role: .destructive) { dismiss() }
                    Button("Verder bewerken", role: .cancel) {}
                }
        }
        .confirmationDialog(saveChoices?.title ?? "", isPresented: $asking, titleVisibility: .visible) {
            ForEach(saveChoices?.options ?? []) { option in
                Button(option.title, role: option.role) {
                    option.action()
                    finish()
                }
            }
            Button("Annuleer", role: .cancel) {}
        } message: {
            if let message = saveChoices?.message { Text(message) }
        }
        .interactiveDismissDisabled(hasChanges)
        .sensoryFeedback(.success, trigger: savedCount)
        .presentationSizing(.form)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }

    private func cancel() {
        if hasChanges {
            confirmingCancel = true
        } else {
            dismiss()
        }
    }

    private func save() {
        if saveChoices != nil {
            asking = true
        } else {
            onSave()
            finish()
        }
    }

    /// "Bewaar" in de vraag bij Annuleer: dezelfde weg als de knop zelf. Een tweede vraag (de keuzes) krijgt even de tijd
    /// om de eerste te laten verdwijnen.
    private func saveAfterDialog() {
        if saveChoices != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { asking = true }
        } else {
            onSave()
            finish()
        }
    }

    /// Geeft de haptiek en sluit het blad in de eerstvolgende ronde, zodat de haptiek nog hoort bij dit blad.
    private func finish() {
        savedCount += 1
        DispatchQueue.main.async { dismiss() }
    }
}

/// Namen van de kleuren in `Theme.palette`, voor VoiceOver (de kleur alleen zegt een blinde gebruiker niets).
private let paletteNames = ["olijf", "saliegroenblauw", "mosterd", "terracotta", "leiblauw", "pruim", "salie", "bruin"]

/// Nederlandse namen van de symbolen in `Theme.potSymbols`, voor VoiceOver.
private let potSymbolNames: [String: String] = [
    "banknote": "Bankbiljet", "shield.lefthalf.filled": "Schild", "airplane": "Vliegtuig", "laptopcomputer": "Laptop",
    "house.fill": "Huis", "car.fill": "Auto", "gift.fill": "Cadeau", "graduationcap.fill": "Studie",
    "heart.fill": "Hart", "pawprint.fill": "Huisdier", "bicycle": "Fiets", "camera.fill": "Camera",
    "gamecontroller.fill": "Spelcomputer", "cart.fill": "Winkelwagen", "wrench.and.screwdriver.fill": "Gereedschap",
    "star.fill": "Ster"
]

/// Keuze uit de kleuren van het palet. Elke kleur is een raakdoel van minstens `Theme.minTapTarget`, heeft een naam voor
/// VoiceOver en toont een vinkje als hij gekozen is.
struct ColorChoiceRow: View {
    @Binding var index: Int
    @ScaledMetric(relativeTo: .body) private var swatch: CGFloat = 28

    /// Een cel is minstens een raakdoel breed en wordt groter als het kleurvlak met de tekst meegroeit.
    private var cell: CGFloat { max(Theme.minTapTarget, swatch) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kleur")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: 4)], spacing: 4) {
                ForEach(0..<Theme.palette.count, id: \.self) { i in
                    Button { index = i } label: {
                        Circle()
                            .fill(Theme.color(i))
                            .frame(width: swatch, height: swatch)
                            .overlay {
                                if index == i {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.onAccent)
                                }
                            }
                            .frame(width: cell, height: cell)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kleur " + colorName(i))
                    .accessibilityAddTraits(index == i ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func colorName(_ i: Int) -> String {
        paletteNames.indices.contains(i) ? paletteNames[i] : String(i + 1)
    }
}

/// Keuze uit een rijtje symbolen. Elk symbool is een raakdoel van minstens `Theme.minTapTarget` met een naam voor VoiceOver.
struct SymbolChoiceRow: View {
    @Binding var symbol: String
    var color: Color
    /// De zijde van een keuze: een raakdoel dat met de tekst meegroeit, zodat het symbool er altijd in past.
    @ScaledMetric(relativeTo: .body) private var cell: CGFloat = Theme.minTapTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Symbool")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: 8)], spacing: 8) {
                ForEach(Theme.potSymbols, id: \.self) { s in
                    Button { symbol = s } label: {
                        Label(potSymbolNames[s] ?? s, systemImage: s)
                            .labelStyle(.iconOnly)
                            .font(.body)
                            .frame(width: cell, height: cell)
                            .foregroundStyle(symbol == s ? Theme.onAccent : color)
                            .background(symbol == s ? color : color.opacity(0.15), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(symbol == s ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}
