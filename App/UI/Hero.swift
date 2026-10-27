import SwiftUI

// De hero van Home: drie grote kaarten (Nog te verdelen, Vermogen, Saldo vandaag) die per kaart snappen, met de volgende kaart
// deels zichtbaar en paginastippen eronder (Apple Muziek en Apple TV). Vanaf 860 punten breed staan de drie kaarten naast
// elkaar en zijn er geen stippen. Bij toegankelijkheidsformaten staan ze onder elkaar. De breedtes komen uit `ShelfMetrics`.

// MARK: - Carrousel

/// De hero-kaarten van Home. `ids` zijn de stabiele id's van de kaarten (de aanroeper tekent per id een `HeroCard`);
/// `selection` is de zichtbare kaart (Home leest hem voor de kleur van de achtergrond), zonder binding houdt de carrousel
/// hem zelf bij. De stippen zijn knoppen met een raakdoel van `Theme.minTapTarget`; VoiceOver krijgt ook de acties "Volgende
/// pagina" en "Vorige pagina".
struct HeroCarousel<Card: View>: View {
    let ids: [String]
    let selection: Binding<String?>?
    let card: (String) -> Card
    @State private var ownSelection: String?
    @State private var measuredWidth: Double = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(ids: [String], selection: Binding<String?>? = nil, @ViewBuilder card: @escaping (String) -> Card) {
        self.ids = ids
        self.selection = selection
        self.card = card
    }

    private var compact: Bool { sizeClass == .compact }
    private var margin: CGFloat { CGFloat(ShelfMetrics.margin(compact: compact)) }
    private var spacing: CGFloat { CGFloat(ShelfMetrics.spacing(compact: compact)) }
    private var current: Binding<String?> { selection ?? $ownSelection }

    /// De breedte binnen de marges bepaalt of het een carrousel is of drie kaarten naast elkaar.
    private var isCarousel: Bool {
        ShelfMetrics.showsHeroCarousel(in: measuredWidth - 2 * Double(margin))
    }

    private var currentIndex: Int {
        guard let id = current.wrappedValue, let index = ids.firstIndex(of: id) else { return 0 }
        return index
    }

    var body: some View {
        VStack(spacing: 4) {
            if typeSize.isAccessibilitySize {
                stacked
            } else if isCarousel {
                carousel
                dots
            } else {
                sideBySide
            }
        }
        .onGeometryChange(for: Double.self) { proxy in
            Double(proxy.size.width)
        } action: { width in
            measuredWidth = width
        }
    }

    // MARK: Opstellingen

    /// Smal: een rij die per kaart snapt, de volgende kaart deels zichtbaar.
    private var carousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: spacing) {
                ForEach(ids, id: \.self) { id in
                    card(id)
                        .id(id)
                        .containerRelativeFrame(.horizontal) { length, _ in
                            CGFloat(ShelfMetrics.heroWidth(in: Double(length), spacing: Double(spacing)))
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: current)
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, margin)
        .accessibilityAction(named: "Volgende pagina") { step(1) }
        .accessibilityAction(named: "Vorige pagina") { step(-1) }
    }

    /// Breed: drie kaarten naast elkaar, zonder stippen.
    private var sideBySide: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(ids, id: \.self) { id in
                card(id)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, margin)
    }

    /// Toegankelijkheidsformaten: onder elkaar, geen zijwaarts scrollen.
    private var stacked: some View {
        VStack(spacing: 12) {
            ForEach(ids, id: \.self) { id in
                card(id)
            }
        }
        .padding(.horizontal, margin)
    }

    // MARK: Stippen

    private var dots: some View {
        HStack(spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                Button {
                    select(id)
                } label: {
                    Circle()
                        .fill(index == currentIndex ? Color.primary : Color.primary.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pagina \(index + 1) van \(ids.count)")
                .accessibilityAddTraits(index == currentIndex ? .isSelected : [])
            }
        }
        .animated(by: currentIndex)
    }

    // MARK: Bladeren

    private func select(_ id: String) {
        current.wrappedValue = id
    }

    private func step(_ direction: Int) {
        let target = min(max(currentIndex + direction, 0), max(ids.count - 1, 0))
        if ids.indices.contains(target) {
            withAnimation(reduceMotion ? nil : Theme.motion) {
                current.wrappedValue = ids[target]
            }
        }
    }
}

// MARK: - Kaart

/// Eén hero-kaart: een tegelverloop met radius 28, minimaal 168 punten hoog (schaalt met Dynamic Type), een regel boven
/// (`eyebrow`, met symbool), de inhoud (het kerngetal) en onderaan pillen. Witte tekst; een grafiek hoort in `heroPanel()`.
struct HeroCard<Content: View, Pills: View>: View {
    let hue: TileHue
    let eyebrow: String
    let symbol: String
    private let content: Content
    private let pills: Pills
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 168

    init(hue: TileHue, eyebrow: String, symbol: String, @ViewBuilder content: () -> Content, @ViewBuilder pills: () -> Pills) {
        self.hue = hue
        self.eyebrow = eyebrow
        self.symbol = symbol
        self.content = content()
        self.pills = pills()
    }

    var body: some View {
        GradientSurface(hue: hue, radius: Theme.heroRadius) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(eyebrow, systemImage: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onTileSecondary)
                        .accessibilityAddTraits(.isHeader)
                    content
                }
                // De pillen staan onderaan: naast elkaar in een rij of een carrousel krijgen alle kaarten de hoogte van de hoogste.
                Spacer(minLength: 0)
                pillsBlock
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// De pillen met 12 punten ruimte erboven, of niets (en dus ook geen ruimte) zonder pillen.
    @ViewBuilder
    private var pillsBlock: some View {
        if Pills.self == EmptyView.self {
            EmptyView()
        } else {
            pills.padding(.top, 12)
        }
    }
}

extension HeroCard where Pills == EmptyView {
    init(hue: TileHue, eyebrow: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(hue: hue, eyebrow: eyebrow, symbol: symbol, content: content, pills: { EmptyView() })
    }
}

// MARK: - Paneel voor een grafiek

extension View {
    /// Een donker paneel voor een grafiek in een hero-kaart of tegel: zwart op 22%, radius 16, padding 12, en de grafiek
    /// tekent zichzelf in de donkere stand (zijn kleuren zijn dan gemeten tegen een donkere achtergrond).
    func heroPanel() -> some View {
        padding(12)
            .background(Theme.heroPanelFill, in: RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}
