# MyBuddy v2: in de stijl van Apple Muziek en Apple TV (ontwerp- en bouwplan)

Peildatum 23 oktober 2026, basis `HEAD` 1b98404. Uitvoerbaar bouwplan voor "verander het design opnieuw waardoor de app simpeler wordt, een combinatie van Apple Muziek en Apple TV", daarna "build". Bronnen: de code, `docs/design/plan.md`, het onderzoek `docs/design2/patterns.md` en eigen proeven tegen de typecontrole (2.2). Er is niets in `App/` of `CoreTests/` aangepast.

**Stand na pakket 3 (27 oktober 2026).** Alle drie golven zijn uitgevoerd: de oude tabroots (`Pages/Tabs/`), `LegacyTabNames.swift`, de oude kaarten en tegels (`HomePotsCard`, `HomeHoldingsCard`, `UpcomingDaysCard`, `FavoriteTileGrid` en tegels, elke `*SummaryCard` van de oude tabs, `SavingSupport.swift`, `EqualSizeGrid`) en alle compat (`BlockPage.month/.saving/.planning/.home/.savings/.tools`, `blockOrderToolbar`, `OrderedBlocks`, `GlassBlock`, `LinkedBlock`, `Chip*`, `ProgressRing`, `ProgressBar`, `SegmentBar`, `MeshBackground`, `glassCard`, `glassButton`, `Theme.olive*`, `Theme.flow*`, `Theme.buttonHeight`, `PeriodControl`, `searchToolbarButton`, `showsSettings`, `TimeLineChart`, `FlowChart`, `AllocationDonut`, `TimePoint`, `chartAxes`) zijn verwijderd; de migratie van oude opgeslagen sleutels bleef. `TabNote`, `TabWarning` en `OverviewCheckBanner` hoefden niet te verhuizen: Home heeft eigen onderdelen en niemand las ze meer. Vier WIRING-punten van de bouwers zijn afgehandeld: `HeroCard` heeft gelijke hoogte (`maxHeight: .infinity` en een `Spacer`), `Shelf(showAllShowsCurrentMonth:)` laat "Toon alle dagen" op de huidige maand openen, `BrowseTile(showsCurrentMonth:opensViaRouter:)` en `SearchTab` openen maandtegels op de huidige maand en Instellingen via `router.open` (op de Mac het `Settings`-venster), en een zoekresultaat van een maandpagina opent ook op de huidige maand. **Eerlijk over de verificatie:** er is geen Xcode-build gedraaid en de macOS-CI is niet gestart; de enige compilercontrole is de nagebootste typecheck (0 fouten), zie `README.md`, "Verificatie".

**Gezag.** Dit plan vervangt `docs/design/plan.md` voor tabstructuur (2.1 t/m 2.7), Instellingen als tab (K2, K3), kaartenpagina's per tab, 4.4 A, 4.5, werkpakketten en eigendom (6). Bindend blijft: kleuren en tokens (4.1, 4.2), gedragsregels 4.6, grafieken (5), Instellingen en Account (3.2 t/m 3.6), de termenlijst 2.8 (aangevuld in 1.6), `hig-notes.md`. **Lezen:** 0 besluiten, 1 architectuur en oud naar nieuw (1.5), 2 contract, 3 pagina's, 4 pakketten en eigendom, 5 verificatie, 6 risico's.

## 0. Besluiten (bindend; geen vragen)

