# Ontwerpplan MyBuddy: Apple-richtlijnen, eenvoud, Instellingen als pagina, werkende grafieken

Peildatum 15 oktober 2026, `HEAD` ca0c945. Dit is het definitieve plan van de architect, gebaseerd op `hig-notes.md` (regel-id's zoals `GLS-1`), `audit.md` (id's zoals `N1`, `E4`) en `charts.md` (id's zoals `G1`, `C1`), en op de kernbestanden zelf (`RootView`, `Router`, `Components`, `Glass`, `Theme`, `SettingsView`, `HomeView`, `SavingsView`, `ToolsView`, `BlockOrder`, `Charts`, `Fields`, `CloudViews`, `BackupUI`, `Invest`). Er is niets in `App/` of `CoreTests/` aangepast. SwiftUI kan hier niet compileren: wat hieronder over views staat, is ontwerp, geen waarneming.

**Hoe te lezen.** Sectie 2 en 3 zeggen wat de gebruiker straks ziet. Sectie 4 is het **contract**: exacte namen en handtekeningen waar de bouwers op coderen. Sectie 6 verdeelt het werk; elk bestand heeft precies een eigenaar. Sectie 7 bevat het controlescript en de scenario's. Regelnummers gelden voor ca0c945; zoek op het patroon.

**De vier wensen van de gebruiker en waar ze zijn opgelost**

| Wens | Antwoord | Sectie |
|---|---|---|
| Ontwerp volgt de Apple HIG in de hele app | Native `TabView`, systeemachtergronden en -kaartkleuren, glas alleen voor bediening, Dynamic Type, 44 pt, contrast 4,5:1, Reduce Motion en Transparency, `List` met swipe-acties, `ContentUnavailableView`, Mac-menubalk en `Settings`-scene | 1, 4 |
| Eenvoudiger: onderdelen makkelijk vinden en uit elkaar houden | 5 tabs met elk een eigen domein, vaste paginaopbouw, maximaal 6 blokken per pagina, een woord per begrip, een plek per functie, zoeken | 2 |
| Instellingen: account los, hele pagina in plaats van pop-up | Tab Instellingen met Account als eerste rij naar een eigen pagina; 6 korte groepen; op de Mac ook de `Settings`-scene; geen enkele sheet | 3 |
| Alle grafieken werken en volgen de invoer (Beleggingen) | Een Core-fix (afgeleid beginpunt uit "Totaal ingelegd"), een modellaag met lege staten, vier componenten, 17 grafiekplekken gelijkgetrokken | 5 |

## 0. Besluitenlijst

Alles hieronder is besloten; de bouwers stellen geen vragen maar volgen dit.

| # | Besluit | Reden |
|---|---|---|
| K1 | **Native `TabView` met `.tabViewStyle(.sidebarAdaptable)`**; de eigen `GlassTabBar` en `barBackdrop` verdwijnen. | TAB-5, LAY-8: tabbalk op iPhone, zijbalk op iPad en Mac, niets onderaan het Mac-venster; glas komt gratis van het systeem. |
| K2 | **5 tabs: Overzicht, Maand, Sparen, Plannen, Instellingen.** | Indeling naar gebruik (audit 4.4): wat staat er nu, elke maand, af en toe, zelden, beheer. Vijf is het maximum zonder "Meer"-tab (TAB-3). |
| K3 | **Instellingen is een eigen tab**, geen knop in de balk. | Een tab blijft op elke diepte zichtbaar, dus Instellingen is altijd **1 tik** weg, ook vanaf een detailpagina; een balkknop zou op alle diepere pagina's ontbreken. Het is navigatie, geen actie (TAB-1). Op de Mac komt er naast het zijbalk-item ook de `Settings`-scene (Cmd+komma), zodat het Mac-gedrag klopt zonder een onzekere API om het item te verbergen. |
| K4 | **Account blijft verplicht om de app te openen**, maar staat los van de rest: eigen pagina, geen sheet. | De HIG (ACT-1) wil dit anders, maar een lokaal account heeft een eigen gegevensmap (`AuthStore.storageURL(for:)`). Migreren raakt de gegevens van de gebruiker en valt buiten de vraag. Staat onder "Niet in deze ronde" (sectie 8). |
| K5 | **Inhoudsblokken worden gegroepeerde kaarten** (`Card`, systeem-kaartkleur op een licht olijf getinte achtergrond) en `List`. Liquid Glass komt alleen van het systeem (tabbalk, werkbalk, sheets, menu's) en van tijdelijke bediening in een grafiek. | GLS-1, GLS-2: 92 `GlassBlock` plus 86 glazen knoppen is glas op glas in de inhoudslaag. |
| K6 | **Alle pagina's met rijen die je wijzigt, verwijdert of herordent worden `List`-pagina's** (`ListScaffold`) met swipe-acties plus contextmenu. Dashboards en rekenpagina's blijven `PageScaffold` met kaarten. | LST-1, LST-3, LST-8: een rij kan alleen in een `List` swipen. |
| K7 | **Publieke API van bestaande componenten blijft bestaan** als compat-laag (`GlassBlock`, `LinkedBlock`, `ChipButton`, `ChipLink`, `ChipGrid`, `ProgressBar`, `ProgressRing`, `SegmentBar`, `MeshBackground`, `Theme.flow*`). Elke eigenaar migreert zijn eigen bestanden naar de nieuwe namen; pakket G verwijdert de compat-laag. | Zes bouwers werken tegelijk; niets hoeft te breken voordat de laatste klaar is. |
| K8 | **Blokvolgorde blijft** en wordt zichtbaar: knop "Volgorde aanpassen" in het menu van de werkbalk, een pagina "Indeling" in Instellingen, en het contextmenu (lang indrukken) blijft als sneltoets. | ACC-7: een functie die alleen via een gebaar werkt, is niet toegankelijk. |
| K9 | **"Kies potten voor Home" en "Kies beleggingen voor Home" vervallen.** | Het Overzicht toont geen pot- of belegging-tegels meer; Sparen toont alle potten en beleggingen. De modelvelden `homePotIDs` en `homeHoldingIDs` blijven bestaan (back-up en sync); alleen de keuzeschermen verdwijnen. |
| K10 | **"Dag voor dag" wordt een segment van Bankrekening**, "Uitgaven" een eigen pagina, "Salaris instellen" een subpagina van Inkomen. | Audit E4, E5: het belangrijkste is nu het moeilijkst te vinden. |
| K11 | **Een Core-fix voor Beleggingen**: een belegging zonder meetpunt krijgt een afgeleid beginpunt uit "Totaal ingelegd" en de inleg (charts.md C1 t/m C9). | Oorzaak van de kapotte grafiek (sectie 5). |
| K12 | **Eén grafieklaag**: `App/UI/ChartModels.swift` (Foundation-only, getest) en `App/UI/Charts.swift` (4 componenten). De acht oude grafiektypen verdwijnen. | CHT-2, CHT-7, CHT-11. |
| K13 | **Geen eigen weergave-, taal- of haptiekinstelling**, geen `.rounded`-cijfers, geen `caption2`. | DRK-1, SET-3, TYP-6, TYP-4. |
| K14 | **Termenlijst (par. 2.8) is bindend**: een woord per begrip. | Audit E1 t/m E17. |

## 1. Ontwerpprincipes

1. **Inhoud is geen glas.** Glas is voor bediening en navigatie (GLS-1). Inhoud staat in kaarten of lijsten; knoppen in inhoud zijn `.bordered` of `.borderedProminent`, nooit glas op glas.
2. **Een plek per functie, een woord per begrip.** Elke functie heeft een primaire route; dubbele ingangen en dubbele cijfers verdwijnen (NAV-5, WRT-2).
3. **Elke pagina is op dezelfde manier opgebouwd:** bovenaan de kerncijfers, daaronder secties met een eigen kop, acties in de werkbalk, destructieve acties onderaan en rood (LAY-1, LST-2).
4. **Weinig, dichtbij, ondiep:** 5 tabs, maximaal 6 blokken per pagina, maximaal 3 niveaus (tab, pagina, detail), progressive disclosure voor de rest (LAY-2, NAV-4, SIM-2).
5. **Instellingen is nooit een sheet en het account staat los** van rekenen, koersen en gegevens (SET-4, ACT-5).
6. **Een sheet is een korte taak** met Annuleer links en Bewaar rechts; nooit een sheet in een sheet; veeg-om-te-sluiten vraagt bevestiging bij niet-bewaarde invoer (SHT-1 t/m SHT-5).
7. **Dynamic Type voorop:** alleen tekststijlen, stapelen bij toegankelijkheidsformaten, 44 pt raakdoelen, krimpen alleen voor een kerngetal (TYP-1 t/m TYP-3, ACC-2).
8. **Contrast en nooit alleen kleur:** tekst 4,5:1 in licht en donker, hoog-contrastvariant, symbool of teken of label naast elke kleur (COL-3, COL-4). Domeinkleur is een aanvulling, nooit de enige drager.
9. **Elke grafiek is een zuivere functie van de invoer**, heeft een lege staat, een samenvatting voor VoiceOver en een tweede kanaal naast kleur (CHT-2, CHT-5, CHT-7, CHT-9).
10. **Een gebaar is altijd ook zichtbaar**: swipe en contextmenu spiegelen een knop of menu; beweging respecteert Verlaag beweging; haptiek alleen bij discrete gebeurtenissen (ACC-4, ACC-7, FDB-4).
11. **Elk platform eigen gedrag:** zijbalk op iPad en Mac, `Settings`-scene, menubalk, sneltoetsen, `.help`, leesbare breedte (MAC-1 t/m MAC-6, LAY-7).
12. **Vereenvoudigen zonder iets te verliezen:** elke functie die nu bestaat blijft bestaan; per verwijderd of samengevoegd onderdeel staat in par. 2.5 en 3.2 waar de functie heen gaat.

## 2. Informatiearchitectuur

### 2.1 Navigatie: native `TabView`, Instellingen als tab

- **Vorm.** `TabView(selection:) { Tab(title, systemImage:, value:) { ... } }` met `.tabViewStyle(.sidebarAdaptable)` (iOS 18 en macOS 15, dus zonder `#available`). iPhone: tabbalk onderin die op iOS 26 als glas boven de inhoud zweeft. iPad: balk bovenin die in een zijbalk kan veranderen. Mac: zijbalk. Op iOS 26 erbij: `.tabBarMinimizeBehavior(.onScrollDown)` achter `#available(iOS 26, *)`.
- **Een `NavigationStack` per tab** met een eigen pad (`router.paths[tab]`). Van tab wisselen wist niets (TAB-6). De stack zit niet in de tabroot maar in een gedeelde `TabStack` (par. 4.4), zodat elke tabroot alleen inhoud is.
- **Instellingen: tab of knop?** Gekozen: **tab**, laatste in de rij. Onderbouwing: (1) HIG `tab-bars`: een tabbalk is voor navigatie op het hoogste niveau; Instellingen is een bestemming, geen actie. (2) De eis "maximaal een tik vanaf overal, nooit een sheet" geldt alleen voor een tab: de balk blijft zichtbaar bij elke push, een toolbarknop staat alleen op tabwortels en ontbreekt op alle diepere pagina's. (3) iOS-instellingen op een eigen tab is gangbaar voor een app met een account en gegevensbeheer; op de iPad staat het als laatste item in de zijbalk. (4) Op de Mac staat naast het item ook de `Settings`-scene met Cmd+komma (SET-4, MAC-3); dezelfde pagina's, zes panes.
- **Zoeken** zit niet in een eigen tab (dat zou een zesde tab zijn) maar als `.searchable` op het Overzicht (par. 2.9).
- **Terugtik op de actieve tab** brengt naar de tabroot waar het systeem dat al doet; of het op alle versies werkt is op een toestel te controleren (TAB-6 is `[K]`). `Router.popToRoot(_:)` bestaat voor menu-commando's.

### 2.2 De tabs

| Tab | Titel (grote titel) | Symbool | Domein | Wat je er doet | Rootbestand |
|---|---|---|---|---|---|
| 1 | Overzicht | `chart.pie` | overview | Wat staat er nu: nog te verdelen, waar gaat je geld heen, vermogen, komende dagen | `OverviewTab` |
| 2 | Maand | `calendar` | money | Elke maand: Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag | `MonthTab` |
| 3 | Sparen | `banknote` | saving, investing | Spaarpotten en Beleggingen | `SavingTab` |
| 4 | Plannen | `flag.checkered` | goals, tools | Doelen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck | `PlanningTab` |
| 5 | Instellingen | `gearshape` | settings | Account, Rekenen, Koersen, Gegevens, Indeling, Over | `SettingsView` |

Alle titels zijn een woord, Nederlands, zinshoofdletter (TAB-4, WRT-2). De gevulde variant kiest het systeem zelf (`AppTab.symbol(selected:)` vervalt).

### 2.3 Een vaste opbouw voor elke pagina

Zo houd je onderdelen uit elkaar: dezelfde plek voor hetzelfde, in elke pagina.

1. **Kop van de pagina**: grote titel alleen op de vijf tabwortels, daaronder (detailpagina's) een korte titel in de balk. Detailtitels zijn kort (NAV-3).
2. **Kerncijfers eerst**: de eerste kaart of sectie toont het ene getal waar de pagina over gaat (`BigAmount`), met maximaal drie ondersteunende cijfers (`FigureRow` met `StatTile`, of `AmountRow`).
3. **Secties met een eigen kop**, elk met het domeinsymbool: `Card(title:symbol:domain:)` op dashboards, `Section(header:)` in een `List`. Een kop is een VoiceOver-kop. Maximaal 6 per pagina, liefst 3 tot 5.
4. **Acties in de werkbalk**: een primaire actie (`plus`, trailing), de rest in een `ellipsis`-menu. Knoppen in de inhoud alleen voor de ene logische vervolgstap van die sectie.
5. **Onderaan destructief**: verwijderen staat in een eigen sectie onderaan, rood, met een bevestiging aan de knop zelf (DLG-4).
6. **Lege staat in plaats van lege ruimte**: elke sectie en elke grafiek zonder gegevens toont uitleg plus een knop.

Drie paginavormen: **tabroot** (dashboard van kaarten, `PageScaffold(large: true)`), **lijstpagina** (`ListScaffold`, rijen met swipe), **rekenpagina** (`PageScaffold`: uitkomst bovenaan, invoer daaronder, details in een uitklapper). Een formulier is een `SheetScaffold`.

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

Een blok is een kaart op een dashboard of een sectie met kop in een lijstpagina. De rijen in een lijst (de 31 dagen op Dag voor dag, de regels van Uitgaven) zijn geen blokken. "Eig." verwijst naar het werkpakket (sectie 6).

**Tabroots**

| Pagina | Eig. | Blokken (volgorde standaard) | Wat er verandert |
|---|---|---|---|
| **Overzicht** (`OverviewTab`) | A | Meldingen (geen blok): opstartmelding, opslaan mislukt, `SyncAttentionBanner`, "Cijfers sluiten niet". **Kern**: *Nog te verdelen in oktober* (hero, 3 tegels Inkomen, Uitgaven, Verdeeld, tik opent Verdelen). Dan `flow`, `wealth`, `upcoming` (zie onder). Lege start: `EmptyHint(.page)` "Welkom bij MyBuddy" met "Salaris instellen" (prominent) en "Voorbeelddata laden" in plaats van de drie kaarten. | Vervangt Home, het Savings-blok Overzicht, de pagina Overzicht en de periodekeuze op Savings. |
| ... `flow` "Waar gaat je geld heen" | A | `PeriodControl` (Maand, Half jaar, Jaar), `StackedBarChart`, tegels Inkomen, Uitgaven, Overgehouden; uitklapper "Meer cijfers" (Gespaard, Belegd, Gemiddeld overgehouden per maand, toelichtingen); uitklapper "Maand voor maand" | Bevat alles van de oude pagina Overzicht; de herhaalde tegel "Over" valt weg (audit H3). |
| ... `wealth` "Vermogen" | A | `BigAmount` vermogen eind van de maand, `TrendChart`, 3 `AmountRow`-links: Bankrekening, Spaarpotten, Beleggingen | Zoals de oude kaart Vermogen. |
| ... `upcoming` "Komende dagen" | A (kaart: B2) | `UpcomingDaysCard()` uit B2 (de oude "Komende 14 dagen"), link "Dag voor dag" | Was verstopt op Bankrekening. |
| **Maand** (`MonthTab`) | A | `MonthBar` bovenaan. Vijf kaarten, elk met het kerncijfer en een tik naar de pagina: `income` Inkomen, `expenses` Uitgaven, `distribute` Verdelen, `bank` Bankrekening, `days` Dag voor dag. | Nieuw: Uitgaven en Dag voor dag zijn nu een kaart op een tab. |
| **Sparen** (`SavingTab`) | A (kaarten: C) | `pots` `PotsSummaryCard()`, `portfolio` `PortfolioSummaryCard()` | Vervangt Home-blokken Spaarpotten en Beleggingen en de Savings-blokken met dezelfde namen. |
| **Plannen** (`PlanningTab`) | A (kaarten: D) | `goals` `GoalsSummaryCard()`, `buffer` `BufferSummaryCard()`, `accelerators` `AcceleratorsSummaryCard()`, `projection` `ProjectionSummaryCard()`, `purchase` `PurchaseSummaryCard()` | Een tab voor alles wat plannen en rekenen is (was verdeeld over Savings en Tools). |
| **Instellingen** (`SettingsView`) | E | Zie par. 3: Account-rij, Rekenen, Koersen, Gegevens, Indeling, Over | Van sheet naar tab. |

**Detailpagina's** (max. 6 blokken)

| Pagina (`Destination`) | Eig. | Vorm | Blokken |
|---|---|---|---|
| Inkomen (`.income`) | B1 | lijst | `MonthBar`; **Samenvatting** (inkomen, Salaris en Overige inkomsten als `AmountRow`, schemazin, rij "Salaris instellen" naar `.salary`); **Salaris deze maand** (uitbetalingen, afwijkend bedrag of andere uren); **Overige inkomsten** (rijen, swipe, `+` in werkbalk) |
| Salaris (`.salary`, nieuw) | B1 | lijst | **Standaard salaris** (vast of uurloon); **Wanneer krijg je salaris?** (maandelijks, om de zoveel weken of dagen, eerste uitbetaling, salarisdag zonder uitbetaling, de volgende 4 data) |
| Uitgaven (`.expenses`, nu een echte pagina) | B1 | lijst | `MonthBar`; **Samenvatting** (uitgaven, waarvan uit spaarpotten, Vast en Variabel); **Vaste uitgaven**; **Variabele uitgaven**; werkbalk: `+`, menu met "Standaard uitgaven invullen" |
| Verdelen (`.distribute`) | B1 | lijst | `MonthBar`; **Samenvatting** (nog te verdelen, balk, Inkomen, Uitgaven, Verdeeld, waarschuwingen); **Spaarpotten**; **Beleggen**; **Overschrijfdag** (uitklapper); menu: Standaardverdeling, Rest over potten, Alles op nul |
| Bankrekening (`.bank`, `.cashflow`) | B2 | lijst met segmenten Saldo / Dag voor dag / Boekingen | *Saldo*: hero Saldo vandaag (+ "Saldo invullen"), **Verwacht verloop**, **Binnen en eruit**, **Minimumsaldo**. *Dag voor dag*: samenvatting en melding bij afwijking, **Saldo per dag**, een sectie per dag (filter, "Naar vandaag"). *Boekingen*: **Geschiedenis**. Werkbalkmenu "Geld bewegen" (storten, opnemen, naar pot, van pot, saldo invullen) |
| Spaarpotten (`.pots`) | C | lijst | **Samenvatting** (totaal gespaard, doel, voortgang, inleg deze maand, rente dit jaar); **Potten** (rijen met swipe); werkbalk `+` |
| Spaarpot (`.pot`) | C | lijst | hero **Saldo** (ring, doel, verwacht eind, knoppen Storten en Opnemen) met **Verloop** (nieuw); **Komende boekingen**; **Inleg en rente**; **Geschiedenis**; **Saldo op datum** (uitklapper); menu: Geld bewegen, Bewerken; onderaan Verwijderen |
| Beleggingen (`.portfolio`) | C | lijst | **Samenvatting** (waarde, winst, koersstatus); **Groei** (`TrendChart` met venster); **Verdeling** (`DonutChart` met lijst); **Beleggingen** (rijen met swipe); pull-to-refresh |
| Belegging (`.holding`) | C | lijst | **Samenvatting**; **Koers en waarde** (segment, `TrendChart`); **Uitgangspunten**; **Inleg**; **Waarde-updates** (rijen met swipe); menu: Bewerken, Waarde bijwerken, Koers vernieuwen |
| Doelen (`.goals`) | D | lijst | **Doelen** (rijen), lege staat; werkbalk `+` met Nieuw doel, Spaardoel berekenen, Noodbuffer |
| Doel (`.goal`) | D | rekenpagina | doeltype met ring, **Zo is het berekend**, **Versnellers**, **Toegepast** |
| Spaardoel berekenen (`.savingsGoal`) | D | rekenpagina | **Uitkomst**, **Invoer**, **Verloop**, **Details** (uitklapper: wat als, ingelegd en rente, per jaar), acties "Maak er een spaarpot van" en "Maak er een doel van" |
| Noodbuffer (`.buffer`) | D | rekenpagina | **Uitkomst** (doel, balk, tegels, verloop), **Jouw situatie** (invoer), **Spaarpot Noodbuffer** (aanmaken of aanpassen) |
| Versnellers (`.accelerators`) | D | rekenpagina | **Voor welk doel?** (alleen bij meer dan een doel), **Versnellers**, **Toegepast** |
| Toekomstschatting (`.projection`) | D | rekenpagina | **Uitkomst** (3 scenario's), **Verloop**, **Uitgangspunten** (uitklapper), **Streefbedrag** |
| Aankoopcheck (`.purchase`) | D | rekenpagina | wizard in 3 stappen (ongewijzigd), elke stap een blok, daarna Uitkomst, Kan het?, Goedkoper te vinden? |
| Account en de rest van Instellingen (`.settings(_)`) | E | lijst | Zie par. 3 |

Ten opzichte van nu: pagina's 18 naar 31 (5 tabroots, 16 detailpagina's, 10 instellingenpagina's), maar het aantal kaarten per scherm gaat van 3 tot 39 naar 1 tot 6, en elke pagina is hooguit drie niveaus diep.

### 2.5 Wat is samengevoegd of vervallen, en waar de functie terechtkomt

| Oud onderdeel | Straks | Functie behouden? |
|---|---|---|
| Tabs Home, Savings, Tools (Engels) | Tabs Overzicht, Maand, Sparen, Plannen, Instellingen | ja |
| Home: `RemainingHeader` | Overzicht, hero | ja, 3 tegels blijven |
| Home: `OverviewBlock`, Savings: `PeriodBlock`, pagina `OverviewPage` (6 kaarten) | Overzicht `flow` en `wealth`; "Cijfers" en "Maand voor maand" als uitklappers; "Klopt met je dagoverzicht" alleen als melding bij afwijking | ja; de herhaalde tegel "Over" (H3) en de bevestiging "Klopt" vervallen |
| Home: `PotsBlock`, `InvestBlock`, Savings: `PotsSummaryBlock`, `PortfolioBlock` | Sparen: `PotsSummaryCard`, `PortfolioSummaryCard` | ja |
| `PotPickerSheet`, `HoldingPickerSheet`, chips "Kies potten" en "Kies beleggingen", `EmptySlotTile` | vervallen (K9) | de keuze wat op Home staat bestaat niet meer; alle potten en beleggingen staan op Sparen |
| `WelcomeBlock` | Lege staat van het Overzicht | ja, met "Voorbeelddata laden" daar |
| Savings: `IncomeBlock`, `BankBlock`, `DistributeBlock` | Maand: kaarten `income`, `bank`, `distribute` | ja |
| Savings: `BufferBlock`, `GoalsHubBlock`; Tools: `AcceleratorsBlock`, `ProjectionBlock`, `PurchaseBlock` | Plannen: vijf kaarten | ja |
| Periodekeuze bovenaan Savings (geldt maar voor 4 van 8 blokken) | alleen in `flow` op het Overzicht; de Maand-pagina's hebben een `MonthBar` | ja |
| `IncomePage`: standaard salaris en schema | Subpagina Salaris (`.salary`) | ja |
| `BankPage`: Vaste en Variabele uitgaven | Pagina Uitgaven | ja |
| `BankPage`: chip "Standaard uitgaven invullen" | Werkbalkmenu en lege staat van Uitgaven | ja |
| `BankPage`: `BankBalanceBlock` met 5 chips | Hero Saldo met "Saldo invullen"; "Geld bewegen" in het werkbalkmenu | ja |
| `BankPage`: `BankTransfersBlock` "Overschrijvingen" | vervalt; dezelfde cijfers staan op Verdelen; in "Binnen en eruit" linken de rijen naar Spaarpotten, Beleggingen en Verdelen | ja (H6) |
| `BankPage`: `BankDayBlock` (dagkiezer), `BankUpcomingBlock`, pagina `CashflowPage` met 28 tot 31 dagkaarten | Segment Dag voor dag met een sectie per dag; "Komende 14 dagen" wordt de Overzicht-kaart `upcoming`; de dagkiezer vervalt omdat de lijst alle dagen toont (filter "Alle dagen" en "Alleen met boekingen", "Naar vandaag") | ja |
| `CashflowBankBlock`, `CashflowPotsBlock`, `CashflowOverviewBlock` | vervallen: ze herhalen Bankrekening en Overzicht (H9) | de links staan op de Overzicht-kaarten |
| `BankBufferBlock` "Bankbuffer" en Instellingen "Buffer op bankrekening" | een veld "Minimumsaldo (maanden aan uitgaven)" op Bankrekening | ja, nu op een plek (E7) |
| `BankHistoryBlock` | Segment Boekingen, rijen met swipe | ja |
| `GoalsPage` met schakelaar Mijn doelen / Spaardoel | Doelen, en Spaardoel berekenen als eigen pagina (`.savingsGoal`) | ja |
| `BufferPage` "Buffer" | Noodbuffer | ja |
| Versnellers in Tools en in elk Doel | pagina Versnellers blijft (Plannen); de sectie in het Doel blijft | ja; beide gebruiken `AcceleratorsSection` |
| Instellingen-sheet en de tandwiel in `PageScaffold` | Tab Instellingen (par. 3) | ja |
| `ChipButton`, `ChipLink`, `ChipGrid`, `ChipLabel` | `ActionButton`, `ActionLink`, `ActionGroup`; acties van een pagina in de werkbalk | ja |
| `RateFetchRow`, `SectionLabel` (dode code), `FirebaseSetupSection` (ontwikkelaarsuitleg) | verwijderd | n.v.t. |
| Ellipsis-menu per rij met een item (Verwijder) | swipe-actie plus contextmenu (`rowActions`) | ja |
| `Meetpunt` (jargon) | "Waarde-update" | ja |

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
| (nieuw) | `.settings(SettingsPage)` | `SettingsDestination(page:)` | `SettingsPage`: `account`, `password`, `deleteAccount`, `conflictBackups`, `calculations`, `prices`, `data`, `layout`, `about` |

`AppTab` wordt `overview, month, saving, planning, settings` (raw values gelijk aan de case-namen; niet bewaard, dus geen migratie). Elke `Destination` heeft een `tab` (eigen tab): income, salary, expenses, distribute, bank, cashflow naar `.month`; pots, pot, portfolio, holding naar `.saving`; goals, goal, savingsGoal, accelerators, buffer, projection, purchase naar `.planning`; `.settings` naar `.settings`; `.overview` naar `.overview`.

**Regels van `Router`** (testbaar, Foundation-only in `NavigationRules`, par. 6 pakket 0B):
- `open(_:)` duwt op het pad van de **huidige** tab (zoals nu; alle bestaande `NavigationLink(value:)` en `router.open` blijven werken). Staat de bestemming al in het pad, dan gaat het pad terug tot die plek in plaats van opnieuw te duwen (lost audit N9 op: Spaarpot, Dag voor dag, Spaarpot kan niet meer eindeloos stapelen).
- `go(_:)` kiest de eigen tab van de bestemming en zet dat pad op `[bestemming]` (bij `.overview` leeg). Gebruiken: zoeken, sneltoetsen, `-mybuddy-open`, meldingen ("Ga naar Account").
- `select(_:)` wisselt alleen van tab; `popToRoot(_:)` maakt een pad leeg.
- Blijft ongewijzigd: `focusMonth`, `periodMode`, `showCurrentMonth(_:)`, `shiftPeriod(_:)`, `resetFocus(to:)`, `orderPage`.
- Verdwijnt: `showSettings`, `homePath`, `savingsPath`, `toolsPath`, `AppTab.symbol(selected:)`.

**Diepe links en debug.** `DebugLaunch` blijft werken: `-mybuddy-tab` kent de nieuwe namen en de oude (home wordt overview, savings wordt month, tools wordt planning); `-mybuddy-open` kent alle bestaande namen plus `salary`, `account`, `password`, `rates`, `prices`, `data`, `layout`, `about`; `-mybuddy-settings` selecteert de tab Instellingen; `-mybuddy-order` accepteert `home`, `savings`, `tools` als alias. `scripts/ci-screenshots.sh` blijft daardoor draaien (G werkt hem bij naar de nieuwe namen).

### 2.7 Volgorde van de blokken: behouden, zichtbaar gemaakt

Gekozen: **behouden** (de gebruiker wilde het), maar de ingang is niet meer alleen lang indrukken. `BlockOrder.swift` (eigenaar 0A) krijgt vier pagina's; de blok-id's staan vast zodat A en de kaarteneigenaars ze kunnen koppelen.

| `BlockPage` (raw value) | Titel | Blok-id's in standaardvolgorde (titel, symbool) |
|---|---|---|
| `overview` | Overzicht | `flow` (Waar gaat je geld heen, `chart.bar.xaxis`), `wealth` (Vermogen, `chart.pie`), `upcoming` (Komende dagen, `calendar.badge.clock`) |
| `month` | Maand | `income` (Inkomen, `eurosign.circle`), `expenses` (Uitgaven, `creditcard`), `distribute` (Verdelen, `square.split.2x2`), `bank` (Bankrekening, `building.columns`), `days` (Dag voor dag, `list.bullet.rectangle`) |
| `saving` | Sparen | `pots` (Spaarpotten, `tray.full`), `portfolio` (Beleggingen, `chart.line.uptrend.xyaxis`) |
| `planning` | Plannen | `goals` (Doelen, `flag.checkered`), `buffer` (Noodbuffer, `shield.lefthalf.filled`), `accelerators` (Versnellers, `bolt`), `projection` (Toekomstschatting, `calendar.badge.clock`), `purchase` (Aankoopcheck, `cart`) |

De kern van een pagina (de hero op het Overzicht, de `MonthBar`) staat vast bovenaan en is niet verplaatsbaar. Ingangen: (1) menu in de werkbalk van elke tabroot, "Volgorde aanpassen…" (opent het korte blad `BlockOrderSheet`); (2) Instellingen, Indeling (`BlockOrderList` per pagina, direct in een pagina); (3) het contextmenu op een kaart blijft. De opgeslagen volgordes onder de oude sleutels `home`, `savings`, `tools` in `AppSettings.blockOrder` blijven staan en worden genegeerd (onbekende sleutels en blok-id's worden al overgeslagen, `BlockOrder.swift:65-78`); geen migratie nodig.

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

Hoofdlettergebruik: zinshoofdletter overal, geen HOOFDLETTERS in de UI (MNU-5, LST-2). Knoppen met een werkwoord: "Toevoegen", "Bewaar", "Annuleer". Op de Mac "klik", op iOS "tik" (WRT-1).

### 2.9 Zoeken

`.searchable(text:prompt: "Zoek in MyBuddy")` op het Overzicht (A). Resultaten uit een vaste index van pagina's met alternatieve namen (Uitgaven, Dag voor dag, Noodbuffer, Rente, Back-up, Wachtwoord, Salaris, Koersen, Account) en uit de namen van spaarpotten, beleggingen, doelen en regels van inkomen en uitgaven. Een resultaat opent met `router.go(...)`. Geen treffers: `ContentUnavailableView.search`. Zo vindt iemand een onderdeel ook als hij de naam niet meer weet (audit 4.7; SRC-1 t/m SRC-3).

### 2.10 Taken in tikken (vanaf een willekeurige plek; tabwissel telt als tik)

| Taak | Nu | Straks |
|---|---|---|
| Instellingen openen | 1, alleen op een tabwortel | **1, overal** |
| Uitgave toevoegen | 4 en veel scrollen | **3**: Maand, Uitgaven, `+` |
| Dag voor dag bekijken | 3 | **2**: Maand, Dag voor dag |
| Nieuwe spaarpot | 3 | **2**: Sparen, `+` |
| Spaarpot storten | 3 | **3**: Sparen, pot, Storten |
| Saldo invullen | 3 | **3**: Maand, Bankrekening, Saldo invullen |
| Spaardoel berekenen | 3 | **2**: Plannen, Spaardoel berekenen |
| Wachtwoord wijzigen | 3 en een sheet | **3**: Instellingen, Account, Wachtwoord wijzigen (pagina) |
| Back-up maken | 2 en scrollen | **3** zonder scrollen: Instellingen, Gegevens, Back-up maken |
| Salaris wijzigen | 2 | **3**: Maand, Inkomen, Salaris instellen (bewust: vaker gebruikt is "deze maand bekijken" en "inkomsten toevoegen", beide 2 tikken; in de lege start 1 tik) |
| Volgorde aanpassen | lang indrukken | **2**: menu in de werkbalk, of Instellingen, Indeling |

## 3. Instellingen: een hele pagina, het account los

### 3.1 Opbouw (tab Instellingen, `SettingsView`)

Een `List` (insetGrouped) zoals de iOS-instellingen: vier secties, zes rijen, elke rij een `NavigationLink` met een korte waarde eronder. Geen sheet, geen "Klaar"-knop, grote titel "Instellingen".

```
Instellingen
 [1] Account                    > Account                 e-mail of naam, daaronder: Gesynchroniseerd om 14:02
 [2] Rekenen                    > Rekenen                 Inflatie 2%, spaarrente 2%
     Koersen                    > Koersen                 Automatisch, laatst bijgewerkt 9:41
 [3] Gegevens                   > Gegevens                Back-up, importeren, exporteren
     Indeling                   > Indeling                Volgorde van de blokken
 [4] Over MyBuddy               > Over                    Versie 1.0
```

De Account-rij staat bovenaan en is de enige rij met een `SymbolBadge` van 40 pt (`person.crop.circle`). Heeft de synchronisatie aandacht nodig (conflict, lokale gegevens uploaden), dan staat daar "Actie nodig" in `Theme.warning` met symbool `exclamationmark.triangle.fill`. Zonder Firebase-sleutel staat er "Alleen op dit apparaat".

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
| Importoverzicht (sheet in sheet, `SpreadsheetImportSheet`) | pagina op de stapel `SpreadsheetImportPage`, geduwd vanuit Gegevens | `BackupUI.swift:586-817` |
| Voorbeelddata laden, Alles wissen, opslagfout | Gegevens, sectie Beheer (onderaan, rood, met cloudwaarschuwing in de dialoog); voorbeelddata staat ook in de lege staat van het Overzicht | `SettingsView.swift:77-93` |
| Over: versie (vast "1.0"), disclaimer | Over MyBuddy: versie uit de bundel, disclaimer, "Bronnen en privacy" (Yahoo Finance, Stooq, CoinGecko, Wereldbank, ECB, Firebase) | `SettingsView.swift:95-104` |
| Volgorde van de blokken (alleen lang indrukken) | Indeling, per tabpagina een lijst met slepen en "Standaardvolgorde" | `BlockOrder.swift:153-165` |
| Tandwiel op de tabwortels | vervalt: Instellingen is een tab | `Components.swift:35-43` |

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

- Zes sheets verdwijnen: Instellingen, Wachtwoord wijzigen (2), Account verwijderen (2), Importoverzicht. `BackupHost` (de zes rijgebonden presentaties) vervalt: op een gewone pagina hangen `fileExporter` en `fileImporter` aan de pagina zelf. Aanbevolen: een `ExportDocument: FileDocument` met dynamisch `contentType`, zodat er een `fileExporter` is in plaats van vier (twee exporters op een view hinderen elkaar).
- Melding "Bestand bewaard" en "Back-up teruggezet": een inline `NoticeBanner` bovenaan de pagina en `sensoryFeedback(.success)`; "Exporteren mislukt": `NoticeBanner` plus `.error`. Alleen wat onomkeerbaar is (Back-up terugzetten, Alles wissen, Account verwijderen, Zet terug) krijgt een `confirmationDialog` aan de knop. `.alert(` komt niet meer voor (ALT-1).
- Synchronisatiemeldingen bij de start ("Lokale gegevens uploaden?", "Welke versie wil je houden?") zijn nu twee alerts aan de wortel (`CloudViews.swift:318-376`, `MyBuddyApp.swift:138`). Straks: **geen alert bij het starten** (ALT-5). `SyncPromptsHost` en `.syncPrompts(_:)` verdwijnen; in plaats daarvan toont `SyncAttentionBanner()` (E, in `CloudViews.swift`) bovenaan het Overzicht een melding "Kies welke versie je houdt" of "Lokale gegevens uploaden?" met een knop "Naar Account" (`router.go(.settings(.account))`); de keuze zelf staat in Account. `sync.deferConflictPrompt()` blijft bestaan voor "Later".
- De pagina's van E zijn pushes op de stapel. Een pagina met een `SpreadsheetImportPage` gebruikt `navigationDestination(item:)`; daarvoor wordt `PendingSpreadsheetImport` `Hashable` op `id`.

### 3.5 macOS en iPad

- **macOS**: naast het zijbalk-item (K3) een `Settings`-scene met Cmd+komma in `#if os(macOS)` (SET-4, MAC-3). Inhoud: een `TabView` met zes panes (Account, Rekenen, Koersen, Gegevens, Indeling, Over), elk `SettingsPane(page:)` met een eigen `NavigationStack`; venstertitel is de naam van de pane; de laatst gebruikte pane wordt onthouden (`@AppStorage("settings.pane")`); vaste breedte ongeveer 520 pt. De scene heeft de store van de actieve sessie nodig: `ActiveSession` (par. 4.4) staat boven de scenes en `SignedInRoot` registreert zijn `AppStore`, `Router` en `SyncController` daarin. Is er niemand ingelogd, dan toont de scene "Log eerst in" (`ContentUnavailableView`).
- **iPad**: hetzelfde als iPhone: tab Instellingen in de zijbalk of de bovenbalk, pagina's als pushes op de stapel. Een toetsenbord geeft Cmd+5 (par. 4.4, commando's); het menu-item "Instellingen" van iPadOS blijft gereserveerd voor de systeeminstellingen (SET-9).
- **Leesbare breedte**: `ListScaffold` begrenst op `Theme.readableWidth` (720 pt) en centreert (LAY-7).

### 3.6 Kleine keuzes in Instellingen

Geen schakelaars voor weergave, taal, haptiek of biometrie (SET-3, ACT-4). Het inlogscherm (`AuthView`) wordt alleen herkleurd en 44 pt gemaakt (A4); zijn logica verandert niet (K4). "Opnamepercentage" blijft als instelling maar met een uitleg van een zin. De waarschuwing "Opslaan is mislukt" staat op het Overzicht (bovenaan, met "Opnieuw proberen") en in Gegevens.

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
- **Maten.** `Theme.cardRadius` 24, `Theme.cardInset` 16, `Theme.tileRadius` = 24 - 16 = 8 (concentrisch), `Theme.pageSpacing` 16, `Theme.sectionSpacing` 24, `Theme.rowSpacing` 12, `Theme.minTapTarget` 44 (vervangt `buttonHeight` 42), `Theme.pageMaxWidth` 960 (kaartenraster), `Theme.readableWidth` 720 (lijsten en formulieren), `Theme.blockColumnMinimum` 340 (twee kolommen op iPad en Mac). Zijmarge van een pagina: `.scenePadding()` in plaats van `.padding(.horizontal, 16)`.
- **Achtergrond.** `Theme.canvas`, een vlak: een lichte olijftint in licht, bijna zwart olijfgroen in donker. De mesh-gradient (`MeshGradient`, negen kleuren, op elke pagina en in negen sheets herhaald) vervalt (DRK-3). Sheets, popovers en bevestigingen krijgen de systeemachtergrond: nergens `.background { ... }` in een sheet, geen `presentationBackground`. De wortel zet `.tint(Theme.accent)`.
- **Kaart.** `Card`: `Theme.card` met `RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)`, geen schaduw, geen glas. Bij `colorSchemeContrast == .increased` een rand van 1 pt in `Color.primary` 35%. Een kaart die naar een pagina leidt is een `NavigationLink` met een eigen `ButtonStyle` met drukstatus (`configuration.isPressed`), geen `.buttonStyle(.plain)` (BTN-1).
- **Wanneer wel glas.** (1) Alles wat het systeem zelf glas geeft: tabbalk (ook zijbalk en bovenbalk van iPad), werkbalk, `Menu`, `confirmationDialog`, sheets, zoekveld. (2) Een tijdelijk bedieningselement boven een grafiek: de annotatie bij `chartXSelection` (via `glassSurface`, met `.regularMaterial` als terugval; GLS-1 maakt hier een uitzondering voor tijdelijke bediening). Dat is alles. Daarom: `glassCard(`, `glassSurface(` en `.glassEffect(` mogen alleen in `Glass.swift` en `Charts.swift` voorkomen. `Glass.swift` blijft bestaan, leest `accessibilityReduceTransparency` (dekkend `Theme.card` in plaats van glas of materiaal), en krijgt `GlassGroup` (een `GlassEffectContainer` met terugval op iOS 18). Knoppen in inhoud: `.bordered`, en voor de ene logische vervolgstap van een pagina `.borderedProminent` met `Theme.accentFill` en `Theme.onAccent` (`ActionButton(prominent: true)`); een prominente knop per scherm (BTN-2). Geen tint op kaarten (`tint: Theme.olive` verdwijnt, 13 plekken).
- **Geen eigen balken.** `barBackdrop` en `.fill(.bar)` verdwijnen; de inhoud scrolt onder de werkbalk en de tabbalk door (LAY-3, TAB-7).

### 4.4 Contract: exacte namen en handtekeningen

De bouwers coderen hierop. Wat hier staat mag niet worden hernoemd; uitbreiden met een parameter met standaardwaarde mag. Een afwijking meldt de bouwer onder **WIRING** in zijn eindrapport.

**A. Navigatie en schil (pakket 0B)**

```swift
// App/Navigation/NavigationModel.swift  (Foundation-only; symlink in CoreTests; tests: NavigationRulesTests)
enum AppTab: String, CaseIterable, Identifiable, Hashable { case overview, month, saving, planning, settings
    var id: String { rawValue }; var title: String; var symbol: String }       // titels en symbolen: par. 2.2
enum SettingsPage: String, CaseIterable, Hashable { case account, password, deleteAccount, conflictBackups,
                                                    calculations, prices, data, layout, about }
enum Destination: Hashable {
    case overview
    case income, salary, expenses, distribute, bank, cashflow
    case pots, pot(UUID), portfolio, holding(UUID)
    case goals, goal(UUID), savingsGoal, accelerators, buffer, projection, purchase
    case settings(SettingsPage)
}
extension Destination { var tab: AppTab }
enum NavigationRules {
    static func push(_ d: Destination, onto path: [Destination]) -> [Destination]   // staat d al in path: kap af erna
    static func go(_ d: Destination) -> (tab: AppTab, path: [Destination])
}

// App/Router.swift
@MainActor @Observable final class Router {
    var tab: AppTab
    var paths: [AppTab: [Destination]]
    var orderPage: BlockPage?
    var focusMonth: YearMonth; var periodMode: PeriodMode                       // ongewijzigd
    func pathBinding(for tab: AppTab) -> Binding<[Destination]>
    func select(_ tab: AppTab)            // alleen wisselen
    func popToRoot(_ tab: AppTab)
    func open(_ d: Destination)           // push op de huidige tab, met NavigationRules.push
    func go(_ d: Destination)             // eigen tab van d, pad = [d]
    func showCurrentMonth(_ current: YearMonth); func shiftPeriod(_ direction: Int); func resetFocus(to current: YearMonth)
}
extension Destination { var domain: AppDomain }                                  // in Router.swift

struct TabStack<Root: View>: View { init(_ tab: AppTab, @ViewBuilder root: () -> Root) }  // NavigationStack(path:) + navigationDestination(for: Destination.self)
@MainActor @Observable final class ActiveSession { var store: AppStore?; var router: Router?; var sync: SyncController?
    func register(store: AppStore, router: Router, sync: SyncController?); func clear() }
struct DestinationView: View { let destination: Destination }                   // koppelt aan de paginanamen van de tabel in "D"
func chartMonths(mode: PeriodMode, focus: YearMonth) -> [YearMonth]              // blijft in DestinationView.swift
```

**B. Ontwerpsysteem (pakket 0A)**: `Theme.swift`, `Components.swift`, `Fields.swift`, `Glass.swift`, `BlockOrder.swift`, nieuwe `Layout.swift`, `Motion.swift`, `RowActions.swift`

```swift
extension Color { init(hex: UInt32, opacity: Double = 1); init(light: Color, dark: Color)
                  init(light: Color, dark: Color, lightContrast: Color, darkContrast: Color) }   // hex alleen in Theme.swift
enum AppDomain: String, CaseIterable, Identifiable { case overview, money, saving, investing, goals, tools, settings
    var title: String; var symbol: String; var color: Color }
enum Theme {  // nieuw
    static let canvas, card, tileFill, textSecondary, accent, accentFill, onAccent, positive, negative, warning: Color
    static let chartExpenses, chartVariable, chartSaved, chartInvested, chartFree: Color
    static let palette: [Color]; static func color(_ index: Int) -> Color; static let potSymbols: [String]
    static let heroAmount: Font, titleAmount: Font
    static let cardRadius, cardInset, minTapTarget, pageSpacing, sectionSpacing, rowSpacing, pageMaxWidth, readableWidth, blockColumnMinimum: CGFloat
    static var tileRadius: CGFloat; static var blockColumns: [GridItem]
    static let motion: Animation, quickMotion: Animation
    // compat tot pakket G: olive, oliveDeep, oliveLight, flowExpenses, flowVariable, flowSaved, flowInvested, flowFree (= chart*),
    //   buttonHeight (= 44), chipRadius, MeshBackground() (tekent canvas)
}
// Pagina's en kaarten
struct PageScaffold<Content: View>: View { init(title: String, large: Bool = false, showsSettings: Bool = false /* verouderd, doet niets */, @ViewBuilder content: () -> Content) }
struct ListScaffold<Content: View>: View { init(title: String, large: Bool = false, @ViewBuilder content: () -> Content) }
struct Card<Content: View>: View { init(title: String? = nil, symbol: String? = nil, domain: AppDomain? = nil, subtitle: String? = nil, headerLink: Destination? = nil, @ViewBuilder content: () -> Content) }
struct LinkCard<Content: View>: View { init(title: String, symbol: String? = nil, domain: AppDomain? = nil, subtitle: String? = nil, destination: Destination, showsCurrentMonth: Bool = false, @ViewBuilder content: () -> Content) }
struct SectionHeader: View { init(_ title: String, symbol: String? = nil, domain: AppDomain? = nil) }          // kop in een List, isHeader
struct NavigationRow: View { init(title: String, symbol: String? = nil, domain: AppDomain? = nil, value: String? = nil, subtitle: String? = nil, destination: Destination) }
// Cijfers
struct BigAmount: View { init(value: Double, font: Font = Theme.heroAmount, color: Color = .primary, label: String? = nil) }
struct StatTile: View { init(title: String, value: String, color: Color = .primary, caption: String? = nil) }
struct FigureRow<Content: View>: View { init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) }         // StatTiles naast elkaar of gestapeld
struct AmountRow: View { init(title: String, value: String, detail: String? = nil, color: Color = .primary, symbol: String? = nil, bold: Bool = false) }
struct SymbolBadge: View { init(symbol: String, color: Color, size: CGFloat = 40) }
// Knoppen en meldingen
struct IconButton: View { init(_ label: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) }  // 44x44, accessibilityLabel, .help(label)
struct ActionButton: View { init(title: String, symbol: String? = nil, role: ButtonRole? = nil, prominent: Bool = false, action: @escaping () -> Void) }
struct ActionLink: View { init(title: String, symbol: String? = nil, destination: Destination, prominent: Bool = false) }
struct ActionGroup<Content: View>: View { init(@ViewBuilder content: () -> Content) }                                // knoppen naast of onder elkaar
struct EmptyHint: View { enum Style { case inline, page }
    init(symbol: String, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil, style: Style = .inline) }
struct NoticeBanner: View { init(text: String, symbol: String = "info.circle.fill", actionTitle: String? = nil, action: (() -> Void)? = nil) }   // verhuisd uit HomeView.swift
// Periode
struct MonthBar: View { init(month: Binding<YearMonth>? = nil) }                  // zonder binding: router.focusMonth met MonthWindow-grenzen
struct MonthStepper, PeriodControl, EqualSizeGrid, MonthWindow, accountPrefsID(...)   // API ongewijzigd
// Modifiers
extension View {
    func animated<V: Equatable>(by value: V, quick: Bool = false) -> some View      // .animation met Reduce Motion (Motion.swift)
    func rowActions(edit: (() -> Void)? = nil, delete: (() -> Void)? = nil, extra: [RowAction] = []) -> some View   // swipeActions + contextMenu
    func blockOrderToolbar(page: BlockPage) -> some View                               // menu "Volgorde aanpassen…"
}
struct RowAction: Identifiable { init(_ title: String, symbol: String, role: ButtonRole? = nil, tint: Color? = nil, action: @escaping () -> Void) }
// Formulieren (Fields.swift): NumberRow, IntStepperRow, OptionalNumberRow, OptionalDateRow, ChoiceRow, ContributionFields, ColorChoiceRow, SymbolChoiceRow: API ongewijzigd
struct SheetScaffold<Content: View>: View { init(title: String, saveTitle: String = "Bewaar", canSave: Bool = true, hasChanges: Bool = false, onSave: @escaping () -> Void, saveChoices: SaveChoices? = nil, @ViewBuilder content: () -> Content) }
// Blokvolgorde (BlockOrder.swift)
enum BlockPage: String, CaseIterable, Identifiable { case overview, month, saving, planning }   // blok-id's: par. 2.7
struct OrderedBlocks<Content: View>: View { init(page: BlockPage, @ViewBuilder content: @escaping (String) -> Content) }
struct BlockOrderList: View { init(page: BlockPage) }   // List in bewerkmodus, ook voor Instellingen, Indeling
struct BlockOrderSheet: View { init(page: BlockPage) }  // kort blad, opent met router.orderPage
```

**C. Grafieken (pakket F)**: `App/UI/ChartModels.swift` (Foundation-only) en `App/UI/Charts.swift`

```swift
enum ChartSize { case compact, regular, tall }          // 96, 180, 240 pt (CHT-11)
struct TrendChart: View { init(model: TrendModel, size: ChartSize = .regular, showsAxes: Bool = true, nonNegative: Bool = false, onAction: @escaping (ChartEmpty.Action) -> Void = { _ in }) }
struct StackedBarChart: View { init(model: StackedBarModel, size: ChartSize = .regular, showsAxes: Bool = true) }
struct DonutChart: View { init(model: DonutModel, size: ChartSize = .regular) }
struct ProgressMeter: View { enum Style { case bar(height: CGFloat = 8), ring(lineWidth: CGFloat = 7) }
    init(value: Double?, tint: Color, style: Style, label: String, valueText: String) }   // nil tekent niets
struct SegmentedMeter: View { struct Segment: Identifiable { let id: String; let title: String; let value: Double; let color: Color }
    init(segments: [Segment], label: String, valueText: String) }
extension HoldingKind { var colorIndex: Int }
// Modelbouwers (Foundation-only); elk geeft altijd een model met `summary`, en `empty != nil` bij te weinig gegevens
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
Elk model heeft altijd een `summary` (VoiceOver) en een `empty` zodra er minder dan twee punten zijn. De typen komen uit bestaande Core-bestanden (`CurvePoint`, `BufferResult`, `SavingsGoalPlan`, `GoalCurves`, `DayChartItem`, `PricePoint`); wijzigt F een parameter, dan meldt F dat meteen onder WIRING aan de pagina-eigenaar (D, B2, C). Afwijking van charts.md 6.2: `height:` is vervangen door `size: ChartSize`; `PortfolioTrend.model` krijgt `only:` voor de detailpagina en `derived:` vervalt omdat `isEstimated` uit Core komt (C2).

**D. Paginanamen en kaarten die eigenaren moeten behouden** (A en 0B coderen hierop)

| Eigenaar | Symbool | Handtekening |
|---|---|---|
| A | tabroots | `OverviewTab()`, `MonthTab()`, `SavingTab()`, `PlanningTab()` (alleen inhoud, zonder `NavigationStack`) |
| B1 | pagina's | `IncomePage()`, `SalaryPage()`, `ExpensesPage()`, `DistributePage()` |
| B1 | blad | `MoneyLineSheet(line: MoneyLine?, kind: FinanceData.LineKind, month: YearMonth, defaultExpenseKind: ExpenseKind)` (ongewijzigd; B2 gebruikt hem) |
| B2 | pagina | `BankPage(section: BankSection = .balance)`, `enum BankSection: String, CaseIterable, Identifiable { case balance, days, entries }` |
| B2 | kaart | `UpcomingDaysCard()` |
| C | pagina's | `PotsPage()`, `PotDetailPage(potID: UUID)`, `PortfolioPage()`, `HoldingDetailPage(holdingID: UUID)` |
| C | kaarten | `PotsSummaryCard()`, `PortfolioSummaryCard()` |
| C | overig | `PotEditSheet(pot: Pot?)`, `HoldingEditSheet(holding: Holding?)`, `GainLabel(gain: Double, fraction: Double?)` |
| D | pagina's | `GoalsPage()`, `GoalDetailPage(goalID: UUID)`, `SavingsGoalPage()`, `AcceleratorsPage()`, `BufferPage()`, `ProjectionPage()`, `PurchasePage()` |
| D | kaarten | `GoalsSummaryCard()`, `BufferSummaryCard()`, `AcceleratorsSummaryCard()`, `ProjectionSummaryCard()`, `PurchaseSummaryCard()` |
| E | pagina's | `SettingsView()` (tabroot), `SettingsDestination(page: SettingsPage)`, `SettingsPane(page: SettingsPage)` (Mac, met eigen `NavigationStack`), `AuthView()` |
| E | melding | `SyncAttentionBanner()` |

Alle `*Card`-views hebben een lege `init()`, lezen hun gegevens zelf uit `AppStore` en `Router` en bevatten hun eigen sheets en lege staat. Alle pagina's lezen `store` en `router` uit de environment.

### 4.5 Componenten: oud naar nieuw

| Oud (`Components.swift` e.a.) | Nieuw | Wat verandert | Compat |
|---|---|---|---|
| `PageScaffold(title:showsSettings:)` | `PageScaffold(title:large:)` | ScrollView op `Theme.canvas`, geen mesh, geen paginabrede `.animation`, `.scenePadding()`, titel `.inline` tenzij `large`, geen tandwiel; DEBUG-scrolloffset blijft | `showsSettings` bestaat nog en doet niets |
| (nieuw) | `ListScaffold(title:large:)` | `List` (iOS `.insetGrouped`, macOS `.inset`), `scrollContentBackground(.hidden)` op `canvas`, `readableWidth` | n.v.t. |
| `GlassBlock` (92x) | `Card` | geen glas; kaartkleur; kop is `isHeader`; `tint` en `interactive` vervallen | `GlassBlock(title:symbol:subtitle:headerLink:showsChevron:interactive:tint:content:)` stuurt door naar `Card` |
| `LinkedBlock` (12x) | `LinkCard` | `NavigationLink` met drukstatus | `LinkedBlock(...)` stuurt door |
| `SectionLabel` (dode code) | `SectionHeader` | geen hoofdletters | verwijderd |
| `StatTile` (85x) | `StatTile` | titel wrapt (2 regels), bedrag `.callout` semibold met cijferuitlijning, `caption` in `.footnote`, `accessibilityElement(.combine)` | zelfde API |
| (HStack of `LazyVGrid` van 3 tegels) | `FigureRow` | stapelt bij AX-formaten en smalle breedte | n.v.t. |
| `BigAmount(value:font:color:)` | `BigAmount(value:font:color:label:)` | tekststijl, `monospacedDigit`, enige plek met `minimumScaleFactor`, VoiceOver-label met "euro" | zelfde API (`font:` met oude `.rounded`-waarden werkt nog maar moet weg) |
| `ChipButton(title:symbol:role:action:)` (77x), `ChipLink` (6x), `ChipLabel` (3x), `ChipGrid` | `ActionButton`, `ActionLink`, `ActionGroup` | systeem `.bordered` of eigen prominente stijl, 44 pt, drukstatus, tekst wrapt, `controlSize(.large)` | `Chip*` bestaan nog, sturen door |
| (kale `Image` in `Button`) | `IconButton` | 44x44, verplicht label, `.help` | n.v.t. |
| `EmptyHint(symbol:title:message:actionTitle:action:)` (14x) | `EmptyHint` met `style` | `.page` is een `ContentUnavailableView`, `.inline` (standaard) een compacte versie binnen een kaart | zelfde API |
| `NoticeBanner` (in `HomeView.swift`) | `NoticeBanner` in `Components.swift` | `Theme.card`, `Label`, `ActionButton` | verhuisd (par. 6.6) |
| `ProgressBar`, `ProgressRing` (14 plekken), `SegmentBar` (1) | `ProgressMeter`, `SegmentedMeter` (pakket F) | label en waarde voor VoiceOver, `nil` is "geen doel", `0,5%` niet meer als 8 pt | `ProgressBar(progress:tint:height:)` en `ProgressRing(progress:tint:lineWidth:)` in `Components.swift` sturen door naar `ProgressMeter` |
| `SymbolBadge` | `SymbolBadge` | schaalt met `@ScaledMetric`, geen `.font(.system(size:))` | zelfde API |
| `MonthStepper`, `PeriodControl`, `StepButton` | idem | 44 pt, kleur uit `textSecondary`, `Verwacht` met woord | zelfde API |
| `MonthPickerBlock` (`SavingsPages.swift:183`) | `MonthBar` | geen glaskaart | `MonthPickerBlock` verwijderd door B1, B2 gebruikt `MonthBar` |
| `EqualSizeGrid` | idem | ongewijzigd | zelfde |
| `MeshBackground` | `Theme.canvas` | vlak | `MeshBackground()` tekent het canvas; weg in G |
| `GlassTabBar`, `barBackdrop` | `TabView` | zie par. 2.1 | verwijderd door 0B |
| `Theme.flow*` | `Theme.chart*` | par. 4.2 | alias tot G |
| `.animation(Theme.motion, value:)` (62x) | `.animated(by:)` | respecteert Verlaag beweging | `Theme.motion` blijft bestaan |
| `NumberRow` | `NumberRow` | label wrapt, `minHeight` 44, `.submitLabel(.next)`, `accessibilityLabel`, eenheid met `textSecondary` | zelfde API |
| `IntStepperRow`, `OptionalNumberRow`, `OptionalDateRow`, `ChoiceRow` | idem | 44 pt, `textSecondary`, `tile()` op ChoiceRow blijft | zelfde API |
| `SheetScaffold` | `SheetScaffold` + `hasChanges` | geen mesh; `interactiveDismissDisabled(hasChanges)` met bevestiging ("Bewaar", "Gooi weg", "Verder bewerken"); `presentationSizing(.form)` (iOS 18, macOS 15); `.success`-haptiek bij Bewaar; Return bewaart | `hasChanges` heeft een standaardwaarde |
| `ColorChoiceRow`, `SymbolChoiceRow` | idem | 44 pt, namen voor VoiceOver, vinkje in `onAccent` op de kleur | zelfde API |
| `AllocationWarningLabel`, `RoundingNote`, `ContributionSummary` (`MoneyViews.swift`) | idem | herkleurd, geen `caption2` | zelfde API |
| `glassCard`, `glassSurface`, `glassButton`, `.tile()` (`Glass.swift`) | `glassSurface` en `glassButton` blijven, `glassCard` vervalt voor inhoud; `.tile()` blijft | zie par. 4.3 | `glassCard` bestaat tot G |

### 4.6 Gedragsregels voor alle bouwers

- **Beweging.** Animaties alleen op concrete waarden via `.animated(by:)`. Geen `.animation(...)` op een hele pagina. Overgangen met schaal of blur zijn verboden; fade volstaat. `MOT-5`: verandert een grafiek met animatie, dan verandert ook zijn samenvatting.
- **Haptiek.** `sensoryFeedback(.success, trigger:)` na Bewaar (zit in `SheetScaffold`), na een geslaagde export, import en synchronisatie; `.error` bij een fout; `.warning` bij een bevestiging die verwijdert; `.selection` bij wisselen van periode of segment. Nooit als enige feedback, nooit een eigen aan/uit.
- **Rij-acties.** Elke bewerkbare rij is een rij in een `List` met `rowActions(edit:delete:extra:)`: swipe (verwijder rood, daarna bewerken) en hetzelfde in het contextmenu, destructief laatst (LST-3, LST-8). Het bevestigingsgedrag van een verwijdering blijft zoals nu (een `confirmationDialog` aan de rij of knop waar dat al zo is, bijvoorbeeld bij een pot, een belegging, een doel en een terugkerende regel); alleen de ingang wisselt. "Maak ongedaan" staat onder "Niet in deze ronde".
- **Toegankelijkheid.** Elke kaartkop en sectiekop is een kop. Elk getal met titel is een element (`.combine`) met label "Over: 1.250 euro". Elke pictogramknop is een `IconButton` (label verplicht). Elke grafiek heeft titel, samenvatting en lege staat (par. 5). Elke `NavigationLink`-rij is een element. `accessibilityInputLabels` bij lange of dubbele knoplabels.
- **Platform.** Geen `UIDevice` of `userInterfaceIdiom`; gebruik `horizontalSizeClass` of `ViewThatFits`. `#if os(iOS)` om `keyboardType`, `navigationBarTitleDisplayMode` (liever `toolbarTitleDisplayMode`), `hoverEffect`. `.help(...)` bij elk pictogram (zit in `IconButton`). `.hoverEffect(.highlight)` op eigen aanklikbare kaarten (iOS, `#if os(iOS)`).
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

### 5.3 De gedeelde grafieklaag (pakket F)

Twee lagen, zodat de logica testbaar is zonder SwiftUI:

1. `App/UI/ChartModels.swift` (Foundation-only, symlink in `CoreTests` zoals `CashflowDisplay.swift`): `ChartPoint` (soorten `actual`, `estimated`, `projected`), `ChartLine`, `ChartMarker`, `ChartEmpty` (symbool, titel, uitleg, actie), `TrendModel`, `DonutModel`, `StackedBarModel`, `ChartAxis` (`domain` altijd `lo < hi` en eindig, `ticks`, `yLabels` nooit twee gelijke naburige labels, `monthLabel`, `monthStride`, `downsample` houdt eerste en laatste punt), `ChartText` (bedragen voor VoiceOver), `PortfolioWindow`, en de modelbouwers uit par. 4.4 C. Startpunt: de code in `charts-prototype.md` B3 (gecompileerd en gedraaid) en B4 (SwiftUI-schets, alleen syntaxis gecontroleerd).
2. `App/UI/Charts.swift` (SwiftUI): `TrendChart`, `StackedBarChart`, `DonutChart`, `ProgressMeter`, `SegmentedMeter`, `ChartEmptyView`. Ze lezen alleen het model en tekenen zelf de assen.

Conventies (uit `charts.md` 6.4, hier bindend voor alle grafieken):

| Onderwerp | Regel |
|---|---|
| Hoogtes | `.compact` 96 pt (Overzicht, Sparen), `.regular` 180, `.tall` 240 (hoofdgrafiek van een pagina); nu 90 tot 210 verspreid |
| x-as | altijd zelf aangestuurd: maanden met `monthStride`, korte Nederlandse maand uit `Fmt.shortMonth`, januari met jaartal; dagen met `DayText.short`; Toekomstschatting verstreken tijd in de gekozen eenheid |
| y-as | eigen ticks en unieke labels, `Fmt.compact` alleen als dat unieke labels geeft; centen bij tickafstand onder 1 euro |
| Domein | altijd vast (`ChartAxis.domain`, 8% ruimte, bij een vlakke reeks 5% of minstens 1 euro), `includeZero` voor staven en voortgang, `nonNegative` voor beleggingen en potten |
| Soorten punten | werkelijk: volle lijn met vlak; afgeleid: dunne lijn met korte stippen, geen vlak, met uitleg erbij; verwacht: gestreepte lijn; een enkel werkelijk punt: een stip met tekst |
| Niet alleen kleur | meer dan een lijn: lijnstijl (vol, gestreept, gestippeld) en bij `accessibilityDifferentiateWithoutColor` een symbool en een label aan het laatste punt; staven: vaste volgorde, inkomenslijn als `RuleMark`, bedragen als tekst na een tik; markeringen hebben een tekst |
| Lege staat | `model.empty != nil` toont een `ContentUnavailableView` op dezelfde hoogte als de grafiek (geen sprong); `.compact`: een regel. Nul punten is nooit een lege `Chart`; een punt is een stip met uitleg; pas vanaf twee punten een lijn |
| Toegankelijkheid | `.accessibilityChartDescriptor` (titel, `summary`, elk punt) op `TrendChart`, `StackedBarChart`, `DonutChart`; meters: `accessibilityElement(.ignore)` met label en waarde; zichtbaar onderschrift met de kernwaarde (CHT-6) |
| Beweging | `accessibilityReduceMotion` leest elke component; een grafiek die met animatie verandert, verandert ook zijn samenvatting |
| Kleuren | alleen `Theme.chart*`, `Theme.accent`, `Theme.negative`, `Theme.color(_:)` (par. 4.2); geen eigen kleuren per grafiek; geen eigen achtergrond (geen glas op glas) |
| Interactie | optioneel `chartXSelection` (iOS 17, macOS 14) met `RuleMark` en een glazen annotatie (par. 4.3); alles daarin staat ook zonder interactie als tekst |

### 5.4 Per grafiek: fix en wie hem aansluit

De component en het model komen van F (golf 0); de pagina-eigenaar sluit ze in golf 1 aan in zijn eigen bestand en verwijdert het oude grafiektype.

| ID | Grafiek | Gebrek | Fix | Aansluiten |
|---|---|---|---|---|
| G1 | Beleggingen, Groei | geen punten zonder meetpunt, onjuiste tekst, keuzebalk doet niets, geen "Ingelegd" | C1 t/m C5; `TrendChart(PortfolioTrend.model(...), size: .tall, nonNegative: true)`; keuzebalk alleen met `PortfolioWindow.options`; tweede lijn "Ingelegd" (dunne volle lijn in `textSecondary`); "Geschat" bij `isEstimated` | C (`PortfolioPages.swift`) |
| G2 | Verdeling | blok weg bij een soort, kleur per rangorde | `DonutChart(DonutModel.holdingKinds(...))` ook bij een soort, kleur per soort, lijst met bedrag en percentage | C |
| G3 | Koers laatste jaar | dubbele y-labels, oude koers blijft staan | `PriceTrend` met unieke labels, `history = []` bij elke ticker, laad- en foutstaat met "Probeer opnieuw" | C |
| G4 | Belegging, Waarde | blok verdwijnt zonder uitleg | segment Koers / Waarde in een blok, `PortfolioTrend.model(only:)` | C |
| G5 | Home en Savings, lijntje | lege vlakte | `PortfolioSummaryCard`: `TrendChart(size: .compact, showsAxes: false)` met begin- en eindwaarde als tekst; lege staat in een regel | C |
| G6 | Per maand (3 plekken) | lege staven vóór de start, tekort onzichtbaar, alleen kleur | een `StackedBarChart(StackedBarModel.months(...))` op het Overzicht (`flow`) | A |
| G7 | Vermogen | jaarmodus springt van 0 naar 15.964, banksaldo onbekend telt als 0 | `NetWorthTrend` (maanden vóór `startMonth` weg, noot zonder banksaldo, C7) | A |
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

- **Eigendom.** Elk bestand in `App/`, `Tests/` en `CoreTests/` heeft precies een eigenaar (tabel 6.7). Je wijzigt alleen je eigen bestanden. Moet er iets in een bestand van een ander veranderen: zet het onder **WIRING** in je eindrapport (zoals `docs/v3-spec.md`) en doe het niet zelf. Uitzondering: pakket G in de laatste golf.
- **Nieuwe bestanden** zijn van het pakket dat ze maakt, in de eigen map (tabel 6.1a). Je mag je eigen bestanden splitsen, hernoemen en verplaatsen; het Xcode-project komt uit XcodeGen (`path: App`), dus er is geen projectbestand om aan te passen. Geen nieuwe pakketten of dependencies.
- **Compat.** Tijdens golf 1 bestaan de oude namen nog (par. 4.5). Elke eigenaar migreert zijn eigen bestanden volledig naar de nieuwe namen; de controle in par. 7 meet dat.
- **Contract.** Par. 4.4 is bindend. Elke aanroep naar een symbool uit een ander bestand vergelijk je letterlijk met de definitie (naam, labels, volgorde, typen, optionals), zoals in `docs/v3-spec.md`. SwiftUI kan hier niet compileren; dat is de enige controle.
- **Taal en stijl.** Nederlands, "je", kort, termenlijst par. 2.8. Commentaar Nederlands. `@Observable`, Swift 5-modus, iOS 18 en macOS 15, iOS 26-API's alleen achter `#available`. Elk nieuw `Codable`-veld met `decodeIfPresent`.
- **Alle functies blijven** (par. 2.5 en 3.2). Verdwijnt een scherm, dan gaat de functie naar de plek uit de tabel; wat niet kan, meld je.
- **Geen git-commando's** behalve lezende, tot G de oplevering regelt.
- **Eindrapport** (korte tekst): gewijzigde en nieuwe bestanden, de uitvoer van `scripts/design-checks.sh <je bestanden>`, `check_swift`-resultaat per bestand, tests, WIRING, en wat je niet kon vaststellen.

Controlecommando's (voor elk Swift-bestand dat je aanraakt):

```
export PATH=/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin:$PATH
P=/tmp/claude-0/-home-user-MyBuddy/9beb118c-8e88-5a84-a4b5-426733aaf64d/scratchpad
$P/venv/bin/python $P/check_swift.py App/Pages/<bestand>.swift                  # 0 foutknopen
cd /home/user/MyBuddy && scripts/design-checks.sh App/Pages/<bestand>.swift     # par. 7
cd CoreTests && swift test --scratch-path /tmp/sb-<naam>                         # alleen als je Core of een Foundation-only UI-bestand raakt
```

**6.1a Mappen voor nieuwe bestanden**

| Pakket | Map |
|---|---|
| 0A | `App/UI/` (`Layout.swift`, `Motion.swift`, `RowActions.swift`, `ComponentGallery.swift`), `scripts/design-checks.sh` |
| 0B | `App/Navigation/` (`NavigationModel.swift`, `ActiveSession.swift`, `AppCommands.swift`, `SettingsScene.swift`), `CoreTests/.../NavigationModel.swift` (symlink) en `NavigationRulesTests.swift` |
| F | `App/UI/ChartModels.swift`, `CoreTests/.../ChartModels.swift` (symlink) en de testbestanden uit par. 5.5 |
| A | `App/Pages/Tabs/` |
| B1 | `App/Pages/Month/` |
| B2 | `App/Pages/Bank/` |
| C | `App/Pages/Saving/` |
| D | `App/Pages/Planning/` |
| E | `App/Pages/Settings/` |

### 6.2 Golven en afhankelijkheden

```
Golf 0  (3 bouwers tegelijk, geen overlap)      0A Ontwerpsysteem   0B Schil en navigatie   F Grafieken en Core
          poort: contractcontrole (par. 7.1) en swift test groen
Golf 1  (6 bouwers tegelijk, geen overlap)      A  Tabroots          B1 Maand-pagina's        B2 Bankrekening
                                                C  Sparen            D  Plannen               E  Instellingen en account
          poort: elk pakket meldt klaar; contractcontrole voor golf 1
Golf 2  (een bouwer)                            G  Integratie, opruimen compat, documentatie, eindcontrole
```

| Pakket | Hangt af van (alleen namen uit par. 4.4, geen code) | Anderen hangen van hem af voor |
|---|---|---|
| 0A | 0B (`Destination`, `Router`, `BlockPage` blijft bij 0A), F (`ProgressMeter`) | alle pakketten: componenten |
| 0B | 0A (`Theme.accent`), A, B1, B2, C, D, E (paginanamen in `DestinationView`, tabroots in `RootView`) | alle: navigatie |
| F | 0A (`Theme.chart*`, `Theme.accent`, `Theme.color`), B2 (`DayChartItem`, `DayChartRange` blijven in `CashflowDisplay.swift`) | A, B2, C, D: grafieken |
| A | 0A, 0B, F; B2 (`UpcomingDaysCard`), C (`PotsSummaryCard`, `PortfolioSummaryCard`), D (vijf `*SummaryCard`), E (`SyncAttentionBanner`) | 0B (`OverviewTab` e.d.) |
| B1 | 0A, 0B | B2 (`MoneyLineSheet`) |
| B2 | 0A, 0B, F, B1 (`MoneyLineSheet`) | A (`UpcomingDaysCard`), 0B (`BankPage`, `BankSection`) |
| C | 0A, 0B, F | A (kaarten), 0B (pagina's) |
| D | 0A, 0B, F | A (kaarten), 0B (pagina's) |
| E | 0A, 0B | A (`SyncAttentionBanner`), 0B (`SettingsView`, `SettingsDestination`, `SettingsPane`) |

### 6.3 Golf 0

**Pakket 0A: Ontwerpsysteem** (`App/UI/Theme.swift`, `Glass.swift`, `Components.swift`, `Fields.swift`, `MoneyViews.swift`, `BlockOrder.swift`, `App/Assets.xcassets/AccentColor.colorset`)

- *Opdracht.* Implementeer par. 4.1 t/m 4.6 en het contract 4.4 B: alle tokens met exact de hex-waarden uit 4.1 en 4.2 (licht, donker, hoog contrast), `AppDomain`, `PageScaffold`, `ListScaffold`, `Card`, `LinkCard`, `SectionHeader`, `NavigationRow`, `BigAmount`, `StatTile`, `FigureRow`, `AmountRow`, `SymbolBadge`, `IconButton`, `ActionButton`, `ActionLink`, `ActionGroup`, `EmptyHint` (met `style`), `NoticeBanner` (verhuisd), `MonthBar`, `animated(by:)`, `rowActions`, `RowAction`, `blockOrderToolbar`, `SheetScaffold(hasChanges:)`, `BlockPage` met vier pagina's, `BlockOrderList`, `OrderedBlocks`. Maak de compat-laag (par. 4.5, kolom Compat) zodat elke bestaande aanroep in `App/Pages` blijft compileren. `ProgressBar`, `ProgressRing` en `SegmentBar` sturen door naar `ProgressMeter` en `SegmentedMeter` (pakket F). `GlassSurface` leest `accessibilityReduceTransparency`. Werk `AccentColor.colorset` bij met drie appearances. Kopieer `docs/design/design-checks.sh` naar `scripts/design-checks.sh` (uitvoerbaar). Voeg `ComponentGallery.swift` toe (`#if DEBUG`, `#Preview` in licht, donker, hoog contrast en `.accessibility3`).
- *Definitie van klaar.* Elk symbool uit 4.4 B bestaat met exact die handtekening; elke compat-aanroep uit de huidige `App/Pages` compileert nog (controleer met een `grep` van alle aanroepen van `GlassBlock(`, `LinkedBlock(`, `ChipButton(`, `ChipLink(`, `ChipGrid(`, `ProgressBar(`, `ProgressRing(`, `SegmentBar(`, `EmptyHint(`, `StatTile(`, `BigAmount(`, `SymbolBadge(`, `MonthStepper(`, `PeriodControl(`, `SheetScaffold(`, `NumberRow(` tegen je definities); `check_swift` 0 foutknopen op elk eigen bestand; `scripts/design-checks.sh` op je eigen bestanden: alleen de bedoelde compat-definities falen nog (`GlassBlock(`, `Chip*(`, `ProgressBar(`, `MeshBackground`, `glassCard(`); geen `.font(.system(size:`, `caption2`, `.rounded`, `.secondary`, `Color(hex:` buiten `Theme.swift`.
- *Niet aanraken.* `App/Pages/*`, `App/Auth`, `App/Cloud`, `App/UI/Charts.swift`, `App/UI/BackupUI.swift`, `App/UI/MarketDataUI.swift`, `Router.swift`, `RootView.swift`, `MyBuddyApp.swift`.
- *Tests en controles.* Geen Core-tests. De `#Preview`s zijn de handmatige controle. Meld de lijst "oude naam, nieuwe naam" die je hebt gebouwd, als hulp voor golf 1.

**Pakket 0B: Schil en navigatie** (`MyBuddyApp.swift`, `RootView.swift`, `Router.swift`, `AppStore.swift` (alleen lezen), `Pages/DestinationView.swift`, `Debug/DebugLaunch.swift`, nieuw `App/Navigation/*`)

- *Opdracht.* Par. 2.1, 2.2, 2.6 en 3.5, contract 4.4 A. `RootView`: `TabView(selection:)` met vijf `Tab`s, elk `TabStack(tab) { <Root>() }`, `.tabViewStyle(.sidebarAdaptable)`, iOS 26 `.tabBarMinimizeBehavior(.onScrollDown)` achter `#available`, de bestaande `.task`s en `onChange`s (koersen, klok per minuut, maandwissel) blijven; `GlassTabBar`, `barBackdrop`, de toetsenbordmelding, `tabContent` en de `sheet` voor Instellingen verdwijnen; het blad "Volgorde aanpassen" blijft `.sheet(item: $router.orderPage)`. `Router` en `NavigationModel` volgens 4.4 A met de regels uit 2.6. `ActiveSession` (SignedInRoot registreert zich daarin, ook in `DemoSession`). `MyBuddyApp`: `ActiveSession` als `@State`, `.commands { AppCommands(session:) }`, op macOS `Settings { SettingsScene(session:) }` (`TabView` met zes `Tab`s die `SettingsPane(page:)` tonen, laatst gebruikte pane onthouden), venster minimaal 640x560 en standaard 1000x760, `.syncPrompts(sync)` uit `SignedInRoot` halen (E verwijdert de definitie). `AppCommands`: Weergave Cmd+1 t/m Cmd+5 voor de tabs (`router.select`), "Koersen vernieuwen" Cmd+R (`store.refreshPrices(force: true)`), "Back-up maken…" (`router.go(.settings(.data))`); alles uitgeschakeld zonder actieve sessie. `DestinationView` koppelt elke `Destination` aan de paginanamen van 4.4 D (`.cashflow` naar `BankPage(section: .days)`, `.bank` naar `BankPage(section: .balance)`, `.overview` naar `OverviewTab()` als noodgreep, `.settings(let p)` naar `SettingsDestination(page: p)`); `chartMonths` blijft. `DebugLaunch` volgens 2.6.
- *Definitie van klaar.* `grep -rn "GlassTabBar\|barBackdrop\|showSettings\|syncPrompts" App/RootView.swift App/Router.swift App/MyBuddyApp.swift` geeft niets; `NavigationRulesTests` slagen (push zonder dubbele, terugknippen tot de bestaande plek, `go` voor elke `Destination` geeft een tab, `Destination.tab` is totaal over alle cases via een uitputtende `switch`); `swift test` volledig groen; `check_swift` 0 foutknopen; elke `Tab` heeft een Nederlandse titel en een symbool uit 2.2.
- *Niet aanraken.* Alle `Pages` behalve `DestinationView.swift`, alle `UI`, `Auth`, `Cloud`, `Core`.
- *Tests en controles.* `NavigationRulesTests` in `CoreTests` (nieuw, met symlink naar `NavigationModel.swift`). Handmatig: tabwissel behoudt het pad; een diepe link uit `-mybuddy-open` opent op de goede tab.

**Pakket F: Grafieken en Core** (`App/UI/Charts.swift`, nieuw `App/UI/ChartModels.swift`, `App/Core/Invest.swift`, `Overview.swift`, `Pots.swift`, alle overige `App/Core/*` als poortwachter, nieuwe en aangepaste tests in `CoreTests`)

- *Opdracht.* Par. 5.2 (C1 t/m C5, C7 t/m C9; C6 niet), 5.3 en contract 4.4 C. Begin met de code uit `charts-prototype.md` B1 (patch C1), B2 (tests), B3 (modellen) en B4 (componenten); werk die uit tot alle modelbouwers van 4.4 C en vervang de oude grafiekviews in `Charts.swift` (`TimeLineChart`, `FlowChart`, `AllocationDonut`, `TimePoint`, `chartAxes`) door `TrendChart`, `StackedBarChart`, `DonutChart`, `ProgressMeter`, `SegmentedMeter`, `ChartEmptyView`. De oude typen blijven als compat-doorverwijzing staan tot golf 1 klaar is; `BufferChart`, `SavingsGoalChart`, `GoalCurveChart` en `DayBalanceChart` staan in pagina-bestanden en worden door hun eigenaars verwijderd.
- *Definitie van klaar.* Alle symbolen uit 4.4 C bestaan; `PortfolioSeriesDerivedTests` (5) slagen; `HoldingDayTests` aangepast; de tests uit par. 5.5 slagen; **volledige `swift test` groen** (was 1.492 tests; elke andere falende test is een fout, geen wens); `ChartModels.swift` is Foundation-only (symlink in `CoreTests` compileert); `accessibilityChartDescriptor` staat op drie componenten; elke component leest `accessibilityReduceMotion`; `check_swift` 0 foutknopen; geen `Color(hex:`, geen vaste kleuren buiten `Theme`.
- *Niet aanraken.* Alle andere Core-bestanden (de rekenlogica blijft zoals ze is; `Models.swift` blijft: geen nieuw `Codable`-veld), `App/Pages`, de overige `App/UI`.
- *Tests en controles.* `cd CoreTests && swift test --scratch-path /tmp/sb-f`; `PortfolioSeriesDerivedTests` eerst rood tegen HEAD, dan groen. Rapporteer de gemeten testaantallen en welke bestaande test je hebt aangepast en waarom.

### 6.4 Golf 1

**Pakket A: Tabroots** (`App/Pages/HomeView.swift`, `SavingsView.swift`, `ToolsView.swift`, nieuw `App/Pages/Tabs/*`)

- *Opdracht.* Par. 2.2 en 2.4 (tabroots), 2.7, 2.9. Maak `OverviewTab`, `MonthTab`, `SavingTab`, `PlanningTab` (alleen inhoud; de `NavigationStack` komt van `TabStack`). Overzicht: meldingen (`startupNotice`, `saveFailed` met "Opnieuw proberen", `SyncAttentionBanner()`, `CashflowCheckBanner` bij afwijking), de hero "Nog te verdelen" (de logica van `RemainingHeader`: `MonthBoard`, `percentWarning`, notities), de kaarten `flow` (`PeriodControl`, `StackedBarChart(StackedBarModel.months(...))`, de cijfers en twee uitklappers uit de oude pagina Overzicht), `wealth` (`NetWorthTrend`, drie `AmountRow`-links) en `upcoming` (`UpcomingDaysCard()`), de lege start, `.searchable` met de index uit 2.9. Maand: `MonthBar` en vijf `LinkCard`s met het kerncijfer (logica van `IncomeBlock`, `DistributeBlock`, `BankBlock`, plus nieuw Uitgaven en Dag voor dag). Sparen en Plannen: plaats de `*SummaryCard`s van C en D met `OrderedBlocks`. Werkbalk van elke tabroot: `blockOrderToolbar(page:)`. Verwijder `HomeView.swift`, `SavingsView.swift` en `ToolsView.swift` volgens de verhuistabel 6.6.
- *Definitie van klaar.* Elke tabroot is `PageScaffold(title:, large: true)` en gebruikt alleen `Card`, `LinkCard`, `FigureRow`, `AmountRow`, `EmptyHint`; geen `GlassBlock(`, `LinkedBlock(`, `Chip*`, `MeshBackground`, `.secondary`, `caption2`, `.rounded`, vaste lettergroottes; alle namen volgen 2.8; elk getal komt uit dezelfde bron als nu (`MonthBoard`, `periodSummary`, `netWorth`); de volgorde van blokken werkt via `OrderedBlocks` met de id's uit 2.7; `check_swift` en `scripts/design-checks.sh` op de eigen bestanden zonder FAIL.
- *Niet aanraken.* `SettingsView.swift`, alle pagina's van B1, B2, C, D, alle `UI`, `Core`.
- *Tests en controles.* Geen Core-tests (geen nieuwe logica; gebruik `MoneyFigures`). Handmatig: scenario's 1, 2, 7 en 9 uit par. 7.4.

**Pakket B1: Maand-pagina's** (`App/Pages/SavingsPages.swift`, `App/UI/SavingsDisplay.swift`, `App/UI/MoneyFigures.swift`, nieuw `App/Pages/Month/*`)

- *Opdracht.* Par. 2.4 (Inkomen, Salaris, Uitgaven, Verdelen) en 2.8. Bouw `IncomePage`, `SalaryPage` (nieuw), `ExpensesPage` (nieuw), `DistributePage` als `ListScaffold`-pagina's met `MonthBar`, `AmountRow`, rijen met `rowActions` (de ellipsis-menu's van `MoneyLineRow` vervallen), `MoneyLinesSection` in plaats van `MoneyLinesBlock` (een `Section`), "Standaard uitgaven invullen" in het werkbalkmenu en in de lege staat van Uitgaven, "Overschrijfdag" in een `DisclosureGroup`, de drie verdeelacties in het werkbalkmenu. `MoneyLineSheet(line:kind:month:defaultExpenseKind:)` blijft ongewijzigd qua API en krijgt `hasChanges`. Verwijder uit `SavingsPages.swift`: `OverviewPage`, `BreakdownRow`, `DayCheckBlock`, `MonthPickerBlock`, en de hele Bank-groep (`BankAction`, `BankPage`, `BankBalanceBlock`, `BankFlowBlock`, `FlowRow`, `BankTransfersBlock`, `TransferRow`, `BankForecastBlock`, `BankBufferBlock`, `BankHistoryBlock`, `BankActionSheet`; B2 bouwt ze opnieuw). `PotSpendOutlook` en `AllocationRow` blijven. Alle teksten in je bestanden naar de termenlijst, ook `MoneyLabels` in `MoneyFigures.swift` ("Nog te verdelen", "Overgehouden"); wijzigt een label, dan pas je de bijbehorende test aan.
- *Definitie van klaar.* Elke pagina heeft maximaal 6 blokken en de volgorde kern, secties, acties, destructief; de pagina's `.income`, `.salary`, `.expenses`, `.distribute` bestaan onder precies deze namen; `design-checks` zonder FAIL op de eigen bestanden; `check_swift` 0; **de bedragen en rekenregels zijn ongewijzigd** (`MonthFigures`, `MonthBoard`, `AllocationEdit`, `LineSave` ongewijzigd qua gedrag); `swift test` groen.
- *Niet aanraken.* `CashflowPages.swift`, `CashflowDisplay.swift`, alle `Core`, `UI` buiten je eigen drie bestanden.
- *Tests en controles.* Bestaande tests voor je bestanden: `MoneyFiguresTests`, `AllocationEditTests`, `LineSaveTests`, `SalaryScheduleEditTests`; nieuw alleen als je Foundation-only logica toevoegt. Handmatig: scenario's 3, 4 en 5 uit par. 7.4.

**Pakket B2: Bankrekening en Dag voor dag** (`App/Pages/CashflowPages.swift`, `App/UI/CashflowDisplay.swift`, nieuw `App/Pages/Bank/*`)

- *Opdracht.* Par. 2.4 (Bankrekening), 2.5 en 5.4 (G8, G9, G15). Bouw `BankPage(section:)` met `BankSection` en een segmentbalk Saldo, Dag voor dag, Boekingen. *Saldo*: hero met `BigAmount`, "Saldo invullen" en de melding uit `BankLowPointNotice`; **Verwacht verloop** (`TrendChart(BankTrend.model(...))` met lege staat); **Binnen en eruit** (`SegmentedMeter` plus `AmountRow`s, de rijen linken naar Spaarpotten, Beleggingen en Verdelen); **Minimumsaldo** (het veld `bankBufferMonths`, een zin, een link naar Noodbuffer). *Dag voor dag*: de inhoud van `CashflowPage` als `List` met een sectie per dag (`CashflowDayFilter`, "Naar vandaag", `DayEventRow` ongewijzigd qua gedrag), `TrendChart(DayBalanceTrend.model(...))`, `CashflowCheckBanner` alleen bij afwijking; vervallen: `CashflowBankBlock`, `CashflowPotsBlock`, `CashflowOverviewBlock`, `BankDayBlock` (de dagkiezer). *Boekingen*: `BankHistoryBlock` als lijst met swipe. Werkbalkmenu "Geld bewegen" (`BankActionSheet` met de vijf acties, naar de nieuwe namen). `UpcomingDaysCard()` uit `BankUpcomingBlock` en `UpcomingDayRow` voor het Overzicht. Verwijder `BankTransfersBlock` en `TransferRow`; `DayBalanceChart` verdwijnt.
- *Definitie van klaar.* `BankPage(section:)`, `BankSection`, `UpcomingDaysCard()` bestaan met de handtekeningen uit 4.4 D; alle functies uit de oude `BankPage` en `CashflowPage` bereikbaar (par. 2.5); `DayChartItem` en `DayChartRange` ongewijzigd; `design-checks` zonder FAIL, `check_swift` 0; `swift test` groen (`CashflowDisplayTests`).
- *Niet aanraken.* `SavingsPages.swift`, `Core`, andere `UI`.
- *Tests en controles.* `CashflowDisplayTests` en `LedgerConsistencyTests` blijven groen; handmatig scenario's 4, 6 en 8.

**Pakket C: Sparen** (`App/Pages/PotPages.swift`, `PortfolioPages.swift`, `App/UI/PotDisplay.swift`, nieuw `App/Pages/Saving/*`)

- *Opdracht.* Par. 2.4 (Spaarpotten, Spaarpot, Beleggingen, Belegging), 5.4 (G1 t/m G5, G14, G16) en 2.5 (K9). `PotsPage`, `PotDetailPage`, `PortfolioPage`, `HoldingDetailPage` als `ListScaffold`-pagina's met `rowActions`, werkbalk `+` en menu's; `PotsSummaryCard()` en `PortfolioSummaryCard()` voor het tabblad Sparen. Sluit de grafieken aan (`TrendChart`, `DonutChart`, `ProgressMeter`) en verwijder de pot- en beleggingkeuze voor Home (`PotPickerSheet`, `HoldingPickerSheet` zijn al weg uit `HomeView.swift` door A; verwijder hun aanroepen). `HoldingEditSheet`: "Huidige waarde" ook bij een belegging met ticker en bij wijzigen (leeg = koers maal aantal zodra binnen), een ticker zonder aantal krijgt de uitleg "Vul ook het aantal stuks in, anders kan de app de waarde niet uitrekenen"; "Geschat" bij `isEstimated`; `GainLabel` verhuist naar `PortfolioPages.swift`; "Meetpunt" wordt "Waarde-update". Sheets: `PotEditSheet`, `PotEntrySheet`, `HoldingEditSheet`, `ValueUpdateSheet` met `hasChanges`.
- *Definitie van klaar.* De vier pagina's en twee kaarten bestaan met de handtekeningen uit 4.4 D; geen `TimeLineChart`, `AllocationDonut`, `ProgressBar`, `ProgressRing`, `ellipsis.circle`-rijmenu; de Beleggingen-grafiek toont voor elk scenario uit `charts.md` 3.2 (b1, b1c, b2, b3, b3b, b4a, g1, g2) een grafiek of een lege staat met actie, nooit een lege vlakte of de oude voetnoot; `design-checks`, `check_swift`, `swift test` (`PotDisplayTests`) zonder fout.
- *Niet aanraken.* `Invest.swift`, `Pots.swift` en de rest van `Core` (F), andere `Pages`.
- *Tests en controles.* `PotDisplayTests`; handmatig scenario's 10 en 11.

**Pakket D: Plannen** (`App/Pages/GoalPages.swift`, `SavingsGoalPages.swift`, `BufferPages.swift`, `ProjectionPage.swift`, `PurchasePages.swift`, `AcceleratorPages.swift`, nieuw `App/Pages/Planning/*`)

- *Opdracht.* Par. 2.4 (Doelen, Doel, Spaardoel berekenen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck), 2.5 en 5.4 (G10 t/m G14). Vijf kaarten met lege `init()`: `GoalsSummaryCard`, `BufferSummaryCard`, `AcceleratorsSummaryCard` (uit `ToolsView.swift`, met `AcceleratorBadge`), `ProjectionSummaryCard` (uit `ToolsView.swift`), `PurchaseSummaryCard`. `GoalsPage` zonder de schakelaar (`GoalsSection` vervalt; werkbalkmenu Nieuw doel, Spaardoel berekenen, Noodbuffer). Rekenpagina's in de volgorde uitkomst, invoer, details in uitklappers; "Buffer" heet "Noodbuffer"; `AcceleratorsPage` verwijst met `router.open(.goals)` in plaats van `router.toolsPath.append`. Sluit de vier grafieken aan op `TrendChart`; verwijder `BufferChart`, `SavingsGoalChart`, `GoalCurveChart`. De bevestiging van `AcceleratorApplySheet` verdwijnt niet vanzelf na 4 seconden (ACC-8): sluit met een knop. `@AppStorage`-sleutels en `SavingsGoalDraft` blijven ongewijzigd.
- *Definitie van klaar.* Zeven pagina's en vijf kaarten bestaan met de handtekeningen uit 4.4 D; geen eigen `Chart(`, `import Charts`, `TimeLineChart`; elke pagina maximaal 6 blokken; `Theme.warning` niet meer als tekst op een vlak onder contrast; `design-checks`, `check_swift`, `swift test` zonder fout.
- *Niet aanraken.* `Core`, andere `Pages`, `UI`.
- *Tests en controles.* Bestaande `GoalTests`, `BufferTests`, `SavingsGoalTests`, `PurchaseTests`, `GrowthTests`, `Accelerator*Tests` blijven groen; handmatig scenario's 12 en 13.

**Pakket E: Instellingen en account** (`App/Pages/SettingsView.swift`, `App/Auth/*`, `App/Cloud/*`, `App/Config/FirebaseConfig.swift`, `App/UI/BackupUI.swift`, `App/UI/MarketDataUI.swift`, `Tests/AppTests/*`, nieuw `App/Pages/Settings/*`)

- *Opdracht.* Par. 3 volledig. `SettingsView()` (tabroot, vier secties, zes rijen), `SettingsDestination(page:)` voor `.account`, `.password`, `.deleteAccount`, `.conflictBackups`, `.calculations`, `.prices`, `.data`, `.layout`, `.about`, `SettingsPane(page:)` voor de Mac met een eigen `NavigationStack`. Zet de bestaande secties om naar pagina's volgens tabel 3.2: `CloudAccountSection`, `SyncSection`, `AccountSection`, `MarketDataSection`, `BackupSection` worden pagina's of secties daarin; de vier wachtwoord- en verwijderbladen worden pagina's; `SpreadsheetImportSheet` wordt `SpreadsheetImportPage`; `BackupHost` en de alerts vervallen; `SyncPromptsHost` en `.syncPrompts` verdwijnen; `SyncAttentionBanner()` komt erbij; `FirebaseSetupSection`, `RateFetchRow` verdwijnen. Indeling gebruikt `BlockOrderList(page:)` van 0A. `AuthView`: `MeshBackground` en glaskaart weg (systeemachtergrond met `Theme.canvas`, een `Card`), knoppen en tekstlinks 44 pt, ogen 44 pt; de logica en de `AuthStore` blijven ongewijzigd (K4). Versie uit `Bundle.main` (`CFBundleShortVersionString`).
- *Definitie van klaar.* `grep -rn "\.sheet(\|\.alert(\|\.fullScreenCover(" App/Pages/Settings App/Pages/SettingsView.swift App/Auth App/Cloud App/UI/BackupUI.swift App/UI/MarketDataUI.swift` geeft niets; elke functie uit tabel 3.2 is bereikbaar; geen enkele pagina dieper dan drie niveaus (tab, pagina, subpagina); `AppTests` en `CoreTests` groen; `design-checks` en `check_swift` zonder fout; de tekst "Firebase" komt alleen nog voor in de Account-uitleg van een zin en in `FirebaseConfig.swift`.
- *Niet aanraken.* `App/Core/*` (`FirebaseAuthClient`, `CloudSync*`, `AccountPrefs`, `Export`, `ImportMapping`), `SyncController`-logica (alleen views en teksten), andere `Pages`, de componenten in `UI`.
- *Tests en controles.* `Tests/AppTests/*` (AuthTests, CloudTests, SyncControllerTests) onaangetast en groen; handmatig scenario's 14 t/m 17.

### 6.5 Golf 2

**Pakket G: Integratie en eindcontrole** (alle bestanden, maar pas nadat A t/m F klaar zijn; plus `README.md`, `docs/v3-spec.md`, `scripts/*`, `project.yml`, `App/Assets.xcassets/AppIcon.appiconset`, `App/PrivacyInfo.xcprivacy`)

- *Opdracht.* (1) Draai de contractcontrole (7.1) en los naamverschillen op. (2) Verwijder de compat-laag: `GlassBlock`, `LinkedBlock`, `Chip*`, `ProgressBar`, `ProgressRing`, `SegmentBar`, `MeshBackground`, `Theme.flow*`, `Theme.buttonHeight`, `Theme.olive*`, `showsSettings`, `glassCard`, oude grafiektypen; ruim ongebruikte code op. (3) Werk `README.md` (tabellen Tabs, "Home" en "Savings", de zin over de tabbalk, Instellingen), `docs/v3-spec.md` (blok-id's, termen, componenten) en `scripts/ci-screenshots.sh` (nieuwe tabnamen en pagina's, `-mybuddy-settings`) bij. (4) Draai de volledige eindcontrole van par. 7 en lever het eindrapport met alle tellingen. G mag elk bestand aanpassen, maar alleen voor integratiefouten en het opruimen; ontwerpwijzigingen niet.
- *Definitie van klaar.* `scripts/design-checks.sh` zonder een FAIL; `check_swift` 0 foutknopen op alle `.swift`-bestanden in `App/`; `swift test` volledig groen; elke aanroep van een symbool uit 4.4 komt letterlijk overeen met zijn definitie (steekproef: elke aanroep van `Card(`, `LinkCard(`, `ActionButton(`, `ActionLink(`, `TrendChart(`, `ProgressMeter(`, `SheetScaffold(`, `BankPage(`); de handmatige scenario's van 7.2 staan op een rij met "gedaan" of "niet te testen hier".
- *Niet aanraken.* `App/Core` (tenzij een test dat eist), de rekenlogica.

### 6.6 Verhuistabel: typen die van bestand wisselen

De verwijderende eigenaar haalt het type weg, de definiërende eigenaar maakt het. Een type dat "vervalt" wordt door niemand opnieuw gedefinieerd.

| Type | Nu in (eigenaar verwijdert) | Straks in (eigenaar definieert) |
|---|---|---|
| `NoticeBanner` | `HomeView.swift` (A) | `Components.swift` (0A) |
| `GainLabel` | `HomeView.swift` (A) | `PortfolioPages.swift` (C) |
| `MiniFigure`, `FlowLegend`, `PotsTotals`, `PotMiniTile`, `EmptySlotTile`, `HoldingTile`, `PotPickerSheet`, `HoldingPickerSheet`, `WelcomeBlock`, `RemainingHeader`, `OverviewBlock`, `PotsBlock`, `InvestBlock`, `HomeView` | `HomeView.swift` (A) | vervallen; A bouwt hero, kaarten en lege staat in `Tabs/`; C bouwt zijn eigen potten- en beleggingrijen in de `*SummaryCard`s |
| `PeriodBlock`, `IncomeBlock`, `DistributeBlock`, `PotsSummaryBlock`, `BankBlock`, `PortfolioBlock`, `SavingsView` | `SavingsView.swift` (A) | vervallen; A bouwt de Maand-kaarten, C `PotsSummaryCard` en `PortfolioSummaryCard` |
| `ProjectionBlock` | `ToolsView.swift` (A) | `ProjectionPage.swift` als `ProjectionSummaryCard` (D) |
| `AcceleratorsBlock`, `AcceleratorBadge` | `ToolsView.swift` (A) | `AcceleratorPages.swift` als `AcceleratorsSummaryCard`, `AcceleratorBadge` (D) |
| `ToolsView` | `ToolsView.swift` (A) | vervallen |
| `BufferBlock`, `GoalsHubBlock`, `PurchaseBlock` | `BufferPages.swift`, `GoalPages.swift`, `PurchasePages.swift` (D) | zelfde bestanden, hernoemd tot `BufferSummaryCard`, `GoalsSummaryCard`, `PurchaseSummaryCard` (D) |
| `OverviewPage`, `BreakdownRow`, `DayCheckBlock` | `SavingsPages.swift` (B1) | vervallen; A bouwt het Overzicht |
| `MonthPickerBlock` | `SavingsPages.swift` (B1) | `MonthBar` in `Components.swift` (0A) |
| `BankPage`, `BankAction`, `BankBalanceBlock`, `BankFlowBlock`, `FlowRow`, `BankForecastBlock`, `BankBufferBlock`, `BankHistoryBlock`, `BankActionSheet` | `SavingsPages.swift` (B1) | `App/Pages/Bank/` (B2), herbouwd |
| `BankTransfersBlock`, `TransferRow` | `SavingsPages.swift` (B1) | vervallen |
| `BankUpcomingBlock`, `UpcomingDayRow` | `CashflowPages.swift` (B2) | `UpcomingDaysCard` en `UpcomingDayRow` in `App/Pages/Bank/` (B2) |
| `CashflowBankBlock`, `CashflowPotsBlock`, `CashflowOverviewBlock`, `DayBalanceChart`, `BankDayBlock` | `CashflowPages.swift` (B2) | vervallen |
| `BufferChart`, `SavingsGoalChart`, `GoalCurveChart` | `BufferPages.swift`, `SavingsGoalPages.swift`, `AcceleratorPages.swift` (D) | vervallen (vervangen door `TrendChart`) |
| `TimeLineChart`, `FlowChart`, `AllocationDonut`, `TimePoint`, `chartAxes` | `Charts.swift` (F) | vervallen na golf 1 (F houdt ze tot dan als compat; G verwijdert) |
| `SyncPromptsHost`, `.syncPrompts(_:)` | `CloudViews.swift` (E), aanroep in `MyBuddyApp.swift` (0B) | vervallen; vervangen door `SyncAttentionBanner` (E) |
| `ChangePasswordSheet`, `DeleteAccountSheet`, `ChangeCloudPasswordSheet`, `DeleteCloudAccountSheet`, `SpreadsheetImportSheet` | `AuthView.swift`, `CloudViews.swift`, `BackupUI.swift` (E) | pagina's in `App/Pages/Settings/` (E) |
| `FirebaseSetupSection`, `RateFetchRow`, `SectionLabel`, `BackupHost` | `CloudViews.swift`, `MarketDataUI.swift` (E), `Components.swift` (0A), `BackupUI.swift` (E) | vervallen |
| `AppTab`, `Destination` | `Router.swift` (0B) | `App/Navigation/NavigationModel.swift` (0B) |

### 6.7 Eigendom van elk bestand (controle: `find App Tests -type f` en `grep` op de namen in `docs/design/plan.md`)

Gecontroleerd met een script: 93 bestanden, alle precies een eigenaar, geen overlap.

| Eigenaar | Bestanden |
|---|---|
| **0A** (8) | `App/UI/Theme.swift`, `Glass.swift`, `Components.swift`, `Fields.swift`, `MoneyViews.swift`, `BlockOrder.swift`; `App/Assets.xcassets/AccentColor.colorset/Contents.json`, `App/Assets.xcassets/Contents.json`; nieuw: `App/UI/Layout.swift`, `Motion.swift`, `RowActions.swift`, `ComponentGallery.swift`, `scripts/design-checks.sh` |
| **0B** (6) | `App/MyBuddyApp.swift`, `RootView.swift`, `Router.swift`, `AppStore.swift` (alleen lezen), `App/Pages/DestinationView.swift`, `App/Debug/DebugLaunch.swift`; nieuw: `App/Navigation/*`, `NavigationRulesTests.swift` en symlink |
| **A** (3) | `App/Pages/HomeView.swift`, `SavingsView.swift`, `ToolsView.swift` (alle drie vervallen); nieuw: `App/Pages/Tabs/*` |
| **B1** (3) | `App/Pages/SavingsPages.swift`, `App/UI/SavingsDisplay.swift`, `App/UI/MoneyFigures.swift`; nieuw: `App/Pages/Month/*`; tests: `MoneyFiguresTests`, `AllocationEditTests`, `LineSaveTests`, `SalaryScheduleEditTests` |
| **B2** (2) | `App/Pages/CashflowPages.swift`, `App/UI/CashflowDisplay.swift`; nieuw: `App/Pages/Bank/*`; tests: `CashflowDisplayTests` |
| **C** (3) | `App/Pages/PotPages.swift`, `PortfolioPages.swift`, `App/UI/PotDisplay.swift`; nieuw: `App/Pages/Saving/*`; tests: `PotDisplayTests` |
| **D** (6) | `App/Pages/GoalPages.swift`, `SavingsGoalPages.swift`, `BufferPages.swift`, `ProjectionPage.swift`, `PurchasePages.swift`, `AcceleratorPages.swift`; nieuw: `App/Pages/Planning/*` |
| **E** (16) | `App/Pages/SettingsView.swift`, `App/Auth/AuthStore.swift`, `AuthView.swift`, `PasswordHasher.swift`, `App/Cloud/CloudAccount.swift`, `CloudViews.swift`, `EventStream.swift`, `KeychainSecretStore.swift`, `NetworkMonitor.swift`, `SyncController.swift`, `App/Config/FirebaseConfig.swift`, `App/UI/BackupUI.swift`, `App/UI/MarketDataUI.swift`, `Tests/AppTests/AuthTests.swift`, `CloudTests.swift`, `SyncControllerTests.swift`; nieuw: `App/Pages/Settings/*`; inhoudelijk gewijzigd worden `SettingsView`, `AuthView`, `CloudViews`, `BackupUI` en `MarketDataUI`; `AuthStore`, `PasswordHasher`, `CloudAccount`, `EventStream`, `KeychainSecretStore`, `NetworkMonitor`, `SyncController`, `FirebaseConfig` en de drie `AppTests` blijven ongewijzigd |
| **F** (1 + Core) | `App/UI/Charts.swift`; nieuw: `App/UI/ChartModels.swift`; **alle 35 bestanden in `App/Core/`** als poortwachter: alleen `Invest.swift`, `Overview.swift`, `Pots.swift` mogen veranderen; tests: `HoldingDayTests`, `InvestTests`, `OverviewTests` (aanpassen) en de nieuwe testbestanden uit 5.5 |
| **G** (10 binnen `App/`) | `README.md`, `docs/v3-spec.md`, `scripts/ci-screenshots.sh`, `project.yml`, `SECURITY.md`, `firebase/*`, `App/PrivacyInfo.xcprivacy`, `App/Assets.xcassets/AppIcon.appiconset/*` (9 bestanden, ongewijzigd); in golf 2 daarnaast elk bestand voor integratiefouten |
| Overige bestaande tests in `CoreTests` | niemand wijzigt ze; breekt er een, dan is dat een signaal voor de eigenaar van het gerelateerde bestand (melden onder WIRING) |

## 7. Verificatiebeleid

### 7.1 Poorten tussen de golven

- **Poort golf 0 naar golf 1:** `docs/design/contract-check.sh 0` meldt "CONTRACT COMPLEET"; `swift test` in `CoreTests` volledig groen; `check_swift` 0 foutknopen op alle eigen bestanden van 0A, 0B en F; de rapporten van 0A, 0B en F bevatten geen openstaande WIRING die golf 1 blokkeert.
- **Poort golf 1 naar golf 2:** `docs/design/contract-check.sh 1` meldt "CONTRACT COMPLEET"; elke bouwer van golf 1 levert zijn rapport met de uitvoer van `scripts/design-checks.sh <eigen bestanden>` zonder FAIL.
- **Oplevering (G):** alles hieronder, op de hele `App/`.

De scripts staan in `docs/design/` (`design-checks.sh`, `contract-check.sh`); 0A kopieert het eerste naar `scripts/design-checks.sh`. Ze zijn hier getest tegen de huidige code (nulmeting hieronder).

### 7.2 Het controlescript (`scripts/design-checks.sh`)

Elke regel is een grep tegen een verboden of verplicht patroon met een verwachting; zonder pad draait hij over heel `App/`, met paden over alleen die bestanden (voor de bouwers). Hij eindigt met "ALLES PASS" of een lijst FAILs (exit 1).

```bash
#!/usr/bin/env bash
# Ontwerpcontrole voor MyBuddy. Gebruik: scripts/design-checks.sh [pad ...]   (zonder pad: heel App/)
# Elke regel: naam | verwachting | aantal gevonden | PASS/FAIL. Exit 1 bij een FAIL.
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /home/user/MyBuddy)"
SCOPE=("${@:-App}")
FAIL=0
# chk <naam> <max|min:N|eq:N> <regex> [uitgezonderd-bestand-regex]
chk() {
  local name="$1" rule="$2" re="$3" skip="${4:-^$}"
  local n; n=$(grep -rnE --include=*.swift -- "$re" "${SCOPE[@]}" 2>/dev/null | grep -vE "$skip" | wc -l | tr -d ' ')
  local ok=0
  case "$rule" in
    0)     [ "$n" -eq 0 ] && ok=1 ;;
    min:*) [ "$n" -ge "${rule#min:}" ] && ok=1 ;;
    max:*) [ "$n" -le "${rule#max:}" ] && ok=1 ;;
  esac
  report "$name" "$rule" "$n" "$ok"
}
report() {
  local verdict=PASS; [ "$4" = 1 ] || { verdict=FAIL; FAIL=1; }
  printf '%-52s verwacht %-7s gevonden %-4s %s\n' "$1" "$2" "$3" "$verdict"
}
# Meerregelig (PCRE): een pictogram-alleen-knop zonder IconButton
chkml() {
  local name="$1" re="$2"
  local n; n=$(grep -rPzo --include=*.swift -- "$re" "${SCOPE[@]}" 2>/dev/null | tr '\0' '\n' | grep -c "Button" )
  local ok=0; [ "$n" -eq 0 ] && ok=1
  report "$name" 0 "$n" "$ok"
}
echo "== Typografie en maten"
chk "vaste lettergrootte"                  0 '\.font\(\.system\(size'
chk "caption2 (11 pt)"                     0 '\.caption2'
chk "afgeronde cijfers (design: .rounded)" 0 'design: *\.rounded'
chk "krimpende tekst buiten Components"    0 'minimumScaleFactor' 'App/UI/Components.swift'
chk "lichte lettergewichten"               0 'weight\(\.(light|thin|ultraLight)\)|\.fontWeight\(\.(light|thin|ultraLight)\)'
chk "HOOFDLETTERS in de UI"                0 '\.uppercased\(\)'
chk "vaste hoogte 20-43 pt op knop/rij"    0 '\.frame\((width|height|minHeight|minWidth): *(2[0-9]|3[0-9]|4[0-3])(\.0)?\)' 'App/UI/Charts.swift|Components.swift'
echo "== Kleur en glas"
chk "Color(hex: buiten Theme"              0 'Color\(hex:' 'App/UI/Theme.swift'
chk "Color(red:/UIColor( buiten Theme"     0 'Color\(red:|UIColor\(|NSColor\(' 'App/UI/Theme.swift'
chk ".secondary als tekst/pictogramkleur"  0 'foregroundStyle\(\.secondary\)|Color\.secondary|foregroundColor\(\.secondary\)'
chk "wit als voorgrond"                    0 'foregroundStyle\(\.white\)|foregroundStyle\(Color\.white\)|foregroundColor\(\.white\)'
chk "glas op inhoud (glassCard/Surface/Effect)" 0 'glassCard\(|glassSurface\(|\.glassEffect\(' 'App/UI/Glass.swift|App/UI/Charts.swift'
chk "oude glasblokken (GlassBlock/LinkedBlock)" 0 'GlassBlock\(|LinkedBlock\(' 'App/UI/Components.swift'
chk "oude chips (ChipButton/Link/Grid/Label)"   0 'Chip(Button|Link|Grid|Label)\(' 'App/UI/Components.swift'
chk "MeshBackground"                       0 'MeshBackground' 'App/UI/Theme.swift'
chk "tint op kaart (tint: Theme.olive)"    0 'tint: *Theme\.olive'
echo "== Navigatie en sheets"
chk "Instellingen als sheet / showSettings" 0 'showSettings|SettingsView\(\) *\}|sheet\(.*Settings'
chk "eigen tabbalk"                        0 'GlassTabBar|barBackdrop'
chk "TabView aanwezig (app + Mac-instellingen)" min:2 'TabView *[\(\{]'
chk "TabView niet vaker dan 3"             max:3 'TabView *[\(\{]'
chk ".sheet( in de hele app (nu 26)"       max:16 '\.sheet\('
chk "alert()"                              0 '\.alert\('
chk "apparaattype als layoutkeuze"         0 'UIDevice|userInterfaceIdiom|UIScreen'
chk "navigationBarTitleDisplayMode buiten Components" 0 'navigationBarTitleDisplayMode' 'App/UI/Components.swift'
echo "== Toegankelijkheid en beweging"
chk "animation(Theme.motion buiten Components" 0 '\.animation\(Theme\.(motion|quickMotion)' 'App/UI/Components.swift|App/UI/Motion.swift'
chk "Reduce Motion gelezen"                min:1 'accessibilityReduceMotion'
chk "Reduce Transparency gelezen"          min:1 'accessibilityReduceTransparency'
chk "koppen (isHeader)"                    min:8 'isHeader|accessibilityHeading'
chk "haptiek (sensoryFeedback)"            min:5 'sensoryFeedback'
chk "swipe-acties op rijen"                min:6 'swipeActions|rowActions\('
chk "contextmenu / rowActions"             min:6 'contextMenu|rowActions\('
chk "lege staat (ContentUnavailableView)"  min:3 'ContentUnavailableView'
chk "ellipsis.circle als rijmenu"          0 'ellipsis\.circle' 'toolbar|Toolbar'
chkml "icoonknop zonder IconButton"        'Button[^{]{0,80}\{[^}]{0,200}\}\s*label:\s*\{\s*Image\(systemName'
echo "== Grafieken"
chk "import Charts buiten Charts.swift"    0 'import Charts' 'App/UI/Charts.swift'
chk "Chart( buiten Charts.swift"           0 '[^a-zA-Z]Chart *[\(\{]' 'App/UI/Charts.swift'
chk "accessibilityChartDescriptor"         min:3 'accessibilityChartDescriptor'
chk "oude grafiektypen"                    0 'TimeLineChart|FlowChart|AllocationDonut|DayBalanceChart|BufferChart|SavingsGoalChart|GoalCurveChart|ProgressBar\(|ProgressRing\(|SegmentBar\(' 'App/UI/Components.swift'
echo "== Taal (termenlijst)"
chk "Engelse tabnamen/oude termen"         0 '"(Home|Savings|Tools)"|Portefeuille|Mijn beleggingen|Salaris & inkomsten|Bankuitgaven|Saldo nu|Bankbuffer|Spaarpot Buffer|Kies potten|Kies beleggingen|Per dag bekijken|Dag voor dag bekijken|Alle dagen bekijken|Meetpunt|vaste lasten|Buffer op bankrekening'
echo "== Instellingen en account: geen sheets (alleen bij een volledige run)"
if [ "$#" -eq 0 ]; then
  SET=(App/Pages/Settings App/Pages/SettingsView.swift App/Auth App/Cloud App/UI/BackupUI.swift App/UI/MarketDataUI.swift)
  n=$(grep -rnE --include=*.swift '\.sheet\(|\.fullScreenCover\(' "${SET[@]}" 2>/dev/null | wc -l | tr -d ' ')
  ok=0; [ "$n" -eq 0 ] && ok=1; report "sheet in Instellingen/Account/Back-up" 0 "$n" "$ok"
  n=$(grep -rnE --include=*.swift 'Theme\.buttonHeight' App 2>/dev/null | wc -l | tr -d ' ')
  ok=0; [ "$n" -eq 0 ] && ok=1; report "Theme.buttonHeight (moet minTapTarget zijn)" 0 "$n" "$ok"
fi
echo
[ "$FAIL" = 0 ] && echo "ALLES PASS" || { echo "ER ZIJN FAILS"; exit 1; }
```

**Nulmeting (HEAD ca0c945, gemeten met dit script) en doel**

| Controle | Nu | Doel |
|---|---|---|
| `.font(.system(size:` | 5 | 0 |
| `caption2` | 25 | 0 |
| `design: .rounded` | 26 | 0 |
| `minimumScaleFactor` buiten `Components.swift` | 44 (49 in totaal) | 0 |
| `.uppercased()` | 13 | 0 |
| `.secondary` als voorgrondkleur | 300 | 0 |
| `GlassBlock(` plus `LinkedBlock(` | 103 | 0 |
| `Chip*(` | 91 | 0 |
| `glassCard(`, `glassSurface(`, `.glassEffect(` buiten `Glass.swift` en `Charts.swift` | 14 | 0 |
| `MeshBackground` | 12 | 0 |
| `.sheet(` in de app | 26 | 16 of minder, en 0 in Instellingen, Account en Back-up |
| `.alert(` | 2 | 0 |
| `TabView` | 0 | 2 (app, Mac-instellingen) |
| `swipeActions` of `rowActions(` | 0 | 6 of meer |
| `ContentUnavailableView` | 0 | 3 of meer |
| `accessibilityChartDescriptor` | 0 | 3 of meer |
| `accessibilityReduceMotion`, `accessibilityReduceTransparency` | 0 | 1 of meer elk |
| `sensoryFeedback` | 0 | 5 of meer |
| isHeader of accessibilityHeading | 3 | 8 of meer |
| `import Charts` buiten `Charts.swift` | 5 | 0 |
| oude grafiektypen | 52 | 0 |
| `.animation(Theme.motion`/`quickMotion` buiten `Components`/`Motion` | 62 | 0 |
| oude termen (Home, Savings, Tools, Portefeuille, Meetpunt, Saldo nu, ...) | 47 | 0 |

### 7.3 Aanvullende controles (G, en elke bouwer voor zijn eigen deel)

1. **Syntaxis.** `check_swift.py` op elk gewijzigd en nieuw `.swift`-bestand: 0 foutknopen.
2. **Core.** `cd CoreTests && swift test`: volledig groen. `git diff --stat App/Core` toont alleen `Invest.swift`, `Overview.swift` en `Pots.swift` (en geen nieuw `Codable`-veld).
3. **Aanroepen tegen definities.** Per symbool uit par. 4.4: `grep -rn "Naam(" App` en elke aanroep letterlijk vergelijken met de definitie (labels, volgorde, typen, optionals, `@ViewBuilder`). Extra aandacht: tuple-destructuring in `ForEach`, `if` in `AxisContentBuilder`, `@Bindable` voor `@Observable` bindings, `private` properties die buiten het type worden gebruikt, ontbrekende `import Charts` (alleen `Charts.swift`).
4. **Elke pictogramknop heeft een label:** `IconButton` is de enige manier (de meerregelige controle in het script); extra handmatig: `grep -rn "Image(systemName" App | grep -v "Label\|IconButton\|accessibilityHidden"` doorlopen op knoppen.
5. **Elke grafiek heeft een lege staat en een beschrijving:** `grep -rn "TrendChart(\|StackedBarChart(\|DonutChart(" App` en voor elke aanroep: het model komt uit een modelbouwer van F (dus heeft `summary` en `empty`); de testlijst van par. 5.5 is groen; `grep -c accessibilityChartDescriptor App/UI/Charts.swift` is 3 of meer.
6. **Geen aanraakdoel kleiner dan 44 pt:** `Theme.minTapTarget` is 44; `grep -rnE "\.frame\((width|height|minHeight|minWidth): *(2[0-9]|3[0-9]|4[0-3])\)" App` geeft alleen decoratie (ringen, badges), geen knop; `StepButton`, `ColorChoiceRow`, `SymbolChoiceRow`, oogknop en terugknop op het inlogscherm zijn 44.
7. **Geen sheet voor Instellingen, Account of Back-up** en geen sheet binnen een sheet: `grep -n "\.sheet(" ` in de bestanden die een sheet-inhoud definiëren (`SheetScaffold`-gebruikers) geeft niets; de controle in het script voor de instellingenmappen geeft 0.
8. **Kleur:** de hex-waarden van par. 4.1 en 4.2 staan letterlijk in `Theme.swift` (`grep -c` per waarde); `python3` op `plan/tokens.py` opnieuw draaien met de waarden uit de code geeft dezelfde contrastcijfers.
9. **Termen en taal:** het termenpatroon uit het script; handmatig: geen "Klik" op iOS, geen "tik" op de Mac, geen "Oeps", geen bezittelijk "Mijn" in titels.
10. **Contract:** `docs/design/contract-check.sh alles` meldt "CONTRACT COMPLEET"; `grep -rn "showsSettings\|Theme.flow\|Theme.olive\|buttonHeight" App` geeft niets na G.

### 7.4 Handmatige scenario's (op een toestel of in de simulator; hier niet uitvoerbaar)

Elke bouwer voert de scenario's van zijn pakket uit zodra er een build is; G rapporteert per scenario "gedaan" of "niet te testen hier".

| # | Scenario | Slaagt als |
|---|---|---|
| 1 | Eerste start, leeg lokaal account | Overzicht toont Welkom met twee knoppen, geen lege grafiek, geen alert; "Salaris instellen" opent Salaris |
| 2 | Voorbeelddata laden | hero, `flow`, `wealth`, `upcoming` gevuld; "Nog te verdelen" is op Overzicht, Maand en Verdelen hetzelfde getal |
| 3 | Uitgave toevoegen | in 3 tikken (Maand, Uitgaven, `+`); swipe verwijdert met bevestiging waar het moet; contextmenu heeft dezelfde acties; terugkerende regel vraagt "alleen deze maand of ook volgende" |
| 4 | Maand wisselen en periodekeuze Jaar | cijfers op Overzicht en Maand sluiten; melding "Cijfers sluiten niet" alleen bij een echte afwijking |
| 5 | Verdelen met percentage, "Alles op nul", Overschrijfdag | zelfde uitkomsten als vóór de herbouw (`MonthFigures` ongewijzigd) |
| 6 | Bankrekening: Saldo invullen, Geld bewegen, Minimumsaldo, drie segmenten | alle vijf acties werken; Dag voor dag toont een sectie per dag; zonder banksaldo een lege staat in plaats van een verdwenen blok |
| 7 | Tabs | pad per tab blijft bewaard bij wisselen; Instellingen is vanaf een diepe pagina (Spaarpot, Dag voor dag) in 1 tik bereikbaar; geen enkele sheet voor Instellingen |
| 8 | Grafieken Bank en Dag voor dag | geen lege `Chart`; een dag is een stip met tekst; labels uniek |
| 9 | Zoeken op het Overzicht | "uitgaven", "back-up", "noodbuffer", "wachtwoord" en de naam van een pot openen de goede pagina; niets gevonden toont `ContentUnavailableView.search` |
| 10 | Spaarpotten | nieuwe pot (2 tikken), storten, rente, doel; pot zonder doel heeft geen volle ring; Verloop-grafiek verschijnt |
| 11 | **Beleggingen** | (a) nieuwe belegging met alleen Totaal ingelegd 3.000 en inleg 200: grafiek met "Geschat"; (b) ticker zonder aantal: uitleg "Vul ook het aantal stuks in"; (c) ticker met aantal en geen internet: afgeleide lijn; (d) Huidige waarde invullen: echte lijn; (e) Totaal ingelegd wijzigen bij een bestaand meetpunt: "Ingelegd" volgt; (f) keuzebalk 6 mnd, 1 jaar, 3 jaar alleen als hij iets verandert; (g) donut ook bij een soort, dezelfde kleur als de lijst; (h) koersgrafiek met unieke labels en bij een fout "Probeer opnieuw" |
| 12 | Plannen | Doelen zonder schakelaar; Spaardoel berekenen (al bereikt: lege staat); Noodbuffer; Versnellers eindigt op het laatste punt |
| 13 | Toekomstschatting | lege invoer: lege staat; Streefbedrag als markering; scenario's herkenbaar zonder kleur |
| 14 | Instellingen | elke functie uit tabel 3.2 bereikbaar; Account-rij toont de status; terugnavigatie overal standaard |
| 15 | Account | wachtwoord wijzigen (pagina), uitloggen (dialoog aan de knop), account verwijderen (pagina), lokaal en cloud |
| 16 | Gegevens | back-up maken, terugzetten met bevestiging, Excel en CSV importeren (pagina met overzicht), 3 CSV-exports, voorbeelddata, Alles wissen |
| 17 | Synchronisatie | conflict: banner op Overzicht, keuze in Account, geen alert bij starten; offline-status; "Lokale gegevens uploaden?" in Account |
| 18 | Toegankelijkheid | Dynamic Type AX5 op alle tabroots (stapelen, niets afgekapt); VoiceOver-rotor Koppen en een grafiekbeschrijving; Verhoog contrast, Verlaag transparantie, Verlaag beweging, Onderscheid zonder kleur; kleurenblindsimulatie op de reeksen |
| 19 | Apparaten | iPhone SE-breedte, iPhone Pro Max, iPad 13 inch (zijbalk en Slide Over), Mac (venster van 640 tot 1400 breed, zijbalk, Cmd+komma, Cmd+1 t/m Cmd+5, menubalk, `.help`) |
| 20 | Licht en donker wisselen tijdens gebruik | geen onleesbare tekst, kaarten en canvas blijven onderscheidbaar |

## 8. Risico's en wat er niet verandert

### 8.1 Wat niet verandert

- **Alle Core-logica en alle rekencijfers**, behalve de bedoelde wijziging voor beleggingen zonder meetpunt (C1 t/m C5, C7 t/m C9 in `Invest.swift`, `Overview.swift`, `Pots.swift`). `MonthFigures`, `MonthBoard`, `periodSummary`, `netWorth`, `remaining(in:)`, bank, potten, rente, doelen, versnellers, aankoopcheck blijven zoals ze zijn; de UI toont dezelfde getallen uit dezelfde bronnen.
- **Gegevens en formaten:** `FinanceData` en `AppSettings` (geen nieuw `Codable`-veld; `blockOrder` houdt `[String: [String]]`), het JSON-back-upformaat, Excel/CSV-import en -export (`ImportMapping`, `Export`, `XLSX`), `AccountPrefs` en alle `@AppStorage`-sleutels, het opslagbestand per account.
- **Synchronisatie en inloggen:** `SyncController`, `CloudSync*`, `FirebaseAuthClient`, `AuthStore`, `PasswordHasher`, `KeychainSecretStore`: alleen de views eromheen veranderen. De inlogplicht blijft (K4).
- **Platformgrenzen:** iOS 18 en macOS 15 als ondergrens, Swift 5-modus, geen nieuwe dependencies, iOS 26-API's alleen achter `#available`. Debug-startargumenten blijven werken.
- **Alles wat de gebruiker nu kan**: par. 2.5 en 3.2 wijzen voor elk verwijderd onderdeel de plek aan. Bewust vervallen zijn alleen: het kiezen van "wat staat op Home" (K9), de losse dagkiezer op Bankrekening, de pagina Overschrijvingen op Bankrekening (dezelfde cijfers staan op Verdelen), de opgeslagen oude blokvolgorden onder `home`, `savings`, `tools`, en de ontwikkelaarsuitleg over Firebase in de app.

### 8.2 Risico's

| # | Risico | Gevolg | Beheersing |
|---|---|---|---|
| R1 | SwiftUI en Charts zijn hier niet te compileren | fouten pas zichtbaar in Xcode | `check_swift` per bestand, letterlijke vergelijking van elke aanroep met zijn definitie, contractcontrole, pakket G; **vóór oplevering een build in Xcode 26 op iPhone, iPad en Mac** |
| R2 | Het andere herstelwerk wijzigt tegelijk bestanden in `App/` | bouwers overschrijven elkaar | start golf 0 pas als dat werk is vastgelegd; elke bouwer begint met `git status` en `git diff` op zijn eigen bestanden; de eigendomsgrenzen van 6.7 gelden ook voor dat werk |
| R3 | Gedrag van `TabView` met `.sidebarAdaptable`, een `NavigationStack` per tab en een padbinding is niet te testen (HIG-notes onzekerheid 4) | pad springt, terugtik werkt niet op elke iOS-versie, zijbalk op de Mac te smal | `TabStack` is een kleine, losse view; minimumvenster 640 breed; controleer scenario 7 en 19; terugval: zonder `.sidebarAdaptable` (alleen tabbalk) is een wijziging van een regel |
| R4 | De `Settings`-scene heeft de store van de actieve sessie nodig | lege scene of verouderde store na uitloggen | `ActiveSession.register` bij start van `SignedInRoot`, `clear` bij verdwijnen; de scene toont "Log eerst in" zonder sessie |
| R5 | C1 verandert getallen in Vermogen, doelen en verdeling voor beleggingen zonder meetpunt | gebruikers zien een ander totaal | bedoeld; `HoldingDayTests` aangepast; de noot "Geschat" maakt het zichtbaar; te melden in de oplevernotitie |
| R6 | De compat-laag blijft hangen | oude namen en glas in de code | het script meldt elke resterende `GlassBlock(`, `Chip*(`, `MeshBackground`; G verwijdert ze en de poort naar oplevering vraagt "ALLES PASS" |
| R7 | Contractdrift tussen parallelle bouwers | aanroepen kloppen niet met definities | par. 4.4 is bindend; wijzigen kan alleen via WIRING; G doet de steekproef van 7.3 punt 3 |
| R8 | Een vervallen type wordt nog elders gebruikt (6.6) | build faalt | de verhuistabel noemt voor elk type wie verwijdert en wie definieert; `grep` op elke naam uit de tabel bij G |
| R9 | `ContentUnavailableView` is groot in een kleine kaart | lelijke lege staten | `EmptyHint` heeft `style: .inline`; `.page` alleen voor een hele lege pagina; grafieken krijgen een compacte variant |
| R10 | `accessibilityChartDescriptor` en `chartXSelection` zijn alleen op syntaxis gecontroleerd | compileerfout of onverwacht gedrag | API-namen zijn tegen Apple's documentatie gecontroleerd (`charts.md` 6.4); terugval: alleen `accessibilityLabel` met `summary` |
| R11 | Contrastcijfers zijn berekend zonder vibrancy of glas | echte waarden iets anders | Accessibility Inspector op een toestel (scenario 18) |
| R12 | Het aantal pagina's stijgt van 18 naar 31 | meer te onderhouden | elke pagina is klein (hooguit 6 blokken), diepte hooguit 3, zoeken vindt alles |
| R13 | Op de Mac staat Instellingen zowel in de zijbalk als in de `Settings`-scene | dubbele ingang | bewust (K3): geen onzekere API om het item te verbergen; de pagina's zijn identiek |
| R14 | Gebruikers met een eigen volgorde of gekozen potten op Home zien dat niet terug | kleine ergernis | de gegevens blijven in het bestand (geen verlies); de nieuwe indeling is eenvoudiger |
| R15 | `Router.open` knipt nu terug in plaats van te duwen als de pagina al in het pad staat | een link lijkt "terug" te gaan | gewenst (N9); `NavigationRulesTests` leggen het vast |
| R16 | `minimumScaleFactor` alleen in `BigAmount` | lange bedragen in smalle kolommen wrappen of stapelen | `FigureRow` en `AmountRow` stapelen; scenario 18 |

### 8.3 Niet in deze ronde (bewust)

Account optioneel maken (ACT-1, K4); nieuwe-regel-commando's in de menubalk en TipKit-tips (vragen actie-routing in elke pagina); B-10 en B-11 uit `charts.md` (ontwerpvragen voor de Core-eigenaar); `Fmt` op `Locale.current` in plaats van vast `nl_NL` (audit 3.12); "Maak ongedaan" in plaats van bevestigen (audit S8); `Tab(role: .search)`; passkeys; `.inspector` op iPad; `privacySensitive`. Alles daarvan is los te plannen en haalt niets van het bovenstaande onderuit.

### 8.4 Op een toestel vast te stellen (hier niet te zien)

Hoe de standaard x-as en een vlakke reeks in Swift Charts eruitzien bij onze eigen assen; of terugtikken op de actieve tab het pad leegt op iOS 18; de breedte van de zijbalk bij 640 pt op de Mac; of `confirmationDialog` op iPad en Mac bij de knop verschijnt; de werkelijke contrastwaarden met glas en vibrancy op iOS 26; de koersgrafiek (G3) met echte koersdata.

## Bijlage: bewijs en hulpmiddelen

| Wat | Waar |
|---|---|
| Contrast en kleurenblindheid van de tokens (par. 4.1, 4.2) | `/tmp/claude-0/-home-user-MyBuddy/9beb118c-8e88-5a84-a4b5-426733aaf64d/scratchpad/plan/tokens.py` en `final.py`; uitvoer in par. 4 |
| Controlescripts | `docs/design/design-checks.sh` (nulmeting in 7.2), `docs/design/contract-check.sh` |
| Code voor modellen, componenten en tests van de grafieklaag | `docs/design/charts-prototype.md` B1 t/m B4 |
| Bronnen van dit plan | `docs/design/hig-notes.md`, `docs/design/audit.md`, `docs/design/charts.md` |
