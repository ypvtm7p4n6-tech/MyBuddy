import SwiftUI

// MARK: - Pagina en blokken

/// Elke pagina in de app (tabs en detailpagina's) gebruikt dezelfde opzet.
struct PageScaffold<Content: View>: View {
    let title: String
    var showsSettings = false
    @ViewBuilder var content: Content
    @Environment(Router.self) private var router
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: Theme.pageMaxWidth)
                .frame(maxWidth: .infinity)
                // Verandert er iets in je gegevens of in de gekozen periode, dan rollen bedragen,
                // groeien balken en schuiven blokken zacht naar hun nieuwe plek.
                .animation(Theme.motion, value: store.data)
                .animation(Theme.motion, value: router.focusMonth)
                .animation(Theme.motion, value: router.periodMode)
                #if DEBUG
                .offset(y: -DebugLaunch.scrollOffset)
                #endif
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
/// Met `showsCurrentMonth` zet een tik eerst de Savings-pagina's op de huidige maand (periode "Maand"),
/// zodat het getal in het blok en op de pagina daarna altijd hetzelfde is. Gebruik dat op Home.
struct LinkedBlock<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var subtitle: String? = nil
    let destination: Destination
    var tint: Color? = nil
    var showsCurrentMonth: Bool = false
    @ViewBuilder var content: Content
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if showsCurrentMonth {
            Button {
                router.showCurrentMonth(store.now)
                router.open(destination)
            } label: { card }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: destination) { card }
                .buttonStyle(.plain)
        }
    }

    private var card: some View {
        GlassBlock(title: title, symbol: symbol, subtitle: subtitle, showsChevron: true, interactive: true, tint: tint) {
            content
        }
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
            .animation(Theme.motion, value: value)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .animation(Theme.motion, value: value)
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
        .animation(Theme.motion, value: progress)
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
        .animation(Theme.motion, value: progress)
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
                // Zelfde knop als overal (even hoog), niet de systeemknop.
                ChipButton(title: actionTitle, action: action)
                    .frame(maxWidth: 280)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// Uiterlijk van alle acties in de app: één hoogte, vult de beschikbare breedte.
/// Staan er meerdere naast elkaar in een HStack, dan zijn ze even breed.
struct ChipLabel: View {
    let title: String
    var symbol: String? = nil
    var destructive = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(destructive ? Theme.negative : Color.primary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
        .contentShape(Capsule())
        .glassSurface(Capsule(), interactive: true)
        .animation(Theme.quickMotion, value: title)
    }
}

/// Glazen capsule-knop voor acties in een blok.
struct ChipButton: View {
    let title: String
    var symbol: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            ChipLabel(title: title, symbol: symbol, destructive: role == .destructive)
        }
        .buttonStyle(.plain)
    }
}

/// Zelfde knop, maar die naar een pagina leidt.
struct ChipLink: View {
    let title: String
    var symbol: String? = nil
    let destination: Destination

    var body: some View {
        NavigationLink(value: destination) {
            ChipLabel(title: title, symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}

/// Rij met knoppen die even groot zijn en op een smal scherm netjes onder elkaar komen.
struct ChipGrid<Content: View>: View {
    var minimumWidth: CGFloat = 150
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 10)], spacing: 10) {
            content
        }
    }
}

// MARK: - Periode kiezen

/// Chevron-knop met een tikvlak van 44 x 44 punten (de minimale maat van Apple). Het icoon blijft aan de
/// buitenkant staan, het tikvlak reikt naar het midden.
private struct StepButton: View {
    let symbol: String
    let label: String
    let alignment: Alignment
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 44, height: 44, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Terug/vooruit door de maanden.
struct MonthStepper: View {
    @Binding var month: YearMonth
    var current: YearMonth

