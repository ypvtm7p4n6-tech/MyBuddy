import SwiftUI

// De bouwstenen van het ontwerpsysteem (par. 4.3 t/m 4.5 van docs/design/plan.md): pagina's, kaarten, cijfers, knoppen en
// de maandkiezer. Geen glas in de inhoud: een kaart is `Theme.card` op het vlakke `Theme.canvas`. Glas komt van het systeem
// (tabbalk, werkbalk, bladen). Onderaan staat de overgangslaag met de oude namen (tot pakket G).

// MARK: - Pagina's

/// Een pagina van kaarten (tabroot of rekenpagina): een `ScrollView` op het canvas. `large` geeft de grote titel (alleen op
/// een tabroot), anders staat de titel klein in de balk. De inhoud scrolt onder de werkbalk door.
struct PageScaffold<Content: View>: View {
    let title: String
    var large: Bool = false
    /// Verouderd: Instellingen is een tab (iOS) of een venster (Mac). Doet niets en verdwijnt in pakket G.
    var showsSettings: Bool = false
    @ViewBuilder var content: Content

    private var titleMode: ToolbarTitleDisplayMode { large ? .large : .inline }

    var body: some View {
        ScrollView {
            content
                .scenePadding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: Theme.pageMaxWidth)
                .frame(maxWidth: .infinity)
                #if DEBUG
                .offset(y: -DebugLaunch.scrollOffset)
                #endif
        }
        .scrollDismissesKeyboard(.interactively)
        .background { Theme.canvas.ignoresSafeArea() }
        .navigationTitle(title)
        .toolbarTitleDisplayMode(titleMode)
    }
}

/// Een pagina van rijen (`List`) met swipe-acties: Inkomen, Uitgaven, Spaarpotten, Beleggingen, Doelen en Instellingen.
/// De lijst staat op het canvas en is niet breder dan `Theme.readableWidth`. In een debug-build scrolt hij naar de sectie
/// uit `-mybuddy-scroll-to` (de koptekst van een `SectionHeader`).
struct ListScaffold<Content: View>: View {
    let title: String
    var large: Bool = false
    @ViewBuilder var content: Content

    private var titleMode: ToolbarTitleDisplayMode { large ? .large : .inline }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                content
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: Theme.readableWidth)
            .frame(maxWidth: .infinity)
            .background { Theme.canvas.ignoresSafeArea() }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(titleMode)
            #if DEBUG
            .onAppear {
                if let target = DebugLaunch.scrollTarget {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
            #endif
        }
    }
}

// MARK: - Kaarten

/// Het oppervlak van een kaart: ruimte binnen, `Theme.card` met de kaartradius, geen schaduw en geen glas. Bij "Verhoog
/// contrast" krijgt de kaart een rand van 1 punt, zodat hij op het canvas onderscheidbaar blijft.
private struct CardSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        content
            .padding(Theme.cardInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                }
            }
    }
}

