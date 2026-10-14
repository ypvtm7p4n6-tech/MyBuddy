import SwiftUI

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

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", text: $text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                #endif
                .focused($focused)
                .frame(minWidth: 70, maxWidth: 150)
            Text(unit.suffix)
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)
        }
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
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Stepper("", value: clampedValue, in: range)
                .labelsHidden()
        }
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

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { value != nil },
            set: { newValue in
                withAnimation(Theme.motion) { value = newValue ? (value ?? defaultValue) : nil }
            }
        ))
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

    static func oneYearFromNow(now: Date = Date()) -> Date {
        YearMonth.calendar.date(byAdding: .year, value: 1, to: now) ?? now
    }

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { newValue in
                withAnimation(Theme.motion) { date = newValue ? (date ?? defaultDate) : nil }
            }
        ))
        if date != nil {
            DatePicker("Datum", selection: Binding(get: { date ?? defaultDate }, set: { date = $0 }),
                       displayedComponents: .date)
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
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(tint: isSelected ? Theme.accent : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.quickMotion, value: isSelected)
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
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("= " + Fmt.euro(resolvedAmount))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                            .animation(Theme.motion, value: resolvedAmount)
                    }
                }
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
struct SheetScaffold<Content: View>: View {
    let title: String
    var saveTitle = "Bewaar"
    var canSave = true
    let onSave: () -> Void
    var saveChoices: SaveChoices? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var asking = false

    var body: some View {
        NavigationStack {
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background { MeshBackground() }
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuleer") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveTitle) {
                            if saveChoices != nil {
                                asking = true
                            } else {
                                onSave()
                                dismiss()
                            }
                        }
                        .disabled(!canSave)
                    }
                }
                .confirmationDialog(saveChoices?.title ?? "", isPresented: $asking, titleVisibility: .visible) {
                    ForEach(saveChoices?.options ?? []) { option in
                        Button(option.title, role: option.role) {
                            option.action()
                            dismiss()
                        }
                    }
                    Button("Annuleer", role: .cancel) {}
                } message: {
                    if let message = saveChoices?.message { Text(message) }
                }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }
}

/// Keuze uit de kleuren van het palet.
struct ColorChoiceRow: View {
    @Binding var index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kleur")
            HStack(spacing: 10) {
                ForEach(0..<Theme.palette.count, id: \.self) { i in
                    Button { index = i } label: {
                        Circle()
                            .fill(Theme.color(i))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if index == i {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kleur \(i + 1)")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Keuze uit een rijtje symbolen.
struct SymbolChoiceRow: View {
    @Binding var symbol: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Symbool")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(Theme.potSymbols, id: \.self) { s in
                    Button { symbol = s } label: {
                        Image(systemName: s)
                            .font(.body)
                            .frame(width: 40, height: 40)
                            .foregroundStyle(symbol == s ? Color.white : color)
                            .background(symbol == s ? color : color.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
