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
struct NumberRow: View {
    let title: String
    @Binding var value: Double
    var unit: NumberUnit = .euro
    var maxDigits: Int = 2

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", text: $text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .focused($focused)
                .frame(minWidth: 70, maxWidth: 150)
            Text(unit.suffix)
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .leading)
        }
        .onAppear { text = display(value) }
        .onChange(of: text) { _, newText in
            let parsed = AmountParser.parse(newText) ?? 0
            let newValue = parsed / unit.scale
            if abs(newValue - value) > 1e-9 { value = newValue }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = display(value) }
        }
        .onChange(of: value) { _, _ in
            if !focused { text = display(value) }
        }
    }

    private func display(_ v: Double) -> String {
        v == 0 ? "" : Fmt.input(v * unit.scale, maxDigits: maxDigits)
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