    var body: some View {
        HStack {
            StepButton(symbol: "chevron.left", label: "Vorige maand", alignment: .leading) {
                month = month.adding(-1)
            }
            Spacer()
            VStack(spacing: 1) {
                Text(Fmt.month(month)).font(.headline)
                if month > current { Text("Verwacht").font(.caption).foregroundStyle(Theme.warning) }
                else if month == current { Text("Deze maand").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            StepButton(symbol: "chevron.right", label: "Volgende maand", alignment: .trailing) {
                month = month.adding(1)
            }
        }
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
                StepButton(symbol: "chevron.left", label: "Vorige periode", alignment: .leading) {
                    router.shiftPeriod(-1)
                }
                Spacer()
                VStack(spacing: 1) {
                    Text(Fmt.period(router.periodMode, containing: router.focusMonth))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let note = statusNote { Text(note).font(.caption).foregroundStyle(Theme.warning) }
                }
                Spacer()
                StepButton(symbol: "chevron.right", label: "Volgende periode", alignment: .trailing) {
                    router.shiftPeriod(1)
                }
            }
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

// MARK: - Negatief restant

/// Waarom "Nog te verdelen" onder nul zit, zodat de melding klopt. Het restant is inkomen min uitgaven van de bank
/// min wat je verdeelde. Zijn de uitgaven alleen al hoger dan het inkomen (bijvoorbeeld omdat je salaris nog
/// ontbreekt), dan heb je niets te veel verdeeld.
enum RemainingShortfall {
    /// Waar komt het tekort vandaan: true = de uitgaven zijn hoger dan het inkomen, false = je verdeelde te veel.
    static func isSpending(income: Double, bankExpenses: Double) -> Bool {
        CentsMath.int(income) - CentsMath.int(bankExpenses) < 0
    }
}

// MARK: - Even grote blokken

/// Legt blokken in kolommen. Elk blok is even breed én even hoog (zo hoog als het hoogste blok).
/// Het aantal kolommen volgt de beschikbare breedte: één op een iPhone, meer op iPad en Mac.
struct EqualSizeGrid: Layout {
    var minimumColumnWidth: CGFloat = 340
    var spacing: CGFloat = Theme.pageSpacing

    private func columns(for width: CGFloat, items: Int) -> Int {
        guard items > 0 else { return 1 }
        let fit = Int(((width + spacing) / (minimumColumnWidth + spacing)).rounded(.down))
        return max(1, min(items, fit))
    }

    private func usableWidth(_ proposal: ProposedViewSize) -> CGFloat {
        guard let w = proposal.width, w.isFinite, w > 0 else { return minimumColumnWidth }
        return w
    }

    private func cellSize(width: CGFloat, subviews: Subviews) -> (columns: Int, cellWidth: CGFloat, cellHeight: CGFloat) {
        let cols = columns(for: width, items: subviews.count)
        let cellWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let tallest = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }
            .max() ?? 0
        return (cols, cellWidth, tallest)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = usableWidth(proposal)
        let cell = cellSize(width: width, subviews: subviews)
        let rows = Int((Double(subviews.count) / Double(cell.columns)).rounded(.up))
        let height = CGFloat(rows) * cell.cellHeight + CGFloat(max(0, rows - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = cellSize(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let row = index / cell.columns
            let column = index % cell.columns
            let origin = CGPoint(x: bounds.minX + CGFloat(column) * (cell.cellWidth + spacing),
                                 y: bounds.minY + CGFloat(row) * (cell.cellHeight + spacing))
            subview.place(at: origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: cell.cellWidth, height: cell.cellHeight))
        }
    }
}

// MARK: - Verdeelbalk

/// Eén balk die in stukken is verdeeld, bijvoorbeeld hoe je inkomen over uitgaven, sparen en overschot gaat.
struct SegmentBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 12

    var body: some View {
        let positive = segments.filter { $0.value > 0 }
        let total = max(positive.reduce(0) { $0 + $1.value }, 0.0001)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(positive) { segment in
                    Capsule()
                        .fill(segment.color)
                        .frame(width: max(4, (geo.size.width - CGFloat(max(0, positive.count - 1)) * 2) * segment.value / total))
                        .transition(.opacity)
                }
                if positive.isEmpty {
                    Capsule().fill(Color.primary.opacity(0.12))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .animation(Theme.motion, value: positive.map(\.value))
    }
}