/// De kop van een kaart: symbool (in de kleur van het domein), titel (een kop voor VoiceOver), een regel uitleg en eventueel
/// een pijltje dat zegt dat de kop naar een pagina leidt.
private struct CardHeader: View {
    let title: String?
    let symbol: String?
    let domain: AppDomain?
    let subtitle: String?
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let iconName = symbol ?? domain?.symbol {
                Image(systemName: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(domain?.color ?? Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Knopstijl met een drukstatus (de inhoud wordt iets doorzichtig zolang je drukt), voor een kaart of kop die naar een pagina
/// leidt. Vervangt `.buttonStyle(.plain)`, dat geen reactie geeft.
private struct PressedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// De gedeelde link naar een bestemming (K16). Hoort de bestemming bij de tab waar je nu bent, dan is het een
/// `NavigationLink(value:)` (het pad loopt door `NavigationRules.normalize`). Hoort hij bij een andere tab, dan wisselt de
/// knop van tab met `router.open` (dat naar `go` doorverwijst), zodat een pagina nooit onder twee tabs staat.
/// Met `showsCurrentMonth` zet een tik eerst de Maand-tab op de huidige maand. De sluiting krijgt `true` als het een knop is
/// (dan tekent het systeem geen pijltje en moet het label dat zelf doen).
private struct DestinationLink<Inner: View>: View {
    let destination: Destination
    let showsCurrentMonth: Bool
    let label: (Bool) -> Inner
    @Environment(Router.self) private var router
    @Environment(AppStore.self) private var store

    init(destination: Destination, showsCurrentMonth: Bool = false, @ViewBuilder label: @escaping (Bool) -> Inner) {
        self.destination = destination
        self.showsCurrentMonth = showsCurrentMonth
        self.label = label
    }

    var body: some View {
        if showsCurrentMonth || destination.tab != router.tab {
            Button {
                if showsCurrentMonth { router.showCurrentMonth(store.now) }
                router.open(destination)
            } label: {
                label(true)
            }
            .accessibilityAddTraits(.isLink)
        } else {
            NavigationLink(value: destination) {
                label(false)
            }
        }
    }
}

/// Een kaart met een kop en inhoud. Met `headerLink` leidt alleen de kop naar een pagina; gebruik `LinkCard` als de hele
/// kaart een link is. De kop is een kop voor VoiceOver; `domain` geeft het symbool en de kleur van het onderdeel.
struct Card<Content: View>: View {
    let title: String?
    let symbol: String?
    let domain: AppDomain?
    let subtitle: String?
    let headerLink: Destination?
    private let content: Content

    init(title: String? = nil, symbol: String? = nil, domain: AppDomain? = nil, subtitle: String? = nil,
         headerLink: Destination? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.domain = domain
        self.subtitle = subtitle
        self.headerLink = headerLink
        self.content = content()
    }

    private var hasHeader: Bool { title != nil || symbol != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            if hasHeader {
                if let link = headerLink {
                    DestinationLink(destination: link) { _ in
                        CardHeader(title: title, symbol: symbol, domain: domain, subtitle: subtitle, showsChevron: true)
                    }
                    .buttonStyle(PressedStyle())
                } else {
                    CardHeader(title: title, symbol: symbol, domain: domain, subtitle: subtitle, showsChevron: false)
                }
            }
            content
        }
        .modifier(CardSurface())
    }
}

/// Een kaart waarvan de hele kaart naar een pagina leidt, met het kerncijfer als inhoud. Met `showsCurrentMonth` zet een tik
/// eerst de Maand-tab op de huidige maand (voor kaarten op het Overzicht, dat altijd over de huidige maand gaat).
struct LinkCard<Content: View>: View {
    let title: String
    let symbol: String?
    let domain: AppDomain?
    let subtitle: String?
    let destination: Destination
    let showsCurrentMonth: Bool
    private let content: Content

    init(title: String, symbol: String? = nil, domain: AppDomain? = nil, subtitle: String? = nil,
         destination: Destination, showsCurrentMonth: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.domain = domain
        self.subtitle = subtitle
        self.destination = destination
        self.showsCurrentMonth = showsCurrentMonth
        self.content = content()
    }

    var body: some View {
        DestinationLink(destination: destination, showsCurrentMonth: showsCurrentMonth) { _ in
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                CardHeader(title: title, symbol: symbol, domain: domain, subtitle: subtitle, showsChevron: true)
                content
            }
            .modifier(CardSurface())
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif
        }
        .buttonStyle(PressedStyle())
    }
}

/// De kop van een sectie in een `List`: titel in zinshoofdletters (geen hoofdletters), een kop voor VoiceOver.
struct SectionHeader: View {
    let title: String
    let symbol: String?
    let domain: AppDomain?

    init(_ title: String, symbol: String? = nil, domain: AppDomain? = nil) {
        self.title = title
        self.symbol = symbol
        self.domain = domain
    }

    var body: some View {
        HStack(spacing: 6) {
            if let iconName = symbol ?? domain?.symbol {
                Image(systemName: iconName)
                    .foregroundStyle(domain?.color ?? Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(.primary)
        .textCase(nil)
        .id(title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Een rij in een `List` die naar een pagina leidt: pictogram, titel, een korte waarde en eventueel een regel uitleg.
struct NavigationRow: View {
    let title: String
    let symbol: String?
    let domain: AppDomain?
    let value: String?
    let subtitle: String?
    let destination: Destination

    init(title: String, symbol: String? = nil, domain: AppDomain? = nil, value: String? = nil, subtitle: String? = nil,
         destination: Destination) {
        self.title = title
        self.symbol = symbol
        self.domain = domain
        self.value = value
        self.subtitle = subtitle
        self.destination = destination
    }

    var body: some View {
        DestinationLink(destination: destination) { isButton in
            HStack(spacing: 12) {
                if let symbol {
                    SymbolBadge(symbol: symbol, color: domain?.color ?? Theme.textSecondary, size: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    // De waarde krijgt eerst zijn plek; een lange titel wrapt in de rest.
                    Text(value)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .layoutPriority(1)
                }
                if isButton {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Cijfers

/// Het kerngetal van een pagina of kaart. De enige plek in de app waar tekst mag krimpen (een regel, tot 60%). `label` is de
/// naam die VoiceOver erbij noemt ("Over: € 1.250").
struct BigAmount: View {
    let value: Double
    var font: Font = Theme.heroAmount
    var color: Color = .primary
    var label: String? = nil

    private var spoken: String {
        guard let label else { return Fmt.euro(value) }
        return label + ": " + Fmt.euro(value)
    }

    var body: some View {
        Text(Fmt.euro(value))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animated(by: value)
            .accessibilityLabel(spoken)
    }
}

/// Een getal met een titel in een tegel. De titel wrapt, het bedrag heeft cijfers van gelijke breedte, en tegel is één
/// element voor VoiceOver. Gebruik meerdere tegels naast elkaar in een `FigureRow`.
struct StatTile: View {
    let title: String
    let value: String
    var color: Color = .primary
    var caption: String? = nil
    @Environment(\.tileFillsHeight) private var fillsHeight

    var body: some View {
        let maxHeight: CGFloat? = fillsHeight ? CGFloat.infinity : nil
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .animated(by: value)
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
        .padding(12)
        .tile()
        .accessibilityElement(children: .combine)
    }
}

/// Rond pictogram in de kleur van een onderdeel, pot of belegging: de kleur staat op een tint van 14% (18% in donker). Het
/// pictogram schaalt mee met Dynamic Type (tot 1,6 keer) en is versiering: de naam staat er altijd naast.
struct SymbolBadge: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme

    init(symbol: String, color: Color, size: CGFloat = 40) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    var body: some View {
        let side = size * min(scale, 1.6)
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .padding(side * 0.27)
            .frame(width: side, height: side)
            .foregroundStyle(color)
            .background(color.opacity(colorScheme == .dark ? 0.18 : 0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Knoppen

/// Een pictogramknop met verplicht label (voor VoiceOver en als tooltip op de Mac) en een raakdoel van minstens
/// `Theme.minTapTarget`. Elke knop met alleen een pictogram is een `IconButton`.
struct IconButton: View {
    let label: String
    let symbol: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ label: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.label = label
        self.symbol = symbol
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .help(label)
    }
}

/// De grootte van knoppen: groot op iOS (raakdoel 44 pt), gewoon op de Mac.
private var actionControlSize: ControlSize {
    #if os(macOS)
    return .regular
    #else
    return .large
    #endif
}

/// Een knop in de inhoud: `.bordered`, of voor de ene logische vervolgstap van een pagina `.borderedProminent` met
/// `Theme.accentFill` en `Theme.onAccent` (`prominent`). Maximaal een prominente knop per scherm. De tekst wrapt.
struct ActionButton: View {
    let title: String
    let symbol: String?
    let role: ButtonRole?
    let prominent: Bool
    let action: () -> Void

    init(title: String, symbol: String? = nil, role: ButtonRole? = nil, prominent: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.prominent = prominent
        self.action = action
    }

    /// Een destructieve knop is nooit prominent (BTN-4): de voorkeurskeuze is nooit de knop die iets weggooit.
    private var isProminent: Bool { prominent && role != .destructive }

    var body: some View {
        if isProminent {
            Button(role: role, action: action) {
                ActionLabel(title: title, symbol: symbol)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentFill)
            .controlSize(actionControlSize)
        } else {
            Button(role: role, action: action) {
                ActionLabel(title: title, symbol: symbol)
            }
            .buttonStyle(.bordered)
            .tint(role == .destructive ? Theme.negative : Theme.accent)
            .controlSize(actionControlSize)
        }
    }
}

/// Het label van een actieknop: een symbool en een titel die over meerdere regels mag lopen.
private struct ActionLabel: View {
    let title: String
    let symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(title)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
    }
}

/// Een knop die naar een pagina leidt, in dezelfde stijl als `ActionButton`.
struct ActionLink: View {
    let title: String
    let symbol: String?
    let destination: Destination
    let prominent: Bool

    init(title: String, symbol: String? = nil, destination: Destination, prominent: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.destination = destination
        self.prominent = prominent
    }

    var body: some View {
        if prominent {
            DestinationLink(destination: destination) { _ in
                ActionLabel(title: title, symbol: symbol)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentFill)
            .controlSize(actionControlSize)
        } else {
            DestinationLink(destination: destination) { _ in
                ActionLabel(title: title, symbol: symbol)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .controlSize(actionControlSize)
        }
    }
}

/// Knoppen naast elkaar als ze passen en anders onder elkaar (grote tekst, smal scherm).
struct ActionGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.rowSpacing) {
                content
            }
            VStack(spacing: Theme.rowSpacing) {
                content
            }
        }
    }
}

// MARK: - Lege staat en melding

/// Wat je ziet als er niets te tonen is: uitleg plus (meestal) een knop. `.inline` (standaard) is een compacte versie binnen
/// een kaart; `.page` is een `ContentUnavailableView` voor een hele lege pagina.
struct EmptyHint: View {
    enum Style { case inline, page }

    let symbol: String
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let style: Style

    init(symbol: String, title: String, message: String? = nil, actionTitle: String? = nil,
         action: (() -> Void)? = nil, style: Style = .inline) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.style = style
    }

    var body: some View {
        switch style {
        case .page:
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                if let message { Text(message) }
            } actions: {
                if let actionTitle, let action {
                    ActionButton(title: actionTitle, prominent: true, action: action)
                }
            }
        case .inline:
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if let actionTitle, let action {
                    ActionButton(title: actionTitle, action: action)
                        .frame(maxWidth: 280)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

/// Een melding bovenaan een pagina: een regel uitleg met een symbool en eventueel een knop ("Opnieuw proberen").
struct NoticeCard: View {
    let text: String
    let symbol: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(text: String, symbol: String = "info.circle.fill", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.symbol = symbol
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
            if let actionTitle, let action {
                ActionButton(title: actionTitle, action: action)
            }
        }
        .padding(Theme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

// MARK: - Zoeken

private struct SearchToolbarButton: ViewModifier {
    @Environment(Router.self) private var router

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    IconButton("Zoeken", symbol: "magnifyingglass") {
                        router.requestSearch()
                    }
                }
            }
    }
}

extension View {
    /// Een zoekknop in de werkbalk: hij gaat naar het Overzicht en opent het zoekveld (`router.requestSearch()`).
    func searchToolbarButton() -> some View {
        modifier(SearchToolbarButton())
    }
}

// MARK: - Periode kiezen

/// Chevron-knop met een raakdoel van `Theme.minTapTarget` (44 punten op iOS, 28 op de Mac). Het pictogram blijft aan de
/// buitenkant staan, het tikvlak reikt naar het midden. Buiten het toegestane bereik is de knop gedempt en uit.
private struct StepButton: View {
    let symbol: String
    let label: String
    let alignment: Alignment
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: Theme.minTapTarget, height: Theme.minTapTarget, alignment: alignment)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(PressedStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Hoever je door de maanden kunt bladeren: niet verder terug dan een jaar voor het begin van de gegevens en
/// niet verder vooruit dan vijf jaar na nu. Daarbuiten is er niets zinvols te zien en rekent de app zich suf.
enum MonthWindow {
    static func bounds(startMonth: YearMonth, now: YearMonth) -> (min: YearMonth, max: YearMonth) {
        let upper = now.adding(60)
        return (min(startMonth.adding(-12), upper), upper)
    }
}

/// Terug/vooruit door de maanden. Met `minMonth` en `maxMonth` houden de knoppen je binnen een bereik.
struct MonthStepper: View {
    @Binding var month: YearMonth
    var current: YearMonth
    var minMonth: YearMonth? = nil
    var maxMonth: YearMonth? = nil

    private var canGoBack: Bool {
        guard let minMonth else { return true }
        return month.adding(-1) >= minMonth
    }

    private var canGoForward: Bool {
        guard let maxMonth else { return true }
        return month.adding(1) <= maxMonth
    }

    var body: some View {
        HStack {
            StepButton(symbol: "chevron.left", label: "Vorige maand", alignment: .leading, isEnabled: canGoBack) {
                month = month.adding(-1)
            }
            Spacer()
            VStack(spacing: 1) {
                Text(Fmt.month(month))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if month > current {
                    Text("Verwacht").font(.caption).foregroundStyle(Theme.warning)
                } else if month == current {
                    Text("Deze maand").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            StepButton(symbol: "chevron.right", label: "Volgende maand", alignment: .trailing, isEnabled: canGoForward) {
                month = month.adding(1)
            }
        }
        .padding(.horizontal, 6)
    }
}

/// De kern van de pagina's op de Maand-tab: stapt per maand. Zonder binding staat hij op `router.focusMonth`, binnen de
/// grenzen van `MonthWindow`. Een tik op een pijl geeft een lichte tik (`.selection`).
struct MonthBar: View {
    var month: Binding<YearMonth>?
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    init(month: Binding<YearMonth>? = nil) {
        self.month = month
    }

    var body: some View {
        let window = MonthWindow.bounds(startMonth: store.data.startMonth, now: store.now)
        let binding: Binding<YearMonth> = month ?? Binding(get: { router.focusMonth }, set: { router.focusMonth = $0 })
        MonthStepper(month: binding, current: store.now, minMonth: window.min, maxMonth: window.max)
            .padding(.vertical, 4)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .sensoryFeedback(.selection, trigger: binding.wrappedValue)
    }
}

/// Kiest de lengte van het venster van een grafiek: Maand, Half jaar of Jaar (`router.periodMode`). Verschuift `focusMonth`
/// niet: dat doet alleen de `MonthBar`.
struct PeriodPicker: View {
    @Environment(Router.self) private var router

    init() {}

    var body: some View {
        @Bindable var router = router
        Picker("Periode", selection: $router.periodMode) {
            ForEach(PeriodMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .sensoryFeedback(.selection, trigger: router.periodMode)
    }
}

/// Maand / half jaar / jaar met terug en vooruit. De knoppen stoppen bij de grenzen van `MonthWindow`. Vervalt in pakket G
/// (nieuwe code gebruikt `MonthBar` en `PeriodPicker`).
struct PeriodControl: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var canGoBack: Bool {
        let window = MonthWindow.bounds(startMonth: store.data.startMonth, now: store.now)
        return router.focusMonth.adding(-router.periodMode.stepMonths) >= window.min
    }

    private var canGoForward: Bool {
        let window = MonthWindow.bounds(startMonth: store.data.startMonth, now: store.now)
        return router.focusMonth.adding(router.periodMode.stepMonths) <= window.max
    }

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 10) {
            Picker("Periode", selection: $router.periodMode) {
                ForEach(PeriodMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                StepButton(symbol: "chevron.left", label: "Vorige periode", alignment: .leading, isEnabled: canGoBack) {
                    router.shiftPeriod(-1)
                }
                Spacer()
                VStack(spacing: 1) {
                    Text(Fmt.period(router.periodMode, containing: router.focusMonth))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if let note = statusNote { Text(note).font(.caption).foregroundStyle(Theme.warning) }
                }
                Spacer()
                StepButton(symbol: "chevron.right", label: "Volgende periode", alignment: .trailing, isEnabled: canGoForward) {
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

// MARK: - Account voor bewaarde keuzes

/// Het account waaronder een pagina zijn eigen keuzes op dit apparaat bewaart (zie `AccountPrefs`): met Firebase
/// het cloudaccount ("cloud-<uid>"), anders het lokale account, anders "demo" (voorbeeldsessie). Alle pagina's
/// gebruiken dezelfde id, zodat "Alles wissen" en het verwijderen van een account alles in één keer opruimen.
@MainActor
func accountPrefsID(auth: AuthStore, cloud: CloudAccount?) -> String {
    if FirebaseConfig.isConfigured, let uid = cloud?.user?.uid { return "cloud-" + uid }
    return auth.currentAccount?.id.uuidString ?? "demo"
}

// MARK: - Overgangslaag: de oude namen (tot pakket G)

// Alles hieronder bestaat alleen zodat de pagina's die nog niet zijn omgebouwd blijven compileren en werken. Het uiterlijk
// is al nieuw (kaart in plaats van glas); het gedrag is dat van de oude componenten, ook voor links: een
// `NavigationLink(value:)` op het pad van de eigen stapel, want de oude tabroots hebben elk een eigen stapel. Nieuwe code
// gebruikt `Card`, `LinkCard`, `ActionButton`, `ActionLink`, `ActionGroup` en `ProgressMeter`. Pakket G verwijdert dit.

/// Overgangsvorm van `Card`: dezelfde kaart met de oude parameters. `interactive` en `tint` doen niets meer.
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
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            if let link = headerLink {
                NavigationLink(value: link) {
                    CardHeader(title: title, symbol: symbol, domain: nil, subtitle: subtitle, showsChevron: true)
                }
                .buttonStyle(PressedStyle())
            } else {
                CardHeader(title: title, symbol: symbol, domain: nil, subtitle: subtitle, showsChevron: showsChevron)
            }
            content
        }
        .modifier(CardSurface())
    }
}

/// Overgangsvorm van `LinkCard`.
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
            .buttonStyle(PressedStyle())
        } else {
            NavigationLink(value: destination) { card }
                .buttonStyle(PressedStyle())
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            CardHeader(title: title, symbol: symbol, domain: nil, subtitle: subtitle, showsChevron: true)
            content
        }
        .modifier(CardSurface())
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Overgangsvorm van het label van `ActionButton`: een afgeronde vlakke knop zonder glas, over de hele breedte.
struct ChipLabel: View {
    let title: String
    var symbol: String? = nil
    var destructive = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
                .multilineTextAlignment(.center)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(destructive ? Theme.negative : Theme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
        .background(Theme.tileFill, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Overgangsvorm van `ActionButton`.
struct ChipButton: View {
    let title: String
    var symbol: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            ChipLabel(title: title, symbol: symbol, destructive: role == .destructive)
        }
        .buttonStyle(PressedStyle())
    }
}

/// Overgangsvorm van `ActionLink`.
struct ChipLink: View {
    let title: String
    var symbol: String? = nil
    let destination: Destination

    var body: some View {
        NavigationLink(value: destination) {
            ChipLabel(title: title, symbol: symbol)
        }
        .buttonStyle(PressedStyle())
    }
}

/// Overgangsvorm van `ActionGroup`: knoppen in een raster van even grote cellen.
struct ChipGrid<Content: View>: View {
    var minimumWidth: CGFloat = 150
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: 10)], spacing: 10) {
            content
        }
    }
}

/// Overgangsvorm van `ProgressMeter` (ring).
struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ProgressMeter(value: progress, tint: tint, style: .ring(lineWidth: lineWidth),
                      label: "Voortgang", valueText: Fmt.percent(progress, digits: 0))
    }
}

/// Overgangsvorm van `ProgressMeter` (balk).
struct ProgressBar: View {
    var progress: Double
    var tint: Color
    var height: CGFloat = 8

    var body: some View {
        ProgressMeter(value: progress, tint: tint, style: .bar(height: height),
                      label: "Voortgang", valueText: Fmt.percent(progress, digits: 0))
    }
}

/// Overgangsvorm van `SegmentedMeter`: één balk die in stukken is verdeeld.
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
                }
                if positive.isEmpty {
                    Capsule().fill(Theme.tileFill)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .animated(by: positive.map(\.value))
    }
}
