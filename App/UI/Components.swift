import SwiftUI

// De bouwstenen van het ontwerpsysteem (par. 4.3 t/m 4.5 van docs/design/plan.md): pagina's, kaarten, cijfers, knoppen en
// de maandkiezer. Geen glas in de inhoud: een kaart is `Theme.card` op het kleurverloop van `BackdropGradient`. Glas komt van
// het systeem (tabbalk, werkbalk, bladen). De tegels, planken, rijen en pillen van ontwerp 2 staan in Tiles.swift, Shelf.swift,
// Hero.swift, Rows.swift, Album.swift en Pills.swift.

// MARK: - Pagina's

/// Een pagina van kaarten (tabroot of rekenpagina): een `ScrollView` op het kleurverloop van `BackdropGradient` (de tint komt
/// uit `\.backdropHue`). `large` geeft de grote titel (alleen op een tabroot), anders staat de titel klein in de balk. De
/// inhoud scrolt onder de werkbalk door. Met `fullBleed` (Home) heeft de inhoud geen horizontale marge en is hij hoogstens
/// `Theme.shelfMaxWidth` breed: hero en planken regelen hun eigen marge.
struct PageScaffold<Content: View>: View {
    let title: String
    var large: Bool = false
    var fullBleed: Bool = false
    @ViewBuilder var content: Content
    @Environment(\.backdropHue) private var backdropHue

    /// `.large` bestaat alleen op iOS en iPadOS; op de Mac is de titel altijd inline.
    private var titleMode: ToolbarTitleDisplayMode {
        #if os(iOS)
        return large ? .large : .inline
        #else
        return .inline
        #endif
    }

    var body: some View {
        ScrollView {
            margined
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: fullBleed ? Theme.shelfMaxWidth : Theme.pageMaxWidth)
                .frame(maxWidth: .infinity)
                #if DEBUG
                .offset(y: -DebugLaunch.scrollOffset)
                #endif
        }
        .scrollDismissesKeyboard(.interactively)
        .background { BackdropGradient(hue: backdropHue) }
        .navigationTitle(title)
        .toolbarTitleDisplayMode(titleMode)
    }

    /// De inhoud met de paginamarge van het systeem, of zonder bij `fullBleed`.
    @ViewBuilder
    private var margined: some View {
        if fullBleed {
            content
        } else {
            content.scenePadding(.horizontal)
        }
    }
}

/// Een pagina van rijen (`List`) met swipe-acties: Inkomen, Uitgaven, Spaarpotten, Beleggingen, Doelen en Instellingen.
/// De lijst staat op het kleurverloop van `BackdropGradient` en is niet breder dan `Theme.readableWidth`. In een debug-build scrolt hij naar de sectie
/// uit `-mybuddy-scroll-to` (de koptekst van een `SectionHeader`).
struct ListScaffold<Content: View>: View {
    let title: String
    var large: Bool = false
    @ViewBuilder var content: Content
    @Environment(\.backdropHue) private var backdropHue

    /// `.large` bestaat alleen op iOS en iPadOS; op de Mac is de titel altijd inline.
    private var titleMode: ToolbarTitleDisplayMode {
        #if os(iOS)
        return large ? .large : .inline
        #else
        return .inline
        #endif
    }

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
            .background { BackdropGradient(hue: backdropHue) }
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

/// De gedeelde link naar een bestemming (K16, B5). Een pagina opent op de stapel waar je bent: een `NavigationLink(value:)`, dus
/// het pad loopt door `NavigationRules.normalize` en een pagina staat nooit twee keer in een pad. Met `showsCurrentMonth` zet
/// een tik eerst de maandpagina's op de huidige maand (`router.showCurrentMonth`) en opent daarna via `router.open`. De
/// sluiting krijgt `true` als het een knop is (dan tekent het systeem geen pijltje en moet het label dat zelf doen).
struct DestinationLink<Inner: View>: View {
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
        if showsCurrentMonth {
            Button {
                router.showCurrentMonth(store.now)
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
            .buttonBorderShape(.capsule)
            .tint(Theme.accentFill)
            .controlSize(actionControlSize)
        } else {
            Button(role: role, action: action) {
                ActionLabel(title: title, symbol: symbol)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
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
            .buttonBorderShape(.capsule)
            .tint(Theme.accentFill)
            .controlSize(actionControlSize)
        } else {
            DestinationLink(destination: destination) { _ in
                ActionLabel(title: title, symbol: symbol)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
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

// MARK: - Account voor bewaarde keuzes

/// Het account waaronder een pagina zijn eigen keuzes op dit apparaat bewaart (zie `AccountPrefs`): met Firebase
/// het cloudaccount ("cloud-<uid>"), anders het lokale account, anders "demo" (voorbeeldsessie). Alle pagina's
/// gebruiken dezelfde id, zodat "Alles wissen" en het verwijderen van een account alles in één keer opruimen.
@MainActor
func accountPrefsID(auth: AuthStore, cloud: CloudAccount?) -> String {
    if FirebaseConfig.isConfigured, let uid = cloud?.user?.uid { return "cloud-" + uid }
    return auth.currentAccount?.id.uuidString ?? "demo"
}
