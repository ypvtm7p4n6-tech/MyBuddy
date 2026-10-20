# Kritiek op het ontwerpplan MyBuddy

Peildatum 15 oktober 2026, `HEAD` 11447d4 (App/ en CoreTests/ ongewijzigd; `git diff HEAD -- App CoreTests` is leeg). Onafhankelijke kritiek op `docs/design/plan.md` (1077 regels), getoetst aan `hig-notes.md`, `audit.md`, `charts.md` en de code (`RootView`, `Router`, `Components`, `SettingsView`, `HomeView`, `SavingsView`, `ToolsView`, `BlockOrder`, `DebugLaunch`, `CashflowPages`, `SavingsPages`, `PortfolioPages`, `Fields`). Regelnummers van `plan.md` zijn die van deze stand; code-regelnummers gelden voor `HEAD`. Alleen gelezen en gemeten; bewijsbestanden staan onder `/tmp/critic/` en `/tmp/sb-critic-ci`.

## 0. Oordeel in tien regels

Het plan is gedegen in analyse en dekt alle vier de wensen op ontwerpniveau. Instellingen als tab met Account als eigen pagina, de Core-fix voor Beleggingen, de termenlijst en de eigendomstabel (93 bestanden, geen enkel bestand twee eigenaren; ik heb dat nagerekend) houden stand. Het plan zou in deze vorm toch mislukken of schade doen op zeven punten:

1. **K9 schrapt een expliciet eerder gevraagde functie** (drie zelfgekozen potten, en gekozen beleggingen, op Home). Dat is de enige harde schending van de opdracht "een eerder gevraagde functie mag niet verdwijnen". Zie F1.
2. **Geen enkele golf eindigt in een compileerbare toestand en er is geen compileer-oordeel** voor 12 bouwers die blind 40.000 regels SwiftUI herschrijven, terwijl `.github/workflows/ci.yml` al iOS en macOS bouwt. Zie F2.
3. **De maandsluiting van bank en spaarpotten** (`CashflowBankBlock`, `CashflowPotsBlock`) verdwijnt, onder een onjuiste verwijzing naar H9. Zie F3.
4. **`focusMonth` en `periodMode` blijven globaal** terwijl Overzicht en Maand nu verschillende tabs zijn: bladeren op het Overzicht verschuift de maand op het tabblad Maand. Dat is het soort verwarring dat de gebruiker wil weghalen. Zie F4.
5. **De Beleggingen-oplossing mist de invoer die de grafiek zinvol maakt** (een startmaand) en heeft geen manier om het gemelde geval zichtbaar te controleren. Zie F5.
6. **De diepteregel en de dedupe (N9) werken niet** voor de `NavigationLink(value:)`-links waar bijna alle navigatie uit bestaat. Zie F6.
7. **De bouwers delen een werkmap, een testmodule en geen isolatie**; de WIRING-regel stuurt alles naar een enkele eindbouwer. Zie F7 en F8.

Rest: kleine HIG-tegenstrijdigheden, een tikkentabel die ongelijke dingen vergelijkt (par. 7), en een paar compileerrisico's die met een regel te verhelpen zijn.

## 1. Bevindingen op ernst

| Id | Ernst | Kort | Waar |
|---|---|---|---|
| F1 | blocker | K9: kiezen van 3 potten en 4 beleggingen voor Home vervalt | plan.md:30, 148, 790, 1039; README.md:7 |
| F2 | blocker | Geen compileerbare golf, geen compileer-oordeel; CI wordt niet gebruikt | plan.md:719-728, 1045, 864-870 |
| F3 | major | Maandsluiting bank en potten (begin, binnen, eruit, eind) vervalt | plan.md:159, 783; CashflowPages.swift:730, 775 |
| F4 | major | Globale `focusMonth`/`periodMode` over tabs; Overzicht en Maand dubbelen cijfers | plan.md:195, 107-111; Router.swift:61-63; Components.swift:414 |
| F5 | major | Beleggingen: geen startmaand-invoer, geen reproduceerbare controle van het gemelde geval | PortfolioPages.swift:494, 682; plan.md:790 |
| F6 | major | Dedupe en "hooguit drie niveaus" gelden niet voor `NavigationLink(value:)` | plan.md:42, 192, 138, 1059 |
| F7 | major | Parallel in een werkmap en testmodule; WIRING-bottleneck bij G | plan.md:686, 692, 811-815; CoreTests/Tests/MyBuddyCoreTests (4 symlinks) |
| F8 | major | Koppelingen buiten het contract; `contract-check.sh` controleert alleen namen | plan.md:412, 866-870; contract-check.sh |
| F9 | major | Inline-formulierrijen (Verdelen, Salaris) in `List` gedwongen (K6) | plan.md:27, 776; SavingsPages.swift:1260-1371 |
| F10 | minor | 4e en 5e tab tegenover eigen toets TAB-3; Instellingen in Mac-zijbalk (SID-4, SET-5) | hig-notes.md:159, 173, 268 |
| F11 | minor | 44 pt en `controlSize(.large)` overal, ook op macOS (ACC-2, MAC-9) | plan.md:404, 575 |
| F12 | minor | K8: opgeslagen blokvolgorde gaat stil verloren; 2-blokspagina's ordenen is zinloos | plan.md:211, 1039; BlockOrder.swift:62-83 |
| F13 | minor | "Veeg-om-te-sluiten vraagt bevestiging" is in SwiftUI niet te bouwen | plan.md:44, 590 |
| F14 | minor | `ActiveSession.clear()` kan een nieuwe sessie wissen; terugtik-regressie | plan.md:60, 331, 1048 |
| F15 | minor | Sync-aandacht alleen op Overzicht; "Koersen vernieuwen" alleen als gebaar; horizon van de schatting verstopt | plan.md:326, 127, 134 |
| F16 | minor | Zoekindex zonder test; zoeken alleen op tab 1 | plan.md:243 |
| F17 | minor | Tikkentabel 2.10 telt "nu" en "straks" niet gelijk | plan.md:245-259 |
| F18 | minor | Kleine gaten: app-icoon, `-mybuddy-scroll` op `List`, verouderde documenten | plan.md:859 |

## 2. (a) Dekt het plan elke zin van de gebruikersvraag?

