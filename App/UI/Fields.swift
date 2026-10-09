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
            guard let newValue = NumberRow.value(from: newText, unit: unit) else { return }
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

    private func display(_ v: Double) -> String {
        guard v.isFinite, v != 0 else { return "" }
        return Fmt.input(v * unit.scale, maxDigits: maxDigits)
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
    var defaultDate: Date = Date().addingTimeInterval(365 * 86_400)

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

// MARK: - Sheets

/// Standaard opzet voor invulschermen: titel, annuleren en bewaren.
struct SheetScaffold<Content: View>: View {
    let title: String
    var saveTitle = "Bewaar"
    var canSave = true
    let onSave: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

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
                            onSave()
                            dismiss()
                        }
                        .disabled(!canSave)
                    }
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