| # | Besluit |
|---|---|
| B1 | **Drie tabs: Home, Bibliotheek, Zoeken** (`Tab(value:role: .search)`), `.tabViewStyle(.sidebarAdaptable)` op iPhone, iPad en Mac. Reden: gebruiker; TAB-3, TAB-9, SID-1. |
| B2 | **Tabtitel "Home"** (woord van de gebruiker); "Overzicht" vervalt overal. Reden: een woord per begrip (1.6). |
| B3 | **Instellingen is geen tab.** iPhone en iPad: een profielknop rechtsboven op de drie wortels pusht `.settingsRoot` (de bestaande lijst, Account eerst en los); nooit een sheet. Mac: geen knop, het `Settings`-venster (Cmd+komma, App-menu). Reden: gebruiker; SID-4, TLB-7. |
| B4 | **Eerlijk oordeel over "Instellingen altijd bereikbaar"** (eis uit K2/K3): bewust verruimd van 1 tik vanaf elke diepte naar **1 tik vanaf elke tabwortel, 2 vanaf elke diepte**, plus Cmd+komma (Mac, iPad met toetsenbord) en Zoeken. Synchronisatie-aandacht: stip op de profielknop (vervangt de tabbadge) en melding bovenaan Home. Reden: Apple Muziek doet dit ook; vindbaarheid blijft gehaald, snelheid vanaf diepte niet. |
| B5 | **Een pagina opent op de stapel waar je bent.** `Destination.tab` vervalt; `router.open(_:)` duwt op het pad van de huidige tab (een pagina mag op twee stapels staan); `router.go(_:)` (sneltoetsen, diepe links, `-mybuddy-open`) selecteert de Bibliotheek met ouders + pagina, behalve Instellingen (push op de huidige stapel) en de wortels. K16 blijft: nooit twee keer dezelfde pagina in een pad. Reden: geen tabwissel bij een link. |
| B6 | **Home = hero en plank.** Hero-carrousel (Nog te verdelen, Vermogen, Saldo vandaag met volgende betaling), daaronder vijf planken: Komende dagen, Spaarpotten, Beleggingen, Doelen, Hulpmiddelen. Plankkop = link "Toon alles". Hoogstens 8 tegels per plank. Reden: gebruiker; patterns 4.1, 4.2. |
| B7 | **Bibliotheek = lijst, drie groepen, 13 rijen, dan Recent**: Deze maand (Maandoverzicht, Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag), Sparen en beleggen (Spaarpotten, Beleggingen), Plannen (Doelen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck). Rij = `MediaRow` met tegel. **Maandoverzicht is nieuw** (`.flow`): de kaart "Waar gaat je geld heen" had anders geen plek. Reden: niets mag verloren gaan. |
| B8 | **Maandpagina's openen vanaf Home en Bibliotheek op de huidige maand** (`showCurrentMonth`); binnen die pagina's bladert de `MonthBar` (staat er al). Home en Bibliotheek lezen `focusMonth` en `periodMode` niet (K17). |
| B9 | **Zoeken**: zonder tekst tien bladertegels, met tekst resultaten per `SearchGroup` uit `SearchIndex`; geen zoekgeschiedenis; Cmd+F selecteert de tab en opent het veld; de zoekknop in de werkbalk vervalt. Reden: patterns 4.8; privacy. |
| B10 | **Spaarpot, belegging en doel zijn albumpagina's**: `AlbumHeader` als eerste rij van de bestaande `List`, daaronder de bestaande secties als tracklijst (swipe, contextmenu), grafieken blijven. Geen logica verandert. |
| B11 | **Rekenpagina's blijven formulier- en lijststructuren**; het nieuwe uiterlijk komt vanzelf via de scaffolds (achtergrond, radius, capsule-knoppen). |
| B12 | **Achtergrond**: zacht kleurverloop (`BackdropGradient`), tint = bovenste tegelkleur van het domein, hoogstens 55% (donker) of 14% (licht) over `Theme.canvas`, uitlopend over 420 pt; op Home volgt de tint de zichtbare hero-kaart (`animated(by:)`); bij Verhoog contrast en Verlaag transparantie geen tint. Reden: gebruiker; contrast berekend (2.1). |
| B13 | **Acht tegelkleuren (`TileHue`)**, niet licht/donker-afhankelijk; wit erop 6,4:1 (hoog contrast 9,6:1). Tekst op een tegel is `Theme.onTile` of `onTileSecondary`, nooit rood of groen: tekens en woorden dragen de betekenis. Een grafiek op een tegel staat in een donker paneel (`heroPanel()`). Reden: COL-3, COL-4. |
| B14 | **Radii**: hero 28, kaart 20 (was 24), artwork rij 8, tegel 16, albumkop 24, `Theme.tileRadius` 12 (was 8). Marge 16 (compact) of 20; tussenruimte 12 of 16; 24 tussen planken. Reden: gebruiker (hero 20 tot 28, tegels 12 tot 16). |
| B15 | **Geen eigen glas**: glas komt van het systeem (tabbalk, werkbalk, zoekveld, menu's, sheets). **Geen BottomAccessory**: het verdubbelt de hero, bestaat niet op macOS en is vaste chrome. Capsule-knoppen in de inhoud zijn vlak. Reden: GLS-1, GLS-2; "eventueel". |
| B16 | **Blokvolgorde blijft, alleen voor de Home-planken** (hero en Bibliotheek vast): `BlockPage.overview` (sleutel blijft, titel "Home") met `upcoming`, `pots`, `invest`, `goals`, `tools`; `wealth` wordt hero 2 en een opgeslagen volgorde met `wealth` laadt gewoon; oude sleutels (`month`, `saving`, `planning`, `home`, `savings`, `tools`) blijven ongemoeid in de data. Zichtbare route: Instellingen, Indeling en lang indrukken op een plankkop; geen werkbalkknop. Reden: K8 was expliciet gevraagd; geen extra chrome. |
| B17 | **Gekozen potten en beleggingen blijven** (K9a t/m K9c): de plank Spaarpotten toont `homePots()` (max. 3, plus lege plek), de plank Beleggingen `homeHoldings()` (max. 4) met vooraan een samenvattingstegel. Plankmenu ("…"): Kies potten…, Nieuwe spaarpot; Kies beleggingen…, Belegging toevoegen, Koersen vernieuwen. Reden: eerder expliciet gevraagd. |
| B18 | **Recent = de laatste vijf handmatige boekingen** (bank en potten, zonder Beginsaldo, een overboeking eenmaal): `RecentActivity`, Foundation-only, getest; geen boekingen: geen groep. Reden: dichtst bij "Recent toegevoegd", zonder opslag. |
| B19 | **`Destination` krijgt `.home`, `.library`, `.flow`, `.tools`, `.settingsRoot`**; `.overview` wordt `.home`; `AppTab` = `home, library, search`. `PageCatalog` is de enige tabel (titel, symbool, tint, groep, "bereikbaar via"); een test bewijst dat elke pagina bereikbaar blijft. Reden: controleerbaar, geen verloren pagina. |
| B20 | **Niet in deze ronde**: zoom-overgangen, `MeshGradient`, `scrollTransition`, `TabSection`, `ToolbarSpacer`, `@Namespace`: ze staan niet in de nagebootste frameworks en zijn niet te controleren (2.2). |
| B21 | **Twee macOS-risico's uit patterns 3.6 meteen rechtzetten**: `tabBarMinimizeBehavior(.onScrollDown)` en `toolbarTitleDisplayMode(.large)` alleen onder `#if os(iOS)`. |
| B22 | **Geen rekenregel, model of opslagformaat verandert**: bedragen uit `MonthBoard`, `MoneyFigures`, `LedgerBook`, `netWorth`, `periodSummary`, `PortfolioFigures`, `GoalMath`, `BufferCalc`. |

## 1. Informatiearchitectuur

### 1.1 Schil

```
iPhone: tabbalk (glas op iOS 26, krimpt bij omlaag scrollen): Home | Bibliotheek | Zoeken (los, rechts)
iPad en Mac: zijbalk met dezelfde drie items; Cmd+1, Cmd+2, Cmd+3; Cmd+F = Zoeken; Cmd+, = Instellingen
Elke tab: eigen NavigationStack en pad (router.paths[tab]); tik op de actieve tab = terug naar de wortel (bestaat al)
iOS en iPadOS: ToolbarItem(.primaryAction) = ProfileButton op de wortels van Home, Bibliotheek, Zoeken -> push .settingsRoot
Mac: Settings-scene ongewijzigd (zes panes); router.go(.settings(_)) zet settingsRequest (bestaat al)
```

Wortels: `HomeTab` (grote titel, `PageScaffold(fullBleed: true)`), `LibraryTab` (`ListScaffold`, grote titel), `SearchTab` (`.searchable`). `RootView` heeft een `TabView` voor beide platforms (de `#if os(macOS)`-tweedeling vervalt). `ProfileButton` toont een stip als `sync?.importOffer != nil || sync?.conflict != nil`, label "Account en instellingen, actie nodig".

### 1.2 Bestemmingen en `PageCatalog`

```swift
enum Destination: Hashable {
    case home, library                                  // tabwortels, alleen voor zoeken, sneltoetsen en diepe links
    case flow                                           // Maandoverzicht
    case income, salary, expenses, distribute, bank, cashflow
    case pots, pot(UUID), portfolio, holding(UUID)
    case goals, goal(UUID), savingsGoal, accelerators, buffer, projection, purchase
    case tools                                          // Hulpmiddelen (lijst van vier)
    case settingsRoot                                   // Instellingen (lijst, Account bovenaan)
    case settings(SettingsPage)                         // ongewijzigd
}
```

`PageCatalog.all` (Foundation-only) is de bron voor Bibliotheekrijen, bladertegels en zoekregels; de zoektermen nemen de bouwers over uit de bestaande `SearchIndex.pages`, aangevuld met de termen van `.flow` (waar gaat je geld heen, periode, half jaar) en `.tools` (rekenhulp, calculators).

| Bestemming | Titel | Symbool | Tint | Groep | Bereikbaar via |
|---|---|---|---|---|---|
| `.home` / `.library` | Home / Bibliotheek | house / books.vertical | olive | - | wortel |
| `.flow` | Maandoverzicht | chart.bar.xaxis | terracotta | Deze maand | Bibliotheek |
| `.income` | Inkomen | eurosign.circle | terracotta | Deze maand | Bibliotheek |
| `.salary` | Salaris instellen | eurosign.circle | terracotta | - | `.income` |
| `.expenses` | Uitgaven | creditcard | terracotta | Deze maand | Bibliotheek |
| `.distribute` | Verdelen | square.split.2x2 | terracotta | Deze maand | Bibliotheek |
| `.bank` | Bankrekening | building.columns | terracotta | Deze maand | Bibliotheek |
| `.cashflow` | Dag voor dag | list.bullet.rectangle | terracotta | Deze maand | Bibliotheek |
| `.pots` | Spaarpotten | tray.full | teal | Sparen en beleggen | Bibliotheek, Home |
| `.portfolio` | Beleggingen | chart.line.uptrend.xyaxis | slate | Sparen en beleggen | Bibliotheek, Home |
| `.goals` | Doelen | flag.checkered | mustard | Plannen | Bibliotheek, Home |
| `.savingsGoal` | Spaardoel berekenen | function | mustard | - | `.goals` |
| `.buffer` | Noodbuffer | shield.lefthalf.filled | mustard | Plannen | Bibliotheek, Hulpmiddelen |
| `.accelerators` | Versnellers | bolt | mustard | Plannen | Bibliotheek, Hulpmiddelen |
| `.projection` | Toekomstschatting | calendar.badge.clock | plum | Plannen | Bibliotheek, Hulpmiddelen |
| `.purchase` | Aankoopcheck | cart | plum | Plannen | Bibliotheek, Hulpmiddelen |
| `.tools` | Hulpmiddelen | wrench.and.screwdriver | plum | - | `.home` (plankkop), Zoeken |
| `.settingsRoot` | Instellingen | gearshape | sage | - | `.home` (profielknop), Zoeken |

`.pot(id)`, `.holding(id)`, `.goal(id)` en `.settings(_)` staan niet in de tabel: ze zijn bereikbaar via Spaarpotten, Beleggingen, Doelen en Instellingen. Pot, belegging en doel gebruiken eigen tinten: `TileHue.forIndex(pot.colorIndex)`, `TileHue.forIndex(holding.kind.colorIndex)`, doel mustard. Bladertegels (`PageCatalog.browse`, tien): Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag, Spaarpotten, Beleggingen, Doelen, Hulpmiddelen, Instellingen.

`NavigationRules.go(_ d: Destination, from current: AppTab, path: [Destination]) -> (tab: AppTab, path: [Destination])`: `.home`, `.library` geven (die tab, []); `.settingsRoot` en `.settings(p)` geven (current, path + ontbrekende `.settingsRoot` en `.settings(parent)` + d, genormaliseerd); de rest geeft (.library, ouders + d), ouders: `.pot` onder `.pots`, `.holding` onder `.portfolio`, `.goal` onder `.goals`, `.salary` onder `.income`.

### 1.3 Home

Boven de hero staan de bestaande meldingen (opslaan mislukt, startmelding, synchronisatie, "De cijfers sluiten niet"). Hero 1 Nog te verdelen (olijf), 2 Vermogen met sparklijn (leiblauw), 3 Saldo vandaag met volgende betaling (terracotta). Planken: Komende dagen (brede kaart per dag), Spaarpotten, Beleggingen (samenvattingstegel en tegels), Doelen (tegels en rekentegel), Hulpmiddelen (vier tegels).

Lege start (`isEmptyStart`): een welkomstkaart met pillen "Salaris instellen" en "Voorbeelddata laden" (bestaande bevestiging) in plaats van hero en planken. Zonder bekend banksaldo toont hero 3 "Vul je saldo in" met pil "Saldo invullen" (`BankActionSheet(.balance)`). Elke plank heeft een lege staat.

### 1.4 Bibliotheek en Zoeken

Bibliotheek: `ListScaffold`, groepskoppen "Deze maand · oktober", "Sparen en beleggen", "Plannen", "Recent". Rijen uit `PageCatalog.library`; waarde of ondertitel uit de bron van de oude kaart: Inkomen en Uitgaven (huidige maand), Verdelen (nog te verdelen, met teken), Bankrekening (saldo vandaag, als bekend), Spaarpotten (totaal, "n potten"), Beleggingen (waarde, "n beleggingen"); Doelen `GoalMath.hubSubtitle`; Noodbuffer "n maanden aan uitgaven"; Versnellers "Voor <doel>"; Toekomstschatting "Wat is het over x jaar?"; Aankoopcheck "Is het je werkuren waard?". Maandrijen met `showsCurrentMonth: true`. Recent: `RecentActivity.items(in:asOf:limit: 5)` als `MediaRow`s (pot: `.pot(id)`, bank: `.bank`).

### 1.5 Oud naar nieuw (niets verloren)

| Oud | Nieuw (bron blijft gelijk) |
|---|---|
| Tab Overzicht, kern `OverviewHero` (Nog te verdelen, `MonthBoard`, notities) | Hero 1; pil naar `.distribute` met `showsCurrentMonth` |
| `OverviewWealthCard` (`netWorth`, `NetWorthTrend`, drie links, notitie bank onbekend) | Hero 2 (sparklijn in `heroPanel`, drie pillen, notitie) |
| `HomePotsCard` (totaal, `homePots()`, Kies potten, Alle spaarpotten, lege pot-tegel) | Plank Spaarpotten (totaal als subtitel, menu, kop-link, lege plek) |
| `HomeHoldingsCard` (waarde, `GainBadge`, `PortfolioTrend`, `homeHoldings()`, Kies beleggingen, Koersen vernieuwen) | Plank Beleggingen (samenvattingstegel met sparklijn, tegels, menu, kop-link) |
| `UpcomingDaysCard` (14 dagen, saldo per dag, knop Dag voor dag, ontbrekend saldo) | Plank Komende dagen en hero 3 |
| `OverviewWelcome`, `OverviewCheckBanner`, `NoticeCard`s, `SyncAttentionBanner` | Zelfde componenten, boven de hero |
| Zoekveld op Overzicht, zoekknoppen op Maand, Sparen, Plannen, Cmd+F; Cmd+1 t/m Cmd+5 | Tab Zoeken (Cmd+F selecteert hem); Cmd+1 t/m Cmd+3 |
| Tab Maand: `MonthBar`; kaarten `income`, `expenses`, `distribute`, `bank`, `days` | Bibliotheekrijen met waarde; de details staan al op de pagina's (`IncomeSummarySection`, `ExpensesSummarySection`, `DistributeSummaryCard`, `BankLowPointSection`) |
| Kaart `flow` (`PeriodPicker`, `StackedBarChart`, tegel, "Cijfers van deze periode", "Maand voor maand") | Pagina `.flow` (Maandoverzicht) |
| Tab Sparen: `PotsSummaryCard`, `PortfolioSummaryCard` | Bibliotheekrijen en Home-planken; voortgang naar het totale doel staat al op Spaarpotten (`PotsSummarySection`) |
| Tab Plannen: kaarten Doelen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck | Bibliotheekrijen; planken Doelen en Hulpmiddelen; "Spaardoel berekenen" op Doelen en als laatste tegel van de plank Doelen |
| Tab Instellingen (iOS), `Settings`-venster (Mac); badge | Profielknop met stip, push `.settingsRoot`; Mac ongewijzigd |
| "Volgorde aanpassen" (menu in werkbalk, Indeling, lang indrukken) | B16; `FavoritePotsSheet` en `FavoriteHoldingsSheet` blijven (plankmenu en menu van Spaarpotten en Beleggingen) |
| Elke bestaande `Destination` | Blijft, tabel 1.2; `.overview` wordt `.home` |
| Vervalt zonder vervanging | zoekknoppen in werkbalken; blokvolgorde van Maand, Sparen, Plannen (data blijft); tab Instellingen en badge |

### 1.6 Termen (aanvulling op 2.8)

Tabs **Home**, **Bibliotheek**, **Zoeken**. Nieuw: **Toon alles** (label per plank, bijvoorbeeld "Toon alle spaarpotten"), **Maandoverzicht**, **Hulpmiddelen**, **Recent**, **Blader**, "Deze maand", "Sparen en beleggen", "Plannen" (alleen als groepskop). Verboden: "Overzicht" als pagina- of tabnaam (`Importoverzicht` mag), "Savings", "Tools". "Kies potten voor het Overzicht…" wordt "Kies potten voor Home…"; sheets "Spaarpotten op Home", "Beleggingen op Home".

## 2. Ontwerpsysteem v2 (het bindende contract)

Wat een andere bouwer aanroept staat hier met exacte handtekening. Uitbreiden met een parameter met standaardwaarde mag, hernoemen niet; een afwijking meldt de bouwer onder WIRING. Nieuwe typen krijgen nieuwe namen (alles is een module). Tekst en commentaar Nederlands, zinshoofdletter.

### 2.1 Kleur, contrast en maten (berekend en getest)

`TilePalette` (Foundation-only) bevat de hex-waarden; `Theme.swift` leest ze, ook `canvas` en `textSecondary` (een bron, zodat test en UI niet uiteen lopen). `Color(hex:)` blijft alleen in `Theme.swift`.

| `TileHue` (= `Theme.palette`-index) | boven | onder | boven hoog contrast | onder hoog contrast | `AppDomain` |
|---|---|---|---|---|---|
| 0 `olive` | 0x566529 | 0x333B18 | 0x3F491E | 0x232911 | overview |
| 1 `teal` | 0x2D6863 | 0x1B3E3B | 0x214C48 | 0x122A28 | saving |
| 2 `mustard` | 0x755C0C | 0x453607 | 0x554308 | 0x2F2505 | goals |
| 3 `terracotta` | 0x924C2E | 0x572D1C | 0x6B3722 | 0x3C1F13 | money |
| 4 `slate` | 0x406281 | 0x263A4D | 0x2E475E | 0x1A2835 | investing |
| 5 `plum` | 0x934276 | 0x582746 | 0x6C3056 | 0x3D1B31 | tools |
| 6 `sage` | 0x57634B | 0x343A2C | 0x404836 | 0x24281F | settings |
| 7 `brown` | 0x735B3E | 0x443525 | 0x54422D | 0x2F2519 | potkleur |

Gemeten (WCAG 2.x, sRGB; `TilePaletteTests` herberekent het): wit op "boven" 6,37 tot 6,42:1, op "onder" minimaal 11,7:1, hoog contrast 9,6:1. `Theme.onTile` is wit; `Theme.onTileSecondary` wit op 82% (minimaal 4,88:1; 4,5:1 vanaf 77%), bij Verhoog contrast 92% (minimaal 8,3:1). Tegelverloop `LinearGradient(colors: [boven, onder], startPoint: .topLeading, endPoint: .bottomTrailing)`, zonder schaduw of glans (elke overlay verlaagt het gemeten contrast).

`BackdropGradient`: bovenstop `TileHue.boven` met dekking 0,55 (donker) of 0,14 (licht), lineair naar 0 over 420 pt, over `Theme.canvas`; alfa-menging zoals SwiftUI tekent. Slechtste palet: `Theme.textSecondary` 5,49:1 (donker) en 4,73:1 (licht), `.primary` meer dan 10:1. Verhoog contrast of Verlaag transparantie: dekking 0. Wie een waarde aanpast laat `TilePaletteTests` slagen, versoepelt hem niet. (`patterns.md` 3.3 noemt andere percentages: andere kleurstops en Oklab-menging.)

### 2.2 Wat de typecontrole kent (proef 23 okt., `/tmp/arch-probe/probe-results.txt`)

De enige compilercontrole is de nagebootste SwiftUI (`/tmp/ctl-all`, gegenereerd uit Apple's documentatie): een API die daar ontbreekt geeft een fout, ook als Xcode hem kent.

- **Aanwezig** (naast alles wat de app al gebruikt): `scrollTargetLayout`, `scrollPosition(id:)`, `safeAreaPadding`, `contentMargins`, `containerRelativeFrame` (`count:` vraagt `spacing:`), `onGeometryChange`, `onHover`, `Layout`, `LinearGradient`, `RadialGradient`, `Color.mix`, `searchable(text:isPresented:prompt:)`, `contextMenu(menuItems:preview:)`, `contentShape(.contextMenuPreview, _)`, `buttonBorderShape(.capsule)`, `Tab(value:role:)`.
- **Ontbreekt, niet gebruiken (B20)**: `MeshGradient`, `scrollTransition`, `visualEffect`, `onScrollGeometryChange`, `scrollEdgeEffectStyle`, `@Namespace`, `matchedTransitionSource`, `navigationTransition`, `TabSection`, `ToolbarSpacer`, `DragGesture`, `Canvas`, `TimelineView`, `Gauge`, `AsyncImage`, `ShareLink`, `popover`, `Color.gradient`, `containerBackground(for:)`, `Tab("Titel", systemImage:, value:, role:)` (gebruik `Tab(value:role:)`).
- **Alleen iOS, dus `#if os(iOS)`**: `topBarTrailing` (gebruik `.primaryAction`), `.listStyle(.insetGrouped)`, `hoverEffect`, `fullScreenCover`, `toolbarTitleDisplayMode(.large)`, `tabBarMinimizeBehavior(.onScrollDown)` (B21).
- **iOS 26**: achter `#available(iOS 26.0, macOS 26.0, *)`, ook als de nabootsing het niet markeert; `run-all.sh` meldt `ONBEWAAKT` en dat moet nul zijn.

**Stap 0 van pakket 1: voeg `scrollTargetBehavior` toe aan de nagebootste SwiftUI** (echte API sinds iOS 17 en macOS 14; nodig voor het snappen van hero en planken; getest: bouwt in 18 s, de carrouselcode typecheckt). Maak `/tmp/ctl-all/stubs/SwiftUI/H_Extra.swift`, draai `cd /tmp/ctl-all && ./build-stubs.sh ios && ./build-stubs.sh mac` en een basislijn `./run-all.sh` (0 fouten):

```swift
import Foundation
public protocol ScrollTargetBehavior {}
public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {
    public struct LimitBehavior: Hashable, Sendable {
        public static var automatic: LimitBehavior { fatalError() }
        public static var always: LimitBehavior { fatalError() }
        public static var never: LimitBehavior { fatalError() }
    }
    public init(limitBehavior: LimitBehavior = .automatic) {}
}
public struct PagingScrollTargetBehavior: ScrollTargetBehavior { public init() {} }
extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
    public static var viewAligned: ViewAlignedScrollTargetBehavior { ViewAlignedScrollTargetBehavior() }
}
extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
    public static var paging: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}
extension View { nonisolated public func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> some View { self } }
```

### 2.3 Foundation-only bouwstenen (symlink in `CoreTests/Tests/MyBuddyCoreTests`, met tests)

```swift
// App/UI/TilePalette.swift                 tests: TilePaletteTests
enum TileHue: Int, CaseIterable, Identifiable, Hashable {
    case olive, teal, mustard, terracotta, slate, plum, sage, brown      // volgorde = Theme.palette 0...7
    var id: Int { rawValue }
    static func forIndex(_ index: Int) -> TileHue                          // ((index % 8) + 8) % 8
}
struct TileColors: Equatable { let top, bottom, topHC, bottomHC: UInt32 }
enum TilePalette {
    static func colors(_ hue: TileHue) -> TileColors                       // tabel 2.1
    static let canvasLight: UInt32 = 0xEEF1E2, canvasDark: UInt32 = 0x0E1209
    static let textSecondaryLight: UInt32 = 0x566049, textSecondaryDark: UInt32 = 0xB3BAA3
    static let textSecondaryLightHC: UInt32 = 0x3A4230, textSecondaryDarkHC: UInt32 = 0xD3D9C4
    static let onTileSecondaryAlpha = 0.82, onTileSecondaryAlphaHC = 0.92
    static let backdropAlphaDark = 0.55, backdropAlphaLight = 0.14
    static func luminance(_ hex: UInt32) -> Double                         // WCAG
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double
    static func blend(_ fg: UInt32, over bg: UInt32, alpha: Double) -> UInt32
}

// App/UI/ShelfMetrics.swift                tests: ShelfMetricsTests (tabel patterns 3.4 als testgegevens)
enum ShelfMetrics {
    static let heroPeek = 8.0
    static func margin(compact: Bool) -> Double                            // 16 : 20
    static func spacing(compact: Bool) -> Double                           // 12 : 16
    static func tileWidth(in length: Double, spacing: Double) -> Double    // whole = max(2, Int((length + spacing) / (150 + spacing))); (length - whole * spacing) / (whole + 0.4); ongeldig 140
    static func wideTileWidth(in length: Double, spacing: Double) -> Double // 2 * tileWidth + spacing
    static func heroWidth(in length: Double, spacing: Double) -> Double    // >= 860: (length - 2 * spacing) / 3; anders min(length - spacing - heroPeek, 480); ongeldig: 300
    static func showsHeroCarousel(in length: Double) -> Bool               // length < 860
}

// App/Navigation/PageCatalog.swift         tests: PageCatalogTests
enum LibrarySection: String, CaseIterable, Identifiable { case month, saving, planning
    var id: String { rawValue }; var title: String }                       // Deze maand, Sparen en beleggen, Plannen
struct PageInfo: Identifiable, Hashable {
    let destination: Destination; let title: String; let symbol: String; let hue: TileHue
    let section: LibrarySection?; let reachableFrom: Destination?; let terms: [String]
    var id: String { String(describing: destination) }
}
enum PageCatalog {
    static let all: [PageInfo]                                             // tabel 1.2
    static var library: [PageInfo] { get }                                 // section != nil, in tabelvolgorde
    static func library(in section: LibrarySection) -> [PageInfo]
    static func info(_ d: Destination) -> PageInfo?
    static let browse: [Destination]                                       // de tien bladertegels
}

// App/UI/RecentActivity.swift              tests: RecentActivityTests (pakket 2B)
struct RecentItem: Identifiable, Equatable { let id: String, title: String, subtitle: String, symbol: String; let date: Date; let amount: Double; let hue: TileHue; let destination: Destination }
enum RecentActivity {
    static func items(in data: FinanceData, asOf: Date, limit: Int = 5) -> [RecentItem]
    // BankEntry en PotEntry met date <= asOf, zonder .opening; een overboeking (zelfde pairID) eenmaal; nieuwste eerst
}
```

`NavigationModel.swift`: `enum AppTab: String, CaseIterable, Identifiable, Hashable { case home, library, search; var id: String; var title: String /* Home, Bibliotheek, Zoeken */; var symbol: String /* house, books.vertical, magnifyingglass */ }`; `Destination` volgens 1.2 zonder `tab`, met `parents` (pot onder pots enz.); `NavigationRules.go` volgens 1.2. `SearchIndex`: `SearchEntry` krijgt `var hue: TileHue = .olive` en `var group: SearchGroup { get }`; `enum SearchGroup: Int, CaseIterable, Identifiable { case pages, pots, holdings, goals, lines, settings; var id: Int; var title: String }` (Pagina's, Spaarpotten, Beleggingen, Doelen, Inkomen en uitgaven, Instellingen); `static func grouped(for:in:) -> [(group: SearchGroup, entries: [SearchEntry])]` (alleen groepen met resultaat); `pages` komt uit `PageCatalog.all` plus de tien instellingenpagina's.

`Router` (pakket 1; alleen de navigatie-API, de rest blijft zoals nu):

```swift
@MainActor @Observable final class Router {
    var tab: AppTab = .home; var paths: [AppTab: [Destination]]; var orderPage: BlockPage?
    var focusMonth: YearMonth; var periodMode: PeriodMode; var searchRequest = 0; var settingsRequest: SettingsPage?
    func pathBinding(for tab: AppTab) -> Binding<[Destination]>   // schrijven gaat door NavigationRules.normalize
    func select(_ tab: AppTab); func popToRoot(_ tab: AppTab)
    func open(_ d: Destination)      // push op paths[tab]; Mac met .settingsRoot of .settings: go
    func go(_ d: Destination)        // NavigationRules.go(d, from: tab, path: paths[tab]); Mac met instellingen: settingsRequest (.settingsRoot -> .account)
    func requestSearch()             // select(.search); searchRequest += 1
    func showCurrentMonth(_ current: YearMonth); func shiftPeriod(_ direction: Int); func resetFocus(to current: YearMonth)
}
```

### 2.4 SwiftUI-componenten (`App/UI/`, pakket 1)

De handtekeningen van `Shelf`, `HeroCarousel`, `HeroCard`, `AlbumHeader` zijn als proefontwerp getypecheckt (iOS en macOS, met de stubs van stap 0): `/tmp/arch-probe/proto.swift`.

```swift
// Theme.swift (uitbreiding)
extension TileHue { var top: Color; var bottom: Color; var gradient: LinearGradient }   // Color(light:dark:lightContrast:darkContrast:), niet modusafhankelijk
extension AppDomain { var hue: TileHue }
extension Theme { static let onTile: Color; static let onTileSecondary: Color
    static let heroRadius: CGFloat = 28; static let cardRadius: CGFloat = 20; static let tileRadius: CGFloat = 12
    static let shelfMaxWidth: CGFloat = 1120; static let backdropHeight: CGFloat = 420
    static func hue(_ paletteIndex: Int) -> TileHue }
extension EnvironmentValues { var backdropHue: TileHue { get set }   // standaard .olive; DestinationView zet hem per pagina
                              var tileHue: TileHue { get set } }     // GradientSurface zet hem; PillStyle.onTile leest hem

// Backdrop.swift
struct BackdropGradient: View { init(hue: TileHue = .olive) }        // canvas + verloop; colorScheme, colorSchemeContrast, reduceTransparency; .animated(by: hue)

// Components.swift (bestaand; aanroepen blijven compileren)
struct PageScaffold<Content: View>: View { let title: String; var large = false; var showsSettings = false
    var fullBleed = false     // nieuw: geen horizontale marge, breedte tot Theme.shelfMaxWidth (Home)
    @ViewBuilder var content: Content }   // achtergrond BackdropGradient(hue: backdropHue); ListScaffold idem
// Card, LinkCard, NoticeCard, MonthBar: Theme.cardRadius. ActionButton, ActionLink: .buttonBorderShape(.capsule).
// DestinationLink: geen tab-logica: showsCurrentMonth -> Button { showCurrentMonth; open }, anders NavigationLink(value:).

// Tiles.swift
struct GradientSurface<Content: View>: View {   // tegelverloop, tekst onTile, zet \.tileHue; Verhoog contrast: HC-kleuren en rand
    init(hue: TileHue, radius: CGFloat = Theme.tileRadius, @ViewBuilder content: () -> Content) }
enum ArtworkSize: Equatable { case row, fill, header }   // row 44 pt (schaalt tot 1,5x), radius 8; fill: vierkant, vult de breedte, radius 16; header: vierkant 220 (compact) of 200 pt, radius 24
struct ArtworkTile: View {   // symbool resizable en scaledToFit (nooit .system(size:)); fill: symbool linksboven en balk onderin; header: symbool midden
    init(symbol: String, hue: TileHue, size: ArtworkSize = .fill, progress: Double? = nil, progressLabel: String? = nil) }
struct PosterCard: View {    // tegel, titel (2 regels), ondertitel, waarde; breedte komt van Shelf; een element voor VoiceOver
    init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, value: String? = nil,
         progress: Double? = nil, progressLabel: String? = nil, destination: Destination? = nil,
         showsCurrentMonth: Bool = false, action: (() -> Void)? = nil) }   // destination = link, action = knop, geen van beide = statisch
struct ShelfCard<Content: View>: View {   // tekst- of brede kaart: hue nil = Theme.card, anders GradientSurface; radius 16
    init(hue: TileHue? = nil, destination: Destination? = nil, showsCurrentMonth: Bool = false, @ViewBuilder content: () -> Content) }
struct BrowseTile: View {    // Zoeken: minimaal 96 pt hoog, radius 16, titel linksonder .headline, decoratief symbool rechtsboven
    init(title: String, symbol: String, hue: TileHue, destination: Destination,
         showsCurrentMonth: Bool = false, opensViaRouter: Bool = false) }   // opensViaRouter: Button { router.open } (Instellingen op de Mac = Settings-venster)
struct TilePressStyle: ButtonStyle {}   // dekking 0,7; schaal 0,98 behalve bij Verlaag beweging

// Shelf.swift
struct ShelfAction: Identifiable { let id = UUID(); let title: String; let symbol: String; var role: ButtonRole? = nil; let action: () -> Void
    init(_ title: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) }
struct Shelf<Item: Identifiable, Tile: View>: View {
    init(_ title: String, subtitle: String? = nil, showAll: Destination? = nil, showAllLabel: String? = nil,
         showAllShowsCurrentMonth: Bool = false,
         actions: [ShelfAction] = [], orderID: String? = nil, wide: Bool = false,
         items: [Item], @ViewBuilder tile: @escaping (Item) -> Tile) }
// Kop: titel .title2.weight(.semibold) (isHeader), subtitel .subheadline, rechts "Toon alles" (label showAllLabel) en bij actions een "…"-menu (IconButton "Meer"); orderID geeft de kop .blockOrderMenu(page: .overview, id:).
// Rij: ScrollView(.horizontal) met HStack (niet Lazy: VoiceOver bereikt alles; hoogstens 8 items), tegel .containerRelativeFrame(.horizontal) { ShelfMetrics.tileWidth of wideTileWidth },
// .scrollTargetLayout(), .scrollTargetBehavior(.viewAligned), .scrollIndicators(.hidden), .safeAreaPadding(.horizontal, margin), .scrollClipDisabled(). Toegankelijkheidsformaat: items onder elkaar, hoogstens 320 pt.

// Hero.swift
struct HeroCarousel<Card: View>: View { init(ids: [String], selection: Binding<String?>? = nil, @ViewBuilder card: @escaping (String) -> Card) }
// < 860 pt (onGeometryChange): ScrollView(.horizontal), kaart .containerRelativeFrame { ShelfMetrics.heroWidth }, viewAligned, scrollPosition(id:); stippen eronder als Buttons
// (raakdoel Theme.minTapTarget, label "Pagina n van m") plus acties "Volgende pagina" en "Vorige pagina". >= 860 pt: drie kaarten naast elkaar zonder stippen. Toegankelijkheidsformaat: onder elkaar.
struct HeroCard<Content: View, Pills: View>: View {   // GradientSurface radius heroRadius, minimaal 168 pt (schaalt), maxHeight .infinity (even hoog als de hoogste), pillen onderaan, padding 20, eyebrow .subheadline.weight(.semibold) in onTileSecondary
    init(hue: TileHue, eyebrow: String, symbol: String, @ViewBuilder content: () -> Content, @ViewBuilder pills: () -> Pills) }
extension HeroCard where Pills == EmptyView { init(hue: TileHue, eyebrow: String, symbol: String, @ViewBuilder content: () -> Content) }
extension View { func heroPanel() -> some View }   // zwart op 22%, radius 16, padding 12, .environment(\.colorScheme, .dark): grafiek in een hero of tegel

// Rows.swift
struct MediaRowLabel: View { init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, value: String? = nil,
                                   valueColor: Color = .primary, progress: Double? = nil, showsChevron: Bool = false) }
struct MediaRow: View { init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, value: String? = nil,
                             valueColor: Color = .primary, progress: Double? = nil, destination: Destination,
                             showsCurrentMonth: Bool = false) }   // DestinationLink { MediaRowLabel }; minimaal Theme.minTapTarget hoog; bij toegankelijkheidsformaat de waarde onder de titel

// Album.swift
struct AlbumHeader<Pills: View, Extra: View>: View {
    init(symbol: String, hue: TileHue, title: String, subtitle: String? = nil, figureLabel: String? = nil,
         figure: Double? = nil, figureColor: Color = .primary, progress: Double? = nil, progressLabel: String? = nil,
         facts: [String] = [], @ViewBuilder pills: () -> Pills, @ViewBuilder extra: () -> Extra) }
extension AlbumHeader where Extra == EmptyView { /* dezelfde init zonder extra */ }
extension View { func albumHeaderRow() -> some View }   // listRowInsets(EdgeInsets()), listRowBackground(Color.clear), listRowSeparator(.hidden)
// compact: gecentreerd (tegel .header, titel .title2.bold, ondertitel, kerngetal via BigAmount, facts .footnote, pillen); regular (>= 560 pt, ViewThatFits): tegel links, tekst rechts. Titel en kerngetal zijn koppen.

// Pills.swift
enum PillStyle { case prominent, secondary, onTile }   // prominent: accentFill + onAccent; secondary: tileFill + accent; onTile: wit vlak, tekst in de bovenkleur van \.tileHue
struct PillButton: View { init(_ title: String, symbol: String? = nil, style: PillStyle = .secondary, role: ButtonRole? = nil, action: @escaping () -> Void) }
struct PillLink: View { init(_ title: String, symbol: String? = nil, style: PillStyle = .secondary, destination: Destination, showsCurrentMonth: Bool = false) }
struct PillRow<Content: View>: View { init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) }   // ViewThatFits: naast elkaar, anders onder elkaar
// Capsule, minimaal Theme.minTapTarget hoog, .subheadline.weight(.semibold), tekst wrapt, destructief Theme.negative; hoogstens een .prominent per scherm.

// Profile.swift
struct ProfileButton: View { init() }   // alleen iOS en iPadOS: cirkel (GradientSurface .olive) met initiaal of person.fill, stip bij aandacht, label "Account en instellingen"; tik: router.open(.settingsRoot)
extension View { func profileToolbarItem() -> some View }   // ToolbarItem(placement: .primaryAction) { ProfileButton() }; op macOS een no-op
```

### 2.5 Gedrag per breedte, toegankelijkheid, componenten

**Per breedte** (maten uit `ShelfMetrics`, patterns 3.4). iPhone: tabbalk, carrousel van 323 tot 388 pt met stippen, plank met 2 tegels en een rand (133 tot 160 pt), albumkop gecentreerd (tegel 220 pt), lijsten `insetGrouped`, 2 bladerkolommen. iPad: tabbalk of zijbalk, carrousel (480 pt) tot 860 pt breed en daarboven drie hero-kaarten naast elkaar, 4 tot 8 tegels per plank (140 tot 166 pt), albumkop met tegel links (200 pt), 3 tot 4 bladerkolommen. Mac: zijbalk en Settings-venster, 3 tot 8 tegels (geen muiswiel: "Toon alles" is de route), lijsten `.inset`; leesbare breedte 720.

**Toegankelijkheid.** VoiceOver: plankkop is een kop; tegel, rij en dagkaart zijn een element met label "titel, ondertitel, waarde"; tegelsymbolen verborgen; bedragen met teken en woord. Dynamic Type: maten schalen tot 1,5x (`@ScaledMetric`), `minimumScaleFactor` alleen in `BigAmount`, bij toegankelijkheidsformaten staat de hero onder elkaar en een plank als verticale lijst (tegels hoogstens 320 pt, titels hoogstens 2 regels bij gewone tekst). Verlaag beweging: geen animatie bij stipwissel, achtergrondwissel of drukstatus. Verhoog contrast: HC-kleuren, `onTileSecondary` 92%, geen tint, rand om tegels. Mac: `.help` op pillen en menu's. Contextmenu's op tegels: pot (Storten, Opnemen, Bewerken), belegging (Waarde bijwerken, Bewerken); verwijderen blijft op de detailpagina en als swipe, want elke actie moet ook zonder gebaar bereikbaar zijn.

**Componenten.** Alle bestaande componenten blijven (`Card`, `LinkCard`, `SectionHeader`, `NavigationRow`, `BigAmount`, `StatTile`, `FigureRow`, `AmountRow`, `SymbolBadge`, `IconButton`, `ActionButton`, `ActionLink`, `ActionGroup`, `EmptyHint`, `NoticeCard`, `MonthBar`, `PeriodPicker`, `ProgressMeter`, `SegmentedMeter`, `RowActions`, `Fields`, `Charts`, sheets), behalve deze, die in pakket 3 vervallen: `searchToolbarButton`, `PeriodControl`, `GlassBlock`, `LinkedBlock`, `Chip*`, `ProgressRing`, `ProgressBar`, `SegmentBar`, `MeshBackground`, `Theme.olive*`, `Theme.flow*`, `Theme.buttonHeight`, `glassCard`, `glassButton`, `TabPressStyle`, `TabAmountLink`, de oude tabroots en hun kaarten. `GlassSurface` blijft ongebruikt in `Glass.swift` (B15).

## 3. Pagina voor pagina

Bedragen en teksten komen uit de bronnen van de kaarten die ze vervangen (1.5): de bouwer kopieert de aanroep en past de vorm aan. Bestanden onder 400 regels, elke `ViewBuilder` onder 10 kinderen (`precheck.sh`).

| Scherm | Bestand (pakket) | Opbouw |
|---|---|---|
| **Home** | `Pages/Home/HomeTab.swift`, `HomeHero.swift`, `HomeShelves.swift`, `HomeWelcome.swift` (2A) | `PageScaffold(title: "Home", large: true, fullBleed: true)` met `.environment(\.backdropHue, heroHue)` en `.profileToolbarItem()`; meldingen met marge; `HeroCarousel(ids: ["distribute", "wealth", "balance"])`; planken in de volgorde van `blockIDs(for: .overview)` (geen `OrderedBlocks`: het ordenmenu zit alleen op de kop, via `orderID`). |
| Hero 1, 2, 3 | idem | **1** `hue: .olive`, eyebrow "\(MoneyLabels.remaining) in \(Fmt.month(now))": `BigAmount(font: Theme.heroAmount, color: Theme.onTile)`, notities van `OverviewHeroNotes` in `onTileSecondary` met waarschuwingssymbool, `PillLink("Verdelen", style: .onTile, destination: .distribute, showsCurrentMonth: true)`. **2** `.slate`, `MoneyLabels.netWorthEnd(of:)`: bedrag, `TrendChart(size: .compact, showsAxes: false)` in `.heroPanel()`, drie `PillLink`s ("Bank € x" `.bank`, "Potten € x" `.pots`, "Beleggingen € x" `.portfolio`), notitie bij onbekend banksaldo. **3** `.terracotta`, "Saldo vandaag": `bankBalanceNowIfKnown`, "Volgende betaling: naam, dag, min € x" uit `UpcomingDaysWindow.nextPayment` (nieuw, 2A: eerste `DayEvent` met `kind == .expense`, `bankAmount < 0`, `isPlanned`, binnen 60 dagen; anders "Geen betalingen gepland"), pillen "Dag voor dag" (`.cashflow`, huidige maand) en "Saldo bijwerken" (`BankActionSheet(.balance)`). |
| Planken | `HomeShelves.swift` (2A) | Per plank `showAll`, `showAllLabel` ("Toon alle spaarpotten" enz.), `orderID` (`upcoming`, `pots`, `invest`, `goals`, `tools`) en menu volgens B17. **Komende dagen** (`wide`, `showAll: .cashflow`, subtitel "d MMM t/m d MMM"): per drukke dag een `ShelfCard` met weekdag en datum, "Vandaag", hoogstens 3 gebeurtenissen (titel, bedrag met teken) en het saldo aan het eind van de dag; geen drukke dag: een kaart met de bestaande tekst. **Spaarpotten** (subtitel "Totaal € x"): `PosterCard(symbol: pot.symbol, hue: forIndex(pot.colorIndex), title:, value: saldo vandaag, progress: potProgress, destination: .pot(id))` met contextmenu; lege plek "Kies pot" of "Nieuwe pot" (zoals `FavoriteSlotTile`); geen potten: `EmptyHint` in een `ShelfCard`. **Beleggingen** (subtitel "Waarde € x"): eerst een samenvattingstegel (`ShelfCard(hue: .slate)` met waarde, `GainBadge` en de `PortfolioTrend`-sparklijn over 6 maanden als `TrendChart(size: .compact, showsAxes: false, nonNegative: true)` in `.heroPanel()`), dan per `homeHoldings()` een `PosterCard(symbol: kind.symbol, hue: forIndex(kind.colorIndex), subtitle: soort en "geschat", value: waarde, destination: .holding(id))` met contextmenu. **Doelen**: `PosterCard(symbol: goal.kind.symbol, hue: .mustard, subtitle: haalbaarheid, value: percentage, progress:, destination: .goal(id))`, laatste tegel "Spaardoel berekenen" (`.savingsGoal`), zonder doelen "Maak je eerste doel". **Hulpmiddelen**: vier `PosterCard`s met tint uit `PageCatalog` en de ondertitel van de oude kaart (uurloon of "Vul je uurloon in", "Voor <doel>" en beste winst, "Over 10 jaar € x", "n maanden gedekt"). |
| **Bibliotheek** | `Pages/Library/LibraryTab.swift`, `LibraryFigures.swift` (2B) | `ListScaffold(title: "Bibliotheek", large: true)` + `.profileToolbarItem()`; een `Section` per `LibrarySection` met `MediaRow`s (1.4); dan `Section("Recent")`. |
| **Zoeken** | `Pages/Search/SearchTab.swift` (2B) | `PageScaffold(title: "Zoeken", large: true)` + `.searchable(text:isPresented:prompt: "Zoek in MyBuddy")` + `.onChange(of: router.searchRequest) { isSearching = true }` + `.profileToolbarItem()`; zonder tekst een `LazyVGrid` met `BrowseTile`s (Instellingen opent `.settingsRoot`); met tekst per `SearchGroup` een `Card` met `MediaRow`s. |
| Maandoverzicht, Hulpmiddelen | `Pages/Month/FlowPage.swift`, `Pages/ToolsPage.swift` (2B) | `PageScaffold(title: "Maandoverzicht")`: `MonthBar()` en daaronder de inhoud van `MonthFlowCard` (kopie `FlowContent`, zonder blokvolgorde). `ListScaffold(title: "Hulpmiddelen")`: vier `MediaRow`s met uitlegregel (de `PlanningFootnote`-teksten van de oude kaarten). |
| Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag, Salaris | `Pages/Month/*`, `Pages/Bank/*`, `CashflowPages.swift` (2D) | Opbouw ongewijzigd; controle op nieuw uiterlijk, geen hardgecodeerde radii, termen volgens 1.6. |
| Spaarpotten, Beleggingen | `Pages/PotPages.swift`, `Pages/PortfolioPages.swift` (2C) | Bestaande `ListScaffold` met summary-sectie; `PotRow` en `HoldingRow` worden `MediaRowLabel` (tegel in pot- of soorttint, naam, saldo of waarde, voortgang of `GainBadge`), `rowActions` ongewijzigd; menu "Kies potten voor Home…" resp. "Kies beleggingen voor Home…"; `router.go(.bank)` en `router.go(.salary)` worden `router.open`. |
| **Spaarpot** (album) | `Pages/Saving/PotDetailPage.swift` (2C) | `.environment(\.backdropHue, forIndex(pot.colorIndex))`; eerste rij `AlbumHeader(symbol: pot.symbol, title: pot.name, subtitle: "Spaarpot" + doel, figureLabel: "Saldo vandaag", figure: saldo, progress: potProgress, facts: [rente, inleg], pills: Storten (.prominent), Opnemen, Bewerken).albumHeaderRow()`; dan `PotUpcomingSection`, `PotHistorySection` (tracklijst met swipe, contextmenu en kleine tegel), de grafiek als eigen sectie "Verloop" (het `chartRow` uit `PotBalanceSection`), `PotContributionSection`, `PotDateBalanceSection`, `PotDeleteSection`; werkbalkmenu "Meer" blijft. |
| **Belegging** (album) | `Pages/Saving/HoldingDetailPage.swift` (2C) | `AlbumHeader(symbol: kind.symbol, title: naam, subtitle: soort en ticker, figureLabel: "Waarde", figure: waarde, facts: ["Belegd sinds …", inleg], pills: bestaande acties (Waarde bijwerken `.prominent`, Bewerken)) { GainBadge }`; daarna de bestaande secties (grafiek ongewijzigd, samenvatting, uitgangspunten, inleg, waarde-updates als tracklijst met swipe, verwijderen). |
| Doelen, **Doel** (album) | `Pages/GoalPages.swift` (2D) | `GoalListRow` wordt `MediaRowLabel` (tegel `goal.kind.symbol`, mustard, naam, haalbaarheid, percentage, voortgang); rijen "Spaardoel berekenen" en "Noodbuffer" als `MediaRow`. `GoalProgressHeader` wordt `AlbumHeader` (tegel, naam, soort, kerngetal, voortgang, pillen Bewerken en Versnellers); de bestaande kaarten eronder blijven. |
| Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck, Spaardoel berekenen | `BufferPages`, `AcceleratorPages`, `ProjectionPage`, `PurchasePages`, `SavingsGoalPages`, `Planning/*` (2D) | Opbouw ongewijzigd; `DestinationView` zet de tint. |
| Instellingen en Account | `Pages/SettingsView.swift`, `Pages/Settings/*` (2D) | `SettingsView` wordt een gepushte pagina (grote titel, stapel van de tab); inhoud en volgorde ongewijzigd; `LayoutPage` toont automatisch alleen "Home". |

## 4. Werkpakketten, golven en eigendom

Volgorde: **golf 1 (pakket 1) -> golf 2 (2A, 2B, 2C, 2D tegelijk) -> golf 3 (pakket 3)**. Elk pakket laat na elke stap alles compileren. Een fout in andermans bestand laat je staan en meld je onder WIRING (`own-check.sh --owner <pad>`). Gedeelde werkboom: de coördinator commit per pakket. Golf 2 verwijdert niets uit andermans bestanden en laat de handtekeningen staan van `PotEditSheet(pot:)`, `HoldingEditSheet(holding:)`, `FavoritePotsSheet()`, `FavoriteHoldingsSheet()`, `BankActionSheet(action:)`, `PotEntrySheet(pot:action:)`, `ValueUpdateSheet`, `GoalEditSheet`; opruimen is alleen aan pakket 3.

**Regels voor elke bouwer.** Lees par. 0 en 2 en de bestanden van je pakket. Nieuwe typen met nieuwe namen. Geen `.system(size:)`, `.caption2`, `.rounded`; geen `Color(hex:)`, `.white`, `.black` buiten `Theme.swift` (gebruik `Theme.onTile`). Liever `containerRelativeFrame` of `onGeometryChange` dan `GeometryReader`. iOS 26-API's achter `#available(iOS 26.0, macOS 26.0, *)`, alleen-iOS-API's achter `#if os(iOS)`. Teksten volgens 1.6. Elke nieuwe view een `#Preview` (gevuld, donker, grote tekst, leeg) in een `*Previews.swift`. `docs/design/precheck.sh` op elk aangeraakt bestand.

### Pakket 1 - Fundament en schil (golf 1, een bouwer)

0. Stap 0 van 2.2 (stubs) en een basislijn: `run-all.sh` 0 fouten, `swift test` 1736 groen.
1. Foundation-only en tests: `TilePalette.swift`, `ShelfMetrics.swift`, `Navigation/PageCatalog.swift` (symlinks in `CoreTests/Tests/MyBuddyCoreTests` zoals bij `NavigationModel.swift`), `NavigationModel.swift`, `SearchIndex.swift`, `BlockOrderMigration.swift` (blokken van `.overview`, `allCases == [.overview]`; de oude cases blijven tot pakket 3). Tests herschrijven en uitbreiden: `NavigationRulesTests`, `SearchIndexTests` (uitputtend over `Destination` en `SettingsPage`, `grouped`, `hue`), `BlockOrderMigrationTests` (nieuwe blokken, `wealth` in een opgeslagen volgorde, oude migratietests blijven); nieuw `TilePaletteTests` (alle waarden van 2.1 voor alle tinten, normaal en hoog contrast, achtergrond licht en donker, `forIndex`), `ShelfMetricsTests`, `PageCatalogTests` (5.3). Minimaal 1736 tests.
2. Ontwerpsysteem: `Theme.swift` (`AppDomain.overview.title` wordt "Home"), `Components.swift` (scaffolds, `DestinationLink`, capsule-knoppen, `#if os(iOS)` voor `.large` en `.onScrollDown`), nieuw `Backdrop.swift`, `Tiles.swift`, `Shelf.swift`, `Hero.swift`, `Rows.swift`, `Album.swift`, `Pills.swift`, `Profile.swift`; `ComponentGallery.swift` toont elke nieuwe component, ook op toegankelijkheidsformaat.
3. Schil: `Router.swift` (1.2; compat `homePath`, `savingsPath`, `toolsPath`, `showSettings` weg; op de Mac roept `open` met `.settingsRoot` of `.settings` `go` aan), `RootView.swift` (een `TabView`, geen badge), `TabRoots.swift`, `TabStack.swift`, `AppCommands.swift` (Cmd+1 t/m Cmd+3, Cmd+F, op iPad een Cmd+komma-commando naar `.settingsRoot`, bij voorkeur `CommandGroup(replacing: .appSettings)`), `DestinationView.swift` (nieuwe cases; `.environment(\.backdropHue, PageCatalog.info(destination)?.hue ?? .olive)`), `DebugLaunch.swift` (tabs `home`, `library`, `search` met aliassen `overview` -> home en `month`, `saving`, `planning`, `savings`, `tools` -> library; `-mybuddy-open` kent ook `flow`, `tools`, `settings`, `home`, `library`; nieuw `-mybuddy-hero 0|1|2`; `-mybuddy-settings` pusht `.settingsRoot`).
4. Tijdelijke wortels (tot golf 2): `HomeTab` (rendert `OverviewTab()`), `LibraryTab` (`NavigationRow` per `PageCatalog.library`), `SearchTab` (zoekveld, platte resultaten), `FlowPage` (`MonthFlowCard` in een `PageScaffold`), `ToolsPage` (vier `NavigationRow`s), allemaal met `.profileToolbarItem()`: elke pagina blijft bereikbaar.
5. Scripts: `design-checks.sh` aanpassen (5.2) en kopiëren naar `scripts/`; schrijf `docs/design2/contract-check.sh`, `keep-check.sh`, `own-check.sh` (5.3, eigendomsblok).

*Klaar*: `run-all.sh` 0 fouten en 0 `ONBEWAAKT`; `swift test` minimaal 1736 groen; `design-checks.sh`, `contract-check.sh 1`, `keep-check.sh` PASS; elke bestemming bereikbaar via de Bibliotheek; gallery compleet. *Niet aanraken*: `App/Core`, `Cloud`, `Auth`, `Charts.swift`, `ChartModels.swift`, `Fields.swift` (behalve compileerfix), `Pages/` behalve de vijf wortels.

### Pakket 2A - Home (golf 2)

Vervang de tijdelijke `HomeTab` (par. 3 en 1.3): `HomeTab.swift`, `HomeHero.swift`, `HomeShelves.swift`, `HomeWelcome.swift`, `HomePreviews.swift`. Voeg `UpcomingDaysWindow.nextPayment(in book: LedgerBook, today: Date) -> (day: DayTotals, event: DayEvent)?` toe aan `UI/CashflowDisplay.swift` met tests in `CashflowDisplayTests.swift` (geen betaling, morgen, alleen inkomsten, grens 60 dagen). Gegevens: exact de aanroepen van de oude kaarten (alleen lezen: `Tabs/OverviewParts.swift`, `Saving/FavoriteCards.swift`, `FavoriteTiles.swift`, `Bank/UpcomingDays.swift`, `GoalPages.swift`, `BufferPages.swift`, `AcceleratorPages.swift`, `ProjectionPage.swift`, `PurchasePages.swift`); kopieer de plumbing (accountsleutel, `@AppStorage`) naar eigen typen met prefix `Home`. *Klaar*: alles van 1.3 werkt met voorbeelddata, lege start en zonder banksaldo; elke plank heeft een lege staat en alle oude menu-acties; backdrop volgt de hero; VoiceOver-labels; previews. *Niet aanraken*: alles buiten `Pages/Home/`, `UI/CashflowDisplay.swift` en zijn test.

### Pakket 2B - Bibliotheek, Zoeken, Maandoverzicht, Hulpmiddelen, Recent (golf 2)

Vervang `LibraryTab`, `SearchTab`, `FlowPage`, `ToolsPage` (par. 3); schrijf `UI/RecentActivity.swift` met symlink en `RecentActivityTests` (leeg, volgorde, `.opening` weg, overboeking eenmaal, toekomst weg, limiet). Waarden uit de bronnen van de oude kaarten (alleen lezen: `Tabs/MonthLinkCards.swift`, `Tabs/MonthFlowCard.swift`, `Saving/FavoriteCards.swift`). *Klaar*: elke rij van 1.4 met de juiste waarde; maandrijen openen op de huidige maand; Zoeken toont tien tegels en gegroepeerde resultaten, Cmd+F opent het veld; `.flow` bevat alles van `MonthFlowCard`. *Niet aanraken*: alles buiten `Pages/Library/`, `Pages/Search/`, `Pages/ToolsPage.swift`, `Pages/Month/FlowPage.swift`, `UI/RecentActivity.swift` en zijn tests.

### Pakket 2C - Sparen: lijsten en albumpagina's (golf 2)

Spaarpot en Belegging als album, lijsten met `MediaRowLabel`, teksten "Kies potten voor Home…", "Kies beleggingen voor Home…", "Spaarpotten op Home", "Beleggingen op Home" (`FavoriteSheets.swift`), `router.go` -> `router.open` in `PortfolioPages.swift`; secties, sheets, `rowActions` en grafieken blijven. *Klaar*: beide detailpagina's tonen `AlbumHeader` met alle oude acties (ook in het werkbalkmenu); elke oude sectie staat er nog. *Niet aanraken*: `Home/`, `Library/`, `UI/` (behalve `PotDisplay.swift`, `SavingsDisplay.swift`), sheet-handtekeningen, `FavoriteCards.swift` en `FavoriteTiles.swift` (2A leest ze, pakket 3 verwijdert ze).

### Pakket 2D - Doelen, Plannen, Instellingen, restyle (golf 2)

Doelen als `MediaRowLabel`-lijst en Doel als album (par. 3); controleer elke pagina onder `Month/`, `Bank/`, `Planning/`, `Settings/` en de rekenpagina's op het nieuwe uiterlijk (geen hardgecodeerde radii of achtergronden, geen verboden termen, `SettingsView` als gepushte pagina) en pas alleen styling en teksten aan. *Klaar*: Doelen en Doel volgens 3; `keep-check.sh` PASS; `git diff -- App/Core` leeg. *Niet aanraken*: alles van 2A, 2B, 2C, `UI/`, `Navigation/`.

### Pakket 3 - Opruimen en documentatie (golf 3, een bouwer)

(1) Verwijder `Pages/Tabs/` (verplaats wat nog gebruikt wordt, zoals `TabNote`, `TabWarning`, `OverviewCheckBanner`, naar de plek van hun gebruiker met een nieuwe naam), alle samenvattingskaarten zonder gebruikers (`HomePotsCard`, `HomeHoldingsCard`, `UpcomingDaysCard`, `FavoriteTileGrid` met tegels en elke `*SummaryCard`) en alle compat (2.5; `BlockPage.month/.saving/.planning/.home/.savings/.tools`, `blockOrderToolbar`; de migratie voor oude sleutels blijft); per verwijdering `grep` op nul gebruikers en `run-all.sh` na elke groep. (2) `design-checks.sh --final`. (3) `README.md` (drie tabs, profielknop, nieuwe schermen), `system_architecture.md` (navigatie, ontwerpsysteem v2, `PageCatalog`), `docs/v3-spec.md` (blok-id's, bestemmingen). (4) `scripts/ci-screenshots.sh`: tabs `home`, `library`, `search`; pagina's `flow`, `tools`, `settings`; `-mybuddy-hero 0|1|2`; oude opnamen met nieuwe tabnamen; iPad en donker. (5) Bovenaan `docs/design/plan.md` een verwijzing naar dit plan. *Klaar*: `run-all.sh` 0 fouten, `swift test` groen, `design-checks.sh --final`, `contract-check.sh final`, `keep-check.sh --final`, `own-check.sh 3` zonder fouten, CI groen.

### Eigendom per golf

<!-- EIGENDOM-BEGIN -->
```text
# pad (meest specifiek wint) | golf1 | golf2 | golf3   ("-" = niemand, "C" = de coördinator)
# Verwijderd in pakket 3 (dus zonder regel): App/Pages/Tabs/, App/Navigation/LegacyTabNames.swift, App/Pages/Saving/FavoriteCards.swift,
# App/Pages/Saving/FavoriteTiles.swift, App/Pages/Saving/SavingSupport.swift en App/Pages/Bank/UpcomingDays.swift.
App/ - - 3
App/UI/ 1 - 3
App/UI/CashflowDisplay.swift - 2A 3
App/UI/PotDisplay.swift - 2C 3
App/UI/SavingsDisplay.swift - 2C 3
App/UI/RecentActivity.swift - 2B 3
App/Navigation/ 1 - 3
App/RootView.swift 1 - 3
App/Router.swift 1 - 3
App/MyBuddyApp.swift 1 - 3
App/Debug/ 1 - 3
App/Pages/ - 2D 3
App/Pages/DestinationView.swift 1 - 3
App/Pages/Home/ 1 2A 3
App/Pages/Library/ 1 2B 3
App/Pages/Search/ 1 2B 3
App/Pages/ToolsPage.swift 1 2B 3
App/Pages/Month/FlowPage.swift 1 2B 3
App/Pages/Saving/ - 2C 3
App/Pages/PotPages.swift - 2C 3
App/Pages/PortfolioPages.swift - 2C 3
CoreTests/ 1 - 3
CoreTests/Tests/MyBuddyCoreTests/CashflowDisplayTests.swift - 2A 3
CoreTests/Tests/MyBuddyCoreTests/RecentActivity.swift - 2B 3
CoreTests/Tests/MyBuddyCoreTests/RecentActivityTests.swift - 2B 3
CoreTests/Tests/MyBuddyCoreTests/SavingAlbumTextTests.swift - 2C 3
scripts/ 1 - 3
docs/design/ 1 - 3
docs/design2/ 1 - 3
docs/design2/plan.md C C 3
```
<!-- EIGENDOM-EINDE -->

`docs/design2/own-check.sh <golf> [--base <commit>]` (pakket 1 schrijft het) leest dit blok, loopt over `git diff --name-only <base>` en ongevolgde bestanden, meldt per eigenaar het aantal bestanden en elk bestand waarvan de eigenaar in die golf "-" is (een pad zonder regel telt als "-" in golf 1 en 2 en als 3 in golf 3); `--owner <pad> <golf>` zegt wie een bestand bezit. Een golf-2-pakket mag nieuwe bestanden in zijn eigen mappen en nieuwe testbestanden in `CoreTests` met unieke naam aanmaken, nooit bestaande testbestanden van een ander wijzigen.

## 5. Verificatie

### 5.1 Poorten per golf (elke bouwer, voor hij klaar meldt)

1. `/tmp/ctl-all/run-all.sh` (50 s): `TOTAAL fouten (alle varianten): 0` en geen `ONBEWAAKT`; tijdens het werk `run-all.sh quick` (iOS, 26 s). Fouten in andermans bestand: melden, niet repareren (bestandsnamen staan platgeslagen in `errors.txt`, bijvoorbeeld `Pages_Home_HomeTab.swift`).
2. `cd /home/user/MyBuddy/CoreTests && swift test --scratch-path /tmp/sb-NAAM`: groen, minimaal 1736 tests.
3. `docs/design/precheck.sh <aangeraakte bestanden>` en `docs/design/design-checks.sh` (golf 3: `--final`) PASS.
4. `docs/design2/contract-check.sh <golf>`, `keep-check.sh`, `own-check.sh <golf>` (5.3).
5. **CI**, de enige echte compiler: de coördinator pusht na elke golf naar een `claude/**`-tak; `.github/workflows/ci.yml` bouwt iOS en macOS, draait de tests en maakt screenshots; een fout gaat met `own-check.sh --owner <pad>` naar de eigenaar.

### 5.2 Aanpassingen in `design-checks.sh` (pakket 1)

- `Home` uit de verboden termen (B2); nieuw: de letterlijke `"Overzicht"` 0 (niet-final uitgezonderd `Pages/Tabs/`). `.sheet(` max 16 blijft, niet-final met uitzondering van `Pages/Tabs/`, `Saving/FavoriteCards.swift`, `Bank/UpcomingDays.swift` (Home krijgt er drie nieuwe, de eindstand is weer 16).
- "Wit als voorgrond" uitbreiden met zwart: `Color.white`, `Color.black`, `.white`, `.black` buiten `Theme.swift` verboden. "Glas op inhoud" ongewijzigd (B15).
- Nieuw: `Tab(value: AppTab.search, role: .search` min 1; `Tab("Instellingen"` 0; `profileToolbarItem()` min 3; `Shelf(` min 5; `AlbumHeader(` min 3; `HeroCarousel(` min 1; `BackdropGradient(` alleen in `Backdrop.swift` en `Components.swift`; `scrollTargetBehavior` alleen in `Shelf.swift` en `Hero.swift`; `destination.tab` en `AppTab.(overview|month|saving|planning|settings)` 0; met `--final` ook `searchToolbarButton`, `PeriodControl`, `TabPressStyle` en `Pages/Tabs/` 0.
- `docs/design/contract-check.sh` en `ownership-check.sh` (oud contract en eigendomsblok) niet meer draaien; `docs/design2/` vervangt ze.

### 5.3 Overige controles

- **`PageCatalogTests`**: elke `Destination` staat in de catalogus, is een wortel of heeft een ouder (`parents`; `.settings(_)` via `.settingsRoot`); elke niet-wortel is via `reachableFrom` zonder lus bereikbaar vanaf een Bibliotheekrij of wortel; Bibliotheek 13 rijen in 3 groepen.
- **`keep-check.sh [--final]`**: elke sleutelaanroep van de oude kaarten heeft een gebruiker in `App/Pages` (met `--final` zonder `Pages/Tabs/`): `netWorth(at:`, `NetWorthTrend.model`, `MonthBoard(`, `periodSummary(`, `StackedBarModel.months`, `income(in:`, `expenseOverview(`, `monthFigures(`, `bankBalanceNowIfKnown`, `LedgerBook(`, `UpcomingDaysWindow.`, `homePots()`, `homeHoldings()`, `PortfolioTrend.model`, `FavoritePotsSheet(`, `FavoriteHoldingsSheet(`, `GoalMath.hubSubtitle`, `BufferCalc.summary`, `accelerators(for`, `Growth.projection`, `PurchaseCalc.resolvedWage`, `BlockOrderSheet(`, `SyncAttentionBanner(`, `CashflowCheckBanner(`, `loadSampleData()`, `refreshPrices(force: true)`, `PotsGoalProgress(`, `savedTowardGoals`.
- **`contract-check.sh`**: elk symbool uit 2.3 en 2.4 bestaat met zijn initializer (`sig`-regels, model: het oude script). **Geen rekenwijziging**: `git diff --stat <basis> -- App/Core CoreTests/Sources` is leeg. **Opgeslagen gegevens**: een test in `BlockOrderMigrationTests` decodeert een oud `blockOrder` (`home`, `savings`, `tools`, `overview` met `wealth`, `month`) en controleert `orderedBlocks(for: .overview)`.

### 5.4 Parallel bouwen in een gedeelde werkboom (golf 2)

De typecontrole leest `/home/user/MyBuddy/App` en schrijft naar `/tmp/ctl-all/work`; parallelle bouwers zouden elkaars logboeken overschrijven. Elke bouwer maakt een eigen kopie van het draaiboek (proef: 26 s, 0 fouten op `HEAD`):

```bash
N=/tmp/ctl-NAAM; S=/tmp/ctl-all; mkdir -p $N
for f in make.sh check.sh run-all.sh tests.sh strip_preview.py; do sed "s#/tmp/ctl-all#$N#g" $S/$f > $N/$f; done
chmod +x $N/*.sh; ln -sfn $S/out $N/out; ln -sfn $S/stubs $N/stubs; ln -sfn $S/tools $N/tools
$N/run-all.sh quick     # uitvoer in $N/errors.txt
```

### 5.5 Handmatig (CI-screenshots of toestel)

iPhone SE en Pro Max, iPad 13, Mac 640, 900 en 1366 pt; licht en donker; AX3; Verhoog contrast, Verlaag transparantie, Verlaag beweging; VoiceOver over hero, plank en albumpagina; iOS 18 en 26 (zoekveld, glas om de profielknop, krimpende tabbalk); Mac-zijbalk met zoektab; Cmd+1 t/m Cmd+3, Cmd+F, Cmd+komma.

## 6. Risico's en wat niet verandert

**Niet veranderd**: `App/Core` en `CoreTests` (rekenlogica), back-up, import, export, synchronisatie en Firebase, bedragen en formules, grafieken (`ChartModels`, `Charts`), de inhoud van Instellingen en Account, per-account bewaarde keuzes, het opslagformaat (`homePotIDs`, `homeHoldingIDs`, `blockOrder`), `Tests/AppTests`.

| # | Risico | Aanpak |
|---|---|---|
| 1 | De typecontrole is een nabootsing: wat ontbreekt geeft een fout, wat te mild staat wordt gemist. | Alleen API's uit de "aanwezig"-lijst (2.2); `scrollTargetBehavior` met de hand toegevoegd; de CI beslist; valt die modifier af, verwijder hem (carrousel zonder snappen). |
| 2 | iOS 26-gedrag niet zichtbaar: zoekveld bij `Tab(role: .search)`, glas om `ProfileButton`, krimpende tabbalk boven een kleurverloop. | CI-screenshots; `.searchable` staat in de zoektab, bij een fout naar de `TabView` verplaatsen; `ProfileButton` heeft geen eigen achtergrond. |
| 3 | `containerRelativeFrame` binnen `safeAreaPadding` trekt de marge misschien niet af (patterns par. 6). | Hoogstens 10% bredere of smallere tegels; terugval `contentMargins`. |
| 4 | Instellingen is niet meer 1 tik vanaf elke diepte (B4). | Bewust; stip, melding, Cmd+komma, Zoeken. Een vierde tab terugzetten is een kleine wijziging in `RootView`. |
| 5 | Mac zonder horizontaal scrollen: planken lastig met een muiswiel. | Vanaf 860 pt drie hero-kaarten naast elkaar; "Toon alles"; pijlknop per plank later. |
| 6 | Tegel op de donkere kaart haalt 2,65:1. | Decoratie; tekst op de tegel 6,4:1; Verhoog contrast geeft een rand. |
| 7 | In golf 2 staat de plumbing van de oude kaarten en van Home dubbel. | Core-aanroepen identiek (`keep-check.sh`); pakket 3 verwijdert de oude. |
| 8 | Herschreven navigatietests dekken minder dan de oude; "Spaardoel berekenen" heeft geen Bibliotheekrij. | Elke oude test krijgt een equivalent of een reden, minimaal 1736; `PageCatalogTests` bewaakt de bereikbaarheid (Doelen, plank Doelen, Hulpmiddelen, Zoeken). |
