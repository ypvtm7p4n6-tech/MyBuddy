# Patronen van Apple Muziek en Apple TV, vertaald naar SwiftUI en naar MyBuddy

Peildatum 23 oktober 2026. Onderzoeker, ontwerpronde 2. Opdracht van de gebruiker (letterlijk): "zoek de skill die de design guidelines volgt van Apple. Verander het design opnieuw waardoor de app simpeler wordt. Het idee in mijn hoofd is een combinatie van Apple Music en de Apple TV apps."

In `docs/design2/` is alleen dit document geschreven; er is niets in `App/` of `CoreTests/` aangepast en er is geen schrijvend git-commando uitgevoerd. Proefbestanden (sessiemap, niet permanent): `/tmp/claude-0/-home-user-MyBuddy/9beb118c-8e88-5a84-a4b5-426733aaf64d/scratchpad/d2/` met `swift/` (alle codeschetsen hieronder, letterlijk), `api/` (Apple-documentatie-JSON), `txt/` (HIG-tekst) en `d2tools/` (scripts voor maten, contrast, beschikbaarheid, syntaxiscontrole).

## 0. Leeswijzer

**Bronlabels.** Elke bewering heeft er een; waar `[K]` staat is het kennis of afleiding en niet uit een gelezen bron.

- `[B:onderwerp]` = officiële HIG-tekst, gelezen via de JSON-route `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<onderwerp>.json` (pagina `.../design/human-interface-guidelines/<onderwerp>`). Voor lockups en top-shelf via WebFetch; de rest met curl en een omzetscript, omdat WebFetch lange pagina's samenvat en afkapt.
- `[W:jaar-sessie]` = transcript van een WWDC-sessie op developer.apple.com, via WebFetch. Let op: WebFetch geeft een samenvatting door een klein model, geen woordelijke tekst; waar de samenvatting iets afwijkends zei is dat met de API-documentatie gecontroleerd (zie par. 1, fout 2).
- `[A:symbool]` = Apple's API-documentatie-JSON (`.../tutorials/data/documentation/swiftui/<symbool>.json`), vooral beschikbaarheid.
- `[D:artikel]` = Apple-documentatieartikel (de Landmarks-voorbeeldapp).
- `[S]` = alleen een WebSearch-resultaat gezien, de pagina zelf niet geopend (`apple.com`, `support.apple.com`, `9to5mac.com` en `skills.sh` waren niet bereikbaar: proxy 403 of geen DNS).
- `[P]` = proefberekening met een script (maten, contrast). `[T]` = syntaxiscontrole met tree-sitter-swift.

**Eerlijkheid over Muziek en TV.** De HIG noemt Muziek en TV alleen in voorbij­gaande voorbeelden (tabbalk, zoeken, minispeler). Hoe hun schermen er precies uitzien (hero, planken, albumkop, afmetingen) kon ik niet uit een gelezen bron vaststellen; dat is `[K]` en staat per patroon apart. Alle afmetingen die ik voorstel zijn eigen keuzes, geen gemeten Apple-waarden.

**Bouwvolgorde van een patroon hieronder:** Apple doet, Maten en typografie, SwiftUI (iOS 18 en macOS 15 als ondergrens, iOS 26 apart), Valkuilen, MyBuddy.

## 1. Skills-beoordeling

**Kort antwoord.** Van de twee past `raintree-technology/apple-hig-skills` (de `hig-*`-skills) het best bij de wens "de richtlijnen van Apple volgen", omdat hij de hele HIG afdekt; maar het is een uitgekleed en deels verouderd uittreksel. Om in SwiftUI uit te voeren is `rshankras/claude-code-apple-skills` (`design`) bruikbaarder, mits elk API wordt nagekeken (er staan drie fouten in). Geen van beide is nodig zolang Apple's eigen HIG-JSON en API-documentatie de bron zijn, zoals in `docs/design/hig-notes.md`.

Geïnstalleerd (alleen markdown, uit `skills-lock.json`): `design` van `rshankras/claude-code-apple-skills` (met liquid-glass, animation-patterns, typography, sf-symbols, ux-writing, game-feel, ui-prototyping) en 14 `hig-*`-skills van `raintree-technology/apple-hig-skills`.

