# HIG-notities voor MyBuddy

Peildatum: 15 oktober 2026. Opgesteld door de HIG-onderzoeker (alleen documenten; er is niets in `App/` of `CoreTests/` aangepast). Regelnummers en tellingen zijn op 15 oktober 2026 (16:55) opnieuw nagelopen tegen `HEAD` (ca0c945); het herstelwerk in `App/` loopt door, dus ze kunnen alweer verschuiven: zoek op het patroon, niet op het nummer.
Doel: de Apple Human Interface Guidelines vertaald naar korte, toetsbare regels voor deze SwiftUI-app (iPhone, iPad, Mac; iOS 18+/macOS 15+, iOS 26-API's alleen achter `#available`).

## 0. Status van de bron en leeswijzer

**De officiele HIG was wel bereikbaar via het netwerk.** Dit document is dus verifieerbaar; alleen waar `[K]` staat is het kennis of afleiding.

- De gewone pagina's (`https://developer.apple.com/design/human-interface-guidelines/<onderwerp>`) geven via WebFetch een lege JavaScript-schil (alleen de titel). Bruikbaar was de JSON-route: `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<onderwerp>.json`. Die bevat de volledige tekst. Ik heb 79 pagina's met curl (via de sessie-proxy) opgehaald en met `/tmp/hig-research/hig2txt.py` naar platte tekst omgezet (`/tmp/hig-research/hig-txt/<onderwerp>.txt`). WebFetch op de JSON werkt ook, maar de samenvattende tussenstap kapt lange pagina's af (typography: 281.026 tekens, 100.000 gelezen); daarom heb ik curl gebruikt.
- API-beschikbaarheid (minimale OS-versie) heb ik gecontroleerd in Apple's documentatie-JSON: `https://developer.apple.com/tutorials/data/documentation/swiftui/<symbool>.json` (en `.../charts/...`, `.../accessibility/...`, `.../technologyoverviews/adopting-liquid-glass.json`). Script: `/tmp/hig-research/api.py`.
- De changelogs in de pagina's lopen tot 9 september 2026 (layout), 8 juni 2026 (tab bars, sidebars, menus, scroll views) en 24 maart 2026 (sheets, plaatsing van knoppen). De tekst is dus iets nieuwer dan iOS 26.0. Waar een regel daardoor kan afwijken van iOS 26 staat dat erbij.
- Niet bestaande pagina's (404): `date-pickers`, `pull-to-refresh`, `empty-states`, `ipad-os`, `macos`, `navigation-bars`, `data-entry`. Vervangen door: `pickers` (bevat datumkiezers), `progress-indicators` (sectie "Refresh content controls"), `writing` plus Apple's `ContentUnavailableView`-documentatie (lege staten), `designing-for-ipados`, `designing-for-macos` plus `windows`, `the-menu-bar`, `keyboards`, en `toolbars` (bevat sinds juni 2025 de navigation-bar-richtlijnen, incl. grote titels).
- Volledig gelezen: layout, adopting-liquid-glass, liquid-glass, applying-liquid-glass-to-custom-views, color, materials, dark-mode, accessibility, motion, tab-bars, tab-views, sidebars, toolbars, sheets, modality, alerts, action-sheets, lists-and-tables, charting-data, charts, settings, onboarding, entering-data, text-fields, pickers, steppers, toggles, segmented-controls, buttons, menus, context-menus, popovers, disclosure-controls, labels, loading, feedback, multitasking, scroll-views, managing-accounts, search-fields, searching, writing, designing-for-ios/ipados/macos. Gedeeltelijk (alleen de relevante delen): typography (iOS/macOS-delen), sf-symbols, icons, privacy, playing-haptics, progress-indicators, sliders, gauges, the-menu-bar, keyboards, windows, pointing-devices, split-views, undo-and-redo, going-full-screen, offering-help. Opgehaald maar niet gebruikt: gestures, images, inclusion, right-to-left en nog enkele.

**Bronlabels per regel**

- `[B:onderwerp]` = gelezen in de officiele HIG-pagina `https://developer.apple.com/design/human-interface-guidelines/<onderwerp>`. Uitzonderingen: `[B:adopting-liquid-glass]` = `https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass`; `[B:swiftui-glass]` = `https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views`.
- `[A:symbool]` = gelezen in Apple's API-documentatie (vooral beschikbaarheid, of wat een API doet).
- `[K]` = kennis, afleiding of eigen meting; niet in een gelezen bron. Dat geldt ook voor alle getallen die ik zelf als drempel voorstel.
- `[P]` = gereproduceerd met een proefscript tegen `App/Core` (`/tmp/hig-probe`, uitvoerbaar met `swift build --scratch-path /tmp/sb-hig-probe` en dan `/tmp/sb-hig-probe/debug/probe`).

**Vorm van een regel:** `ID REGEL: ... / TOETS: ... [bron]`. In TOETS staat waar je op zoekt (`grep -rn "<patroon>" App/`) of wat je test.

**Aantal regels:** de opdracht vroeg 3 tot 8 regels per onderwerp. Negen onderwerpen hebben er meer (9 tot 12: GLS, CHT, ACC, TAB, SHT, SET, LST, WRT, MAC), omdat ze voor deze app zwaar wegen (glas, toegankelijkheid, navigatie, grafieken, instellingen). Ze zijn niet samengevoegd zodat de ID's stabiel blijven voor wie ernaar verwijst; de eerste regels van elk onderwerp zijn de kern.

**Waar de app niet op hoeft te letten:** watchOS, tvOS en visionOS komen in de HIG voor, maar zijn hier weggelaten.

---

## 1. De 15 belangrijkste regels voor deze app

1. **Inhoud is geen glas.** Liquid Glass is voor de bedienings- en navigatielaag (tabbalk, toolbar, sidebar, knoppen, sheets), niet voor de inhoudslaag. Nu is elk van de circa 90 `GlassBlock`-blokken een glaskaart. Inhoud krijgt een standaardmateriaal of een gegroepeerde `List`/`Form`; geen glas op glas; tinten spaarzaam. (GLS-1 t/m GLS-4)
2. **Native navigatie.** `TabView` met `Tab` en `.tabViewStyle(.sidebarAdaptable)` in plaats van de zelfgebouwde `GlassTabBar`. Tabbalk altijd zichtbaar, navigatiepad per tab bewaren (nu wist `Router.select` het pad), Nederlandse eenwoord-labels. Op de Mac een sidebar: niets onderaan het venster. (TAB-1 t/m TAB-7, LAY-8)
3. **Instellingen is een volledige pagina.** iPhone/iPad: een pagina op de navigatiestapel (of een eigen tab/sidebar-item). Mac: de `Settings`-scene met Cmd+komma. Geen sheet. Weinig instellingen, goede standaardwaarden, taakspecifieke opties in het scherm zelf. (SET-1 t/m SET-6)
4. **Account staat los van de rest.** Eigen pagina (`person.crop.circle`) met synchronisatie, wachtwoord, uitloggen en account verwijderen; de rest van de instellingen daarbuiten. Verplicht aanmelden bij het starten vermijden. (ACT-1 t/m ACT-5, ONB-5)
5. **Een sheet is voor een afgebakende taak.** Annuleer links, Klaar/Bewaar rechts, titel die de taak noemt, een sheet tegelijk, veeg-om-te-sluiten met bevestiging bij niet-opgeslagen wijzigingen. Niet voor lange of hierarchische flows. (SHT-1 t/m SHT-7)
6. **Dynamic Type.** Tekststijlen in plaats van `.font(.system(size:))` (5 plekken), layouts die stapelen bij toegankelijkheidsformaten, geen `minimumScaleFactor` op labels, minimaal 11 pt. (TYP-1 t/m TYP-5)
7. **Kleur en contrast.** Systeemkleuren, eigen kleuren als Color Set met licht/donker/hoog contrast. Tekst minimaal 4,5:1. Gemeten (`[K]`): `Theme.warning` licht haalt 2,5 tot 3,4:1, `negative` licht 3,3 tot 4,5:1, `accent` licht 3,7 tot 5,0:1. Nooit alleen kleur: teken, symbool of tekst erbij. (COL-1 t/m COL-7)
8. **Elke grafiek is toegankelijk en leesbaar zonder kleur.** Nu hebben 8 grafiekviews samen 2 samenvattende labels en 0 `AXChartDescriptor`. Elke grafiek: titel plus samenvatting, labels per punt of groep, een reeks per kleur plus vorm/lijnstijl/label. Gemeten (`[K]`): bij deuteranopie lopen `flowExpenses`/`flowSaved` en `palette[0]`/`palette[3]` bijna in elkaar over. (CHT-2, CHT-4, CHT-5, COL-7)
9. **Grafieken bewegen mee met de invoer en tonen altijd iets zinnigs.** Reeksen zijn pure functies van `store.data`, alleen eindige waarden, `domain: lo...hi` alleen met `lo < hi`, elke reeks apart (`series:`/`foregroundStyle(by:)`), 0 punten = lege staat, 1 punt = punt plus uitleg. Een gedeelde grafiekstijl. (CHT-7 t/m CHT-11)
10. **Raakdoelen en gebaren.** Minimaal 44x44 pt (`Theme.buttonHeight` is 42), drukstatus op eigen knoppen (`.buttonStyle(.plain)` heeft er geen), nooit een actie alleen via lang indrukken of swipen, maximaal een prominente knop per scherm. (ACC-2, ACC-7, BTN-1 t/m BTN-3)
11. **Beweging en haptiek.** `accessibilityReduceMotion` en `accessibilityReduceTransparency` respecteren (nu 0 treffers), geen paginabrede `.animation(value: store.data)`, haptiek via `sensoryFeedback` op discrete gebeurtenissen (nu 0 treffers). (MOT-1 t/m MOT-5, FDB-4)
12. **Lijsten en lege staten.** Gegroepeerde lijsten/formulieren, sectiekoppen niet in hoofdletters (`SectionLabel` gebruikt `uppercased()`), swipe-acties plus contextmenu die elkaar spiegelen, destructief laatst en rood, `ContentUnavailableView` met een volgende stap. (LST-1 t/m LST-8, EMP-1 t/m EMP-4)
13. **Toolbar.** Een primaire actie, trailing, prominent; symbolen zonder rand; geen eigen balkachtergronden; standaard Back/Close; grote titel alleen op de hoofdpagina van een tab. `navigationBarTitleDisplayMode` bestaat niet op macOS (`toolbarTitleDisplayMode` wel, vanaf iOS 17/macOS 14). (TLB-1 t/m TLB-7, NAV-2)
14. **Vereenvoudigen volgens de HIG.** Progressive disclosure, minder bedieningselementen per scherm, minder niveaus, een primaire route per functie, zoeken waar mensen dingen zoeken (`.searchable`). (SIM-1 t/m SIM-6, SRC-1 t/m SRC-3)
15. **Mac en iPad horen bij het platform.** Menubalk-commando's (`.commands`, nu 0), Cmd+komma, standaard sneltoetsen, `.help`-tooltips, pointer-effecten (`hoverEffect`, alleen iOS), minimumgrootte van het venster, Back/Close zonder tekst. (MAC-1 t/m MAC-8, IPD-1 t/m IPD-6)

---

## 2. Regels per onderwerp

### 2.1 Layout (LAY)

- **LAY-1** REGEL: Zet het belangrijkste bovenaan en vooraan (leesrichting boven naar onder, leading naar trailing), lijn uit, en groepeer wat bij elkaar hoort met witruimte, een vorm of een scheidingslijn. / TOETS: open elk scherm; de eerste een tot twee schermhoogtes tonen het hoofdgetal en de hoofdactie, de rest staat eronder. `[B:layout]`
- **LAY-2** REGEL: Progressive disclosure: toon eerst het wezenlijke, de rest achter een `NavigationLink`, `DisclosureGroup`, menu of "Toon meer". / TOETS: per scherm: wat is het dagelijks gebruikte deel? Alles wat dat niet is zit een niveau dieper. Als vuistregel (`[K]`) meer dan 4 gelijkwaardige blokken of meer dan 6 bedieningselementen op een scherm zonder tussenkopjes is te veel. `[B:layout, disclosure-controls, designing-for-ios]`
- **LAY-3** REGEL: Scheid bediening van inhoud: geen effen of halfdoorzichtig vlak onder bedieningselementen; laat de achtergrond doorlopen onder tabbalk, toolbar en sidebar; het scroll-edge-effect regelt de leesbaarheid. / TOETS: zoek `.background(.bar)`, `fill(.bar)`, `toolbarBackground`, `Rectangle().fill(` in bar-code (nu `RootView.swift:139,142`); `ignoresSafeArea` alleen op achtergronden. `[B:layout, adopting-liquid-glass, scroll-views]`
- **LAY-4** REGEL: Respecteer safe areas en systeemmarges; inhoud binnen de safe area, alleen achtergronden erdoorheen. / TOETS: `ignoresSafeArea` alleen op `MeshBackground`; geen vaste `.padding(.bottom, <balkhoogte>)`; `.padding(.horizontal, 16)` (`Components.swift:16`) vervangen door `.scenePadding()` of `contentMargins`. `[B:layout]`
- **LAY-5** REGEL: Kies de layout op basis van size classes en beschikbare ruimte, niet op apparaattype of oriëntatie; denk aan alle combinaties van compact/regular. / TOETS: zoek `UIDevice`, `userInterfaceIdiom`, `UIScreen`, `GeometryReader` voor breedtebeslissingen; gebruik `horizontalSizeClass` (nu 0 treffers), `ViewThatFits`, `LazyVGrid(.adaptive)` (aanwezig in `Theme.blockColumns`). `[B:layout]`
- **LAY-6** REGEL: Zelfde functionaliteit bij elke grootte; alleen de hoeveelheid die tegelijk zichtbaar is mag veranderen (tabbalk wordt sidebar). / TOETS: elke `Destination` is bereikbaar op iPhone, iPad en Mac; geen `if sizeClass == .compact { feature weglaten }`. `[B:layout]`
- **LAY-7** REGEL: Lange tekst en formulierrijen krijgen een begrensde, leesbare breedte op iPad en Mac. / TOETS: `Theme.pageMaxWidth = 960` is goed voor een kaartenraster maar te breed voor lopende tekst of `Form`-rijen; begrens die op ongeveer 600 tot 700 pt (waarde `[K]`; de HIG zegt alleen "restrict the width of text for optimal readability"). `[B:layout]`
- **LAY-8** REGEL (macOS): geen bedieningselementen of kritieke informatie onderaan het venster en niets achter de cameraopening. / TOETS: de onderste `GlassTabBar` (`RootView.swift:21`) is op de Mac in strijd; vervang door sidebar (zie TAB-5). `[B:layout, sidebars]`
- **LAY-9** REGEL: Het venster is vrij schaalbaar tot een zinvol minimum; de layout werkt in elke venstergrootte (Slide Over, Stage Manager, iPhone Mirroring). / TOETS: minimumgrootte op macOS aanwezig (`MyBuddyApp.swift:39`, 480x640); test op 480 pt en 1400 pt breed en met `.dynamicTypeSize(.accessibility3)`. `[B:layout, windows, multitasking, adopting-liquid-glass]`

### 2.2 Typography (TYP)

- **TYP-1** REGEL: Gebruik de ingebouwde tekststijlen (`.largeTitle`, `.title`, `.headline`, `.body`, `.callout`, `.footnote`, `.caption`); die schalen mee met Dynamic Type. / TOETS: `grep -rn "\.font(\.system(size" App/` heeft nu 5 treffers (`RootView.swift:101`, `Components.swift:239`, `HomeView.swift:328`, `PurchasePages.swift:516,631`); vervang door een tekststijl of `@ScaledMetric`. `[B:typography]`
- **TYP-2** REGEL: Test met de grootste toegankelijkheidsformaten; laat layouts meegroeien: gestapeld in plaats van naast elkaar, minder kolommen, rijen die hoger worden. / TOETS: zoek `isAccessibilitySize` (nu 0 treffers) en `ViewThatFits` (1); elke `HStack` met label plus bedrag moet bij `.accessibility3` stapelen (`AnyLayout`/`ViewThatFits`). `[B:typography, layout]`
- **TYP-3** REGEL: Houd afkappen minimaal; geen afgekapte tekst in scrollende gebieden. / TOETS: `grep -rn "minimumScaleFactor" App/` (49 treffers): toegestaan voor een kerngetal per scherm (`BigAmount`), niet voor labels, titels en uitleg; die mogen wrappen. Grens voor 'te klein' is 11 pt (iOS). `[B:typography, accessibility]`
- **TYP-4** REGEL: Standaardgrootte is 17 pt op iOS/iPadOS en 13 pt op macOS; minimum 11 pt (iOS) en 10 pt (macOS). macOS ondersteunt geen Dynamic Type. / TOETS: `.caption2` (11 pt) alleen voor bijzaken; geen essentiele informatie kleiner dan `.footnote`; op macOS niet de iOS-maten kopieren. `[B:typography, accessibility]`
- **TYP-5** REGEL: Vermijd lichte gewichten (Ultralight, Thin, Light); gebruik Regular, Medium, Semibold of Bold. / TOETS: zoek `.light`, `.thin`, `.ultraLight` bij `weight(`. `[B:typography]`
- **TYP-6** REGEL: Maak hierarchie met gewicht, grootte en kleur, met zo weinig lettertypen mogelijk; het systeemfont (SF) is de standaard. De afgeronde variant is een officiele systeemvariant, maar gebruik die consequent. / TOETS: `Font.custom` komt niet voor (goed); `design: .rounded` staat op bedragen en tegels: op alle getallen of nergens. `[B:typography]`
- **TYP-7** REGEL: Getallen en valuta volgen de locale (komma als decimaalteken, punt als duizendtal); houd bedragen in kolommen uitgelijnd. / TOETS: alles via `Fmt.*`; geen handmatige `"€ " + ...`; bedragenkolommen met `.monospacedDigit()` (`[K]`); `.contentTransition(.numericText())` voor veranderende bedragen. `[B:text-fields]` (locale) / `[K]` (uitlijning)
- **TYP-8** REGEL: Niet alles hoeft mee te groeien: tabtitels en andere navigatielabels groeien niet mee; belangrijke inhoud wel. / TOETS: bij de native tabbalk automatisch; bij eigen balken geen vaste `.font(.system(size:))`. `[B:typography]`

### 2.3 Color (COL)

- **COL-1** REGEL: Gebruik semantische systeemkleuren (`.primary`, `.secondary`, `Color(.systemBackground)`, `secondarySystemGroupedBackground`, `.separator`) voor tekst en achtergronden en geef ze geen andere betekenis (geen scheidingskleur als tekstkleur). / TOETS: `grep -rn "Color(hex" App/` (26): alleen in `Theme.swift` en assets; `.white`/`.black` als tekstkleur (3 treffers op `foregroundStyle(.white)`: `Fields.swift:417`, `HomeView.swift:506,553`) alleen op een gekleurde achtergrond. `[B:color]`
- **COL-2** REGEL: Elke eigen kleur heeft een licht, een donker en een hoog-contrast-variant van beide; ook een app met een vaste weergave levert licht en donker, voor het aanpassen van Liquid Glass. / TOETS: `Theme.accent/positive/negative/warning` (`Theme.swift:60-63`) hebben licht en donker maar geen hoog-contrast; verplaats naar Color Sets in `Assets.xcassets` met de appearances Any/Dark/High Contrast. `[B:color, dark-mode]`
- **COL-3** REGEL: Tekstcontrast minimaal 4,5:1 (tot en met 17 pt), 3:1 bij 18 pt of vet; streef naar 7:1 voor kleine tekst; lukt dat niet, dan een sterkere variant bij Verhoog contrast. / TOETS: zie de meting hieronder en draai `/tmp/hig-research/contrast.py`; controleer in Xcode met Accessibility Inspector. `[B:accessibility, dark-mode]`

  Eigen meting `[K]` (WCAG-contrast tegen de negen mesh-achtergrondkleuren van `Theme.swift`, zonder glaslaag of vibrancy; een `.tile()` verlaagt het contrast nog iets):

  | Tekstkleur | Licht (tegen `meshLight`) | Donker (tegen `meshDark`) |
  |---|---|---|
  | accent | 3,66 tot 4,97 (onder 4,5 op de donkerste vlakken) | 5,87 tot 9,48 |
  | positive | 3,79 tot 5,14 | 7,02 tot 11,33 |
  | negative | 3,29 tot 4,47 | 5,45 tot 8,80 (op `.tile()` 4,38) |
  | warning | 2,50 tot 3,40 (onvoldoende, ook voor vette tekst) | 6,82 tot 11,02 |

- **COL-4** REGEL: Vertrouw nooit alleen op kleur voor status of betekenis: positief/negatief altijd met teken (+/min), symbool of tekst; zelfde voor reeksen in een grafiek. / TOETS: zoek `Theme.positive`, `Theme.negative` en `Theme.warning`: staat er een teken, symbool of woord bij? Test met `accessibilityDifferentiateWithoutColor` (nu 0 treffers). `[B:color, accessibility, toggles]`
- **COL-5** REGEL: Een kleur, een betekenis: de accentkleur betekent "interactief". / TOETS: `foregroundStyle(Theme.accent)` op niet-interactieve elementen (bijvoorbeeld het symbool in `GlassBlock.header`, `Components.swift:78`) vermijden of bewust houden; een globale `.tint(Theme.accent)` staat al op de wortel (`MyBuddyApp.swift:37`). `[B:color]`
- **COL-6** REGEL: Kleur op Liquid Glass spaarzaam: kleur de achtergrond van de primaire actie, niet de symbolen of tekst, en niet van meerdere bedieningselementen. / TOETS: `glassCard(tint:)` en `GlassBlock(tint:)` met `Theme.olive.opacity(0.3)` (bijvoorbeeld `PortfolioPages.swift:29`) weg; hooguit een `.glassProminent`-knop per scherm. `[B:color, materials, buttons]`
- **COL-7** REGEL: Kleuren in grafieken moeten ook voor kleurenblinden te onderscheiden zijn en tegen de achtergrond zichtbaar. / TOETS (meting `[K]`, Machado-simulatie, kleurverschil deltaE76 onder 15 = lastig te onderscheiden):
  - flow-kleuren: deuteranopie `flowExpenses`/`flowSaved` 6,9 (normaal 53,8); protanopie `flowVariable`/`flowSaved` 10,6.
  - `Theme.palette`: deuteranopie `[0]`/`[3]` 1,3, `[1]`/`[5]` 8,4, `[4]`/`[5]` 13,0; protanopie `[4]`/`[5]` 9,9; tritanopie `[0]`/`[6]` 12,7, `[1]`/`[4]` 10,4.
  - vlakken tegen de lichte mesh (WCAG 1.4.11 vraagt 3:1 voor grafische delen, `[K]`): alle `flow*` onder 3:1 (`flowFree` 1,15; `flowVariable` 1,38); tegen donker onder 3:1: `palette[4]` 2,69, `[5]` 2,19, `[7]` 1,80.
  - Gevolg: elke reeks krijgt naast kleur ook een tweede kanaal (vorm, lijnstijl, direct label) en aangrenzende vlakken een scheiding (zie CHT-5). `[B:charts, accessibility]`
- **COL-8** REGEL: Accentkleur via `AccentColor` in de asset catalog; op macOS geldt de app-accentkleur alleen als de systeemaccentkleur "multicolor" is, anders wint de keuze van de gebruiker. / TOETS: `project.yml` zet `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`; controleer dat de kleur ook daar met licht/donker/hoog contrast staat en dat standaardcontrols niet met de hand worden ingekleurd. `[B:color]`

### 2.4 Dark Mode (DRK)

- **DRK-1** REGEL: Geen app-eigen weergave-instelling (licht/donker); volg het systeem. / TOETS: `preferredColorScheme` komt niet voor (goed); voeg in Instellingen geen thema-schakelaar toe. `[B:dark-mode]`
- **DRK-2** REGEL: De app moet in beide modi goed werken, ook als het systeem tijdens gebruik wisselt; test ook Verhoog contrast en Verlaag transparantie, apart en samen. / TOETS: previews met `.preferredColorScheme(.dark)` en `.light`; handmatig met de instellingen aan. `[B:dark-mode]`
- **DRK-3** REGEL: Gebruik de systeemachtergronden (basis en verhoogd); een eigen achtergrond maakt het systeemonderscheid tussen vlakken (sheet, popover, multitasking) onzichtbaar. / TOETS: sheets en pagina's die `.background { MeshBackground() }` zetten (`SettingsView.swift:108`, `PageScaffold` `Components.swift:30`): de olijf-mesh op de wortel is een merkkeuze, maar herhaal hem niet in sheets; kies voor sheets de systeemachtergrond. `[B:dark-mode, adopting-liquid-glass]`
- **DRK-4** REGEL: Contrast minimaal 4,5:1, streven naar 7:1 voor kleine tekst; zachte witte afbeeldingen dempen; SF Symbols voor pictogrammen. / TOETS: zie COL-3; geen witte PNG's in de assets. `[B:dark-mode]`
- **DRK-5** REGEL: Eigen kleuren als Color Set met aparte lichte en donkere waarde, niet als hard-coded waarde. / TOETS: `Color(light:dark:)` (`Theme.swift:18`) werkt maar mist het hoog-contrast; zie COL-2. `[B:dark-mode]`

### 2.5 Materials en Liquid Glass (GLS)

- **GLS-1** REGEL: Liquid Glass vormt een aparte functionele laag voor bediening en navigatie die boven de inhoud zweeft. Gebruik het niet in de inhoudslaag; gebruik daar standaardmaterialen. Uitzondering: tijdelijke interactieve elementen zoals de knop van een schuifregelaar. / TOETS: `grep -rn "glassCard(\|glassSurface(\|glassEffect(" App/` en `GlassBlock(`/`LinkedBlock(` (92 plus 12 aanroepen): alle inhoudsblokken moeten naar een `List`/`Form`-sectie of `.background(.regularMaterial, in: ...)`/`secondarySystemGroupedBackground`; glas blijft voor tabbalk, toolbar, knoppen en zwevende bediening. `[B:materials, adopting-liquid-glass]`
- **GLS-2** REGEL: Geen glas op glas en geen gestapelde of overlappende glaselementen. / TOETS: `glassButton(...)`/`ChipButton` binnen een `GlassBlock` is glas op glas; knoppen in inhoud krijgen `.bordered`/`.borderedProminent`. `[B:adopting-liquid-glass]`
- **GLS-3** REGEL: Gebruik glaseffecten op eigen elementen spaarzaam, alleen voor de belangrijkste functionele elementen. / TOETS: buiten de systeembalken zijn hooguit een paar glaselementen tegelijk zichtbaar. `[B:materials, adopting-liquid-glass]`
- **GLS-4** REGEL: Tint op glas spaarzaam; de systeemlogica is: accentkleur op de achtergrond van de primaire knop (prominent), niet op meerdere bedieningselementen. / TOETS: zie COL-6. `[B:color]`
- **GLS-5** REGEL: Gebruik standaardcomponenten (TabView, NavigationStack-toolbar, `Button`-stijlen, sheets, popovers, menu's); die krijgen Liquid Glass vanzelf. Verwijder eigen achtergronden in balken, sheets en popovers. / TOETS: zoek de zelfgebouwde `GlassTabBar` (`RootView.swift:86`), `barBackdrop` (`RootView.swift:136-148`), `toolbarBackground`, `presentationBackground`, `.background { MeshBackground() }` in sheets. `[B:adopting-liquid-glass]`
- **GLS-6** REGEL: Meerdere eigen glaselementen naast elkaar: `GlassEffectContainer`; pas `.glassEffect` toe na de andere uiterlijkmodifiers. / TOETS: elke groep van twee of meer naburige glaselementen zit in een container (iOS 26). `[B:swiftui-glass]`
- **GLS-7** REGEL: Clear-glas alleen boven visueel rijke media (foto's, video); overal anders `regular`. / TOETS: `Glass.clear` komt niet voor in de app (goed). `[B:materials]`
- **GLS-8** REGEL: Test met Verlaag transparantie, Verhoog contrast en Verlaag beweging; standaardcomponenten passen zich aan, eigen elementen niet. / TOETS: `@Environment(\.accessibilityReduceTransparency)` (nu 0 treffers) in `GlassSurface`; de terugval voor iOS 18 (`ultraThinMaterial` plus witte rand met 14% dekking, `Glass.swift:14-15`) moet bij Verlaag transparantie een dekkend vlak worden. `[B:adopting-liquid-glass, dark-mode]`
- **GLS-9** REGEL: Houd vormen concentrisch met hun container (binnenradius = buitenradius min tussenruimte); op iOS 26 met `ConcentricRectangle`/`containerShape`. / TOETS: `Theme.tileRadius = cardRadius - cardInset` (`Theme.swift:36`) volgt dit al. `[B:adopting-liquid-glass, toolbars]`
- **GLS-10** REGEL: Terugval op iOS 18/macOS 15: standaardmateriaal in plaats van glas, standaard `.bordered`/`.borderedProminent` in plaats van `.glass`/`.glassProminent`. / TOETS: elke iOS 26-API staat achter `#available(iOS 26.0, macOS 26.0, *)` (de helpers `glassSurface`/`glassButton` doen dat al, `Glass.swift:10,42`); `UIDesignRequiresCompatibility` is geen oplossing voor een nieuwe ontwerprichting. `[B:adopting-liquid-glass]`
- **GLS-11** REGEL: Het scroll-edge-effect alleen als een scrollview achter zwevende elementen zit; gebruik de automatische stijl; een per view. / TOETS: `scrollEdgeEffectStyle` alleen bij eigen balken; bij de native balken niets doen. `[B:scroll-views]`
- **GLS-12** REGEL: Laat een achtergrondafbeelding of -kleur doorlopen onder sidebar en toolbar (`backgroundExtensionEffect()`) in plaats van een eigen laag. / TOETS: alleen relevant als de olijf-mesh onder een sidebar moet doorlopen (iOS 26). `[B:layout, sidebars]`

### 2.6 SF Symbols (SYM)

- **SYM-1** REGEL: Gebruik SF Symbols voor interface-pictogrammen, en de standaardsymbolen voor standaardacties: `plus` (toevoegen), `xmark` (annuleren/sluiten), `checkmark` (klaar), `trash` (verwijderen), `ellipsis` (meer), `square.and.arrow.up` (delen), `person.crop.circle` (account), `magnifyingglass`, `line.3.horizontal.decrease` (filter), `pencil` (hernoemen), `arrow.uturn.backward` (ongedaan maken). / TOETS: toolbar- en menuacties gebruiken deze namen; geen emoji of PNG als pictogram. `[B:icons]`
- **SYM-2** REGEL: Symbolen schalen mee met de tekst; vermijd vaste puntgroottes. / TOETS: `.font(.system(size:` op een symbool (`RootView.swift:101`, `Components.swift:239`, `HomeView.swift:328`); gebruik `Label`, een tekststijl of `@ScaledMetric`. `[B:sf-symbols, typography]`
- **SYM-3** REGEL: Gewicht van symbool en tekst gelijk houden, tenzij een van beide moet opvallen. / TOETS: `.font(.subheadline.weight(.semibold))` op een symbool naast `.headline`-tekst (`Components.swift:77-81`): bewust kiezen. `[B:icons]`
- **SYM-4** REGEL: Lever een geselecteerde variant (gevuld) alleen zelf als het nodig is; standaardcomponenten (tabbalk, toolbar) regelen dat. / TOETS: `AppTab.symbol(selected:)` (`Router.swift:16`) vervalt bij `TabView`. `[B:icons, tab-bars]`
- **SYM-5** REGEL: Rendering mode bewust: monochroom/hierarchisch met systeemkleuren; multicolor alleen als de kleur betekenis heeft. / TOETS: `symbolRenderingMode` komt niet voor; standaard is goed. `[B:sf-symbols]`
- **SYM-6** REGEL: Elk pictogram zonder zichtbare tekst heeft een toegankelijkheidslabel. / TOETS: `Image(systemName:)` in een `Button` zonder `Label(...)` of `.accessibilityLabel(...)` (nu 17 labels in de app tegen 106 `Label(`-aanroepen en veel kale `Image`-knoppen). `[B:adopting-liquid-glass, icons]`
- **SYM-7** REGEL: Symbolen en symbooleigenschappen hangen aan de OS-versie. / TOETS: elk symbool bestaat in SF Symbols 6 (iOS 18); namen uit SF Symbols 7 (de HIG-tabel noemt bijvoorbeeld `document.on.document` voor Kopieren) achter `#available(iOS 26, *)` of met de oudere naam als terugval. `[B:sf-symbols]` / `[K]` (welke namen nieuw zijn)

### 2.7 Accessibility (ACC)

- **ACC-1** REGEL: Tekst moet minstens 200% groter kunnen worden (Dynamic Type tot en met de toegankelijkheidsformaten). / TOETS: simulator met Grotere tekst op AX5; geen afgekapte of overlappende kerngetallen. `[B:accessibility, typography]`
- **ACC-2** REGEL: Raakdoelen op iOS/iPadOS 44x44 pt (minimaal 28x28), op macOS 28x28 (minimaal 20x20); ongeveer 12 pt ruimte rond elementen met een rand, ongeveer 24 pt rond elementen zonder rand. / TOETS: `Theme.buttonHeight = 42` (`Theme.swift:39`) is te laag; zet op 44. Icoonknoppen (`Image` zonder frame) krijgen `.frame(minWidth: 44, minHeight: 44)` en `.contentShape(Rectangle())`. `[B:accessibility, buttons]`
- **ACC-3** REGEL: VoiceOver: elk niet-tekstelement een label; een samengesteld blok als een element met een zinnige samenvatting; koppen als kop markeren. / TOETS: `.accessibilityElement(children: .combine)` plus `.accessibilityLabel("Overzicht: nog te verdelen 1.250 euro")` per blok (nu 12 `accessibilityElement`, 17 `accessibilityLabel`); `.accessibilityAddTraits(.isHeader)` (3) of `.accessibilityHeading`: elke kop. `[B:accessibility]` / `[K]` (voorbeeldlabel)
- **ACC-4** REGEL: Verminder beweging als Verlaag beweging aanstaat: geen zoom/schaal/blur-overgangen, vervang door fades, strakkere veren. / TOETS: `grep -rn "accessibilityReduceMotion" App/` = 0. Aan te passen: `RootView.tabTransition` (`.scale(0.98)`), `matchedGeometryEffect` (indicator), `.animation(Theme.motion, value: store.data)` (`Components.swift:23`), `.numericText()`-overgangen. `[B:accessibility, motion]`
- **ACC-5** REGEL: Informatie nooit alleen via kleur; respecteer "Onderscheid zonder kleur". / TOETS: zie COL-4. `[B:accessibility]`
- **ACC-6** REGEL: Ondersteun Verhoog contrast voor eigen kleuren. / TOETS: zie COL-2; `@Environment(\.colorSchemeContrast)` voor kleuren die niet uit de asset catalog komen. `[B:accessibility]`
- **ACC-7** REGEL: Elke functie die via een gebaar werkt (lang indrukken, swipen) is ook via een zichtbare knop of menu bereikbaar. / TOETS: "Volgorde aanpassen" zit in een contextmenu op de blokken (`BlockOrder.swift`, 2 `contextMenu`-treffers) en nergens anders: voeg een menu-item toe in de toolbar of in Instellingen. `[B:accessibility]`
- **ACC-8** REGEL: Vermijd tijdgebonden interface (meldingen die vanzelf verdwijnen); sluit met een expliciete actie. / TOETS: `grep -rn "Task.sleep\|asyncAfter" App/` (11): geen melding verbergen na een timer. `[B:accessibility]`
- **ACC-9** REGEL: Werk met alleen een toetsenbord (Full Keyboard Access) en Voice Control: zinvolle labels, logische focusvolgorde. / TOETS: `accessibilityInputLabels` voor knoppen met lange of dubbele labels; tab-volgorde via `@FocusState` in formulieren. `[B:accessibility, keyboards]`
- **ACC-10** REGEL: Meld wijzigingen die alleen visueel zichtbaar zijn ook voor VoiceOver. / TOETS: na een berekening die een grafiek of bedrag verandert: `AccessibilityNotification.Announcement`/`.LayoutChanged` (`[K]` voor de API-naam; de regel staat in `[B:charts]`). `[B:charts]`

### 2.8 Motion (MOT)

- **MOT-1** REGEL: Beweging is doelgericht en kort; geen beweging om de beweging; geen extra beweging bij vaak herhaalde interacties. / TOETS: `PageScaffold` animeert de hele pagina bij elke wijziging van `store.data`, `router.focusMonth` en `router.periodMode` (`Components.swift:23-25`); beperk tot concrete waarden (een bedrag, een lijst). `[B:motion]`
- **MOT-2** REGEL: Beweging is nooit de enige informatiedrager; vul aan met tekst of haptiek. / TOETS: elke animatie die iets meldt (bedrag omhoog, blok verschijnt) heeft ook een leesbare tekst of status. `[B:motion]`
- **MOT-3** REGEL: Laat mensen niet op een animatie wachten; animaties volgen gebaren en zijn te onderbreken. / TOETS: geen `Task.sleep` vooraf aan navigatie; korte `smooth`/`snappy` (nu 0,25 tot 0,3 s) is goed. `[B:motion, accessibility]`
- **MOT-4** REGEL: Gebruik de systeemanimaties van standaardcomponenten (navigatie, sheets, tabs) en pas Verlaag beweging toe op eigen animaties. / TOETS: de eigen crossfade-plus-schaal tussen tabs (`RootView.swift:53-67`) vervalt bij `TabView`. `[B:motion, accessibility]`
- **MOT-5** REGEL: Verander je een grafiek of as met animatie, markeer dat dan ook op een andere manier. / TOETS: `.animation(Theme.motion, value: points)` in `Charts.swift` blijft, plus een bijgewerkt `accessibilityLabel` en zichtbare kernwaarde (zie CHT-6). `[B:charts]`

### 2.9 Tab bars (TAB)

- **TAB-1** REGEL: Een tabbalk is voor navigatie tussen secties op het hoogste niveau, niet voor acties (acties horen in een toolbar). / TOETS: geen tab die een actie uitvoert (bijvoorbeeld "Voorbeelddata laden"). `[B:tab-bars]`
- **TAB-2** REGEL: De tabbalk blijft zichtbaar bij het navigeren in een sectie (uitzondering: een modaal scherm erover); schakel tabs nooit uit of verberg ze; is een sectie leeg, leg uit waarom. / TOETS: `RootView.swift:20` verbergt de tabbalk bij een zichtbaar toetsenbord; de native tabbalk regelt dit zelf. `[B:tab-bars]`
- **TAB-3** REGEL: Gebruik zo weinig tabs als nodig en vermijd de overloop-tab "Meer" (iOS/iPadOS); minder tabs is makkelijker te overzien, en bij een complexe structuur past een sidebar of een tabbalk die in een sidebar kan veranderen. / TOETS: nu 3 tabs (goed); een vierde of vijfde tab alleen als die dagelijks nodig is. De HIG noemt geen getal; "hoogstens 5 op een iPhone" is `[K]`. `[B:tab-bars]`
- **TAB-4** REGEL: Elke tab een label van een woord en een gevuld SF Symbol. Voor deze Nederlandse app horen de labels Nederlands te zijn. / TOETS: `AppTab.title` (`Router.swift:8-14`) is "Home", "Savings", "Tools"; voorstel `[K]`: "Overzicht", "Sparen", "Hulpmiddelen" (of een andere vaste Nederlandse eenwoord-set). `[B:tab-bars, writing]`
- **TAB-5** REGEL: Gebruik de native tabbalk: `TabView { Tab("Naam", systemImage: "...") { ... } }` met `.tabViewStyle(.sidebarAdaptable)` (iOS 18/macOS 15). Gedrag volgens Apple: iPhone onderbalk, iPad bovenbalk die in een sidebar kan veranderen, macOS altijd een sidebar. / TOETS: `grep -rn "TabView" App/` = 0 en de zelfgebouwde `GlassTabBar`; vervangen. `[A:swiftui/tabviewstyle/sidebaradaptable, B:tab-bars, sidebars]`
- **TAB-6** REGEL: Bewaar de navigatiestatus per tab; wisselen tussen tabs wist het pad niet. Opnieuw tikken op de actieve tab brengt je terug naar de hoofdpagina. / TOETS: `Router.select` (`Router.swift:66-73`) zet het pad van de nieuwe tab leeg ook bij wisselen van een andere tab; wis alleen als `newTab == tab`. `[B:tab-bars]` (bewaren) / `[K]` (opnieuw tikken)
- **TAB-7** REGEL: Op iOS 26 zweeft de tabbalk als glas boven de inhoud, die eronder doorloopt; een eigen achtergrond eronder hoort er niet. Optioneel: `.tabBarMinimizeBehavior(.onScrollDown)` (iOS 26). / TOETS: `barBackdrop` en `.fill(.bar)` verwijderen; inhoud mag onder de balk door scrollen (README zegt nu het tegendeel: "neemt eigen ruimte in"). `[B:tab-bars, adopting-liquid-glass]`
- **TAB-8** REGEL: Een badge alleen voor kritieke informatie. / TOETS: nu geen badges. `[B:tab-bars]`
- **TAB-9** REGEL: Zoeken als een eigen tab: `Tab(role: .search)`; het systeem zet die aan het trailing-uiteinde. / TOETS: alleen relevant als globaal zoeken komt (zie SRC-2). `[B:tab-bars, search-fields]` `[A:swiftui/tabrole/search]`
- **TAB-10** REGEL (iPadOS): overweeg elke tab ook als menu-item in het Weergave-menu, met een sneltoets. / TOETS: `.commands { CommandGroup(after: .sidebar) { ... } }` met Cmd+1/2/3. `[B:the-menu-bar]`

### 2.10 Sidebars en split views (SID)

- **SID-1** REGEL: Een sidebar toont secties of verzamelingen op het hoogste niveau; maximaal twee niveaus; dieper wordt een split view met een inhoudslijst. / TOETS: sidebar-items = de tabs plus eventueel groepen (bijvoorbeeld "Sparen: Spaarpotten, Beleggingen, Doelen"). `[B:sidebars]`
- **SID-2** REGEL: Verberg de sidebar niet standaard; laat hem verbergen via de bekende interactie (iPadOS: veeg; macOS: knop of Weergave-menu "Toon/Verberg navigatiekolom"). / TOETS: `NavigationSplitViewVisibility` niet op `.detailOnly` als standaard. `[B:sidebars]`
- **SID-3** REGEL: Sidebar-items met SF Symbols en korte labels; sidebar-iconen volgen de accentkleur; vaste kleuren alleen met een duidelijk doel. / TOETS: `Tab(..., systemImage:)` levert dit. `[B:sidebars]`
- **SID-4** REGEL: Plaats geen kritieke informatie of acties onderaan een sidebar (macOS). / TOETS: geen "Instellingen" of "Account" als vaste knop onderaan; zet ze bovenaan of in de toolbar/App-menu. `[B:sidebars]`
- **SID-5** REGEL: Wil je alleen een sidebar zonder tabbalk-variant, gebruik dan `NavigationSplitView`; wil je beide, `sidebarAdaptable`. / TOETS: een keuze per platform vastleggen in `docs/design`. `[B:sidebars, tab-bars]`
- **SID-6** REGEL: Split views moeten bij smalle, compacte en tussenliggende breedtes logisch navigeerbaar blijven en hebben redelijke minimum- en maximumbreedtes; verborgen kolommen zijn op meer dan een manier terug te halen. / TOETS: test met iPad in Slide Over en het kleinste macOS-venster. `[B:split-views]`

### 2.11 Navigatie en navigatiebalk (NAV)

- **NAV-1** REGEL: Hierarchie met `NavigationStack` en `NavigationLink(value:)`; terug met de standaard Back-knop (symbool, niet de tekst "Terug"); gebruik geen eigen terugknop die de veeg-terug-beweging breekt. / TOETS: `Destination`-enum plus `navigationDestination(for:)` (aanwezig); geen `.navigationBarBackButtonHidden` zonder reden. `[B:toolbars, designing-for-ios]` (Back) / `[K]` (veeg-terug)
- **NAV-2** REGEL: Gebruik een grote titel om oriëntatie te geven op de hoofdpagina van een sectie; hij gaat bij scrollen over in de standaardtitel. / TOETS: `PageScaffold` zet `.navigationBarTitleDisplayMode(.large)` op alle pagina's (`Components.swift:32-34`): kies `.large` op de tab-hoofdpagina's en `.inline` op dichte detailpagina's (`[K]`: de HIG noemt alleen "large title ... to stay oriented"). `navigationBarTitleDisplayMode` bestaat niet op macOS; `toolbarTitleDisplayMode(.large)` (iOS 17/macOS 14) werkt overal. `[B:toolbars]` `[A:swiftui/view/navigationbartitledisplaymode(_:), toolbartitledisplaymode(_:)]`
- **NAV-3** REGEL: Titels kort (ongeveer onder 15 tekens waar mogelijk) en geen appnaam als titel. / TOETS: `PageScaffold(title:)` en `Window("MyBuddy")` (`MyBuddyApp.swift:24`): op macOS toont de venstertitel de sectie, niet "MyBuddy". `[B:toolbars]`
- **NAV-4** REGEL: Minder niveaus op grote schermen; meer inhoud in minder geneste lagen. / TOETS: maximaal drie niveaus diep (tab, pagina, detail); blok, pagina, detail, sheet is te veel. `[B:designing-for-macos, designing-for-ipados]`
- **NAV-5** REGEL: Een duidelijke navigatiehierarchie, gescheiden van de inhoud. / TOETS: per `Destination` een primaire route; tel de ingangen (`NavigationLink(value: .x)`, `router.open(.x)`, `LinkedBlock(destination: .x)`) en schrap dubbele. `[B:adopting-liquid-glass]`
- **NAV-6** REGEL: Context in de balk met een subtitel (macOS, en iOS 26): `.navigationSubtitle("oktober 2026")`. / TOETS: voor de periodekeuze op Savings; niet op iOS 18 (alleen iOS 26 en macOS 13). `[A:swiftui/view/navigationsubtitle(_:)]`

### 2.12 Toolbars (TLB)

- **TLB-1** REGEL: Een toolbar bevat de titel, navigatie en acties voor de huidige weergave. Kies bewust en voorkom overvolle balken; maximaal ongeveer drie groepen. / TOETS: per scherm hooguit een primaire actie plus een "Meer"-menu (`ellipsis`). `[B:toolbars]`
- **TLB-2** REGEL: Een primaire actie (Klaar, Bewaar) trailing en prominent; bij een sheet Annuleer leading. / TOETS: `ToolbarItem(placement: .confirmationAction)` en `.cancellationAction`; op iOS 26 `Button(role: .confirm)`/`.close` of `.buttonStyle(.borderedProminent)`. `[B:toolbars, sheets]` `[A:swiftui/buttonrole/confirm]`
- **TLB-3** REGEL: Gebruik herkenbare symbolen voor bekende acties, zonder eigen rand of cirkel; meng tekst- en symbool-items niet binnen een groep (scheid met `ToolbarSpacer`, iOS 26). / TOETS: `Label("Instellingen", systemImage: "gearshape")` in de toolbar toont automatisch alleen het symbool. `[B:toolbars, adopting-liquid-glass]`
- **TLB-4** REGEL: Geen eigen toolbarachtergronden en geen getinte bedieningselementen; laat de inhoud de kleur bepalen. / TOETS: `grep -rn "toolbarBackground" App/` = 0 (goed). `[B:toolbars, adopting-liquid-glass]`
- **TLB-5** REGEL: Gebruik de standaard Back- en Close-knoppen en vermijd een tekstlabel "Terug"/"Sluit". / TOETS: sheets sluiten met `xmark` of "Annuleer"; geen eigen "Sluit"-tekstknop. `[B:toolbars]`
- **TLB-6** REGEL: Verberg een toolbar-item als geheel (`if` om het `ToolbarItem`), niet de view erin; anders blijft een lege knop over. / TOETS: `PageScaffold` (`Components.swift:35-43`) doet dit goed. `[B:adopting-liquid-glass]`
- **TLB-7** REGEL (macOS): elk toolbar-item bestaat ook als menucommando; Instellingen komt niet in de toolbar maar in het App-menu. / TOETS: zie MAC-2 en SET-4. `[B:toolbars, settings]`
- **TLB-8** REGEL: Een "Meer"-menu voor secundaire acties, alleen als het echt nodig is. / TOETS: bijvoorbeeld "Volgorde aanpassen" (ACC-7) en "Exporteren" daarin. `[B:toolbars]`

### 2.13 Sheets en modality (SHT)

- **SHT-1** REGEL: Een sheet is voor een afgebakende taak die dicht bij de huidige context ligt (informatie vragen, iets toevoegen of kiezen). Voor lange of complexe flows, voor een hele pagina met veel secties, en voor navigatie: gebruik een duwpagina, een eigen tab of volledig scherm. / TOETS: `grep -rn "\.sheet(" App/` (26): voor elke sheet de vraag "een taak, kort, eindigt met Annuleer/Bewaar?". `SettingsView` in een sheet (`RootView.swift:26`) voldoet niet. `[B:sheets, modality]`
- **SHT-2** REGEL: Een sheet tegelijk; maak geen sheet vanuit een sheet (sluit de eerste eerst). / TOETS: `CloudViews.swift:115-116` en `AuthView.swift:636-637` openen sheets vanuit de Instellingen-sheet: verdwijnt als Instellingen een pagina wordt. `[B:sheets, modality]`
- **SHT-3** REGEL: iOS/iPadOS: Annuleer links, Klaar rechts; combineer Klaar altijd met Annuleer of Terug; niet alle drie. / TOETS: elke sheet-toolbar. `[B:sheets]` (guidance bijgewerkt 24 maart 2026)
- **SHT-4** REGEL: Geef de sheet een titel die de taak noemt. / TOETS: `.navigationTitle` in elke sheet (bijvoorbeeld "Nieuwe spaarpot", niet "Nieuw"). `[B:modality]`
- **SHT-5** REGEL: Ondersteun veeg-om-te-sluiten; bij niet-opgeslagen wijzigingen vraag je bevestiging met een action sheet. / TOETS: `.interactiveDismissDisabled(hasChanges)` plus `confirmationDialog` met "Bewaar" / "Gooi weg" / "Verder bewerken" (nu 0 `interactiveDismissDisabled`). `[B:sheets, modality]` `[A:swiftui/view/interactivedismissdisabled(_:)]`
- **SHT-6** REGEL: Detents: `.medium` en `.large` voor korte keuzes (met `presentationDragIndicator(.visible)`), alleen `.large` voor formulieren. / TOETS: 2 `presentationDetents`, 0 `presentationDragIndicator` (grabber ontbreekt). `[B:sheets]`
- **SHT-7** REGEL: Op iPad en Mac een formulier- of paginasheet met standaardgrootte: `.presentationSizing(.form)` (iOS 18/macOS 15). / TOETS: geen schermbrede sheet op iPad; zoek `presentationSizing`. `[B:sheets]` `[A:swiftui/view/presentationsizing(_:)]`
- **SHT-8** REGEL: Verwijder eigen achtergronden van sheets en popovers; laat de systeemglaslaag werken. / TOETS: zie DRK-3 en GLS-5. `[B:adopting-liquid-glass]`
- **SHT-9** REGEL: Houd een modale taak eenvoudig en kort; een hierarchie van schermen in een sheet is een "app in de app". / TOETS: de importflow in `BackupUI.swift` en `PurchasePages` (stappen) beoordelen: een pad zonder knoppen die op de sluitknop lijken. `[B:modality]`
- **SHT-10** REGEL: Popovers alleen in brede weergaven; in compacte weergave een sheet. / TOETS: `popover` komt niet voor; houd dat zo of gebruik `presentationCompactAdaptation`. `[B:popovers]`

### 2.14 Alerts (ALT)

- **ALT-1** REGEL: Alerts spaarzaam, alleen voor kritieke en liefst bruikbare informatie; alleen informatie hoort inline. / TOETS: `grep -rn "\.alert(" App/` (2): voor elk of er een inline alternatief is (`NoticeBanner`, voetnoot). `[B:alerts]`
- **ALT-2** REGEL: Geen alert voor gebruikelijke, ongedaan te maken acties, ook niet als ze destructief zijn. / TOETS: een pot of regel verwijderen mag met "Maak ongedaan" in plaats van een dialoog; "Alles wissen" (onomkeerbaar, ook in de cloud) wel bevestigen. `[B:alerts, feedback, undo-and-redo]`
- **ALT-3** REGEL: De titel beschrijft de situatie ("Opslaan is mislukt", niet "Fout"), hoogstens twee regels; knoptitels zijn een of twee woorden met een werkwoord; "Annuleer" voor annuleren; "OK" alleen bij puur informatieve alerts. / TOETS: `Button("OK")` met een bevestigende betekenis opsporen. `[B:alerts]`
- **ALT-4** REGEL: Destructieve stijl voor een knop die een onbedoelde destructieve actie uitvoert; de bewust gekozen actie niet. Plaats de standaardknop trailing of bovenaan; voeg Cancel toe bij destructieve acties. / TOETS: `role: .destructive` (aanwezig) en altijd een Annuleer. `[B:alerts, buttons]`
- **ALT-5** REGEL: Geen alert bij het starten van de app; toon een discreet label of gecachte data. / TOETS: geen `.alert` aan een `.task` op de wortel. `[B:alerts]`
- **ALT-6** REGEL: Nooit meer dan een alert tegelijk. / TOETS: bij `syncPrompts` (`SyncController`) twee prompts tegelijk? Zet ze in een wachtrij. `[B:modality]`
- **ALT-7** REGEL: Foutmeldingen dicht bij het probleem, zonder verwijt, met wat de gebruiker kan doen; geen "Oeps". / TOETS: zie WRT-6. `[B:writing]`

### 2.15 Bevestigingsdialogen en action sheets (DLG)

- **DLG-1** REGEL: Een `confirmationDialog` (action sheet) voor keuzes bij een bewuste actie; een alert voor onverwacht nieuws. / TOETS: 17 `confirmationDialog`-aanroepen (goed). `[B:action-sheets, alerts]`
- **DLG-2** REGEL: Houd de titel op een regel, geef een bericht alleen als dat nodig is; destructieve keuzes bovenaan, Annuleer onderaan (SwiftUI voegt Annuleer zelf toe). / TOETS: `SettingsView.swift:118-146`. `[B:action-sheets]`
- **DLG-3** REGEL: Laat een action sheet niet scrollen; houd het aantal keuzes klein. / TOETS: hoogstens vier knoppen. `[B:action-sheets]`
- **DLG-4** REGEL: Verbind de dialoog met het element dat hem opent (op iPad/Mac komt hij daar uit); zet `.confirmationDialog` op de knop of rij, niet op de wortelview. / TOETS: nu hangen ze aan `NavigationStack`/`Form` (`SettingsView.swift:118,131`). `[B:adopting-liquid-glass]` (apparaattest nodig)
- **DLG-5** REGEL: Benoem het gevolg bij onomkeerbare acties; de cloudgevolgen staan al in de berichten (goed). / TOETS: "Dit kan niet ongedaan worden gemaakt." blijft. `[B:alerts]`
- **DLG-6** REGEL: Geef voor veelvoorkomende acties liever Ongedaan maken dan een bevestiging. / TOETS: `@Environment(\.undoManager)` (nu 0) of een "Verwijderd. Maak ongedaan"-balk. `[B:undo-and-redo]`

### 2.16 Lijsten en tabellen (LST)

- **LST-1** REGEL: Tekst staat voorop in een rij; houd rijtekst kort; navigatie wordt aangegeven met een disclosure-indicator (`NavigationLink`), een info-knop alleen om meer informatie bij de rij te tonen. / TOETS: eigen rijen met `chevron.right` (`Components.swift:88`) vervangen door `NavigationLink` in een `List`. `[B:lists-and-tables]`
- **LST-2** REGEL: Gebruik de gegroepeerde stijl (`List` met `.insetGrouped`/`.formStyle(.grouped)`) voor groepen; sectiekoppen in de normale hoofdletterstijl, niet in hoofdletters. / TOETS: `SectionLabel` doet `text.uppercased()` (`Components.swift:137`): verwijderen; `Section("Titel")` laat het systeem de stijl bepalen (`.textCase(nil)` als je zelf een `Text` gebruikt). `[B:adopting-liquid-glass, lists-and-tables]`
- **LST-3** REGEL: Veelgebruikte rij-acties als swipe-actie, en spiegel ze bovenin het contextmenu. / TOETS: `grep -rn "swipeActions" App/` = 0 voor rijen die je kunt bewerken of verwijderen (inkomsten-/uitgavenregels, potten, beleggingen). `[B:adopting-liquid-glass, context-menus]`
- **LST-4** REGEL: Herordenen mag ook zonder toevoegen/verwijderen (`.onMove`, `EditButton`). / TOETS: de blokvolgorde-sheet gebruikt `.onMove` (goed); zie ACC-7 voor de ingang. `[B:lists-and-tables]`
- **LST-5** REGEL: Selectiefeedback: een navigatielijst markeert de gekozen rij (iPad/Mac), een keuzelijst toont een vinkje. / TOETS: `List(selection:)` in de sidebar. `[B:lists-and-tables]`
- **LST-6** REGEL: Bij te lange namen een ellips in het midden (`.truncationMode(.middle)`) of laat de tekst wrappen. / TOETS: namen van potten/beleggingen in rijen. `[B:lists-and-tables]`
- **LST-7** REGEL: Gebruik de standaard rijhoogte en -padding (op iOS 26 groter); krimp ze niet. / TOETS: `listRowInsets` en vaste rijhoogtes opsporen. `[B:adopting-liquid-glass]`
- **LST-8** REGEL: Contextmenu: weinig items, de belangrijkste eerst, destructief laatst en als destructief gemarkeerd, onbeschikbare items verbergen (niet dimmen), overal consequent, en alles ook in de hoofd-UI. / TOETS: 2 `contextMenu`-treffers tegen tientallen rijsoorten; maak het een patroon via een gedeelde `View`-extensie. `[B:context-menus]`
- **LST-9** REGEL: Een lege lijst krijgt een lege staat (EMP-1). / TOETS: `EmptyHint` (14 plekken) is de eigen versie. `[B:writing]`

### 2.17 Grafieken (CHT)

- **CHT-1** REGEL: Een grafiek is er om een boodschap te laten zien; kies gangbare typen (lijn voor verloop in de tijd, staaf voor vergelijken of een som per periode, sector spaarzaam). Houd het eenvoudig en laat details op verzoek zien. / TOETS: boven elke grafiek staat een kop of een zin met de kernboodschap ("Je buffer groeit naar 5.000 euro in mei"), niet alleen de bloktitel. `[B:charting-data, charts]`
- **CHT-2** REGEL: Elke grafiek is toegankelijk: labels die waarden en onderdelen beschrijven en elementen waarmee VoiceOver kan interacteren. Swift Charts geeft standaard een element per mark en een Audio Graph; verbeter dat met een titel en samenvatting (`AXChartDescriptorRepresentable`/`.accessibilityChartDescriptor`, iOS 15/macOS 12) en `accessibilityLabel`/`accessibilityValue` op marks. Labels: context plus waarde plus eenheid ("januari 2026: 1.250 euro", niet "1/26: 1250"), geen subjectieve woorden ("snel", "bijna"), beschrijf wat het betekent, niet welke kleur; verberg de zichtbare as- en tick-labels voor VoiceOver. Voor een kleine grafiek (sparkline) volstaat een samenvattend label. / TOETS: `grep -rn "accessibilityChartDescriptor" App/` = 0; van de 8 grafiekviews hebben alleen `BufferChart` (`BufferPages.swift:526`) en `DayBalanceChart` (`CashflowPages.swift:315`) een samenvattend label. `[B:charts]` `[A:swiftui/axchartdescriptorrepresentable, charts/chartcontent]`
- **CHT-3** REGEL: Kies de as bewust: vast bereik als min en max betekenis hebben (percentage 0 tot 100), dynamisch als de waarden sterk wisselen; staafgrafieken beginnen bij nul, lijngrafieken mogen een andere ondergrens hebben als het verloop telt; gangbare tickreeksen (0, 5, 10); niet te veel rasterlijnen. / TOETS: `Charts.swift:89` `includesZero: false` voor lijnen is goed; elke `BarMark` heeft `includesZero: true` (staat nu standaard). `[B:charts]`
- **CHT-4** REGEL: Gebruik een reeks per kleur en dezelfde kleur voor dezelfde grootheid door de hele app, ook tussen de kleine en de grote versie van dezelfde gegevens. / TOETS: `Theme.flow*` zijn gedeeld (goed); `BufferChart`, `ProjectionPage`, `GoalCurveChart` en `SavingsGoalChart` kiezen eigen kleuren (`Theme.warning`, `Theme.flowExpenses`, ...): een tabel `grootheid -> kleur` vastleggen. `AllocationDonut` kleurt per positie (`Theme.color($0)`, `Charts.swift:158-159`) terwijl de sectoren op waarde zijn gesorteerd: een beleggingssoort wisselt van kleur zodra de volgorde verandert; kleur per `HoldingKind` vastleggen. `[B:charting-data]` / `[K]` (eigen leeswerk)
- **CHT-5** REGEL: Gebruik niet alleen kleur: vorm, patroon of lijnstijl erbij; geef aangrenzende gekleurde vlakken een scheiding. / TOETS: bij twee of meer reeksen `.symbol(by:)`, `.lineStyle(by:)` of directe labels aan de lijn; gestapelde staven een dunne witte rand of `.cornerRadius`; zie COL-7 voor de meting. `[B:charts, accessibility]`
- **CHT-6** REGEL: Interactie is optioneel; kritieke informatie staat zonder interactie zichtbaar. Maak het raakvlak het hele plotgebied (scrubben, `chartXSelection`, iOS 17/macOS 14) met een `RuleMark` en annotatie. / TOETS: naast elke grafiek staat de kernwaarde als tekst (laatste waarde, totaal). `[B:charts]` `[A:swiftui/view/chartxselection(value:)]`
- **CHT-7** REGEL: Een grafiek zonder gegevens toont een lege staat met uitleg en actie; een grafiek met een punt toont dat punt plus tekst; pas vanaf twee punten een lijn. / TOETS: `PortfolioPages.swift:66-75` toont "Groei" alleen bij `series.count > 1` en anders een voetnoot (`:72-74`); `series` komt uit `portfolioSeries` (`Invest.swift:152-170`), dat maanden zonder meetpunt overslaat (`guard any`) en na de huidige maand verwachte punten toevoegt. Een belegging zonder enig meetpunt geeft dus een lege reeks: een gevolgde belegging krijgt bij toevoegen geen beginwaarde (`PortfolioPages.swift:705-707`: `initial` is nil als `tracked`) en dus pas een punt als `refreshPrices` slaagt; een handmatige belegging met waarde 0 ook niet. `TimeLineChart` (`Charts.swift:58-95`) tekent bij een werkelijk punt alleen een `PointMark`. De voetnoot ("groeit mee zodra er meer meetpunten zijn") klopt dan niet: er is er nog geen. Gereproduceerd: een gevolgde belegging zonder koers en een handmatige met waarde 0 geven 0 punten; met een beginwaarde of een eerste koers 13 punten (1 werkelijk, 12 verwacht). Test ook: meerdere punten en koersophaling mislukt. `[P]` (HIG-regel over lege staten: `[B:writing]`)
- **CHT-8** REGEL: Houd grafiekgegevens robuust. / TOETS `[K]` (Swift Charts-praktijk):
  - alleen eindige waarden (`isFinite`); NaN en oneindig geven lege of gebroken grafieken;
  - unieke, stabiele `id`'s per punt;
  - `domain: lo...hi` alleen met `lo < hi`; een omgekeerd bereik of NaN laat Swift crashen (`CashflowPages.swift:303` `floorValue...ceilingValue`, `BufferPages.swift:512` `0...topValue`); beide zijn nu veilig doordat `pad >= 50` (`CashflowPages.swift:261`) en `topValue >= 1,05` (`BufferPages.swift:498-502`) gelden: houd die ondergrens;
  - meerdere reeksen in een `LineMark` apart houden met `series:` of `foregroundStyle(by:)`, anders verbindt Charts alle punten tot een lijn;
  - bij `unit: .month` datums op de eerste van de maand;
  - een expliciete `.frame(height:)` in een `ScrollView`.
- **CHT-9** REGEL: De grafiek is een zuivere functie van het model: reeksen worden bij elke wijziging van `store.data` opnieuw berekend, zonder `@State`-kopie. / TOETS: in de chartviews geen `@State var points`; wel `let points` of een berekende eigenschap die van de `@Observable` store afhangt. `[K]`
- **CHT-10** REGEL: Maak compacte grafieken zo breed mogelijk; korte aslabels (`Fmt.compact`), eenheid in de titel. / TOETS: de Home-versies verbergen de assen (`showsAxes: false`) en zetten dan wel de legenda en kernwaarde ernaast. `[B:charts]`
- **CHT-11** REGEL: Houd vergelijkbare grafieken consistent in type, stijl, kleuren, annotaties en hoogte. / TOETS: de acht grafiekviews (`TimeLineChart`, `FlowChart`, `AllocationDonut`, `SavingsGoalChart`, `BufferChart`, `ProjectionPage`-chart, `GoalCurveChart`, `DayBalanceChart`) delen as-stijl, legenda-plaats en hoogtes via een gemeenschappelijke modifier. `[B:charting-data]`
- **CHT-12** REGEL: Een sector- of donutgrafiek alleen voor een kleine verdeling van een geheel; de verdeling is ook als lijst met percentages te lezen. / TOETS: `AllocationDonut` (`Charts.swift:146`) plus een legenda met waarde en percentage. `[B:charts]` (bar vs. delen van een geheel) / `[K]`

### 2.18 Instellingen (SET)

- **SET-1** REGEL: Algemene, zelden gewijzigde opties horen in instellingen; opties voor een specifieke taak (delen van het scherm tonen of verbergen, herordenen, filteren) horen in het scherm zelf. / TOETS: "Volgorde aanpassen" en "Kies voor Home" zijn taakspecifiek en blijven in de context; de rekeninstellingen (inflatie, opnamepercentage, spaarrente) horen bij de Toekomstschatting of in een korte sectie "Rekenen" (`SettingsView.swift:23-32`, `[K]` voor de keuze). `[B:settings]`
- **SET-2** REGEL: Minimaliseer het aantal instellingen, kies standaarden die voor de meeste mensen goed zijn, en vraag niets wat het systeem al weet. / TOETS: geen schakelaars voor weergave, taal of biometrie; de koersverbinding testen en de diagnoseregels (`SettingsView.swift:50-68`) onder "Geavanceerd". `[B:settings, managing-accounts]`
- **SET-3** REGEL: Respecteer systeeminstellingen en maak er geen kopie van (toegankelijkheid, tekstgrootte, haptiek, donkere modus). / TOETS: geen "Haptiek aan/uit" in de app; `sensoryFeedback` volgt de systeeminstelling. `[B:settings, playing-haptics]`
- **SET-4** REGEL: Instellingen is een volledige pagina of een eigen venster, geen sheet. iPhone/iPad: een pagina op de navigatiestapel, bereikbaar via een toolbar-knop of een eigen sidebar-item. Mac: de `Settings`-scene in `#if os(macOS)` (opent met Cmd+komma, `Settings` bestaat alleen op macOS, 11+; `SettingsLink`/`openSettings` vanaf macOS 14). / TOETS: `RootView.swift:26` `.sheet(isPresented: $router.showSettings)`, `Router.showSettings` (`Router.swift:57`), `Components.swift:38` (de tandwiel-knop); `MyBuddyApp.swift:20-32` heeft geen `Settings`-scene. `[B:settings, sheets, modality]` `[A:swiftui/settings, swiftui/settingslink]`
- **SET-5** REGEL: macOS-instellingenvenster: een niet-aanpasbare toolbar met knoppen voor de panes (de actieve pane is gemarkeerd), een venstertitel die de pane noemt (anders "<App> Settings"), de laatst gebruikte pane onthouden, minimaliseer en zoom gedimd, en geen instellingenknop in de toolbar van het hoofdvenster maar in het App-menu. / TOETS: `Settings { TabView { Tab("Algemeen", systemImage: "gearshape") {...}; Tab("Account", systemImage: "person.crop.circle") {...}; Tab("Gegevens", ...) } }` met `@AppStorage` voor de laatste pane. `[B:settings, the-menu-bar]`
- **SET-6** REGEL: Groepeer logisch en zet het vaakst gebruikte bovenaan: Account (een rij die naar een eigen pagina leidt), Rekenen, Koersen, Gegevens (back-up, import/export), Over; gevaarlijke acties ("Alles wissen") onderaan in een eigen sectie en destructief. / TOETS: de volgorde in `SettingsView.swift` (nu Account, Rekenen, Koersdata, Koersen, Back-up, Gegevens, Over). `[B:settings, writing]` (groeperen) / `[K]` (volgorde)
- **SET-7** REGEL: Kort en praktisch benoemen; als het label niet genoeg is, een uitleg die zegt wat het doet als het aan staat. / TOETS: voetnoten van meer dan twee zinnen (`SettingsView.swift:31`, `:72`) inkorten. `[B:writing]`
- **SET-8** REGEL: Verwijs naar een systeeminstelling met een knop, niet met een beschrijving van waar die staat. / TOETS: bij een ontbrekende toestemming een knop "Open Instellingen". `[B:writing]`
- **SET-9** REGEL: iPad met toetsenbord: het item "<App> > Instellingen" in de menubalk is gereserveerd voor de iPadOS-instellingenpagina van de app; een eigen instellingengebied krijgt een apart menu-item eronder. / TOETS: `.commands { CommandGroup(after: .appSettings) { Button("Instellingen van MyBuddy…") {...}.keyboardShortcut(",", modifiers: .command) } }`. `[B:the-menu-bar, keyboards]`

### 2.19 Account (ACT)

- **ACT-1** REGEL: Een account is geen drempel: vraag er alleen om als de kernfunctie het vereist en stel aanmelden zo lang mogelijk uit. / TOETS: `AppRoot` (`MyBuddyApp.swift:86-102`) toont `AuthView` zolang er geen account is, ook bij lokale accounts zonder cloud; overweeg een automatisch lokaal profiel en "Inloggen voor synchronisatie" als keuze op de Account-pagina. `[B:managing-accounts]`
- **ACT-2** REGEL: Leg de voordelen van een account uit waar je erom vraagt ("synchroniseer je gegevens tussen iPhone, iPad en Mac"). / TOETS: een korte tekst op het aanmeldscherm. `[B:managing-accounts]`
- **ACT-3** REGEL: Als je het aanmaken van een account in de app aanbiedt, bied dan ook het verwijderen aan (niet alleen deactiveren), duidelijk te vinden, met uitleg over de duur en een melding als het klaar is. / TOETS: `DeleteCloudAccountSheet` en `DeleteAccountSheet` staan in `CloudViews.swift:116` en `AuthView.swift:637`; verhuizen naar de Account-pagina. `[B:managing-accounts]`
- **ACT-4** REGEL: Benoem de aanmeldmethode bij naam ("Inloggen met e-mail"); geen app-eigen schakelaar voor biometrie; gebruik de term "toegangscode" niet voor het wachtwoord; vul nooit een wachtwoordveld vooraf. Geef de voorkeur aan Sign in with Apple of een passkey boven eigen wachtwoorden. / TOETS: `SecureField` en `textContentType(.password)`; opmerking: Firebase e-mail plus wachtwoord is een bewuste keuze (README), maar de HIG ziet passkeys als betere optie (`[B:managing-accounts]`). `[B:managing-accounts, entering-data]`
- **ACT-5** REGEL: De Account-pagina (`person.crop.circle`, `[B:icons]`) bevat: wie ben ik (e-mail), synchronisatiestatus, wachtwoord wijzigen, uitloggen, account verwijderen. Alles wat met rekenen, koersen of gegevens te maken heeft staat daarbuiten. / TOETS: `AccountAndSyncSections` (in `SettingsView.swift:21`) is nu een sectie bovenaan de lange instellingenlijst; maak er een eigen pagina van. `[B:managing-accounts, icons]` / `[K]` (indeling)

### 2.20 Onboarding (ONB)

- **ONB-1** REGEL: Snel, optioneel en interactief; leer door te doen. / TOETS: geen verplichte uitlegtour; de eerste start toont meteen het Overzicht met een lege staat. `[B:onboarding]`
- **ONB-2** REGEL: Geef de voorkeur aan contextuele tips (TipKit) boven een lange onboarding. / TOETS: `import TipKit` (nu 0) voor tips als "Houd een blok ingedrukt om de volgorde te wijzigen". `[B:onboarding]`
- **ONB-3** REGEL: Bied de voorbeelddata aan op de plek van de lege staat ("Probeer met voorbeelddata"), niet verstopt in Instellingen. / TOETS: "Voorbeelddata laden" staat nu alleen in `SettingsView.swift:78` (README noemt Home). `[B:onboarding, writing]`
- **ONB-4** REGEL: Stel niet-essentiele setup uit en kies standaarden waarmee mensen direct kunnen beginnen. / TOETS: salaris, potten en beleggingen worden pas gevraagd als iemand die functie opent. `[B:onboarding]`
- **ONB-5** REGEL: Vraag toestemming (privacy) pas als de functie die nodig heeft. / TOETS: de app vraagt niets; houd dat zo. `[B:onboarding, privacy]`

### 2.21 Gegevens invoeren, tekstvelden, kiezers, stappers, schakelaars, segmenten

**Invoer (ENT)**

- **ENT-1** REGEL: Vraag zo weinig mogelijk, vul redelijke standaardwaarden vooraf in, en bied keuzes in plaats van typen. / TOETS: een formulier met meer dan vijf velden opsplitsen of onder "Meer opties" zetten. `[B:entering-data]`
- **ENT-2** REGEL: Een zichtbaar label per veld plus een placeholder met een voorbeeld; placeholder is niet het enige label (verdwijnt bij typen). / TOETS: `TextField("0", text:)` in `NumberRow` (`Fields.swift:48`) heeft een label ernaast (goed); vermijd velden met alleen een placeholder. `[B:text-fields, entering-data]`
- **ENT-3** REGEL: Numerieke velden: een nummertoetsenbord, locale-bewuste invoer (komma), directe validatie met de melding naast het veld. / TOETS: `NumberRow` zet `.decimalPad` achter `#if os(iOS)` (goed, `.keyboardType` bestaat niet op macOS); `range:` corrigeert direct. `[B:text-fields, entering-data]`
- **ENT-4** REGEL: Kies het juiste toetsenbord, een zinnige `submitLabel`, een logische focusvolgorde en sluit het toetsenbord bij scrollen (`.scrollDismissesKeyboard(.interactively)`, iOS 16/macOS 13). / TOETS: `@FocusState` aanwezig in `NumberRow`; `submitLabel(.next)` ontbreekt (`[K]`). `[B:text-fields]` `[A:swiftui/view/scrolldismisseskeyboard(_:)]`
- **ENT-5** REGEL: Verplichte velden: de bevestigknop pas actief als ze zijn ingevuld, met zichtbare reden. / TOETS: `.disabled(!isValid)` plus een regel "Vul een naam in" (`[K]`). `[B:entering-data]`
- **ENT-6** REGEL: Gevoelige invoer in een `SecureField`; nooit een wachtwoord vooraf invullen. / TOETS: `AuthView` (goed gebruikt volgens de grep op `SecureField`). `[B:entering-data, text-fields]`

**Kiezers en datums (PCK)**

- **PCK-1** REGEL: Een kiezer voor middellange lijsten; een korte lijst (tot ongeveer 5) als segmenten of menu; een zeer lange lijst als `List` met zoeken. / TOETS: 34 `Picker(`-aanroepen: stijl bewust gekozen (`.segmented` voor 2 tot 5, `.menu` voor langere). `[B:pickers, segmented-controls]`
- **PCK-2** REGEL: `DatePicker` compact bij beperkte ruimte; toon de kiezer in context, niet op een apart scherm. / TOETS: 5 `DatePicker`-plekken. `[B:pickers]`
- **PCK-3** REGEL: Een "dag van de maand" (1 tot 31) is geen datum: gebruik een `Picker(.menu)` of een stapper met veld. / TOETS: dag-velden (`MoneyLine.day`, `transferDay`) zijn getallen (goed); klem 1 tot 31 in het veld. `[K]`

**Stappers en schuifregelaars (STP)**

- **STP-1** REGEL: Een stapper staat naast het veld dat de waarde toont; combineer hem met een tekstveld bij grote waardenbereiken. / TOETS: 6 `Stepper`-plekken: elk met zichtbare waarde. `[B:steppers]`
- **STP-2** REGEL: Een schuifregelaar: minimum links (leading), maximum rechts; combineer hem met een tekstveld (en stapper) bij brede bereiken en toon de exacte waarde. / TOETS: 3 `Slider`-plekken tonen de waarde numeriek. `[B:sliders]`

**Schakelaars (TGL)**

- **TGL-1** REGEL: Gebruik de switch alleen in een lijstrij; buiten een lijst een knop die zich als schakelaar gedraagt. / TOETS: 17 `Toggle(`-aanroepen binnen `Form`/`List`. `[B:toggles]`
- **TGL-2** REGEL: Het verschil tussen aan en uit moet duidelijk zijn zonder alleen kleur. / TOETS: standaard `Toggle` voldoet; eigen toggles een vorm- of symboolverschil geven. `[B:toggles]`
- **TGL-3** REGEL: Het label zegt wat er gebeurt als het aan staat. / TOETS: "Koersen automatisch ophalen" (goed). `[B:writing, toggles]`

**Segmenten (SEG)**

- **SEG-1** REGEL: Een gesegmenteerde besturing voor nauw verwante keuzes of subweergaven (Maand, Half jaar, Jaar; 6 maanden, 1 jaar, 3 jaar); op iPhone hoogstens ongeveer 5 segmenten; alleen tekst of alleen pictogrammen; gelijke breedte; zelfstandig naamwoord als label; niet voor navigatie tussen secties (dat is de tabbalk). / TOETS: `Picker(...).pickerStyle(.segmented)` (aanwezig bij `PortfolioPages.swift:59-65`) met `.labelsHidden()`: geef de picker een toegankelijkheidslabel. `[B:segmented-controls]`

### 2.22 Knoppen (BTN)

- **BTN-1** REGEL: Een knop heeft een raakgebied van minstens 44x44 pt en een drukstatus; zonder drukstatus voelt hij dood. / TOETS: `ChipButton` met `minHeight: Theme.buttonHeight` (42) naar 44 (`Components.swift:296`); `.buttonStyle(.plain)` op `NavigationLink`/`Button` zonder eigen drukstatus (`LinkedBlock`, `Components.swift:116,120`): een `ButtonStyle` met `configuration.isPressed`. `[B:buttons]`
- **BTN-2** REGEL: Onderscheid de voorkeurskeuze met stijl, niet met grootte; een of twee prominente knoppen per scherm. / TOETS: `glassButton(prominent: true)` en `.borderedProminent` tellen per scherm; houd het bij een. `[B:buttons]`
- **BTN-3** REGEL: Gebruik de systeemknopstijlen (`.bordered`, `.borderedProminent`, op iOS 26 `.glass`/`.glassProminent`), `controlSize` en `buttonBorderShape`. / TOETS: eigen `ChipButton` (`Components.swift:304`) en `ChipGrid` vervangen door systeemstijlen met vaste hoogte. `[B:buttons, adopting-liquid-glass]`
- **BTN-4** REGEL: Geef de primaire rol aan de knop die mensen het waarschijnlijkst kiezen, nooit aan een destructieve knop. / TOETS: `role: .destructive` nooit prominent. `[B:buttons]`
- **BTN-5** REGEL: Label met een werkwoord, kort; een symbool als het duidelijk is; geen "Klik hier". / TOETS: "Toevoegen", "Bewaar", "Annuleer". `[B:buttons, writing]`
- **BTN-6** REGEL: Een knop kan een voortgangsindicator tonen voor een langzame actie. / TOETS: "Nu vernieuwen" doet dit (goed, `SettingsView.swift:38-46`); `.disabled` tijdens het werk. `[B:buttons]`
- **BTN-7** REGEL (macOS): een ellips in de titel als de knop om meer invoer vraagt ("Importeren…"); tooltips via `.help(...)`. / TOETS: `grep -rn "\.help(" App/` = 0. `[B:buttons, offering-help]`

### 2.23 Menu's (MNU)

- **MNU-1** REGEL: Menu-items beginnen met een werkwoord; een ellips (…) als er nog invoer nodig is; belangrijke items eerst; groepeer met scheidingen. / TOETS: "Bewerken", "Dupliceren", "Verwijderen" (destructief, laatst). `[B:menus]`
- **MNU-2** REGEL: Houd menu's kort; een submenu hoogstens een niveau diep en bij ongeveer 5 items of minder. / TOETS: geen geneste `Menu` in een `Menu`. `[B:menus]`
- **MNU-3** REGEL: Iconen in een menu voor alle items van een groep of voor geen enkele; gebruik de standaardsymbolen voor standaardacties. / TOETS: `Label("...", systemImage:)` consequent. `[B:menus]`
- **MNU-4** REGEL: Een menu voor commando's die iemand zelf opent, een action sheet voor keuzes bij een bewuste actie. / TOETS: zie DLG-1. `[B:action-sheets, menus]`
- **MNU-5** REGEL: Hoofdlettergebruik consequent; voor het Nederlands zinshoofdletter (alleen het eerste woord), zoals de systeem-apps. / TOETS: "Volgorde aanpassen" (goed); "Wis alle gegevens" (goed); afwijkingen opsporen. `[B:writing]` (kies een stijl en houd die vast) / `[K]` (zinshoofdletter voor NL; de HIG beschrijft Engelse titel-hoofdletters)

### 2.24 Verversen en laden (RFR/LOD)

- **RFR-1** REGEL: Trek-om-te-verversen (`.refreshable`) op scrollende lijsten met gegevens die kunnen verversen; en ververs ook automatisch; geef een titel alleen als die iets toevoegt (bijvoorbeeld wanneer het laatst). / TOETS: `grep -rn "refreshable" App/` (1: `PortfolioPages.swift:96`): ook op Home en de koersgevoelige pagina's (belegging-detail); de koersen worden al bij openen opgehaald. `[B:progress-indicators]`
- **RFR-2** REGEL: Toon de status "laatst bijgewerkt" in de context, niet als pop-up. / TOETS: `priceStatus` (`PortfolioPages.swift:102`) doet dat (goed). `[B:feedback, progress-indicators]`
- **LOD-1** REGEL: Toon zo snel mogelijk iets (gecachte gegevens, placeholders) en laad op de achtergrond; blokkeer de interface niet. / TOETS: `.redacted(reason: .placeholder)` (nu 0) tijdens de eerste koersen; geen schermvullende spinner. `[B:loading]`
- **LOD-2** REGEL: Een determinate voortgangsindicator als de duur bekend is (`ProgressView(value:total:)`), een spinner als die onbekend is; wissel niet van spinner naar balk; bied annuleren aan bij lange acties. / TOETS: de import in `BackupUI.swift`: `ProgressView(value:)` (nu 0) en een Annuleer-knop. `[B:progress-indicators]`
- **LOD-3** REGEL: Beschrijf de voortgang concreet ("Koersen ophalen…"), niet "Laden". / TOETS: `PortfolioPages.swift:107` (goed). `[B:progress-indicators]`
- **LOD-4** REGEL: Een storing bij ophalen is een inline melding (`NoticeBanner`, 4 plekken), geen alert. / TOETS: `store.priceMessage`. `[B:alerts, feedback]`

### 2.25 Lege staten (EMP)

- **EMP-1** REGEL: Een lege staat gebruikt `ContentUnavailableView` (iOS 17/macOS 14) met een label, een beschrijving en een actieknop; `ContentUnavailableView.search` voor "geen resultaten". Apple raadt hem aan voor "een netwerkfout, een lijst zonder items, een zoekopdracht zonder resultaat". / TOETS: `grep -rn "ContentUnavailableView" App/` = 0; de eigen `EmptyHint` (14 plekken) is ofwel een dunne wrapper om `ContentUnavailableView` ofwel vervangen. `[A:swiftui/contentunavailableview]` `[B:writing]`
- **EMP-2** REGEL: Geef op een leeg scherm een duidelijke volgende stap met een knop of link; toon geen cruciale informatie die later verdwijnt. / TOETS: elke `EmptyHint` heeft `actionTitle` (`PortfolioPages.swift:31-33` goed). `[B:writing]`
- **EMP-3** REGEL: Is een tab-sectie leeg, laat de tab staan en leg uit waarom. / TOETS: geen tab die verdwijnt als er geen potten zijn. `[B:tab-bars]`
- **EMP-4** REGEL: Een grafiek zonder gegevens is een lege staat, geen lege assen (zie CHT-7). / TOETS: elke chartview begint met een `guard`/`if` naar `ContentUnavailableView`. `[B:charts]` / `[K]`
- **EMP-5** REGEL: Een foutstaat (geen verbinding) krijgt een knop "Probeer opnieuw". / TOETS: `ContentUnavailableView` met `actions:`. `[A:swiftui/contentunavailableview]`

### 2.26 Zoeken (SRC)

- **SRC-1** REGEL: Als zoeken belangrijk is, geef het een prominente plek; zoek op een enkele plek in de hele app; plaats het veld naast de inhoud die het doorzoekt. / TOETS: het eenvoudiger terugvinden van onderdelen (opdracht van de gebruiker) kan met `.searchable(text:)` op de lijsten van potten, beleggingen en regels; globale zoekfunctie later. `[B:searching, search-fields]`
- **SRC-2** REGEL: iOS: zoeken als eigen tab (`Tab(role: .search)`) of in de toolbar, bij voorkeur onderaan als er ruimte is; iPad/Mac: rechts in de toolbar of bovenaan de sidebar. / TOETS: kies een plek per platform en houd iPad en Mac gelijk. `[B:search-fields]` `[A:swiftui/tabrole/search]`
- **SRC-3** REGEL: Geef zoekresultaten het meest relevante eerst, toon een placeholder die zegt waarin gezocht wordt, en bij geen resultaten `ContentUnavailableView.search`. / TOETS: `prompt:` in `.searchable`; `.overlay` met `ContentUnavailableView.search`. `[B:search-fields, searching]` `[A:swiftui/contentunavailableview/search]`

### 2.27 Feedback en haptiek (FDB)

- **FDB-1** REGEL: Laat de opdringerigheid van de feedback passen bij het belang: status passief in de interface; alleen een waarschuwing met verlies-risico onderbreekt. / TOETS: een opgeslagen wijziging krijgt geen alert; een fout bij opslaan (`store.saveFailed`) is een zichtbare inline melding. `[B:feedback]`
- **FDB-2** REGEL: Bevestig belangrijke voltooide acties (opslaan, import, overschrijving), niet de routine. / TOETS: import klaar: een samenvatting; toevoegen van een regel: de rij verschijnt (animatie volstaat). `[B:feedback]`
- **FDB-3** REGEL: Toon waarom een opdracht niet kan en wat te doen; schakel een knop niet zonder reden uit. / TOETS: bij `.disabled` een uitleg ernaast. `[B:feedback, entering-data]`
- **FDB-4** REGEL: Haptiek met `sensoryFeedback(_:trigger:)` (iOS 17/macOS 14) alleen bij discrete gebeurtenissen, consequent van betekenis (`.success` = gelukt, `.error` = mislukt, `.warning` = let op, `.selection` = keuze, `.impact` = fysieke metafoor), kort, nooit als enige feedback, niet overdrijven. Standaardcontrols spelen al haptiek. / TOETS: `grep -rn "sensoryFeedback" App/` = 0. Aanwijzingen: opslaan gelukt `.success`, validatiefout `.error`, onder nul in de bankplanning `.warning`, periode wisselen `.selection`. `[B:playing-haptics]` `[A:swiftui/view/sensoryfeedback(_:trigger:)]`
- **FDB-5** REGEL: Haptiek moet te dempen zijn; de systeeminstelling geldt. / TOETS: geen eigen aan/uit; `sensoryFeedback` respecteert de systeeminstelling (`[K]`). `[B:playing-haptics]`
- **FDB-6** REGEL: Feedback toegankelijk: kleur plus tekst plus (waar mogelijk) haptiek; niet alleen geluid of alleen kleur. / TOETS: zie COL-4. `[B:feedback]`

### 2.28 iPadOS (IPD)

- **IPD-1** REGEL: Benut het grote scherm: inhoud omhoog halen, minder modaal en minder schermovergangen, bediening op bereikbare plekken. / TOETS: bewerken in een inspector of detailkolom (`.inspector`, iOS 17) in plaats van een sheet waar dat past. `[B:designing-for-ipados, sheets]`
- **IPD-2** REGEL: Gebruik de adaptieve tabbalk (bovenbalk die een sidebar kan worden) of een `NavigationSplitView`. / TOETS: zie TAB-5. `[B:tab-bars]`
- **IPD-3** REGEL: Werk in elke venstergrootte en multitasking-stand (Slide Over, Split View, Stage Manager, aanpasbare vensters); maak geen aannames over oriëntatie; bewaar en herstel de context. / TOETS: `project.yml` laat op iPad alle oriëntaties toe (goed); test op het kleinste en grootste venster. `[B:multitasking, layout, windows]`
- **IPD-4** REGEL: Sheets in de formulier- of paginastijl (`presentationSizing(.form)`). / TOETS: zie SHT-7. `[B:sheets]`
- **IPD-5** REGEL: Eigen elementen die zich als standaardcontrols gedragen krijgen de standaard pointer-effecten (`hoverEffect`, alleen iOS), geen decoratieve effecten. / TOETS: `grep -rn "hoverEffect" App/` = 0: de `.buttonStyle(.plain)`-blokken en eigen chips krijgen `.hoverEffect(.highlight)` (achter `#if os(iOS)`; bestaat niet op macOS). `[B:pointing-devices]` `[A:swiftui/view/hovereffect(_:isenabled:)]`
- **IPD-6** REGEL: Ondersteun het toetsenbord: sneltoetsen voor veelgebruikte acties, de menubalk van iPadOS, Full Keyboard Access; herdefinieer geen standaardsneltoetsen. / TOETS: zie MAC-2 en MAC-5. `[B:keyboards, the-menu-bar]`
- **IPD-7** REGEL: Contextmenu via lang indrukken en secundair klikken; ook op iPad voor "nieuw maken". / TOETS: `contextMenu` (zie LST-8). `[B:context-menus]`

### 2.29 macOS (MAC)

- **MAC-1** REGEL: Laat mensen het venster verkleinen, vergroten en verplaatsen; stel een minimumgrootte in. Een enkel venster (`Window`) is toegestaan als er een reden is (hier: een store per gegevensbestand, `MyBuddyApp.swift:22-24`). / TOETS: `Window("MyBuddy", id: "main")` met `.defaultSize` (`MyBuddyApp.swift:27`) en een `.frame(minWidth: 480, minHeight: 640)` op de inhoud (`:39`) is aanwezig; `windowResizability` is niet gezet (controleer op de Mac dat het venster niet kleiner kan dan dat minimum, `[K]`); zorg dat de titel de sectie noemt (NAV-3). `[B:windows, designing-for-macos]`
- **MAC-2** REGEL: Plaats alle commando's in de menubalk; ondersteun de standaardmenu's (App, Archief, Bewerken, Weergave, Venster, Help) en zet app-eigen commando's in een eigen menu; "Instellingen…" staat in het App-menu. / TOETS: `grep -rn "\.commands\|CommandMenu\|CommandGroup" App/` = 0: voeg toe: `CommandGroup(replacing: .newItem)` (Nieuwe regel, Cmd+N), `CommandMenu("Gegevens")` (Importeren, Exporteren), Weergave-items per tab (Cmd+1/2/3). `[B:the-menu-bar, designing-for-macos]`
- **MAC-3** REGEL: Instellingen via de `Settings`-scene; Cmd+komma werkt dan vanzelf. / TOETS: zie SET-4 en SET-5. `[B:settings]` `[A:swiftui/settings]`
- **MAC-4** REGEL: Navigatie als sidebar (niet als onderbalk), geen kritieke elementen onderaan het venster of de sidebar. / TOETS: zie TAB-5, LAY-8, SID-4. `[B:sidebars, layout]` `[A:swiftui/tabviewstyle/sidebaradaptable]`
- **MAC-5** REGEL: Respecteer de standaard sneltoetsen en herdefinieer ze niet (Cmd+W, Cmd+Z, Cmd+F, Cmd+komma, Ctrl+Cmd+F); ondersteun Ongedaan maken in het Bewerken-menu. / TOETS: `keyboardShortcut` (nu 0) alleen voor eigen acties; `UndoManager` voor bewerkingen. `[B:keyboards, undo-and-redo]`
- **MAC-6** REGEL: Tooltips voor knoppen die alleen een symbool hebben (`.help("...")`), kort (60 tot 75 tekens) en zonder de naam te herhalen. / TOETS: `.help(` = 0. `[B:offering-help, buttons]`
- **MAC-7** REGEL: Controls (schakelaars, selectievakjes) in de vensterinhoud, niet in het venster-frame (toolbar of statusbalk). / TOETS: geen `Toggle` in een `ToolbarItem`. `[B:toggles]`
- **MAC-8** REGEL: Volledig scherm via het systeem (Weergave-menu, Ctrl+Cmd+F); verberg of herstel de toolbar niet zelf. / TOETS: geen eigen "volledig scherm"-knop. `[B:going-full-screen]`
- **MAC-9** REGEL: macOS heeft geen Dynamic Type; gebruik wel tekststijlen (13 pt body) en pas bedieningselementen aan op `controlSize(.regular)`. / TOETS: zie TYP-4. `[B:typography]`

### 2.30 Privacy (PRV)

- **PRV-1** REGEL: Vraag alleen toegang tot gegevens die je echt nodig hebt, en pas als de functie erom vraagt. / TOETS: geen `NS*UsageDescription` in de Info.plist-keys van `project.yml` (goed). `[B:privacy, onboarding]`
- **PRV-2** REGEL: Wees transparant over wat de app met gegevens doet: koersen via Yahoo Finance, Stooq en CoinGecko (er gaan tickers naar buiten), synchronisatie via Firebase (financiele gegevens naar de cloud), ECB voor inflatie. / TOETS: een korte privacy-uitleg bij "Over" en bij de Account-pagina; de App Store-privacygegevens kloppen met die lijst. `[B:privacy]`
- **PRV-3** REGEL: Verwerk gegevens liefst op het apparaat; cloud is een keuze. / TOETS: de standaard is lokaal (goed, README). `[B:privacy]`
- **PRV-4** REGEL: Bewaar geheimen in de Keychain (`KeychainSecretStore`, goed) en gebruik `SecureField` voor wachtwoorden. / TOETS: geen wachtwoord in `UserDefaults` of logbestand. `[B:privacy, entering-data]`
- **PRV-5** REGEL: Optioneel: maak bedragen onzichtbaar in schermopnames of vergrendelde widgets met `.privacySensitive()`. / TOETS: `[K]`; geen HIG-regel, wel passend bij een geldapp. `[K]`

### 2.31 Schrijven in het Nederlands (WRT)

- **WRT-1** REGEL: Duidelijk, kort, actief; knoppen en links met een werkwoord; "tik" op een touchscreen en "klik" met de muis; geen "Klik hier". / TOETS: `grep -rn "Klik\|klik\|Tik\|tik" App/` en kijk of de tekst bij het platform past (op de Mac "klik"). `[B:writing]`
- **WRT-2** REGEL: Een woord per begrip, in de hele app: spaarpot, belegging, doel, blok, bank. Stel een termenlijst op. / TOETS: `Portefeuille` komt nog voor naast `Beleggingen`; "Savings", "Tools", "Home" staan in een Nederlandse app. `[B:writing]`
- **WRT-3** REGEL: Kies per soort element een hoofdletterstijl en houd die vast; voor het Nederlands zinshoofdletter. / TOETS: zie MNU-5. `[B:writing]` / `[K]`
- **WRT-4** REGEL: Gebruik bezittelijke voornaamwoorden spaarzaam ("Beleggingen", niet "Mijn beleggingen"); en nooit "wij". / TOETS: `PortfolioPages.swift:84` "Mijn beleggingen"; "je" in lopende tekst mag, maar niet wisselen van perspectief. `[B:writing]` (bijgewerkt 16 december 2025)
- **WRT-5** REGEL: Voor lege schermen een volgende stap met knop. / TOETS: zie EMP-2. `[B:writing]`
- **WRT-6** REGEL: Foutmeldingen dichtbij het probleem, zonder blaam, en zeg wat te doen ("Kies een bedrag van 0 tot 100 procent", niet "Ongeldige invoer"); geen "Oeps". / TOETS: foutteksten in `Core` en `Pages` nalopen. `[B:writing]`
- **WRT-7** REGEL: Instellinglabels praktisch; beschrijf wat het doet als het aan staat. / TOETS: zie SET-7. `[B:writing]`
- **WRT-8** REGEL: Schrijf voor iedereen: eenvoudige taal, financiele termen uitleggen (opnamepercentage, rendement). / TOETS: elke term die een gewone gebruiker niet kent heeft een `footnote`-uitleg. `[B:writing]`
- **WRT-9** REGEL: Datums en getallen ondubbelzinnig, zeker in toegankelijkheidslabels ("6 juni", niet "6/6"; "60 minuten", niet "60m"). / TOETS: `Fmt.date`, `Fmt.euro` en de labels van de grafieken. `[B:charts]`

### 2.32 Vereenvoudigen volgens de HIG (SIM)

De opdracht van de gebruiker om de app eenvoudiger en beter te doorzoeken te maken heeft in de HIG deze steun:

- **SIM-1** REGEL: Beperk het aantal bedieningselementen op het scherm en maak bijzaken vindbaar met een minimum aan interactie. / TOETS: per scherm hooguit een primaire actie; secundaire acties in het "Meer"-menu of een niveau dieper. `[B:designing-for-ios, toolbars]`
- **SIM-2** REGEL: Een interface met te veel inhoud en keuzes maakt het moeilijker om iets te vinden; gebruik progressive disclosure (disclosure-driehoeken, menu's, geneste weergaven, scrollbare secties). / TOETS: zie LAY-2. `[B:layout, disclosure-controls]`
- **SIM-3** REGEL: Minder niveaus op grote schermen. / TOETS: zie NAV-4. `[B:designing-for-macos]`
- **SIM-4** REGEL: Minimaliseer het aantal instellingen. / TOETS: zie SET-2. `[B:settings]`
- **SIM-5** REGEL: Houd modale taken eenvoudig en breek taken met meerdere stappen op in een interactie per scherm. / TOETS: de stappen van de Aankoopcheck (`PurchasePages.swift:131`, "Stap n van m") zijn goed. `[B:modality, accessibility]` (Assistive Access)
- **SIM-6** REGEL: Een duidelijke navigatiehierarchie, gescheiden van de inhoud, en een manier om te zoeken waar de inhoud groot wordt. / TOETS: zie NAV-5 en SRC-1. `[B:adopting-liquid-glass, searching]`

---

## 3. Tabel: HIG-regel naar SwiftUI-implementatie

De deployment targets zijn iOS 18 en macOS 15. Alles met "min. OS" tot en met iOS 18/macOS 15 mag zonder `#available`; alleen iOS 26-API's hebben een terugval nodig. `(A)` = versie gecontroleerd in Apple's documentatie-JSON op 15 oktober 2026; `(K)` = uit kennis.

| HIG-regel | SwiftUI-implementatie | Min. OS | Terugval iOS 18 / macOS 15 |
|---|---|---|---|
| Dynamic Type, tekststijlen | `.font(.body)`, `.headline`, `.title2` in plaats van `.font(.system(size:))`; `@ScaledMetric` voor maten | `ScaledMetric` iOS 14/macOS 11 (A) | n.v.t. |
| Layout bij grote tekst | `@Environment(\.dynamicTypeSize)` + `.isAccessibilitySize`; `ViewThatFits`; `AnyLayout`; `.dynamicTypeSize(...DynamicTypeSize.accessibility3)` om te begrenzen | iOS 15/macOS 12; `ViewThatFits`, `AnyLayout` iOS 16/macOS 13 (A) | n.v.t. |
| Marges, leesbare breedte | `.scenePadding()`, `.contentMargins(_:_:for:)`, `.safeAreaPadding`, `.frame(maxWidth:)` | `scenePadding` iOS 15; `contentMargins`, `safeAreaPadding` iOS 17/macOS 14 (A) | n.v.t. |
| Layout op size class | `@Environment(\.horizontalSizeClass)`, `LazyVGrid(columns: [.adaptive(...)])` | iOS 13 (A) | n.v.t. |
| Native tabbalk, sidebar | `TabView { Tab("Naam", systemImage: "...") { ... } }` + `.tabViewStyle(.sidebarAdaptable)` | `Tab`, `sidebarAdaptable` iOS 18/macOS 15 (A) | n.v.t. (precies de ondergrens); iOS 26 voegt het glas toe |
| Tabbalk minimaliseren, accessoire | `.tabBarMinimizeBehavior(.onScrollDown)`, `.tabViewBottomAccessory { }` | iOS 26 (A) | weglaten achter `#available(iOS 26, *)` |
| Zoek-tab | `Tab(role: .search) { }` | iOS 18/macOS 15 (A) | n.v.t. |
| Grote titel | `.toolbarTitleDisplayMode(.large)`; (`navigationBarTitleDisplayMode(.large)` bestaat niet op macOS) | `toolbarTitleDisplayMode` iOS 17/macOS 14 (A); `navigationBarTitleDisplayMode` iOS 14, niet macOS (A) | n.v.t. |
| Hierarchische navigatie | `NavigationStack`, `NavigationLink(value:)`, `.navigationDestination(for:)`, `NavigationPath` | iOS 16/macOS 13 (A) | n.v.t. |
| Sidebar met detail | `NavigationSplitView` | iOS 16/macOS 13 (A) | n.v.t. |
| Subtitel in de balk | `.navigationSubtitle("...")` | macOS 13; iOS 26 (A) | op iOS 18 weglaten (`#if os(macOS)` of `#available`) |
| Annuleer links, Klaar rechts | `ToolbarItem(placement: .cancellationAction)` / `.confirmationAction` / `.primaryAction` | iOS 14/macOS 11 (A) | n.v.t. |
| Prominente actie | `Button(role: .confirm)`, `Button(role: .close)`, of `.buttonStyle(.borderedProminent)` | `.confirm`/`.close` iOS 26/macOS 26 (A); `borderedProminent` iOS 15 (K) | `.borderedProminent` |
| Toolbar-groepen scheiden | `ToolbarSpacer(.fixed)`, `.sharedBackgroundVisibility(.hidden)` | iOS 26/macOS 26 (A) | weglaten |
| Sheet | `.sheet(item:)`, `.presentationDetents([.medium, .large])`, `.presentationDragIndicator(.visible)`, `.presentationSizing(.form)`, `.interactiveDismissDisabled(_:)` | detents iOS 16/macOS 13; `presentationSizing` iOS 18/macOS 15; `interactiveDismissDisabled` iOS 15 (A) | n.v.t. |
| Eigen sheetachtergrond (vermijden) | `.presentationBackground`, `.presentationCornerRadius` | iOS 16.4/macOS 13.3 (A) | n.v.t. |
| Volledig scherm | `.fullScreenCover` (niet op macOS) | iOS 14 (A) | op macOS een sheet of venster |
| Alert, bevestiging | `.alert(_:isPresented:actions:message:)`, `.confirmationDialog(...)` met `role: .destructive` | iOS 16/macOS 13 (A, dit overload); eerdere overloads iOS 15 (K) | n.v.t. |
| Lijsten, formulieren | `List`, `Form` + `.formStyle(.grouped)`, `Section("Titel")`, `LabeledContent` | `formStyle`, `LabeledContent` iOS 16/macOS 13 (A) | n.v.t. |
| Swipe-acties, contextmenu | `.swipeActions(edge:allowsFullSwipe:content:)`, `.contextMenu { }` | `swipeActions` iOS 15/macOS 12 (A); `contextMenu` iOS 13 (A) | n.v.t. |
| Lege staat | `ContentUnavailableView("Titel", systemImage: "...", description: Text("..."))`, `ContentUnavailableView.search` | iOS 17/macOS 14 (A) | n.v.t. |
| Trek om te verversen | `.refreshable { await ... }` | iOS 15/macOS 12 (A) | n.v.t. |
| Haptiek | `.sensoryFeedback(.success, trigger: waarde)`; `.selection`, `.warning`, `.error`, `.impact` | iOS 17/macOS 14 (A) | n.v.t. |
| Verlaag beweging | `@Environment(\.accessibilityReduceMotion)` | iOS 13/macOS 10.15 (A) | n.v.t. |
| Verlaag transparantie, hoog contrast, onderscheid zonder kleur | `\.accessibilityReduceTransparency`, `\.colorSchemeContrast`, `\.accessibilityDifferentiateWithoutColor` | iOS 13/macOS 10.15 (A) | n.v.t. |
| VoiceOver | `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint`, `.accessibilityElement(children: .combine)`, `.accessibilityAddTraits(.isHeader)`, `.accessibilityHeading`, `.accessibilityHidden`, `.accessibilityInputLabels` | label/value iOS 16/macOS 13; `isHeader` iOS 14; `accessibilityHeading` iOS 15 (A) | n.v.t. |
| Raakdoel 44 pt | `.frame(minWidth: 44, minHeight: 44)`, `.contentShape(Rectangle())`, `.accessibilityShowsLargeContentViewer()` | iOS 15 voor large content viewer (A) | n.v.t. |
| Grafiek | `Chart { LineMark/BarMark/AreaMark/PointMark/RuleMark }`; `SectorMark` voor donut | `Chart` iOS 16/macOS 13; `SectorMark` iOS 17/macOS 14 (A) | donut op iOS 16: staafgrafiek |
| Grafiek-toegankelijkheid | `ChartContent.accessibilityLabel/.accessibilityValue`; `.accessibilityChartDescriptor(_:)` met `AXChartDescriptorRepresentable` | iOS 15/macOS 12 (A); label/value op `ChartContent` iOS 16 (A) | n.v.t. |
| Grafiek-interactie | `.chartXSelection(value:)`, `.chartScrollableAxes`, `.chartXVisibleDomain(length:)` | iOS 17/macOS 14 (A) | op iOS 16: `.chartOverlay` met `DragGesture` |
| Grafiek zonder alleen kleur | `.symbol(by:)`, `.lineStyle(by:)`, `.foregroundStyle(by:)`, `.chartForegroundStyleScale` | iOS 16/macOS 13 (A) | n.v.t. |
| Grafiekassen | `.chartYScale(domain: .automatic(includesZero:))`, `.chartYAxis { AxisMarks }`, `.chartLegend` | iOS 16/macOS 13 (A) | n.v.t. |
| Instellingen (macOS) | `Settings { TabView { Tab(...) } }` in `#if os(macOS)`; `SettingsLink`, `openSettings` | `Settings` macOS 11; `SettingsLink`, `openSettings` macOS 14 (A) | iOS: een pagina op de `NavigationStack` |
| Menubalk, sneltoetsen | `.commands { CommandMenu("..."), CommandGroup(...) }`, `.keyboardShortcut(",", modifiers: .command)` | iOS 14/macOS 11 (A) | n.v.t. |
| Tooltips (macOS) | `.help("...")` | macOS 11 (K) | n.v.t. |
| Pointer (iPad) | `.hoverEffect(.highlight)` (niet op macOS) | iOS 17 voor `hoverEffect(_:isEnabled:)` (A) | `#if os(iOS)` |
| Liquid Glass op custom bediening | `.glassEffect(.regular, in: shape)`, `GlassEffectContainer`, `.glassEffectID(_:in:)` | iOS 26/macOS 26 (A) | `.background(.regularMaterial, in: shape)` (app heeft `glassSurface`) |
| Glasknoppen | `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)` | iOS 26/macOS 26 (A) | `.bordered`, `.borderedProminent` (app heeft `glassButton`) |
| Scroll-edge, achtergrond doortrekken | `.scrollEdgeEffectStyle(_:for:)`, `.backgroundExtensionEffect()` | iOS 26/macOS 26 (A) | weglaten |
| Concentrische vormen | `ConcentricRectangle`, `.containerShape(_:)` | iOS 26/macOS 26 (A) | `RoundedRectangle(cornerRadius: parent - inset)` (`Theme.tileRadius`) |
| Standaardmaterialen | `.ultraThinMaterial` ... `.thickMaterial`, `.bar` | iOS 15/macOS 12 (K) | n.v.t. |
| Invoer | `TextField(value:format:)`, `.keyboardType` (niet op macOS), `.submitLabel`, `@FocusState`, `.scrollDismissesKeyboard`, `SecureField` | `submitLabel`, `FocusState` iOS 15/macOS 12; `scrollDismissesKeyboard` iOS 16/macOS 13; `keyboardType` alleen iOS (A) | `#if os(iOS)` voor `keyboardType` |
| Stepper, picker, schakelaar, segmenten | `Stepper`, `Picker` (`.menu`, `.segmented`), `DatePicker`, `Toggle`, `Slider` | iOS 13/macOS 10.15 (A) | n.v.t. |
| Knoppen | `.buttonStyle(.bordered/.borderedProminent)`, `.controlSize`, `.buttonBorderShape`, eigen `ButtonStyle` met `configuration.isPressed` | iOS 15/macOS 12 (A) | n.v.t. |
| Voortgang | `ProgressView(value:total:)`, `Gauge` | iOS 14/macOS 11; `Gauge` iOS 16/macOS 13 (A) | n.v.t. |
| Getallen | `.monospacedDigit()`, `.contentTransition(.numericText())` | iOS 15 / iOS 16 (A) | n.v.t. |
| Progressive disclosure | `DisclosureGroup`, `Menu`, `NavigationLink` | iOS 14/macOS 11 (A) | n.v.t. |
| Symbolen | `Label`, `.symbolVariant(.fill)`, `.symbolRenderingMode`, `.symbolEffect` | `symbolEffect` iOS 17/macOS 14 (A) | n.v.t. |
| Tips | TipKit (`TipView`, `.popoverTip`) | iOS 17/macOS 14 (K) | n.v.t. |
| Delen/exporteren | `ShareLink`, `.fileExporter` | `ShareLink` iOS 16/macOS 13 (A) | n.v.t. |
| Privacy | `.privacySensitive()` | iOS 15 (K) | n.v.t. |
| Ongedaan maken | `@Environment(\.undoManager)` | iOS 13/macOS 10.15 (K) | n.v.t. |
| Detail naast hoofdscherm op groot scherm | `.inspector(isPresented:content:)` | iOS 17/macOS 14 (A) | n.v.t. |
| Venster (macOS) | `Window`, `WindowGroup`, `.defaultSize`, `.windowResizability` | `windowResizability` macOS 13 (A) | n.v.t. |

---

## 4. Eerste meting in de code (informatief, geen opdracht tot aanpassen in deze fase)

Peildatum 15 oktober 2026. Een ander herstelwerk wijzigt tegelijk bestanden in `App/`; regelnummers kunnen dus verschuiven.

| Onderwerp | Meting | Plek |
|---|---|---|
| Glas in de inhoudslaag | 92 `GlassBlock(`- en 12 `LinkedBlock(`-aanroepen, elk een `glassCard` | `Components.swift:48-70` |
| Eigen tabbalk | `GlassTabBar` met eigen achtergrond (`.fill(.bar)`), verbergt bij toetsenbord, onderaan ook op macOS; 0 `TabView` | `RootView.swift:18-24, 86-148` |
| Navigatiepad wordt gewist bij tabwissel | `select` zet het pad van de nieuwe tab leeg | `Router.swift:66-73` |
| Tabnamen Engels | "Home", "Savings", "Tools" | `Router.swift:8-14` |
| Instellingen als sheet | `.sheet(isPresented: $router.showSettings)`; geen `Settings`-scene; geen `.commands` | `RootView.swift:26`, `Router.swift:57`, `Components.swift:38`, `MyBuddyApp.swift:20-32` |
| Sheet vanuit sheet | wachtwoord- en verwijdersheets vanuit Instellingen | `CloudViews.swift:115-116`, `AuthView.swift:636-637` |
| Account niet apart | `AccountAndSyncSections` is de eerste sectie in de lange instellingenlijst | `SettingsView.swift:21` |
| Vaste lettergroottes | 5 plekken | `RootView.swift:101`, `Components.swift:239`, `HomeView.swift:328`, `PurchasePages.swift:516,631` |
| Dynamic Type niet beheerd | 0 `isAccessibilitySize`, 0 `ScaledMetric`, 0 `dynamicTypeSize`, 49 `minimumScaleFactor` | app-breed |
| Beweging | 0 `accessibilityReduceMotion`, 0 `accessibilityReduceTransparency`; paginabrede animaties | `Components.swift:23-25`, `RootView.swift:64-67` |
| Haptiek | 0 `sensoryFeedback` | app-breed |
| Raakdoel | `Theme.buttonHeight = 42` | `Theme.swift:39` |
| Sectiekoppen in hoofdletters | `SectionLabel` met `uppercased()` | `Components.swift:137` |
| Swipe-acties, tooltips, hover | 0 `swipeActions`, 0 `.help(`, 0 `hoverEffect` | app-breed |
| Lege staten | 0 `ContentUnavailableView`; 14 `EmptyHint` | app-breed |
| Contrast (tekstkleuren licht) | `warning` 2,5 tot 3,4:1; `negative` 3,3 tot 4,5:1; `accent` 3,7 tot 5,0:1 | `Theme.swift:60-63`; meting in 2.3 |
| Kleurenblindheid | `flowExpenses`/`flowSaved` (deuteranopie) en `palette[0]`/`[3]` vrijwel gelijk | `Theme.swift:66-82`; meting in COL-7 |
| Grafiek-toegankelijkheid | 8 grafiekviews; 2 samenvattende labels (`BufferChart`, `DayBalanceChart`); 0 `accessibilityChartDescriptor`; 0 labels per mark | `BufferPages.swift:526`, `CashflowPages.swift:315` |
| Grafiekbereik | `floorValue...ceilingValue` en `0...topValue` zijn veilig door `pad >= 50` en `topValue >= 1,05`; alleen NaN zou crashen (geen `isFinite`-controle) | `CashflowPages.swift:261-264, 303`, `BufferPages.swift:498-512` |
| Grafiek Beleggingen | "Groei" verschijnt alleen bij `series.count > 1`, anders een voetnoot. `portfolioSeries` slaat maanden zonder meetpunt over; een gevolgde belegging krijgt bij toevoegen geen beginwaarde (`initial` is nil) en heeft dus geen punt tot `refreshPrices` slaagt; een handmatige belegging met waarde 0 ook niet. Gereproduceerd met `/tmp/hig-probe` (`portfolioSeries` tegen `App/Core`): zonder meetpunt 0 punten, met een beginwaarde of een eerste koers 13 (1 werkelijk, 12 verwacht). De voetnoot zegt dan ten onrechte "zodra er meer meetpunten zijn" | `PortfolioPages.swift:20, 66-75, 705-707`, `Invest.swift:152-170`, `Charts.swift:58-95` |
| Grafiekkleur per positie | `AllocationDonut` kleurt met `Theme.color(index)` terwijl de sectoren op waarde zijn gesorteerd: een soort wisselt van kleur als de volgorde wisselt | `Charts.swift:158-159` |
| Contextmenu als enige ingang | "Volgorde aanpassen" alleen via lang indrukken | `BlockOrder.swift` |
| Bezittelijk voornaamwoord | "Mijn beleggingen" | `PortfolioPages.swift:84` |
| Al goed | `Fmt` met locale; `#if os(iOS)` om `keyboardType`; `#available(iOS 26, macOS 26)` in `Glass.swift`; `confirmationDialog` met `role: .destructive`; concentrische radii (`Theme.tileRadius`); `Window` voor een venster op macOS; geen `preferredColorScheme`; Keychain voor geheimen | respectievelijk |

---

## 5. Onzekerheden

1. De HIG-tekst is van 15 oktober 2026 en bevat changelogs tot 9 september 2026 (nieuwer dan iOS 26.0). Waar een regel is bijgewerkt (sheet-knoppen, 24 maart 2026; sidebar en menu's, 8 juni 2026), sluit de tekst aan op de huidige richtlijn. De API-versies controleer je in Xcode 26.
2. De contrastcijfers zijn berekend tegen de negen mesh-kleuren uit `Theme.swift`, zonder glaslaag, vibrancy of systeemlabelkleuren (`.secondary` e.d.). De werkelijke waarden liggen anders; controleer met de Accessibility Inspector.
3. De kleurenblindheidsmeting gebruikt een Machado-simulatie en deltaE76 (grof: onder 15 is lastig). Dat is een indicatie, geen norm. De WCAG 1.4.11-drempel van 3:1 voor grafische delen staat niet in de HIG (`[K]`).
4. `TabView` met `Tab` en `.sidebarAdaptable` gedraagt zich volgens Apple per platform verschillend (iPhone onderbalk, iPad bovenbalk, Mac sidebar); of elk tab-pad en alle `NavigationStack`-gedrag in de bestaande `Router` daarmee probleemloos blijft werken, kan hier niet worden getest (SwiftUI compileert hier niet).
5. `confirmationDialog` op iPad/macOS verankeren aan een knop en `presentationSizing(.form)` hangen af van gedrag op een echt apparaat.
6. Nederlandse hoofdlettergebruik: de HIG beschrijft titel-hoofdletters voor het Engels; de zinshoofdletter voor het Nederlands (Apple's eigen NL-interface) is `[K]`.
7. Welke SF Symbols-namen nieuw zijn in SF Symbols 7 (zoals `document.on.document` uit de HIG-tabel) heb ik niet kunnen nagaan zonder de SF Symbols-app; houd voor iOS 18 de oude namen aan.
8. Voor de grafiek bij Beleggingen: de oorzaak "geen meetpunt, dus geen punten, dus alleen een voetnoot" is met `/tmp/hig-probe` gereproduceerd op `portfolioSeries` (Core), maar dat bewijst niet dat het de enige oorzaak is: of de gebruiker een belegging zonder meetpunt heeft, en of de koersophaling (netwerk) slaagt, is hier niet te zien. Een grafiek met 1 werkelijk punt plus 12 verwachte punten toont een stip en een stippellijn; of dat voor de gebruiker "werkt" is een ontwerpvraag. De rest van de keten (`TimeLineChart`, SwiftUI) kan hier niet worden uitgevoerd.
9. De HIG zegt niets specifieks over de plek van een "Instellingen"-knop op iOS. De voorgestelde vorm (een toolbar-knop op de tab-hoofdpagina's naar een volledige pagina, met Account als eerste rij) is afgeleid uit `[B:settings, sheets, managing-accounts]` plus de indeling van Apple's eigen Instellingen-app (`[K]`).
10. Opgehaalde bronbestanden en scripts: `/tmp/hig-probe` (proef `portfolioSeries`), `/tmp/hig-research/hig-txt/*.txt` (tekst per HIG-pagina), `/tmp/hig-research/contrast.py` (contrast en kleurenblindheid), `/tmp/hig-research/api.py` (beschikbaarheid), `/tmp/hig-research/hig2txt.py` (JSON naar tekst). Dit zijn tijdelijke bestanden buiten de repo.
