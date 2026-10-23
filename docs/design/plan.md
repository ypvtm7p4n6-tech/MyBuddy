# Ontwerpplan MyBuddy: Apple-richtlijnen, eenvoud, Instellingen als pagina, werkende grafieken

Peildatum 20 oktober 2026, `HEAD` 6140902. De code in `App/` en `CoreTests/` is gelijk aan die van ca0c945 (sindsdien is alleen `docs/design/` veranderd). **Dit is de herziene versie** na de kritiek in `critique.md` (2 blockers, 7 majors, 9 minors): onderaan staat onder "Herzieningen" wat is overgenomen, wat is aangepast en wat bewust niet is overgenomen. Het plan is gebaseerd op `hig-notes.md` (regel-id's zoals `GLS-1`), `audit.md` (id's zoals `N1`, `E4`) en `charts.md` (id's zoals `G1`, `C1`), en op de kernbestanden zelf (`RootView`, `Router`, `Components`, `Glass`, `Theme`, `SettingsView`, `HomeView`, `SavingsView`, `ToolsView`, `BlockOrder`, `Charts`, `Fields`, `CloudViews`, `BackupUI`, `Invest`, `CashflowPages`, `PortfolioPages`). Er is niets in `App/` of `CoreTests/` aangepast. SwiftUI kan hier niet compileren: wat hieronder over views staat, is ontwerp, geen waarneming. Het enige echte compileeroordeel is de CI (par. 6.1 en 7.1).

**Hoe te lezen.** Sectie 2 en 3 zeggen wat de gebruiker straks ziet. Sectie 4 is het **contract**: exacte namen en handtekeningen waar de bouwers op coderen. Sectie 6 verdeelt het werk, in golven die elk compileerbaar eindigen; elk bestand heeft precies een eigenaar (blok in par. 6.7, met een script gecontroleerd). Sectie 7 bevat de poorten en de scenario's. Regelnummers gelden voor `HEAD`; zoek op het patroon.

**De vier wensen van de gebruiker en waar ze zijn opgelost**

| Wens | Antwoord | Sectie |
|---|---|---|
| Ontwerp volgt de Apple HIG in de hele app | Native `TabView`, systeemachtergronden en -kaartkleuren, glas alleen van het systeem (tabbalk, werkbalk, sheets), Dynamic Type, raakdoelen per platform (44 pt iOS, 28 pt Mac), contrast 4,5:1, Reduce Motion en Transparency, `List` met swipe-acties, `ContentUnavailableView`, Mac-menubalk en `Settings`-scene | 1, 4 |
| Eenvoudiger: onderdelen makkelijk vinden en uit elkaar houden | 5 tabs (4 op de Mac) met elk een eigen domein: Overzicht is "nu", Maand is "door de tijd"; vaste paginaopbouw, maximaal 6 blokken per pagina, een woord per begrip, een plek per functie, zoeken vanaf elke tab | 2 |
| Instellingen: account los, hele pagina in plaats van pop-up | Tab Instellingen (iPhone, iPad) of `Settings`-venster (Mac) met Account als eerste rij naar een eigen pagina; 6 korte groepen; geen enkele sheet | 3 |
| Alle grafieken werken en volgen de invoer (Beleggingen) | Een Core-fix (afgeleid beginpunt uit "Totaal ingelegd" en "Belegd sinds"), een modellaag met lege staten, vier componenten, 17 grafiekplekken gelijkgetrokken, een reproduceerbaar demo-scenario | 5 |

**Wat de gebruiker eerder expliciet vroeg en dat blijft**: drie zelfgekozen spaarpotten en vier beleggingen op de eerste tab (K9), volgorde van de blokken (K8), Dag voor dag en de maandsluiting van bank en spaarpotten (K15), percentage-inleg, terugkerende regels met reikwijdte, salaris per N weken of dagen, versnellers, Aankoopcheck, Excel-import, Firebase-synchronisatie (par. 2.5 en 3.2 wijzen voor elke functie de plek aan).

## 0. Besluitenlijst

Alles hieronder is besloten; de bouwers stellen geen vragen maar volgen dit. K1 t/m K14 zijn uit de eerste versie (K2, K3, K5, K6, K7, K8 aangepast, K9 vervangen door K9a t/m K9e); K15 t/m K21 zijn nieuw uit de kritiek.

| # | Besluit | Reden |
|---|---|---|
| K1 | **Native `TabView` met `.tabViewStyle(.sidebarAdaptable)`**; de eigen `GlassTabBar` en `barBackdrop` verdwijnen. | TAB-5, LAY-8: tabbalk op iPhone, zijbalk op iPad en Mac, niets onderaan het Mac-venster; glas komt gratis van het systeem. |
| K2 | **5 tabs op iPhone en iPad: Overzicht, Maand, Sparen, Plannen, Instellingen. Op de Mac 4 tabs (zonder Instellingen, zie K3).** | Indeling naar gebruik (audit 4.4): wat staat er nu, elke maand, af en toe, zelden, beheer. Vijf is het maximum zonder "Meer"-tab. **Afweging tegen TAB-3** ("zo weinig tabs als nodig"): het alternatief, 3 tabs en een Instellingen-knop op elke tabwortel, laat Instellingen op elke diepere pagina verdwijnen en dwingt Plannen (5 onderdelen) in Maand of Sparen. Daarom verruimen we TAB-3 bewust tot: elke tab is een eigen domein en is vanaf elke diepte met 1 tik bereikbaar. |
| K3 | **Instellingen is een tab op iPhone en iPad en het `Settings`-venster op de Mac** (Cmd+komma, App-menu); geen knop in de balk en geen zijbalk-item op de Mac. | iOS: een tab blijft op elke diepte zichtbaar; het is navigatie, geen actie (TAB-1). Mac: SID-4, SET-5 en MAC-3 zetten instellingen in het App-menu en niet onderaan de zijbalk; de vijfde `Tab` staat daarom onder `#if !os(macOS)` (geen onzekere API nodig). Een diepe link naar een instellingenpagina (`router.go(.settings(_))`) opent op de Mac het `Settings`-venster op die pane (`openSettings()`, macOS 14+). |
| K4 | **Account blijft verplicht om de app te openen**, maar staat los van de rest: eigen pagina, geen sheet. | De HIG (ACT-1) wil dit anders, maar een lokaal account heeft een eigen gegevensmap (`AuthStore.storageURL(for:)`). Migreren raakt de gegevens van de gebruiker en valt buiten de vraag. Staat onder "Niet in deze ronde" (par. 8.3). |
| K5 | **Inhoudsblokken worden gegroepeerde kaarten** (`Card`, systeem-kaartkleur op een licht olijf getinte achtergrond) en `List`. Liquid Glass komt alleen van het systeem (tabbalk, werkbalk, sheets, menu's); de eigen code tekent **geen enkel glas**, ook niet in een grafiek: de annotatie bij een gekozen punt is `Theme.card` met een rand. | GLS-1, GLS-2: 92 `GlassBlock` plus 86 glazen knoppen is glas op glas in de inhoudslaag; de uitzondering in GLS-1 geldt voor een bedieningselement zoals de knop van een schuifregelaar, niet voor een tooltip (kritiek F10/F11). **Merkkeuze die de gebruiker nog niet kent**: README.md:3 noemt "Liquid Glass"; na K5 is dat het systeemglas van balken en bladen, niet meer elk blok. Wordt in de oplevernotitie gemeld. |
| K6 | **`List`-pagina's (`ListScaffold`) voor pagina's die uit rijen bestaan met swipe-acties**: Inkomen, Uitgaven, Spaarpotten, Beleggingen, Doelen, Geschiedenis, Dag voor dag, Instellingen. **Rekenpagina's en formulierpagina's blijven `PageScaffold` met `Card`s**: Verdelen, Salaris en de calculators (Doel, Spaardoel berekenen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck). | LST-1, LST-3, LST-8: een rij kan alleen in een `List` swipen. `AllocationRow` (`SavingsPages.swift:1260-1371`) is een mini-formulier met segment, bedragveld, twee knoppen en een bijschrift; in een `List`-rij activeert een tik meerdere knoppen tegelijk (zonder `.buttonStyle(.borderless)`) en botst de focus van het veld met swipe-acties (kritiek F9). |
| K7 | **Publieke API van bestaande componenten blijft bestaan als compat-laag** (`GlassBlock`, `LinkedBlock`, `ChipButton`, `ChipLink`, `ChipGrid`, `ProgressBar`, `ProgressRing`, `SegmentBar`, `MeshBackground`, `Theme.flow*`, `Theme.olive*`, `Theme.buttonHeight`, en in `Router` `homePath`, `savingsPath`, `toolsPath`, `showSettings`; in `BlockPage` de cases `home`, `savings`, `tools`). **Een nieuw type dat een bestaand type vervangt krijgt een nieuwe naam**, zodat er nooit twee definities zijn: `NoticeBanner` wordt `NoticeCard`, `GainLabel` wordt `GainBadge`, `MonthPickerBlock` wordt `MonthBar`, `PeriodControl` krijgt naast zich `PeriodPicker`, `PotPickerSheet` en `HoldingPickerSheet` worden `FavoritePotsSheet` en `FavoriteHoldingsSheet`. Pakket G verwijdert de compat-laag en de oude namen. | Zes bouwers werken tegelijk en elke golf moet compileren (K18). |
| K8 | **Blokvolgorde blijft en wordt zichtbaar**: knop "Volgorde aanpassen" in het menu van de werkbalk (alleen op pagina's met drie of meer blokken), een pagina "Indeling" in Instellingen, en het contextmenu (lang indrukken) blijft als sneltoets. **Een opgeslagen volgorde onder de oude sleutels `home`, `savings`, `tools` wordt gemigreerd** met `BlockOrderMigration.migrate(_:)` (Foundation-only, getest), met behoud van de relatieve volgorde (par. 2.7). | ACC-7: een functie die alleen via een gebaar werkt, is niet toegankelijk. De persoonlijke volgorde mag niet stil verdwijnen (kritiek F12); ordenen op een pagina met 2 blokken (Sparen) is zinloos. |
| K9a | **De keuze van potten en beleggingen voor de eerste tab blijft.** `homePotIDs` en `homeHoldingIDs` blijven functioneel (maximaal 3 potten, maximaal 4 beleggingen; `homePots()`, `homeHoldings()` en hun tests blijven in gebruik). Het Overzicht krijgt twee kaarten `pots` (`HomePotsCard`) en `invest` (`HomeHoldingsCard`) met de gekozen tegels. | Een eerder expliciet gevraagde functie (README.md:7, `HomeView.swift:254-283`, `:486-575`) mag niet verdwijnen. De HIG eist het schrappen niet (een kort keuzeblad met Annuleer en Bewaar is toegestaan, SHT-1); audit E16 stelde "de drie grootste met link Alle" voor, niet verwijdering. |
| K9b | `FavoritePotsSheet` en `FavoriteHoldingsSheet` zijn korte sheets (`SheetScaffold`, `hasChanges`) met pakket C als eigenaar; ze staan in `App/Pages/Saving/` en worden geopend vanuit het kaartmenu op het Overzicht ("Kies potten…", "Kies beleggingen…") en vanuit het werkbalkmenu van `PotsPage` en `PortfolioPage`; geen chip meer. | Een plek per functie: C bezit alles wat potten en beleggingen is. |
| K9c | `PotsSummaryCard` en `PortfolioSummaryCard` op Sparen tonen dezelfde gekozen tegels, het totaal en een link "Alle spaarpotten" en "Alle beleggingen". De lege plek-tegel ("Kies pot") blijft zolang er minder dan drie potten gekozen zijn. | Eerste versie liet Sparen niets tonen waarvan was vastgelegd dat het potten bevat (kritiek F1). |
| K9d | Het Overzicht heeft dan **de kern (hero) plus vier kaarten**: `wealth`, `pots`, `invest`, `upcoming`. | Binnen de grens van zes (par. 2.4); `flow` verhuist naar Maand (K17). |
| K9e | Sheetsoorten in de app: 11 (was 17), waarvan geen enkele voor Instellingen of Account. | Telling in par. 2.4. |
| K10 | **"Dag voor dag" wordt een segment van Bankrekening**, "Uitgaven" een eigen pagina, "Salaris instellen" een subpagina van Inkomen. | Audit E4, E5: het belangrijkste is nu het moeilijkst te vinden. |
| K11 | **Een Core-fix voor Beleggingen**: een belegging zonder meetpunt krijgt een afgeleid beginpunt uit "Totaal ingelegd", de inleg en **"Belegd sinds"** (K19) (charts.md C1 t/m C9). | Oorzaak van de kapotte grafiek (sectie 5). |
| K12 | **Eén grafieklaag**: `App/UI/ChartModels.swift` (Foundation-only, getest) en `App/UI/Charts.swift` (3 componenten: `TrendChart`, `StackedBarChart`, `DonutChart`); de voortgangsmeters (`ProgressMeter`, `SegmentedMeter`) staan in `App/UI/Meters.swift` bij het ontwerpsysteem (0A), zodat 0A niet van F afhangt. De acht oude grafiektypen verdwijnen. | CHT-2, CHT-7, CHT-11; geen cyclus tussen 0A en F. |
| K13 | **Geen eigen weergave-, taal- of haptiekinstelling**, geen `.rounded`-cijfers, geen `caption2`. | DRK-1, SET-3, TYP-6, TYP-4. |
| K14 | **Termenlijst (par. 2.8) is bindend**: een woord per begrip. | Audit E1 t/m E17. |
| K15 | **De maandsluiting van bank en spaarpotten blijft** (`CashflowBankBlock`: begin, binnen, eruit, overgeschreven, handmatig, eind; `CashflowPotsBlock`: begin, inleg, rente, uit potten betaald, eind) als twee uitklappers "Zo komt je saldo tot stand" in het segment Dag voor dag van Bankrekening, met dezelfde `CashflowSummary.bankRows` en `potsRows` en dezelfde `LedgerLineRow`. Wat een dagsectie toont staat in par. 2.4. | Eerste versie liet ze vervallen onder een onjuiste verwijzing naar H9; `LedgerCheck` en de tests (8 verwijzingen in `CashflowDisplayTests`) blijven dan in gebruik (kritiek F3). |
| K16 | **Een pagina staat nooit twee keer in een pad, en een link naar een pagina van een andere tab wisselt van tab.** `NavigationRules.normalize` knipt elk pad dat een bestemming herhaalt; `Router.pathBinding(for:)` past het toe bij elke schrijfactie, dus ook voor `NavigationLink(value:)`. De componenten `Card(headerLink:)`, `LinkCard`, `NavigationRow` en `ActionLink` gebruiken `router.go(_:)` als `destination.tab != router.tab`, anders `NavigationLink(value:)`. `go` bouwt het ouderpad (Spaarpot onder Spaarpotten). | Eerste versie loste N9 alleen op voor `router.open`; bijna alle navigatie is `NavigationLink(value:)` en schreef rechtstreeks in de padbinding (kritiek F6). |
| K17 | **Overzicht is "nu", Maand is "door de tijd".** Het Overzicht leest `focusMonth` en `periodMode` niet (altijd de huidige maand, vaste vensters). De Maand-tab bezit beide: `MonthBar` stapt per maand, `PeriodPicker` in de kaart `flow` kiest alleen de vensterlengte (Maand, Half jaar, Jaar) en verschuift `focusMonth` niet. De kaart `flow` ("Waar gaat je geld heen") staat daarom op Maand. | Anders verschuift terugbladeren op het Overzicht stil de maand op de Maand-tab, en tonen hero en Maand-kaarten dezelfde vier getallen (kritiek F4, audit E2/H1). |
| K18 | **Elke golf eindigt compileerbaar en de CI geeft het oordeel.** Golf 0 begint met een kleine, compileerbare schil (0B) met tijdelijke tabwortels; elk pakket werkt in een eigen `git worktree` op een eigen branch `claude/ontwerp-<pakket>`; na elk pakket en na elke golf bouwt de CI (iOS, macOS, `swift test`) groen; fouten gaan met `docs/design/ownership-check.sh --owner <pad>` naar de eigenaar. | `check_swift` is alleen een parser (kritiek 5.2: een bestand met foute labels, `Text(42)`, een onbekend type en 11 kinderen geeft 0 foutknopen); `.github/workflows/ci.yml` bouwt al bij elke push op `claude/**`. |
| K19 | **Beleggingen: "Belegd sinds" en een eerlijk onderschrift.** `HoldingEditSheet` krijgt een keuze "Belegd sinds" (maand, op het bestaande `Holding.startMonth`; geen nieuw `Codable`-veld). De afgeleide lijn heeft als onderschrift "Geschat uit je inleg, zonder rendement." Een `DebugLaunch`-scenario en een CI-screenshot maken het gemelde geval reproduceerbaar. | Zonder startmaand krijgt elke via de UI ingevulde belegging een beginpunt in de huidige maand: een stip en nooit geschiedenis (kritiek F5). |
| K20 | **Zoeken vanaf elke tab**: `SearchIndex` (Foundation-only, uitputtend getest), een zoekknop in de werkbalk van elke tabwortel (`searchToolbarButton()`) die `router.requestSearch()` aanroept, en `.searchable(text:isPresented:)` op het Overzicht dat het zoekveld opent; ook Cmd+F. | Zoeken stond alleen op tab 1 en had geen test (kritiek F16). `Tab(role: .search)` blijft buiten deze ronde (par. 8.3). |
| K21 | **Platformafhankelijke maten**: `Theme.minTapTarget` is 44 pt op iOS en 28 pt op macOS; `ActionButton` gebruikt `.controlSize(.large)` op iOS en `.regular` op macOS. | ACC-2 en MAC-9: een Mac-knop van 44 pt is onnodig groot (kritiek F11). |

## 1. Ontwerpprincipes

1. **Inhoud is geen glas.** Glas is voor bediening en navigatie en komt van het systeem (GLS-1). Inhoud staat in kaarten of lijsten; knoppen in inhoud zijn `.bordered` of `.borderedProminent`, nooit glas op glas.
2. **Een plek per functie, een woord per begrip.** Elke functie heeft een primaire route; dubbele ingangen en dubbele cijfers verdwijnen (NAV-5, WRT-2). Een getal heeft een thuis: "Nog te verdelen" woont op Verdelen; het Overzicht toont het met een link.
3. **Elke pagina is op dezelfde manier opgebouwd:** bovenaan de kerncijfers, daaronder secties met een eigen kop, acties in de werkbalk, destructieve acties onderaan en rood (LAY-1, LST-2).
4. **Weinig, dichtbij, ondiep:** 5 tabs (4 op de Mac), maximaal 6 blokken per pagina, progressive disclosure voor de rest (LAY-2, NAV-4, SIM-2). De gewone route is tab, pagina, detail (3 niveaus); een link naar een pagina van een andere tab wisselt van tab (K16) en een pagina staat nooit twee keer in een pad. Het diepste pad zonder omweg is Plannen, Doelen, Doel, Versnellers (4 inclusief de tabwortel).
5. **Instellingen is nooit een sheet en het account staat los** van rekenen, koersen en gegevens (SET-4, ACT-5).
6. **Een sheet is een korte taak** met Annuleer links en Bewaar rechts; nooit een sheet in een sheet. Bij niet-bewaarde invoer is veeg-om-te-sluiten uit (`interactiveDismissDisabled(hasChanges)`) en vraagt "Annuleer" bevestiging ("Bewaar", "Gooi weg", "Verder bewerken"). De veeg zelf meldt een geweigerde poging niet terug (kritiek F13), dus die belofte doen we niet (SHT-1 t/m SHT-4; SHT-5 deels).
7. **Dynamic Type voorop:** alleen tekststijlen, stapelen bij toegankelijkheidsformaten, raakdoelen per platform (44 pt iOS, 28 pt Mac), krimpen alleen voor een kerngetal (TYP-1 t/m TYP-3, ACC-2, MAC-9).
8. **Contrast en nooit alleen kleur:** tekst 4,5:1 in licht en donker, hoog-contrastvariant, symbool of teken of label naast elke kleur (COL-3, COL-4). Domeinkleur is een aanvulling, nooit de enige drager.
9. **Elke grafiek is een zuivere functie van de invoer**, heeft een lege staat, een samenvatting voor VoiceOver en een tweede kanaal naast kleur (CHT-2, CHT-5, CHT-7, CHT-9).
10. **Een gebaar is altijd ook zichtbaar**: swipe en contextmenu spiegelen een knop of menu (ook "Koersen vernieuwen" staat in het menu naast pull-to-refresh); beweging respecteert Verlaag beweging; haptiek alleen bij discrete gebeurtenissen (ACC-4, ACC-7, FDB-4).
11. **Elk platform eigen gedrag:** zijbalk op iPad en Mac, `Settings`-venster op de Mac (geen Instellingen in de zijbalk), menubalk, sneltoetsen, `.help`, leesbare breedte (MAC-1 t/m MAC-6, LAY-7).
12. **Vereenvoudigen zonder iets te verliezen:** elke functie die nu bestaat blijft bestaan; per verwijderd of samengevoegd onderdeel staat in par. 2.5 en 3.2 waar de functie heen gaat.

## 2. Informatiearchitectuur

### 2.1 Navigatie: native `TabView`, Instellingen als tab (iOS) of venster (Mac)

- **Vorm.** `TabView(selection:) { Tab(title, systemImage:, value:) { ... } }` met `.tabViewStyle(.sidebarAdaptable)` (iOS 18 en macOS 15, dus zonder `#available`). iPhone: tabbalk onderin die op iOS 26 als glas boven de inhoud zweeft. iPad: balk bovenin die in een zijbalk kan veranderen. Mac: zijbalk met vier items. Op iOS 26 erbij: `.tabBarMinimizeBehavior(.onScrollDown)` achter `#available(iOS 26.0, macOS 26.0, *)` (bestaat ook op macOS 26).
- **Een `NavigationStack` per tab** met een eigen pad (`router.paths[tab]`). Van tab wisselen wist niets (TAB-6). De stack zit niet in de tabroot maar in een gedeelde `TabStack` (par. 4.4), zodat elke tabroot alleen inhoud is.
- **Instellingen: tab of knop?** Gekozen: **tab op iPhone en iPad**, laatste in de rij, met een badge (`.badge(1)`, anders `.badge(0)`) zolang de synchronisatie aandacht vraagt (conflict, aanbod om lokale gegevens te uploaden; TAB-8 staat kritieke meldingen toe). Onderbouwing: (1) HIG `tab-bars`: een tabbalk is voor navigatie op het hoogste niveau; Instellingen is een bestemming, geen actie. (2) De eis "een tik vanaf overal, nooit een sheet" geldt alleen voor een tab: de balk blijft zichtbaar bij elke push, een toolbarknop staat alleen op tabwortels. (3) Op de iPad staat het als laatste item in de zijbalk. (4) **Op de Mac geen tab**: `#if !os(macOS)` om de vijfde `Tab`; Instellingen is daar het `Settings`-venster met Cmd+komma en het menu-item in het App-menu, dezelfde pagina's als zes panes (SID-4, SET-5, MAC-3).
- **Zoeken** zit niet in een eigen tab (dat zou een zesde tab zijn) maar is vanaf elke tabwortel bereikbaar met `searchToolbarButton()` en Cmd+F; het zoekveld zelf is `.searchable` op het Overzicht (par. 2.9).
- **Terugtik op de actieve tab** brengt naar de tabroot. De selectie loopt door een `Binding(get:set:)` die bij `new == router.tab` `router.popToRoot(new)` aanroept; of `TabView` de selectie bij een terugtik meldt, is op een toestel te controleren (TAB-6 is `[K]`; scenario 7). Het oude gedrag (`Router.select` wist het pad, `RootView.swift:84-90`) mag niet stil verdwijnen.

### 2.2 De tabs

| Tab | Titel (grote titel) | Symbool | Domein | Wat je er doet | Rootbestand |
|---|---|---|---|---|---|
| 1 | Overzicht | `chart.pie` | overview | **Nu**: nog te verdelen, vermogen, je gekozen potten en beleggingen, komende dagen | `OverviewTab` |
| 2 | Maand | `calendar` | money | **Door de tijd**, per maand: waar gaat je geld heen, Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag | `MonthTab` |
| 3 | Sparen | `banknote` | saving, investing | Spaarpotten en Beleggingen | `SavingTab` |
| 4 | Plannen | `flag.checkered` | goals, tools | Doelen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck | `PlanningTab` |
| 5 | Instellingen (alleen iOS en iPadOS) | `gearshape` | settings | Account, Rekenen, Koersen, Gegevens, Indeling, Over | `SettingsView` |

Alle titels zijn een woord, Nederlands, zinshoofdletter (TAB-4, WRT-2). De gevulde variant kiest het systeem zelf (`AppTab.symbol(selected:)` vervalt in G).

### 2.3 Een vaste opbouw voor elke pagina

Zo houd je onderdelen uit elkaar: dezelfde plek voor hetzelfde, in elke pagina.

1. **Kop van de pagina**: grote titel alleen op de tabwortels, daaronder (detailpagina's) een korte titel in de balk. Detailtitels zijn kort (NAV-3).
2. **Kerncijfers eerst**: de eerste kaart of sectie toont het ene getal waar de pagina over gaat (`BigAmount`), met maximaal drie ondersteunende cijfers (`FigureRow` met `StatTile`, of `AmountRow`).
3. **Secties met een eigen kop**, elk met het domeinsymbool: `Card(title:symbol:domain:)` op dashboards, `Section(header:)` in een `List`. Een kop is een VoiceOver-kop. Maximaal 6 per pagina, liefst 3 tot 5.
4. **Acties in de werkbalk**: een primaire actie (`plus`, trailing), de rest in een `ellipsis`-menu. Knoppen in de inhoud alleen voor de ene logische vervolgstap van die sectie.
5. **Onderaan destructief**: verwijderen staat in een eigen sectie onderaan, rood, met een bevestiging aan de knop zelf (DLG-4).
6. **Lege staat in plaats van lege ruimte**: elke sectie en elke grafiek zonder gegevens toont uitleg plus een knop.

Drie paginavormen: **tabroot** (dashboard van kaarten, `PageScaffold(large: true)`; de kern staat vast bovenaan), **lijstpagina** (`ListScaffold`, rijen met swipe), **rekenpagina** (`PageScaffold` met kaarten: uitkomst bovenaan, invoer daaronder, details in een uitklapper; ook Verdelen en Salaris, K6). Een formulier is een `SheetScaffold`.

**Kleur en symbool per domein** (`AppDomain`, par. 4.2). Dit onderscheidt de onderdelen in een oogopslag, maar draagt nooit alleen de betekenis: titel en symbool staan er altijd bij.

| Domein | Hoort bij | Symbool | Titel |
|---|---|---|---|
| overview | Overzicht | `chart.pie` | Overzicht |
| money | Inkomen, Uitgaven, Verdelen, Bankrekening | `calendar` (tab), `eurosign.circle` (Inkomen), `creditcard` (Uitgaven), `square.split.2x2` (Verdelen), `building.columns` (Bankrekening) | Inkomen en uitgaven |
| saving | Spaarpotten | `tray.full` | Sparen |
| investing | Beleggingen | `chart.line.uptrend.xyaxis` | Beleggen |
| goals | Doelen, Noodbuffer, Versnellers | `flag.checkered`, `shield.lefthalf.filled`, `bolt` | Doelen |
| tools | Toekomstschatting, Aankoopcheck, Spaardoel berekenen | `calendar.badge.clock`, `cart`, `function` | Hulpmiddelen |
| settings | Instellingen en Account | `gearshape`, `person.crop.circle` | Instellingen |

### 2.4 Pagina's en blokken

Een blok is een kaart op een dashboard of een sectie met kop in een lijstpagina. De rijen in een lijst (de 31 dagen op Dag voor dag, de regels van Uitgaven) zijn geen blokken. De **kern** van een pagina (de hero op het Overzicht, de `MonthBar` op Maand) is geen blok: hij staat vast bovenaan, buiten `OrderedBlocks`, en is niet verplaatsbaar. "Eig." verwijst naar het werkpakket (sectie 6).

**Tabroots**

| Pagina | Eig. | Kern en blokken (volgorde standaard) | Wat er verandert |
|---|---|---|---|
| **Overzicht** (`OverviewTab`) | A | Meldingen (geen blok): opstartmelding, opslaan mislukt (met "Opnieuw proberen"), `SyncAttentionBanner`, "Cijfers sluiten niet" (`CashflowCheckBanner`, alleen bij afwijking). **Kern**: *Nog te verdelen in oktober* (hero met `BigAmount`, de waarschuwingen `percentWarning` en notities van `MonthBoard`, tik opent Verdelen; geen tegels Inkomen, Uitgaven, Verdeeld: die staan op Maand). **Blokken**: `wealth` Vermogen, `pots` Spaarpotten (`HomePotsCard`, C), `invest` Beleggingen (`HomeHoldingsCard`, C), `upcoming` Komende dagen (`UpcomingDaysCard`, B2). Lege start: `EmptyHint(.page)` "Welkom bij MyBuddy" met "Salaris instellen" (prominent) en "Voorbeelddata laden" in plaats van de vier kaarten. Zoeken: `.searchable` (par. 2.9). | Vervangt Home. Leest `focusMonth` en `periodMode` niet (K17): altijd de huidige maand. |
| ... `wealth` "Vermogen" | A | `BigAmount` vermogen (eind van de huidige maand), `TrendChart(NetWorthTrend)` over de laatste 12 maanden (vast venster, geen periodekeuze), 3 `AmountRow`-links: Bankrekening, Spaarpotten, Beleggingen | Zoals de oude kaart Vermogen; links naar een andere tab gebruiken `go` (K16). |
| ... `pots` en `invest` | C (kaarten), A (plaatsing) | `HomePotsCard`: totaal gespaard, tot 3 gekozen potten als tegels (`FavoritePotTile` met `ProgressMeter`, geen `.rounded`, geen `minimumScaleFactor`), lege plek-tegel "Kies pot" (`FavoriteSlotTile`) bij minder dan 3, kaartmenu "Kies potten…" (`FavoritePotsSheet`) en link "Alle spaarpotten". `HomeHoldingsCard`: waarde, `GainBadge`, tot 4 gekozen beleggingen als tegels (`FavoriteHoldingTile`), kaartmenu "Kies beleggingen…" (`FavoriteHoldingsSheet`), link "Alle beleggingen" | Herbouw van `PotsBlock`, `InvestBlock`, `PotMiniTile`, `HoldingTile`, `EmptySlotTile` (K9a). Lege staten: "Nog geen spaarpotten" en "Nog geen beleggingen" met knop. |
| ... `upcoming` "Komende dagen" | B2 (kaart), A | `UpcomingDaysCard()`: de komende 14 dagen, link "Dag voor dag" | Was verstopt op Bankrekening. |
| **Maand** (`MonthTab`) | A | **Kern**: `MonthBar` (stapt per maand; `focusMonth`). **Blokken**: `flow` "Waar gaat je geld heen" (`PeriodPicker` Maand, Half jaar, Jaar; `StackedBarChart`; tegel Overgehouden; uitklapper "Cijfers van deze periode" met Inkomen, Uitgaven, Gespaard, Belegd, gemiddeld overgehouden per maand en de toelichtingen; uitklapper "Maand voor maand"); dan vijf `LinkCard`s met het kerncijfer en een tik naar de pagina: `income` Inkomen, `expenses` Uitgaven, `distribute` Verdelen (toont Nog te verdelen), `bank` Bankrekening (saldo), `days` Dag voor dag (laagste saldo van de maand). | Bevat alles van de oude pagina Overzicht (de herhaalde tegel "Over" valt weg, audit H3) en de oude periodekeuze van Savings; zes blokken. |
| **Sparen** (`SavingTab`) | A (kaarten: C) | `pots` `PotsSummaryCard()`, `portfolio` `PortfolioSummaryCard()` | Vervangt de Savings-blokken met dezelfde namen. Twee blokken: geen "Volgorde aanpassen". |
| **Plannen** (`PlanningTab`) | A (kaarten: D) | `goals` `GoalsSummaryCard()` (met altijd een rij "Spaardoel berekenen"), `buffer` `BufferSummaryCard()`, `accelerators` `AcceleratorsSummaryCard()`, `projection` `ProjectionSummaryCard()`, `purchase` `PurchaseSummaryCard()` | Een tab voor alles wat plannen en rekenen is (was verdeeld over Savings en Tools). |
| **Instellingen** (`SettingsView`) | E | Zie par. 3: Account-rij, Rekenen, Koersen, Gegevens, Indeling, Over | Van sheet naar tab (iOS) of venster (Mac). |

**Detailpagina's** (maximaal 6 blokken)

| Pagina (`Destination`) | Eig. | Vorm | Blokken |
|---|---|---|---|
| Inkomen (`.income`) | B1 | lijst | `MonthBar`; **Samenvatting** (inkomen, Salaris en Overige inkomsten als `AmountRow`, schemazin, rij "Salaris instellen" naar `.salary`); **Salaris deze maand** (uitbetalingen, afwijkend bedrag of andere uren); **Overige inkomsten** (rijen, swipe, `+` in werkbalk) |
| Salaris (`.salary`, nieuw) | B1 | **rekenpagina** (`PageScaffold`, kaarten) | **Standaard salaris** (vast of uurloon); **Wanneer krijg je salaris?** (maandelijks, om de zoveel weken of dagen, eerste uitbetaling, salarisdag zonder uitbetaling, de volgende 4 data) |
| Uitgaven (`.expenses`, nu een echte pagina) | B1 | lijst | `MonthBar`; **Samenvatting** (uitgaven, waarvan uit spaarpotten, Vast en Variabel); **Vaste uitgaven**; **Variabele uitgaven**; werkbalk: `+`, menu met "Standaard uitgaven invullen" |
| Verdelen (`.distribute`) | B1 | **rekenpagina** (`PageScaffold`, een `Card` per pot of belegging, K6) | `MonthBar`; **Samenvatting** (nog te verdelen, balk, Inkomen, Uitgaven, Verdeeld, waarschuwingen); **Spaarpotten** (`AllocationRow` per pot: segment Bedrag/Percentage, bedrag, grondslag, "Afwijkend", "Terug naar standaard", "Maak dit je standaard"); **Beleggen**; **Overschrijfdag** (uitklapper); menu: Standaardverdeling, Rest over potten, Alles op nul |
| Bankrekening (`.bank`, `.cashflow`) | B2 | lijst met segmenten Saldo / Dag voor dag / Boekingen | *Saldo*: hero Saldo vandaag (+ "Saldo invullen"), **Verwacht verloop**, **Binnen en eruit**, **Minimumsaldo**. *Dag voor dag*: melding bij afwijking (`CashflowCheckBanner`), **Saldo per dag** (grafiek), uitklapper **Zo komt je saldo tot stand** (bank: begin, binnen, eruit, overgeschreven, handmatig, eind; `CashflowBankBlock`), uitklapper **Zo komen je spaarpotten tot stand** (alleen met potten: begin, inleg, rente, uit potten betaald, eind; `CashflowPotsBlock`), daarna een sectie per dag. *Boekingen*: **Geschiedenis**. Werkbalkmenu "Geld bewegen" (storten, opnemen, naar pot, van pot, saldo invullen) |
| ... een dagsectie (Dag voor dag) | B2 | rij-sectie | Kop: weekdag en datum met "Vandaag" of "Gepland"; `DayFlowTiles` (Binnen, Eruit, Overgeschreven); `DayEventRow`s (of "Geen boekingen op deze dag"); `DayBalanceRows` (Saldo bankrekening aan het eind van de dag met het beginsaldo, Spaarpotten totaal, Te verdelen t/m deze dag). Filter standaard **Alleen met boekingen**; andere keuze Alle dagen; knop "Naar vandaag". Zo blijft het saldo van bank en potten per dag bereikbaar (de functie van `BankDayBlock`). |
| Spaarpotten (`.pots`) | C | lijst | **Samenvatting** (totaal gespaard, doel, voortgang, inleg deze maand, rente dit jaar); **Potten** (rijen met swipe); werkbalk `+` en menu met "Kies potten voor het Overzicht…" |
| Spaarpot (`.pot`) | C | lijst | hero **Saldo** (ring, doel, verwacht eind, knoppen Storten en Opnemen) met **Verloop** (nieuw); **Komende boekingen**; **Inleg en rente**; **Geschiedenis**; **Saldo op datum** (uitklapper); menu: Geld bewegen, Bewerken; onderaan Verwijderen |
| Beleggingen (`.portfolio`) | C | lijst | **Samenvatting** (waarde, winst, koersstatus); **Groei** (`TrendChart` met venster); **Verdeling** (`DonutChart` met lijst); **Beleggingen** (rijen met swipe); werkbalk `+` en menu: Koersen vernieuwen, Kies beleggingen voor het Overzicht…; pull-to-refresh |
| Belegging (`.holding`) | C | lijst | **Samenvatting**; **Koers en waarde** (segment, `TrendChart`); **Uitgangspunten**; **Inleg**; **Waarde-updates** (rijen met swipe); menu: Bewerken, Waarde bijwerken, Koers vernieuwen |
| Doelen (`.goals`) | D | lijst | **Doelen** (rijen), lege staat; werkbalk `+` met Nieuw doel, Spaardoel berekenen, Noodbuffer |
| Doel (`.goal`) | D | rekenpagina | doeltype met ring, **Zo is het berekend**, **Versnellers**, **Toegepast** |
| Spaardoel berekenen (`.savingsGoal`) | D | rekenpagina | **Uitkomst**, **Invoer**, **Verloop**, **Details** (uitklapper: wat als, ingelegd en rente, per jaar), acties "Maak er een spaarpot van" en "Maak er een doel van" |
| Noodbuffer (`.buffer`) | D | rekenpagina | **Uitkomst** (doel, balk, tegels, verloop), **Jouw situatie** (invoer), **Spaarpot Noodbuffer** (aanmaken of aanpassen) |
| Versnellers (`.accelerators`) | D | rekenpagina | **Voor welk doel?** (alleen bij meer dan een doel), **Versnellers**, **Toegepast** |
| Toekomstschatting (`.projection`) | D | rekenpagina | **Uitkomst** (3 scenario's), **Verloop**, **Looptijd** ("Hoe ver kijk je vooruit?": veld, eenheid, snelkeuzes; altijd zichtbaar, geen uitklapper), **Uitgangspunten** (uitklapper), **Streefbedrag** |
| Aankoopcheck (`.purchase`) | D | rekenpagina | wizard in 3 stappen (ongewijzigd), elke stap een blok, daarna Uitkomst, Kan het?, Goedkoper te vinden? |
| Instellingen en Account (`.settings(_)`) | E | lijst | Zie par. 3 |

Ten opzichte van nu (audit par. 0 en 1.6): tabs 3 naar 5 (4 op de Mac); pagina's 18 naar 31 (5 tabroots, 16 detailpagina's, 10 instellingenpagina's), een toename die bewust is om elk scherm klein te houden; het aantal blokken per scherm gaat van 3 tot 39 naar 1 tot 6 (Maand heeft er zes); glazen kaarten 115 naar 0; sheetsoorten 17 naar 11; Instellingen van 10 secties en 29 rijen in een sheet naar 4 groepen en 6 rijen op een eigen pagina. Pagina's zijn gemiddeld ondieper (par. 1 punt 4).

### 2.5 Wat is samengevoegd of vervallen, en waar de functie terechtkomt

| Oud onderdeel | Straks | Functie behouden? |
|---|---|---|
| Tabs Home, Savings, Tools (Engels) | Tabs Overzicht, Maand, Sparen, Plannen, Instellingen | ja |
| Home: `RemainingHeader` | Overzicht, hero (alleen Nog te verdelen); Inkomen, Uitgaven en Verdeeld staan op Maand en Verdelen | ja (de drie tegels verhuizen om dubbele cijfers tussen tabs te voorkomen, K17) |
| Home: `OverviewBlock`, Savings: `PeriodBlock`, pagina `OverviewPage` (6 kaarten) | Maand, kaart `flow`; "Cijfers van deze periode" en "Maand voor maand" als uitklappers; "Klopt met je dagoverzicht" alleen als melding bij afwijking | ja; de herhaalde tegel "Over" (H3) en de bevestiging "Klopt" vervallen |
| Home: `PotsBlock`, `InvestBlock`, `PotsTotals`, `PotMiniTile`, `HoldingTile`, `EmptySlotTile` | Overzicht: `HomePotsCard`, `HomeHoldingsCard` (C); Sparen: `PotsSummaryCard`, `PortfolioSummaryCard` | ja, inclusief de keuze van 3 potten en 4 beleggingen (K9a t/m K9c) |
| `PotPickerSheet`, `HoldingPickerSheet`, chips "Kies potten" en "Kies beleggingen" | `FavoritePotsSheet`, `FavoriteHoldingsSheet` (C), geopend vanuit kaartmenu en werkbalkmenu | ja |
| `WelcomeBlock` | Lege staat van het Overzicht | ja, met "Voorbeelddata laden" daar |
| Savings: `IncomeBlock`, `BankBlock`, `DistributeBlock` | Maand: kaarten `income`, `bank`, `distribute` | ja |
| Savings: `BufferBlock`, `GoalsHubBlock`; Tools: `AcceleratorsBlock`, `ProjectionBlock`, `PurchaseBlock` | Plannen: vijf kaarten | ja |
| Periodekeuze bovenaan Savings (geldt maar voor 4 van 8 blokken) | alleen `PeriodPicker` in `flow` op Maand; de Maand-pagina's hebben een `MonthBar` | ja |
| `IncomePage`: standaard salaris en schema | Subpagina Salaris (`.salary`) | ja |
| `BankPage`: Vaste en Variabele uitgaven | Pagina Uitgaven | ja |
| `BankPage`: chip "Standaard uitgaven invullen" | Werkbalkmenu en lege staat van Uitgaven | ja |
| `BankPage`: `BankBalanceBlock` met 5 chips | Hero Saldo met "Saldo invullen"; "Geld bewegen" in het werkbalkmenu | ja |
| `BankPage`: `BankTransfersBlock` "Overschrijvingen" | vervalt; dezelfde cijfers staan op Verdelen; in "Binnen en eruit" linken de rijen naar Spaarpotten, Beleggingen en Verdelen | ja (H6) |
| `BankPage`: `BankDayBlock` (dagkiezer met bank- en potsaldo van een gekozen dag), `BankUpcomingBlock`, pagina `CashflowPage` met 28 tot 31 dagkaarten | Segment Dag voor dag met een sectie per dag die bank- en potsaldo toont (par. 2.4); "Komende 14 dagen" wordt de Overzicht-kaart `upcoming`; de losse dagkiezer vervalt omdat de lijst alle dagen toont | ja |
| `CashflowBankBlock`, `CashflowPotsBlock` | **blijven**: twee uitklappers "Zo komt je saldo tot stand" in Dag voor dag (K15) | ja |
| `CashflowOverviewBlock` ("Klopt met je overzicht", links naar Overzicht) | alleen de banner `CashflowCheckBanner` bij een afwijking | de positieve bevestiging vervalt (akkoord) |
| `BankBufferBlock` "Bankbuffer" en Instellingen "Buffer op bankrekening" | een veld "Minimumsaldo (maanden aan uitgaven)" op Bankrekening | ja, nu op een plek (E7) |
| `BankHistoryBlock` | Segment Boekingen, rijen met swipe | ja |
| `GoalsPage` met schakelaar Mijn doelen / Spaardoel | Doelen, en Spaardoel berekenen als eigen pagina (`.savingsGoal`) | ja |
| `BufferPage` "Buffer" | Noodbuffer | ja |
| Versnellers in Tools en in elk Doel | pagina Versnellers blijft (Plannen); de sectie in het Doel blijft | ja; beide gebruiken `AcceleratorsSection` |
| Instellingen-sheet en de tandwiel in `PageScaffold` | Tab Instellingen (iOS) of venster (Mac), par. 3 | ja |
| `ChipButton`, `ChipLink`, `ChipGrid`, `ChipLabel` | `ActionButton`, `ActionLink`, `ActionGroup`; acties van een pagina in de werkbalk | ja |
| `RateFetchRow`, `SectionLabel` (dode code), `FirebaseSetupSection` (ontwikkelaarsuitleg) | verwijderd | n.v.t. |
| Ellipsis-menu per rij met een item (Verwijder) | swipe-actie plus contextmenu (`rowActions`) | ja |
| `Meetpunt` (jargon) | "Waarde-update" | ja |
| Opgeslagen blokvolgorde onder `home`, `savings`, `tools` | gemigreerd naar de nieuwe pagina's (par. 2.7) | ja |

### 2.6 `Destination`: oud naar nieuw, `Router` en diepe links

| Oud (`Destination`) | Nieuw | Opent | Opmerking |
|---|---|---|---|
| `.overview` | `.overview` | tab Overzicht | alleen via `router.go(.overview)`; nooit meer een geduwde pagina |
| `.income` | `.income` | `IncomePage` | ongewijzigd |
| (nieuw) | `.salary` | `SalaryPage` | subpagina van Inkomen |
| `.expenses` (alias voor `BankPage`) | `.expenses` | `ExpensesPage` | nu een echte pagina |
| `.distribute` | `.distribute` | `DistributePage` | ongewijzigd |
| `.bank` | `.bank` | `BankPage(section: .balance)` | segment Saldo |
| `.cashflow` | `.cashflow` | `BankPage(section: .days)` | blijft bestaan voor diepe links en `-mybuddy-open cashflow` |
| `.pots`, `.pot(UUID)` | idem | `PotsPage`, `PotDetailPage` | ongewijzigd |
| `.portfolio`, `.holding(UUID)` | idem | `PortfolioPage`, `HoldingDetailPage` | ongewijzigd |
| `.goals`, `.goal(UUID)` | idem | `GoalsPage`, `GoalDetailPage` | de schakelaar is weg |
| `.savingsGoal` | `.savingsGoal` | `SavingsGoalPage` | nu rechtstreeks de calculator |
| `.accelerators`, `.buffer`, `.projection`, `.purchase` | idem | zoals nu | `.buffer` heet in de UI "Noodbuffer" |
| (nieuw) | `.settings(SettingsPage)` | `SettingsDestination(page:)` | `SettingsPage`: `account`, `password`, `deleteAccount`, `conflictBackups`, `calculations`, `prices`, `data`, `layout`, `about`, `importReview` |

`AppTab` wordt `overview, month, saving, planning, settings` (raw values gelijk aan de case-namen; niet bewaard, dus geen migratie). Elke `Destination` heeft een `tab`: income, salary, expenses, distribute, bank, cashflow naar `.month`; pots, pot, portfolio, holding naar `.saving`; goals, goal, savingsGoal, accelerators, buffer, projection, purchase naar `.planning`; `.settings` naar `.settings`; `.overview` naar `.overview`.

**Regels van `Router`** (testbaar, Foundation-only in `NavigationRules`, pakket 0B):
- `normalize(_ path:)`: loopt het pad door en knipt het af op de eerste plek van een bestemming die al eerder voorkomt (Spaarpot, Dag voor dag, Spaarpot wordt Spaarpot). **Elke schrijfactie van `pathBinding(for:)` gaat erdoor**, dus ook een `NavigationLink(value:)` (K16, lost audit N9 echt op).
- `push(_:onto:)` = normalize van pad plus bestemming. `open(_:)`: heeft de bestemming dezelfde tab als `router.tab`, dan `push` op dat pad, anders `go`.
- `go(_:)` kiest de eigen tab van de bestemming en zet dat pad op het **ouderpad** plus de bestemming (`NavigationRules.go` geeft `(tab, path)`): `.pot(id)` onder `.pots`, `.holding(id)` onder `.portfolio`, `.goal(id)` onder `.goals`, `.salary` onder `.income`, `.settings(.password)`, `.settings(.deleteAccount)`, `.settings(.conflictBackups)` onder `.settings(.account)`, `.settings(.importReview)` onder `.settings(.data)`; alle andere `[bestemming]`; bij `.overview` leeg. Gebruiken: zoeken, sneltoetsen, `-mybuddy-open`, meldingen ("Naar Account"), links naar een andere tab. **Op de Mac** zet `go(.settings(p))` geen tab maar `router.settingsRequest = p`; de root opent met `openSettings()` het venster op die pane.
- `select(_:)` wisselt alleen van tab; `popToRoot(_:)` maakt een pad leeg; `requestSearch()` gaat naar het Overzicht en verhoogt `searchRequest` (de `OverviewTab` opent het zoekveld).
- `focusMonth`, `periodMode`, `showCurrentMonth(_:)`, `shiftPeriod(_:)`, `resetFocus(to:)`, `orderPage` blijven, maar **alleen de Maand-tab en de pagina's eronder lezen `focusMonth` en `periodMode`** (K17). `LinkCard(showsCurrentMonth: true)` op het Overzicht zet de Maand-tab op de huidige maand en `periodMode` op Maand voordat het opent.
- Verdwijnt in G: `showSettings`, `homePath`, `savingsPath`, `toolsPath`, `AppTab.symbol(selected:)`; tot dan bestaan ze als doorverwijzing naar `paths` (K7).
- `ActiveSession.unregister(store:)` wist de registratie alleen als de geregistreerde store dezelfde instantie is (een accountwissel laat oud en nieuw scherm kort samenleven, `MyBuddyApp.swift:89-98`).

**Diepe links en debug.** `DebugLaunch` blijft werken: `-mybuddy-tab` kent de nieuwe namen en de oude (home wordt overview, savings wordt month, tools wordt planning); `-mybuddy-open` kent alle bestaande namen plus `salary`, `account`, `password`, `rates`, `prices`, `data`, `layout`, `about`, `importreview`; `-mybuddy-settings` selecteert de tab Instellingen (op de Mac: opent het venster); `-mybuddy-order` accepteert `home`, `savings`, `tools` als alias; **nieuw**: `-mybuddy-demo-holding <only-invested|ticker-no-units|tracked-offline>` zet na het laden van de voorbeelddata een belegging zonder meetpunten neer (K19, scenario 11) en `-mybuddy-scroll-to <sectiekop>` scrolt een `ListScaffold` naar de sectie met die titel (`-mybuddy-scroll` werkt alleen via `.offset` in `PageScaffold` en dus niet op `List`-pagina's). `scripts/ci-screenshots.sh` blijft daardoor draaien (G werkt hem bij naar de nieuwe namen en voegt de screenshots toe).

### 2.7 Volgorde van de blokken: behouden, zichtbaar gemaakt, gemigreerd

Gekozen: **behouden** (de gebruiker wilde het), maar de ingang is niet meer alleen lang indrukken. `BlockOrder.swift` (eigenaar 0A) krijgt vier pagina's; de blok-id's staan vast zodat A en de kaarteneigenaars ze kunnen koppelen. Alleen pagina's met drie of meer blokken tonen "Volgorde aanpassen" (dus niet Sparen).

| `BlockPage` (raw value) | Titel | Blok-id's in standaardvolgorde (titel, symbool) |
|---|---|---|
| `overview` | Overzicht | `wealth` (Vermogen, `chart.pie`), `pots` (Spaarpotten, `tray.full`), `invest` (Beleggingen, `chart.line.uptrend.xyaxis`), `upcoming` (Komende dagen, `calendar.badge.clock`) |
| `month` | Maand | `flow` (Waar gaat je geld heen, `chart.bar.xaxis`), `income` (Inkomen, `eurosign.circle`), `expenses` (Uitgaven, `creditcard`), `distribute` (Verdelen, `square.split.2x2`), `bank` (Bankrekening, `building.columns`), `days` (Dag voor dag, `list.bullet.rectangle`) |
| `saving` | Sparen | `pots` (Spaarpotten, `tray.full`), `portfolio` (Beleggingen, `chart.line.uptrend.xyaxis`) |
| `planning` | Plannen | `goals` (Doelen, `flag.checkered`), `buffer` (Noodbuffer, `shield.lefthalf.filled`), `accelerators` (Versnellers, `bolt`), `projection` (Toekomstschatting, `calendar.badge.clock`), `purchase` (Aankoopcheck, `cart`) |

De kern van een pagina staat in de tabroot zelf, **boven** `OrderedBlocks(page:)`; `OrderedBlocks` kent alleen blok-id's uit de tabel. Ingangen: (1) menu in de werkbalk van een tabroot met drie of meer blokken, "Volgorde aanpassen…" (opent het korte blad `BlockOrderSheet`); (2) Instellingen, Indeling (`BlockOrderList` per pagina, direct in een pagina); (3) het contextmenu op een kaart blijft.

**Migratie** (`BlockOrderMigration.migrate(_ stored: [String: [String]]) -> [String: [String]]`, Foundation-only in `App/UI/BlockOrderMigration.swift`, tests in `BlockOrderMigrationTests`). Hij draait bij het lezen (`AppSettings.orderedBlocks(for:)`), is idempotent en schrijft niets terug tot de gebruiker zelf herordent. Oude sleutels en id's (`BlockOrder.swift:31-56`) gaan naar de nieuwe pagina's met behoud van hun onderlinge volgorde; nieuwe blokken komen achteraan in standaardvolgorde (zoals `orderedBlocks` al doet, `BlockOrder.swift:62-83`):

| Oud | Nieuw |
|---|---|
| `home`: `overview` | `month.flow` |
| `home`: `pots`, `invest` | `overview.pots`, `overview.invest` |
| `savings`: `period` | `month.flow` |
| `savings`: `income`, `bank`, `distribute` | `month.income`, `month.bank`, `month.distribute` |
| `savings`: `pots`, `portfolio` | `saving.pots`, `saving.portfolio` |
| `savings`: `buffer`, `goals` | `planning.buffer`, `planning.goals` |
| `tools`: `accelerators`, `projection`, `purchase` | `planning.accelerators`, `planning.projection`, `planning.purchase` |

### 2.8 Termenlijst (bindend)

Elke eigenaar past de teksten in zijn eigen bestanden aan. Het controlescript zoekt de linkerkolom.

| Begrip | Vaste naam | Vervangt (verboden in UI-tekst) |
|---|---|---|
| tabs | Overzicht, Maand, Sparen, Plannen, Instellingen | Home, Savings, Tools |
| wat er van het maandinkomen overblijft | **Nog te verdelen** (nu en komende maanden), **Overgehouden** (verleden, periodes) | kaal "Over", Over deze maand, Over op de rekening, Overschot |
| salaris en extra inkomsten | **Inkomen** met onderdelen **Salaris** en **Overige inkomsten** | Salaris & inkomsten, Salaris en inkomsten, Overig |
| kosten | **Uitgaven**, onderverdeeld **Vast** en **Variabel** | lasten, vaste lasten, Bankuitgaven (wordt "Van je rekening") |
| bedrag naar pot of belegging | **Inleg** | Overschrijving, Verdeeld als bedrag |
| dag van de overschrijving | **Overschrijfdag** | Eigen overschrijfdag inleg |
| minimum op de betaalrekening | **Minimumsaldo** | Bankbuffer, Buffer op bankrekening, Gewenste bankbuffer |
| noodgeld | **Noodbuffer** | Buffer, Spaarpot Buffer, Buffercalculator |
| doel in euro's | **Doel** (pagina "Spaardoel berekenen" voor de calculator) | Streefbedrag (veldnaam Doelbedrag mag) |
| winst in euro's | **Winst** | Rendement (als bedrag) |
| procent per jaar | **Rendement per jaar** | Verwacht rendement, Rendement na kosten |
| rente van een pot | **Rente** (alleen bij spaarpotten en de spaarrente-aanname) | Rentepercentage |
| saldo | **Saldo vandaag**, **Verwacht eind oktober** | Saldo nu, Saldo van vandaag, Saldo aan het eind van vandaag |
| dagoverzicht | **Dag voor dag** | Per dag, Alle dagen bekijken, dagoverzicht |
| gemeten waarde | **Waarde-update** | Meetpunt |
| bewerkformulier | **Bewerken** | Instellingen (bij een pot of belegging), Doel en instellingen, Rente aanpassen, Inleg aanpassen |
| app-instellingen | **Instellingen** | |
| beleggingen | **Beleggingen** | Portefeuille, Mijn beleggingen |
| Account en cloud | **Account**, **Synchronisatie** | Firebase (uit de UI) |
| keuze van wat op het Overzicht staat | **Kies potten…**, **Kies beleggingen…** (bladen: "Spaarpotten op het Overzicht", "Beleggingen op het Overzicht") | Spaarpotten op Home, Beleggingen op Home |
| sluitrekening van een saldo | **Zo komt je saldo tot stand**, **Zo komen je spaarpotten tot stand** | Maandoverzicht bank (als kaartkop in Dag voor dag) |
| startmaand van een belegging | **Belegd sinds** | Startmaand |

Hoofdlettergebruik: zinshoofdletter overal, geen HOOFDLETTERS in de UI (MNU-5, LST-2). Knoppen met een werkwoord: "Toevoegen", "Bewaar", "Annuleer". Op de Mac "klik", op iOS "tik" (WRT-1).

### 2.9 Zoeken

**`SearchIndex`** (pakket 0B, `App/Navigation/SearchIndex.swift`, Foundation-only, symlink in `CoreTests`): een vaste lijst `SearchIndex.pages: [SearchEntry]` met per `Destination`-case zonder id en per `SettingsPage`-case een titel, een symbool en alternatieve namen (Uitgaven, Dag voor dag, Noodbuffer, Rente, Back-up, Wachtwoord, Salaris, Koersen, Account, Belegd sinds, Minimumsaldo), plus `SearchIndex.results(for:in:)` dat daarnaast zoekt in de namen van spaarpotten, beleggingen, doelen en regels van inkomen en uitgaven. **`SearchIndexTests` zijn uitputtend**: een `switch` zonder `default` over alle `Destination`- en `SettingsPage`-cases dwingt af dat een nieuwe case een zoekregel krijgt, en elke regel heeft een titel en minstens een alternatieve term.

**Bediening** (K20). `searchToolbarButton()` (0A, een `ToolbarItem(placement: .automatic)` met `IconButton("Zoeken", symbol: "magnifyingglass")`) staat in de werkbalk van Maand, Sparen en Plannen en roept `router.requestSearch()` aan; Cmd+F doet hetzelfde (0B, `AppCommands`). `requestSearch()` gaat naar het Overzicht en verhoogt `router.searchRequest`; `OverviewTab` heeft `.searchable(text:isPresented:prompt: "Zoek in MyBuddy")` en opent het zoekveld bij elke verhoging. Een resultaat opent met `router.go(...)`. Geen treffers: `ContentUnavailableView.search(text:)`. Zo vindt iemand een onderdeel ook als hij de naam niet meer weet (audit 4.7; SRC-1 t/m SRC-3) en vanaf elke tab.

### 2.10 Taken in tikken (vanaf een willekeurige plek; tot het doelscherm of blad verschijnt; een tabwissel telt als tik)

De eerste versie telde "nu" soms tot en met het blad en "straks" zonder blad (kritiek F17). Hieronder staat de gecorrigeerde telling. **De claim is dus bescheiden: de indeling wint vooral op scrollen, benaming en vindbaarheid, niet op tikken**; twee taken worden korter (Dag voor dag, Spaardoel berekenen), zes blijven gelijk (door K9 ook Spaarpot storten en het zien van saldi), en drie worden een tik langer (Back-up maken, Wachtwoord wijzigen, Salaris wijzigen: een pagina in plaats van een sheet of een extra niveau).

| Taak | Nu | Straks |
|---|---|---|
| Instellingen openen | 1, alleen op een tabwortel | **1, overal** (Mac: Cmd+komma) |
| Dag voor dag bekijken | 3 | **2**: Maand, Dag voor dag |
| Spaardoel berekenen | 3 | **2**: Plannen, rij "Spaardoel berekenen" (`GoalsSummaryCard` heeft die rij altijd) |
| Uitgave toevoegen | 3 en scrollen | **3**, geen scrollen: Maand, Uitgaven, `+` |
| Back-up maken | 2 en scrollen | **3**, geen scrollen: Instellingen, Gegevens, Back-up maken |
| Nieuwe spaarpot | 2 | **2**: Sparen, `+` |
| Saldo invullen | 3 | **3**: Maand, Bankrekening, Saldo invullen |
| Geld verdelen | 1 | **1**: Overzicht, hero |
| Spaarpot storten | 2 (Home-tegel, chip) | **2** vanaf het Overzicht met een gekozen pot (tegel, Storten); 3 vanaf Sparen (pot, Storten) |
| Wachtwoord wijzigen | 2 (tandwiel, rij; sheet) | **3**: Instellingen, Account, Wachtwoord wijzigen (pagina in plaats van sheet) |
| Salaris wijzigen | 2 | **3**: Maand, Inkomen, Salaris instellen (bewust: "deze maand bekijken" en "inkomsten toevoegen" zijn vaker en blijven 2; in de lege start 1) |
| Saldo van een gekozen pot of belegging zien | 0 (tegel op Home) | **0** (tegel op het Overzicht); andere potten 1 (Sparen) |
| Volgorde aanpassen | lang indrukken | **2**: menu in de werkbalk, of Instellingen, Indeling |

## 3. Instellingen: een hele pagina, het account los

### 3.1 Opbouw (tab Instellingen, `SettingsView`)

Een `List` (insetGrouped) zoals de iOS-instellingen: vier secties, zes rijen, elke rij een `NavigationLink` met een korte waarde eronder. Geen sheet, geen "Klaar"-knop, grote titel "Instellingen". Op de Mac is dit het `Settings`-venster (par. 3.5) met dezelfde pagina's als panes.

```
Instellingen
 [1] Account                    > Account                 e-mail of naam, daaronder: Gesynchroniseerd om 14:02
 [2] Rekenen                    > Rekenen                 Inflatie 2%, spaarrente 2%
     Koersen                    > Koersen                 Automatisch, laatst bijgewerkt 9:41
 [3] Gegevens                   > Gegevens                Back-up, importeren, exporteren
     Indeling                   > Indeling                Volgorde van de blokken
 [4] Over MyBuddy               > Over                    Versie 1.0
```

De Account-rij staat bovenaan en is de enige rij met een `SymbolBadge` van 40 pt (`person.crop.circle`). Heeft de synchronisatie aandacht nodig (conflict, lokale gegevens uploaden), dan staat daar "Actie nodig" in `Theme.warning` met symbool `exclamationmark.triangle.fill`. Zonder Firebase-sleutel staat er "Alleen op dit apparaat". Dezelfde voorwaarde (`sync.importOffer != nil || sync.conflict != nil`, bestaande eigenschappen) zet een badge op de tab Instellingen (iOS en iPadOS), zodat een openstaand conflict ook op de andere tabs zichtbaar is.

### 3.2 Waar elke bestaande functie terechtkomt

Alle functies uit `SettingsView`, `AccountAndSyncSections`, `MarketDataSection` en `BackupSection` blijven bestaan.

| Functie nu | Plek straks | Bestand van de huidige code |
|---|---|---|
| E-mail of naam, "Ingelogd" | Account, sectie Profiel | `CloudViews.swift:100-114`, `AuthView.swift:614-649` |
| Synchronisatiestatus (7 toestanden), "Nu synchroniseren", "Laatst gesynchroniseerd", grootte-waarschuwing | Account, sectie Synchronisatie | `CloudViews.swift:149-231` |
| Conflict: "Bewaar deze versie" en "Neem cloud-versie over" | Account, sectie Synchronisatie (prominent zolang er een conflict is) | `CloudViews.swift:162-171` |
| Aanbod "Lokale gegevens uploaden?" (Uploaden, Niet uploaden) | Account, sectie Synchronisatie (zelfde plek) | `CloudViews.swift:329,361-364` |
| Back-ups van conflicten met "Terugzetten" | pagina `.settings(.conflictBackups)`, rij in Account, met swipe-actie "Zet terug" | `CloudViews.swift:192-219` |
| Wachtwoord wijzigen (cloud en lokaal) | pagina `.settings(.password)`, rij in Account (nu sheet) | `CloudViews.swift:387`, `AuthView.swift:653` |
| Uitloggen | knop in Account met bevestiging aan de knop | `CloudViews.swift:119`, `AuthView.swift:640` |
| Account verwijderen (cloud en lokaal) | pagina `.settings(.deleteAccount)`, onderaan Account, rood (nu sheet) | `CloudViews.swift:504`, `AuthView.swift:740` |
| Keychain-voetnoot | een zin onder Profiel | `CloudViews.swift:129-133` |
| Uitleg "Firebase aanzetten" met vier stappen | weg uit de app (blijft in `firebase/README.md`); Account zegt in een regel "Alleen op dit apparaat" | `CloudViews.swift:47-88` |
| Inflatie per jaar, Spaarrente, Opnamepercentage | Rekenen; het opnamepercentage heet "Opnamepercentage voor nieuwe doelen" (het is alleen de beginwaarde, `Goals.swift:218`) | `SettingsView.swift:24-26` |
| Buffer op bankrekening (mnd) | **alleen** het veld Minimumsaldo op Bankrekening (een plek, een naam) | `SettingsView.swift:27`, `SavingsPages.swift:1953` |
| Cijfers van internet: 3 ophaalknoppen, 2 resultaatkaarten, 3 bevestigingslabels | Rekenen, een rij "Actuele cijfers": een knop "Ophalen", dan twee rijen (inflatie, spaarrente) elk met "Gebruik" en een knop "Beide gebruiken"; "Laatst bijgewerkt" | `MarketDataUI.swift:167-231` |
| Koersen automatisch ophalen, "Nu vernieuwen", laatst bijgewerkt, foutmelding | Koersen | `SettingsView.swift:36-69` |
| "Koersverbinding testen" met diagnoseregels | Koersen, uitklapper "Geavanceerd" (dicht) | `SettingsView.swift:50-65` |
| Back-up exporteren (JSON), Importeren (JSON, Excel, CSV), Voorbeeldbestand | Gegevens, secties Back-up en Importeren | `BackupUI.swift:229-302` |
| CSV-export: Maandcijfers, Transacties, Beleggingen | Gegevens, sectie Exporteren (drie rijen) | `BackupUI.swift:293-301` |
| Importoverzicht (sheet in sheet, `SpreadsheetImportSheet`) | pagina `.settings(.importReview)` (`SpreadsheetImportPage`), geduwd vanuit Gegevens; de ingelezen gegevens staan in een `ImportCoordinator` (E) die vóór het openen wordt gevuld | `BackupUI.swift:586-817` |
| Voorbeelddata laden, Alles wissen, opslagfout | Gegevens, sectie Beheer (onderaan, rood, met cloudwaarschuwing in de dialoog); voorbeelddata staat ook in de lege staat van het Overzicht | `SettingsView.swift:77-93` |
| Over: versie (vast "1.0"), disclaimer | Over MyBuddy: versie uit de bundel, disclaimer, "Bronnen en privacy" (Yahoo Finance, Stooq, CoinGecko, Wereldbank, ECB, Firebase) | `SettingsView.swift:95-104` |
| Volgorde van de blokken (alleen lang indrukken) | Indeling, per tabpagina met drie of meer blokken (Overzicht, Maand, Plannen) een lijst met slepen en "Standaardvolgorde" | `BlockOrder.swift:153-165` |
| Tandwiel op de tabwortels | vervalt: Instellingen is een tab (iOS) of venster (Mac) | `Components.swift:35-43` |

De voetnoten krimpen tot maximaal twee zinnen (SET-7). Teksten als "end-to-end" en "HTTPS" gaan naar "Bronnen en privacy".

### 3.3 De pagina Account (`.settings(.account)`)

`ListScaffold`, inline titel "Account", symbool `person.crop.circle`.

1. **Profiel**: `SymbolBadge`, e-mailadres (lokaal: naam en e-mail), "Ingelogd". Een zin: "Je blijft ingelogd. Het wachtwoord staat niet op dit apparaat." of de waarschuwing dat de Keychain niet beschikbaar is.
2. **Synchronisatie** (alleen met Firebase-sleutel): statusrij, conflictknoppen of uploadaanbod als dat speelt, "Nu synchroniseren" (met `ProgressView` en `.disabled` tijdens het werk), "Laatst gesynchroniseerd", rij "Back-ups van conflicten (n)" naar de subpagina. Zonder sleutel: een rij "Alleen op dit apparaat. Er is geen synchronisatie tussen apparaten."
3. **Beveiliging**: rij "Wachtwoord wijzigen" naar `.settings(.password)`.
4. **Uitloggen**: een knop; `confirmationDialog` aan de knop met de gevolgzin uit `signOutMessage`.
5. **Account verwijderen**: eigen sectie onderaan, rij in `Theme.negative` naar `.settings(.deleteAccount)`; die pagina legt uit wat er gebeurt (ook in de cloud, kan niet ongedaan), vraagt het wachtwoord in een `SecureField` en heeft een destructieve knop met bevestiging (ACT-3, ALT-4).

De pagina's Wachtwoord en Account verwijderen zijn de huidige sheet-inhoud zonder eigen `NavigationStack` en zonder `MeshBackground`; invoer in `SecureField`, `submitLabel`, `@FocusState`-volgorde, melding bij de knop.

### 3.4 Geen sheets en geen alerts in Instellingen en Account

- Zes sheets verdwijnen: Instellingen, Wachtwoord wijzigen (2), Account verwijderen (2), Importoverzicht. `BackupHost` (de zes rijgebonden presentaties) vervalt: op een gewone pagina hangen `fileExporter` en `fileImporter` aan de pagina zelf. **Een `ExportDocument: FileDocument`** vervangt de drie bestaande documenttypen (`BackupUI.swift:83-129`) zodat er een `fileExporter` is in plaats van vier (twee exporters op een view hinderen elkaar, `BackupUI.swift:254`). `FileDocument.readableContentTypes` en `writableContentTypes` zijn statisch, dus beide lijsten zijn expliciet `[.json, .commaSeparatedText, BackupFileTypes.xlsx]`; `fileExporter(isPresented:document:contentType:...)` krijgt per export het juiste type uit die lijst.
- Melding "Bestand bewaard" en "Back-up teruggezet": een inline `NoticeCard` bovenaan de pagina en `sensoryFeedback(.success)`; "Exporteren mislukt": `NoticeCard` plus `.error`. Alleen wat onomkeerbaar is (Back-up terugzetten, Alles wissen, Account verwijderen, Zet terug) krijgt een `confirmationDialog` aan de knop. `.alert(` komt niet meer voor (ALT-1).
- Synchronisatiemeldingen bij de start ("Lokale gegevens uploaden?", "Welke versie wil je houden?") zijn nu twee alerts aan de wortel (`CloudViews.swift:318-376`, `MyBuddyApp.swift:138`). Straks: **geen alert bij het starten** (ALT-5). `SyncPromptsHost` en `.syncPrompts(_:)` verdwijnen (E definieert niets meer, 0B haalt de aanroep uit `SignedInRoot`); in plaats daarvan toont `SyncAttentionBanner()` (E, in `CloudViews.swift`) bovenaan het Overzicht een melding "Kies welke versie je houdt" of "Lokale gegevens uploaden?" met een knop "Naar Account" (`router.go(.settings(.account))`); de keuze zelf staat in Account. De voorwaarde is `sync.importOffer != nil || sync.conflict != nil` (bestaande eigenschappen van `SyncController`); dezelfde voorwaarde zet een badge op de tab Instellingen (iOS en iPadOS; op de Mac staat alleen de melding op het Overzicht). `sync.deferConflictPrompt()` blijft bestaan voor "Later".
- Het importoverzicht is **een echte bestemming**: `SettingsPage.importReview` (`SpreadsheetImportPage`), geduwd vanuit Gegevens met `router.open(.settings(.importReview))`. De ingelezen gegevens staan in een `@Observable ImportCoordinator` (E, in `BackupUI.swift`) die Gegevens vult vóór het openen; zo ziet de padlogica (`normalize`, `popToRoot`) de pagina en is `navigationDestination(item:)` niet nodig (kritiek 5.3).

### 3.5 macOS en iPad

- **macOS**: geen Instellingen-tab (K3). Een `Settings`-scene met Cmd+komma in `#if os(macOS)` (SET-4, MAC-3). Inhoud: een `TabView` met zes panes (Account, Rekenen, Koersen, Gegevens, Indeling, Over), elk `SettingsPane(page:)` met een eigen `NavigationStack` (Wachtwoord, Account verwijderen, Back-ups van conflicten en het Importoverzicht zijn pushes in die stack); venstertitel is de naam van de pane; de laatst gebruikte pane wordt onthouden (`@AppStorage("settings.pane")`); vaste breedte ongeveer 520 pt. De scene heeft de store van de actieve sessie nodig: `ActiveSession` (par. 4.4) staat boven de scenes en `SignedInRoot` registreert zijn `AppStore`, `Router` en `SyncController` daarin; `auth` en `cloud` staan op `MyBuddyApp` en worden **expliciet** in de scene geïnjecteerd (ze zitten niet in `ActiveSession`). Een diepe link naar een instellingenpagina zet `router.settingsRequest`; de wortel opent het venster met `openSettings()` op die pane. Is er niemand ingelogd, dan toont de scene "Log eerst in" (`ContentUnavailableView`). Alle commando's van `AppCommands` zijn dan uitgeschakeld.
- **iPad**: hetzelfde als iPhone: tab Instellingen in de zijbalk of de bovenbalk, pagina's als pushes op de stapel. Een toetsenbord geeft Cmd+5; het menu-item "Instellingen" van iPadOS blijft gereserveerd voor de systeeminstellingen (SET-9).
- **Leesbare breedte**: `ListScaffold` begrenst op `Theme.readableWidth` (720 pt) en centreert (LAY-7).

### 3.6 Kleine keuzes in Instellingen

Geen schakelaars voor weergave, taal, haptiek of biometrie (SET-3, ACT-4). **Het inlogscherm (`AuthView`)**: `MeshBackground` en de glaskaart weg (`Theme.canvas` met een `Card`), knoppen, tekstlinks en oogknoppen op `Theme.minTapTarget`; zijn logica verandert niet (K4). "Opnamepercentage" blijft als instelling maar met een uitleg van een zin. De waarschuwing "Opslaan is mislukt" staat op het Overzicht (bovenaan, met "Opnieuw proberen") en in Gegevens. Het app-icoon (iOS 26 verwacht een gelaagd icoon uit Icon Composer) valt buiten deze ronde (par. 8.3).

## 4. Ontwerpsysteem

### 4.1 Kleuren (semantisch, licht en donker, hoog contrast)

Systeemkleuren waar het kan (`.primary`, systeem-kaartkleur, systeemscheidingslijn), eigen kleuren alleen waar de olijftint of het contrast dat vraagt. Alle waarden staan in **`Theme.swift`** (de enige plek met `Color(hex:)`), als `Color(light:dark:lightContrast:darkContrast:)`; de hoog-contrastvariant is overal strikt sterker (donkerder in licht, lichter in donker). Alleen `AccentColor` staat ook in `Assets.xcassets` (drie appearances), omdat `project.yml` hem als globale accentkleur gebruikt. Contrast is berekend volgens WCAG (scripts `plan/tokens.py` en `plan/final.py` in de scratchpad; de uitvoer staat hieronder) tegen de kaartkleur: licht wit, donker `#1C1C1E` (de systeemwaarden van `secondarySystemGroupedBackground`). De laatste kolom geeft het contrast op `canvas`, de olijfachtergrond.

| Token | Licht | Donker | Hoog contrast (licht, donker) | Contrast op kaart (licht, donker) | Canvas (licht, donker) |
|---|---|---|---|---|---|
| `canvas` (paginaachtergrond) | `#EEF1E2` | `#0E1209` | zelfde, kaart krijgt een rand | n.v.t. | n.v.t. |
| `card` (kaart, lijstrij) | systeem: `secondarySystemGroupedBackground` (macOS `controlBackgroundColor`) | idem | idem | n.v.t. | n.v.t. |
| `tileFill` (tegel in een kaart) | `Color.primary` 6% | idem | 10% | n.v.t. | n.v.t. |
| `textSecondary` (uitleg, bijschrift) | `#566049` | `#B3BAA3` | `#3A4230`, `#D3D9C4` | 6,63 / 8,48 | 5,79 / 9,44 |
| `accent` (tint, knoptekst, pictogram) | `#3F5220` | `#A9C06B` | `#2C3A14`, `#C4D68C` | 8,61 / 8,46 | 7,51 / 9,41 |
| `accentFill` (gevulde knop) en `onAccent` (tekst erop) | `#3F5220` en `#FFFFFF` | `#A9C06B` en `#10140B` | zelfde | 8,61 / 9,26 (tekst op vulling) | n.v.t. |
| `positive` | `#2F5E1A` | `#B7D96F` | `#1F4510`, `#CBE88D` | 7,67 / 10,67 | 6,69 / 11,87 |
| `negative` | `#A12F18` | `#F29A7C` | `#7E2210`, `#FFB8A0` | 7,15 / 7,85 | 6,24 / 8,74 |
| `warning` | `#7A5800` | `#E3C25A` | `#5C4200`, `#F0D885` | 6,51 / 9,83 | 5,68 / 10,94 |

Gemeten voorheen (audit 3.5): `.secondary` 2,8 tot 3,2:1, `warning` 2,5 tot 3,4:1, wit op het donkere accent 2,0:1. Nu zijn alle tekstkleuren minstens 5,7:1 op canvas en kaart. Daarom: **`foregroundStyle(.secondary)` en `Color.secondary` verdwijnen overal** (300 plekken, mechanisch vervangen door `Theme.textSecondary`); op een gevulde knop staat `Theme.onAccent`, nooit `.white`. Positief en negatief dragen altijd een teken, symbool of woord (COL-4); het accent betekent "interactief" en wordt niet meer op niet-interactieve pictogrammen gebruikt, behalve in `SymbolBadge` met een domeinkleur (COL-5).

### 4.2 Domeinkleuren en grafiekkleuren

**Domeinkleuren** (`AppDomain.color`): alleen voor het pictogram in een `SymbolBadge` (kleur op een tint van 14%, licht, 18% donker) en voor het kaartsymbool; nooit voor tekst. Contrast van het pictogram op de kaart (licht / donker) en op zijn eigen badge:

| Domein | Licht | Donker | Pictogram op kaart | Op badge |
|---|---|---|---|---|
| overview | `#3F5220` | `#A9C06B` | 8,61 / 8,46 | 6,89 / 5,82 |
| money | `#9A4B26` | `#E39A74` | 6,16 / 7,41 | 5,03 / 5,29 |
| saving | `#2A6F66` | `#6FC2B4` | 5,89 / 8,14 | 4,85 / 5,69 |
| investing | `#3F5F8C` | `#8FB0E0` | 6,51 / 7,66 | 5,33 / 5,39 |
| goals | `#8A6A00` | `#E3C25A` | 5,07 / 9,83 | 4,22 / 6,54 |
| tools | `#74476A` | `#CF9BC3` | 7,36 / 7,40 | 5,95 / 5,27 |
| settings | `#5B6150` | `#B3BAA3` | 6,42 / 8,48 | 5,27 / 5,88 |

**Grafiekkleuren** (`Theme.chart*`, vervangen `Theme.flow*`): vlakken tegen de kaart minstens 3:1, onderling onderscheidbaar voor kleurenblinden, en altijd met een tweede kanaal (patroon, lijnstijl, label; CHT-5). Gemeten met een Machado-simulatie en deltaE76:

| Reeks | Licht | Donker | Op kaart (licht / donker) |
|---|---|---|---|
| `chartExpenses` (Uitgaven) | `#A24427` | `#E48A5E` | 6,19 / 6,56 |
| `chartVariable` (Variabele uitgaven, naast `chartExpenses` in de verdeelbalk) | `#C9835F` | `#F0B08E` | 3,05 / 9,16 |
| `chartSaved` (Gespaard) | `#2B7F72` | `#5FBFAE` | 4,79 / 7,74 |
| `chartInvested` (Belegd) | `#3C5A99` | `#8FAEE6` | 6,74 / 7,59 |
| `chartFree` (Over, Overgehouden) | `#A38F30` | `#EDE3A6` | 3,22 / 13,08 |

Kleinste onderlinge afstand van de vier hoofdreeksen: normaal 47 (licht) en 43 (donker); deuteranopie 19,5 en 23,6; protanopie 29,7 en 27,2. Dat is bruikbaar maar niet royaal: **het tweede kanaal is verplicht**. Voorheen was `flowExpenses` tegen `flowSaved` bij deuteranopie 6,9 en waren alle `flow*` onder 3:1 op de lichte achtergrond. Waarde, saldo en doel: lijn in `accent`, verwachting hetzelfde gestreept, doel een grijze (`textSecondary`) gestreepte `RuleMark`, tekort en negatief `negative`.

**Palet voor spaarpotten en beleggingssoorten** (`Theme.palette`, 8 kleuren, ook `Theme.color(_ index:)`): alleen voor pictogram en ring (niet-tekst, 3:1), nooit voor tekst, en altijd met symbool en naam erbij. Licht en donker apart waar de oude waarde onder 3:1 kwam:

| # | Naam | Licht | Donker |
|---|---|---|---|
| 0 | olijf | `#7C9440` (3,41) | `#7C9440` (5,00) |
| 1 | saliegroenblauw | `#4E8F86` (3,75) | `#4E8F86` (4,53) |
| 2 | mosterd | `#B08E21` (3,12, was 2,42) | `#C9A227` (7,03) |
| 3 | terracotta | `#C4704A` (3,64) | `#C4704A` (4,67) |
| 4 | leiblauw | `#5B7C99` (4,39) | `#5B7C99` (3,88) |
| 5 | pruim | `#8E5A7B` (5,39) | `#8E5A7B` (3,16) |
| 6 | salie | `#959575` (3,07, was 2,59) | `#A3A380` (6,57) |
| 7 | bruin | `#6B5B3E` (6,58) | `#796748` (3,12, was 2,59) |

Een beleggingssoort heeft overal dezelfde kleur: `HoldingKind.colorIndex` (in `ChartModels.swift`, F) wijst `Theme.color(_:)` aan; zowel de donut, `HoldingRow` en de tegels gebruiken dat (oplossing voor B-7 uit charts.md).

### 4.3 Typografie, maten, achtergrond en glas

- **Tekststijlen.** Alleen `.largeTitle` (tabtitel, door het systeem), `.title2` en `.title3`, `.headline` (kaartkop), `.body`, `.callout`, `.subheadline`, `.footnote`, `.caption`. Niet: `.system(size:)`, `.caption2`, `design: .rounded`, lichte gewichten. Bedragen: `.monospacedDigit()` en `.contentTransition(.numericText())`. Tokens: `Theme.heroAmount` (`.largeTitle.weight(.bold)`), `Theme.titleAmount` (`.title2.weight(.bold)`). Pictogrammen schalen mee: `SymbolBadge` gebruikt `@ScaledMetric` en een afbeelding in plaats van een vaste puntgrootte.
- **Krimpen.** `minimumScaleFactor` alleen in `BigAmount` (0,6, een regel). Labels, titels en uitleg wrappen. Rijen met label en bedrag (`AmountRow`) en rijen tegels (`FigureRow`) stapelen bij toegankelijkheidsformaten (`dynamicTypeSize.isAccessibilitySize`) en als ze niet naast elkaar passen (`ViewThatFits`).
- **Maten.** `Theme.cardRadius` 24, `Theme.cardInset` 16, `Theme.tileRadius` = 24 - 16 = 8 (concentrisch), `Theme.pageSpacing` 16, `Theme.sectionSpacing` 24, `Theme.rowSpacing` 12, `Theme.minTapTarget` 44 op iOS en 28 op macOS (`#if os(macOS)`; vervangt `buttonHeight` 42; ACC-2, MAC-9), `Theme.pageMaxWidth` 960 (kaartenraster), `Theme.readableWidth` 720 (lijsten en formulieren), `Theme.blockColumnMinimum` 340 (twee kolommen op iPad en Mac). Zijmarge van een pagina: `.scenePadding()` in plaats van `.padding(.horizontal, 16)`.
- **Achtergrond.** `Theme.canvas`, een vlak: een lichte olijftint in licht, bijna zwart olijfgroen in donker. De mesh-gradient (`MeshGradient`, negen kleuren, op elke pagina en in negen sheets herhaald) vervalt (DRK-3). Sheets, popovers en bevestigingen krijgen de systeemachtergrond: nergens `.background { ... }` in een sheet, geen `presentationBackground`. De wortel zet `.tint(Theme.accent)`.
- **Kaart.** `Card`: `Theme.card` met `RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)`, geen schaduw, geen glas. Bij `colorSchemeContrast == .increased` een rand van 1 pt in `Color.primary` 35%. Een kaart die naar een pagina leidt is een `NavigationLink` met een eigen `ButtonStyle` met drukstatus (`configuration.isPressed`), geen `.buttonStyle(.plain)` (BTN-1).
- **Wanneer glas.** Alleen wat het systeem zelf glas geeft: tabbalk (ook zijbalk en bovenbalk van iPad), werkbalk, `Menu`, `confirmationDialog`, sheets, zoekveld. **De eigen code tekent geen glas** (K5): ook de annotatie bij `chartXSelection` is `Theme.card` met een rand van 1 pt, omdat de GLS-1-uitzondering een bedieningselement zoals de knop van een schuifregelaar bedoelt en een tooltip dat niet is. `glassCard(`, `glassSurface(` en `.glassEffect(` mogen daarom alleen in `Glass.swift` voorkomen en in de eindcontrole nergens anders. `Glass.swift` blijft bestaan als compat (`glassCard`, `glassButton`) en bevat het ene hulpmiddel `glassSurface` voor zwevende bediening boven scrollende inhoud (iOS 26 `glassEffect`, anders `.regularMaterial`, bij Reduce Transparency dekkend `Theme.card`); in deze ronde gebruikt niets het en G verwijdert wat ongebruikt blijft. Knoppen in inhoud: `.bordered`, en voor de ene logische vervolgstap van een pagina `.borderedProminent` met `Theme.accentFill` en `Theme.onAccent` (`ActionButton(prominent: true)`); een prominente knop per scherm (BTN-2). Geen tint op kaarten (`tint: Theme.olive` verdwijnt, 13 plekken).
- **Geen eigen balken.** `barBackdrop` en `.fill(.bar)` verdwijnen; de inhoud scrolt onder de werkbalk en de tabbalk door (LAY-3, TAB-7).

### 4.4 Contract: exacte namen en handtekeningen

De bouwers coderen hierop. Wat hier staat mag niet worden hernoemd; uitbreiden met een parameter met standaardwaarde mag. Een afwijking meldt de bouwer onder **WIRING** (par. 6.1) aan de eigenaar. `docs/design/contract-check.sh` controleert niet alleen of een type bestaat maar ook zijn initializer (een `sig`-regel per symbool); het script en deze paragraaf horen gelijk te blijven.

**A. Navigatie en schil (pakket 0B, stap 0)**

```swift
// App/Navigation/NavigationModel.swift  (Foundation-only; symlink in CoreTests; tests: NavigationRulesTests)
enum AppTab: String, CaseIterable, Identifiable, Hashable { case overview, month, saving, planning, settings
    var id: String { rawValue }; var title: String; var symbol: String }       // titels en symbolen: par. 2.2
enum SettingsPage: String, CaseIterable, Hashable { case account, password, deleteAccount, conflictBackups,
                                                    calculations, prices, data, layout, about, importReview }
enum Destination: Hashable {
    case overview
    case income, salary, expenses, distribute, bank, cashflow
    case pots, pot(UUID), portfolio, holding(UUID)
    case goals, goal(UUID), savingsGoal, accelerators, buffer, projection, purchase
    case settings(SettingsPage)
}
extension Destination { var tab: AppTab }
enum NavigationRules {
    static func normalize(_ path: [Destination]) -> [Destination]                       // knipt af bij een herhaalde bestemming (K16)
    static func push(_ d: Destination, onto path: [Destination]) -> [Destination]       // normalize(path + [d])
    static func go(_ d: Destination) -> (tab: AppTab, path: [Destination])              // ouderpad + d (par. 2.6)
}
// App/Navigation/SearchIndex.swift  (Foundation-only; symlink in CoreTests; tests: SearchIndexTests, uitputtend)
struct SearchEntry: Identifiable, Hashable { let id: String; let title: String; let symbol: String
    let terms: [String]; let destination: Destination }
enum SearchIndex { static let pages: [SearchEntry]; static func results(for query: String, in data: FinanceData) -> [SearchEntry] }

// App/Router.swift
@MainActor @Observable final class Router {
    var tab: AppTab
    var paths: [AppTab: [Destination]]
    var orderPage: BlockPage?
    var focusMonth: YearMonth; var periodMode: PeriodMode                       // alleen Maand-tab en de pagina's eronder (K17)
    var searchRequest: Int                                                       // OverviewTab opent het zoekveld bij elke verhoging
    var settingsRequest: SettingsPage?                                           // macOS: de wortel opent het Settings-venster op die pane
    func pathBinding(for tab: AppTab) -> Binding<[Destination]>                  // set: NavigationRules.normalize
    func select(_ tab: AppTab)            // alleen wisselen
    func popToRoot(_ tab: AppTab)
    func open(_ d: Destination)           // zelfde tab als d: push met normalize; anders go
    func go(_ d: Destination)             // eigen tab van d, pad = ouderpad + d; macOS + .settings: settingsRequest
    func requestSearch()                  // go(.overview) en searchRequest += 1
    func showCurrentMonth(_ current: YearMonth); func shiftPeriod(_ direction: Int); func resetFocus(to current: YearMonth)
    // compat tot pakket G (doorverwijzing naar paths): var homePath, savingsPath, toolsPath: [Destination]; var showSettings: Bool
}
extension Destination { var domain: AppDomain }                                  // in Router.swift

// App/Navigation/*.swift
struct TabStack<Root: View>: View { init(_ tab: AppTab, @ViewBuilder root: () -> Root) }  // NavigationStack(path: router.pathBinding(for: tab)) + navigationDestination(for: Destination.self)
@MainActor @Observable final class ActiveSession { var store: AppStore?; var router: Router?; var sync: SyncController?
    func register(store: AppStore, router: Router, sync: SyncController?)
    func unregister(store: AppStore)      // wist alleen als `store` dezelfde instantie is (accountwissel)
}
struct AppCommands: Commands { init(session: ActiveSession) }                    // Cmd+1...5 (Mac 1...4), Cmd+F, Cmd+R, "Back-up maken…"
#if os(macOS)
struct SettingsScene: Scene { init(session: ActiveSession, auth: AuthStore, cloud: CloudAccount) }
#endif
struct DestinationView: View { let destination: Destination }                   // koppelt aan de paginanamen van de tabel in "D"
func chartMonths(mode: PeriodMode, focus: YearMonth) -> [YearMonth]              // blijft in DestinationView.swift
// App/Debug/DebugLaunch.swift (DEBUG): static var scrollTarget: String?  (-mybuddy-scroll-to), demoHolding (-mybuddy-demo-holding)
```

**B. Ontwerpsysteem (pakket 0A)**: `Theme.swift`, `Components.swift`, `Fields.swift`, `Glass.swift`, `MoneyViews.swift`, `BlockOrder.swift`, nieuw `Layout.swift`, `Motion.swift`, `RowActions.swift`, `Meters.swift`, `BlockOrderMigration.swift`

```swift
extension Color { init(hex: UInt32, opacity: Double = 1); init(light: Color, dark: Color)    // de tweede bestaat (Theme.swift:18-26)
                  init(light: Color, dark: Color, lightContrast: Color, darkContrast: Color) }   // nieuw; zelfde UIColor/NSColor-provider, uitgebreid met accessibilityContrast; hex alleen in Theme.swift
enum AppDomain: String, CaseIterable, Identifiable { case overview, money, saving, investing, goals, tools, settings
    var title: String; var symbol: String; var color: Color }
enum Theme {  // nieuw
    // notatie: elke naam hieronder is een eigen `static let` (contract-check.sh zoekt `static let textSecondary` enz.)
    static let canvas, card, tileFill, textSecondary, accent, accentFill, onAccent, positive, negative, warning: Color
    static let chartExpenses, chartVariable, chartSaved, chartInvested, chartFree: Color
    static let palette: [Color]; static func color(_ index: Int) -> Color; static let potSymbols: [String]
    static let heroAmount: Font, titleAmount: Font
    static let cardRadius, cardInset, pageSpacing, sectionSpacing, rowSpacing, pageMaxWidth, readableWidth, blockColumnMinimum: CGFloat
    static var minTapTarget: CGFloat                                                 // 44 op iOS, 28 op macOS (K21)
    static var tileRadius: CGFloat; static var blockColumns: [GridItem]
    static let motion: Animation, quickMotion: Animation
    // compat tot pakket G: olive, oliveDeep, oliveLight, flowExpenses, flowVariable, flowSaved, flowInvested, flowFree (= chart*),
    //   buttonHeight (= minTapTarget), chipRadius, MeshBackground() (tekent canvas)
}
// Pagina's en kaarten
struct PageScaffold<Content: View>: View { init(title: String, large: Bool = false, showsSettings: Bool = false /* verouderd, doet niets */, @ViewBuilder content: () -> Content) }
struct ListScaffold<Content: View>: View { init(title: String, large: Bool = false, @ViewBuilder content: () -> Content) }   // DEBUG: leest DebugLaunch.scrollTarget
struct Card<Content: View>: View { init(title: String? = nil, symbol: String? = nil, domain: AppDomain? = nil, subtitle: String? = nil, headerLink: Destination? = nil, @ViewBuilder content: () -> Content) }
struct LinkCard<Content: View>: View { init(title: String, symbol: String? = nil, domain: AppDomain? = nil, subtitle: String? = nil, destination: Destination, showsCurrentMonth: Bool = false, @ViewBuilder content: () -> Content) }
struct SectionHeader: View { init(_ title: String, symbol: String? = nil, domain: AppDomain? = nil) }          // kop in een List, isHeader
struct NavigationRow: View { init(title: String, symbol: String? = nil, domain: AppDomain? = nil, value: String? = nil, subtitle: String? = nil, destination: Destination) }
// Card(headerLink:), LinkCard, NavigationRow en ActionLink delen een privé DestinationLink: destination.tab == router.tab -> NavigationLink(value:), anders Button { router.go(d) } met .isLink (K16)
// Cijfers
struct BigAmount: View { init(value: Double, font: Font = Theme.heroAmount, color: Color = .primary, label: String? = nil) }
struct StatTile: View { init(title: String, value: String, color: Color = .primary, caption: String? = nil) }
struct FigureRow<Content: View>: View { init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) }         // StatTiles naast elkaar of gestapeld
struct AmountRow: View { init(title: String, value: String, detail: String? = nil, color: Color = .primary, symbol: String? = nil, bold: Bool = false) }
struct SymbolBadge: View { init(symbol: String, color: Color, size: CGFloat = 40) }
// Voortgang (App/UI/Meters.swift; eerder bij F, nu bij 0A)
struct ProgressMeter: View { enum Style { case bar(height: CGFloat = 8), ring(lineWidth: CGFloat = 7) }
    init(value: Double?, tint: Color, style: Style, label: String, valueText: String) }   // nil tekent niets
struct SegmentedMeter: View { struct Segment: Identifiable { let id: String; let title: String; let value: Double; let color: Color }
    init(segments: [Segment], label: String, valueText: String) }
// Knoppen en meldingen
struct IconButton: View { init(_ label: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) }  // minTapTarget, accessibilityLabel, .help(label)
struct ActionButton: View { init(title: String, symbol: String? = nil, role: ButtonRole? = nil, prominent: Bool = false, action: @escaping () -> Void) }   // controlSize .large op iOS, .regular op macOS
struct ActionLink: View { init(title: String, symbol: String? = nil, destination: Destination, prominent: Bool = false) }
struct ActionGroup<Content: View>: View { init(@ViewBuilder content: () -> Content) }                                // knoppen naast of onder elkaar
struct EmptyHint: View { enum Style { case inline, page }
    init(symbol: String, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil, style: Style = .inline) }
struct NoticeCard: View { init(text: String, symbol: String = "info.circle.fill", actionTitle: String? = nil, action: (() -> Void)? = nil) }   // nieuw naast het oude NoticeBanner in HomeView.swift (K7)
// Periode (K17)
struct MonthBar: View { init(month: Binding<YearMonth>? = nil) }                  // stapt per maand; zonder binding: router.focusMonth met MonthWindow-grenzen
struct PeriodPicker: View { init() }                                              // Maand, Half jaar, Jaar op router.periodMode; verschuift focusMonth niet
struct MonthStepper, PeriodControl, EqualSizeGrid, MonthWindow, accountPrefsID(...)   // API ongewijzigd (PeriodControl vervalt in G)
// Modifiers
extension View {
    func animated<V: Equatable>(by value: V, quick: Bool = false) -> some View      // .animation met Reduce Motion (Motion.swift)
    func rowActions(edit: (() -> Void)? = nil, delete: (() -> Void)? = nil, extra: [RowAction] = []) -> some View   // swipeActions + contextMenu
    func blockOrderToolbar(page: BlockPage) -> some View                               // menu "Volgorde aanpassen…" (alleen bij 3 of meer blokken)
    func searchToolbarButton() -> some View                                            // zoekknop in de werkbalk (K20)
}
struct RowAction: Identifiable { init(_ title: String, symbol: String, role: ButtonRole? = nil, tint: Color? = nil, action: @escaping () -> Void) }
// Formulieren (Fields.swift): NumberRow, IntStepperRow, OptionalNumberRow, OptionalDateRow, ChoiceRow, ContributionFields, ColorChoiceRow, SymbolChoiceRow, SafeInt, SaveChoices: API ongewijzigd
struct SheetScaffold<Content: View>: View { init(title: String, saveTitle: String = "Bewaar", canSave: Bool = true, hasChanges: Bool = false, onSave: @escaping () -> Void, saveChoices: SaveChoices? = nil, @ViewBuilder content: () -> Content) }
// Blokvolgorde (BlockOrder.swift, BlockOrderMigration.swift)
enum BlockPage: String, CaseIterable, Identifiable { case overview, month, saving, planning
    /* compat tot G: case home, savings, tools */ }                               // blok-id's: par. 2.7
struct OrderedBlocks<Content: View>: View { init(page: BlockPage, @ViewBuilder content: @escaping (String) -> Content) }   // alleen de blokken, niet de kern
struct BlockOrderList: View { init(page: BlockPage) }   // List in bewerkmodus, ook voor Instellingen, Indeling
struct BlockOrderSheet: View { init(page: BlockPage) }  // kort blad, opent met router.orderPage
enum BlockOrderMigration { static func migrate(_ stored: [String: [String]]) -> [String: [String]] }   // Foundation-only, par. 2.7
```

**C. Grafieken (pakket F)**: `App/UI/ChartModels.swift` (Foundation-only) en `App/UI/Charts.swift`

```swift
enum ChartSize { case compact, regular, tall }          // 96, 180, 240 pt (CHT-11)
struct TrendChart: View { init(model: TrendModel, size: ChartSize = .regular, showsAxes: Bool = true, nonNegative: Bool = false, onAction: @escaping (ChartEmpty.Action) -> Void = { _ in }) }
struct StackedBarChart: View { init(model: StackedBarModel, size: ChartSize = .regular, showsAxes: Bool = true) }
struct DonutChart: View { init(model: DonutModel, size: ChartSize = .regular) }
extension HoldingKind { var colorIndex: Int }
// TrendModel heeft: title, summary (VoiceOver), footnote: String? (bijvoorbeeld "Geschat uit je inleg, zonder rendement."), empty: ChartEmpty?, lijnen, markeringen, as
// Modelbouwers (Foundation-only); elk geeft altijd een model met `summary`, en `empty != nil` bij te weinig gegevens.
// Notatie: elke regel is de aanroep van een `static func model` (of `holdingKinds`, `months`) in een eigen `enum` of `struct` met die naam
PortfolioTrend.model(_ d: FinanceData, window: PortfolioWindow, current: YearMonth, today: Date, only: Set<UUID>? = nil) -> TrendModel
PriceTrend.model(history: [PricePoint], ticker: String, state: PriceTrend.LoadState) -> TrendModel   // LoadState: loading, loaded, failed(String)
NetWorthTrend.model(_ d: FinanceData, months: [YearMonth], current: YearMonth, today: Date) -> TrendModel
BankTrend.model(_ d: FinanceData, current: YearMonth, today: Date) -> TrendModel
DayBalanceTrend.model(items: [DayChartItem], range: DayChartRange, focus: YearMonth, today: Date) -> TrendModel
ProjectionTrend.model(start: Double, monthly: Double, annualReturn: Double, months: Double, unit: HorizonUnit,
                      target: Double, inflationAdjusted: Bool, inflation: Double) -> TrendModel
BufferTrend.model(_ result: BufferResult, start: YearMonth) -> TrendModel
SavingsGoalTrend.model(plan: SavingsGoalPlan, now: YearMonth) -> TrendModel
GoalCurveTrend.model(curves: GoalCurves, goalName: String, start: YearMonth) -> TrendModel
PotTrend.model(_ d: FinanceData, potID: UUID, current: YearMonth, today: Date) -> TrendModel
DonutModel.holdingKinds(_ d: FinanceData, current: YearMonth, today: Date) -> DonutModel
StackedBarModel.months(_ summaries: [MonthSummary], startMonth: YearMonth) -> StackedBarModel
```
Elk model heeft altijd een `summary` (VoiceOver) en een `empty` zodra er minder dan twee punten zijn. De typen komen uit bestaande Core-bestanden (`CurvePoint`, `BufferResult`, `SavingsGoalPlan`, `GoalCurves`, `DayChartItem`, `PricePoint`); wijzigt F een parameter, dan meldt F dat meteen onder WIRING aan de pagina-eigenaar (D, B2, C, A). Afwijking van charts.md 6.2: `height:` is vervangen door `size: ChartSize`; `PortfolioTrend.model` krijgt `only:` voor de detailpagina en `derived:` vervalt omdat `isEstimated` uit Core komt (C2). De annotatie bij een gekozen punt is `Theme.card` met een rand van 1 pt (K5), geen glas.

**D. Paginanamen en kaarten die eigenaren moeten behouden** (A en 0B coderen hierop)

| Eigenaar | Symbool | Handtekening |
|---|---|---|
| A | tabroots | `OverviewTab()`, `MonthTab()`, `SavingTab()`, `PlanningTab()` (alleen inhoud, zonder `NavigationStack`) |
| B1 | pagina's | `IncomePage()`, `SalaryPage()`, `ExpensesPage()`, `DistributePage()` |
| B1 | blad | `MoneyLineSheet(line: MoneyLine?, kind: FinanceData.LineKind, month: YearMonth, defaultExpenseKind: ExpenseKind)` (ongewijzigd; B2 gebruikt hem) |
| B2 | pagina | `BankPage(section: BankSection = .balance)`, `enum BankSection: String, CaseIterable, Identifiable { case balance, days, entries }` |
| B2 | kaart | `UpcomingDaysCard()` |
| C | pagina's | `PotsPage()`, `PotDetailPage(potID: UUID)`, `PortfolioPage()`, `HoldingDetailPage(holdingID: UUID)` |
| C | kaarten | `PotsSummaryCard()`, `PortfolioSummaryCard()` (Sparen), `HomePotsCard()`, `HomeHoldingsCard()` (Overzicht) |
| C | bladen en overig | `FavoritePotsSheet()`, `FavoriteHoldingsSheet()`, `PotEditSheet(pot: Pot?)`, `HoldingEditSheet(holding: Holding?)`, `GainBadge(gain: Double, fraction: Double?)` |
| D | pagina's | `GoalsPage()`, `GoalDetailPage(goalID: UUID)`, `SavingsGoalPage()`, `AcceleratorsPage()`, `BufferPage()`, `ProjectionPage()`, `PurchasePage()` |
| D | kaarten | `GoalsSummaryCard()`, `BufferSummaryCard()`, `AcceleratorsSummaryCard()`, `ProjectionSummaryCard()`, `PurchaseSummaryCard()` |
| E | pagina's | `SettingsView()` (tabroot), `SettingsDestination(page: SettingsPage)`, `SettingsPane(page: SettingsPage)` (Mac, met eigen `NavigationStack`), `AuthView()` |
| E | melding | `SyncAttentionBanner()` |

Alle `*Card`-views hebben een lege `init()`, lezen hun gegevens zelf uit `AppStore` en `Router` en bevatten hun eigen sheets en lege staat. Alle pagina's lezen `store` en `router` uit de environment.

**E. Bevroren typen die over eigenaarsgrenzen worden gebruikt** (kritiek F8): alleen toevoegen, nooit hernoemen, verplaatsen of van parameters veranderen; een verhuizing mag pas als de gebruiker ervan in het andere pakket is aangepast.

| Type (definitie) | Eigenaar | Gebruikt door |
|---|---|---|
| `ContributionInfo`, `ContributionPreview`, `PotDeleteEffect`, `PotUpcoming`, `PotUpcomingItem`, `TransferDayOrigin`, `MonthBoard`, `MoneyLabels` (`MoneyFigures.swift`) | B1 | C, A, B2 |
| `DisplayRounding` (`MoneyFigures.swift`) | B1 | 0A (`MoneyViews.swift`) |
| `DayText`, `CashflowText`, `CashflowSummary`, `CashflowRow`, `LedgerCheck`, `DayChartItem`, `DayChartRange` (`CashflowDisplay.swift`) | B2 | B1, C, F, A |
| `LedgerLineRow`, `DayEventRow`, `DayFlowTiles`, `DayBalanceRows`, `CashflowCheckBanner` (`CashflowPages.swift`) | B2 | A (`CashflowCheckBanner`) |
| `PotFormat`, `PotInterestStats` (`PotDisplay.swift`) | C | B2, B1, A |
| `SafeInt`, `ChoiceRow`, `SaveChoices`, `NumberRow`, `NumberUnit` (`Fields.swift`) | 0A | B1, D, C, E |
| `MonthFigures`, `PeriodSummary` (`Plan.swift`), alle overige `App/Core` | F (poortwachter) | iedereen |

### 4.5 Componenten: oud naar nieuw

| Oud (`Components.swift` e.a.) | Nieuw | Wat verandert | Compat |
|---|---|---|---|
| `PageScaffold(title:showsSettings:)` | `PageScaffold(title:large:)` | ScrollView op `Theme.canvas`, geen mesh, geen paginabrede `.animation`, `.scenePadding()`, titel `.inline` tenzij `large`, geen tandwiel; DEBUG-scrolloffset blijft | `showsSettings` bestaat nog en doet niets |
| (nieuw) | `ListScaffold(title:large:)` | `List` (`.insetGrouped` achter `#if os(iOS)`, anders `.inset`), `scrollContentBackground(.hidden)` op `canvas`, `readableWidth` | n.v.t. |
| `GlassBlock` (92x) | `Card` | geen glas; kaartkleur; kop is `isHeader`; `tint` en `interactive` vervallen | `GlassBlock(title:symbol:subtitle:headerLink:showsChevron:interactive:tint:content:)` stuurt door naar `Card` |
| `LinkedBlock` (12x) | `LinkCard` | `NavigationLink` met drukstatus | `LinkedBlock(...)` stuurt door |
| `SectionLabel` (dode code) | `SectionHeader` | geen hoofdletters | verwijderd |
| `StatTile` (85x) | `StatTile` | titel wrapt (2 regels), bedrag `.callout` semibold met cijferuitlijning, `caption` in `.footnote`, `accessibilityElement(.combine)` | zelfde API |
| (HStack of `LazyVGrid` van 3 tegels) | `FigureRow` | stapelt bij AX-formaten en smalle breedte | n.v.t. |
| `BigAmount(value:font:color:)` | `BigAmount(value:font:color:label:)` | tekststijl, `monospacedDigit`, enige plek met `minimumScaleFactor`, VoiceOver-label met "euro" | zelfde API (`font:` met oude `.rounded`-waarden werkt nog maar moet weg) |
| `ChipButton(title:symbol:role:action:)` (77x), `ChipLink` (6x), `ChipLabel` (3x), `ChipGrid` | `ActionButton`, `ActionLink`, `ActionGroup` | systeem `.bordered` of eigen prominente stijl, `Theme.minTapTarget`, drukstatus, tekst wrapt, `controlSize(.large)` op iOS en `.regular` op macOS | `Chip*` bestaan nog, sturen door |
| (kale `Image` in `Button`) | `IconButton` | `Theme.minTapTarget` (44x44 op iOS, 28x28 op macOS), verplicht label, `.help` | n.v.t. |
| `EmptyHint(symbol:title:message:actionTitle:action:)` (14x) | `EmptyHint` met `style` | `.page` is een `ContentUnavailableView`, `.inline` (standaard) een compacte versie binnen een kaart | zelfde API |
| `NoticeBanner` (in `HomeView.swift`) | `NoticeCard` in `Components.swift` | `Theme.card`, `Label`, `ActionButton` | `NoticeBanner` blijft in `HomeView.swift` tot A het verwijdert (golf 1c); C migreert zijn aanroepen in golf 1a |
| `ProgressBar`, `ProgressRing` (14 plekken), `SegmentBar` (1) | `ProgressMeter`, `SegmentedMeter` (pakket 0A, `Meters.swift`) | label en waarde voor VoiceOver, `nil` is "geen doel", `0,5%` niet meer als 8 pt | `ProgressBar(progress:tint:height:)` en `ProgressRing(progress:tint:lineWidth:)` in `Components.swift` sturen door naar `ProgressMeter` |
| `SymbolBadge` | `SymbolBadge` | schaalt met `@ScaledMetric`, geen `.font(.system(size:))` | zelfde API |
| `MonthStepper`, `PeriodControl`, `StepButton` | idem, plus `MonthBar` en `PeriodPicker` | raakdoel `Theme.minTapTarget`, kleur uit `textSecondary`, `Verwacht` met woord | zelfde API; `PeriodControl` vervalt in G |
| `MonthPickerBlock` (`SavingsPages.swift:183`) | `MonthBar` | geen glaskaart; stapt per maand | `MonthPickerBlock` blijft tot golf 1c (B1 verwijdert); B2 gebruikt `MonthBar` |
| `EqualSizeGrid` | idem | ongewijzigd | zelfde |
| `MeshBackground` | `Theme.canvas` | vlak | `MeshBackground()` tekent het canvas; weg in G |
| `GlassTabBar`, `barBackdrop` | `TabView` | zie par. 2.1 | verwijderd door 0B |
| `Theme.flow*` | `Theme.chart*` | par. 4.2 | alias tot G |
| `.animation(Theme.motion, value:)` (62x) | `.animated(by:)` | respecteert Verlaag beweging | `Theme.motion` blijft bestaan |
| `NumberRow` | `NumberRow` | label wrapt, `minHeight` `Theme.minTapTarget`, `.submitLabel(.next)`, `accessibilityLabel`, eenheid met `textSecondary` | zelfde API |
| `IntStepperRow`, `OptionalNumberRow`, `OptionalDateRow`, `ChoiceRow` | idem | `Theme.minTapTarget`, `textSecondary`, `tile()` op ChoiceRow blijft | zelfde API |
| `SheetScaffold` | `SheetScaffold` + `hasChanges` | geen mesh; veeg-om-te-sluiten uit bij wijzigingen (`interactiveDismissDisabled(hasChanges)`) en bevestiging ("Bewaar", "Gooi weg", "Verder bewerken") bij Annuleer, de twee `confirmationDialog`s aan verschillende subviews; `presentationSizing(.form)` (iOS 18, macOS 15); `.success`-haptiek bij Bewaar; Return bewaart | `hasChanges` heeft een standaardwaarde |
| `ColorChoiceRow`, `SymbolChoiceRow` | idem | `Theme.minTapTarget`, namen voor VoiceOver, vinkje in `onAccent` op de kleur | zelfde API |
| `AllocationWarningLabel`, `RoundingNote`, `ContributionSummary` (`MoneyViews.swift`) | idem | herkleurd, geen `caption2` | zelfde API |
| `glassCard`, `glassSurface`, `glassButton`, `.tile()` (`Glass.swift`) | `glassSurface` blijft als enig hulpmiddel voor zwevende bediening (nu ongebruikt); `glassCard` en `glassButton` vervallen voor inhoud; `.tile()` blijft | zie par. 4.3 | `glassCard` en `glassButton` bestaan tot G |

### 4.6 Gedragsregels voor alle bouwers

- **Beweging.** Animaties alleen op concrete waarden via `.animated(by:)`. Geen `.animation(...)` op een hele pagina. Overgangen met schaal of blur zijn verboden; fade volstaat. `MOT-5`: verandert een grafiek met animatie, dan verandert ook zijn samenvatting.
- **Haptiek.** `sensoryFeedback(.success, trigger:)` na Bewaar (zit in `SheetScaffold`), na een geslaagde export, import en synchronisatie; `.error` bij een fout; `.warning` bij een bevestiging die verwijdert; `.selection` bij wisselen van periode of segment. Nooit als enige feedback, nooit een eigen aan/uit.
- **Rij-acties.** Elke bewerkbare rij is een rij in een `List` met `rowActions(edit:delete:extra:)`: swipe (verwijder rood, daarna bewerken) en hetzelfde in het contextmenu, destructief laatst (LST-3, LST-8). Het bevestigingsgedrag van een verwijdering blijft zoals nu (een `confirmationDialog` aan de rij of knop waar dat al zo is, bijvoorbeeld bij een pot, een belegging, een doel en een terugkerende regel); alleen de ingang wisselt. "Maak ongedaan" staat onder "Niet in deze ronde".
- **Toegankelijkheid.** Elke kaartkop en sectiekop is een kop. Elk getal met titel is een element (`.combine`) met label "Over: 1.250 euro". Elke pictogramknop is een `IconButton` (label verplicht). Elke grafiek heeft titel, samenvatting en lege staat (par. 5). Elke `NavigationLink`-rij is een element. `accessibilityInputLabels` bij lange of dubbele knoplabels.
- **Platform.** Geen `UIDevice` of `userInterfaceIdiom`; gebruik `horizontalSizeClass` of `ViewThatFits`. `#if os(iOS)` om `keyboardType`, `navigationBarTitleDisplayMode` (liever `toolbarTitleDisplayMode`), `hoverEffect`. `.help(...)` bij elk pictogram (zit in `IconButton`). `.hoverEffect(.highlight)` op eigen aanklikbare kaarten (iOS, `#if os(iOS)`). Maten die per platform verschillen (`Theme.minTapTarget`, `controlSize`) staan achter `#if os(macOS)`.
- **iOS 26.** Alle iOS 26-API's alleen achter `#available(iOS 26.0, macOS 26.0, *)` met terugval op iOS 18 (`.tabBarMinimizeBehavior`, `.glassEffect`, `.glass`).
- **Voorbeelden.** `ComponentGallery.swift` (alleen `#if DEBUG`, eigenaar 0A) toont elk component met `#Preview` in licht, donker, hoog contrast en `.accessibility3`; de tabroots en pagina's krijgen elk een `#Preview` met voorbeelddata (`store.loadSampleData()`), zodat de eindcontrole snel kan.

## 5. Grafieken

### 5.1 Waarom de grafiek bij Beleggingen niet werkt (samengevat uit `charts.md` en `audit.md`, beide met proefscripts tegen `App/Core`)

1. **Core tekent alleen uit meetpunten.** `historicState` geeft `nil` zonder meetpunt (`Invest.swift:41`) en `portfolioSeries` slaat zulke maanden over (`:168`). "Totaal ingelegd", "Inleg per maand", startmaand, ticker en aantal doen niets zolang er geen meetpunt is: waarde, ingelegd en reeks zijn dan 0 (gemeten bij een ticker zonder koers, alleen inleg, ingelegd plus inleg, een startmaand in het verleden, een ticker zonder aantal).
2. **De invoer maakt zelden een meetpunt.** Een handmatige belegging krijgt er een bij "Huidige waarde" groter dan 0 (`PortfolioPages.swift:706`), maar dat veld staat alleen bij nieuw en zonder ticker (`:494`). Een gevolgde belegging krijgt er een pas als de koers binnenkomt en het aantal groter dan 0 is (`Invest.swift:270`). Offline, onbekende ticker of leeg aantal: nooit een punt.
3. **De pagina maskeert dat met een onjuiste tekst** ("De grafiek groeit mee zodra er meer meetpunten zijn", `PortfolioPages.swift:72`: staat alleen bij 0 punten). Home en Savings tekenen een lege `Chart` (`HomeView.swift:414`, `SavingsView.swift:276`).
4. **Met een punt** is het beeld een stip plus 12 maanden stippellijn; de keuzebalk 6 mnd, 1 jaar, 3 jaar verandert niets; de y-labels zijn gelijk (`€1,1k` drie keer).
5. **Bewerken van "Totaal ingelegd" doet niets** zolang er een meetpunt is (audit C3: scherm toont 5.000, opgeslagen 6.000), en de grafiek toont geen "Ingelegd".

### 5.2 Herstel in Core (eigenaar F; elke wijziging met tests, `CoreTests` blijft groen)

| # | Functie | Gewenst gedrag |
|---|---|---|
| C1 | `historicState` (`Invest.swift:38`), `holdingState` (`:70`) | Zonder meetpunt en met `investedTotal > 0` of een inleg: een **afgeleid beginpunt** op `startMonth.firstDay` met `value = invested = max(0, investedTotal - inleg van startMonth+1 t/m current)`; voor de lopende maand telt een inleg pas als zijn overschrijfdag geweest is (`DayMath.isPlanned`, zoals `:48-52`). Er wordt **niets** in `snapshots` geschreven (geen verzonnen punt in Meetpunten of de back-up); een echt meetpunt neemt het over. Zonder bedrag en zonder inleg: `nil`, dus een lege staat. `historicState` krijgt `current` als parameter. |
| C2 | `HoldingState`, `PortfolioPoint` | `isEstimated: Bool`; de pagina toont "Geschat" bij het bedrag en verbergt "Winst" en "Rendement" zolang het geschat is. |
| C3 | nieuw `portfolioDataStart(current:today:) -> YearMonth?` | Eerste maand met een meetpunt of afgeleid beginpunt; het venster (6 mnd, 1 jaar, 3 jaar, Alles) begint daar en `PortfolioWindow.options(availableMonths:)` toont alleen keuzes die iets veranderen. |
| C4 | `holdingState` na `current` | `value = max(0, value * (1 + rm) + a)`: geen negatieve verwachte waarde (was -2.637). |
| C5 | `valueByKind` | leest C1 via `holdingValueNow`; de donut krijgt dus ook een afgeleide waarde. |
| C6 | **niet in deze ronde** | B-10 (inleg van de meetpuntmaand) en B-11 (aantal bijhouden bij gevolgde beleggingen): ontwerpvragen voor de Core-eigenaar, veranderen `HoldingDayTests` en `InvestTests`. |
| C7 | `netWorthSeries` (`Overview.swift:32`) | `NetWorthPoint.bankKnown: Bool` voor een noot "Zonder banksaldo". Weglaten van maanden vóór `startMonth` gebeurt in de modelbouwer. |
| C8 | nieuw `potSeries(_:from:count:current:) -> [PotPoint]` in `Pots.swift` | Saldo per maand-einde en verwacht, zoals `netWorthSeries` het per pot doet. Voor het Verloop van een spaarpot (G16). |
| C9 | `updateHolding` (`Invest.swift:217`) | Voor een niet-gevolgde belegging met minstens een meetpunt en een gewijzigd `investedTotal`: een meetpunt van vandaag met de huidige waarde en het nieuwe bedrag (audit C3), zodat "Ingelegd" op scherm en opgeslagen gelijk zijn. |

Gevolg dat de eigenaar moet weten: C1 verandert getallen. Een belegging zonder meetpunt telde als 0 in Vermogen (`netWorthSeries`), doelen (`goalInputs(.portfolio)`) en de verdeling; dat wordt nu de ingevulde inleg. Dat is bedoeld. `HoldingDayTests.testHoldingWithoutMeasurementHasNoStateNow` (`:217-225`) legt het oude gedrag vast en wordt aangepast (de enige test die faalt, gemeten in een kopie van Core; 1.492 tests). De vijf tests uit `PortfolioSeriesDerivedTests` (`charts-prototype.md` B2) komen in `CoreTests`: drie falen op HEAD, alle vijf slagen met C1.

**Invoer en reproduceerbaar bewijs voor Beleggingen (K19; pakket C, 0B en G).** Core alleen is niet genoeg: de gebruiker vult een formulier in, en dat formulier mist de invoer die de grafiek zinvol maakt (kritiek F5).

1. **`HoldingEditSheet`** (`PortfolioPages.swift:409-715`, pakket C): (a) een nieuwe keuze **"Belegd sinds"**: een `Picker` (menu) over de laatste 10 jaar in maanden, standaard de huidige maand bij een nieuwe belegging en `holding.startMonth` bij wijzigen; het schrijft `Holding.startMonth` (bestaat al, `Models.swift:524`; geen nieuw `Codable`-veld). Nu maakt `draftHolding()` altijd `Holding(name: "", startMonth: store.now)` (`PortfolioPages.swift:682`), zodat een via de UI ingevulde belegging nooit geschiedenis kan krijgen. (b) "Huidige waarde" ook bij een belegging met ticker en bij wijzigen (nu alleen bij nieuw en zonder ticker, `:493-494`); leeg betekent koers maal aantal zodra die binnen is, en bij wijzigen werkt het het bestaande meetpunt van vandaag bij (C9). (c) Bij een ticker zonder aantal de uitleg "Vul ook het aantal stuks in, anders kan de app de waarde niet uitrekenen". (d) Onder de bedragen een zin: "Met Belegd sinds en Totaal ingelegd tekent de app de groei vanaf die maand, zonder rendement. Vul Huidige waarde in voor de echte waarde."
2. **Onderschrift** (`TrendModel.footnote`, pakket F): bij een afgeleide lijn "Geschat uit je inleg, zonder rendement." en het label "Geschat" bij het bedrag. De lijn heeft waarde gelijk aan ingelegd, dus Winst en Rendement zijn verborgen (C2); het onderschrift zorgt dat hij niet als werkelijke groei wordt gelezen.
3. **Bewijs dat het gemelde geval werkt.** (a) `DebugLaunch` (0B): `-mybuddy-demo-holding only-invested` (belegging "Demo", soort ETF, Totaal ingelegd 3.000, Inleg per maand 200, Belegd sinds 8 maanden geleden, geen ticker, geen meetpunten), `ticker-no-units` (ticker `VWCE.DE` zonder aantal) en `tracked-offline` (ticker met aantal, geen koers). (b) `scripts/ci-screenshots.sh` (G) maakt per scenario een screenshot van `portfolio` en `holding0`. (c) De tests uit par. 5.5. Zonder (a) en (b) wordt het gemelde geval nergens uitgevoerd in de UI: de voorbeelddata heeft zes meetpunten per belegging en toont het dus niet.

### 5.3 De gedeelde grafieklaag (pakket F)

Twee lagen, zodat de logica testbaar is zonder SwiftUI:

1. `App/UI/ChartModels.swift` (Foundation-only, symlink in `CoreTests` zoals `CashflowDisplay.swift`): `ChartPoint` (soorten `actual`, `estimated`, `projected`), `ChartLine`, `ChartMarker`, `ChartEmpty` (symbool, titel, uitleg, actie), `TrendModel`, `DonutModel`, `StackedBarModel`, `ChartAxis` (`domain` altijd `lo < hi` en eindig, `ticks`, `yLabels` nooit twee gelijke naburige labels, `monthLabel`, `monthStride`, `downsample` houdt eerste en laatste punt), `ChartText` (bedragen voor VoiceOver), `PortfolioWindow`, en de modelbouwers uit par. 4.4 C. Startpunt: de code in `charts-prototype.md` B3 (gecompileerd en gedraaid) en B4 (SwiftUI-schets, alleen syntaxis gecontroleerd).
2. `App/UI/Charts.swift` (SwiftUI): `TrendChart`, `StackedBarChart`, `DonutChart`, `ChartEmptyView` (de voortgangsmeters staan bij 0A in `Meters.swift`). Ze lezen alleen het model en tekenen zelf de assen.

Conventies (uit `charts.md` 6.4, hier bindend voor alle grafieken):

| Onderwerp | Regel |
|---|---|
| Hoogtes | `.compact` 96 pt (Overzicht, Sparen), `.regular` 180, `.tall` 240 (hoofdgrafiek van een pagina); nu 90 tot 210 verspreid |
| x-as | altijd zelf aangestuurd: maanden met `monthStride`, korte Nederlandse maand uit `Fmt.shortMonth`, januari met jaartal; dagen met `DayText.short`; Toekomstschatting verstreken tijd in de gekozen eenheid |
| y-as | eigen ticks en unieke labels, `Fmt.compact` alleen als dat unieke labels geeft; centen bij tickafstand onder 1 euro |
| Domein | altijd vast (`ChartAxis.domain`, 8% ruimte, bij een vlakke reeks 5% of minstens 1 euro), `includeZero` voor staven en voortgang, `nonNegative` voor beleggingen en potten |
| Soorten punten | werkelijk: volle lijn met vlak; afgeleid: dunne lijn met korte stippen, geen vlak, met uitleg erbij (`TrendModel.footnote`); verwacht: gestreepte lijn; een enkel werkelijk punt: een stip met tekst |
| Niet alleen kleur | meer dan een lijn: lijnstijl (vol, gestreept, gestippeld) en bij `accessibilityDifferentiateWithoutColor` een symbool en een label aan het laatste punt; staven: vaste volgorde, inkomenslijn als `RuleMark`, bedragen als tekst na een tik; markeringen hebben een tekst |
| Lege staat | `model.empty != nil` toont een `ContentUnavailableView` op dezelfde hoogte als de grafiek (geen sprong); `.compact`: een regel. Nul punten is nooit een lege `Chart`; een punt is een stip met uitleg; pas vanaf twee punten een lijn |
| Toegankelijkheid | `.accessibilityChartDescriptor` (titel, `summary`, elk punt) op `TrendChart`, `StackedBarChart`, `DonutChart`; meters: `accessibilityElement(.ignore)` met label en waarde; zichtbaar onderschrift met de kernwaarde (CHT-6) |
| Beweging | `accessibilityReduceMotion` leest elke component; een grafiek die met animatie verandert, verandert ook zijn samenvatting |
| Kleuren | alleen `Theme.chart*`, `Theme.accent`, `Theme.negative`, `Theme.color(_:)` (par. 4.2); geen eigen kleuren per grafiek; geen eigen achtergrond (geen glas op glas) |
| Interactie | optioneel `chartXSelection` (iOS 17, macOS 14) met `RuleMark` en een annotatie in `Theme.card` met rand (K5, geen glas); alles daarin staat ook zonder interactie als tekst |

### 5.4 Per grafiek: fix en wie hem aansluit

De component en het model komen van F (golf 0b); de pagina-eigenaar sluit ze in golf 1a aan (A in golf 1b) in zijn eigen bestand en verwijdert het oude grafiektype.

| ID | Grafiek | Gebrek | Fix | Aansluiten |
|---|---|---|---|---|
| G1 | Beleggingen, Groei | geen punten zonder meetpunt, onjuiste tekst, keuzebalk doet niets, geen "Ingelegd" | C1 t/m C5; `TrendChart(PortfolioTrend.model(...), size: .tall, nonNegative: true)`; keuzebalk alleen met `PortfolioWindow.options`; tweede lijn "Ingelegd" (dunne volle lijn in `textSecondary`); "Geschat" en het onderschrift "Geschat uit je inleg, zonder rendement." bij `isEstimated`; "Belegd sinds" in het formulier (K19) | C (`PortfolioPages.swift`) |
| G2 | Verdeling | blok weg bij een soort, kleur per rangorde | `DonutChart(DonutModel.holdingKinds(...))` ook bij een soort, kleur per soort, lijst met bedrag en percentage | C |
| G3 | Koers laatste jaar | dubbele y-labels, oude koers blijft staan | `PriceTrend` met unieke labels, `history = []` bij elke ticker, laad- en foutstaat met "Probeer opnieuw" | C |
| G4 | Belegging, Waarde | blok verdwijnt zonder uitleg | segment Koers / Waarde in een blok, `PortfolioTrend.model(only:)` | C |
| G5 | Overzicht en Sparen, lijntje | lege vlakte | `HomeHoldingsCard` en `PortfolioSummaryCard`: `TrendChart(size: .compact, showsAxes: false)` met begin- en eindwaarde als tekst; lege staat in een regel | C |
| G6 | Per maand (3 plekken) | lege staven vóór de start, tekort onzichtbaar, alleen kleur | een `StackedBarChart(StackedBarModel.months(...))` in de kaart `flow` op de Maand-tab | A |
| G7 | Vermogen | jaarmodus springt van 0 naar 15.964, banksaldo onbekend telt als 0 | `NetWorthTrend` (maanden vóór `startMonth` weg, noot zonder banksaldo, C7; op het Overzicht een vast venster van 12 maanden) | A |
| G8 | Bank, Verwacht verloop | blok verdwijnt zonder banksaldo | `BankTrend` met lege staat en actie "Saldo invullen" | B2 |
| G9 | Saldo per dag (2 plekken) | maandvenster met 1 dag: foute tekst, blok verdwijnt op Dag voor dag | `DayBalanceTrend` (`xAxis: .days`, markeringen Nul en Laagste); een grafiek in het segment Dag voor dag | B2 |
| G10 | Toekomstschatting | drie nullijnen bij lege invoer, alleen kleur, geen streefbedrag | `ProjectionTrend` (lijnstijl per scenario, markering Streefbedrag, lege staat) | D |
| G11 | Buffer | geen markering waar het doel bereikt wordt | `BufferTrend` met markering "Doel bereikt in augustus 2027" | D |
| G12 | Spaardoel | al bereikt of doel 0: geen lijn | `SavingsGoalTrend`; bij `plan.isReached` een lege staat "Je hebt dit bedrag al" | D |
| G13 | Versnellers | laatste punt valt weg (`i += step`), `Color.gray` | `GoalCurveTrend` met `downsample`; lijnstijl vol en gestreept | D |
| G14 | Voortgangsbalk en -ring (14 plekken) | pot zonder doel krijgt een volle ring (`progress ?? 1`), geen label | `ProgressMeter(value: nil)` tekent niets; de pagina zegt "Geen doel ingesteld"; label en waarde voor VoiceOver | elke eigenaar in zijn bestanden (C, D, B1, A) |
| G15 | Binnen en eruit | tekort onzichtbaar, alleen kleur | `SegmentedMeter` met de bedragen als tekst eronder | B2 |
| G16 | Saldoverloop per spaarpot | bestaat niet | C8 plus `PotTrend`: `TrendChart` onder het saldo van de spaarpot, met doelstreep en "Doel bereikt in {maand}" | C |
| G17 | Aankoopcheck | geen datagrafiek; `PurchaseStepBar` is in orde | geen werk | D |

### 5.5 Tests (pakket F, in `CoreTests`)

`PortfolioSeriesDerivedTests` (de 5), aangepaste `HoldingDayTests`, `ChartAxisTests` (domein `lo < hi` voor vlak, nul en NaN; `yLabels` uniek voor de acht gevallen uit `charts.md` 6.4; `ticks` binnen het domein; `monthStride`; `downsample` houdt eerste en laatste punt), `PortfolioTrendTests` (vier lege staten, `estimated`, `PortfolioWindow.options` voor 0, 1, 2, 7, 8 en 14 maanden), `DonutModelTests` (kleur per soort, aandelen tellen op tot 1, een soort), `StackedBarModelTests` (maanden vóór start weg, tekort boven de inkomenslijn, lege staat), `ChartSegmentTests` (aansluitpunt, een punt is een stip), `PotSeriesTests` (C8), `UpdateHoldingInvestedTests` (C9), en per modelbouwer van G3 en G7 t/m G13 een test voor lege staat, een punt, twee punten en `summary` niet leeg. Elke modelbouwer is een zuivere functie, dus de tests draaien met `swift test` zonder SwiftUI.

## 6. Werkpakketten

### 6.1 Afspraken voor alle bouwers

- **Eigendom.** Elk bestand in `App/`, `Tests/`, `CoreTests/`, `scripts/`, `.github/`, `firebase/` en de losse hoofdbestanden heeft precies een eigenaar (blok in par. 6.7; controle `docs/design/ownership-check.sh`). Je wijzigt alleen je eigen bestanden. Moet er iets in een bestand van een ander veranderen, dan is dat **WIRING**: zet in je eindrapport het bestand, de plek en de gewenste tekst, en doe het niet zelf. De eigenaar (`docs/design/ownership-check.sh --owner <pad>`) voert het uit in zijn volgende stap of in golf 1c. Twee tijdelijke uitzonderingen staan in pakket 0B (de verhuizing van de Bank-groep) en pakket G (golf 2).
- **Nieuwe bestanden** zijn van het pakket dat ze maakt, in de eigen map (tabel 6.1a). Je mag je eigen bestanden splitsen, hernoemen en verplaatsen; het Xcode-project komt uit XcodeGen (`path: App`), dus er is geen projectbestand om aan te passen. Geen nieuwe pakketten of dependencies.
- **Namen.** Een nieuw type dat een bestaand type vervangt krijgt een nieuwe naam (K7). **In golf 1a voeg je nieuwe namen toe naast de oude**; een oude naam die een ander pakket nog aanroept (controle: `grep -rn "Naam(" App` buiten je eigen bestanden) blijft staan tot golf 1c. Zo bouwt elk pakket tegen de rest zoals die nu is.
- **Contract.** Par. 4.4 is bindend. Elke aanroep naar een symbool uit een ander bestand vergelijk je letterlijk met de definitie (naam, labels, volgorde, typen, optionals); de CI is de scheidsrechter (zie onder).
- **Taal en stijl.** Nederlands, "je", kort, termenlijst par. 2.8. Commentaar Nederlands. `@Observable`, Swift 5-modus, iOS 18 en macOS 15, iOS 26-API's alleen achter `#available(iOS 26.0, macOS 26.0, *)`. Elk nieuw `Codable`-veld met `decodeIfPresent` (er komt er geen).
- **Alle functies blijven** (par. 2.5 en 3.2). Verdwijnt een scherm, dan gaat de functie naar de plek uit de tabel; wat niet kan, meld je.
- **Isolatie (K18).** Elk pakket werkt in een eigen `git worktree` (`EnterWorktree`) op een eigen branch `claude/ontwerp-<pakket>`, gemaakt vanaf de integratiebranch `claude/ontwerp-integratie` zoals die op dat moment staat. Een commit per afgerond deel; pushen mag en moet (de CI draait op `claude/**`). Een half bewerkt bestand van een ander pakket is zo onzichtbaar en `swift test` van de een faalt niet op het werk van de ander (`--scratch-path` scheidt alleen de builddirectory). De orchestrator voegt samen in de volgorde van par. 6.2; omdat de bestandsverdeling disjunct is, is dat triviaal. Andermans branch lezen mag, schrijven niet.
- **Voorcontrole (geen compileerbewijs).** `docs/design/precheck.sh <bestanden>`: (1) syntaxis met tree-sitter (`tools/check_swift.py`), (2) ViewBuilder-limiet (`tools/count_children.py`: een closure met meer dan 9 statements), (3) `docs/design/design-checks.sh` op precies die bestanden (het script zoekt de Python-omgeving met tree-sitter via `MYBUDDY_VENV`). Het vangt syntaxisfouten en een `VStack` met elf kinderen, maar geen foute labels, `Text(42)` of een onbekend type (bewezen in de kritiek, par. 5.2). Een oude typecontrole met nagemaakte SwiftUI-stubs is bewust niet meer in gebruik (par. "Herzieningen").
- **Poort: groene CI op je eigen branch.** Je pakket is pas klaar als op je branch `core-tests`, `build-ios` en `build-macos` (en voor E ook de app-tests in `build-ios`) groen zijn. Procedure: push; lijst de runs van je branch (`mcp__github__actions_list`); bij een fout lees je de logs (`mcp__github__get_job_logs`, alleen mislukte jobs; de CI toont maximaal 150 foutregels). Elke foutregel noemt een bestand: is het van jou, herstel het; is het van een ander, bepaal de eigenaar met `docs/design/ownership-check.sh --owner <pad>` en meld het onder WIRING. Is de CI niet te lezen of draait de runner `macos-26` niet, meld dat en **bouw niet door zonder compileerbewijs** (R1).
- **Eindrapport** (korte tekst): gewijzigde en nieuwe bestanden, uitvoer van `precheck.sh`, CI-runs (branch en conclusie), tests, WIRING, en wat je niet kon vaststellen.

Controlecommando's (voor elk Swift-bestand dat je aanraakt):

```
export PATH=/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin:$PATH
cd /home/user/MyBuddy && docs/design/precheck.sh App/Pages/<bestand>.swift          # syntaxis, ViewBuilder-limiet, ontwerpcontrole
cd CoreTests && swift test --scratch-path /tmp/sb-<naam>                             # alleen als je Core of een Foundation-only UI-bestand raakt
docs/design/ownership-check.sh                                                       # na elke wijziging van het blok in par. 6.7
```

**6.1a Mappen voor nieuwe bestanden**

| Pakket | Map |
|---|---|
| 0A | `App/UI/` (`Layout.swift`, `Motion.swift`, `RowActions.swift`, `Meters.swift`, `BlockOrderMigration.swift`, `ComponentGallery.swift`), `scripts/design-checks.sh`, `CoreTests/.../BlockOrderMigration.swift` (symlink) en `BlockOrderMigrationTests.swift` |
| 0B | `App/Navigation/` (`NavigationModel.swift`, `SearchIndex.swift`, `ActiveSession.swift`, `TabStack.swift`, `TabRoots.swift`, `AppCommands.swift`, `SettingsScene.swift`), `CoreTests/.../NavigationModel.swift` en `SearchIndex.swift` (symlinks), `NavigationRulesTests.swift`, `SearchIndexTests.swift` |
| F | `App/UI/ChartModels.swift`, `CoreTests/.../ChartModels.swift` (symlink) en de testbestanden uit par. 5.5 |
| A | `App/Pages/Tabs/` |
| B1 | `App/Pages/Month/` |
| B2 | `App/Pages/Bank/` (ook `BankLegacy.swift`, door 0B verhuisd) |
| C | `App/Pages/Saving/` |
| D | `App/Pages/Planning/` |
| E | `App/Pages/Settings/` |

### 6.2 Golven en afhankelijkheden

Elke golf eindigt compileerbaar (K18). De app is tussendoor niet af, maar hij bouwt.

```
Golf 0a (een bouwer)    0B  Schil: NavigationModel, Router, TabView met tijdelijke tabwortels, ActiveSession, commando's, DebugLaunch
          poort: CI groen (core-tests, build-ios, build-macos); NavigationRulesTests en SearchIndexTests groen
Golf 0b (2 bouwers)     0A  Ontwerpsysteem (eerst Theme.swift apart samenvoegen)     F  Core en grafieken (eerst Core en ChartModels, dan Charts.swift)
          poort: CI groen na elke samenvoeging; contract-check.sh 0 meldt CONTRACT COMPLEET
Golf 1a (5 bouwers)     B1  Maand   B2  Bankrekening   C  Sparen   D  Plannen   E  Instellingen
          poort: per pakket CI groen op de eigen branch, daarna CI groen op de integratiebranch
Golf 1b (1 bouwer)      A   Tabroots
          poort: CI groen; contract-check.sh 1 meldt CONTRACT COMPLEET
Golf 1c (aansluiten)    0B: definitieve tabwortels, DestinationView, Settings-scene, .syncPrompts weg   daarna E, A, B1, B2, C, D: eigen vervallen typen weg (par. 6.6)
          poort: CI groen na elke stap; design-checks.sh zonder FAIL behalve de compat-definities in de bestanden van 0A en F
Golf 2  (een bouwer)    G   Opruimen compat, documentatie, ci-screenshots.sh, eindcontrole (design-checks.sh --final, contract-check.sh final, CI)
```

| Pakket | Hangt af van (alleen namen uit par. 4.4) | Anderen hangen van hem af voor |
|---|---|---|
| 0B | niets (leest `AppStore`, `FinanceData`) | 0A (`Destination`, `Router`), alle pagina's: navigatie |
| 0A | 0B (`Destination`, `Router`, `BlockPage` blijft bij 0A) | alle pakketten: componenten en tokens; F (`Theme.chart*`) |
| F | 0A (`Theme.swift`, alleen voor `Charts.swift`; Core en `ChartModels.swift` zijn vrij), B2 (`DayChartItem`, `DayChartRange` blijven in `CashflowDisplay.swift`, bevroren) | A, B2, C, D: grafieken |
| B1 | 0A, 0B | B2 (`MoneyLineSheet`, bevroren), C en A (bevroren typen uit `MoneyFigures.swift`) |
| B2 | 0A, 0B, F, B1 (`MoneyLineSheet`) | A (`UpcomingDaysCard`, `CashflowCheckBanner`), 0B (`BankPage`, `BankSection`) |
| C | 0A, 0B, F | A (kaarten), 0B (pagina's), A en B2 (`PotFormat`) |
| D | 0A, 0B, F | A (kaarten), 0B (pagina's) |
| E | 0A, 0B | A (`SyncAttentionBanner`), 0B (`SettingsView`, `SettingsDestination`, `SettingsPane`) |
| A | 0A, 0B, F, B2, C, D, E (alle kaarten, op naam) | 0B (`OverviewTab` e.d. in golf 1c) |

**Samenvoegvolgorde** (door de orchestrator, CI groen na elke stap): 0B; dan 0A (eerst alleen `Theme.swift`), F, 0A (rest); dan B1, B2, C, D, E; dan A; dan de stappen van golf 1c; dan G.

De afhankelijkheid van 0A van F (`ProgressMeter`) is weggehaald (K12) en die van 0A van 0B is werkelijke code in plaats van een afspraak op papier (kritiek 4.2).

### 6.3 Golf 0

**Pakket 0B: Schil en navigatie** (golf 0a; `MyBuddyApp.swift`, `RootView.swift`, `Router.swift`, `AppStore.swift` (alleen lezen), `Pages/DestinationView.swift`, `Debug/DebugLaunch.swift`, nieuw `App/Navigation/*`; tijdelijke uitzondering: het verhuizen van de Bank-groep uit `SavingsPages.swift`)

- *Opdracht.* Par. 2.1, 2.2, 2.6, 2.9 en 3.5, contract 4.4 A, en daarbij compileerbaar blijven:
  1. `NavigationModel.swift`: `AppTab`, `SettingsPage`, `Destination` (verhuisd uit `Router.swift`), `NavigationRules` (`normalize`, `push`, `go` met ouderpad). `SearchIndex.swift`: `SearchEntry`, `SearchIndex.pages`, `results(for:in:)`.
  2. `Router.swift` volgens 4.4 A: `paths`, `pathBinding(for:)` met `normalize`, `open`, `go`, `select`, `popToRoot`, `requestSearch`, `searchRequest`, `settingsRequest`. **Compat**: `homePath`, `savingsPath`, `toolsPath` zijn berekende eigenschappen (`get`/`set`) die doorverwijzen naar `paths[.overview]`, `paths[.month]` en `paths[.planning]`; `showSettings` blijft een opgeslagen waarde zonder werking. Zo blijven de oude tabroots (`HomeView`, `SavingsView`, `ToolsView`, elk met een eigen `NavigationStack(path: $router.homePath)`) en `AcceleratorPages.swift:651` ongewijzigd compileren.
  3. `RootView.swift`: `TabView(selection:)` met vijf `Tab`s (de vijfde onder `#if !os(macOS)`, met `.badge(needsAttention ? 1 : 0)` waarbij `needsAttention` is `sync.importOffer != nil || sync.conflict != nil`; bouwt `.badge` niet op de `Tab`, dan op de inhoud van de tab, de iOS 16-variant), `.tabViewStyle(.sidebarAdaptable)`, `.tabBarMinimizeBehavior(.onScrollDown)` achter `#available(iOS 26.0, macOS 26.0, *)`, de selectie via een `Binding(get:set:)` die bij `new == router.tab` `popToRoot` aanroept, de bestaande `.task`s en `onChange`s (koersen, klok per minuut, maandwissel: `focusMonth` meeschuiven), `.sheet(item: $router.orderPage)` blijft, op macOS `.onChange(of: router.settingsRequest)` met `openSettings()`. Weg: `GlassTabBar`, `barBackdrop`, de toetsenbordmelding, `tabContent`, `MeshBackground` en de `sheet` voor Instellingen.
  4. **`TabRoots.swift` (tijdelijk, tot golf 1c)**: `TabRoot(tab)` toont per tab de oude inhoud: Overzicht `HomeView()`, Maand `SavingsView()`, Plannen `ToolsView()`, Instellingen `SettingsView()`, Sparen een `ContentUnavailableView("Sparen", ...)` met "Wordt gebouwd". De oude views houden hun eigen `NavigationStack`; `TabStack` bestaat al maar wordt pas in golf 1c gebruikt. Dit is geen eindvorm en wordt nooit opgeleverd.
  5. `ActiveSession.swift` (`register`, `unregister(store:)`), `TabStack.swift`, `AppCommands.swift` (Weergave Cmd+1 t/m Cmd+5, op de Mac Cmd+1 t/m Cmd+4; "Zoeken" Cmd+F; "Koersen vernieuwen" Cmd+R (`store.refreshPrices(force: true)`); "Back-up maken…" (`router.go(.settings(.data))`); alles uitgeschakeld zonder actieve sessie), `SettingsScene.swift` (macOS; tijdelijk elke pane `SettingsView()`).
  6. `MyBuddyApp.swift`: `ActiveSession` als `@State`; `SignedInRoot` registreert zijn `AppStore`, `Router` en `SyncController` bij `onAppear` en roept `unregister(store:)` aan bij `onDisappear` (ook `DemoSession`); `.commands { AppCommands(session:) }`; op macOS `Settings { SettingsScene(session:auth:cloud:) }` met `auth` en `cloud` expliciet; minimale venstergrootte 640 breed. `.syncPrompts(sync)` blijft staan tot golf 1c.
  7. `DestinationView.swift`: tijdelijke koppeling voor de nieuwe bestemmingen: `.salary` toont `IncomePage()`, `.expenses` `BankPage()` (zoals nu), `.settings(_)` `SettingsView()`; `.cashflow` blijft `CashflowPage()`; `chartMonths` blijft.
  8. `DebugLaunch.swift` volgens 2.6: nieuwe en oude tabnamen, `-mybuddy-open` met de nieuwe namen, `-mybuddy-settings`, `-mybuddy-order`-aliassen, `scrollTarget`, `-mybuddy-demo-holding`.
  9. **Verhuizing (knippen en plakken, geen enkele wijziging)**: de Bank-groep uit `SavingsPages.swift` (`BankAction`, `BankPage`, `BankBalanceBlock`, `BankFlowBlock`, `FlowRow`, `BankTransfersBlock`, `TransferRow`, `BankForecastBlock`, `BankBufferBlock`, `BankHistoryBlock`, `BankActionSheet`, vanaf `:1605`) naar `App/Pages/Bank/BankLegacy.swift`. Dat bestand is vanaf dat moment van B2. Reden: B2 bouwt een nieuwe `BankPage(section:)` en twee definities met dezelfde naam in een module compileren niet; B1 hoeft de groep dan niet te verwijderen en B1 en B2 raken elkaar niet.
  10. Tests: `NavigationRulesTests` (normalize knipt bij een herhaalde bestemming en laat een pad zonder herhaling gelijk; `push`; `go` geeft voor elke `Destination` een tab en het ouderpad uit 2.6; `Destination.tab` is totaal via een uitputtende `switch`), `SearchIndexTests` (uitputtend, par. 2.9).
- *Definitie van klaar.* `grep -rn "GlassTabBar\|barBackdrop" App` geeft niets; `grep -n "showSettings" App/RootView.swift` geeft niets; `NavigationRulesTests` en `SearchIndexTests` slagen en `swift test` is volledig groen; `precheck.sh` zonder fout op de eigen bestanden; `docs/design/ownership-check.sh` klopt; **CI groen** (`core-tests`, `build-ios`, `build-macos`) op `claude/ontwerp-0b`; `contract-check.sh 0` meldt voor 0B-symbolen niets meer ontbrekend (de regels voor 0A en F ontbreken nog).
- *Niet aanraken.* Alle `Pages` behalve `DestinationView.swift` en de verhuizing uit `SavingsPages.swift`, alle `UI`, `Auth`, `Cloud`, `Core`.
- *Tests en controles.* `NavigationRulesTests` en `SearchIndexTests` (punt 10). Handmatig (niet hier): scenario 7 en 19.

**Pakket 0A: Ontwerpsysteem** (golf 0b; `App/UI/Theme.swift`, `Glass.swift`, `Components.swift`, `Fields.swift`, `MoneyViews.swift`, `BlockOrder.swift`, `App/Assets.xcassets/AccentColor.colorset`, nieuw `Layout.swift`, `Motion.swift`, `RowActions.swift`, `Meters.swift`, `BlockOrderMigration.swift`, `ComponentGallery.swift`, `scripts/design-checks.sh`)

- *Opdracht.* Par. 4.1 t/m 4.6 en contract 4.4 B. **Volgorde:** (1) `Theme.swift` met alle tokens (exact de hex-waarden uit 4.1 en 4.2: licht, donker, hoog contrast), `AppDomain`, `Color(light:dark:lightContrast:darkContrast:)` als uitbreiding van de bestaande `Color(light:dark:)` en `minTapTarget` per platform; **apart committen en laten samenvoegen**, zodat F ertegen kan schrijven; (2) `Meters.swift`, `Layout.swift`, `Motion.swift`, `RowActions.swift`; (3) `Components.swift`, `Fields.swift`, `MoneyViews.swift`, `BlockOrder.swift` met alle componenten uit 4.4 B: `PageScaffold`, `ListScaffold` (met `DebugLaunch.scrollTarget`), `Card`, `LinkCard`, `SectionHeader`, `NavigationRow` en `ActionLink` met de gedeelde `DestinationLink` (K16), `BigAmount`, `StatTile`, `FigureRow`, `AmountRow`, `SymbolBadge`, `IconButton`, `ActionButton` (`controlSize` per platform), `ActionGroup`, `EmptyHint` (met `style`), `NoticeCard`, `MonthBar`, `PeriodPicker`, `animated(by:)`, `rowActions`, `RowAction`, `blockOrderToolbar` (alleen bij drie of meer blokken), `searchToolbarButton`, `SheetScaffold(hasChanges:)` (veeg uit bij wijzigingen, bevestiging "Bewaar", "Gooi weg", "Verder bewerken" bij Annuleer, de twee `confirmationDialog`s aan verschillende subviews, `.success`-haptiek, Return bewaart, `presentationSizing(.form)`), `BlockPage` met vier nieuwe cases en de oude drie als compat, `BlockOrderList`, `BlockOrderSheet`, `OrderedBlocks`, `BlockOrderMigration` met `AppSettings.orderedBlocks(for:)` die de gemigreerde volgorde leest. `GlassSurface` leest `accessibilityReduceTransparency`. Maak de compat-laag (par. 4.5, kolom Compat) zodat elke bestaande aanroep in `App/Pages` blijft compileren. Werk `AccentColor.colorset` bij met drie appearances. Kopieer `docs/design/design-checks.sh` naar `scripts/design-checks.sh` (uitvoerbaar). Voeg `ComponentGallery.swift` toe (`#if DEBUG`, `#Preview` in licht, donker, hoog contrast en `.accessibility3`).
- *Fallback voor de kleurtokens.* Bouwt `Color(light:dark:lightContrast:darkContrast:)` niet op de CI of werkt hij niet, dan verhuizen alleen de tokens met een hoog-contrastvariant naar Color Sets in `Assets.xcassets` (appearances dark en high contrast); de tokennamen veranderen niet.
- *Definitie van klaar.* Elk symbool uit 4.4 B bestaat met exact die handtekening (`contract-check.sh 0`: alle 0A-regels slagen); elke compat-aanroep uit de huidige `App/Pages` compileert nog (bewijs: **CI groen** op `claude/ontwerp-0a`; hulp: `grep` van alle aanroepen van `GlassBlock(`, `LinkedBlock(`, `ChipButton(`, `ChipLink(`, `ChipGrid(`, `ProgressBar(`, `ProgressRing(`, `SegmentBar(`, `EmptyHint(`, `StatTile(`, `BigAmount(`, `SymbolBadge(`, `MonthStepper(`, `PeriodControl(`, `SheetScaffold(`, `NumberRow(` tegen je definities); `BlockOrderMigrationTests` slagen (de zeven rijen van 2.7, idempotent, onbekende ids genegeerd, een lege invoer blijft leeg) en `swift test` is volledig groen; `precheck.sh` op de eigen bestanden: alleen de bedoelde compat-definities falen nog (`GlassBlock(`, `Chip*(`, `ProgressBar(`, `MeshBackground`, `glassCard(`, `Theme.flow*`, `Theme.olive*`, `Theme.buttonHeight`); geen `.font(.system(size:`, `caption2`, `.rounded`, `.secondary`, `Color(hex:` buiten `Theme.swift`; de contrastcijfers van 4.1 en 4.2 zijn opnieuw te berekenen uit `Theme.swift` (scenario 18).
- *Niet aanraken.* `App/Pages/*`, `App/Auth`, `App/Cloud`, `App/UI/Charts.swift`, `App/UI/BackupUI.swift`, `App/UI/MarketDataUI.swift`, `Router.swift`, `RootView.swift`, `MyBuddyApp.swift`.
- *Tests en controles.* `BlockOrderMigrationTests`; de `#Preview`s zijn de handmatige controle. Meld de lijst "oude naam, nieuwe naam" die je hebt gebouwd, als hulp voor golf 1.

**Pakket F: Grafieken en Core** (golf 0b; `App/UI/Charts.swift`, nieuw `App/UI/ChartModels.swift`, `App/Core/Invest.swift`, `Overview.swift`, `Pots.swift`, alle overige `App/Core/*` als poortwachter, nieuwe en aangepaste tests in `CoreTests`)

- *Opdracht.* Par. 5.2 (C1 t/m C5, C7 t/m C9; C6 niet), 5.3 en contract 4.4 C. **Volgorde:** (1) Core en tests (`swift test` alleen; geen SwiftUI): begin met de code uit `charts-prototype.md` B1 (patch C1), B2 (tests), B3 (modellen); (2) `ChartModels.swift` met alle modelbouwers van 4.4 C, `TrendModel.footnote` en `PortfolioWindow`; (3) pas als `Theme.swift` van 0A is samengevoegd: `Charts.swift` met `TrendChart`, `StackedBarChart`, `DonutChart`, `ChartEmptyView` (B4 uit het prototype; de annotatie bij `chartXSelection` is `Theme.card` met rand, geen glas). De oude typen (`TimeLineChart`, `FlowChart`, `AllocationDonut`, `TimePoint`, `chartAxes`) blijven als compat staan tot golf 1c; `BufferChart`, `SavingsGoalChart`, `GoalCurveChart` en `DayBalanceChart` staan in pagina-bestanden en worden door hun eigenaars verwijderd. `ProgressMeter` en `SegmentedMeter` maakt 0A.
- *Definitie van klaar.* Alle symbolen uit 4.4 C bestaan; `PortfolioSeriesDerivedTests` (5) slagen; `HoldingDayTests` aangepast; de tests uit par. 5.5 slagen; **volledige `swift test` groen** (was 1.492 tests; elke andere falende test is een fout, geen wens); `ChartModels.swift` is Foundation-only (symlink in `CoreTests` compileert, ook op de Linux-job van de CI); `accessibilityChartDescriptor` staat op drie componenten (eerst `accessibilityLabel` met `summary`, de descriptor als tweede stap als hij niet bouwt, R10); elke component leest `accessibilityReduceMotion`; `precheck.sh` zonder fout; geen `Color(hex:`, geen vaste kleuren buiten `Theme`; **CI groen** op `claude/ontwerp-f`; `git diff --stat App/Core` toont alleen `Invest.swift`, `Overview.swift`, `Pots.swift`.
- *Niet aanraken.* Alle andere Core-bestanden (de rekenlogica blijft zoals ze is; `Models.swift` blijft: geen nieuw `Codable`-veld), `App/Pages`, de overige `App/UI`.
- *Tests en controles.* `cd CoreTests && swift test --scratch-path /tmp/sb-f`; `PortfolioSeriesDerivedTests` eerst rood tegen HEAD, dan groen. Rapporteer de gemeten testaantallen en welke bestaande test je hebt aangepast en waarom.

### 6.4 Golf 1

Regel voor 1a: nieuwe namen erbij, oude namen die een ander pakket nog aanroept blijven tot 1c (par. 6.1). Elk pakket draait de CI-poort op de eigen branch.

**Pakket B1: Maand-pagina's** (golf 1a; `App/Pages/SavingsPages.swift`, `App/UI/SavingsDisplay.swift`, `App/UI/MoneyFigures.swift`, nieuw `App/Pages/Month/*`)

- *Opdracht.* Par. 2.4 (Inkomen, Salaris, Uitgaven, Verdelen), K6 en 2.8. `IncomePage` en `ExpensesPage` (nieuw) zijn `ListScaffold`-pagina's met `MonthBar`, `AmountRow` en rijen met `rowActions` (de ellipsis-menu's van `MoneyLineRow` vervallen); `MoneyLinesSection` (een `Section`) komt naast `MoneyLinesBlock`; "Standaard uitgaven invullen" in het werkbalkmenu en in de lege staat van Uitgaven. **`SalaryPage` (nieuw) en `DistributePage` zijn `PageScaffold` met `Card`s** (rekenpagina's, K6): `AllocationRow` blijft een mini-formulier per pot of belegging in een `Card`, met `.buttonStyle(.bordered)` of `.borderless` per knop zodat een tik een actie raakt; "Overschrijfdag" in een `DisclosureGroup`, de drie verdeelacties in het werkbalkmenu. `MoneyLineSheet(line:kind:month:defaultExpenseKind:)` blijft ongewijzigd qua API en krijgt `hasChanges`. Alle teksten in je bestanden naar de termenlijst, ook `MoneyLabels` in `MoneyFigures.swift` ("Nog te verdelen", "Overgehouden"); wijzigt een label, dan pas je de bijbehorende test aan. De frozen typen uit 4.4 E blijven ongewijzigd. De Bank-groep staat na 0B niet meer in dit bestand. **Golf 1c:** verwijder `OverviewPage`, `BreakdownRow`, `DayCheckBlock`, `MonthPickerBlock` en `MoneyLinesBlock` zodra niemand ze meer aanroept.
- *Definitie van klaar.* Elke pagina heeft maximaal 6 blokken en de volgorde kern, secties, acties, destructief; de pagina's `.income`, `.salary`, `.expenses`, `.distribute` bestaan onder precies deze namen (`contract-check.sh 1`: de B1-regels); `precheck.sh` zonder fout; **de bedragen en rekenregels zijn ongewijzigd** (`MonthFigures`, `MonthBoard`, `AllocationEdit`, `LineSave` ongewijzigd qua gedrag); `swift test` groen; **CI groen** op `claude/ontwerp-b1`; handmatig (niet hier) scenario's 3, 4, 5 en 24: percentage-inleg, "Afwijkend", "Terug naar standaard", "Maak dit je standaard", en een terugkerende regel met reikwijdte via swipe.
- *Niet aanraken.* `CashflowPages.swift`, `CashflowDisplay.swift`, `Pages/Bank/`, alle `Core`, `UI` buiten je eigen drie bestanden.
- *Tests en controles.* Bestaande tests voor je bestanden: `MoneyFiguresTests`, `AllocationEditTests`, `LineSaveTests`, `SalaryScheduleEditTests`; nieuw alleen als je Foundation-only logica toevoegt.

**Pakket B2: Bankrekening en Dag voor dag** (golf 1a; `App/Pages/CashflowPages.swift`, `App/UI/CashflowDisplay.swift`, `App/Pages/Bank/*` inclusief `BankLegacy.swift`)

- *Opdracht.* Par. 2.4 (Bankrekening en de dagsectie), K15, 2.5 en 5.4 (G8, G9, G15). Bouw `BankPage(section:)` met `BankSection` en een segmentbalk Saldo, Dag voor dag, Boekingen. *Saldo*: hero met `BigAmount`, "Saldo invullen" en de melding uit `BankLowPointNotice`; **Verwacht verloop** (`TrendChart(BankTrend.model(...))` met lege staat); **Binnen en eruit** (`SegmentedMeter` plus `AmountRow`s, de rijen linken naar Spaarpotten, Beleggingen en Verdelen); **Minimumsaldo** (het veld `bankBufferMonths`, een zin, een link naar Noodbuffer). *Dag voor dag*: `CashflowCheckBanner` alleen bij afwijking; **Saldo per dag** (`TrendChart(DayBalanceTrend.model(...))`); **twee uitklappers "Zo komt je saldo tot stand"** (`CashflowBankBlock`-inhoud: `CashflowSummary.bankRows`, `LedgerLineRow`, de zin over een saldo dat later bekend wordt, `RoundingNote`) en "Zo komen je spaarpotten tot stand" (`CashflowPotsBlock`-inhoud: `potsRows`, alleen met potten): geen nieuwe logica, alleen een `DisclosureGroup` rond dezelfde rijen; daarna een sectie per dag zoals in 2.4 (`DayFlowTiles`, `DayEventRow` met navigatie naar pot, belegging, Inkomen of het regelblad `MoneyLineSheet`, `DayBalanceRows`), `CashflowDayFilter` met standaard "Alleen met boekingen", "Naar vandaag". *Boekingen*: `BankHistoryBlock` als lijst met swipe. Werkbalkmenu "Geld bewegen" (`BankActionSheet` met de vijf acties). `UpcomingDaysCard()` uit `BankUpcomingBlock` en `UpcomingDayRow` voor het Overzicht. `MonthBar` in plaats van `MonthPickerBlock`. Verwijder `BankTransfersBlock`, `TransferRow`, `BankDayBlock`, `CashflowOverviewBlock` en `DayBalanceChart` zodra de nieuwe pagina compleet is (alleen jouw bestanden); `CashflowPage` blijft tot golf 1c (de koppeling in `DestinationView` verwijst er nog naar).
- *Definitie van klaar.* `BankPage(section:)`, `BankSection`, `UpcomingDaysCard()` bestaan met de handtekeningen uit 4.4 D; alle functies uit de oude `BankPage` en `CashflowPage` bereikbaar (par. 2.5, K15); de twee uitklappers sluiten (begin plus binnen min eruit min overgeschreven is eind) met dezelfde cijfers als voor de herbouw; `DayChartItem` en `DayChartRange` ongewijzigd; `precheck.sh` zonder fout; `swift test` groen (`CashflowDisplayTests`, `LedgerConsistencyTests`); **CI groen** op `claude/ontwerp-b2`; handmatig scenario's 6 en 8.
- *Niet aanraken.* `SavingsPages.swift`, `Core`, andere `UI`.
- *Tests en controles.* `CashflowDisplayTests` en `LedgerConsistencyTests` blijven groen.

**Pakket C: Sparen** (golf 1a; `App/Pages/PotPages.swift`, `PortfolioPages.swift`, `App/UI/PotDisplay.swift`, nieuw `App/Pages/Saving/*`)

- *Opdracht.* Par. 2.4 (Spaarpotten, Spaarpot, Beleggingen, Belegging), 5.4 (G1 t/m G5, G14, G16), K9a t/m K9c en K19. `PotsPage`, `PotDetailPage`, `PortfolioPage`, `HoldingDetailPage` als `ListScaffold`-pagina's met `rowActions`, werkbalk `+` en menu's. **Vier kaarten**: `PotsSummaryCard()`, `PortfolioSummaryCard()` voor Sparen en `HomePotsCard()`, `HomeHoldingsCard()` voor het Overzicht, met de gekozen tegels (par. 2.4: `FavoritePotTile`, `FavoriteHoldingTile`, `FavoriteSlotTile`; **niet** de oude namen `PotMiniTile`, `HoldingTile`, `EmptySlotTile`, `PotsTotals`, die `design-checks.sh` buiten `HomeView.swift` telt), de lege plek-tegel en een kaartmenu; **twee korte sheets** `FavoritePotsSheet()` en `FavoriteHoldingsSheet()` (herbouw van `PotPickerSheet` en `HoldingPickerSheet`, met `SheetScaffold(hasChanges:)`, `homePotIDs`, `homeHoldingIDs`, limiet 3 en 4, een bol met volgnummer in `Theme.onAccent`), geopend vanuit het kaartmenu en het werkbalkmenu van `PotsPage` en `PortfolioPage` (de huidige aanroepen op `PotPages.swift:97` en `PortfolioPages.swift:98` gaan naar de nieuwe namen). Sluit de grafieken aan (`TrendChart`, `DonutChart`, `ProgressMeter`). `HoldingEditSheet` en het bewijs volgens "Invoer en reproduceerbaar bewijs voor Beleggingen" in par. 5.2 (Belegd sinds, Huidige waarde, uitleg zonder aantal, "Geschat"); werkbalkmenu Beleggingen met "Koersen vernieuwen"; `GainBadge(gain:fraction:)` in `PortfolioPages.swift` (vervangt `GainLabel`); `NoticeCard` in plaats van `NoticeBanner` (`PortfolioPages.swift:26, 242`); "Meetpunt" wordt "Waarde-update"; sheets `PotEditSheet`, `PotEntrySheet`, `HoldingEditSheet`, `ValueUpdateSheet` met `hasChanges`. De oude `PotPickerSheet`, `HoldingPickerSheet`, `PotsBlock`, `InvestBlock`, `GainLabel` staan in `HomeView.swift` (A) en verdwijnen in golf 1c met dat bestand.
- *Definitie van klaar.* De vier pagina's, vier kaarten en twee sheets bestaan met de handtekeningen uit 4.4 D; geen `TimeLineChart`, `AllocationDonut`, `ProgressBar`, `ProgressRing`, `ellipsis.circle`-rijmenu, `GainLabel`, `NoticeBanner`, `PotPickerSheet`, `HoldingPickerSheet` in je bestanden; de Beleggingen-grafiek toont voor elk scenario uit `charts.md` 3.2 (b1, b1c, b2, b3, b3b, b4a, g1, g2) en voor de drie `-mybuddy-demo-holding`-scenario's een grafiek of een lege staat met actie, nooit een lege vlakte of de oude voetnoot, en een afgeleide lijn heeft het onderschrift; `precheck.sh` zonder fout; `swift test` (`PotDisplayTests`) groen; **CI groen** op `claude/ontwerp-c`; handmatig scenario's 10, 11 en 21.
- *Niet aanraken.* `Invest.swift`, `Pots.swift` en de rest van `Core` (F), andere `Pages`, `HomeView.swift` en `SavingsView.swift`.
- *Tests en controles.* `PotDisplayTests`.

**Pakket D: Plannen** (golf 1a; `App/Pages/GoalPages.swift`, `SavingsGoalPages.swift`, `BufferPages.swift`, `ProjectionPage.swift`, `PurchasePages.swift`, `AcceleratorPages.swift`, nieuw `App/Pages/Planning/*`)

- *Opdracht.* Par. 2.4 (Doelen, Doel, Spaardoel berekenen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck), 2.5 en 5.4 (G10 t/m G14). Vijf kaarten met lege `init()`: `GoalsSummaryCard` (**altijd met een rij "Spaardoel berekenen"** naar `.savingsGoal`, ook zonder berekend plan; uit `GoalsHubBlock`), `BufferSummaryCard`, `AcceleratorsSummaryCard` en `ProjectionSummaryCard` (uit `ToolsView.swift`, met `AcceleratorBadge`), `PurchaseSummaryCard`; de oude `GoalsHubBlock`, `BufferBlock`, `PurchaseBlock` blijven tot golf 1c (de oude tabroots roepen ze aan). `GoalsPage` zonder de schakelaar (`GoalsSection` vervalt; werkbalkmenu Nieuw doel, Spaardoel berekenen, Noodbuffer). Rekenpagina's in de volgorde uitkomst, invoer, details in uitklappers; "Buffer" heet "Noodbuffer"; **Toekomstschatting toont "Hoe ver kijk je vooruit?" als zichtbaar blok Looptijd** (`ProjectionPage.swift:70`, veld, eenheid, snelkeuzes); `AcceleratorsPage` verwijst met `router.open(.goals)` in plaats van `router.toolsPath.append` (`AcceleratorPages.swift:651`). Sluit de vier grafieken aan op `TrendChart`; verwijder `BufferChart`, `SavingsGoalChart`, `GoalCurveChart`. De bevestiging van `AcceleratorApplySheet` verdwijnt niet vanzelf na 4 seconden (ACC-8): sluit met een knop. "Herstel" van versnellers blijft bereikbaar bij 0 en bij meer dan een doel. `@AppStorage`-sleutels en `SavingsGoalDraft` blijven ongewijzigd.
- *Definitie van klaar.* Zeven pagina's en vijf kaarten bestaan met de handtekeningen uit 4.4 D; geen eigen `Chart(`, `import Charts`, `TimeLineChart`; elke pagina maximaal 6 blokken; `Theme.warning` niet meer als tekst op een vlak onder contrast; `precheck.sh` zonder fout; `swift test` groen; **CI groen** op `claude/ontwerp-d`; handmatig scenario's 12 en 13.
- *Niet aanraken.* `Core`, andere `Pages`, `UI`.
- *Tests en controles.* Bestaande `GoalTests`, `BufferTests`, `SavingsGoalTests`, `PurchaseTests`, `GrowthTests`, `Accelerator*Tests` blijven groen.

**Pakket E: Instellingen en account** (golf 1a; `App/Pages/SettingsView.swift`, `App/Auth/*`, `App/Cloud/*`, `App/Config/FirebaseConfig.swift`, `App/UI/BackupUI.swift`, `App/UI/MarketDataUI.swift`, `Tests/AppTests/*`, nieuw `App/Pages/Settings/*`)

- *Opdracht.* Par. 3 volledig. `SettingsView()` (tabroot, vier secties, zes rijen, zonder eigen `NavigationStack`), `SettingsDestination(page:)` voor alle tien `SettingsPage`-cases, `SettingsPane(page:)` voor de Mac met een eigen `NavigationStack`. Zet de bestaande secties om naar pagina's volgens tabel 3.2: `CloudAccountSection`, `SyncSection`, `AccountSection`, `MarketDataSection`, `BackupSection` worden pagina's of secties daarin; de vier wachtwoord- en verwijderbladen worden pagina's; `SpreadsheetImportSheet` wordt `SpreadsheetImportPage` achter `SettingsPage.importReview` met een `ImportCoordinator`; **een `ExportDocument` met statische content types** vervangt de drie documenttypen en `BackupHost`; `SyncAttentionBanner()` komt erbij; `FirebaseSetupSection`, `RateFetchRow` verdwijnen; Indeling gebruikt `BlockOrderList(page:)` van 0A. `AuthView`: `MeshBackground` en glaskaart weg (par. 3.6), knoppen en tekstlinks op `Theme.minTapTarget`; de logica en de `AuthStore` blijven ongewijzigd (K4). Versie uit `Bundle.main` (`CFBundleShortVersionString`). `SyncPromptsHost` en `.syncPrompts` blijven bestaan tot golf 1c (0B haalt de aanroep eerst weg), daarna verwijdert E ze.
- *Definitie van klaar.* `grep -rn "\.sheet(\|\.alert(\|\.fullScreenCover(" App/Pages/Settings App/Pages/SettingsView.swift App/Auth App/Cloud App/UI/BackupUI.swift App/UI/MarketDataUI.swift` geeft niets (behalve `SyncPromptsHost` tot golf 1c); elke functie uit tabel 3.2 is bereikbaar; geen enkele instellingenpagina dieper dan drie niveaus (tab, pagina, subpagina); `AppTests` en `CoreTests` groen; `precheck.sh` zonder fout; **CI groen** op `claude/ontwerp-e` (inclusief de app-tests in `build-ios`); de tekst "Firebase" komt alleen nog voor in de Account-uitleg van een zin en in `FirebaseConfig.swift`; handmatig scenario's 14 t/m 17.
- *Niet aanraken.* `App/Core/*` (`FirebaseAuthClient`, `CloudSync*`, `AccountPrefs`, `Export`, `ImportMapping`), `SyncController`-logica (alleen views en teksten), andere `Pages`, de componenten in `UI`.
- *Tests en controles.* `Tests/AppTests/*` (AuthTests, CloudTests, SyncControllerTests) onaangetast en groen.

**Pakket A: Tabroots** (golf 1b, pas als B2, C, D en E samengevoegd zijn; `App/Pages/HomeView.swift`, `SavingsView.swift`, `ToolsView.swift`, nieuw `App/Pages/Tabs/*`)

- *Opdracht.* Par. 2.2, 2.4 (tabroots), 2.7, 2.9, K17. Maak `OverviewTab`, `MonthTab`, `SavingTab`, `PlanningTab` (alleen inhoud; de `NavigationStack` komt van `TabStack`). **Overzicht**: meldingen (`startupNotice`, `saveFailed` met "Opnieuw proberen", `SyncAttentionBanner()`, `CashflowCheckBanner` bij afwijking), de hero "Nog te verdelen" (de logica van `RemainingHeader`: `MonthBoard`, `percentWarning`, notities; zonder de drie tegels), `OrderedBlocks(page: .overview)` met `wealth` (`NetWorthTrend` over de laatste 12 maanden, drie `AmountRow`-links), `pots` (`HomePotsCard()`), `invest` (`HomeHoldingsCard()`) en `upcoming` (`UpcomingDaysCard()`), de lege start, `.searchable(text:isPresented:)` met `SearchIndex` en `onChange(of: router.searchRequest)`. **Maand**: `MonthBar` als kern, daarna `OrderedBlocks(page: .month)` met `flow` (`PeriodPicker`, `StackedBarChart(StackedBarModel.months(...))`, tegel Overgehouden, twee uitklappers uit de oude pagina Overzicht) en vijf `LinkCard`s met het kerncijfer (logica van `IncomeBlock`, `DistributeBlock`, `BankBlock`, plus nieuw Uitgaven en Dag voor dag). **Sparen en Plannen**: plaats de `*SummaryCard`s van C en D met `OrderedBlocks`. Werkbalk van elke tabroot: `blockOrderToolbar(page:)` (alleen waar het kan) en `searchToolbarButton()` (niet op het Overzicht). De oude `HomeView.swift`, `SavingsView.swift` en `ToolsView.swift` blijven staan tot golf 1c; ze worden dan verwijderd (par. 6.6).
- *Definitie van klaar.* Elke tabroot is `PageScaffold(title:, large: true)` en gebruikt alleen `Card`, `LinkCard`, `FigureRow`, `AmountRow`, `EmptyHint`; geen `GlassBlock(`, `LinkedBlock(`, `Chip*`, `MeshBackground`, `.secondary`, `caption2`, `.rounded`, vaste lettergroottes in de nieuwe bestanden; alle namen volgen 2.8; elk getal komt uit dezelfde bron als nu (`MonthBoard`, `periodSummary`, `netWorth`); het Overzicht leest `focusMonth` en `periodMode` niet; de volgorde van blokken werkt via `OrderedBlocks` met de id's uit 2.7 en de kern staat erbuiten; `precheck.sh` zonder fout op de eigen bestanden; **CI groen** op `claude/ontwerp-a`; `contract-check.sh 1` meldt CONTRACT COMPLEET.
- *Niet aanraken.* `SettingsView.swift`, alle pagina's van B1, B2, C, D, alle `UI`, `Core`.
- *Tests en controles.* Geen Core-tests (geen nieuwe logica; gebruik `MoneyFigures`). Handmatig: scenario's 1, 2, 4, 7, 9, 21 en 23.

### 6.5 Golf 1c en golf 2

**Golf 1c: aansluiten** (volgorde vast; na elke stap CI groen)

1. **0B**: `TabRoots.swift` wordt de definitieve vorm (`TabStack(.overview) { OverviewTab() }`, `.month`, `.saving`, `.planning` en `.settings` met `SettingsView()`); `DestinationView` koppelt aan de echte pagina's (`.salary` `SalaryPage()`, `.expenses` `ExpensesPage()`, `.cashflow` `BankPage(section: .days)`, `.settings(let p)` `SettingsDestination(page: p)`, `.overview` `OverviewTab()` als noodgreep); `SettingsScene` toont `SettingsPane(page:)`; `.syncPrompts(sync)` uit `SignedInRoot`; `DebugLaunch` volledig.
2. **E**: verwijder `SyncPromptsHost` en `.syncPrompts`, en wat in 6.6 voor E staat.
3. **A**: verwijder `HomeView.swift`, `SavingsView.swift` en `ToolsView.swift` (en daarmee `NoticeBanner`, `GainLabel`, de oude tegels en blokken).
4. **B1, B2, C, D**: verwijder in je eigen bestanden de vervallen typen uit 6.6 die nu door niemand meer worden aangeroepen (controle met `grep` en de CI).

*Definitie van klaar (golf 1c).* `TabRoots.swift` verwijst niet meer naar `HomeView`, `SavingsView` of `ToolsView` en die bestanden bestaan niet meer; `grep -rn "syncPrompts\|SyncPromptsHost\|PotPickerSheet\|HoldingPickerSheet\|NoticeBanner\|GainLabel\|MonthPickerBlock" App` geeft niets; `DestinationView` koppelt geen enkele bestemming meer aan een tijdelijke pagina; `design-checks.sh` zonder FAIL behalve de compat-definities in de bestanden van 0A en F; `contract-check.sh 1` meldt CONTRACT COMPLEET; **CI groen** op de integratiebranch.

**Pakket G: Integratie en eindcontrole** (golf 2; `README.md`, `docs/v3-spec.md`, `system_architecture.md`, `implementation_plan.md`, `task.md`, `scripts/*`, `.github/*`, `project.yml`, `firebase/*`, `App/PrivacyInfo.xcprivacy`, `App/Assets.xcassets/AppIcon.appiconset`; en elk bestand voor opruimen)

- *Opdracht.* (1) Draai `contract-check.sh alles` en los naamverschillen op. (2) Verwijder de compat-laag: `GlassBlock`, `LinkedBlock`, `Chip*`, `ProgressBar`, `ProgressRing`, `SegmentBar`, `MeshBackground`, `Theme.flow*`, `Theme.buttonHeight`, `Theme.olive*`, `showsSettings`, `glassCard`, `glassButton` (wat ongebruikt is), `PeriodControl`, de oude grafiektypen, `Router.homePath`, `savingsPath`, `toolsPath`, `showSettings`, `AppTab.symbol(selected:)`, `BlockPage.home`, `savings`, `tools`; ruim ongebruikte code op. (3) Werk bij: `README.md` (tabellen Tabs, "Home" en "Savings", de zin over de tabbalk, Instellingen, de Liquid Glass-formulering), `docs/v3-spec.md` (blok-id's, termen, componenten, regel 126-140), `system_architecture.md` (regel 8: tabs en navigatiepaden), `implementation_plan.md`, `task.md`, `scripts/ci-screenshots.sh` (nieuwe tabnamen en pagina's, `-mybuddy-settings`, de screenshots `portfolio` en `holding0` voor de drie `-mybuddy-demo-holding`-scenario's, `-mybuddy-scroll-to` voor lange lijsten) en zo nodig `.github/workflows/ci.yml`. (4) Draai de volledige eindcontrole van par. 7 en lever het eindrapport met alle tellingen. G mag elk bestand aanpassen, maar alleen voor integratiefouten en opruimen; ontwerpwijzigingen niet.
- *Definitie van klaar.* `docs/design/design-checks.sh --final` zonder een FAIL; `docs/design/contract-check.sh final` meldt CONTRACT COMPLEET; `precheck.sh` zonder fout op alle gewijzigde bestanden; `swift test` volledig groen; **CI groen** (`core-tests`, `build-ios`, `build-macos`) op de integratiebranch en de workflow `screenshots` (handmatig gestart) levert de screenshots; de handmatige scenario's van 7.4 staan op een rij met "gedaan" of "niet te testen hier".
- *Niet aanraken.* `App/Core` (tenzij een test dat eist), de rekenlogica.

### 6.6 Verhuistabel: typen die van bestand wisselen of vervallen

De verwijderende eigenaar haalt het type weg, de definiërende eigenaar maakt het. Een nieuw type heeft een nieuwe naam (K7), dus er bestaan nooit twee definities. "Wanneer" is golf 1a (meteen, alleen als niemand buiten je eigen bestanden het nog aanroept) of golf 1c.

| Type | Nu in (eigenaar verwijdert, wanneer) | Straks in (eigenaar definieert) |
|---|---|---|
| `NoticeBanner` | `HomeView.swift` (A, 1c); aanroepen in `PortfolioPages.swift` migreert C in 1a | `NoticeCard` in `Components.swift` (0A) |
| `GainLabel` | `HomeView.swift` (A, 1c); aanroepen in `PortfolioPages.swift` migreert C in 1a, in `SavingsView.swift` verdwijnt het met A | `GainBadge` in `PortfolioPages.swift` (C) |
| `PotsBlock`, `InvestBlock`, `PotMiniTile`, `HoldingTile`, `EmptySlotTile`, `PotsTotals` | `HomeView.swift` (A, 1c) | `HomePotsCard`, `HomeHoldingsCard` met eigen tegels (C, in `Saving/`) |
| `PotPickerSheet`, `HoldingPickerSheet` | `HomeView.swift` (A, 1c); aanroepen in `PotPages.swift:97` en `PortfolioPages.swift:98` migreert C in 1a | `FavoritePotsSheet`, `FavoriteHoldingsSheet` (C) |
| `MiniFigure`, `FlowLegend`, `WelcomeBlock`, `RemainingHeader`, `OverviewBlock`, `HomeView` | `HomeView.swift` (A, 1c) | vervallen; A bouwt hero, kaarten en lege staat in `Tabs/` |
| `PeriodBlock`, `IncomeBlock`, `DistributeBlock`, `PotsSummaryBlock`, `BankBlock`, `PortfolioBlock`, `SavingsView` | `SavingsView.swift` (A, 1c) | vervallen; A bouwt de Maand-kaarten, C `PotsSummaryCard` en `PortfolioSummaryCard` |
| `ProjectionBlock` | `ToolsView.swift` (A, 1c) | `ProjectionSummaryCard` in `ProjectionPage.swift` (D) |
| `AcceleratorsBlock`, `AcceleratorBadge` | `ToolsView.swift` (A, 1c) | `AcceleratorsSummaryCard`, `AcceleratorBadge` in `AcceleratorPages.swift` (D) |
| `ToolsView` | `ToolsView.swift` (A, 1c) | vervallen |
| `BufferBlock`, `GoalsHubBlock`, `PurchaseBlock` | `BufferPages.swift`, `GoalPages.swift`, `PurchasePages.swift` (D, 1c; blijven tot dan voor de oude tabroots) | `BufferSummaryCard`, `GoalsSummaryCard`, `PurchaseSummaryCard` in dezelfde bestanden (D, 1a) |
| `OverviewPage`, `BreakdownRow`, `DayCheckBlock` | `SavingsPages.swift` (B1, 1c) | vervallen; A bouwt het Maand-overzicht (`flow`) |
| `MonthPickerBlock` | `SavingsPages.swift` (B1, 1c); aanroep in `CashflowPages.swift:906` migreert B2 in 1a | `MonthBar` in `Components.swift` (0A) |
| `MoneyLinesBlock` | `SavingsPages.swift` (B1, 1c) | `MoneyLinesSection` in `App/Pages/Month/` (B1) |
| `BankPage`, `BankAction`, `BankBalanceBlock`, `BankFlowBlock`, `FlowRow`, `BankForecastBlock`, `BankBufferBlock`, `BankHistoryBlock`, `BankActionSheet` | `SavingsPages.swift` (**0B verhuist ze in golf 0a**) naar `Pages/Bank/BankLegacy.swift` (B2) | `App/Pages/Bank/` (B2), herbouwd; B2 verwijdert `BankLegacy.swift` zodra de nieuwe pagina compleet is |
| `BankTransfersBlock`, `TransferRow` | `BankLegacy.swift` (B2, 1a) | vervallen |
| `BankUpcomingBlock`, `UpcomingDayRow` | `CashflowPages.swift` (B2) | `UpcomingDaysCard` en `UpcomingDayRow` in `App/Pages/Bank/` (B2) |
| `CashflowBankBlock`, `CashflowPotsBlock` | `CashflowPages.swift` (B2) | **blijven**, als inhoud van de twee uitklappers in `App/Pages/Bank/` (B2, K15) |
| `CashflowOverviewBlock`, `DayBalanceChart`, `BankDayBlock`, `CashflowPage` | `CashflowPages.swift` (B2; `CashflowPage` in 1c, de rest in 1a) | vervallen (`CashflowPage` gaat op in `BankPage(section: .days)`) |
| `BufferChart`, `SavingsGoalChart`, `GoalCurveChart` | `BufferPages.swift`, `SavingsGoalPages.swift`, `AcceleratorPages.swift` (D, 1a) | vervallen (vervangen door `TrendChart`) |
| `TimeLineChart`, `FlowChart`, `AllocationDonut`, `TimePoint`, `chartAxes` | `Charts.swift` (F; compat tot de pagina's zijn gemigreerd) | vervallen in golf 2 (G) |
| `ProgressBar`, `ProgressRing`, `SegmentBar` | `Components.swift` (0A, compat) | `ProgressMeter`, `SegmentedMeter` in `Meters.swift` (0A); compat weg in golf 2 (G) |
| `SyncPromptsHost`, `.syncPrompts(_:)` | `CloudViews.swift` (E, 1c), aanroep in `MyBuddyApp.swift` (0B, 1c) | vervallen; vervangen door `SyncAttentionBanner` (E) |
| `ChangePasswordSheet`, `DeleteAccountSheet`, `ChangeCloudPasswordSheet`, `DeleteCloudAccountSheet`, `SpreadsheetImportSheet` | `AuthView.swift`, `CloudViews.swift`, `BackupUI.swift` (E) | pagina's in `App/Pages/Settings/` (E) |
| `FirebaseSetupSection`, `RateFetchRow`, `BackupHost` | `CloudViews.swift`, `MarketDataUI.swift`, `BackupUI.swift` (E, 1c) | vervallen |
| `SectionLabel` | `Components.swift` (0A) | vervallen (dode code) |
| `AppTab` (oude cases), `Destination` | `Router.swift` (0B, golf 0a) | `App/Navigation/NavigationModel.swift` (0B) |

### 6.7 Eigendom van elk bestand

Controle: `docs/design/ownership-check.sh` leest het blok hieronder, loopt over elk bestand in `App/`, `Tests/`, `CoreTests/`, `scripts/`, `.github/`, `firebase/` en de losse hoofdbestanden en meldt een bestand zonder eigenaar of met twee eigenaren (de meest specifieke regel wint; een pad met `/` aan het eind geldt voor alles eronder; een `+` betekent nieuw bestand of nieuwe map). `docs/design/ownership-check.sh --owner <pad>` zegt wie een bestand bezit, voor het doorsturen van CI-fouten. Twee bijzonderheden: `BankLegacy.swift` is van B2 maar wordt door 0B in golf 0a aangemaakt (verhuizing), en G mag in golf 2 elk bestand aanpassen voor opruimen.

<!-- EIGENDOM-BEGIN -->
```text
# 0A Ontwerpsysteem
0A App/UI/Theme.swift
0A App/UI/Glass.swift
0A App/UI/Components.swift
0A App/UI/Fields.swift
0A App/UI/MoneyViews.swift
0A App/UI/BlockOrder.swift
0A App/Assets.xcassets/Contents.json
0A App/Assets.xcassets/AccentColor.colorset/Contents.json
+0A App/UI/Layout.swift
+0A App/UI/Motion.swift
+0A App/UI/RowActions.swift
+0A App/UI/Meters.swift
+0A App/UI/BlockOrderMigration.swift
+0A App/UI/ComponentGallery.swift
+0A scripts/design-checks.sh
+0A CoreTests/Tests/MyBuddyCoreTests/BlockOrderMigration.swift
+0A CoreTests/Tests/MyBuddyCoreTests/BlockOrderMigrationTests.swift
# 0B Schil en navigatie
0B App/MyBuddyApp.swift
0B App/RootView.swift
0B App/Router.swift
0B App/AppStore.swift
0B App/Pages/DestinationView.swift
0B App/Debug/DebugLaunch.swift
+0B App/Navigation/
+0B CoreTests/Tests/MyBuddyCoreTests/NavigationModel.swift
+0B CoreTests/Tests/MyBuddyCoreTests/SearchIndex.swift
+0B CoreTests/Tests/MyBuddyCoreTests/NavigationRulesTests.swift
+0B CoreTests/Tests/MyBuddyCoreTests/SearchIndexTests.swift
# F Grafieken en Core (poortwachter van App/Core en CoreTests)
F App/UI/Charts.swift
+F App/UI/ChartModels.swift
F App/Core/
F CoreTests/
+F CoreTests/Tests/MyBuddyCoreTests/ChartModels.swift
# A Tabroots
# (golf 1c: HomeView.swift, SavingsView.swift en ToolsView.swift zijn verwijderd)
+A App/Pages/Tabs/
# B1 Maand-pagina's
# (golf 1c: SavingsPages.swift is verwijderd)
B1 App/UI/SavingsDisplay.swift
B1 App/UI/MoneyFigures.swift
+B1 App/Pages/Month/
B1 CoreTests/Tests/MyBuddyCoreTests/MoneyFigures.swift
B1 CoreTests/Tests/MyBuddyCoreTests/SavingsDisplay.swift
B1 CoreTests/Tests/MyBuddyCoreTests/MoneyFiguresTests.swift
B1 CoreTests/Tests/MyBuddyCoreTests/AllocationEditTests.swift
B1 CoreTests/Tests/MyBuddyCoreTests/LineSaveTests.swift
B1 CoreTests/Tests/MyBuddyCoreTests/SalaryScheduleEditTests.swift
# B2 Bankrekening en Dag voor dag
B2 App/Pages/CashflowPages.swift
B2 App/UI/CashflowDisplay.swift
+B2 App/Pages/Bank/
B2 CoreTests/Tests/MyBuddyCoreTests/CashflowDisplay.swift
B2 CoreTests/Tests/MyBuddyCoreTests/CashflowDisplayTests.swift
# C Sparen
C App/Pages/PotPages.swift
C App/Pages/PortfolioPages.swift
C App/UI/PotDisplay.swift
+C App/Pages/Saving/
C CoreTests/Tests/MyBuddyCoreTests/PotDisplay.swift
C CoreTests/Tests/MyBuddyCoreTests/PotDisplayTests.swift
# D Plannen
D App/Pages/GoalPages.swift
D App/Pages/SavingsGoalPages.swift
D App/Pages/BufferPages.swift
D App/Pages/ProjectionPage.swift
D App/Pages/PurchasePages.swift
D App/Pages/AcceleratorPages.swift
+D App/Pages/Planning/
# E Instellingen en account
E App/Pages/SettingsView.swift
E App/Auth/
E App/Cloud/
E App/Config/FirebaseConfig.swift
E App/UI/BackupUI.swift
E App/UI/MarketDataUI.swift
E Tests/AppTests/
+E App/Pages/Settings/
# G Integratie, documentatie, CI, resources
G README.md
G SECURITY.md
G implementation_plan.md
G system_architecture.md
G task.md
G project.yml
G docs/v3-spec.md
G App/PrivacyInfo.xcprivacy
G App/Assets.xcassets/AppIcon.appiconset/
G scripts/
G .github/
G firebase/
```
<!-- EIGENDOM-EINDE -->

## 7. Verificatiebeleid

### 7.1 Poorten tussen de golven

De CI (`.github/workflows/ci.yml`: `core-tests` op Linux, `build-ios` met app-tests, `build-macos`) is het enige echte compileeroordeel; de scripts in `docs/design/` zijn voorcontroles (K18).

- **Poort 0a (0B klaar):** CI groen op `claude/ontwerp-0b`; `NavigationRulesTests` en `SearchIndexTests` groen; `docs/design/ownership-check.sh` klopt. Daarna maakt de orchestrator `claude/ontwerp-integratie` vanaf deze stand.
- **Poort 0b (0A en F klaar):** CI groen op elke eigen branch en op de integratiebranch na elke samenvoeging; `docs/design/contract-check.sh 0` meldt "CONTRACT COMPLEET"; `swift test` in `CoreTests` volledig groen; geen openstaande WIRING die golf 1 blokkeert. 0A en F blijven beschikbaar voor de WIRING-rondes van golf 1.
- **Poort 1a (B1, B2, C, D, E klaar):** per pakket CI groen op de eigen branch; na elke samenvoeging CI groen op de integratiebranch; WIRING van de vijf pakketten is uitgevoerd door de eigenaren (0A, 0B, F beschikbaar).
- **Poort 1b (A klaar):** CI groen; `contract-check.sh 1` meldt "CONTRACT COMPLEET"; elke bouwer van golf 1 levert zijn rapport met de uitvoer van `precheck.sh`.
- **Poort 1c (aangesloten):** CI groen na elke stap van par. 6.5; `docs/design/design-checks.sh` zonder FAIL behalve de compat-definities in de bestanden van 0A en F; de app start in de simulator op elke tab (scenario 7, "niet te testen hier" als er geen simulator is).
- **Oplevering (G):** `design-checks.sh --final`, `contract-check.sh final`, CI groen, alles uit par. 7.3 op de hele `App/`.

Falende CI: lees `get_job_logs`, bepaal per foutregel de eigenaar (`ownership-check.sh --owner <pad>`), meld het en herstel het in de eigen branch. Geen enkele golf begint voordat de poort ervoor groen is.

### 7.2 De controlescripts (`docs/design/`)

De scripts zijn getest tegen `HEAD` (nulmeting hieronder) en staan niet meer in dit plan afgedrukt, zodat er geen tweede kopie kan afwijken. 0A kopieert `design-checks.sh` naar `scripts/`.

| Script | Wat het doet |
|---|---|
| `design-checks.sh [--final] [pad ...]` | Een regel per grep tegen een verboden of verplicht patroon, met verwachting, aantal en PASS of FAIL; exit 1 bij een FAIL. Zonder pad over heel `App/`; met paden alleen over die bestanden (regels met `min:N` alleen bij een volledige run). Zonder `--final` tellen overgangsvormen niet mee (compat-laag, de oude tabbestanden, compat in `Router`); met `--final` (G) mag er geen enkele meer bestaan. Groepen: Typografie en maten; Kleur en glas; Navigatie en sheets; Toegankelijkheid en beweging; Grafieken; Verhuisde of herbouwde typen (par. 6.6); Taal (termenlijst); Instellingen zonder sheets. |
| `contract-check.sh [0\|1\|alles\|final]` | Twee soorten regels: `need` (het type bestaat) en `sig` (binnen het type komt de initializer-regex voor: labels en typen, zodat een oud type met dezelfde naam maar een oude init niet slaagt). `final` controleert bovendien dat geen overgangsvorm meer bestaat. |
| `ownership-check.sh [--owner <pad>]` | Het eigendomsblok van par. 6.7 tegen alle bestanden. |
| `precheck.sh <bestanden>` | Syntaxis (tree-sitter), ViewBuilder-limiet, `design-checks.sh` op deze bestanden. Geen compileerbewijs. |

**Nulmeting (`HEAD` 6140902, gemeten met `design-checks.sh`) en doel**

| Controle | Nu | Doel |
|---|---|---|
| `.font(.system(size:` | 5 | 0 |
| `caption2` | 25 | 0 |
| `design: .rounded` | 26 | 0 |
| `minimumScaleFactor` buiten `Components.swift` | 44 | 0 (alleen `BigAmount`) |
| `.uppercased()` | 13 | 0 |
| vaste hoogte 20-43 pt op knop of rij | 10 | 0 |
| `minTapTarget` bestaat | 0 | 1 of meer (iOS 44, macOS 28) |
| `.secondary` als voorgrondkleur | 300 | 0 |
| wit als voorgrond | 3 | 0 |
| `GlassBlock(` plus `LinkedBlock(` | 103 | 0 |
| `Chip*(` | 91 | 0 |
| `glassCard(`, `glassSurface(`, `.glassEffect(` buiten `Glass.swift` | 14 | 0 (ook niet in `Charts.swift`, K5) |
| `MeshBackground` | 11 | 0 |
| `Theme.olive*`, `Theme.flow*` | 32 | 0 |
| `Theme.buttonHeight` | 5 | 0 |
| `showSettings`, Instellingen als sheet | 3 | 0 |
| `homePath`, `savingsPath`, `toolsPath` buiten de overgangsbestanden | 1 | 0 |
| `GlassTabBar`, `barBackdrop` | 4 | 0 |
| `TabView` | 0 | 2 (app, Mac-instellingen) |
| `.sheet(` in de app | 26 | 16 of minder, en 0 in Instellingen, Account en Back-up |
| `.alert(` | 2 | 0 |
| `UIDevice`, `userInterfaceIdiom` | 1 | 0 |
| `navigationBarTitleDisplayMode` buiten `Components.swift` | 9 | 0 |
| `interactiveDismissDisabled`, `.searchable(`, `Settings {` | 0, 0, 0 | 1 of meer elk |
| `.animation(Theme.motion`/`quickMotion` buiten `Components`/`Motion` | 62 | 0 |
| `accessibilityReduceMotion`, `accessibilityReduceTransparency` | 0, 0 | 1 of meer elk |
| isHeader of accessibilityHeading | 3 | 8 of meer |
| `sensoryFeedback` | 0 | 5 of meer |
| `swipeActions` of `rowActions(` | 0 | 6 of meer |
| `contextMenu` of `rowActions(` | 2 | 6 of meer |
| `ContentUnavailableView` | 0 | 3 of meer |
| `ellipsis.circle` als rijmenu | 5 | 0 |
| pictogramknop zonder `IconButton` | 5 | 0 |
| `import Charts` en `Chart(` buiten `Charts.swift` | 5 en 5 | 0 |
| `accessibilityChartDescriptor` | 0 | 3 of meer |
| oude grafiektypen | 48 | 0 |
| `NoticeBanner`, `GainLabel`, oude keuzebladen, `MonthPickerBlock` buiten hun oude bestand | 2, 3, 2, 1 | 0 |
| oude termen (Home, Savings, Tools, Portefeuille, Meetpunt, Saldo nu, ...) | 37 | 0 |
| `.sheet(` in Instellingen, Account en Back-up (alleen volledige run) | 5 | 0 |

### 7.3 Aanvullende controles (G, en elke bouwer voor zijn eigen deel)

1. **Syntaxis en ViewBuilder.** `precheck.sh` op elk gewijzigd en nieuw `.swift`-bestand: 0 foutknopen, geen closure met meer dan 9 statements.
2. **Compileren.** CI groen (par. 7.1). Dit vervangt de oude regel "aanroepen letterlijk vergelijken als enige controle".
3. **Core.** `cd CoreTests && swift test`: volledig groen. `git diff --stat App/Core` toont alleen `Invest.swift`, `Overview.swift` en `Pots.swift` (en geen nieuw `Codable`-veld).
4. **Aanroepen tegen definities (extra, naast de CI).** Per symbool uit par. 4.4: `grep -rn "Naam(" App`; extra aandacht voor tuple-destructuring in `ForEach`, `if` in `AxisContentBuilder`, `@Bindable` voor `@Observable` bindings, `private` properties die buiten het type worden gebruikt, ontbrekende `import Charts` (alleen `Charts.swift`).
5. **Elke pictogramknop heeft een label:** `IconButton` is de enige manier (de meerregelige controle in het script); extra handmatig: `grep -rn "Image(systemName" App | grep -v "Label\|IconButton\|accessibilityHidden"` doorlopen op knoppen.
6. **Elke grafiek heeft een lege staat en een beschrijving:** `grep -rn "TrendChart(\|StackedBarChart(\|DonutChart(" App` en voor elke aanroep: het model komt uit een modelbouwer van F (dus heeft `summary` en `empty`); de testlijst van par. 5.5 is groen; `grep -c accessibilityChartDescriptor App/UI/Charts.swift` is 3 of meer (of, bij R10, `accessibilityLabel` met `summary` op alle drie).
7. **Raakdoelen:** `Theme.minTapTarget` is 44 op iOS en 28 op macOS; `grep -rnE "\.frame\((width|height|minHeight|minWidth): *(2[0-9]|3[0-9]|4[0-3])\)" App` geeft alleen decoratie (ringen, badges), geen knop; `StepButton`, `ColorChoiceRow`, `SymbolChoiceRow`, oogknop en terugknop op het inlogscherm halen `minTapTarget`.
8. **Geen sheet voor Instellingen, Account of Back-up** en geen sheet binnen een sheet: `grep -n "\.sheet(" ` in de bestanden die een sheet-inhoud definiëren (`SheetScaffold`-gebruikers) geeft niets; de controle in het script voor de instellingenmappen geeft 0.
9. **Kleur:** de hex-waarden van par. 4.1 en 4.2 staan letterlijk in `Theme.swift` (`grep -c` per waarde); `python3` op `plan/tokens.py` opnieuw draaien met de waarden uit de code geeft dezelfde contrastcijfers.
10. **Termen en taal:** het termenpatroon uit het script; handmatig: geen "Klik" op iOS, geen "tik" op de Mac, geen "Oeps", geen bezittelijk "Mijn" in titels.
11. **Contract en eigendom:** `contract-check.sh final` meldt "CONTRACT COMPLEET" en `ownership-check.sh` klopt; `grep -rn "showsSettings\|Theme.flow\|Theme.olive\|buttonHeight" App` geeft niets na G.
12. **Navigatie:** `NavigationRulesTests` groen; in de nieuwe bestanden komt `NavigationLink(value:` alleen voor in de gedeelde `DestinationLink` (`grep -rn "NavigationLink(value:" App | grep -v Components.swift` geeft niets na G); geen pad bevat een bestemming twee keer (scenario 22).

### 7.4 Handmatige scenario's (op een toestel of in de simulator; hier niet uitvoerbaar)

Elke bouwer voert de scenario's van zijn pakket uit zodra er een build is; G rapporteert per scenario "gedaan" of "niet te testen hier".

| # | Scenario | Slaagt als |
|---|---|---|
| 1 | Eerste start, leeg lokaal account | Overzicht toont Welkom met twee knoppen, geen lege grafiek, geen alert; "Salaris instellen" opent Salaris |
| 2 | Voorbeelddata laden | hero, `wealth`, `pots`, `invest`, `upcoming` gevuld; "Nog te verdelen" is op Overzicht, Maand (kaart Verdelen) en Verdelen hetzelfde getal |
| 3 | Uitgave toevoegen | in 3 tikken (Maand, Uitgaven, `+`); swipe verwijdert met bevestiging waar het moet; contextmenu heeft dezelfde acties; terugkerende regel vraagt "alleen deze maand of ook volgende" |
| 4 | Maand wisselen en periodekeuze Jaar op Maand | `MonthBar` stapt per maand; `PeriodPicker` Jaar verandert alleen de grafiek en niet de maand; het Overzicht blijft op de huidige maand en leest de keuze niet; cijfers op Maand en de pagina's sluiten; melding "Cijfers sluiten niet" alleen bij een echte afwijking |
| 5 | Verdelen met percentage, "Alles op nul", Overschrijfdag | zelfde uitkomsten als vóór de herbouw (`MonthFigures` ongewijzigd); een tik op een knop in een `AllocationRow` activeert maar een actie |
| 6 | Bankrekening: Saldo invullen, Geld bewegen, Minimumsaldo, drie segmenten | alle vijf acties werken; Dag voor dag toont een sectie per dag met bank- en potsaldo, standaard alleen dagen met boekingen; de uitklappers "Zo komt je saldo tot stand" (bank en potten) sluiten; zonder banksaldo een lege staat in plaats van een verdwenen blok |
| 7 | Tabs | pad per tab blijft bewaard bij wisselen; een terugtik op de actieve tab gaat naar de tabroot; Instellingen is vanaf een diepe pagina in 1 tik bereikbaar (iOS); op de Mac geen Instellingen in de zijbalk, wel Cmd+komma en Cmd+1 t/m Cmd+4; badge op Instellingen bij een conflict; geen enkele sheet voor Instellingen |
| 8 | Grafieken Bank en Dag voor dag | geen lege `Chart`; een dag is een stip met tekst; labels uniek |
| 9 | Zoeken vanaf elke tab | de zoekknop of Cmd+F opent het zoekveld op het Overzicht; "uitgaven", "back-up", "noodbuffer", "wachtwoord", "belegd sinds" en de naam van een pot openen de goede pagina; niets gevonden toont `ContentUnavailableView.search` |
| 10 | Spaarpotten | nieuwe pot (2 tikken), storten, rente, doel; pot zonder doel heeft geen volle ring; Verloop-grafiek verschijnt |
| 11 | **Beleggingen** | (a) nieuwe belegging met alleen Totaal ingelegd 3.000 en inleg 200, Belegd sinds 8 maanden geleden: lijn met "Geschat" en het onderschrift; (b) ticker zonder aantal: uitleg "Vul ook het aantal stuks in"; (c) ticker met aantal en geen internet: afgeleide lijn; (d) Huidige waarde invullen: echte lijn; (e) Totaal ingelegd wijzigen bij een bestaand meetpunt: "Ingelegd" volgt; (f) keuzebalk 6 mnd, 1 jaar, 3 jaar alleen als hij iets verandert; (g) donut ook bij een soort, dezelfde kleur als de lijst; (h) koersgrafiek met unieke labels en bij een fout "Probeer opnieuw"; (i) de drie `-mybuddy-demo-holding`-scenario's geven in de CI-screenshots een grafiek of lege staat met actie |
| 12 | Plannen | Doelen zonder schakelaar; Spaardoel berekenen (al bereikt: lege staat); Noodbuffer; Versnellers eindigt op het laatste punt en "Herstel" is bereikbaar |
| 13 | Toekomstschatting | lege invoer: lege staat; Looptijd zichtbaar; Streefbedrag als markering; scenario's herkenbaar zonder kleur |
| 14 | Instellingen | elke functie uit tabel 3.2 bereikbaar; Account-rij toont de status; terugnavigatie overal standaard |
| 15 | Account | wachtwoord wijzigen (pagina), uitloggen (dialoog aan de knop), account verwijderen (pagina), lokaal en cloud |
| 16 | Gegevens | back-up maken, terugzetten met bevestiging, Excel en CSV importeren (pagina `importReview`), 3 CSV-exports met een `fileExporter`, voorbeelddata, Alles wissen |
| 17 | Synchronisatie | conflict: banner op Overzicht en badge op Instellingen, keuze in Account, geen alert bij starten; offline-status; "Lokale gegevens uploaden?" in Account |
| 18 | Toegankelijkheid | Dynamic Type AX5 op alle tabroots (stapelen, niets afgekapt); VoiceOver-rotor Koppen en een grafiekbeschrijving; Verhoog contrast, Verlaag transparantie, Verlaag beweging, Onderscheid zonder kleur; kleurenblindsimulatie op de reeksen |
| 19 | Apparaten | iPhone SE-breedte, iPhone Pro Max, iPad 13 inch (zijbalk en Slide Over), Mac (venster van 640 tot 1400 breed, vier tabs in de zijbalk, `Settings`-venster, Cmd+komma, menubalk, `.help`, knoppen op `.regular`) |
| 20 | Licht en donker wisselen tijdens gebruik | geen onleesbare tekst, kaarten en canvas blijven onderscheidbaar (ook de olijfzwarte pagina met neutraalgrijze kaarten in donker, DRK-3: kijk in de CI-screenshot van golf 0b of dat bedoeld oogt) |
| 21 | Favorieten op het Overzicht | drie potten en vier beleggingen kiezen en ordenen vanuit het kaartmenu en vanuit het menu van Spaarpotten en Beleggingen; minder dan drie potten toont de lege plek-tegel; Sparen toont dezelfde tegels met "Alle ..."; een verwijderde pot verdwijnt uit de keuze |
| 22 | Navigatie | een link naar een pagina van een andere tab wisselt van tab (hero naar Verdelen: de terugknop gaat naar Maand); Overzicht, Sparen, Spaarpot, Dag voor dag, Spaarpot geeft geen tweede Spaarpot op de stapel; de diepste route is Plannen, Doelen, Doel, Versnellers |
| 23 | Blokvolgorde | een opgeslagen volgorde onder `savings`, `home` of `tools` komt terug op de nieuwe pagina's met dezelfde onderlinge volgorde; Sparen heeft geen "Volgorde aanpassen"; een nieuwe volgorde blijft na herstart |
| 24 | Rijen en reikwijdte | percentage-inleg, "Afwijkend", "Terug naar standaard", "Maak dit je standaard"; een terugkerende regel verwijderen via swipe toont dezelfde reikwijdte-dialoog als voorheen |

## 8. Risico's en wat er niet verandert

### 8.1 Wat niet verandert

- **Alle Core-logica en alle rekencijfers**, behalve de bedoelde wijziging voor beleggingen zonder meetpunt (C1 t/m C5, C7 t/m C9 in `Invest.swift`, `Overview.swift`, `Pots.swift`). `MonthFigures`, `MonthBoard`, `periodSummary`, `netWorth`, `remaining(in:)`, bank, potten, rente, doelen, versnellers, aankoopcheck blijven zoals ze zijn; de UI toont dezelfde getallen uit dezelfde bronnen.
- **Gegevens en formaten:** `FinanceData` en `AppSettings` (geen nieuw `Codable`-veld; `blockOrder` houdt `[String: [String]]`; `homePotIDs` en `homeHoldingIDs` blijven in gebruik), het JSON-back-upformaat, Excel/CSV-import en -export (`ImportMapping`, `Export`, `XLSX`), `AccountPrefs` en alle `@AppStorage`-sleutels, het opslagbestand per account.
- **Synchronisatie en inloggen:** `SyncController`, `CloudSync*`, `FirebaseAuthClient`, `AuthStore`, `PasswordHasher`, `KeychainSecretStore`: alleen de views eromheen veranderen. De inlogplicht blijft (K4).
- **Platformgrenzen:** iOS 18 en macOS 15 als ondergrens, Swift 5-modus, geen nieuwe dependencies, iOS 26-API's alleen achter `#available`. Debug-startargumenten blijven werken.
- **Alles wat de gebruiker nu kan**: par. 2.5 en 3.2 wijzen voor elk verwijderd onderdeel de plek aan. Bewust vervallen zijn alleen: de losse dagkiezer op Bankrekening (de dagsecties tonen dezelfde bank- en potsaldi), de pagina Overschrijvingen op Bankrekening (dezelfde cijfers staan op Verdelen), de bevestiging "Klopt met je overzicht" (alleen de melding bij een afwijking blijft), de drie tegels Inkomen, Uitgaven en Verdeeld in de hero van het Overzicht (ze staan op Maand en Verdelen), en de ontwikkelaarsuitleg over Firebase in de app. De keuze wat op de eerste tab staat en de opgeslagen blokvolgorde **blijven**.

### 8.2 Risico's

| # | Risico | Gevolg | Beheersing |
|---|---|---|---|
| R1 | SwiftUI en Charts zijn hier niet te compileren en `check_swift` is alleen een parser | foutieve labels, onbekende types of te grote `ViewBuilder`s pas zichtbaar na een build | **CI groen na elke golf en na elk pakket** (K18, par. 7.1); worktree per pakket; `precheck.sh` als voorcontrole; geen golf begint op een rode CI; is de CI niet te lezen, dan stopt het bouwen (R17) |
| R2 | Het andere herstelwerk wijzigt tegelijk bestanden in `App/` | bouwers overschrijven elkaar | start golf 0a pas als dat werk is vastgelegd; elke worktree begint op de actuele integratiebranch; de eigendomsgrenzen van 6.7 gelden ook voor dat werk |
| R3 | Gedrag van `TabView` met `.sidebarAdaptable`, een `NavigationStack` per tab en een padbinding is niet te testen (HIG-notes onzekerheid 4); idem de terugtik op de actieve tab | pad springt, terugtik werkt niet op elke iOS-versie, zijbalk op de Mac te smal | `TabStack` is een kleine, losse view; de selectie-`Binding` roept bij `new == current` `popToRoot` aan; minimumvenster 640 breed; scenario 7 en 19; terugval: zonder `.sidebarAdaptable` (alleen tabbalk) is een wijziging van een regel |
| R4 | De `Settings`-scene en `ActiveSession` bij een accountwissel | lege scene of een gewiste registratie van het nieuwe scherm (oud en nieuw `SignedInRoot` leven kort samen, `MyBuddyApp.swift:89-98`) | `unregister(store:)` wist alleen als de store dezelfde instantie is; `auth` en `cloud` expliciet in de scene geïnjecteerd; de scene toont "Log eerst in" zonder sessie |
| R5 | C1 verandert getallen in Vermogen, doelen en verdeling voor beleggingen zonder meetpunt | gebruikers zien een ander totaal | bedoeld; `HoldingDayTests` aangepast; de noot "Geschat" en het onderschrift maken het zichtbaar; te melden in de oplevernotitie |
| R6 | De compat-laag blijft hangen | oude namen en glas in de code | `design-checks.sh` meldt elke resterende `GlassBlock(`, `Chip*(`, `MeshBackground`; G verwijdert ze en `--final` vraagt "ALLES PASS" |
| R7 | Contractdrift tussen parallelle bouwers | aanroepen kloppen niet met definities | par. 4.4 is bindend en bevat de bevroren lijst (E); `contract-check.sh` controleert initializers; de CI vangt de rest; wijzigen kan alleen via WIRING |
| R8 | Een vervallen type wordt nog elders gebruikt (6.6) | build faalt | nieuwe namen naast de oude (K7); oude namen weg in 1c; `design-checks.sh` groep "Verhuisde of herbouwde typen"; CI |
| R9 | `ContentUnavailableView` is groot in een kleine kaart | lelijke lege staten | `EmptyHint` heeft `style: .inline`; `.page` alleen voor een hele lege pagina; grafieken krijgen een compacte variant |
| R10 | `accessibilityChartDescriptor` en `chartXSelection` zijn alleen op syntaxis gecontroleerd | compileerfout of onverwacht gedrag | de CI na golf 0b vangt het; terugval: alleen `accessibilityLabel` met `summary` |
| R11 | Contrastcijfers zijn berekend zonder vibrancy of glas | echte waarden iets anders | Accessibility Inspector op een toestel (scenario 18) |
| R12 | Het aantal pagina's stijgt van 18 naar 31 | meer te onderhouden | elke pagina is klein (hooguit 6 blokken), zoeken vindt alles vanaf elke tab (K20) |
| R13 | Op de Mac bestaat Instellingen alleen als `Settings`-venster | een diepe link moet het venster openen | `router.settingsRequest` en `openSettings()` (macOS 14+, ondergrens is 15); scenario 7 en 19 |
| R14 | De blokvolgorde-migratie kopieert verkeerd | een persoonlijke volgorde gaat toch verloren | `BlockOrderMigration` is een zuivere functie met tests voor de zeven rijen van 2.7; hij leest alleen en schrijft niets terug |
| R15 | `normalize` knipt een pad af bij een herhaalde bestemming | een link lijkt "terug" te gaan | gewenst (N9, K16); `NavigationRulesTests` leggen het vast; scenario 22 |
| R16 | `minimumScaleFactor` alleen in `BigAmount` | lange bedragen in smalle kolommen wrappen of stapelen | `FigureRow` en `AmountRow` stapelen; scenario 18 |
| R17 | De CI-runner `macos-26` is niet beschikbaar of een bouwronde duurt lang | geen compileerbewijs | stop het bouwen en meld het; de gebruiker kan een Xcode-build draaien; er wordt niet doorgebouwd op de aanname dat het wel compileert (kritiek 12) |
| R18 | Zes worktrees samenvoegen | conflicten in `CoreTests/` of gedeelde bestanden | de bestandsverdeling is disjunct (6.7); nieuwe testbestanden hebben unieke namen; de orchestrator voegt samen in vaste volgorde en wacht op groene CI na elke samenvoeging |
| R19 | De tijdelijke tabwortels (golf 0a tot 1c) tonen een lege Sparen-tab en oude schermen onder de nieuwe tabbalk | verwarrende tussenstanden en screenshots | nooit opleveren; de poort van 1c eist de definitieve wortels |
| R20 | `Color(light:dark:lightContrast:darkContrast:)` met `UIColor`- en `NSColor`-providers is blind geschreven | compileerfout of een kleur die niet meebeweegt met Verhoog contrast | de CI na golf 0b; terugval Color Sets (pakket 0A) |
| R21 | Een link naar een andere tab gebruikt per ongeluk `NavigationLink(value:)` | dezelfde pagina onder twee tabs | alleen `DestinationLink` (K16); controle in 7.3 punt 12; scenario 22 |
| R22 | De veeg-om-te-sluiten meldt een geweigerde poging niet terug | de gebruiker veegt en er gebeurt niets | bewust (principe 6): de veeg is uit zolang er wijzigingen zijn en "Annuleer" vraagt bevestiging |
| R23 | Olijfachtig canvas met neutraalgrijze systeemkaarten in donker (DRK-3) | kaarten en pagina passen niet bij elkaar | beoordelen in de CI-screenshot van golf 0b (scenario 20); alternatief is een eigen kaartkleur in dezelfde tint, zonder systeem-elevatie |

### 8.3 Niet in deze ronde (bewust)

Account optioneel maken (ACT-1, K4); `Tab(role: .search)` en een eigen zoektab; nieuwe-regel-commando's in de menubalk en TipKit-tips (vragen actie-routing in elke pagina); B-10 en B-11 uit `charts.md` (ontwerpvragen voor de Core-eigenaar); `Fmt` op `Locale.current` in plaats van vast `nl_NL` (audit 3.12); "Maak ongedaan" in plaats van bevestigen (audit S8); passkeys; `.inspector` op iPad; `privacySensitive`; **een gelaagd app-icoon voor iOS 26** (Icon Composer; `AppIcon.appiconset` blijft ongewijzigd). Alles daarvan is los te plannen en haalt niets van het bovenstaande onderuit.

### 8.4 Op een toestel vast te stellen (hier niet te zien)

Hoe de standaard x-as en een vlakke reeks in Swift Charts eruitzien bij onze eigen assen; of terugtikken op de actieve tab het pad leegt op iOS 18; de breedte van de zijbalk bij 640 pt op de Mac; of `confirmationDialog` op iPad en Mac bij de knop verschijnt; de werkelijke contrastwaarden met glas en vibrancy op iOS 26; de koersgrafiek (G3) met echte koersdata; of alle stap-tellingen van par. 2.10 kloppen (ze zijn afgeleid uit de code); hoe lang een CI-bouwronde duurt.

## Herzieningen

Deze versie vervangt de eerste (`HEAD` ca0c945, 1077 regels) na `critique.md`. De eerste versie staat in de git-geschiedenis (`git show 11447d4:docs/design/plan.md`).

**Wat is veranderd per bevinding**

| Kritiek | Ernst | Wat het plan nu zegt | Waar |
|---|---|---|---|
| F1 K9: kiezen van 3 potten en 4 beleggingen vervalt | blocker | K9 is vervangen door K9a t/m K9e: de keuze blijft; kaarten `pots` en `invest` op het Overzicht (`HomePotsCard`, `HomeHoldingsCard`), `PotsSummaryCard` en `PortfolioSummaryCard` tonen dezelfde tegels, `FavoritePotsSheet` en `FavoriteHoldingsSheet` als korte sheets van C; `homePots()` en `homeHoldings()` blijven in gebruik; scenario 21 | 0, 2.4, 2.5, 6.4 C, 6.6 |
| F2 geen compileerbare golf, geen compileeroordeel | blocker | K18: elke golf eindigt compileerbaar (golf 0a met tijdelijke tabwortels en een compat-`Router`), CI-poort na elk pakket en elke golf, `git worktree` per pakket, `precheck.sh` en `count_children.py` als voorcontrole; R1 is "CI groen na elke golf"; de verhuizing van de Bank-groep voorkomt een dubbele `BankPage` | 0, 6.1, 6.2, 6.3, 7.1, 8.2 |
| F3 maandsluiting bank en potten vervalt | major | K15: `CashflowBankBlock` en `CashflowPotsBlock` blijven als twee uitklappers "Zo komt je saldo tot stand" in Dag voor dag; de dagsectie is gespecificeerd (weekdag, gebeurtenissen, bank- en potsaldo aan het eind van de dag, overgeschreven bedrag); filter standaard "Alleen met boekingen" | 0, 2.4, 2.5, 6.4 B2 |
| F4 gedeelde maandstatus en dubbele cijfers over tabs | major | K17: Overzicht is "nu" (leest `focusMonth` en `periodMode` niet), Maand is "door de tijd" met `MonthBar` en een `PeriodPicker` die de maand niet verschuift; `flow` verhuist naar Maand; de hero toont alleen Nog te verdelen | 0, 2.2, 2.4, 2.6, 6.4 A |
| F5 Beleggingen: geen startmaand, niet reproduceerbaar | major | K19: "Belegd sinds" in `HoldingEditSheet`, "Huidige waarde" ook bij wijzigen en met ticker, onderschrift "Geschat uit je inleg, zonder rendement", `DebugLaunch`-scenario's `-mybuddy-demo-holding` en screenshots in `ci-screenshots.sh`, scenario 11 | 0, 5.2, 6.4 C, 6.5 G, 7.4 |
| F6 dedupe en diepte gelden niet voor `NavigationLink(value:)` | major | K16: `normalize` in de set van `pathBinding(for:)`; cross-tab links gebruiken `go` via een gedeelde `DestinationLink`; `go` bouwt het ouderpad; principe 4 herformuleerd; scenario 22 | 0, 1, 2.6, 4.4 A en B, 7.3 |
| F7 een werkmap en een testmodule; WIRING-bottleneck | major | worktree per pakket op eigen branch; stap 0 (0B, met `NavigationModel.swift` en tests) landt eerst; golf 1c is een aansluitronde door 0B en de eigenaars; G ruimt alleen op | 6.1, 6.2, 6.5 |
| F8 koppelingen buiten het contract; zwakke contractcontrole | major | bevroren lijst (4.4 E); nieuwe namen voorkomen dubbele definities (`NoticeCard`, `GainBadge`, `MonthBar`, `PeriodPicker`, `FavoritePotsSheet`, ...); `contract-check.sh` controleert initializers; `ci.yml`, `system_architecture.md`, `implementation_plan.md` en `task.md` zijn van G | 0 (K7), 4.4, 6.6, 6.7 |
| F9 formulierrijen in `List` | major | K6: `DistributePage` en `SalaryPage` zijn `PageScaffold` met `Card`s; `List` alleen voor echte rijen; DoD van B1 met scenario's 5 en 24 | 0, 2.4, 6.4 B1 |
| F10 TAB-3, Instellingen in Mac-zijbalk | minor | K2 legt de afweging vast; K3 en `#if !os(macOS)`: geen Instellingen-tab op de Mac, `Settings`-venster en `openSettings()` | 0, 2.1, 3.5 |
| F11 44 pt en `controlSize(.large)` overal; glazen annotatie | minor | K21: `minTapTarget` 44 op iOS en 28 op macOS, `controlSize` per platform; K5: de annotatie is `Theme.card` met rand | 0, 4.3, 4.4 B, 5.3 |
| F12 blokvolgorde-migratie | minor | `BlockOrderMigration` (Foundation-only, getest, leest zonder terug te schrijven) met de zeven rijen van 2.7; "Volgorde aanpassen" alleen bij drie of meer blokken | 0 (K8), 2.7, 6.3 0A |
| F13 veeg-om-te-sluiten | minor | alleen veeg uit bij `hasChanges` en bevestiging bij Annuleer; principe 6 en de componentenregel aangepast; twee `confirmationDialog`s aan verschillende subviews | 1, 4.5, 6.3 0A |
| F14 `ActiveSession`-race en terugtik | minor | `unregister(store:)`; `auth` en `cloud` expliciet in de Settings-scene; `Binding(get:set:)` met `popToRoot` | 2.1, 3.5, 4.4 A, 8.2 R3 en R4 |
| F15 zichtbaarheid van sync en gebaar-alleen functies | minor | badge op de tab Instellingen bij een conflict of uploadaanbod; "Koersen vernieuwen" in het werkbalkmenu van Beleggingen; Looptijd als zichtbaar blok op Toekomstschatting | 2.1, 2.4, 3.4 |
| F16 zoekindex zonder test, zoeken alleen op tab 1 | minor | `SearchIndex` Foundation-only met uitputtende test; zoekknop in elke tabwerkbalk en Cmd+F (K20) | 2.9 |
| F17 tikkentabel telt ongelijke dingen | minor | tabel 2.10 gecorrigeerd (tikken tot het doel of blad verschijnt) en de claim bescheiden: winst op scrollen, benaming en vindbaarheid, niet op tikken | 2.10 |
| F18 gaten in "gehele app" | minor | app-icoon expliciet buiten de ronde; `AuthView` volgt de DoD (geen mesh, geen glaskaart); de Liquid Glass-merkkeuze wordt gemeld (K5); `-mybuddy-scroll-to` voor `List`; G werkt `README.md`, `system_architecture.md` en `docs/v3-spec.md` bij | 0 (K5), 3.6, 6.5, 8.3 |

**Aanvullende wijzigingen buiten de kritiek (uit het uitwerken)**

- `ProgressMeter` en `SegmentedMeter` verhuizen van F naar 0A (`Meters.swift`): de cyclus 0A naar F verdwijnt (K12).
- 0B verhuist in golf 0a de Bank-groep van `SavingsPages.swift` naar `App/Pages/Bank/BankLegacy.swift` (B2), omdat B2 een nieuwe `BankPage(section:)` bouwt en twee definities niet compileren.
- Het eigendomsblok in 6.7 is nu door een script leesbaar (`ownership-check.sh`) en bevat ook `scripts/`, `.github/`, `firebase/`, `Tests/` en `CoreTests/`; het script van par. 7.2 staat niet meer in het plan afgedrukt maar in `docs/design/design-checks.sh` (de nulmeting is opnieuw gemeten).
- `NavigationRules.go` bouwt het ouderpad (een Spaarpot onder Spaarpotten), zodat terug naar de lijst gaat in plaats van naar de tabwortel.
- De pakketten hebben elk een CI-poort in hun definitie van klaar.

**Wat bewust niet (of anders) is overgenomen**

| Voorstel uit de kritiek | Besluit | Reden |
|---|---|---|
| Color Sets in `Assets.xcassets` in plaats van tokens in code (5.3) | tokens in code, met Color Sets als terugval voor alleen de tokens met een hoog-contrastvariant (0A) | de bestaande `Color(light:dark:)` (`Theme.swift:18-26`) bouwt en de hex-waarden staan op een plek, zodat de contrastcijfers opnieuw te berekenen zijn; de CI na golf 0b beslist |
| Een bijgewerkte stub-typecontrole (`scratchpad/ci-ui`) als voorcontrole (F2) | niet onderhouden | een nabootsing van 600 regels API's die verouderd is en een deel van de fouten mist; de CI geeft het echte oordeel; `precheck.sh` (syntaxis, ViewBuilder-limiet, ontwerpcontrole) is genoeg als snelle controle |
| TAB-3 volgen en terug naar 3 tabs (F10, eerste optie) | 5 tabs met een vastgelegde afweging (K2) | Instellingen blijft op elke diepte 1 tik weg en Plannen krijgt een eigen plek; de eigen toets wordt bewust verruimd |
| `Tab(role: .search)` als zoektab (F16) | zoeken via een knop in elke tabwerkbalk, Cmd+F en `.searchable` op het Overzicht (K20) | `Tab(role: .search)` bestaat vanaf iOS 18 en macOS 15 (gelezen in de bewaarde documentatie), maar met vijf tabs zou het een zesde item in de balk zijn; een knop in de werkbalk kost geen plek in de balk en past bij het zoekveld op het Overzicht. Los te plannen (8.3) |
| "Schrap de zin over drie niveaus" (F6, tweede optie) | de zin is herformuleerd (principe 4) en door K16 waar gemaakt | `go` en `normalize` begrenzen de diepte; het diepste pad is Plannen, Doelen, Doel, Versnellers |
| Aparte `overviewFocus` en `monthFocus` in `Router` (F4, alternatief) | niet nodig | het Overzicht leest de maandstatus niet meer (K17) |
| 0A één verwijdering in `HomeView.swift` toestaan (4.2) | niet nodig | nieuwe namen voor vervangende types voorkomen dubbele definities (K7) |
| Een andere kaartkleur in donker (6, punt 8, DRK-3) | systeemkaartkleur blijft | de keuze is te beoordelen in de CI-screenshot (scenario 20, R23); een eigen kleur kost de systeem-elevatie |

**Eindtelling van de herziening** (uit `ownership-check.sh`): 182 bestanden onderzocht (90 in `App/`, 3 in `Tests/`, 78 in `CoreTests/`, 11 daarbuiten: `scripts/`, `.github/`, `firebase/` en de losse hoofdbestanden), geen enkel zonder eigenaar en geen enkel met twee. Per eigenaar: 0A 8, 0B 6, F 104 (35 in `App/Core`, `Charts.swift` en 68 in `CoreTests/`), A 3, B1 9, B2 4, C 5, D 6, E 16, G 21; daarnaast de nieuwe bestanden en mappen met `+` in het blok. Elk pakket in par. 6.3 tot 6.5 heeft een definitie van klaar met de CI-poort.

## Bijlage: bewijs en hulpmiddelen

| Wat | Waar |
|---|---|
| Contrast en kleurenblindheid van de tokens (par. 4.1, 4.2) | `/tmp/claude-0/-home-user-MyBuddy/9beb118c-8e88-5a84-a4b5-426733aaf64d/scratchpad/plan/tokens.py` en `final.py`; uitvoer in par. 4 |
| Controlescripts | `docs/design/design-checks.sh` (nulmeting in 7.2), `contract-check.sh`, `ownership-check.sh`, `precheck.sh`, `tools/check_swift.py`, `tools/count_children.py`, `tools/ownership_check.py` |
| Code voor modellen, componenten en tests van de grafieklaag | `docs/design/charts-prototype.md` B1 t/m B4 |
| Kritiek op de eerste versie | `docs/design/critique.md` |
| Bronnen van dit plan | `docs/design/hig-notes.md`, `docs/design/audit.md`, `docs/design/charts.md` |