| | rshankras `design` | raintree `hig-*` |
|---|---|---|
| Reputatie (GitHub-pagina's, 23 okt. 2026, via een WebFetch-samenvatting) | 824 sterren, 77 forks, 121 commits, MIT; repo heeft 164 skills in 23 categorieën | 148 sterren, 10 forks, 134 commits, MIT; de repo heet nu `hig-doctor`; README: de skillcorpus is "frozen 2025-02-02 snapshot, 14 skills, 156 reference topics" |
| Installatie-aantallen | niet vast te stellen: `skills.sh` en de GitHub-API waren niet bereikbaar | idem |
| Inhoud | SwiftUI-recepten voor iOS 26: `glassEffect`, `GlassEffectContainer`, tab-bar-gedrag, zoom-overgangen, typografie, animaties; `last_verified: 2026-07-16` | per HIG-onderwerp een `references/*.md` met vooral de vetgedrukte kernzinnen van de HIG en weinig uitleg; daarboven korte SKILL.md's met "Questions to ask" |
| Actualiteit | recent, maar `os_version: iOS 27 / macOS 27` terwijl dit project Xcode 26 gebruikt | label 2025-02-02, inhoud gemengd; bijvoorbeeld `tab-bars.md` mist de iOS-alinea over MiniPlayer, minimaliseren en zoektab die Apple's HIG nu heeft |
| Past bij "Apple's design guidelines volgen" | als uitvoeringshulp voor iOS 26-API's | letterlijk het best passend qua doel, maar te dun om iets te sturen |

**Veiligheid** (`find` en `grep` over `skills-hig/`): 186 `.md`-bestanden en 1 `skills-lock.json`; 0 uitvoerbare bestanden; geen `.sh`, `.py`, `.js` of `.swift`; 15 symlinks in `.claude/skills/` die relatief naar `.agents/skills/` wijzen; geen regel met `curl`, `wget`, `npx`, `sudo`, `eval` of een shell-prompt; URL's alleen naar `developer.apple.com` (628), `raintree.technology` (28, voetregels), `apple.com` (2) en `support.apple.com` (1); geen zinnen als "ignore previous instructions". Bij rshankras staat in `allowed-tools` van `ui-prototyping` het gereedschap Bash, maar de tekst bevat geen commando's; `design/SKILL.md` zegt dat de agent optioneel `~/Downloads/docs/*.md` leest als die bestaan (buiten het project, alleen lezen). Netwerktoegang: geen. Kortom: veilig om als gegevens te lezen.

**Juistheid** (gecontroleerd tegen Apple's documentatie-JSON, `[A]`): drie fouten die code zouden breken als ze klakkeloos werden overgenomen.

1. `liquid-glass/SKILL.md` noemt `.scrollExtensionMode(.underSidebar)`: dat symbool bestaat niet (404 in de documentatie). Apple's eigen voorbeeld laat een horizontale scrollview gewoon tegen de zijranden aan lopen en het systeem regelt de rest `[D:landmarks-extending-horizontal-scrolling]`.
2. Dezelfde skill noemt `.rect(corner: .containerConcentric)`; het echte API is `ConcentricRectangle(corners: .concentric(minimum: .fixed(8)), isUniform: true)` (iOS 26) `[A:concentricrectangle, edge/corner/style]`. (Het WebFetch-overzicht van WWDC25-sessie 323 noemt dezelfde schrijfwijze, mogelijk uit het transcript en dan een bètanaam; in de gepubliceerde documentatie bestaat alleen `concentric`.)
3. `animation-patterns/transitions.md` noemt `.navigationTransition(.slide)`: bestaat niet. Er zijn `.automatic`, `.zoom(sourceID:in:)` en `.crossFade` (dat laatste is iOS 27, dus niet bruikbaar met Xcode 26) `[A:navigationtransition]`.

Verder: de checklist "gebruik `.glassEffect()` in plaats van `.background(.material)`" is in strijd met de HIG (geen glas in de inhoudslaag `[B:materials]`); de zes regels uit "Design Rules (WWDC25)" zelf kloppen wel. De `animation-patterns`-API-tabel (bijvoorbeeld `matchedTransitionSource` en zoom vanaf iOS 18, `scrollTransition` en `visualEffect` vanaf iOS 17) komt overeen met mijn controle. Niet in de skills, wel nu ontdekt: zie par. 3.6 (macOS-beschikbaarheid), dat geen van beide skills behandelt.

**Aanbeveling.** (1) De beste "skill" voor "de richtlijnen van Apple volgen" is Apple's eigen HIG-tekst plus de API-documentatie, en die zit al in `docs/design/hig-notes.md` en in dit document; geen van de twee derde-partij-skills voegt waarheid toe. (2) Voeg niets uit de skills toe aan `docs/design/hig-notes.md`: dat bestand is rechtstreeks uit de HIG-JSON opgebouwd, en de skills brengen fouten (hierboven) en een verouderd label mee. (3) Gebruik rshankras `liquid-glass` en `animation-patterns` hooguit als geheugensteun voor API-namen en controleer elk symbool in de documentatie-JSON; gebruik raintree alleen als trefwoordenindex. (4) Zet in `hig-notes.md` hooguit drie regels "bekende fouten in derde-partij-skills" (de drie hierboven), zodat niemand ze later overneemt.

## 2. Het voorstel in een oogopslag

Muziek en TV delen een grammatica: een tabbalk met weinig items en een aparte zoektab, grote titels, een profielknop rechtsboven, bovenaan een hero, daaronder horizontale planken met dezelfde tegelvorm, en per ding een pagina met een grote kop. Vertaald:

```
Tabbalk (iPhone) / zijbalk (iPad, Mac): Overzicht, Bibliotheek, Zoeken (Tab(role: .search))
Profielknop rechtsboven op Overzicht en Bibliotheek: Account en Instellingen
Overzicht      grote titel, hero (Nog te verdelen, Vermogen, Saldo vandaag), planken:
               Komende dagen (brede kaarten), Spaarpotten, Beleggingen, Doelen  (+ Hulpmiddelen, optioneel)
Bibliotheek    lijst, 3 groepen, 12 rijen met pictogram en pijltje
Zoeken         zoekveld, bladercategorieën als gekleurde tegels, resultaten gegroepeerd
Spaarpot, Belegging, Doel   "albumpagina": kop met tegel, titel, ondertitel, kerngetal en twee capsule-knoppen, dan lijstsecties
```

**Waarom dit simpeler is.** Topniveau: 5 tabs (4 op de Mac) naar 3 plus een profielknop. Elke plek waar je iets "zoals een album" opent heeft dezelfde tegel en dezelfde paginakop. Het Overzicht heeft nog twee bouwstenen (hero en plank) in plaats van vier verschillende kaartsoorten. De kaartenpagina's per tab verdwijnen; wat blijft zijn de lijst- en rekenpagina's die al bestaan.

**Wat moet beslist worden** (ik beslis niet): (a) de tabs Maand en Plannen vervallen; hun pagina's (Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag, Doelen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck) zijn dan alleen via Bibliotheek, planken en zoeken bereikbaar. (b) `BlockOrder` ("Volgorde aanpassen") heeft geen functie meer als de planken vast staan; Muziek en TV laten de plankvolgorde ook niet door de gebruiker kiezen `[K]`. (c) De door de gebruiker eerder gevraagde keuze van drie potten en vier beleggingen voor de eerste tab (K9a in `plan.md`) past op de plank: toon eerst de gekozen favorieten, dan de rest; het keuzeblad kan bestaan blijven in het plankmenu. (d) Profielknop: Muziek en TV openen daar een blad `[K]`; `plan.md` K3/SET-4 besloot dat Instellingen geen sheet is. Aanbeveling: een duwpagina (`Destination.settings`), conform dat besluit.

## 3. Gemeenschappelijke maten en bouwstenen

### 3.1 Maten

| Onderdeel | iPhone (compact) | iPad en Mac (regular) | Bron |
|---|---|---|---|
| Paginamarge, tussenruimte tegels | 16 en 12 pt | 20 en 16 pt | `[K]` |
| Hero-kaart, radius | 28 pt | 28 pt | `[K]`; binnenradius = buitenradius min marge (concentrisch) `[B:adopting-liquid-glass]`, `[W:2025-356]` |
| Tegel, radius | 16 pt | 16 pt | `[K]` |
| Kopartwork op detailpagina, radius | 24 pt, 200 tot 220 pt breed | 24 pt, 200 pt | `[K]` |
| Raakdoel | 44 pt | 28 pt | `docs/design/hig-notes.md` ACC-2 `[B:accessibility]` |
| Paginastippen | 7 pt, 8 pt ertussen, hoogstens ongeveer 10 | niet op macOS | `[B:page-controls]` |
| Hoeken van capsule-knoppen | halve hoogte | idem | `[W:2025-356]` |

### 3.2 Tekststijlen

De iOS-tabel van de HIG is een afbeelding en staat niet in de JSON; de iOS-maten zijn dus `[K]` (de bekende standaardgroottes). De macOS-maten komen uit de tabel `[B:typography]`.

| Gebruik | Stijl | iOS | macOS |
|---|---|---|---|
| Grote titel (tabroot) | `.largeTitle` | 34 pt | 26 pt |
| Hero-bedrag | `.largeTitle.bold()` met `.monospacedDigit()` | 34 pt | 26 pt |
| Plankkop | `.title2.weight(.semibold)` | 22 pt | 17 pt |
| Titel kopartwork | `.title2.bold()` | 22 pt | 17 pt |
| Tegeltitel en tegelwaarde, "Toon alles" | `.subheadline` (titel semibold) | 15 pt | 11 pt |
| Lijstrij | `.body`, bijschrift `.subheadline` | 17 en 15 pt | 13 en 11 pt |

Alleen tekststijlen (`TYP-1`): geen `.font(.system(size:))`, geen `.caption2`, geen `.rounded`. `Theme.textSecondary` voor bijschriften.

### 3.3 Tegelkleuren en kleurverloop (berekend, `[P]`)

Zeven tegelpaletten, een per `AppDomain` (de bestaande domeinkleuren zijn voor pictogrammen en wisselen met licht en donker; in donker zijn ze te licht voor witte tekst). Witte tekst en symbolen op beide kleurstops, WCAG-contrast (tekst minimaal 4,5; de HIG vraagt 4,5 tot en met 17 pt `[B:accessibility]`):

| Palet (domein) | Bovenste stop | Wit op boven | Onderste stop | Wit op onder |
|---|---|---|---|---|
| olijf (overview) | `#5C7A2A` | 4,92 | `#34471A` | 10,18 |
| terracotta (money) | `#B0552B` | 5,02 | `#7C3517` | 8,83 |
| saliegroenblauw (saving) | `#2B7A6D` | 5,11 | `#1B4F46` | 9,32 |
| leiblauw (investing) | `#4A6FA8` | 5,08 | `#2C4573` | 9,52 |
| mosterd (goals) | `#966C00` | 4,73 | `#6B4D00` | 7,82 |
| pruim (tools) | `#8A5A80` | 5,45 | `#5A3453` | 10,24 |
| saliegrijs (settings) | `#68705C` | 5,17 | `#40473A` | 9,63 |

(Mosterd `#9A7000` haalde 4,48 en is daarom aangepast.) Het kleurverloop achter een detailpagina is de tint over `Theme.canvas`. Gemeten met `Theme.textSecondary` en nagerekend met dezelfde perceptuele (Oklab-)menging die `Color.mix` standaard gebruikt (`d2tools/oklab.py`): **donker** hoogstens 50% van de onderste stop, dan minimaal 6,64:1 voor bijschriften en minimaal 13,32:1 voor wit; **licht** hoogstens 18% van de bovenste stop, dan minimaal 4,57:1 voor bijschriften en minimaal 14,47:1 voor zwart. (Bij een gewone sRGB-menging ligt de lichte grens per palet tussen 19 en 21%; de marge boven 4,5:1 is dus klein, houd 18% aan.) Bij "Verhoog contrast" of "Verlaag transparantie": geen tint. Een tint naast een olijf-accent op een tabroot is te vermijden `[B:tab-bars]`: de kleurverlopen alleen op detailpagina's.

### 3.4 Maten voor hero en planken (berekend met de formules uit `10_Metrics.swift`, `[P]`)

`binnen marges` is de breedte die `containerRelativeFrame` geeft nadat de paginamarge is afgetrokken (volgens `[A:containerrelativeframe]` trekt hij de veilige-gebied-marges af; of `safeAreaPadding` daar echt zo in meetelt moet op een toestel worden gecontroleerd).

| Breedte | Marge en ruimte | Binnen marges | Hero | Tegels zichtbaar | Tegelbreedte | Brede kaart |
|---|---|---|---|---|---|---|
| iPhone 16e (375) | 16 en 12 | 343 | 323 pt, carrousel | 2 en een deel | 133 pt | 278 pt |
| iPhone 16 (393) | 16 en 12 | 361 | 341 pt, carrousel | 2 en een deel | 140 pt | 293 pt |
| iPhone 16 Pro Max (440) | 16 en 12 | 408 | 388 pt, carrousel | 2 en een deel | 160 pt | 332 pt |
| Mac-venster klein (640) | 20 en 16 | 600 | 480 pt, carrousel | 3 en een deel | 162 pt | 341 pt |
| iPad mini staand (744) | 20 en 16 | 704 | 480 pt, carrousel | 4 en een deel | 145 pt | 307 pt |
| iPad 11 staand (834) | 20 en 16 | 794 | 480 pt, carrousel | 4 en een deel | 166 pt | 348 pt |
| Mac-venster 900 | 20 en 16 | 860 | 276 pt, drie naast elkaar | 5 en een deel | 144 pt | 305 pt |
| iPad 13 staand (1032) | 20 en 16 | 992 | 320 pt, drie naast elkaar | 6 en een deel | 140 pt | 296 pt |
| iPad 13 liggend, Mac 1366 | 20 en 16 | 1326 | 431 pt, drie naast elkaar | 8 en een deel | 143 pt | 301 pt |

De tegel blijft tussen 133 en 166 pt breed; alleen het aantal verandert met de breedte. Er is steeds ongeveer 0,4 tegel plus de paginamarge van de volgende te zien, zodat duidelijk is dat de plank doorloopt `[B:scroll-views]`.

```swift
/// Maten voor hero en planken. Zuivere functies: te verplaatsen naar Foundation-only code en te testen in CoreTests.
enum ShelfMetrics {
    /// Extra zichtbare rand van de volgende hero-kaart, bovenop de paginamarge.
    static let heroPeek: CGFloat = 8

    /// Paginamarge en tussenruimte: iPhone (compact) 16 en 12, iPad en Mac (regular, of onbekend) 20 en 16.
    static func margin(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { sizeClass == .compact ? 16 : 20 }
    static func spacing(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { sizeClass == .compact ? 12 : 16 }

    /// Breedte van een tegel in een plank. `length` is de breedte binnen de veilige marges, zoals `containerRelativeFrame` hem geeft.
    /// Er passen `whole` hele tegels en 0,4 tegel van de volgende (plus de paginamarge): zo zie je dat de plank doorloopt.
    static func tileWidth(in length: CGFloat, spacing: CGFloat = 12) -> CGFloat {
        guard length.isFinite, length > 0 else { return 140 }   // `Int(.infinity)` zou crashen
        let whole = max(2, Int((length + spacing) / (150 + spacing)))
        return (length - CGFloat(whole) * spacing) / (CGFloat(whole) + 0.4)
    }

    /// Breedte van een brede kaart (16:9, zoals "Volgende" in de TV-app): twee tegels plus de tussenruimte.
    static func wideTileWidth(in length: CGFloat, spacing: CGFloat = 12) -> CGFloat {
        2 * tileWidth(in: length, spacing: spacing) + spacing
    }

    /// Breedte van een hero-kaart: een kaart plus een rand van de volgende; vanaf 860 pt drie naast elkaar.
    static func heroWidth(in length: CGFloat, spacing: CGFloat = 12) -> CGFloat {
        guard length.isFinite, length > 0 else { return 300 }
        if length >= 860 { return (length - 2 * spacing) / 3 }
        return min(length - spacing - heroPeek, 480)
    }

    static func showsHeroCarousel(in length: CGFloat) -> Bool { length < 860 }
}
```

De formules zijn zuivere functies; voor een test in `CoreTests` dezelfde berekening met `Double` en een `Bool` voor "compact" (`UserInterfaceSizeClass` is SwiftUI).

### 3.5 Beschikbaarheid van de gebruikte API's (uit Apple's documentatie-JSON, `[A]`)

Ondergrens van dit project: iOS 18 en macOS 15. Alles tot en met 18 hoeft dus geen `#available`; "niet" betekent dat het symbool op die platformen ontbreekt in de documentatie.

| API | iOS | macOS | Opmerking |
|---|---|---|---|
| `ScrollView`, `LazyHStack`, `LazyVGrid`, `GridItem` | 13 tot 14 | 10.15 tot 11 | |
| `scrollTargetLayout()`, `scrollTargetBehavior(.viewAligned / .paging)` | 17 | 14 | |
| `.viewAligned(limitBehavior:)`; `.alwaysByOne` | 17; 18 | 14; 15 | |
| `.viewAligned(limitBehavior:anchor:)` | 26 | 26 | |
| `containerRelativeFrame` (count, span en sluitingsvariant) | 17 | 14 | |
| `scrollTransition(_:axis:transition:)`, `visualEffect(_:)` | 17 | 14 | |
| `scrollPosition(id:anchor:)`; `ScrollPosition` met `scrollPosition(_:anchor:)` | 17; 18 | 14; 15 | |
| `safeAreaPadding`, `contentMargins`, `scrollClipDisabled` | 17 | 14 | |
| `MeshGradient`, `Color.mix(with:by:in:)` | 18 | 15 | |
| `Tab`, `TabSection`, `.tabViewStyle(.sidebarAdaptable)`, `Tab(role: .search)` | 18 | 15 | |
| `searchable(text:isPresented:placement:prompt:)` | 17 | 14 | zonder `isPresented`: iOS 16, macOS 13 |
| `searchToolbarBehavior(_:)`, `DefaultToolbarItem` | 26 | 26 | |
| `tabBarMinimizeBehavior(_:)` | 26 | 26 | op macOS alleen `.automatic`; `.onScrollDown`, `.onScrollUp`, `.never` alleen iOS en iPadOS |
| `tabViewBottomAccessory(content:)` | 26.0 | niet | alleen iOS en iPadOS |
| `tabViewBottomAccessory(isEnabled:content:)` | 26.1 | niet | |
| `tabViewBottomAccessoryPlacement` (omgevingswaarde) | 26 | 26 | `.inline`, `.expanded` |
| `ToolbarItemPlacement.topBarTrailing` | 14 | niet | macOS: `.primaryAction` |
| `toolbarTitleDisplayMode(_:)` | 17 | 14 | documentatie: "no effect on macOS"; `.large` bestaat niet op macOS |
| `navigationSubtitle(_:)` | 26 | 13 | |
| `navigationTransition(_:)`, `matchedTransitionSource(id:in:)` | 18 | 15 | |
| `NavigationTransition.zoom(sourceID:in:)` | 18 | niet | |
| `containerBackground(for: .navigation)` | 18 | niet | |
| `contextMenu(menuItems:preview:)`, `contentShape(.contextMenuPreview, _)` | 16; 15 | 13; 12 | preview alleen op iOS en iPadOS `[B:context-menus]` |
| `ToolbarSpacer`, `sharedBackgroundVisibility(_:)` | 26 | 26 | |
| `glassEffect(_:in:)`, `GlassEffectContainer`, `.glass`, `.glassProminent` | 26 | 26 | |
| `backgroundExtensionEffect()`, `safeAreaBar(edge:...)` | 26 | 26 | |
| `scrollEdgeEffectStyle(_:for:)`, `ScrollEdgeEffectStyle` | 26 | 26 | |
| `ConcentricRectangle`, `Edge.Corner.Style.concentric(minimum:)`, `containerShape(_:)` met `RoundedRectangularShape` | 26 | 26 | |
| `hoverEffect(_:)` | 13.4 | niet | |
| `NavigationTransition.crossFade` | 27 | niet | niet bruikbaar met Xcode 26 |

### 3.6 Wat niet op macOS bestaat en het project raakt

`#available(macOS 26.0, *)` helpt niet voor een symbool dat op macOS helemaal ontbreekt; dat vraagt `#if os(iOS)` (of `#if !os(macOS)`). In de schetsen is dat verwerkt. Twee plekken in de bestaande code vallen volgens de documentatie in dezelfde categorie en horen in de macOS-job van de CI (`.github/workflows/ci.yml`, "Bouwen macOS") te worden nagelopen; ik kan de CI-uitslag hier niet zien:

- `App/RootView.swift:118`: `content.tabBarMinimizeBehavior(.onScrollDown)` binnen `#available(iOS 26.0, macOS 26.0, *)`. `.onScrollDown` staat alleen voor iOS, iPadOS en Mac Catalyst in de documentatie.
- `App/UI/Components.swift:18,47`: `ToolbarTitleDisplayMode.large` zonder `#if`. De documentatie vermeldt voor `.large` geen macOS, en `toolbarTitleDisplayMode` "has no effect on macOS". `docs/design/hig-notes.md` (NAV-2, regel 13 van de top 15) zegt dat het "overal werkt": dat is daarmee te corrigeren.

## 4. De patronen

### 4.1 Hero-carrousel

**Apple doet.** Muziek (Home en Nieuw): bovenaan een rij grote kaarten die per kaart snappen, met de volgende kaart zichtbaar `[K]`. TV: bovenaan Home een schermbrede carrousel met key art, titel, korte tekst, een afspeelknop en een plusknop, paginastippen eronder `[K]`. De HIG beschrijft het tvOS-equivalent: Top Shelf "carousel actions" met een primaire en een Meer-info-knop, titel plus optionele ondertitel, en de "scrolling inset banner": "Provide three to eight images. A minimum of three images is recommended for a scrolling banner to feel effective. More than eight images can make it hard to navigate to a specific image." Tekst die in de afbeelding staat hoort ook in het toegankelijkheidslabel `[B:top-shelf]`. Apple's eigen SwiftUI-voorbeeld heeft een uitgelicht item als kop en daaronder planken per sectie `[D:landmarks-building-an-app-with-liquid-glass]`.

**Maten en typografie.** Tabel 3.4. Kaart minimaal ongeveer 168 pt hoog en inhoudsgedreven (geen vaste verhouding, anders breekt Dynamic Type), radius 28, kop `.subheadline`, bedrag `.largeTitle.bold()`, daaronder een regel `.subheadline`. Drie kaarten (meer dan ongeveer 10 stippen zijn volgens de HIG moeilijk te tellen `[B:page-controls]`). Paginastippen gecentreerd onderaan, niet gekleurd (`primary` en `primary` op 30%) `[B:page-controls]`.

**SwiftUI.** iOS 17: `ScrollView(.horizontal)`, `scrollTargetLayout()`, `scrollTargetBehavior(.viewAligned)` (voor een zichtbare volgende kaart; `.paging` voor schermbrede kaarten zonder rand), `containerRelativeFrame` met sluiting, `scrollPosition(id:)` voor de stippen, `scrollTransition` voor een lichte fade, `visualEffect` voor optionele parallax (`heroParallax` onderaan het blok; niet gebruikt). iOS 18: `ScrollPosition` met `scrollTo(id:)` voor knoppen. iOS 26: niets nodig voor een vlak met een kleurverloop; `backgroundExtensionEffect()` (par. 4.15) alleen voor een echte afbeelding. Alternatief met systeemstippen: `TabView` met `.tabViewStyle(.page)` en `.indexViewStyle(...)`, maar dat bestaat niet op macOS en heeft geen zichtbare volgende kaart.

```swift
struct HeroCarousel<Card: View>: View {
    let heroes: [HeroItem]
    @ViewBuilder var card: (HeroItem) -> Card

    @State private var current: HeroItem.ID?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if typeSize.isAccessibilitySize {
            // Bij toegankelijkheidsformaten: onder elkaar, geen zijwaarts scrollen.
            VStack(spacing: 12) {
                ForEach(heroes) { card($0) }
            }
            .padding(.horizontal, ShelfMetrics.margin(sizeClass))
        } else {
            VStack(spacing: 10) {
                ScrollView(.horizontal) {
                    // Geen LazyHStack: drie kaarten, en VoiceOver moet ze alle drie kunnen bereiken.
                    HStack(spacing: ShelfMetrics.spacing(sizeClass)) {
                        ForEach(heroes) { hero in
                            card(hero)
                                .containerRelativeFrame(.horizontal) { length, _ in
                                    ShelfMetrics.heroWidth(in: length, spacing: ShelfMetrics.spacing(sizeClass))
                                }
                                .scrollTransition(axis: .horizontal) { content, phase in
                                    content.opacity(reduceMotion || phase.isIdentity ? 1 : 0.7)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $current)
                .scrollIndicators(.hidden)
                .safeAreaPadding(.horizontal, ShelfMetrics.margin(sizeClass))

                PageDots(count: heroes.count, index: heroes.firstIndex { $0.id == current } ?? 0)
            }
        }
    }
}

struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pagina \(index + 1) van \(count)")
    }
}

extension View {
    /// Optionele lichte parallax van een hero-kaart met `visualEffect` (zonder `GeometryReader`). Muziek en TV doen dit in de
    /// hero niet `[K]`; zet het uit bij Verlaag beweging. Niet gebruikt in `HeroCarousel`.
    func heroParallax(enabled: Bool) -> some View {
        visualEffect { content, proxy in
            content.offset(x: enabled ? proxy.frame(in: .scrollView).minX * -0.08 : 0)
        }
    }
}
```

**Valkuilen.** (1) Een `LazyHStack` maakt buiten beeld geen kaarten; met drie kaarten daarom een gewone `HStack`, anders kan VoiceOver ze niet bereiken. (2) Bij toegankelijkheidsformaten onder elkaar in plaats van zijwaarts (`isAccessibilitySize`). (3) Verlaag beweging: de fade valt weg. (4) macOS: de HIG kent daar geen paginastippen. Vanaf 860 pt breed staan de drie kaarten naast elkaar (geen carrousel); in een smaller venster horen Vorige/Volgende-knoppen naast de kaarten (`ScrollPosition.scrollTo`), want `scrollIndicators(.hidden)` laat muisgebruikers zonder aanwijzing `[W:2023-10159]` (samenvatting van de sessie). (5) Een carrousel verbergt twee van de drie getallen; elk getal is ook elders te vinden (Verdelen, Bankrekening, Vermogen). (6) Padding op de `ScrollView` knipt de inhoud af; gebruik `safeAreaPadding` `[W:2023-10159]`.

**MyBuddy.** Drie kaarten, kleur van het domein van de bestemming: **Nog te verdelen** (in deze maand; opent Verdelen), **Vermogen** (einde van de maand, met het verschil met vorige maand als tekst met teken; opent een Vermogen-pagina met de huidige `wealth`-inhoud), **Saldo vandaag** (opent Bankrekening). Nog simpeler alternatief zonder carrousel: één hero-kaart "Nog te verdelen" met daaronder twee regels Vermogen en Saldo vandaag; dat verliest het Apple-gevoel maar verbergt niets.

### 4.2 Plankenrij (shelf)

**Apple doet.** Muziek en TV: een sectiekop (titel met pijltje of "Toon alles"/"See All"), eronder een horizontaal scrollende rij met snappen, per rij een soort tegel; de rij loopt tot de schermrand, de volgende tegel is deels zichtbaar; op iPad en Mac passen er meer tegels `[K]`. De HIG: "use scrollable sections to showcase additional content, which is particularly useful for media-focused apps like those for video, music, or books" `[B:layout]`; "use the standard row or grid layout" en "use adequate padding around images to keep focus or hover effects easy to see" `[B:collections]`; scrollviews lopen standaard onder de zijbalk door, zodat carrousels er doorheen schuiven (samenvatting van de sessie) `[W:2025-356]`; tvOS: extra ruimte boven een rij met titel, en halfzichtbare inhoud links en rechts even breed `[B:layout]`.

**Maten en typografie.** Kop `.title2` semibold, 8 pt tot de rij, 24 pt tussen planken (`Theme.sectionSpacing`); tegelbreedte tabel 3.4; de kop staat op de paginamarge, de rij loopt door tot de rand.

**SwiftUI.** iOS 17: zoals de hero, met `LazyHStack` (veel tegels), `containerRelativeFrame` en `scrollClipDisabled()` (anders knipt de rij de zoom-overgang en schaduwen af). iOS 26: geen nieuwe API nodig.

```swift
struct Shelf<Item: Identifiable, Tile: View>: View {
    let title: String
    let showAllLabel: String          // bijvoorbeeld "Toon alle spaarpotten"
    let showAll: Destination
    let items: [Item]
    /// Breedte van een tegel uit (breedte binnen de marges, tussenruimte); voor een rij met brede kaarten: `ShelfMetrics.wideTileWidth`.
    var width: (CGFloat, CGFloat) -> CGFloat = { ShelfMetrics.tileWidth(in: $0, spacing: $1) }
    @ViewBuilder var tile: (Item) -> Tile

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                NavigationLink(value: showAll) {
                    Text("Toon alles").font(.subheadline)
                }
                .accessibilityLabel(showAllLabel)
            }
            .padding(.horizontal, ShelfMetrics.margin(sizeClass))

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: ShelfMetrics.spacing(sizeClass)) {
                    ForEach(items) { item in
                        tile(item)
                            .containerRelativeFrame(.horizontal) { length, _ in
                                width(length, ShelfMetrics.spacing(sizeClass))
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .safeAreaPadding(.horizontal, ShelfMetrics.margin(sizeClass))
            .scrollClipDisabled()
        }
    }
}
```

**Valkuilen.** (1) "Toon alles" komt per plank voor: geef elk een eigen toegankelijkheidslabel ("Toon alle spaarpotten"), de kop krijgt `.isHeader`. (2) Bij toegankelijkheidsformaten de plank als lijst onder elkaar. (3) Geen horizontale scrollview in een horizontale `[B:scroll-views]`. (4) Muisbediening op de Mac: Vorige/Volgende-knoppen in de kop. (5) Een plank met 0 of 1 item: één brede kaart met de lege staat ("Nog geen spaarpotten, Voeg toe"). (6) Elk item een stabiele `id`; `scrollTargetLayout` en `scrollPosition` leunen daarop.

**MyBuddy.** Planken op het Overzicht, in deze volgorde: **Komende dagen** (brede kaarten, par. 4.2b; Toon alles gaat naar Dag voor dag), **Spaarpotten** (naar Spaarpotten), **Beleggingen** (naar Beleggingen), **Doelen** (naar Doelen). **Hulpmiddelen** (Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck) is de vijfde plank die jij noemde; mijn aanbeveling is die in de Bibliotheek te laten: het zijn zelden gebruikte rekenpagina's (progressive disclosure `[B:layout]`), en elke plank minder is simpeler. Hoogstens 8 tegels per plank, daarna alleen Toon alles.

### 4.2b Volgende-rij (brede kaart)

**Apple doet.** In TV de rij "Up Next": 16:9-kaarten met een voortgangsbalk en eronder titel en ondertitel `[K]`; de HIG kent voor tvOS de formaten 2:3, 1:1 en 16:9 `[B:top-shelf]`. **Maten.** Brede kaart = twee tegelbreedtes plus de tussenruimte (`wideTileWidth`, tabel 3.4: 278 tot 348 pt), verhouding 16:9, dezelfde radius 16 en dezelfde onderschriften. **SwiftUI.** Dezelfde `Shelf`, met `width: ShelfMetrics.wideTileWidth` en `ArtworkTile(aspect: 16/9)`. **Valkuilen.** Datum en bedrag moeten als tekst in het label staan (niet alleen in het kleurvlak); een toekomstige boeking krijgt "Gepland" als woord. **MyBuddy.** De komende 14 dagen: pictogram van de boeking, naam, "ma 27 okt, min € 850,00" (teken en woord, niet alleen kleur `[B:color]`).

### 4.3 Artwork-tegel

**Apple doet.** Een vierkante hoes met afgeronde hoeken en daaronder titel en ondertitel; artiesten als cirkel `[K]`. De HIG: gelijke afmetingen binnen een rij `[B:lockups]` (tvOS, maar de regel is algemeen).

**Maten en typografie.** Vierkant, radius 16, pictogram `.title2` semibold linksboven (12 pt rand, wit, hiërarchisch), voortgang onderin (12 pt rand), eronder titel `.subheadline` semibold (hoogstens twee regels) en waarde `.subheadline` met `monospacedDigit` in `Theme.textSecondary`. Kleuren: tabel 3.3. Geen glas op de tegel (inhoudslaag) `[B:materials]`.

**SwiftUI.** Een `RoundedRectangle` met `LinearGradient`, overlays, `ProgressView(value:)`; `TilePressStyle` voor drukstatus (`.buttonStyle(.plain)` heeft er geen). iOS 26: voor een chip binnen de tegel `ConcentricRectangle` (par. 4.15).

```swift
struct ArtworkTile: View {
    let title: String
    let value: String
    let symbol: String
    let palette: TilePalette
    var progress: Double?
    /// 1 voor een vierkante tegel; 16/9 voor een brede kaart.
    var aspect: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [palette.top, palette.bottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .overlay(alignment: .bottom) {
                    if let progress {
                        ProgressView(value: progress)
                            .tint(.white)
                            .padding(12)
                    }
                }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Drukstatus voor een tegel die een link is (`.buttonStyle(.plain)` heeft er geen).
struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
```

**Valkuilen.** (1) Wit op het verloop: alle zeven paletten halen 4,5:1 (tabel 3.3). (2) Het label: `accessibilityElement(children: .combine)` plus waar nodig een eigen `accessibilityLabel("Vakantie, spaarpot")` en `accessibilityValue("1.250 euro, 40 procent van het doel")`; de tegel mag nooit alleen uit kleur en symbool bestaan. (3) Bij "Verhoog contrast" een dunne rand. (4) Vaste vierkanten en Dynamic Type: bij toegankelijkheidsformaten schakelt de plank naar rijen. (5) Op de Mac een hover-markering met `onHover` (`hoverEffect` bestaat daar niet).

**MyBuddy.** Spaarpot: pictogram van de pot, naam, saldo, voortgang naar het doel. Belegging: pictogram per soort, naam, waarde, onderschrift "+ 4,2 %" met teken. Doel: pictogram, naam, "€ 800 van € 5.000", voortgang. Hulpmiddel (alleen in de Bibliotheek of de optionele plank): pictogram en naam, geen waarde.

### 4.4 Poster-kaart

**Apple doet.** TV-posters in verhouding 2:3 (voor tvOS 404 bij 608 pt in Top Shelf `[B:top-shelf]`); personen als ronde "monogrammen" `[B:lockups]` (tvOS; niet voor iOS ondersteund). **MyBuddy.** Bewust niet gebruiken: twee vormen (vierkante tegel en brede kaart) zijn genoeg en simpeler. Als een belegging later een mini-grafiek nodig heeft: `ArtworkTile(aspect: 4/5)`; de tegel ondersteunt een andere `aspect` al. **Valkuil.** Elke extra vorm in dezelfde plank maakt de rij rommelig: houd de vorm per plank gelijk `[B:lockups]`.

### 4.5 Lijstrij met artwork

**Apple doet.** Tracklijsten en zoekresultaten: een kleine hoes links, titel en ondertitel, rechts een menuknop `[K]`. **Maten.** Miniatuur 44 pt (gelijk aan het minimale raakdoel) met radius 8, rijhoogte minimaal 44; op iOS 26 hebben lijstrijen standaard meer hoogte en marge `[B:adopting-liquid-glass]`. **SwiftUI.** `List` met `NavigationLink(value:)`; de rij is een `HStack` met miniatuur (hetzelfde verloop als de tegel, kleiner) en een `VStack`; `swipeActions` die de bovenste items van het contextmenu spiegelen `[B:adopting-liquid-glass]`; sectiekoppen met normale hoofdletters, niet in kapitalen `[B:adopting-liquid-glass]`. **Valkuilen.** Eén tikdoel per rij (meerdere knoppen in een rij vragen `.buttonStyle(.borderless)`), bedragen met `monospacedDigit`, bij toegankelijkheidsformaten label en bedrag onder elkaar. **MyBuddy.** Rijen op de pagina's Spaarpotten, Beleggingen, Doelen en Dag voor dag; de miniatuur is het verloop met pictogram.

### 4.6 Albumpagina-kop

**Apple doet.** Muziek: een grote hoes gecentreerd, daaronder titel, artiest en genre, twee afgeronde knoppen (Afspelen, Willekeurig), een omschrijving, dan de tracklijst; het kleurverloop van de pagina komt uit de hoes `[K]`. TV: key art over de volle breedte met titel, hoofdknop en een plusknop, daaronder planken `[K]`. Apple's voorbeeld: de afbeelding loopt tot de randen en onder de zijbalk (`backgroundExtensionEffect`), titel en knop staan als overlay erbovenop, buiten het effect `[D:landmarks-applying-a-background-extension-effect]`.

**Maten en typografie.** Kopartwork 200 tot 220 pt, radius 24, titel `.title2.bold()`, ondertitel `.subheadline`, kerngetal `.largeTitle.bold()`, twee capsule-knoppen op dezelfde breedte met `.controlSize(.large)`: een `.borderedProminent` (de ene hoofdactie, `[B:buttons]`: een of twee prominente knoppen per scherm) en een `.bordered`. Op iPad en Mac: artwork links (200 pt) en tekst rechts (`ViewThatFits`, minimale breedte 560 pt).

**SwiftUI.** Kop als eerste rij van een gegroepeerde `List` met `listRowBackground(Color.clear)`; daaronder gewone secties met swipe-acties (zoals besloten in `plan.md` K6). iOS 26: knoppen blijven `.borderedProminent` (geen glas in de inhoud `[B:materials]`); `ToolbarSpacer` voor groepen in de werkbalk.

```swift
/// De kop van een spaarpot-, beleggings- of doelpagina: groot "artwork", titel, ondertitel, kerngetal en twee capsule-knoppen.
struct DetailHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let value: String
    let symbol: String
    let palette: TilePalette
    @ViewBuilder var actions: Actions

    var body: some View {
        // Breed (iPad, Mac): artwork links, tekst rechts. Smal (iPhone): alles gecentreerd onder elkaar.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 20) {
                artwork.frame(width: 200)
                VStack(alignment: .leading, spacing: 8) { texts; actions }
            }
            .frame(minWidth: 560)

            VStack(spacing: 16) {
                artwork.frame(maxWidth: 220)
                VStack(spacing: 6) { texts }.multilineTextAlignment(.center)
                actions
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: [palette.top, palette.bottom],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: symbol)
                    .font(.largeTitle.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var texts: some View {
        Text(title).font(.title2.bold())
        Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary)
        Text(value).font(.largeTitle.bold()).monospacedDigit()
    }
}

struct PotHeaderActions: View {
    var body: some View {
        HStack(spacing: 12) {
            Button { } label: { Label("Storten", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
            Button { } label: { Label("Opnemen", systemImage: "minus").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}
```

```swift
/// Een spaarpotpagina: de kop als eerste rij van een gegroepeerde lijst, daaronder gewone secties met swipe-acties.
struct PotPage: View {
    let palette: TilePalette

    var body: some View {
        List {
            Section {
                DetailHeader(title: "Vakantie", subtitle: "Spaarpot, doel € 5.000", value: "€ 1.250,00",
                             symbol: "sun.max", palette: palette) {
                    PotHeaderActions()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Komende boekingen") {
                Text("Geen boekingen")
            }
        }
        .scrollContentBackground(.hidden)
        .ambientBackdrop(palette)
        .navigationTitle("Vakantie")
        .toolbarTitleDisplayMode(.inline)
    }
}
```

**Valkuilen.** (1) Het artwork is decoratie: `accessibilityHidden(true)`, de titel draagt de betekenis. (2) Het kerngetal en de titel zijn koppen voor VoiceOver. (3) Eén prominente knop per scherm; "Verwijderen" staat onderaan in een eigen sectie, niet in de kop. (4) Het kopartwork schaalt niet mee met Dynamic Type; de tekst wel (let op `minimumScaleFactor` alleen op het kerngetal).

**MyBuddy.** Spaarpot: tegel in het palet van Sparen, titel, "Spaarpot, doel € 5.000", saldo, knoppen Storten (prominent) en Opnemen. Belegging: "Belegging, [soort]", waarde, knoppen Waarde bijwerken en Koers vernieuwen. Doel: "Doel, [datum]", bedrag van doel, knoppen Bijdragen en Versnellers. Daaronder de bestaande secties (Komende boekingen, Geschiedenis, Inleg en rente) als lijstsecties.

### 4.7 Bibliotheek-lijst

**Apple doet.** Muziek: Bibliotheek is een lijst met categorierijen (Afspeellijsten, Artiesten, Albums, Nummers, ...) met een pictogram en een pijltje, daaronder een raster "Recent toegevoegd"; bewerken bepaalt welke rijen zichtbaar zijn `[K]`. Op iPad en Mac staan dezelfde rijen in de zijbalk `[K]`. TV op de iPhone heeft de tabs Home, Apple TV, Store, Library en Search; de Library-tab heeft rijen als Recent Purchases, Movies, Rentals, Downloaded en Genres `[S]`. HIG: een tabbalk heeft weinig items, een zijbalk of tabbalk die in een zijbalk verandert past bij een complexere structuur `[B:tab-bars]`; op iPad mag de gebruiker de tabbalk aanpassen, met een standaard van hoogstens vijf (Muziek: een favoriete afspeellijst) `[B:tab-bars]`.

**Maten.** Gegroepeerde lijst, rij minimaal 44 pt, pictogram in `Theme.accent` (een kleur, niet per domein: rustiger en simpeler), sectiekoppen in normale hoofdletters, op iPad en Mac begrensd op `Theme.readableWidth` (720 pt).

**SwiftUI.** `List` met `Section` en `NavigationLink(value:)` met `Label`; `.listStyle(.insetGrouped)` bestaat alleen op iOS en dus achter `#if os(iOS)`. iOS 26: grotere rijen en grotere hoeken vanzelf. Optioneel voor iPad en Mac: `TabSection("Bibliotheek")` in de `TabView` (iOS 18, macOS 15) zodat de rijen rechtstreeks in de zijbalk staan; het gedrag daarvan op een iPhone is niet geverifieerd.

```swift
struct LibraryPage: View {
    var body: some View {
        List {
            Section("Maand") {
                row("Inkomen", "eurosign.circle", .income)
                row("Uitgaven", "creditcard", .expenses)
            }
            Section("Sparen en beleggen") {
                row("Spaarpotten", "tray.full", .pots)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background { Theme.canvas.ignoresSafeArea() }
        .navigationTitle("Bibliotheek")
        #if os(iOS)
        .toolbarTitleDisplayMode(.large)
        #endif
    }

    private func row(_ title: String, _ symbol: String, _ destination: Destination) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: symbol)
        }
    }
}
```

**Valkuilen.** Rijen niet als kaarten tekenen; geen eigen pijltjes (`NavigationLink` doet dat); een lege groep verbergen in plaats van dimmen; sectiekoppen niet in hoofdletters.

**MyBuddy.** 12 rijen in drie groepen. **Maand**: Inkomen (`eurosign.circle`), Uitgaven (`creditcard`), Verdelen (`square.split.2x2`), Bankrekening (`building.columns`), Dag voor dag (`calendar`). **Sparen en beleggen**: Spaarpotten (`tray.full`), Beleggingen (`chart.line.uptrend.xyaxis`), Doelen (`flag.checkered`). **Plannen**: Noodbuffer (`shield.lefthalf.filled`), Versnellers (`bolt`), Toekomstschatting (`calendar.badge.clock`), Aankoopcheck (`cart`). Een samenvatting rechts in de rij (bijvoorbeeld "€ 3.200") alleen als de gebruiker daar iets aan heeft; zonder is het rustiger.

### 4.8 Zoektab met bladercategorieën

**Apple doet.** De HIG: "Apple TV uses this search tab style to present its various genres and categories, helping ground people in what's available before they search" (standaardstijl van de zoektab: een landingspagina met het zoekveld bovenaan) `[B:search-fields]`; in Muziek is de hoofdzoekopdracht een tab en filtert een inlineveld in de bibliotheek `[B:search-fields]`, `[B:searching]`; Muziek en TV als voorbeeld van een eigen zoekgebied "to highlight suggested content, categories, and recent searches" `[B:search-fields]`. Apple: zoeken staat onderaan op de iPhone `[S]`. Bladercategorieën als gekleurde tegels in twee kolommen: `[K]`.

**Maten.** Tegel minimaal 96 pt hoog, radius 16, titel linksonder `.headline` wit, decoratief pictogram rechtsboven; raster `GridItem(.adaptive(minimum: 150), spacing: 12)` (twee kolommen op een iPhone, meer op breder).

**SwiftUI.** iOS 18: `Tab(role: .search)` en `.searchable(text:)` op de `TabView`: "Searchable tab views will prefer to have the first tab with this role implement search. If no tabs are specified as the search tab, the tab view will apply search to all tabs" `[A:tabrole/search]`. iOS 26: het systeem zet de zoektab los aan het eind van de balk, hij verandert in het zoekveld `[W:2025-256]`; op iPad en Mac staat het veld gecentreerd boven de suggesties `[W:2025-323]`. Verder `searchSuggestions`, `searchScopes` (iOS 16.4), `searchFocused` (iOS 18), en `ContentUnavailableView.search(text:)` voor "geen resultaten". Hoe iOS 18 het zoekveld in een zoektab plaatst verschilt van iOS 26: op een toestel testen.

```swift
struct RootTabs: View {
    @State private var tab: AppTab = .overview
    @State private var query = ""

    var body: some View {
        TabView(selection: $tab) {
            Tab("Overzicht", systemImage: "house", value: AppTab.overview) {
                NavigationStack { Text("Overzicht") }
            }
            Tab("Bibliotheek", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack { LibraryPage() }
            }
            Tab("Zoeken", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack { SearchLanding(query: query) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .searchable(text: $query, prompt: "Zoek in MyBuddy")
        .minimizingTabBar()
    }
}

extension View {
    /// iOS/iPadOS 26: de tabbalk krimpt bij omlaag scrollen. `onScrollDown` bestaat niet op macOS, dus `#if os(iOS)`.
    @ViewBuilder func minimizingTabBar() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct SearchLanding: View {
    let query: String
    @Environment(\.isSearching) private var isSearching

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            if isSearching || !query.isEmpty {
                Text("Resultaten voor \(query)")
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(["Inkomen", "Uitgaven", "Sparen", "Beleggen"], id: \.self) { name in
                        NavigationLink(value: Destination.income) {
                            CategoryTile(title: name, symbol: "tray.full")
                        }
                        .buttonStyle(TilePressStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationTitle("Zoeken")
    }
}

struct CategoryTile: View {
    let title: String
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(minHeight: 96)
            .overlay(alignment: .bottomLeading) {
                Text(title).font(.headline).foregroundStyle(.white).padding(12)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.white.opacity(0.85)).padding(12)
            }
            .accessibilityElement(children: .combine)
    }
}
```

**Valkuilen.** (1) Zoek tijdens het typen `[B:search-fields]`; zonder tekst de categorieën, met tekst de resultaten, gegroepeerd per soort. (2) De tegel is kleur plus tekst plus pictogram, nooit alleen kleur. (3) Geen zoekgeschiedenis tonen of opslaan: de HIG waarschuwt voor privacy, en dit zijn financiële gegevens `[B:searching]`. (4) De zoektab op macOS in de zijbalk: gedrag niet geverifieerd. (5) Cmd+F moet het veld openen (bestaand `router.requestSearch`).

**MyBuddy.** Acht categorietegels: Inkomen, Uitgaven, Verdelen, Bankrekening, Spaarpotten, Beleggingen, Doelen, Hulpmiddelen. Resultaten komen uit het bestaande `SearchIndex` (Foundation-only, al getest), gegroepeerd: Pagina's, Spaarpotten, Beleggingen, Doelen, Boekingen.

### 4.9 Profielknop

**Apple doet.** Op de tabroots van Muziek en TV staat rechtsboven een ronde knop met je profielfoto die een account- of profielblad opent `[K]`. HIG: het symbool voor accounts is `person.crop.circle` en elk pictogram krijgt een toegankelijkheidslabel `[B:icons]`, `[B:adopting-liquid-glass]`; werkbalkitems krijgen op iOS 26 vanzelf glas; een item dat geen glasbolletje wil gebruikt `sharedBackgroundVisibility(.hidden)` (iOS 26) `[A]`.

**Maten.** Standaard werkbalkgrootte, raakdoel 44 pt; bij een aandachtspunt (synchronisatieconflict) een stip en een tekstlabel ("Account, aandacht nodig"), want een badge is voor kritieke informatie `[B:tab-bars]`.

**SwiftUI.** `ToolbarItem` met `.topBarTrailing` (iOS, iPadOS) en `.primaryAction` (macOS), met een `NavigationLink(value:)` naar de Account-bestemming (in het project `Destination.settings(.account)`; de schets gebruikt een vereenvoudigde `Destination`); zonder `if` om het item, hooguit om de hele `ToolbarItem` `[B:adopting-liquid-glass]`.

```swift
// MARK: Profielknop (rechtsboven)

extension View {
    func profileButton() -> some View {
        toolbar {
            ToolbarItem(placement: Self.profilePlacement) {
                NavigationLink(value: Destination.settings) {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
        }
    }

    private static var profilePlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .primaryAction
        #else
        return .topBarTrailing
        #endif
    }
}
```

**Valkuilen.** `.topBarTrailing` bestaat niet op macOS (daar is Instellingen ook het `Settings`-venster met Cmd+komma); een duwpagina of een blad is een ontwerpbesluit (par. 2, punt d); het label niet weglaten (alleen symbool).

**MyBuddy.** Op Overzicht en Bibliotheek rechtsboven; opent de Account-pagina met daarin Instellingen, Account, Synchronisatie. Deze knop vervangt de tab Instellingen.

### 4.10 Minispeler-accessoire

**Apple doet.** In Muziek zweeft de minispeler boven de tabbalk; bij omlaag scrollen krimpt de tabbalk en schuift de minispeler eromheen op dezelfde rij; tikken op een tab of omhoog scrollen herstelt dat `[B:tab-bars]`; bij samengevouwen balk staan tabbalk, minispeler en zoeken op een rij `[S]`.

**SwiftUI.** `tabViewBottomAccessory` (iOS 26.0; `isEnabled:` iOS 26.1) en `tabBarMinimizeBehavior(.onScrollDown)`, alleen iOS en iPadOS (par. 3.5); de inhoud leest `tabViewBottomAccessoryPlacement` (`.inline` of `.expanded`). In `tabViewBottomAccessory` moet de inhoud compact zijn: een regel.

**Valkuilen.** Alleen iPhone en iPad met iOS 26 en hoger; op iOS 18 tot 25 en op de Mac is er niets, dus twee verschillende schermen. De tabbalk is voor navigatie, niet voor acties `[B:tab-bars]`.

**MyBuddy.** Een "kerngetal-balk" ("Nog te verdelen € 1.250", tik opent Verdelen) kan, maar ik raad het **niet** aan voor de eerste ronde: het verdubbelt de hero, voegt vaste chroom toe op elk scherm en dat is het tegendeel van simpeler. Wel nuttig, en dan alleen met `isEnabled`: een tijdelijke status zoals "Koersen ophalen" of "Niet gesynchroniseerd". Minimaliseren van de tabbalk bij scrollen (`tabBarMinimizeBehavior`) blijft wel zinvol op iOS 26; de bestaande `RootView` heeft dat al, maar met de macOS-kanttekening van par. 3.6 (in `RootTabs` hierboven is dat `minimizingTabBar()`).

```swift
// MARK: Minispeler-accessoire (alleen iPhone/iPad, iOS 26)

#if os(iOS)
@available(iOS 26.0, *)
struct KeyFigureBar: View {
    let figure: KeyFigure
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if placement == .inline {
            Text(figure.amount).font(.subheadline.weight(.semibold)).monospacedDigit()
        } else {
            HStack {
                Text(figure.label).font(.subheadline)
                Spacer()
                Text(figure.amount).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .padding(.horizontal, 16)
        }
    }
}
#endif

extension View {
    /// `tabViewBottomAccessory` bestaat alleen op iOS en iPadOS (niet op macOS): `#if os(iOS)` plus `#available`.
    /// De variant met `isEnabled:` is iOS 26.1; op 26.0 is er alleen de variant zonder.
    @ViewBuilder func keyFigureAccessory(_ figure: KeyFigure?) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            self.tabViewBottomAccessory(isEnabled: figure != nil) {
                if let figure { KeyFigureBar(figure: figure) }
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
```

### 4.11 Achtergrond met kleurverloop

**Apple doet.** Albumpagina's en het volledige Nu-speelt-scherm hebben een achtergrond die uit de hoes is afgeleid en naar de systeemachtergrond vervaagt; in iOS 26 beweegt hij op het Nu-speelt-scherm `[K]`. HIG: kleur van artwork beïnvloedt nabije kleuren (continuïteit) `[B:color]`; bij een kleurrijke achtergrond een monochrome tabbalk (of een accent met voldoende verschil) `[B:tab-bars]`, `[B:color]`; achtergrondinhoud loopt onder balken en zijbalken `[B:layout]`; geen eigen achtergrond onder bedieningselementen, het scroll-edge-effect regelt de leesbaarheid `[B:layout]`.

**Maten.** Het verloop is ongeveer 380 pt hoog, vloeit naar `Theme.canvas`, en de tint is hoogstens 50% (donker) of 18% (licht), tabel 3.3. Eén mesh per scherm.

**SwiftUI.** iOS 18: `MeshGradient` (3 bij 3) of `LinearGradient`, kleuren met `Color.mix(with:by:)`; als navigatieachtergrond met `containerBackground(for: .navigation)` (iOS 18; beweegt mee met de zoom-overgang), op macOS een gewone `background`. Niet animeren (Verlaag beweging, batterij). iOS 26: `backgroundExtensionEffect()` alleen als er een echte afbeelding is.

```swift
/// Het kleurverloop achter een pagina: een tint die naar het canvas vervaagt (de "ambient backdrop" van Muziek en TV).
struct AmbientBackdrop: View {
    let palette: TilePalette

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Donker: de donkere kleurstop op hoogstens 50%; licht: de lichte stop op hoogstens 18% (gemeten, zie par. 3.3).
    private var strength: Double {
        if reduceTransparency || contrast == .increased { return 0 }
        return scheme == .dark ? 0.5 : 0.18
    }

    private var tint: Color { scheme == .dark ? palette.bottom : palette.top }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.canvas
            MeshGradient(
                width: 3, height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    .init(0, 0.5), .init(0.6, 0.45), .init(1, 0.5),
                    .init(0, 1), .init(0.5, 1), .init(1, 1)
                ],
                colors: [
                    mixed(1), mixed(0.85), mixed(1),
                    mixed(0.55), mixed(0.7), mixed(0.45),
                    mixed(0), mixed(0), mixed(0)
                ]
            )
            .frame(height: 380)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    /// De tint over het canvas, `amount` van de volle sterkte (0 = alleen canvas).
    private func mixed(_ amount: Double) -> Color {
        Theme.canvas.mix(with: tint, by: strength * amount)
    }
}

extension View {
    /// iOS/iPadOS: als achtergrond van de navigatiecontainer, zodat hij met de zoom-overgang meebeweegt
    /// (`ContainerBackgroundPlacement.navigation` bestaat niet op macOS). Mac: gewone achtergrond.
    @ViewBuilder func ambientBackdrop(_ palette: TilePalette) -> some View {
        #if os(macOS)
        background { AmbientBackdrop(palette: palette) }
        #else
        containerBackground(for: .navigation) { AmbientBackdrop(palette: palette) }
        #endif
    }
}
```

**Valkuilen.** (1) Contrast: de percentages hierboven komen uit meting, niet uit smaak. (2) "Verhoog contrast" en "Verlaag transparantie": geen tint. (3) Alleen detailpagina's: op een tabroot botst de tint met het olijf-accent van de tabbalk. (4) Een lijst met `scrollContentBackground(.hidden)` toont de achtergrond erachter; gegroepeerde rijen houden hun eigen kleur. (5) `MeshGradient` is duurder dan een lineair verloop; als het zwaar wordt, terugvallen op `LinearGradient`.

**MyBuddy.** Het palet van het domein: Spaarpot en Spaarpotten in saliegroenblauw, Belegging in leiblauw, Doel in mosterd, Verdelen en Inkomen in terracotta. Overzicht, Bibliotheek en Zoeken blijven vlak (`Theme.canvas`).

### 4.12 Grote titels

**Apple doet.** Tabroots (Home, Bibliotheek) hebben een grote titel die bij scrollen in de balk komt; detailpagina's en albums hebben een korte titel in de balk `[K]`. HIG: "Use a large title to help people stay oriented ... transitions to a standard title as people begin scrolling" `[B:toolbars]`.

**SwiftUI.** `navigationTitle` plus `toolbarTitleDisplayMode(.large)` op tabroots en `.inline` op detailpagina's. `.large` bestaat niet op macOS en de modifier doet daar niets (par. 3.6): `#if os(iOS)`. Voor context in de balk: `navigationSubtitle("oktober 2026")` (macOS 13; iOS 26).

```swift
// Tabroot (zie LibraryPage hierboven): grote titel alleen op iOS
.navigationTitle("Bibliotheek")
#if os(iOS)
.toolbarTitleDisplayMode(.large)
#endif
```

**Valkuilen.** Titels kort (NAV-3: geen appnaam, liefst onder 15 tekens); op macOS toont de venstertitel de sectie; bij toegankelijkheidsformaten kan een grote titel twee regels worden, dat is goed.

**MyBuddy.** "Overzicht", "Bibliotheek", "Zoeken" groot; alle andere pagina's `.inline`. De huidige `PageScaffold` en `ListScaffold` kiezen dat al via `large`, alleen zonder macOS-voorbehoud.

### 4.13 Contextmenu

**Apple doet.** Lang indrukken op een hoes toont de hoes opgetild met daarnaast een menu (Voeg toe aan bibliotheek, Speel hierna, Deel, ...) `[K]`. HIG: weinig items, hoogstens ongeveer drie groepen, het belangrijkste eerst, destructief laatst en als destructief gemarkeerd, onbeschikbare items verbergen (niet dimmen), dezelfde acties ook in de hoofdinterface, een grafische preview waarvan het clippad bij de vorm past `[B:context-menus]`; bovenste acties gelijk aan de swipe-acties `[B:adopting-liquid-glass]`.

**SwiftUI.** `contextMenu(menuItems:preview:)` (iOS 16, macOS 13; de preview alleen op iOS en iPadOS) en `contentShape(.contextMenuPreview, RoundedRectangle(...))` zodat de hoeken kloppen.

```swift
struct PotTileLink: View {
    let pot: UUID
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        NavigationLink(value: Destination.pot(pot)) {
            ArtworkTile(title: "Vakantie", value: "€ 1.250,00", symbol: "sun.max",
                        palette: TilePalette(top: .teal, bottom: .green), progress: 0.4)
                .zoomSource(Destination.pot(pot), in: zoom)
        }
        .buttonStyle(TilePressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button("Storten", systemImage: "plus.circle") { }
            Button("Opnemen", systemImage: "minus.circle") { }
            Divider()
            Button("Bewerken", systemImage: "pencil") { }
            Button("Verwijderen", systemImage: "trash", role: .destructive) { }
        } preview: {
            ArtworkTile(title: "Vakantie", value: "€ 1.250,00", symbol: "sun.max",
                        palette: TilePalette(top: .teal, bottom: .green), progress: 0.4)
                .frame(width: 200)
                .padding()
        }
    }
}
```

**Valkuilen.** Een contextmenu is verborgen: elke actie staat ook in het "…"-menu van de detailpagina en als swipe-actie in de lijst (`ACC-7`); maximaal een submenu-niveau; geen sneltoetsen in het contextmenu zelf; en een contextmenu óf een bewerkmenu per item, niet beide `[B:context-menus]`.

**MyBuddy.** Op elke tegel van pot, belegging en doel: Storten, Opnemen | Bewerken | Verwijderen (rood, laatst). Geen menu op de hero-kaarten.

### 4.14 Overgangen (zoom en matchedTransitionSource)

**Apple doet.** Tikken op een hoes laat de hoes uitgroeien tot de pagina (zoom) `[K]`; Apple documenteert `matchedTransitionSource` plus `navigationTransition(.zoom)` voor push, sheet en volledig scherm `[A:navigationtransition]`, `[W:2024-10144]`, en op iOS 26 voor een blad dat uit zijn knop komt `[W:2025-323]`.

**SwiftUI.** iOS 18: `matchedTransitionSource(id:in:)` op de bron (met `configuration:` voor straal en schaduw van de bron), `navigationTransition(.zoom(sourceID:in:))` op de wortel van de bestemming, beide met dezelfde `@Namespace`. `.zoom` bestaat niet op macOS: `#if !os(macOS)`. De namespace staat in `TabStack` en gaat via een omgevingswaarde naar de tegels.

```swift
// MARK: Zoom-overgang (iOS/iPadOS 18+; op macOS bestaat `.zoom` niet)

private struct ZoomNamespaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? { nil }
}

extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder func zoomSource(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        #if os(macOS)
        self
        #else
        if let namespace { self.matchedTransitionSource(id: id, in: namespace) } else { self }
        #endif
    }

    @ViewBuilder func zoomDestination(_ id: some Hashable, in namespace: Namespace.ID?) -> some View {
        #if os(macOS)
        self
        #else
        if let namespace { self.navigationTransition(.zoom(sourceID: id, in: namespace)) } else { self }
        #endif
    }
}

struct ZoomingStack<Root: View, Detail: View>: View {
    @Namespace private var zoom
    @State private var path: [Destination] = []
    @ViewBuilder var root: Root
    @ViewBuilder var detail: (Destination) -> Detail

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Destination.self) { destination in
                    detail(destination).zoomDestination(destination, in: zoom)
                }
        }
        .environment(\.zoomNamespace, zoom)
    }
}
```

(`PotTileLink` in par. 4.13 gebruikt `zoomSource`.)

**Valkuilen.** (1) De `id` moet uniek zijn binnen de namespace; dezelfde bestemming vanuit twee tegels op één scherm geeft een botsing: geef maar een bron de overgang. (2) De bron moet in beeld zijn; in een `LazyHStack` die buiten beeld is gescrold is er geen bron en valt de overgang terug. (3) Bij Verlaag beweging gedraagt de systeemovergang zich naar verwachting als een fade; niet zelf getest `[K]`. (4) `matchedGeometryEffect` is niet de goede weg voor een `NavigationStack`. (5) Gebruik geen `.crossFade` (iOS 27).

**MyBuddy.** Zoom vanaf elke tegel en hero-kaart naar de bestemming; Bibliotheek-rijen gebruiken de gewone duw-overgang (zoals Muziek). Op de Mac geen overgang.

### 4.15 De iOS 26-laag

Alleen voor bediening en navigatie, nooit voor tegels of kaarten (geen glas in de inhoudslaag `[B:materials]`). In het blok hieronder: `safeAreaBar` voor een vaste actiebalk onderaan met scroll-edge-uitwerking (daaronder `safeAreaInset`), `ConcentricRectangle` voor binnenvormen (daaronder een vaste straal), `backgroundExtensionEffect()` voor een afbeelding onder de zijbalk, `scrollEdgeEffectStyle` (zacht op iOS en iPadOS, hard vooral op macOS) alleen bij een eigen balk boven een scrollview, en `glassEffect` voor een zwevende bediening zoals "Naar vandaag" op Dag voor dag (daaronder `.regularMaterial`). Standaardcomponenten (tabbalk, werkbalk, menu, blad, zoekveld) krijgen glas vanzelf; het scroll-edge-effect is daar automatisch `[B:scroll-views]`. Voor een groep losse glaselementen naast elkaar hoort een `GlassEffectContainer` (glas kan geen ander glas bemonsteren `[W:2025-323]`).

```swift
extension View {
    /// Concentrische hoeken (iOS/macOS 26); daaronder dezelfde straal als vaste waarde.
    @ViewBuilder func concentricFill<S: ShapeStyle>(_ style: S, fallbackRadius: CGFloat) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            background(style, in: ConcentricRectangle(corners: .concentric(minimum: .fixed(fallbackRadius)), isUniform: true))
        } else {
            background(style, in: RoundedRectangle(cornerRadius: fallbackRadius, style: .continuous))
        }
    }

    /// Een afbeelding mag onder zijbalk en inspector doorlopen (iPad, Mac). Alleen voor een echte afbeelding, niet voor een vlak.
    @ViewBuilder func extendsUnderSidebar() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
    }

    /// Een vaste actiebalk onderaan die de scroll-edge-uitwerking meekrijgt (iOS/macOS 26); daaronder `safeAreaInset`.
    @ViewBuilder func bottomActionBar<Bar: View>(_ bar: Bar) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            safeAreaBar(edge: .bottom) { bar }
        } else {
            safeAreaInset(edge: .bottom) { bar }
        }
    }

    /// Alleen bij een eigen balk boven een scrollview; de systeembalken regelen dit zelf. De HIG: zacht op iOS en iPadOS,
    /// hard vooral op macOS.
    @ViewBuilder func scrollEdgeUnderCustomBar(_ edges: Edge.Set = .top) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if os(macOS)
            scrollEdgeEffectStyle(.hard, for: edges)
            #else
            scrollEdgeEffectStyle(.soft, for: edges)
            #endif
        } else {
            self
        }
    }

    /// Een zwevende bediening boven scrollende inhoud (bijvoorbeeld "Naar vandaag" in Dag voor dag): hier hoort glas wel,
    /// in tegenstelling tot tegels en kaarten. Daaronder een standaardmateriaal.
    @ViewBuilder func floatingGlass() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}
```

## 5. Wat gecontroleerd is, en wat niet

- **Syntaxis (`[T]`)**: alle 14 schetsbestanden en het bestand met hulptypen (`swift/`, 15 in totaal) zijn met tree-sitter-swift geparst: 0 foutknopen; een bewust kapot bestand geeft 1 foutknoop. Dat is alleen een parser: geen typecontrole.
- **API's (`[A]`)**: elk symbool dat in de schetsen staat is opgezocht in Apple's documentatie-JSON; een script (`d2tools/symcheck.py`) vindt geen onbekend API-symbool buiten mijn eigen typen. Handtekeningen zijn met de hand naast de declaraties gelegd (bijvoorbeeld `concentric(minimum: Edge.Corner.Style?)`, `containerRelativeFrame(_:alignment:_:)`, `tabViewBottomAccessory(isEnabled:content:)`).
- **Maten en contrast (`[P]`)**: tabel 3.3 en 3.4 met `d2tools/contrast2.py`, `d2tools/oklab.py` en `d2tools/metrics.py`; de contrastwaarden zijn berekend, niet met een toestel of Accessibility Inspector gemeten.
- **Niet gedaan**: compileren (geen `swiftc` en geen SwiftUI op Linux; het enige echte compileeroordeel is de CI), draaien op een toestel of simulator, VoiceOver, de echte Muziek- en TV-schermen meten.

## 6. Onzekerheden

1. Alles over het uiterlijk van Muziek en TV (hero, planken, albumkop, profielknop, categorietegels) is `[K]`; er was geen gelezen bron.
2. `containerRelativeFrame` binnen `safeAreaPadding`: of de marge van de lengte wordt afgetrokken volgt uit Apple's voorbeeld (`.safeAreaPadding(.horizontal, 20.0)` met `count: 4, span: 3`), maar de uitlijning van het snappen met `viewAligned` is niet op een toestel gezien.
3. De iOS 18-plaatsing van het zoekveld bij `Tab(role: .search)` en `.searchable` op de `TabView` verschilt waarschijnlijk van iOS 26; en het gedrag van de zoektab in een macOS-zijbalk is niet geverifieerd. Of `isSearching` in `SearchLanding` goed doorkomt als `.searchable` op de `TabView` staat is evenmin op een toestel gezien.
4. De twee mogelijke macOS-compileerfouten in bestaande code (par. 3.6) volgen uit de documentatie, niet uit een build.
5. Welk systeemgedrag "Verlaag beweging" bij de zoom-overgang geeft is niet getest.
6. Apple's documentatie-JSON is van het Xcode 27-tijdperk (er staan iOS 27-symbolen in); wat ik als iOS 26 heb genoteerd, stond ook zo in die JSON.
7. Installatie-aantallen van de skills zijn niet vast te stellen.
