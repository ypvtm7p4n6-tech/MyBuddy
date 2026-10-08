import SwiftUI

// MARK: - Pagina en blokken

/// Elke pagina in de app (tabs en detailpagina's) gebruikt dezelfde opzet.
struct PageScaffold<Content: View>: View {
    let title: String
    var showsSettings = false
    @ViewBuilder var content: Content
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: Theme.pageMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .background { MeshBackground() }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if showsSettings {
                ToolbarItem(placement: .primaryAction) {
                    Button { router.showSettings = true } label: {
                        Label("Instellingen", systemImage: "gearshape")
                    }
                }
            }
        }
    }
}

/// Een glazen blok met titel. Gebruik `headerLink` als alleen de kop naar een pagina leidt.
struct GlassBlock<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var subtitle: String? = nil
    var headerLink: Destination? = nil
    var showsChevron: Bool = false
    var interactive: Bool = false
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let link = headerLink {
                NavigationLink(value: link) { header(chevron: true) }
                    .buttonStyle(.plain)
            } else {
                header(chevron: showsChevron)
            }
            content
        }
        .padding(Theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, interactive: interactive)
    }

    private func header(chevron: Bool) -> some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Een glazen blok waarvan de hele kaart naar een eigen pagina leidt.
struct LinkedBlock<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var subtitle: String? = nil
    let destination: Destination
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        NavigationLink(value: destination) {
            GlassBlock(title: title, symbol: symbol, subtitle: subtitle, showsChevron: true, interactive: true, tint: tint) {
                content
            }
        }
        .buttonStyle(.plain)
    }
}

/// Kleine kop boven een groep op een detailpagina.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Getallen en voortgang

struct BigAmount: View {
    let value: Double
    var font: Font = .system(.largeTitle, design: .rounded, weight: .bold)
    var color: Color = .primary

    var body: some View {
        Text(Fmt.euro(value))
            .font(font)
            .foregroundStyle(color)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .tile()
    }
}

struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct ProgressBar: View {
    var progress: Double
    var tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let p = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.22))
                Capsule()
                    .fill(tint)
                    .frame(width: p > 0 ? max(height, geo.size.width * p) : 0)
            }
        }
        .frame(height: height)
    }
}

/// Rond icoon in de kleur van een pot of belegging.
struct SymbolBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: Circle())
    }
}

// MARK: - Hints en knoppen

struct EmptyHint: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
            Text(title).font(.subheadline.weight(.semibold))
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .glassButton()
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// Kleine glazen capsule-knop met een icoon, voor acties in een blok.
struct ChipButton: View {
    let title: String
    var symbol: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .glassSurface(Capsule(), interactive: true)
    }
}

// MARK: - Periode kiezen

/// Terug/vooruit door de maanden.
struct MonthStepper: View {
    @Binding var month: YearMonth
    var current: YearMonth

    var body: some View {
        HStack {
            Button { month = month.adding(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Vorige maand")
            Spacer()
            VStack(spacing: 1) {
                Text(Fmt.month(month)).font(.headline)
                if month > current { Text("Verwacht").font(.caption).foregroundStyle(Theme.warning) }
                else if month == current { Text("Deze maand").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { month = month.adding(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Volgende maand")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

/// Maand / half jaar / jaar met terug en vooruit.
struct PeriodControl: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 10) {
            Picker("Periode", selection: $router.periodMode) {
                ForEach(PeriodMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button { router.shiftPeriod(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Vorige periode")
                Spacer()
                VStack(spacing: 1) {
                    Text(Fmt.period(router.periodMode, containing: router.focusMonth)).font(.headline)
                    if let note = statusNote { Text(note).font(.caption).foregroundStyle(Theme.warning) }
                }
                Spacer()
                Button { router.shiftPeriod(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Volgende periode")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
        }
    }

    private var statusNote: String? {
        let months = router.periodMode.months(containing: router.focusMonth)
        guard let last = months.last, let first = months.first else { return nil }
        if first > store.now { return "Verwacht" }
        if last > store.now { return "Deels verwacht" }
        return nil
    }
}