| Zin van de vraag | Plan | Oordeel |
|---|---|---|
| "Analyseer de design guidelines van apple" | `hig-notes.md`: 15 kernregels, per onderwerp toetsbare regels met id, bronlabel en proef; officiele pagina's via de JSON-route gelezen | gedekt |
| "pas het design in de gehele app aan" | golf 0 (tokens, componenten, schil) en golf 1 (alle pagina's, Auth, Cloud, BackupUI) | gedekt op papier; zie gaten hieronder |
| "versimpelingen ... onderdelen makkelijker te vinden" | 5 tabs met een domein, vaste paginaopbouw, termenlijst par. 2.8, zoeken par. 2.9 | gedeeltelijk: pagina's 18 naar 31 (par. 7), zoeken alleen op tab 1, tikken vooral gelijk (par. 7) |
| "makkelijker uit elkaar houden" | domeinkleur en -symbool (`AppDomain`), een woord per begrip, max 6 blokken | gedeeltelijk: dezelfde getallen op Overzicht en Maand, gedeelde maandstatus (F4), dezelfde pagina onder twee tabs (F6) |
| "versimpel de instellingen" | 10 secties en 29 rijen naar 6 rijen op 4 groepen; Firebase-uitleg, `RateFetchRow`, `SectionLabel` weg | gedekt |
| "account los van de rest" | `Account` als eerste rij, eigen pagina met Profiel, Synchronisatie, Beveiliging, Uitloggen, Verwijderen | gedekt |
| "instellingen ... heel de pagina ... in plaats van alleen een pop-up" | tab Instellingen, zes sheets weg, `grep` in de DoD van E; Mac `Settings`-scene | gedekt |
| "alle grafieken werken" | G1-G17 met modellaag, lege staten en `accessibilityChartDescriptor` | gedekt |
| "en passen zich aan de gegevens die ik invul" | pure modelbouwers; C1 t/m C5 | gedekt, behalve F5 |
| "(zo doet die bij de beleggingen het niet)" | Core-fix C1 (afgeleid beginpunt), `PortfolioWindow`, "Geschat" | gedeeltelijk: zie F5 |

Gaten in "gehele app":

- **App-icoon** blijft "ongewijzigd" (plan.md:859). Voor iOS 26 verwacht de HIG een gelaagd icoon (Icon Composer). Zeg expliciet dat dit buiten de ronde valt.
- **`AuthView`** krijgt volgens E "alleen herkleurd en 44 pt" (plan.md:337), maar de DoD (plan.md:804) vraagt mesh en glaskaart weg. Kies een van beide; de DoD wint.
- **Liquid Glass-identiteit**: README.md:3 noemt "in de stijl van Apple's Liquid Glass met donker olijfgroen". Na K5 is er geen eigen glas meer; alleen systeembalken en chart-annotatie. Dat volgt de HIG (GLS-1), maar het is een merkkeuze die de gebruiker nog niet heeft gezien. Meld het in de eindnotitie.

## 3. (b) Verliest het plan een functie?

Doorgelopen: 17 `Destination`-cases, 17 sheetsoorten (audit 1.4), alle blokken van Home, Savings, Tools, en de pagina's P1 t/m P17.

**Alle 17 Destination-cases komen terug** (plan.md:173-187). Van de 17 sheetsoorten komen er 15 terug of worden een pagina. Wat nergens meer terugkomt of verkleind terugkomt:

| Onderdeel | Plan | Verlies | Ernst |
|---|---|---|---|
| Sheets "Kies potten voor Home" en "Kies beleggingen voor Home" (HomeView.swift:486-575; limiet 3 en 4) | K9: vervalt | gebruiker kan niet meer kiezen wat op de eerste tab staat | F1 |
| `PotsBlock` en `InvestBlock` met drie potten en beleggingstegels op de eerste tab | geen pot- of beleggingstegel op Overzicht (plan.md:30) | zichtbare saldi op de eerste tab | F1 |
| `CashflowBankBlock` (begin, binnen, eruit, overgeschreven, handmatig, eind) | vervalt (plan.md:159) | maandsluiting van de bank | F3 |
| `CashflowPotsBlock` (begin, inleg, rente, uit potten betaald, eind) | vervalt (plan.md:159) | maandsluiting van de potten; geen equivalent op een andere pagina | F3 |
| `CashflowOverviewBlock` ("Klopt met je overzicht", links) | banner alleen bij afwijking | de positieve bevestiging; acceptabel (plan.md:146) | geen |
| `BankDayBlock` (dagkiezer, saldo bank en potten van een gekozen dag) | vervalt; lijst met alle dagen | alleen een verlies als de dagsectie niet bank- en potsaldo toont; niet gespecificeerd | F3 |
| `BankTransfersBlock` ("Overschrijvingen") | vervalt, cijfers op Verdelen | akkoord (zelfde bron `MonthFigures`) | geen |
| Opgeslagen blokvolgorde onder `home`, `savings`, `tools` | genegeerd (plan.md:211, 1039) | persoonlijke voorkeur gaat stil verloren | F12 |
| "Koersen vernieuwen" en koersstatus-rij op Beleggingen | pull-to-refresh, Cmd+R, Instellingen > Koersen | op iPhone alleen een gebaar (ACC-7) | F15 |
| "Hoe ver kijk je vooruit?" (veld, eenheid, 5 snelkeuzes) op Toekomstschatting | niet genoemd in de blokkenlijst (plan.md:134) | de belangrijkste invoer kan in een uitklapper verdwijnen | F15 |
| Chips "Verdelen" op Spaarpot en Belegging (2 van 7 ingangen naar Verdelen) | niet genoemd | bereikbaar via Maand > Verdelen; geen echt verlies | geen |

Onopgemerkt gevolg van F3: `CashflowSummary.bankRows` en `potsRows` (`CashflowDisplay.swift:245, 294`, 8 verwijzingen in `CoreTests/.../CashflowDisplayTests.swift`) en `LedgerCheck` blijven getest maar worden door geen scherm meer gebruikt.

## 4. (c) Disjunct en uitvoerbaar?

### 4.1 Eigendom

Gecontroleerd met een script tegen tabel 6.7 (plan.md:848-860): 78 `.swift`-bestanden onder `App/`, 3 onder `Tests/AppTests` en 12 resources (icoon, kleurset, privacy) = 93; geen enkel bestand zonder eigenaar, geen enkel met twee. De tabel klopt op bestandsniveau. `Router.swift`, `AppStore.swift`, `BlockOrder.swift` en `DestinationView.swift` hebben elk een eigenaar (0B, 0B, 0A, 0B). Niet van een eigenaar voorzien: `.github/workflows/ci.yml`, `system_architecture.md` (regel 8 beschrijft nog "tab (Home, Savings, Tools), drie navigatiepaden"), `implementation_plan.md`, `task.md`. Wijs ze aan G toe.

### 4.2 Wat het plan niet ziet

- **Typen die over eigenaarsgrenzen heen gebruikt worden maar niet in het contract staan** (gemeten door definities per bestand te vergelijken met gebruik in bestanden van een andere eigenaar):

  | Type (definitie) | Gebruikt door | Risico |
  |---|---|---|
  | `ContributionInfo`, `ContributionPreview`, `PotDeleteEffect`, `PotUpcoming`, `PotUpcomingItem` (`MoneyFigures.swift`, B1) | C (`PotPages.swift`) | B1 mag alleen labels wijzigen (plan.md:776), maar C staat niet als afhankelijke in tabel 6.2 (plan.md:730-740) |
  | `DisplayRounding` (`MoneyFigures.swift`, B1) | 0A (`MoneyViews.swift`) | 0A hangt af van B1 |
  | `DayText` (`CashflowDisplay.swift`, B2) | B1 (`SavingsPages.swift`), C (`PotPages.swift`) | B2 mag niet hernoemen |
  | `PotFormat` (`PotDisplay.swift`, C) | B2 (`CashflowPages.swift`) | idem |
  | `MoneyLabels`, `MonthBoard` (B1) | A | wel genoemd (plan.md:770) |
  | `SafeInt`, `ChoiceRow`, `SaveChoices` (`Fields.swift`, 0A) | D, B1 | API "ongewijzigd" (plan.md:506) |

  Vries deze lijst in het contract (par. 4.4) in, met de regel "alleen toevoegen".

- **`NoticeBanner` verhuist van `HomeView.swift` (A) naar `Components.swift` (0A)** (plan.md:823), maar 0A schrijft in golf 0 en A verwijdert in golf 1. Tussen die twee momenten bestaan twee definities. Idem `MonthBar`/`MonthPickerBlock`. Laat 0A de verhuizing pas uitvoeren als de verwijderende eigenaar klaar is, of sta 0A een enkele verwijdering toe in `HomeView.swift`.

- **Afhankelijkheden zijn cyclisch in golf 0**: 0A hangt van 0B af voor `Destination` (`Card(headerLink:)`, `LinkCard`, `NavigationRow`) en van F voor `ProgressMeter`; 0B hangt van 0A af voor `Theme.accent`; F hangt van 0A af voor `Theme.chart*` en van B2 voor `DayChartItem` (plan.md:730-735). Dat kan alleen "op contract". Het is eenvoudiger en veiliger om `NavigationModel.swift` (Foundation-only, ongeveer 100 regels, getest met `swift test`) als stap 0 te laten landen; dan kunnen 0A en F tegen echte code schrijven.

- **Geen enkele golf eindigt compileerbaar.** Na golf 0 verwijst `RootView` naar `OverviewTab()` e.d. die pas in golf 1 bestaan, en pagina's verwijzen nog naar `router.homePath`/`toolsPath` (`AcceleratorPages.swift:651`, `HomeView.swift:11`, `SavingsView.swift:11`, `ToolsView.swift:10`, `Components.swift:38`, `DebugLaunch.swift:31-41`) die 0B verwijdert. Gevolg: tot het einde van golf 1 is er geen punt waarop iemand kan zien of het geheel bouwt. Zie F2.

- **A kan beginnen zodra het fundament klaar is**, maar alleen naar naam: de `*SummaryCard`-views van C, D, B2 en E bestaan dan nog niet (`contract-check.sh 1` toont 18 ontbrekende namen op `HEAD`). A kan zijn tabroots dus niet tegen het gedrag van die kaarten toetsen.

### 4.3 Dezelfde werkmap en dezelfde testmodule (F7)

Plan.md:692 verbiedt git-commando's tot G, en alle bouwers werken in `/home/user/MyBuddy`. `CoreTests` compileert vier UI-bestanden als symlink in het testtarget (`CashflowDisplay.swift`, `MoneyFigures.swift`, `PotDisplay.swift`, `SavingsDisplay.swift`) en straks ook `ChartModels.swift` en `NavigationModel.swift`. Eén half bewerkt bestand van B1 laat dus `swift test` voor C, B2 en F falen. `--scratch-path` per bouwer scheidt alleen de builddirectory, niet de bronnen. Dit is dezelfde situatie als R2 (andere herstelwerk), maar nu intern.

Oplossing: een `git worktree` per pakket (de omgeving heeft `EnterWorktree`), elk op een eigen branch; omdat de bestanden disjunct zijn is samenvoegen triviaal. Pas dan is "elke bouwer draait `swift test` groen" een betrouwbare poort.

### 4.4 WIRING-bottleneck

Plan.md:686 verwijst elke noodzakelijke wijziging in andermans bestand naar WIRING, en plan.md:811-815 laat G ze in golf 2 afhandelen. Dat is een enkele bouwer die 12 rapporten, duizenden regels en alle compilatiefouten tegelijk krijgt. Houd 0A, 0B en F na golf 1 beschikbaar voor een WIRING-ronde en laat G alleen opruimen.

### 4.5 `contract-check.sh`

Golf 1 test alleen of een `struct X` ergens bestaat. Op `HEAD` slagen `IncomePage`, `BankPage`, `PotsPage`, `SettingsView`, `AuthView` al (ze bestaan met de oude handtekening). `BankPage(section:)`, `PotDetailPage(potID:)` e.d. worden niet op parameters gecontroleerd. Voeg per symbool een regex op de initializer toe (`BankPage` met `section:`, `MonthBar` met `month:`, `SheetScaffold` met `hasChanges:`).

## 5. (d) Uitvoerbaar op iOS 18 / macOS 15 zonder SwiftUI-compiler?

### 5.1 Wat klopt

Beschikbaarheid gecontroleerd in de bewaarde Apple-documentatie (`scratchpad/api-json`): `.tabViewStyle(.sidebarAdaptable)` iOS 18/macOS 15; `Tab(_:systemImage:value:content:)` iOS 18/macOS 15; `presentationSizing(.form)` iOS 18/macOS 15; `swipeActions` iOS 15/macOS 12; `ContentUnavailableView` iOS 17/macOS 14; `chartXSelection` en `sensoryFeedback` iOS 17/macOS 14; `toolbarTitleDisplayMode` iOS 17/macOS 14; `accessibilityChartDescriptor` iOS 15/macOS 12; `Settings` macOS 11. `tabBarMinimizeBehavior`, `glassEffect` en `GlassEffectContainer` zijn iOS 26 **en** macOS 26, dus `#available(iOS 26.0, macOS 26.0, *)` (plan.md:602) is juist. `hoverEffect` is alleen iOS (plan.md:601 zegt dat al). De ondergrens is dus haalbaar zonder extra `#available` behalve voor de iOS 26-API's.

### 5.2 Wat de controles niet vangen

`check_swift.py` is alleen een parser. Bewezen met `/tmp/critic/Bad.swift`: een bestand met `Card(titel:symbool:)`, `Text(42)`, een niet-bestaand type en een `VStack` met elf kinderen geeft `TOTAL ERROR NODES: 0`. Het plan leunt (plan.md:689) op "letterlijk vergelijken met de definitie" als enige controle voor ongeveer 25.000 regels herschreven SwiftUI.

Twee bronnen van een echt compileer-oordeel zijn niet benut:

1. **CI.** `.github/workflows/ci.yml` bouwt bij elke push op `claude/**` het project met XcodeGen voor iOS-simulator en macOS (`macos-26`) en draait de apptests. De uitvoer wordt beperkt tot 150 foutregels, maar de bestandsnaam in elke fout wijst naar de eigenaar. Het plan noemt een Xcode-build alleen "vóór oplevering" (plan.md:1045).
2. **Stub-typecontrole.** Uit een eerdere fase staat in `scratchpad/ci-ui` een pakket met ongeveer 600 regels nagemaakte SwiftUI- en Charts-API's dat alle pagina's tegen de echte Core typecheckt (7960 regels inclusief stubs; een run duurt ongeveer 40 s). Ik heb het gedraaid: het is verouderd. Zonder `PotDisplay.swift`, `SavingsDisplay.swift` en `CashflowDisplay.swift` geeft het veel "cannot find"-fouten; met die drie symlinks (in een kopie, `/tmp/critic/ci-ui`) blijven fouten over uit ontbrekende stubs (bijvoorbeeld `@State(initialValue:)`, `chartForegroundStyleScale`, `presentationDetents`), niet uit de app. Het vangt wel labels, ontbrekende types en ViewBuilder-limieten, maar moet voor `TabView`, `List`, `swipeActions`, `Settings` en `ContentUnavailableView` worden uitgebreid en blijft een nabootsing. Alleen CI geeft het echte oordeel.

### 5.3 Riskante ontwerpkeuzes voor compileerbaarheid

| Keuze | Risico | Maatregel |
|---|---|---|
| Kleur met vier varianten in code (`Color(light:dark:lightContrast:darkContrast:)`, plan.md:343) | UIColor/NSColor-providers per platform, blind geschreven; de HIG (COL-2, DRK-5) kiest Color Sets | Color Sets in `Assets.xcassets` voor tokens met hoog-contrastvariant, of het bestaande `Color(light:dark:)` (`Theme.swift:18-26`, werkt) uitbreiden en eerst op CI bouwen |
| `fileExporter` met een `ExportDocument` en dynamisch type (plan.md:324) | `FileDocument.writableContentTypes` is statisch; alle types (json, csv, xlsx) moeten erin | noem ze expliciet in de opdracht aan E |
| `navigationDestination(item:)` in een stack met getypt `[Destination]`-pad (plan.md:327) | werkt, maar het item verschijnt niet in `paths`; `popToRoot` en dedupe zien het niet | `SpreadsheetImportPage` als `Destination`-case of `SettingsPage.importReview` |
| `accessibilityChartDescriptor` met `AXChartDescriptorRepresentable` (plan.md:1054, R10) | veel API-oppervlak, alleen op syntaxis gecontroleerd | eerst `accessibilityLabel` met `summary`, descriptor in een tweede stap |
| Eigen assen, `AxisMarks(values:)`, `if` in `AxisContentBuilder` (v3-spec.md:37-39) | bekende valkuilen | CI-gate op `Charts.swift` voordat C, D, A, B2 aansluiten |
| `ListScaffold` met `.listStyle(.insetGrouped)` | iOS-only stijl | `#if os(iOS)` in `ListScaffold` (plan.md:568 noemt het) |
| ViewBuilder-limiet van 10 kinderen | niet te zien met `check_swift`; `BankPage` (SavingsPages.swift:1614, 1622) omzeilt het nu al met twee `Group`s | `scratchpad/count_children.py` (telt lambdas met meer dan 9 statements) als vast onderdeel van elke bouwcontrole |
| Dubbele definities tijdens verhuizingen (`NoticeBanner`, `MonthBar`) | alleen te zien bij een build | zie 4.2 |
| Twee `confirmationDialog`s op dezelfde view in `SheetScaffold` (saveChoices bestaat al, plan.md:590 voegt "Gooi weg" toe) | bij meerdere dialogen op een view werkt in de praktijk soms alleen de laatste | hang de tweede aan een andere subview of gebruik een enkele dialoog met afgeleide inhoud |
| Terugtik op actieve tab (plan.md:60) | oud gedrag (`Router.select` wist het pad, `RootView.swift:84-90`) gaat verloren als `TabView` de selectie niet opnieuw meldt | `Binding(get:set:)` voor `TabView(selection:)` dat bij `new == current` `popToRoot` aanroept, en op een toestel testen |

## 6. (e) HIG-conformiteit

Het plan volgt de HIG-notities op de grote punten: native `TabView` (TAB-5), glas alleen voor bediening (GLS-1/2), gegroepeerde lijsten en swipe-acties (LST-1/3), `ContentUnavailableView` (EMP-1), tekststijlen en AX-stapelen (TYP-1/2), contrast en dubbele kanalen (COL-3/4, CHT-5), Reduce Motion en Transparency (ACC-4, GLS-8). Ik heb de contrastcijfers van par. 4.1 en 4.2 herberekend; ze kloppen (bijvoorbeeld `textSecondary` licht 6,63 op wit en 5,79 op `#EEF1E2`, `chartVariable` licht 3,05).

Tegenstrijdigheden met `hig-notes.md`:

1. **TAB-3** (hig-notes.md:159): "een vierde of vijfde tab alleen als die dagelijks nodig is". K2 zelf rechtvaardigt de tabs naar gebruiksfrequentie, waarbij Plannen "zelden" en Instellingen "beheer" zijn (plan.md:22). Dat spreekt de eigen toets tegen. Verdedigbaar (alternatief: knop op elke tabwortel, wat de audit zelf noemde), maar leg die afweging vast of pas TAB-3 aan.
2. **SID-4** (hig-notes.md:173) en **SET-5** (hig-notes.md:268): geen "Instellingen" in de zijbalk onderaan en instellingen in het App-menu. Plan.md:24 en R13 houden beide ingangen op de Mac "zonder onzekere API". Er is geen onzekere API nodig: laat in `RootView` de vijfde `Tab` onder `#if !os(macOS)` staan. Op de Mac bestaan dan de `Settings`-scene, Cmd+komma en het menu-item (plan.md:753). Dit is geen risico voor de compilatie.
3. **ACC-2** (hig-notes.md:137) en **MAC-9** (hig-notes.md:392): op macOS 28x28 en `controlSize(.regular)`. Plan.md:404 en 575 zetten overal `minTapTarget` 44 en `controlSize(.large)`. Op de Mac worden knoppen en rijen dan onnodig groot. Gebruik `#if os(macOS)` in `Theme.minTapTarget` en `ActionButton`.
4. **GLS-1-uitzondering**: plan.md:407 laat een glazen annotatie bij `chartXSelection` toe als "tijdelijke bediening". De HIG-uitzondering is een interactief element zoals de knop van een schuifregelaar; een tooltip is dat niet. Gebruik `Theme.card` met rand.
5. **SHT-5** (hig-notes.md:203) vraagt bevestiging bij veeg-om-te-sluiten. `interactiveDismissDisabled` verhindert alleen de veeg; de bewaarde documentatie noemt geen terugmelding van een geweigerde poging. Bouw dus alleen: veeg uit bij `hasChanges`, bevestiging bij "Annuleer". Pas principe 6 (plan.md:44) en de componentenregel (plan.md:590) aan.
6. **ACC-7**: "Koersen vernieuwen" op Beleggingen bestaat straks alleen als pull-to-refresh en Cmd+R (F15).
7. **ACT-1** (hig-notes.md:276): K4 houdt het verplichte account; bewust uitgesteld en gedocumenteerd (plan.md:1064). Akkoord, want de vraag was Account los van de rest, niet optioneel.
8. **DRK-3**: het plan houdt `Theme.canvas` (olijftint) naast `Theme.card` = systeemkleur (`#1C1C1E` donker, wit licht). Dat geeft in donker een olijfzwarte pagina met neutraalgrijze kaarten. Controleer in een screenshot of dat bedoeld is; alternatief is een eigen kaartkleur uit dezelfde tint (dan geen systeem-elevatie).

## 7. (f) Is de indeling echt eenvoudiger? Getallen

Bron "nu": audit.md par. 0 en 1.6; bron "plan": plan.md par. 2.2, 2.4, 2.10.

| Maat | Nu | Plan | Opmerking |
|---|---|---|---|
| Tabs | 3 | 5 | +2, Engelse namen weg |
| Pagina's | 18 (+ Instellingen als sheet, + inlog) | 31 (+ inlog) | +72 %; plan.md:138 meldt het zelf (R12) |
| Items op tabwortels | 16 blokken (Home 4, Savings 9, Tools 3) | 16 + 6 instellingsrijen (Overzicht 4, Maand 5 + `MonthBar`, Sparen 2, Plannen 5) | gelijk verdeeld over meer tabs; maximum per wortel 9 naar 5 |
| Maximum blokken op een pagina | 39 (Dag voor dag) | 6 | Dag voor dag heeft 3 blokken plus 28-31 daggedeelten (plan.md:101 telt die "rijen"); zet het standaardfilter op "Alleen met boekingen" |
| Glazen kaarten en knoppen | 115 en 86 | 0 en 0 | |
| Sheetsoorten | 17 (26 plekken) | 9 (met F1-oplossing 11); plan.md:929 staat tot 16 plekken toe | |
| Instellingen | 10 secties, 29 rijen, 3 sheets in de sheet | 4 groepen, 6 rijen, 0 sheets | de enige echte, grote winst |
| Niveaus | "kan eindeloos" | "hooguit 3" (plan.md:42) | onwaar zolang links `NavigationLink(value:)` zijn (F6): Overzicht > Spaarpotten > Spaarpot > Dag voor dag > Salaris is 5 diep |

Taken in tikken, **tot het doelscherm of blad verschijnt, een tabwissel telt als tik**. Plan.md:245-259 neemt de "nu"-kolom van de audit over, die het blad soms meetelt ("kop, chip, sheet"), en telt "straks" zonder blad. Gecorrigeerd:

| Taak | Nu | Plan | Verschil |
|---|---|---|---|
| Instellingen openen | 1 (alleen op een tabwortel) | 1, overal | beter |
| Dag voor dag bekijken | 3 | 2 | -1 |
| Spaardoel berekenen | 3 | 2 (alleen als `GoalsSummaryCard` een spaardoel-rij heeft; anders 4) | -1 |
| Uitgave toevoegen | 3 en scrollen | 3 | geen scrollen meer |
| Back-up maken | 2 en scrollen | 3 | +1, geen scrollen |
| Nieuwe spaarpot | 2 | 2 | gelijk |
| Saldo invullen | 3 | 3 | gelijk |
| Geld verdelen | 1 | 1 | gelijk |
| Spaarpot storten | 2 (Home-tegel, chip) | 3 (Sparen, pot, Storten) | +1 |
| Wachtwoord wijzigen | 2 | 3 | +1 (een pagina in plaats van een sheet) |
| Salaris wijzigen | 2 | 3 | +1 |
| Saldo van een pot of belegging zien | 0 (tegel op Home) | 1 | +1 (zonder F1-oplossing) |

Netto: twee echte winsten in tikken, en winst in scrollen en vindbaarheid door benaming en structuur; vier taken worden een tik langer. "Makkelijker te vinden" komt dus vooral uit de benaming, de vaste paginaopbouw en het wegvallen van scrollen, niet uit minder tikken. Dat is een eerlijke claim; plan.md:245-259 overdrijft hem.

**Uitgaven toevoegen "4 naar 3"** is niet juist: in beide gevallen opent het blad bij tik 3.

**F4 (gedeelde maandstatus).** `Router.focusMonth` en `periodMode` blijven "ongewijzigd" (plan.md:195). `PeriodControl` (`Components.swift:414-466`) bladert met `shiftPeriod`, wat `focusMonth` met `periodMode.stepMonths` verschuift (12 bij "Jaar"). Het Overzicht (tab 1, kaart `flow`) en `MonthBar` op de Maand-pagina's (tab 2) lezen dezelfde `focusMonth`. Wie op het Overzicht een jaar terugbladert, ziet daarna op de tab Maand "Inkomen" van een jaar eerder zonder dat iets dat meldt. Het Overzicht en de Maand-tab tonen bovendien dezelfde vier getallen (Nog te verdelen, Inkomen, Uitgaven, Verdeeld) in hero en kaarten. Dat is het patroon E2/H1 uit de audit (zelfde getal op meer plekken), verplaatst van binnen een tab naar tussen twee tabs.

Voorstel: **Overzicht = nu** (hero, `wealth`, favorieten, `upcoming`; geen periodekeuze) en **Maand = door de tijd** (`MonthBar`, daaronder `flow` met `PeriodControl`, dan de vijf kaarten). Dan heeft `periodMode` één plek, en is de hero de enige "nu"-weergave. Anders: aparte `overviewFocus` en `monthFocus`.

## 8. (g) Eerder expliciet gevraagde functies

| Functie | Plan | Oordeel |
|---|---|---|
| **K9: 3 zelfgekozen potten op Home** (README.md:7: "plus 3 potten die je zelf kiest"; `HomeView.swift:489` limiet 3; `PotsBlock`: tegels, `EmptySlotTile`, chip "Kies potten") | vervalt (plan.md:30, 148, 790) | **schending, F1** |
| Gekozen beleggingen op Home (limiet 4, `HoldingPickerSheet`, `InvestBlock` met tegels) | vervalt | **schending, F1** |
| **K8: blokvolgorde** (README.md:11; `BlockOrder.swift`) | blijft; menu "Volgorde aanpassen", Instellingen > Indeling, contextmenu (plan.md:200-211) | blijft; opgeslagen volgorde gaat verloren (F12) |
| **K4: account verplicht** | blijft; Account is een eigen pagina | geen verlies. Eerste start vraagt nog steeds een lokaal account met wachtwoord, ook zonder cloud (HIG ACT-1, bewust uitgesteld) |
| **Dag voor dag** | segment van Bankrekening; kaart `days` op de Maand-tab (2 tikken) | bereikbaar. Inhoud van een dagsectie niet gespecificeerd (zie F3) |
| **Bankrekening per dag** (saldo bank en potten per dag, grafiek, laagste punt, waarschuwing) | dagsecties, `DayBalanceTrend`, `BankLowPointNotice` | bereikbaar, mits elke dagsectie bank- en potsaldo toont (nu `DayBalanceRows`/`DayFlowTiles`, `CashflowPages.swift:171, 192`); neem dat expliciet op |
| **Maandsluiting bank en potten** (sluitend overzicht) | vervalt | **verlies, F3** |
| **Aankoopcheck** | wizard "ongewijzigd" (plan.md:135) | blijft |
| **Versnellers** toepassen en herstellen | `AcceleratorsSection` blijft in Doel en op Versnellers; bevestiging sluit met een knop | blijft; test dat "Herstel" bereikbaar is bij 0 doelen en bij meerdere doelen |
| **Toekomstschatting** | uitkomst, verloop, uitgangspunten, streefbedrag | blijft; horizon-invoer zichtbaar houden (F15) |
| **Buffer** | `BufferPage` als "Noodbuffer", pot aanmaken, minimumsaldo op Bankrekening | blijft |
| **Doelen** | schakelaar weg; Spaardoel berekenen als eigen pagina; versnellers per doel | blijft |
| **Excel-import** | `SpreadsheetImportSheet` wordt `SpreadsheetImportPage` via `navigationDestination(item:)` | blijft, risico in 5.3 |
| **Firebase-synchronisatie** | logica ongewijzigd; alerts bij start vervangen door `SyncAttentionBanner` en Account | blijft; zie F15 voor zichtbaarheid |
| **Salaris elke N weken of dagen** | `SalaryPage` met drie schema's, eerste uitbetaling, "Salarisdag zonder uitbetaling", volgende vier data | blijft, maar twee tikken dieper dan het maandsalaris zelf (3) |
| **Percentage-inleg** | `AllocationRow` op Verdelen, `ContributionFields` in `PotEditSheet` en `HoldingEditSheet`, `percentWarning` in de hero | blijft, mits F9 |
| **Terugkerend met reikwijdte** (alleen deze maand of ook volgende) | `MoneyLineSheet(saveChoices:)` en verwijderdialoog; scenario 3 (plan.md:1012) | blijft; delete via swipe moet nog steeds dezelfde dialoog tonen |

### 8.1 F1: oplossing

Niets in de HIG eist het verwijderen. De pickers zijn korte keuzebladen met Annuleer en Bewaar (SHT-1) en dus toegestaan. De audit (E16, audit.md:592) stelde "de drie grootste potten en beleggingen met een link 'Alle'" voor, niet het schrappen van de weergave; plan.md:30 gaat verder dan zijn bron. De reden "Sparen toont alle potten en beleggingen" klopt bovendien niet met tabel 2.4: de tab Sparen bevat alleen `PotsSummaryCard` en `PortfolioSummaryCard` zonder dat is vastgelegd dat die potten tonen. `homePots()` (`Pots.swift:463`) en `homeHoldings()` (`Invest.swift:290`) hebben eigen tests (`PotsAndBankTests.swift:130`, `InvestTests.swift:139`) en zouden zonder scherm blijven staan.

Voorgestelde besluiten (vervangt K9):

- **K9a.** `homePotIDs` en `homeHoldingIDs` blijven functioneel. Het Overzicht (de opvolger van Home) krijgt twee kaarten `pots` en `invest` met de gekozen potten (max 3) en beleggingen (max 4) als compacte tegels (`PotMiniTile`, `HoldingTile` herbouwd met `Card`, `ProgressMeter`, geen `.rounded`, geen `minimumScaleFactor`).
- **K9b.** `PotPickerSheet` en `HoldingPickerSheet` blijven als korte sheets (`SheetScaffold`, `hasChanges`), nu met C als eigenaar; ze verhuizen van `HomeView.swift` naar `PotPages.swift` en `PortfolioPages.swift` (pas tabel 6.6 aan). Ze worden geopend vanuit de kaart (menu "Kies potten") en vanuit `PotsPage`/`PortfolioPage` (werkbalkmenu), niet meer als chip.
- **K9c.** `PotsSummaryCard` en `PortfolioSummaryCard` op Sparen tonen dezelfde gekozen tegels plus totaal en een link "Alle spaarpotten" / "Alle beleggingen".
- **K9d.** Het Overzicht heeft dan: hero, `flow` (of, volgens F4, naar Maand), `wealth`, `pots`, `invest`, `upcoming` = hero plus vijf, binnen de grens van zes. Met de F4-verplaatsing van `flow` naar Maand blijven vier kaarten over.
- **K9e.** Sheetsoorten: 11 in plaats van 9 (par. 7).

Dit herstelt ook de weergave van saldi zonder tik op de eerste tab (par. 7, laatste regel). De lege plek-tegel (`EmptySlotTile`, "Kies pot") blijft nodig zolang er minder dan drie potten gekozen zijn; behoud hem in de kaart.

## 9. Uitwerking van de overige majeure bevindingen

### F2. Compileer-oordeel per golf

- Maak golf 0 compileerbaar: 0B levert tijdelijke `OverviewTab/MonthTab/SavingTab/PlanningTab` die de bestaande `HomeView`/`SavingsView`/`ToolsView`-inhoud hergebruiken, en laat `Router` tijdelijk de oude padnamen als doorverwijzing houden. Dan bouwt na golf 0 de hele app met `TabView` en kan CI dat bevestigen.
- Voeg een poort toe: na elke golf, en na elk pakket in golf 1, push naar `claude/...` en lees de CI-uitvoer (`mcp__github__actions_*`, `get_job_logs`). Voor golf 1: per pakket een eigen commit, zodat een fout aan een pakket te koppelen is.
- Zet `scratchpad/count_children.py` en een bijgewerkte stub-typecontrole als snelle voorcontrole in 6.1 (niet als vervanging).
- Pas R1 aan: "een build in Xcode 26" wordt "CI-build groen na elke golf".

### F3. Maandsluiting

Behoud `CashflowBankBlock` en `CashflowPotsBlock` als uitklappers (`DisclosureGroup`) "Zo komt je saldo tot stand" in het segment Dag voor dag (bank) en onder het verloop in `PotsPage` of Dag voor dag (potten), met dezelfde `CashflowSummary.bankRows`/`potsRows` en `LedgerLineRow`. Dat kost B2 geen nieuwe logica. Specificeer in plan.md:124 wat een dagsectie toont: titel met weekdag, gebeurtenissen (`DayEventRow`), bank- en potsaldo aan het eind van de dag, overgeschreven bedrag.

### F5. Beleggingen

- Er is geen invoer voor de startmaand: `HoldingEditSheet` kent geen `startMonth` en maakt `Holding(name: "", startMonth: store.now)` (`PortfolioPages.swift:682`). C1 rekent het afgeleide beginpunt op `startMonth` (plan.md:619), dus een door de gebruiker ingevulde belegging krijgt altijd een beginpunt in de huidige maand: een stip plus 12 maanden verwachting, nooit geschiedenis. Voeg "Belegd sinds" (maandkiezer, `Holding.startMonth` bestaat al in het model, dus geen nieuw `Codable`-veld) toe aan C's opdracht en aan scenario 11.
- "Huidige waarde" staat nu alleen bij nieuw en zonder ticker (`PortfolioPages.swift:494`). C voorziet de uitbreiding (plan.md:790); neem op dat het veld ook bij wijzigen een bestaand meetpunt bijwerkt (C9).
- De afgeleide lijn heeft waarde gelijk aan ingelegd (plan.md:619): winst is altijd 0 en "Winst/Rendement" wordt daarom verborgen (C2). Zeg dat in het onderschrift ("Geschat uit je inleg, zonder rendement"), zodat de lijn niet als werkelijke groei wordt gelezen.
- **Controle van het gemelde geval.** Alle bewijs is een Core-model plus tests; de SwiftUI-component die de gebruiker ziet, wordt nergens uitgevoerd. De CI heeft screenshots (`-mybuddy-demo`), maar de voorbeelddata heeft zes meetpunten per belegging en toont het gemelde geval dus niet. Voeg aan `DebugLaunch` (0B) een scenario toe: `-mybuddy-demo-holding-only-invested` (een belegging met alleen Totaal ingelegd en Inleg per maand) en een screenshot van de Beleggingen-pagina in `ci-screenshots.sh`.

### F6. Navigatie

`NavigationLink(value:)` voegt aan het padbinding toe zonder `Router.open` aan te roepen; alle kaarten, rijen en links in 0A zijn zo gebouwd (plan.md:478-481, 491). De dedupe in `NavigationRules.push` (plan.md:192, R15) geldt dus alleen voor handmatige `router.open`-aanroepen. Normaliseer in de `set` van `pathBinding(for:)`: elke wijziging gaat door `NavigationRules.normalize`, dat afkapt bij een bestemming die al in het pad staat. Test dat in `NavigationRulesTests`.

Leg ook vast wat "tab van een pagina" betekent: `open` duwt op de huidige tab (plan.md:192), dus Spaarpot kan zowel onder Overzicht als onder Sparen staan. Kies: links naar een pagina van een andere tab (`destination.tab != router.tab`) gebruiken `router.go`; anders `open`. Dan klopt "uit elkaar houden", en "hooguit drie niveaus" (tab, pagina, detail) wordt waar voor 95 % van de paden. Anders: schrap de zin.

### F8. Contract

Zie 4.2 en 4.5. Voeg bovendien toe: de "kern" van elke tabroot (hero, `MonthBar`) is geen blok (plan.md:211), maar `OrderedBlocks` kent alleen blok-id's; leg vast hoe de kern buiten `OrderedBlocks` blijft.

### F9. `List` voor formulierrijen

K6 (plan.md:27) maakt alle pagina's "met rijen die je wijzigt" een `List`. `AllocationRow` (`SavingsPages.swift:1260-1371`) is een mini-formulier per pot: segment Bedrag/Percentage, bedragveld, grondslag, "= bedrag", bijschrift, "Afwijkend", twee knoppen. In een `List`-rij leveren meerdere knoppen zonder `.buttonStyle(.borderless)` het bekende probleem op dat een tik meerdere acties activeert, en `TextField`-focus in een rij met swipe-acties is kwetsbaar. Die rijen zijn de nieuwste functie (percentage-inleg). Houd `DistributePage` en `SalaryPage` `PageScaffold` met `Card` per pot of belegging (rekenpagina, plan.md:85), gebruik `List` alleen voor `MoneyLinesSection`, Geschiedenis, Potten en Beleggingen. Voeg aan B1's DoD toe: handmatige scenario's met percentage-inleg, "Afwijkend", "Terug naar standaard", "Maak dit je standaard".

## 10. Kleine bevindingen

- **F10, F11**: zie par. 6.
- **F12 (blokvolgorde).** `BlockPage` krijgt nieuwe sleutels (`overview`, `month`, `saving`, `planning`); een opgeslagen volgorde onder `home`, `savings`, `tools` wordt genegeerd (plan.md:211). Schrijf `BlockOrderMigration.migrate(_:)` (Foundation-only, getest): `savings.[income, bank, distribute]` naar `month`, `savings.[pots, portfolio]` naar `saving`, `savings.[buffer, goals]` en `tools.*` naar `planning`, `home.[pots, invest]` naar `overview` (bij K9a). Houd de relatieve volgorde. Sparen (2 blokken) en een enkel-blokspagina ordenen is overbodig; verberg "Volgorde aanpassen" op pagina's met minder dan drie blokken.
- **F13**: zie par. 6.
- **F14.** `SignedInRoot` krijgt `.id(user.uid)` met `.transition(.opacity)` (`MyBuddyApp.swift:89-98`): bij een accountwissel leven oud en nieuw tegelijk en is de volgorde van `onDisappear` en `onAppear` niet gegarandeerd. Een `clear()` van het oude scherm wist dan de registratie van het nieuwe. Gebruik `unregister(store:)` dat alleen wist als de geregistreerde store dezelfde instantie is. Het `Settings`-scene heeft ook zelf `auth` en `cloud` nodig; die staan op `MyBuddyApp`, niet in `ActiveSession`.
- **F15.** (a) `SyncAttentionBanner` staat alleen op het Overzicht; een openstaand conflict verdwijnt dus uit zicht op de andere tabs. Geef de Instellingen-tab een `badge` (iOS 16/macOS 13, TAB-8 staat kritieke meldingen toe) zolang er een conflict of uploadaanbod is. (b) Neem "Koersen vernieuwen" op in het werkbalkmenu van Beleggingen. (c) Noem "Hoe ver kijk je vooruit?" als zichtbaar blok in plan.md:134.
- **F16.** Maak de zoekindex (plan.md:243) een Foundation-only `SearchIndex` met een uitputtende test dat elke `Destination`- en `SettingsPage`-case een naam en alternatieve termen heeft. Zoeken staat nu alleen op het Overzicht; dat is het enige zoekveld (SRC-1), maar vermeld in de lege staat van de andere tabs hoe je het vindt, of plaats `Tab(role: .search)` (plan.md:1064 schuift dat door).
- **F17**: zie par. 7.
- **F18.** `-mybuddy-scroll` werkt alleen via `.offset` in `PageScaffold` (`Components.swift:26-28`); `List`-pagina's negeren het, dus screenshots van lange `List`-pagina's (Dag voor dag) mislukken. Voeg `ScrollViewReader`/`scrollTo` voor `ListScaffold` toe. `README.md` (tabellen, regel 7-11), `system_architecture.md:8` en `docs/v3-spec.md:126-140` moeten mee; G heeft de eerste twee al, de derde niet.

## 11. Voorgestelde aanpassingen aan het plan

1. Vervang K9 door K9a t/m K9e (par. 8.1); pas 2.4 (Overzicht, Sparen), 2.5, 6.4 A en C, 6.6 en 8.1 aan.
2. Verplaats `flow` en de `PeriodControl` naar de Maand-tab (F4) en laat het Overzicht "nu" zijn.
3. Voeg K15 toe: `CashflowBankBlock` en `CashflowPotsBlock` blijven als uitklappers (F3), en specificeer de dagsectie.
4. Voeg K16 toe: pad-normalisatie in `pathBinding.set` en `go` voor links naar een andere tab (F6).
5. Voeg aan C toe: "Belegd sinds" in `HoldingEditSheet`, onderschrift van de afgeleide lijn, `DebugLaunch`-scenario en screenshot (F5).
6. Maak golf 0 compileerbaar met tijdelijke tabroots; voeg CI-poort per golf en per pakket toe; werk met `git worktree` per pakket (F2, F7).
7. Laat `NavigationModel.swift` (met tests) als stap 0 landen; houd 0A, 0B en F beschikbaar voor een WIRING-ronde na golf 1 (F7).
8. Breid het contract uit met de bevroren lijst uit 4.2 en met signatuur-regexen in `contract-check.sh` (F8).
9. Houd `DistributePage` en `SalaryPage` `PageScaffold` met kaarten (F9).
10. Mac: geen Instellingen-tab onder `#if os(macOS)`, `minTapTarget` en `controlSize` per platform (F10, F11).
11. Schrap of verzwak de claims: "veeg-om-te-sluiten vraagt bevestiging", "hooguit drie niveaus", de tikkentabel 2.10 (F13, F6, F17).
12. Voeg `BlockOrderMigration` toe (F12), `unregister(store:)` (F14), `badge` op Instellingen (F15) en `SearchIndex` met test (F16).
13. Wijs `.github/workflows/ci.yml`, `system_architecture.md`, `implementation_plan.md`, `task.md` aan G toe.

## 12. Wat ik niet kon vaststellen

- Hoe `TabView` met `.sidebarAdaptable` en een `NavigationStack` per tab zich werkelijk gedraagt (terugtik, zijbalkbreedte bij 640 pt, state bij wissel van zijbalk naar balk). Geen SwiftUI hier.
- Of alle stap-tellingen in par. 7 op een toestel kloppen; ze zijn afgeleid uit de code.
- Of de stub-typecontrole na onderhoud betrouwbaar genoeg is; ik heb alleen vastgesteld dat hij verouderd is en wat er ontbreekt.
- Of de CI-runner `macos-26` nog beschikbaar is en hoe lang een bouwronde duurt; het workflowbestand zegt dat het draait bij elke push op `claude/**`.
- De exacte inhoud van `GoalsSummaryCard` (heeft hij een spaardoel-rij?), waar plan.md:255 op leunt.
