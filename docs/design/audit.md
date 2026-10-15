# UI-audit MyBuddy

Peildatum 15 oktober 2026, code-stand commit `ca0c945` (`App/` en `CoreTests/` zijn niet aangepast). Alleen gelezen en geteld.
Regelnummers zijn die van deze stand; een ander herstelwerk kan ze later laten schuiven. HIG-regel-id's (TYP-1, GLS-1, ...) verwijzen naar
`docs/design/hig-notes.md`. Bewijs voor de getallen staat achterin (par. 6).

## 0. In cijfers

| Onderdeel | Aantal |
|---|---|
| Tabs | 3 (Home, Savings, Tools) |
| Pagina's | 18: 3 tabwortels + 15 paginatypen (`Destination` heeft 17 cases, 2 daarvan zijn aliassen: `.expenses` opent `BankPage`, `.savingsGoal` opent `GoalsPage` met de calculator open) |
| Schermen buiten de navigatie | Inlogscherm (`AuthView`), Instellingen (sheet) |
| Sheets | 17 soorten op 26 plekken (`.sheet(`); daarnaast 4 bestandsdialogen, 2 alert-bronnen, 17 bevestigingsdialogen |
| Inhoudsblokken | 103 (91 `GlassBlock(` + 12 `LinkedBlock(`), plus 12 losse glaskaarten (`.glassCard(`, waaronder de tabbalk en de inlogkaart) = 115 glazen kaarten |
| Knoppen als glazen capsule (77 `ChipButton`, 6 `ChipLink`, 3 los `ChipLabel`) | 86 |
| Tegels (`StatTile`, `.tile()`) | 85 `StatTile`, 38 `.tile()` |
| Grafieken | 8 soorten op 17 plekken |
| Vaste teksten in de UI | 293, waarvan 59 langer dan 120 tekens en 9 langer dan 220 tekens |
| `TabView` / `List` in een pagina / `swipeActions` / `ContentUnavailableView` | 0 / 0 / 0 / 0 |
| `contextMenu` | 1 (volgorde van blokken) |
| `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `.commands`, `Settings {}`, `keyboardShortcut`, `.help(`, `sensoryFeedback`, `.searchable`, `hoverEffect`, `horizontalSizeClass`, `presentationSizing`, TipKit, `undoManager` | 0 |
| Vaste lettergrootte (`.font(.system(size:))`) | 5 |
| `minimumScaleFactor` | 49 |
| `ViewThatFits` / `isAccessibilitySize` | 1 / 0 |
| Toegankelijkheidsmodifiers in totaal | 33 (waarvan 0x `.isHeader`) |
| Grafiektypen met een toegankelijkheidslabel | 2 van 8 |

---

## 1. Inventaris

### 1.1 Opbouw

- `MyBuddyApp.swift:20-41`: `Window("MyBuddy")` op macOS (een venster, minimum 480x640, standaard 860x920), `WindowGroup` elders.
- `AppRoot` (`MyBuddyApp.swift:67-104`): toont `AuthView` zolang er geen (cloud of lokaal) account is, anders `SignedInRoot` (eigen `AppStore`, `Router`, `SyncController`). **Zonder account is de app dus niet te gebruiken.**
- `RootView.swift:9-82`: `VStack { tabContent; GlassTabBar }` met mesh-achtergrond. Twee sheets: Instellingen (`:26`) en Volgorde aanpassen (`:27`). Achtergrondtaken: koersen ophalen (`:28`), klok elke minuut (`:30`, `:69-81`), maandwissel (`:39`).
- `Router.swift:50-101`: drie navigatiepaden (`homePath`, `savingsPath`, `toolsPath`), `showSettings`, `orderPage`, en twee **globale** keuzes `focusMonth` en `periodMode` die door alle Savings-pagina's worden gedeeld. `select` (`:66-73`) wist het pad van de gekozen tab, ook bij wisselen van een andere tab. `open` (`:77-83`) voegt toe aan het pad van de tab waar je nu bent en voorkomt alleen een dubbele bovenaan.
- Elke tab heeft een eigen `NavigationStack` met `navigationDestination(for: Destination.self)` (`HomeView.swift:35`, `SavingsView.swift:22`, `ToolsView.swift:16`): **elke pagina kan in elke tab openen**, en er is geen diepteregel (Spaarpot > Dag voor dag > Spaarpot > ... kan eindeloos).
- `PageScaffold` (`Components.swift:6-45`): ScrollView, paginabrede mesh-achtergrond, grote titel op alle 21 aanroepen, tandwiel alleen op de 3 tabwortels (`showsSettings`, `:35-43`).
- Blokvolgorde per tab (Home, Savings, Tools) is door de gebruiker aanpasbaar via lang indrukken (`BlockOrder.swift`); opgeslagen in `AppSettings.blockOrder`.

### 1.2 De drie tabs

**Tab Home** (`HomeView.swift:5-49`, titel "Home", tandwiel). Standaard 4 kaarten, bij een lege start een welkomstblok erbij, tot 2 meldingen.

| Onderdeel | Toont | Tik / actie |
|---|---|---|
| Meldingen (`:14-27`) | opstartmelding, "Opslaan is mislukt" met "Opnieuw proberen" | knop |
| Welkom (`:76-109`, alleen lege start) | uitleg + chips "Salaris instellen", "Voorbeelddata" | naar Salaris & inkomsten; dialoog "Voorbeelddata laden?" |
| Nog te verdelen in <maand> (`RemainingHeader`, `:113-183`) | groot bedrag, 3 mini-tegels Inkomen / (Bank)uitgaven / Verdeeld, salarisnotitie, uitleg bij pot-uitgaven, afrondingsnotitie, waarschuwing | hele kaart naar Verdelen |
| Overzicht (`OverviewBlock`, `:224-250`) | FlowChart 6 maanden zonder assen, legenda, tegels "Vermogen eind <maand>" en "Over deze maand" | hele kaart naar Overzicht (huidige maand) |
| Spaarpotten (`PotsBlock`, `:254-283`) | subtitel "Totaal <bedrag>", tegels Totaal gespaard / Totaal doel, voortgangsbalk, 3 potten of "Kies pot"-tegels | alleen de kop naar Spaarpotten; pottegel naar Spaarpot; chip "Kies potten" (sheet); leeg: EmptyHint "Nieuwe spaarpot" (sheet) |
| Beleggingen (`InvestBlock`, `:383-424`) | waarde, winst/verlies, lijngrafiek 110 pt, 2x2 beleggingstegels | alleen de kop naar Beleggingen; tegel naar Belegging; chip "Kies beleggingen" (sheet); leeg: EmptyHint |

Binnen die 4 kaarten staan 14 tegels (3 `MiniFigure`, 4 `StatTile`, 3 `PotMiniTile`, 4 `HoldingTile`) en 2 grafieken.

**Tab Savings** (`SavingsView.swift:6-41`, titel "Savings", tandwiel). Periodekaart (Maand / Half jaar / Jaar met vorige/volgende) en daarna 8 blokken (standaardvolgorde `BlockOrder.swift:39-49`). Samen 9 kaarten.

| # | Blok | Toont | Tik naar |
|---|---|---|---|
| 1 | Overzicht (`PeriodBlock`, `:45-74`) | tegels Inkomen / Uitgaven / Over, FlowChart, legenda | Overzicht |
| 2 | Salaris & inkomsten (`IncomeBlock`, `:78-110`) | groot bedrag, tegels Salaris / Overig, schemazin | Salaris & inkomsten |
| 3 | Bankrekening (`BankBlock`, `:189-246`) | saldo, toelichting, tegels Vast / Variabel / Over | Bankrekening |
| 4 | Verdelen (`DistributeBlock`, `:114-145`) | nog te verdelen, balk, Gespaard / Belegd | Verdelen |
| 5 | Spaarpotten (`PotsSummaryBlock`, `:149-185`) | totaal, 3 potrijen | Spaarpotten |
| 6 | Buffer (`BufferBlock`, `BufferPages.swift:15-66`) | doelbuffer, balk, "Nu", "Dekt" | Buffer |
| 7 | Beleggingen (`PortfolioBlock`, `:251-280`) | waarde, winst, lijngrafiek 90 pt | Beleggingen |
| 8 | Doelen (`GoalsHubBlock`, `GoalPages.swift:8-72`) | tot 2 levensdoelen met balk, spaardoel-rij | Doelen (of Spaardoel als er alleen een berekening is) |

De periodekeuze bovenaan geldt alleen voor blok 1 t/m 4. Blok 5 t/m 8 tonen "nu" en negeren hem.

**Tab Tools** (`ToolsView.swift:5-30`, titel "Tools", tandwiel). 3 blokken:

| # | Blok | Toont | Tik naar |
|---|---|---|---|
| 1 | Versnellers (`:70-111`) | tot 3 versnellers voor het eerste doel | Versnellers |
| 2 | Toekomstschatting (`:34-66`) | tegels "Over 5/10/20 jaar", regel met aannames | Toekomstschatting |
| 3 | Aankoopcheck (`PurchasePages.swift:44-90`) | uitleg, tegel "Je uurloon" | Aankoopcheck |

### 1.3 Pagina's (per `Destination`)

Tikken zijn geteld vanaf Home (de startpagina), een tabwissel telt als tik. "Kaarten" zijn glazen blokken/kaarten die op de pagina staan.

**P1. Overzicht** (`OverviewPage`, `SavingsPages.swift:5-130`; titel "Overzicht"). Ingangen: Home-blok Overzicht (1 tik, huidige maand), Savings-blok Overzicht (2 tikken, gekozen periode), kop "Je overzicht" op Dag voor dag.
6 kaarten: (1) periodekeuze; (2) "Over deze maand / Over <periode>" met uitleg en pot-uitgaven; (3) "Cijfers": 6 tegels (Inkomen, Uitgaven, Gespaard, Belegd, Over, Gemiddeld over per maand), verwachtingsnotitie, afrondingsnotitie, blok "Klopt met je dagoverzicht" met chip "Per dag bekijken"; (4) "Per maand": FlowChart 200 pt met assen en legenda; (5) "Vermogen": groot bedrag, lijngrafiek, 3 rijen die doorlinken naar Bankrekening / Spaarpotten / Beleggingen; (6) "Maand voor maand": lijst met per maand Over, inkomen en uitgaven. Geen sheets.

**P2. Salaris & inkomsten** (`IncomePage`, `SavingsPages.swift:221-586`). Ingangen: Savings-blok (2 tikken), welkomstblok (1), Dag voor dag (rij Inkomen en salarisgebeurtenis).
5 kaarten met 15 tot 25 bedieningselementen: (1) "Standaard salaris": Vast of Uurloon, bedrag of uurloon + uren per week, formule, tegels, uitleg; (2) "Wanneer krijg je salaris?": 3 keuzerijen (maandelijks, om de zoveel weken, om de zoveel dagen), dag of interval, datum, schakelaar "Dit is mijn eerste uitbetaling", "Salarisdag zonder uitbetaling", volgende 4 data, waarschuwing; (3) maandkiezer; (4) "Salaris deze maand": uitbetalingen, tegels Salaris / Overig / Inkomen, schakelaar "Afwijkend bedrag" of "Andere uren", chip "Dag voor dag bekijken"; (5) "Overige inkomsten" (`MoneyLinesBlock`): lijst, "Toevoegen", per rij menu Wijzig / Verwijder. Sheets: `MoneyLineSheet`; dialoog "alleen deze maand of ook volgende" bij terugkerende regels.

**P3. Bankrekening** (`BankPage`, `SavingsPages.swift:1605-1634`; ook bereikbaar als `.expenses`). Ingangen: Savings-blok (2 tikken), rij Bankrekening op Overzicht, rij Uitgaven op Dag voor dag. **Hier staan ook alle uitgaven.**
8 vaste + 4 voorwaardelijke kaarten, in deze volgorde: (1) "Saldo nu" (`BankBalanceBlock`, `:1639`): saldo, tegel "Eind van <maand>", uitleg, 5 chips (Geld storten, Geld opnemen, Naar spaarpot, Van spaarpot, Saldo invullen); (2) waarschuwing onder nul of buffer (`BankLowPointNotice`, `CashflowPages.swift:325`, voorwaardelijk); (3) maandkiezer; (4) "Per dag" (`BankDayBlock`, `CashflowPages.swift:363`): dagkiezer, saldo einde dag, tegels, gebeurtenissen, saldo bank en potten, grafiek "Saldo per dag" met keuze 30 dagen of maand, tegels Laagste saldo / Saldo op het eind; (5) "Komende 14 dagen" (`:542`) met chip "Alle dagen bekijken"; (6) "Binnen en eruit" (`BankFlowBlock`, `:1694`): verdeelbalk, 9 rijen, eindsaldo, chips "Standaard uitgaven invullen", "Geld verdelen", "Dag voor dag"; (7) "Vaste uitgaven" (`MoneyLinesBlock`); (8) "Variabele uitgaven" (`MoneyLinesBlock`); (9) "Overschrijvingen" (`:1822`, kop naar Verdelen); (10) "Verwacht verloop" (`:1920`, lijngrafiek, voorwaardelijk); (11) "Bankbuffer" (`:1938`, voorwaardelijk): 2 tegels, invulveld maanden, uitleg, chip "Buffercalculator"; (12) "Geschiedenis" (`:1966`, voorwaardelijk): tot 40 rijen met menu Verwijder.
Sheets: `BankActionSheet` (5 acties), `MoneyLineSheet`; dialoog bij verwijderen van een gekoppelde boeking.

**P4. Verdelen** (`DistributePage`, `SavingsPages.swift:1371-1574`). Ingangen: Home-kaart "Nog te verdelen" (1 tik), Savings-blok (2), chip op Bankrekening, kop Overschrijvingen, chip "Verdelen" op Spaarpot en Belegging, rij op Dag voor dag (7 ingangen).
5 kaarten: (1) maandkiezer; (2) "Nog te verdelen": groot bedrag, balk, tegels Inkomen / Uitgaven / Verdeeld, waarschuwingen, uitleg over percentages, 3 chips (Standaardverdeling, Rest over potten, Alles op nul); (3) "Overschrijfdag": dagkiezer + 2 uitlegteksten; (4) "Spaarpotten": per pot een rij (`AllocationRow`: Bedrag of Percentage, veld, grondslag, "= bedrag", bijschrift, "Afwijkend", chips "Terug naar standaard" en "Maak dit je standaard"); (5) "Beleggen": zelfde rijen per belegging. Kopjes (4) en (5) linken naar Spaarpotten en Beleggingen.

**P5. Spaarpotten** (`PotsPage`, `PotPages.swift:43-99`). Ingangen: Home-kop (1 tik), Savings-blok (2), Overzicht, Verdelen, Dag voor dag (6).
1 + N kaarten: "Totaal gespaard" (groot bedrag, 3-4 tegels: Inleg deze maand, Eind <maand>, Rente dit jaar, Aantal potten), `PotRowCard` per pot (naam, saldo, voortgang, rente-badge, inlegregel), chips "Nieuwe spaarpot" en "Kies potten voor Home". Sheets: `PotEditSheet`, `PotPickerSheet`.

**P6. Spaarpot** (`PotDetailPage`, `PotPages.swift:199-735`). Ingangen: Home-tegel (1 tik), Spaarpotten, Dag voor dag, resultaat van de spaardoel-calculator.
7 kaarten + 1 verwijderknop: (1) "Saldo" (ring, bedrag, doel, planning); (2) "Komende boekingen" (30 dagen, tegels, rijen, chip "Dag voor dag bekijken"); (3) "Geld bewegen" (4 chips); (4) "Inleg" (tegels, uitleg, chips "Doel en instellingen" en "Verdelen"); (5) "Rente" (tegels, chip "Rente aanpassen" of "Rente instellen"); (6) "Saldo op datum" (datumkiezer, tegels, 4 snelkeuzes); (7) "Waar is het geld heen gegaan?" (geschiedenis, "Toon alle n boekingen", menu Verwijder per rij). Sheets: `PotEntrySheet` (4 acties), `PotEditSheet` (5 secties); dialogen voor verwijderen pot (2-3 keuzes) en boeking.

**P7. Beleggingen** (`PortfolioPage`, `PortfolioPages.swift:5-121`). Ingangen: Home-kop (1 tik), Savings-blok (2), Overzicht, Verdelen, Dag voor dag.
3-4 kaarten (+ melding): (1) "Waarde" (bedrag, winst, 3 tegels, uitleg 3 regels, koersstatus, chip "Koersen vernieuwen"); (2) "Groei" (keuze 6 mnd / 1 jaar / 3 jaar, lijngrafiek 190 pt); (3) "Verdeling" (donut, alleen bij meer dan 1 soort); (4) "Mijn beleggingen" (rijen, chips "Toevoegen", "Kies voor Home"). Pull-to-refresh. Sheets: `HoldingEditSheet`, `HoldingPickerSheet`.

**P8. Belegging** (`HoldingDetailPage`, `PortfolioPages.swift:177-375`). Ingangen: Home-tegel (1 tik), Beleggingen, Dag voor dag.
4-5 kaarten + verwijderknop: (1) soort-blok (waarde, winst, Ingelegd, Rendement, Aantal, Koers, chip "Koers vernieuwen"); (2) grafiek "Koers laatste jaar" (netwerk) of "Waarde"; (3) "Uitgangspunten" (tegels, chips "Instellingen" en "Waarde bijwerken" of "Historie aanvullen"); (4) "Inleg" (chips "Inleg aanpassen", "Verdelen"); (5) "Meetpunten" (24 rijen met menu). Sheets: `HoldingEditSheet`, `ValueUpdateSheet`.

**P9. Toekomstschatting** (`ProjectionPage`, `ProjectionPage.swift:5-231`). Ingang: Tools-blok (2 tikken). 5 kaarten: "Hoe ver kijk je vooruit?" (veld, eenheid, 5 snelkeuzes), "Uitgangspunten" (4 velden, schakelaar, chip "Gebruik mijn beleggingen"), "Verwachte waarde" (bedrag, 3 scenario's), "Verloop" (grafiek 3 lijnen), "Streefbedrag".

**P10. Doelen** (`GoalsPage`, `GoalPages.swift:223-291`; `SavingsGoalCalculator`, `SavingsGoalPages.swift:27-518`). Ingang: Savings-blok (2 tikken), `.savingsGoal` alleen als er geen doel maar wel een berekening is. Bovenaan een kaart met schakelaar "Mijn doelen | Spaardoel".
Onderdeel Mijn doelen: `GoalCard` per doel of EmptyHint, en blok "Nieuw doel" (4 doelsoorten + "Spaardoel berekenen").
Onderdeel Spaardoel (calculator) heeft 8 kaarten, waarvan 5 afhankelijk van de invoer: "Uitkomst", "Je spaardoel", "Rendement", "Wat als ik meer inleg?", "Verloop" (grafiek), "Ingelegd en rente", "Per jaar" (tabel), "Bewaar dit doel" (chips "Maak er een spaarpot van" en "Maak er een doel van"). De invoer staat alleen op dit apparaat (`@AppStorage`).
Sheet: `GoalEditSheet`.

**P11. Doel** (`GoalDetailPage`, `GoalPages.swift:338-509`). Ingang: Doelen > doel (3 tikken). 4 kaarten + verwijderknop: type-blok (ring, benodigd bedrag, haalbaarheid), "Zo is het berekend" (4 tegels, chip "Doel aanpassen"), "Versnellers" en "Toegepast" (`AcceleratorsSection`, dezelfde onderdelen als pagina P12). Sheets: `GoalEditSheet`, `AcceleratorApplySheet`.

**P12. Versnellers** (`AcceleratorsPage`, `AcceleratorPages.swift:637-671`). Ingang: Tools-blok (2 tikken). 2-3 kaarten: "Voor welk doel?" (alleen bij meer dan een doel), "Versnellers" (resultaat, grafiek, rijen met keuze en "Toepassen", "Alles kiezen"/"Niets kiezen"), "Toegepast" (alle doelen, "Herstel"). Zonder doel: EmptyHint met knop die `router.toolsPath.append(.goals)` doet (`:651`).

**P13. Buffer** (`BufferPage`, `BufferPages.swift:70-450`). Ingangen: Savings-blok (2 tikken), chip "Buffercalculator" op Bankrekening. 7 kaarten: "Jouw situatie" (2 keuzemenu's, stapper, schakelaar), "Noodzakelijke uitgaven" (tegels, schuif), "Wat heb je al?", "Jouw buffer" (doel, balk, 4 tegels), "Hoe snel?" (veld, schakelaar, 2 chips, schuif), "Verloop" (grafiek), "Spaarpot Buffer" (maakt of past de pot aan). Invoer alleen op dit apparaat (`@AppStorage`).

**P14. Aankoopcheck** (`PurchasePage`, `PurchasePages.swift:197-789`). Ingang: Tools-blok (2 tikken). Wizard in 3 stappen op een pagina: (1) "Wat wil je kopen?" (naam, 10 soortegels, prijs, verzendkosten, uurloon, uren per week, "Verder"); (2) "Hoeveel uur wil je ervoor werken?" (schuif, veld, 7 knoppen, "Terug", "Laat zien wat het kost"); (3) uitkomst-blok, "Kan het?", "Goedkoper te vinden?" (zoekterm, 3 zoeklinks, 2 velden), 2 chips. Het uurloon staat alleen op dit apparaat (`@AppStorage`); het veld "Uren per week" schrijft in de salarisgegevens (`:301`).

**P15. Dag voor dag** (`CashflowPage`, `CashflowPages.swift:883-1103`). Ingangen (alle diep): chip "Per dag bekijken" op Overzicht (3 tikken), chip op Salaris & inkomsten, twee chips op Bankrekening, chip op Spaarpot (2 tikken). Niet vanaf een tab te bereiken.
4 vaste en 4 voorwaardelijke kaarten plus 28-31 dagkaarten: maandkiezer, waarschuwing (voorwaardelijk), rode melding "De cijfers sluiten niet" (voorwaardelijk), "Bankrekening", "Spaarpotten" (voorwaardelijk), "Je overzicht" (5 rijen die doorlinken), "Saldo per dag" (grafiek, voorwaardelijk), "Dag voor dag" (filter + "Naar vandaag"), dan een glazen kaart per dag (tegels, gebeurtenissen, saldo's). Een tik op een gebeurtenis opent Salaris, Spaarpot, Belegging of `MoneyLineSheet`. Kaarten per scherm: 32 tot 39.

**P16. Instellingen** (`SettingsView`, `SettingsView.swift:3-152`). Zie par. 2. Alleen als sheet (`RootView.swift:26`), alleen via het tandwiel op een tabwortel (1 tik).

**P17. Inlogscherm** (`AuthView`, `AuthView.swift:8-533`). Volledig scherm met glazen kaart: segment Inloggen / Account maken, e-mail, wachtwoord (met oog), herhaal wachtwoord, naam (alleen lokaal), "Wachtwoord vergeten?", hoofdknop, voetnoot. Drie standen: inloggen, account maken, wachtwoord vergeten.

### 1.4 Alle sheets en dialogen

| # | Sheet | Bestand:regel (definitie) | Geopend door (plekken) | Opmerking |
|---|---|---|---|---|
| 1 | Instellingen | `SettingsView.swift:3` | `RootView.swift:26` via tandwiel (`Components.swift:38`) | hele pagina als sheet; opent zelf 3 sheets, 4 bestandsdialogen en meerdere bevestigingen |
| 2 | Volgorde aanpassen | `BlockOrder.swift:187` | `RootView.swift:27`, contextmenu `BlockOrder.swift:153-165` | alleen via lang indrukken |
| 3 | Wachtwoord wijzigen (lokaal) | `AuthView.swift:653` | `AuthView.swift:636` | sheet in sheet |
| 4 | Account verwijderen (lokaal) | `AuthView.swift:740` | `AuthView.swift:637` | sheet in sheet |
| 5 | Wachtwoord wijzigen (cloud) | `CloudViews.swift:387` | `CloudViews.swift:115` | sheet in sheet |
| 6 | Account verwijderen (cloud) | `CloudViews.swift:504` | `CloudViews.swift:116` | sheet in sheet |
| 7 | Importeren (controle en uitkomst) | `BackupUI.swift:586-817` | `BackupUI.swift:385` | sheet in sheet; twee toestanden met eigen `NavigationStack`: een flow |
| 8 | Nieuwe spaarpot / Spaarpot aanpassen | `PotPages.swift:824` | `PotPages.swift:96,269`, `HomeView.swift:281` | 5 secties |
| 9 | Kies potten voor Home | `HomeView.swift:486` | `PotPages.swift:97`, `HomeView.swift:280` | |
| 10 | Geld storten / opnemen / saldo aanpassen / overboeken | `PotPages.swift:739` | `PotPages.swift:268` | 4 acties, 1 sheet |
| 11 | Belegging toevoegen / aanpassen | `PortfolioPages.swift:409` | `PortfolioPages.swift:97,324`, `HomeView.swift:422` | zoeken op internet, 4 secties |
| 12 | Kies beleggingen voor Home | `HomeView.swift:530` | `PortfolioPages.swift:98`, `HomeView.swift:421` | |
| 13 | Waarde bijwerken | `PortfolioPages.swift:380` | `PortfolioPages.swift:325` | |
| 14 | Inkomen / Uitgave toevoegen / wijzigen | `SavingsPages.swift:818` | `SavingsPages.swift:672,675`, `CashflowPages.swift:929` | naam, bedrag, soort, dag, terugkerend, uit spaarpot |
| 15 | Bankactie (saldo invullen, storten, opnemen, naar/van spaarpot) | `SavingsPages.swift:2068` | `SavingsPages.swift:1632` | 5 acties, 1 sheet |
| 16 | Nieuw doel / Doel aanpassen | `GoalPages.swift:513` | `GoalPages.swift:260,414` | |
| 17 | Versneller toepassen | `AcceleratorPages.swift:303` | `AcceleratorPages.swift:49` | bevestiging in sheetvorm; de enige met `presentationDetents` naast nr. 2 |

Bestandsdialogen: `BackupUI.swift:315` (JSON), `:333` (importeren), `:349` (voorbeeldbestand), `:364` (CSV, 3 rijen). Alert-bronnen: `BackupUI.swift:375` (6 rijen, ook gewone meldingen als "Bestand bewaard") en `CloudViews.swift:360` (synchronisatiemeldingen op de wortel van de app). Bevestigingsdialogen: 17 (`.confirmationDialog(`), o.a. `SettingsView.swift:118,131`, `PotPages.swift:270,551`, `SavingsPages.swift:678,887,2025`, `CloudViews.swift:120,210,558`.

### 1.5 Navigatiekaart

Vanaf een tabwortel (blok of kop) en van pagina naar pagina. Elke pijl is een bestaande tik; "kop" is alleen de kop van een blok.

```
Home      ─ kaart "Nog te verdelen" ─► Verdelen
          ─ blok Overzicht ─────────► Overzicht
          ─ kop Spaarpotten ────────► Spaarpotten      ─ pottegel ─► Spaarpot
          ─ kop Beleggingen ────────► Beleggingen      ─ tegel ────► Belegging
          ─ welkomstblok (lege start) ─► Salaris & inkomsten
          ─ tandwiel ───────────────► [sheet] Instellingen
Savings   ─ Overzicht, Salaris & inkomsten, Bankrekening, Verdelen, Spaarpotten, Buffer, Beleggingen, Doelen
Tools     ─ Versnellers, Toekomstschatting, Aankoopcheck

Overzicht            ─► Bankrekening, Spaarpotten, Beleggingen (rijen); Dag voor dag (chip)
Salaris & inkomsten  ─► Dag voor dag (chip); [sheet] regel toevoegen/wijzigen
Bankrekening         ─► Verdelen (chip + kop Overschrijvingen); Dag voor dag (2 chips); Buffer (chip); [sheet] bankactie, regel
Verdelen             ─► Spaarpotten (kop); Beleggingen (kop)
Dag voor dag         ─► Overzicht (kop); Spaarpotten (kop + rij); Salaris & inkomsten (rij + gebeurtenis);
                        Bankrekening (rij "Uitgaven"); Beleggingen (rij); Verdelen (rij);
                        Spaarpot en Belegging (gebeurtenis); [sheet] regel wijzigen
Spaarpotten          ─► Spaarpot;  [sheet] nieuwe pot, kies potten
Spaarpot             ─► Dag voor dag (chip); Verdelen (chip); [sheet] bewegen, aanpassen
Beleggingen          ─► Belegging;  [sheet] nieuwe belegging, kies beleggingen
Belegging            ─► Verdelen (chip); [sheet] aanpassen, waarde bijwerken
Doelen               ─► Doel; schakelaar "Spaardoel" ─► Spaarpot, Doel (resultaat); [sheet] nieuw doel
Doel                 ─► (Versnellers en Toegepast ingebed); [sheet] doel aanpassen, versneller toepassen
Versnellers          ─► Doelen (alleen als er geen doel is; schrijft rechtstreeks in het pad van Tools)
Buffer, Toekomstschatting, Aankoopcheck: geen uitgaande links (Buffer maakt wel een spaarpot aan)
```

**Pagina's op meer dan een plek bereikbaar** (aantal ingangen, vanaf blok/chip/rij):

| Pagina | Ingangen | Plekken |
|---|---|---|
| Verdelen | 7 | Home-kaart, Savings-blok, chip Bankrekening, kop Overschrijvingen, chip Spaarpot, chip Belegging, rij Dag voor dag |
| Spaarpotten | 6 | Home-kop, Savings-blok, rij Overzicht, kop op Verdelen, kop en rij op Dag voor dag |
| Dag voor dag | 5 | chip Overzicht, chip Salaris, 2 chips Bankrekening, chip Spaarpot |
| Beleggingen | 5 | Home-kop, Savings-blok, rij Overzicht, kop Verdelen, rij Dag voor dag |
| Salaris & inkomsten | 4 | Savings-blok, welkomstblok, rij Dag voor dag, salarisgebeurtenis |
| Overzicht | 3 | Home-blok, Savings-blok, kop op Dag voor dag |
| Bankrekening | 3 | Savings-blok, rij Overzicht, rij "Uitgaven" op Dag voor dag (als `.expenses`) |
| Buffer | 2 | Savings-blok, chip Bankrekening |
| Versnellers (inhoud) | 2 | pagina Versnellers (Tools) en ingebed in elk Doel |
| Instellingen | 3 | tandwiel op Home, Savings en Tools (niet op detailpagina's) |

**Moeilijk te vinden of te raden**:

| Onderdeel | Probleem | Bewijs |
|---|---|---|
| Uitgaven toevoegen | Er is geen tab, blok of pagina "Uitgaven". Je moet Savings > Bankrekening openen en 5 tot 6 kaarten scrollen naar "Vaste uitgaven" / "Variabele uitgaven". Het Buffer-scherm verwijst naar een "Uitgaven" die niet bestaat. | `SavingsPages.swift:1623-1624`, `DestinationView.swift:11`, `BufferPages.swift:211` |
| Dag voor dag | Alleen via een chip diep op een pagina; de 5 chips heten 4 verschillende dingen ("Per dag bekijken", "Dag voor dag bekijken" (2x), "Dag voor dag", "Alle dagen bekijken") | `SavingsPages.swift:176,545,1757`, `CashflowPages.swift:574`, `PotPages.swift:374` |
| Spaardoel-calculator | Zit achter een schakelaar op de pagina Doelen; staat niet in de tab Tools bij de andere rekenhulpen | `GoalPages.swift:240-255` |
| Buffercalculator | Staat in Savings, de andere rekenhulpen in Tools | `BufferPages.swift:15`, `ToolsView.swift:22-28` |
| Volgorde van blokken | Alleen lang indrukken; geen knop | `BlockOrder.swift:153-165` |
| Account | Eerste sectie in de Instellingen-sheet; na inloggen nergens anders | `CloudViews.swift:92` |
| Back-up / import / export | Sectie 6 t/m 8 van 10 in de Instellingen-sheet | `BackupUI.swift:257-301` |
| Rente van een pot | Pagina Spaarpot > chip "Rente instellen" opent een sheet met 5 secties; rente is sectie 5 | `PotPages.swift:500,903` |
| Voorbeelddata | Op Home alleen zolang de app leeg is, anders in Instellingen > Gegevens | `HomeView.swift:91`, `SettingsView.swift:78` |
| Standaard uitgaven invullen | Chip onderaan het blok "Binnen en eruit" | `SavingsPages.swift:1749` |

### 1.6 Veelvoorkomende taken in tikken (vanaf Home)

| Taak | Tikken | Opmerking |
|---|---|---|
| Geld verdelen | 1 | kaart "Nog te verdelen" |
| Spaarpot storten | 3 | pottegel, chip, sheet |
| Nieuwe spaarpot | 3 | kop Spaarpotten, chip, sheet |
| Salaris wijzigen | 2 | Savings, Salaris & inkomsten |
| Uitgave toevoegen | 4 en veel scrollen | Savings, Bankrekening, scrollen, "Toevoegen", sheet |
| Saldo invullen | 3 | Savings, Bankrekening, chip |
| Dag voor dag | 3 (min. 2 via een spaarpot) | Savings, Bankrekening, chip |
| Spaardoel berekenen | 3 | Savings, Doelen, schakelaar |
| Rente instellen | 3 | pottegel, chip, sheet-scrollen |
| Back-up maken | 2 + scrollen | tandwiel, 6e sectie, bestandsdialoog |
| Wachtwoord wijzigen | 3 | tandwiel, rij, sheet |
| Volgorde aanpassen | lang indrukken | geen zichtbare knop |

---

## 2. Instellingen

### 2.1 Wat er nu staat

De Instellingen zijn een `Form` in een sheet (`SettingsView.swift:18-151`, geopend via `RootView.swift:26`). Met een Firebase-sleutel zijn er 10 secties:

| # | Sectie | Bestand:regel | Rijen, knoppen, uitleg | Account? |
|---|---|---|---|---|
| 1 | Account (cloud) | `CloudViews.swift:92-145` | e-mailrij "Ingelogd"; knoppen Wachtwoord wijzigen (sheet), Uitloggen (dialoog), Account verwijderen (sheet, rood); voetnoot over Keychain (2 varianten) | ja |
| 2 | Synchroniseren | `CloudViews.swift:149-231` | statusrij (7 toestanden); bij conflict tekst + "Bewaar deze versie" + "Neem cloud-versie over"; "Nu synchroniseren"; "Laatst gesynchroniseerd"; grootte-waarschuwing; uitklapper "Back-ups van conflicten (n)" met "Terugzetten" per rij; voetnoot van 3 zinnen (HTTPS, niet end-to-end, offline) | ja |
| 3 | Rekenen | `SettingsView.swift:23-32` | 4 velden: Inflatie per jaar, Opnamepercentage, Spaarrente, Buffer op bankrekening (mnd); voetnoot van 3 zinnen | nee |
| 4 | Cijfers van internet | `MarketDataUI.swift:167-231` | "Inflatie ophalen", "Spaarrente ophalen", "Alles ophalen"; per cijfer een resultaatkaart (waarde, label, bron, knop "Gebruik"); "Beide gebruiken"; "Laatst bijgewerkt"; voetnoot | nee |
| 5 | Koersen | `SettingsView.swift:36-73` | schakelaar "Koersen automatisch ophalen"; "Nu vernieuwen"; "Laatst bijgewerkt"; "Koersverbinding testen" met diagnoseregels; foutregel; voetnoot (Yahoo Finance, Stooq, CoinGecko) | nee |
| 6 | Back-up en importeren | `BackupUI.swift:257-283` | "Back-up exporteren (JSON)", "Importeren" (+ leesvoortgang); voetnoot van 437 tekens | nee |
| 7 | Excel en CSV | `BackupUI.swift:285-291` | "Voorbeeldbestand downloaden"; voetnoot van 374 tekens | nee |
| 8 | Cijfers exporteren (CSV) | `BackupUI.swift:293-301` | 3 rijen: Maandcijfers, Transacties, Beleggingen; voetnoot | nee |
| 9 | Gegevens | `SettingsView.swift:77-93` | "Voorbeelddata laden", "Alles wissen" (rood), opslagfout-regel; voetnoot per Firebase-stand | gedeeltelijk (wist ook de cloud) |
| 10 | Over | `SettingsView.swift:95-104` | "MyBuddy / Versie 1.0" (vast getal), disclaimer | nee |

Zonder Firebase-sleutel vervangen twee andere secties 1 en 2: **Account (lokaal)** (`AuthView.swift:614-649`: naam of e-mail, Wachtwoord wijzigen, Uitloggen, Account verwijderen, voetnoot "geen wachtwoordherstel") en **Synchroniseren staat uit** (`FirebaseSetupSection`, `CloudViews.swift:47-88`): een instructie voor ontwikkelaars met vier stappen en bestandsnamen (`FirebaseConfig.swift`, `firebase/README.md`) die een gewone gebruiker ziet.

Totaal: circa 29 vaste rijen en knoppen, 10 voetnoten, 3 sheets in de sheet (wachtwoord, verwijderen, importeren), 4 bestandsdialogen, 6 aparte alert- en dialoogaanhakingen (`BackupHost`).

Buiten het scherm Instellingen hoort ook bij account of gegevens: het volledige inlogscherm (`AuthView`), de alert "Lokale gegevens uploaden?" en "Welke versie wil je houden?" die bij het openen van de app op de wortel verschijnt (`CloudViews.swift:318-376`, `MyBuddyApp.swift:138`), en `AccountPrefs` (`AccountPrefs.swift:12-18`).

### 2.2 Wat hoort bij het account en wat niet

| Onderdeel | Plek nu | Hoort bij account |
|---|---|---|
| Inloggen, account maken, wachtwoord vergeten | `AuthView.swift:8-533` | ja |
| Uitloggen | `CloudViews.swift:119`, `AuthView.swift:640` | ja |
| Wachtwoord wijzigen | `CloudViews.swift:387`, `AuthView.swift:653` | ja |
| Account verwijderen | `CloudViews.swift:504`, `AuthView.swift:740` | ja |
| Synchronisatiestatus, nu synchroniseren, conflicten, back-ups van conflicten | `CloudViews.swift:149-231` | ja |
| Meldingen over uploaden en conflict | `CloudViews.swift:318-376` | ja (maar nu een alert bij het starten, zie HIG par. 3) |
| Uitleg "Firebase aanzetten" | `CloudViews.swift:47-88` | nee: hoort niet in de app |
| Inflatie, spaarrente, opnamepercentage, buffer | `SettingsView.swift:23-32` | nee |
| Cijfers van internet, koersen | `MarketDataUI.swift:167`, `SettingsView.swift:36` | nee |
| Back-up, import, export | `BackupUI.swift:229-302` | nee (JSON-back-up is wel het alternatief voor synchronisatie) |
| Voorbeelddata laden, Alles wissen | `SettingsView.swift:77-93` | nee, maar ze wissen ook de cloud: voorwaarschuwing blijft nodig |
| Over | `SettingsView.swift:95-104` | nee |

### 2.3 Wat onnodig of verwarrend is

1. **Account staat in dezelfde lijst als rekeninstellingen**, verdeeld over twee secties (Account en Synchroniseren), terwijl wachtwoord wijzigen en account verwijderen sheets openen vanuit een sheet (HIG SHT-2). Zie `SettingsView.swift:21`.
2. **De Instellingen zijn een sheet.** Dat dwingt tot sheet-in-sheet en tot `BackupHost` (`BackupUI.swift:253-256`, 6 rijen): bestandsdialogen, alerts en het importoverzicht moeten aan de aangetikte rij hangen omdat een Form-rij buiten beeld niet bestaat. Op een eigen pagina met toolbar verdwijnt die constructie.
3. **Opnamepercentage** (`SettingsView.swift:25`) is alleen de beginwaarde voor een nieuw doel (`Goals.swift:218`); elk doel heeft zijn eigen veld (`GoalPages.swift:580,594`). Als instelling is het misleidend.
4. **Spaarrente** (`SettingsView.swift:26`) klinkt als de rente van een pot, maar is een aanname voor de spaardoel-calculator en de buffer (`SavingsGoalPages.swift:328`, `BufferPages.swift:320`, `Buffer.swift:373`).
5. **Buffer op bankrekening (mnd)** (`SettingsView.swift:27`) staat ook als veld "Bankbuffer in maanden aan uitgaven" op de pagina Bankrekening (`SavingsPages.swift:1953`): dezelfde instelling op twee plekken met twee namen, en geen van beide is de "Buffer" van de calculator.
6. **Cijfers van internet**: drie ophaalknoppen, twee resultaatkaarten en drie verschillende bevestigingslabels ("Gebruik" `MarketDataUI.swift:237`, "Overnemen" `:136`, "Beide gebruiken" `:214`) voor twee getallen die een rij hierboven al staan.
7. **Koersverbinding testen** met diagnoseregels (`SettingsView.swift:50-65`) is een ontwikkelaarsfunctie; "Nu vernieuwen" bestaat ook als "Koersen vernieuwen" (`PortfolioPages.swift:116`) en "Koers vernieuwen" (`:358`).
8. **Drie back-upsecties voor zes rijen** (6, 7, 8) en een knop "Importeren" die twee verschillende dingen doet (JSON vervangt alles, Excel/CSV voegt toe) onder een uitleg van 437 tekens.
9. **Voorbeelddata laden** staat ook op Home (`HomeView.swift:91`).
10. **"Versie 1.0"** is een vast getal (`SettingsView.swift:99`), geen bundelversie.
11. **Voetnoten te lang en te technisch**: `SettingsView.swift:31` (3 zinnen), `:72` (Yahoo Finance, Stooq, CoinGecko), `BackupUI.swift:282`, `:290`, `:300`, `MarketDataUI.swift:229`, `CloudViews.swift:228` ("HTTPS", "end-to-end"), `CloudViews.swift:132` ("Keychain").
12. **Dode code**: `RateFetchRow` (`MarketDataUI.swift:94-161`, geen aanroep) en `SectionLabel` (`Components.swift:132-144`, geen aanroep).
13. **Een account is verplicht om de app te gebruiken** (`MyBuddyApp.swift:86-102`), ook zonder cloud: dan een lokaal account met wachtwoord "zonder wachtwoordherstel" (`AuthView.swift:228`) voor gegevens die het apparaat toch niet verlaten (HIG ACT-1).
14. **Invoer die niet in de back-up of synchronisatie zit**: spaardoel-calculator, buffer-calculator en uurloon van de aankoopcheck staan in `UserDefaults` (`AccountPrefs.swift:12-18`). Wie een back-up terugzet of een tweede apparaat koppelt, mist ze zonder melding.

### 2.4 Voorstel: een korte lijst met groepen

**Plek.** iPhone en iPad: een volledige pagina "Instellingen" op de navigatiestapel, bereikbaar als eigen tab/zijbalkitem (of als toolbar-knop op elke tabwortel). Mac: de `Settings`-scene (⌘,) met dezelfde inhoud. Geen sheet, geen "Klaar"-knop.

**Groepen** (Nederlandse namen, zinshoofdletter):

```
Instellingen
 ├ [bovenste rij] Account                  > eigen pagina   (e-mail · Gesynchroniseerd om 14:02)
 ├ Rekenen
 │    Inflatie per jaar
 │    Aangenomen spaarrente
 │    Minimumsaldo bankrekening (maanden aan uitgaven)    [alleen hier of alleen op Bankrekening]
 │    Actuele cijfers ophalen                             [1 rij: toont inflatie en rente, knop "Gebruik"]
 ├ Koersen
 │    Koersen automatisch ophalen
 │    Nu vernieuwen · laatst bijgewerkt
 ├ Gegevens
 │    Back-up maken
 │    Back-up terugzetten
 │    Importeren uit Excel of CSV                         [voorbeeldbestand in het importscherm]
 │    Exporteren voor Excel                               [keuze Maandcijfers / Transacties / Beleggingen]
 │    Voorbeelddata laden · Alles wissen                  [onderaan, rood, met cloudwaarschuwing]
 ├ Indeling
 │    Volgorde van de blokken                             [per tab; zichtbare ingang voor het sleepscherm]
 └ Over MyBuddy
      Versie (uit de bundel) · korte disclaimer · privacy
```

**Account** (eigen pagina, geduwd op de stapel, symbool `person.crop.circle`):

```
Account
 ├ Profiel                e-mail (lokaal: naam), "Ingelogd"
 ├ Synchronisatie         status · Nu synchroniseren · Laatst gesynchroniseerd
 │                        [bij conflict: Bewaar deze versie / Neem cloud-versie over]
 │                        Back-ups van conflicten >  (push)
 ├ Wachtwoord wijzigen    (push, geen sheet)
 ├ Uitloggen
 └ Account verwijderen    (onderaan, rood; push met wachtwoord en bevestiging)
```

Zonder Firebase-sleutel toont Account alleen "Gegevens staan alleen op dit apparaat" plus de lokale accountrijen. De vier stappen om Firebase aan te zetten verdwijnen uit de app (ze staan in `firebase/README.md`).

**Resultaat**: 6 groepen in plaats van 10 secties, ongeveer 16 rijen in plaats van 29, en elke uitleg maximaal twee zinnen.

**Schrappen of verplaatsen**
- Opnamepercentage: alleen nog in het doel (`GoalEditSheet`); veld uit Instellingen (en `AppSettings.defaultWithdrawalRate` blijft als vaste beginwaarde).
- Koersverbinding testen: weg, of achter een "Geavanceerd"-uitklapper; een mislukte koers meldt zichzelf inline (zoals `store.priceMessage` al doet).
- `RateFetchRow` en `SectionLabel` verwijderen.
- Voorbeelddata alleen in de lege staat van het Overzicht en onder Gegevens.
- Back-upsecties 6 t/m 8 worden de pagina Gegevens met vier rijen; de importflow wordt een eigen pagina op de stapel in plaats van een sheet in een sheet.
- Account niet verplicht maken: de eerste start opent direct het Overzicht; "Inloggen om te synchroniseren" staat op de Account-pagina. Bestaande lokale accounts moeten bij die wijziging worden gemigreerd (`AuthStore.storageURL(for:)`), dus dit is een keuze voor de ontwerper.

**Uitvoeringsnotities**
- Een `Settings`-scene heeft `AppStore`, `Router` en `AuthStore` nodig; die staan nu in `SignedInRoot` (`MyBuddyApp.swift:115-117`) en moeten daarvoor boven de scenes komen, anders blijft op de Mac een sheet de terugval.
- `AccountAndSyncSections` levert `Section`s af (`CloudViews.swift:31-44`) en moet een eigen pagina worden; de `BackupHost`-constructie (`BackupUI.swift:153-170`, `:373-398`) vervalt op een pagina met een gewone toolbar of menu.

---

## 3. HIG-toets

Prioriteit: **H** = breekt een kernregel of blokkeert gebruik, **M** = merkbaar, **L** = netjes maken. Wat al goed is staat in par. 3.15.

### 3.1 Scorebord

| Onderwerp | Stand | Kern |
|---|---|---|
| Navigatie (tabs, zijbalk, titels) | niet | eigen tabbalk, pad wissen, Engelse namen |
| Materialen / Liquid Glass | niet | inhoud in glas, glas op glas |
| Typografie / Dynamic Type | deels | 5 vaste groottes, 49 krimpende teksten, vaste drie kolommen |
| Kleur en contrast | niet (licht), deels (donker) | secundaire tekst 2,8 tot 3,2:1 op de lichte achtergrond |
| Aanraakdoelen | deels | knoppen 42 pt, menuknoppen ongeveer 22 pt |
| Toegankelijkheid | niet | 33 modifiers, geen Reduce Motion/Transparency, grafieken zonder samenvatting |
| Sheets en alerts | deels | Instellingen als sheet, sheet-in-sheet, alerts voor informatie |
| Lijsten, rij-acties, lege staten | niet | geen `List`, 0 swipe-acties, eigen lege staat |
| Grafieken | deels | werken niet bij lege invoer (zie 3.11), 2 van 8 met label |
| Invoer | goed | locale-bewuste velden, juiste toetsenborden |
| Bedragen en datums | goed | kleine punten (3.12) |
| macOS | niet | geen Settings-scene, menu, sneltoetsen; balk onderin |
| iPad | deels | geen zijbalk, geen paginasheets |
| Teksten | deels | 59 lange teksten, technische termen, dubbele teksten |

### 3.2 Navigatie en structuur

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| N1 | Eigen tabbalk in plaats van `TabView`: geen zijbalk op iPad en Mac, geen standaard toetsenbord- en VoiceOver-gedrag, balk verdwijnt zelf bij het toetsenbord, `barBackdrop` legt een tweede materiaal onder het glas | `RootView.swift:86-149` (balk), `:18-24`, `:136-148` | `TabView { Tab(...) }` met `.tabViewStyle(.sidebarAdaptable)`; `GlassTabBar` en `barBackdrop` weg | TAB-5, LAY-8 | H |
| N2 | Van tab wisselen wist het navigatiepad van de gekozen tab (ook bij een andere tab dan de actieve) | `Router.swift:66-73` | pad per tab bewaren; alleen wissen bij een tik op de tab waar je al bent (via de selectiebinding van `TabView`) | TAB-6 | H |
| N3 | Tabnamen en paginatitels in het Engels in een Nederlandse app | `Router.swift:10-12`, `HomeView.swift:12`, `SavingsView.swift:12`, `ToolsView.swift:11`, `BlockOrder.swift:24-26` | Nederlandse eenwoordnamen, zie par. 4.5 | TAB-4, WRT-2 | M |
| N4 | Grote titel op alle 21 pagina's, ook diepe detailpagina's | `Components.swift:33` | `.large` alleen op tabwortels, `.inline` op detail; op macOS bestaat dit niet (is al afgeschermd met `#if os(iOS)`) | NAV-2 | L |
| N5 | Instellingen is een sheet | `RootView.swift:26` | volledige pagina, zie par. 2.4 | SET-4, SHT-1 | H |
| N6 | Een account is verplicht om de app te gebruiken | `MyBuddyApp.swift:86-102` | account optioneel, aanmelden uitstellen | ACT-1 | M |
| N7 | Functie alleen via een gebaar: "Volgorde aanpassen" alleen via lang indrukken | `BlockOrder.swift:153-165` | ook zichtbaar via Instellingen > Indeling of een toolbarmenu | ACC-7 | M |
| N8 | Rij is een `onTapGesture` op een `VStack`, geen knop: geen knop-eigenschap voor VoiceOver en geen toetsenbordfocus | `SavingsPages.swift:780` | `Button`/`NavigationLink` of een `List`-rij | ACC-3 | M |
| N9 | Geen diepteregel: Spaarpot > Dag voor dag > Spaarpot > ... kan eindeloos worden gestapeld | `Router.swift:77-83` | onderscheid pagina's per tab, of tonen als geschiedenis; maximaal 3 niveaus | NAV-4 | L |
| N10 | `AcceleratorsPage` schrijft rechtstreeks in `router.toolsPath` terwijl de rest `router.open` gebruikt | `AcceleratorPages.swift:651` | `router.open(.goals)` | NAV-5 | L |

### 3.3 Materialen en glas

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| G1 | Inhoud staat in glas: elk van de 103 blokken en 12 losse kaarten is een glazen kaart | `Components.swift:70` (`GlassBlock`), `:125` (`LinkedBlock`), `Glass.swift:35-37` | inhoud in gegroepeerde `List`/`Form`-secties of `.background(.regularMaterial)`; glas alleen voor tabbalk, toolbar, knoppen | GLS-1, GLS-3 | H |
| G2 | Glas op glas: alle 86 chip-knoppen zijn glas (`ChipLabel`) binnen een glazen blok; de tabbalk is glas op een balkmateriaal | `Components.swift:298` binnen `:70`; `RootView.swift:125` + `:139` | knoppen in inhoud krijgen `.bordered`/`.borderedProminent`; hooguit een `.glassProminent` per scherm | GLS-2, BTN-3 | H |
| G3 | Tint op glas bijna overal: 13 keer olijf, 5 keer een kleur van pot of status | `PortfolioPages.swift:29,214`, `PotPages.swift:61,305,469`, `SavingsPages.swift:32,1410,1652`, `SavingsGoalPages.swift:173`, `BufferPages.swift:273`, `ProjectionPage.swift:115`, `GoalPages.swift:363`, `HomeView.swift:82,179`, `CashflowPages.swift:351,405,743,858` | tint alleen op de primaire actie; belangrijke kaart onderscheiden met positie, niet met kleur | COL-6, GLS-4 | M |
| G4 | Terugval iOS 18 en macOS 15 (de ondergrens, dus voor veel gebruikers het enige uiterlijk): `ultraThinMaterial` met een witte rand van 14%, die op de lichte achtergrond onzichtbaar is; geen aanpassing bij Verlaag transparantie | `Glass.swift:13-16` | systeemmaterialen en `Form`-achtergrond; bij `accessibilityReduceTransparency` een dekkend vlak | GLS-8, GLS-10 | M |
| G5 | Mesh-achtergrond wordt meerdere keren getekend en herhaald in sheets: root, elke pagina, 9 sheets | `RootView.swift:25`, `Components.swift:30`, `SettingsView.swift:108`, `Fields.swift:361`, `BlockOrder.swift:221`, `BackupUI.swift:620`, `AcceleratorPages.swift:364`, `AuthView.swift:73,700,775`, `CloudViews.swift:435,546` | een mesh op de wortel; sheets krijgen de systeemachtergrond | DRK-3, GLS-5 | M |
| G6 | `ChipButton` zet `.buttonStyle(.plain)`: geen drukstatus op iOS 18/macOS 15 | `Components.swift:310-315` | systeemknopstijl met `controlSize(.large)` | BTN-1 | M |
| G7 | Glaselementen naast elkaar zitten niet in een `GlassEffectContainer` | `Components.swift:333-341` (`ChipGrid`), `Glass.swift` | `GlassEffectContainer` of afschaffen (zie G2) | GLS-6 | L |

### 3.4 Typografie en Dynamic Type

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| T1 | Vaste lettergroottes (5) | `RootView.swift:101`, `Components.swift:239`, `HomeView.swift:328`, `PurchasePages.swift:516,631` | tekststijlen of `@ScaledMetric` | TYP-1, SYM-2 | M |
| T2 | Drie kolommen vast, "ook op een smalle iPhone", met kerngetallen die krimpen in plaats van te stapelen | `HomeView.swift:153-157` (3 mini-tegels), `:271-276` (3 pottegels), `:415` (2 kolommen beleggingen), `SavingsView.swift:57-58,224-225`, `SavingsPages.swift:459,1406`, `PurchasePages.swift:576` (5 knoppen) | `ViewThatFits` of `AnyLayout` die bij `isAccessibilitySize` stapelt; `isAccessibilitySize` komt nergens voor | TYP-2, ACC-1 | H |
| T3 | `minimumScaleFactor` op 49 plekken, ook op labels en titels (alleen een kerngetal mag krimpen) | `Components.swift:157,176,180,291,447`, `HomeView.swift:195,198,334,337,343,439,459,462`, `PotPages.swift:123,134,158,...`, `CashflowPages.swift:93,134,153,158,...` | labels laten wrappen; krimpen alleen bij `BigAmount` | TYP-3 | M |
| T4 | Tabbalk-icoon 19 pt vast en tekst `caption2` | `RootView.swift:101-105` | vervalt met `TabView` | TYP-8 | L |
| T5 | `caption2` (11 pt) op 25 plekken, ook voor betekenisvolle bijschriften (`StatTile`-caption, "Verwacht", "Afwijkend") | `Components.swift:184`, `SavingsPages.swift:96,1317` | minimaal `footnote` voor betekenisvolle tekst | TYP-4 | L |
| T6 | `design: .rounded` op 26 plekken: bedragen in tegels afgerond, bedragen in rijen niet (bijv. `FlowRow`, `MoneyLineRow`) | `Components.swift:150,178`; `SavingsPages.swift:782,1809` | op alle bedragen of nergens | TYP-6 | L |
| T7 | Vaste zijmarge van 16 en pagina's tot 960 pt breed: lopende tekst en formulierrijen worden op iPad en Mac regels van meer dan 100 tekens | `Components.swift:16`, `Theme.swift:41` | `.scenePadding()`; leesbare breedte 600-700 pt voor enkelkoloms pagina's (Salaris, Overzicht, Verdelen, Bankrekening) | LAY-4, LAY-7 | M |
| T8 | Segmentkeuzes met lange labels bij grote tekst ("Over een periode" / "Op een datum", "Komende 30 dagen" / maandnaam) | `SavingsGoalPages.swift:283-286`, `CashflowPages.swift:509-513` | menu of `ViewThatFits` | TYP-2 | L |

### 3.5 Kleur en contrast

Berekend (WCAG 2.x, de negen mesh-achtergronden van `Theme.swift:95-104`; script par. 6). Drempel 4,5:1 voor tekst tot 17 pt, 3:1 voor groot of vet.

| Kleur (tekst) | Licht op mesh | Licht op `.tile()` | Donker op mesh | Donker op `.tile()` |
|---|---|---|---|---|
| `Theme.accent` `#556B2F` / `#A9C06B` | 3,66 - 4,97 | 3,15 - 4,26 | 5,87 - 9,48 | 4,75 - 8,07 |
| `Theme.positive` `#4A6B1C` / `#B7D272` | 3,79 - 5,14 | 3,26 - 4,41 | 7,02 - 11,33 | 5,67 - 9,64 |
| `Theme.negative` `#B5482A` / `#F29A7C` | 3,29 - 4,47 | 2,83 - 3,83 | 5,45 - 8,80 | 4,40 - 7,49 |
| `Theme.warning` `#9A7A12` / `#E3C25A` | **2,50 - 3,40** | **2,15 - 2,91** | 6,82 - 11,02 | 5,51 - 9,37 |
| `.secondary` (systeemkleur) | **2,82 - 3,21** | **2,64 - 3,01** | 4,70 - 6,26 | 4,06 - 5,79 |
| `.primary` | 12,91 - 17,55 | | 11,81 - 19,08 | |

Ter vergelijking: de systeemkleur `.secondary` op wit haalt zelf maar 3,44:1 (op `systemGroupedBackground` 3,30:1); op de olijfachtergrond is het nog lager. Donker is overal prima, licht niet.

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| K1 | `.secondary` voor uitleg en bijschriften: 279 plekken, meestal in `footnote` (200 plekken in de app), `caption` (137) en `caption2` (25), halen in licht 2,8 tot 3,2:1 | overal | uitleg die iemand moet lezen in `.primary` of een eigen tekstkleur met 85% dekking (4,3 tot 5,4:1 op tegels); op systeemachtergronden blijft `.secondary` ook 3,3:1, dus voor langere uitleg niet gebruiken | COL-3 | H |
| K2 | Statuskleuren als tekst in licht onder 4,5:1; `warning` zelfs onder 3:1 | `Theme.swift:60-63`; gebruikt o.a. `Components.swift:402,448`, `HomeView.swift:61`, `BackupUI.swift:700-702` | licht: accent `#3F5220` (4,56 op tegel), positive `#385213` (4,67), negative `#832F14` (4,67), warning `#5C4700` (4,72); donker blijft | COL-3 | H |
| K3 | Witte cijfers en vinkjes op de accentkleur: donker 2,01:1; op potkleuren 2,4 tot 3,4:1 | `HomeView.swift:506-508,553-555`, `Fields.swift:417,444` | zwarte of primaire tekst op de lichte accentkleur; of de gekozen pot met een rand/vinkje op `.primary` aangeven | COL-3, COL-4 | M |
| K4 | Geen hoog-contrastvariant en alle kleuren in code; `AccentColor` heeft licht en donker maar geen "Verhoog contrast" | `Theme.swift:57-82`, `Assets.xcassets/AccentColor.colorset/Contents.json` | Color Sets met Any / Dark / High Contrast | COL-2, ACC-6 | M |
| K5 | Grafiekkleuren tegen de lichte achtergrond onder 3:1: `flowFree` 1,15, `flowVariable` 1,38, `flowSaved` 1,64, `palette[2]` 1,49, `palette[6]` 1,59; donker `palette[7]` 1,80, `[5]` 2,19 | `Theme.swift:66-82` | donkerdere vulkleur plus rand, of patroon/label per reeks | COL-7, CHT-5 | M |
| K6 | Kleur als enige onderscheid in grafieken met meerdere reeksen: FlowChart (4 kleuren), Toekomstschatting (3 lijnen), Doelcurve (grijs of accent) | `Charts.swift:105,136`, `ProjectionPage.swift:133-134`, `AcceleratorPages.swift:627` | lijnstijl, symbool of directe label erbij (`BufferChart` doet dat al voor de doellijn, `BufferPages.swift:508`) | COL-4, CHT-5 | M |
| K7 | Zekerheid in het importoverzicht is alleen een gekleurd bolletje (het label bestaat wel voor VoiceOver) | `BackupUI.swift:830-834,896-903` | woord of symbool naast het bolletje | COL-4 | L |

### 3.6 Aanraakdoelen

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| A1 | Alle knoppen zijn 42 pt hoog (83 `ChipButton`/`ChipLink`) | `Theme.swift:39`, `Components.swift:296` | 44 | ACC-2, BTN-1 | M |
| A2 | Menuknoppen met alleen `ellipsis.circle` en `.fixedSize()`: ongeveer 22 pt | `SavingsPages.swift:788-797`, `:2011-2019`, `PotPages.swift:650-658`, `PortfolioPages.swift:301-312` | minimaal 44x44; en vervangen door swipe-actie (de drie laatste hebben maar een item: Verwijder) | ACC-2, LST-3 | M |
| A3 | Chevron-knoppen voor vorige/volgende dag: glyph met `.padding(8)`, ongeveer 33 pt | `CashflowPages.swift:430-444` | 44x44 zoals `StepButton` (`Components.swift:358`) | ACC-2 | M |
| A4 | Inlogscherm: oog en terug 32 pt; "Wachtwoord vergeten?" en "Terug naar inloggen" zijn tekst van 13 pt zonder vlak | `AuthView.swift:198-204,211-218,155-160,292-299` | 44 pt vlak | ACC-2 | M |
| A5 | Kleurkeuze 28 pt, symboolkeuze 40 pt | `Fields.swift:412,443` | 44 pt (kolommen van 44 zijn er al) | ACC-2 | L |

### 3.7 Toegankelijkheid

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| V1 | Geen koppen: 0x `.isHeader`, blokkoppen zijn gewone tekst, dus de rotor "Koppen" is leeg | `Components.swift:81` | `.accessibilityAddTraits(.isHeader)` op blokken en paginasecties | ACC-3 | M |
| V2 | Bedragen en tegels niet samengevoegd of benoemd: `StatTile` leest titel en bedrag los (85 plekken), `BigAmount` zonder label | `Components.swift:148-192` | `.accessibilityElement(children: .combine)` plus label "Over: 1.250 euro" | ACC-3, WRT-9 | M |
| V3 | Grafieken: 6 van 8 zonder label, 0x `accessibilityChartDescriptor` | `Charts.swift:53-164`, `AcceleratorPages.swift:585-632`, `SavingsGoalPages.swift:655-712`, `ProjectionPage.swift:127-138` (alleen `CashflowPages.swift:315` en `BufferPages.swift:526` hebben er een) | titel plus samenvatting ("Waarde stijgt van 4.800 naar 6.151 euro") op elke grafiek; later een descriptor | CHT-2 | H |
| V4 | Menuknoppen en symboolkeuze zonder label | `PortfolioPages.swift:308`, `PotPages.swift:653`, `SavingsPages.swift:2014`, `Fields.swift:441` | `.accessibilityLabel("Opties voor <rij>")`; symbolen met naam | SYM-6 | M |
| V5 | Kleurkeuze heet "Kleur 1" tot "Kleur 8" | `Fields.swift:422` | kleurnamen plus `.isSelected` | ACC-3 | L |
| V6 | Geen aanpassing voor Verlaag beweging, Verlaag transparantie, Onderscheid zonder kleur | 0 treffers | `accessibilityReduceMotion` op tabovergang, `matchedGeometryEffect`, `numericText`; `accessibilityReduceTransparency` in `GlassSurface` | ACC-4, GLS-8, COL-4 | H |
| V7 | Wijzigingen die alleen visueel zijn (grafiek of bedrag verandert na invoer) worden niet gemeld | overal | `AccessibilityNotification.LayoutChanged` of bijgewerkt label | ACC-10 | L |
| V8 | Geen haptiek bij gebeurtenissen (bewaard, mislukt, import klaar) | 0 `sensoryFeedback` | `sensoryFeedback(.success/.error, trigger:)` | FDB-4 | L |

### 3.8 Beweging

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| M1 | `PageScaffold` animeert de hele pagina bij elke wijziging van `store.data`, `focusMonth` en `periodMode`; dat vergelijkt bij elke update het hele gegevensmodel | `Components.swift:23-25` | animatie op concrete waarden (bedrag, lijst), niet op de pagina | MOT-1 | M |
| M2 | Eigen tabovergang met schaal en `matchedGeometryEffect` | `RootView.swift:64-67,111-115` | vervalt met `TabView` | MOT-4 | L |
| M3 | Bevestiging verdwijnt na 4 seconden vanzelf; meldingen na een timer | `AcceleratorPages.swift:55-66` | sluit met een actie of laat staan tot de volgende wijziging | ACC-8 | L |
| M4 | Schaal-overgangen in de importflow | `BackupUI.swift:614,617,640,645` | fade | ACC-4 | L |

### 3.9 Sheets, alerts en bevestigingen

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| S1 | Sheet-in-sheet: 5 soorten (zie 1.4), in elke configuratie 3 tegelijk bereikbaar (wachtwoord, verwijderen, importeren; lokaal en cloud sluiten elkaar uit) | `AuthView.swift:636-637`, `CloudViews.swift:115-116`, `BackupUI.swift:385` | verdwijnt als Instellingen een pagina wordt | SHT-2 | H |
| S2 | De importflow (twee toestanden, eigen navigatiebalk, 230 regels) is een "app in de app" | `BackupUI.swift:586-817` | pagina op de stapel met stappen | SHT-9 | M |
| S3 | Veeg-om-te-sluiten verliest invoer zonder vraag: geen `interactiveDismissDisabled` in `SheetScaffold` (9 gebruikers) | `Fields.swift:346-398` | `.interactiveDismissDisabled(hasChanges)` plus bevestiging | SHT-5 | M |
| S4 | Alleen 2 sheets hebben `presentationDetents`; geen grabber; geen `presentationSizing(.form)` op iPad en Mac | `BlockOrder.swift:245`, `AcceleratorPages.swift:370` | `.presentationDetents([.medium,.large])` voor korte keuzes, `.presentationSizing(.form)` voor formulieren | SHT-6, SHT-7 | L |
| S5 | Alert voor gewone informatie ("Bestand bewaard", "Back-up teruggezet") | `BackupUI.swift:375-380,436-454,524` | inline melding of banner; alert alleen voor onomkeerbare bevestiging | ALT-1 | M |
| S6 | Twee alerts die bij het openen van de app kunnen verschijnen ("Lokale gegevens uploaden?", "Welke versie wil je houden?"), aan de wortel van de app gehangen | `CloudViews.swift:318-376`, `MyBuddyApp.swift:138` | banner op de Account-rij en een duidelijke knop; alert niet bij start | ALT-5 | M |
| S7 | Dialogen hangen aan de hele `Form` of `NavigationStack`, niet aan de knop (op iPad en Mac komt hij dan niet bij de knop vandaan) | `SettingsView.swift:118,131` | aan de knop hangen | DLG-4 | L |
| S8 | Vaak voorkomende verwijderacties vragen bevestiging in plaats van "Maak ongedaan" | `PotPages.swift:551`, `SavingsPages.swift:2025` | undo-banner | ALT-2, DLG-6 | L |

### 3.10 Lijsten, rij-acties en lege staten

| # | Afwijking | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| L1 | Geen `List` in een pagina: rijen zijn `VStack` + `Divider` in glazen kaarten (regels, geschiedenis, dagen, versnellers, beleggingen). Geen swipe, geen selectie, geen standaardrijhoogte, geen lazy laden | `SavingsPages.swift:652-662`, `:1996-2023`, `PotPages.swift:564-574`, `PortfolioPages.swift:295-317` | `List` met `.insetGrouped` voor alle lijsten | LST-1, LST-2, LST-7 | H |
| L2 | 0x `swipeActions`: wijzigen en verwijderen zitten achter een `ellipsis.circle`-menu per rij (drie ervan met maar een item: Verwijder) | `SavingsPages.swift:788`, `:2011`, `PotPages.swift:650`, `PortfolioPages.swift:301` | swipe-acties (verwijder rood, wijzig) gespiegeld in een contextmenu | LST-3, LST-8 | H |
| L3 | Eén contextmenu in de hele app (blokvolgorde); geen rechtermuisklik op rijen voor de Mac | `BlockOrder.swift:153` | gedeelde `rowActions`-extensie | LST-8, IPD-7 | M |
| L4 | Eigen lege staat `EmptyHint` (15 plekken) in plaats van `ContentUnavailableView` | `Components.swift:248-277` | `ContentUnavailableView` met actie | EMP-1 | M |
| L5 | Lege staat ontbreekt waar het ertoe doet: Home- en Savings-blokken met een lege beleggingsreeks of alleen nullen tekenen een lege grafiek | `HomeView.swift:237,414`, `SavingsView.swift:70,276`, `SavingsPages.swift:69` | grafiek alleen bij 2 of meer punten, anders `ContentUnavailableView` | EMP-4, CHT-7 | H |
| L6 | Pagina met 28-31 glazen dagkaarten (32 tot 39 kaarten in totaal) in plaats van een `List` met secties per dag | `CashflowPages.swift:985-991` | `List` met `Section` per dag | LAY-2 | H |
| L7 | Sectiekop `SectionLabel` zet tekst in HOOFDLETTERS maar wordt nergens gebruikt | `Components.swift:132-144` | verwijderen | LST-2 | L |

### 3.11 Grafieken

8 grafiektypen op 17 plekken. Per type:

| Type | Bestand:regel | Gebruikt op | Lege staat | Label |
|---|---|---|---|---|
| `TimeLineChart` | `Charts.swift:53-94` | 7: `HomeView.swift:414`, `SavingsView.swift:276`, `PortfolioPages.swift:67,234,238`, `SavingsPages.swift:75,1929` | alleen op Beleggingen en Bankrekening (`>1` punt); Home en Savings tekenen een lege vlakte | geen |
| `FlowChart` | `Charts.swift:99-142` | 3: `HomeView.swift:237`, `SavingsView.swift:70`, `SavingsPages.swift:69` | geen | geen |
| `AllocationDonut` | `Charts.swift:146-164` | 1: `PortfolioPages.swift:80` | verborgen bij 1 soort | geen |
| `DayBalanceChart` | `CashflowPages.swift:243-317` | 2: `:517`, `:942` | ja (`days.count > 1`) | ja |
| `BufferChart` | `BufferPages.swift:481-528` | 1 | ja (`hasTarget`) | ja |
| `SavingsGoalChart` | `SavingsGoalPages.swift:655-712` | 1 | via `plan.cleanGoal > 0` | geen |
| `GoalCurveChart` | `AcceleratorPages.swift:585-632` | 1 | alleen bij een keuze | geen |
| Toekomstschatting | `ProjectionPage.swift:127-138` | 1 | geen (altijd data) | geen |

**Werkt de grafiek met wat de gebruiker invult?** Proef op `App/Core` (par. 6). De beleggingsgrafiek faalt in deze gevallen; de andere grafieken zijn pure functies van de invoer en bewegen mee.

| # | Bevinding | Bewijs | Voorstel | Prio |
|---|---|---|---|---|
| C1 | **Een belegging zonder meetpunt bestaat niet in de cijfers.** Een handmatige belegging waarbij de gebruiker "Totaal ingelegd" 5.000 en "Inleg per maand" 200 invult maar "Huidige waarde" leeg laat, heeft waarde 0, ingelegd 0 en 0 punten. Hetzelfde voor een belegging met ticker zolang er geen koers is (offline, of Yahoo geweigerd). | Proef A en C: waarde 0, ingelegd 0, 0 punten. Oorzaak `Invest.swift:38-41` (`guard let snap`), `:152-170` (`compactMap` slaat maanden zonder meetpunt over), `PortfolioPages.swift:493-494` (veld alleen bij nieuw én zonder ticker), `:706` (geen meetpunt als waarde 0) | start de reeks bij `startMonth` met `investedTotal` als waarde als er geen meetpunt is, of vraag de huidige waarde verplicht; toon het veld ook bij bewerken | H |
| C2 | Home en Savings tekenen dan een lege grafiek zonder uitleg (110 en 90 pt leeg). Alleen `PortfolioPage` heeft een uitlegtekst. | `HomeView.swift:414`, `SavingsView.swift:276` tegenover `PortfolioPages.swift:66-75` | `ContentUnavailableView` of uitleg bij minder dan 2 punten in elk blok | H |
| C3 | **"Totaal ingelegd" in het bewerkscherm doet niets zolang er een meetpunt is**: 5.000 naar 6.000 wijzigen laat "Ingelegd" op 5.000 staan; het opgeslagen veld wijkt af van wat het scherm toont. Alleen "Waarde bijwerken" verandert het. Twee plekken voor hetzelfde getal. | Proef F; `Invest.swift:217-230` (meetpunt alleen bij `isTracked`), `PortfolioPages.swift:380-405` | bij wijziging een meetpunt met dezelfde waarde en het nieuwe ingelegde bedrag; veld op een plek | H |
| C4 | **"Terugkijken" (6 mnd / 1 jaar / 3 jaar) doet niets** zolang er weinig meetpunten zijn: de reeks begint bij de eerste maand met een meetpunt. Eén meetpunt: altijd 13 punten (1 echt, 12 verwacht); voorbeelddata (6 maanden meetpunten): altijd 18. | Proef B en D; `PortfolioPages.swift:20,59-65` | keuze verbergen bij minder dan 2 maanden echte punten, of de reeks aanvullen met inleg per maand sinds `startMonth` | M |
| C5 | Met één echt punt staat er een stip en een stippellijn: wat als aanname bedoeld is, is het enige wat de gebruiker ziet, zonder uitleg dat de echte lijn pas bij het tweede meetpunt begint. | `Charts.swift:75-87` | uitlegtekst bij 1 punt | M |
| C6 | De grafiek toont niet of je winst of verlies maakt: `PortfolioPoint.invested` bestaat maar wordt niet getekend (`TimePoint` heeft het niet). | `Invest.swift:13-19`, `Charts.swift:35-50` | tweede lijn "Ingelegd" | M |
| C7 | Donutkleur per positie in de gesorteerde lijst, rij- en tegelkleur per soort: dezelfde soort heeft in grafiek en lijst een andere kleur. | `Charts.swift:159`, `PortfolioPages.swift:129`, `HomeView.swift:479-481` | kleur per `HoldingKind` op een plek; lijst met percentages naast de donut | M |
| C8 | `FlowChart` toont een tekort niet: `max(0, s.remaining)` laat "Over" bij een tekort wegvallen. Proef G: inkomen 3.000, uitgaven 3.500, Over -500, balk 0. | `Charts.swift:124` | tekort als rode reeks of markering | M |
| C9 | `FlowChart` op Home, Savings en Overzicht met alleen nullen (nieuwe gebruiker) tekent lege assen/blokken | `HomeView.swift:237`, `SavingsView.swift:70`, `SavingsPages.swift:69` | lege staat | M |

HIG-punten voor alle grafieken: samenvatting en label ontbreken (V3), kleur als enige onderscheid (K6), kleuren onder 3:1 (K5), geen interactie (scrubben met `chartXSelection`), y-as `includesZero: false` bij beleggingen (`Charts.swift:89`) maakt kleine schommelingen groot, en het nut van `showsAxes: false` op Home vraagt dan wel een kernwaarde (die staat er meestal al).

### 3.12 Bedragen en datums

| # | Afwijking | Waar | Voorstel | Prio |
|---|---|---|---|---|
| B1 | `nl_NL` vast, ongeacht de regio-instelling van het apparaat; maandnamen en datumpatroon met de hand | `Formatting.swift:5,75-79,113-125` | `Locale.current` met Nederlandse taal; `Date.FormatStyle` | L |
| B2 | Elk getoond bedrag of percentage bouwt een nieuwe `NumberFormatter` | `Formatting.swift:7-16,50-58,65-73` | gedeelde, gecachte formatters of `FormatStyle` | L |
| B3 | `Fmt.compact` bouwt "€1,2k" en "€3,4 mln" met de hand (aslabels, niet voorgelezen als bedrag) | `Formatting.swift:41-48` | `IntegerFormatStyle.Currency` met `.notation(.compactName)` | L |

### 3.13 macOS

| # | Tekortkoming | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| X1 | Geen `Settings`-scene en geen ⌘, : Instellingen is een sheet in het venster met `minWidth: 480` | `MyBuddyApp.swift:20-33`, `SettingsView.swift:148-150` | `Settings { ... }` met panes (Account, Rekenen, Koersen, Gegevens); zie uitvoeringsnotitie par. 2.4 | MAC-3, SET-5 | H |
| X2 | Geen menubalk: 0x `.commands`, geen sneltoetsen | 0 treffers | `CommandGroup` met Weergave: Overzicht ⌘1, Maand ⌘2, Sparen ⌘3, Plannen ⌘4; Archief: Nieuwe spaarpot ⌘N, Importeren ⌘I, Exporteren; Koersen vernieuwen ⌘R; Instellingen ⌘, | MAC-2, MAC-5 | H |
| X3 | Navigatie als balk onderaan het venster | `RootView.swift:21` | zijbalk (`sidebarAdaptable`) | LAY-8, MAC-4 | H |
| X4 | Geen `.help`-tooltips, geen hover op eigen knoppen; menuknoppen met alleen een symbool zijn op de Mac nauwelijks als knop te herkennen | 0 treffers | `.help("...")` op alle symbolen | MAC-6 | M |
| X5 | Geen rechtermuisklik-menu op rijen | zie L3 | `contextMenu` per rij | LST-8 | M |
| X6 | Geen toetsenbordbediening in de formulieren: `submitLabel`, `onSubmit` en een focusvolgorde bestaan alleen op het inlogscherm (`@FocusState` verder alleen binnen `NumberRow` en `IntStepperRow`); Return bewaart niet | `AuthView.swift:38,267-328` (enige), `Fields.swift:42,108` | focusvolgorde en Return voor "Bewaar" in `SheetScaffold` | ENT-4 | M |
| X7 | Vaste sheetminimums per sheet (460x440 en vergelijkbaar, 9 plekken); geen `windowResizability` | `Fields.swift:395`, `SettingsView.swift:149`, `AuthView.swift:718,793`, `CloudViews.swift:457,565`, `BackupUI.swift:627`, `BlockOrder.swift:247`, `AcceleratorPages.swift:372` | `presentationSizing(.form)` | MAC-1 | L |

### 3.14 iPad

| # | Tekortkoming | Waar | Voorstel | HIG | Prio |
|---|---|---|---|---|---|
| I1 | Geen zijbalk; 0x `horizontalSizeClass`; de zwevende tabbalk is 460 pt breed midden onderin | `RootView.swift:126`, 0 treffers | `TabView(.sidebarAdaptable)` | IPD-2, LAY-5 | H |
| I2 | Sheets op iPad in standaardgrootte (smal), Instellingen krampachtig in een formulier-sheet | zie S4 | pagina of `presentationSizing(.form)` | IPD-4 | M |
| I3 | Geen toetsenbord- en aanwijzerondersteuning (`keyboardShortcut`, `hoverEffect`: 0) | 0 treffers | sneltoetsen uit X2, `hoverEffect` op eigen kaarten | IPD-5, IPD-6 | M |
| I4 | Enkelkoloms pagina's lopen tot 960 pt | `Theme.swift:41` | leesbare breedte | LAY-7 | M |

### 3.15 Wat al goed is

- Alle iOS 26-API's staan achter `#available(iOS 26.0, macOS 26.0, *)` met een terugval (`Glass.swift:10,42`), `preferredColorScheme` komt niet voor (volgt het systeem), en er is geen eigen schakelaar voor weergave, taal of haptiek.
- `NumberRow` en `AmountParser` lezen Nederlandse invoer (`12,5`, `1.234,56`) zonder een ander getal te geven, met het decimale toetsenbord (`Fields.swift:44-95`, `Formatting.swift:140-168`).
- `StepButton` (`Components.swift:348-366`) is 44x44 en heeft een label; `PurchaseStepBar` en categoriekeuze melden hun stand (`PurchasePages.swift:130-131,386-387`); de tabbalk markeert de geselecteerde tab (`RootView.swift:121`).
- Bedragen krijgen `.contentTransition(.numericText())`, animaties zijn kort (0,25 tot 0,3 s) en volgen een waarde, niet elke frame.
- Destructieve acties zijn rood en vragen bevestiging met het gevolg erbij (`PotPages.swift:270-295`, `SettingsView.swift:118-146`); `SecureField` voor wachtwoorden; `textContentType` voor wachtwoordhulp (`AuthView.swift:561-609`).
- SF Symbols als pictogrammen; geen eigen afbeeldingen.

---

## 4. Eenvoud-toets: wat is moeilijk te vinden of uit elkaar te houden

### 4.1 Gelijknamige of overlappende onderdelen

| # | Onderdeel | Wat er nu is | Overlap of onduidelijkheid | Vereenvoudiging |
|---|---|---|---|---|
| E1 | **Overzicht** | Home-blok "Overzicht" (altijd deze maand), Savings-blok "Overzicht" (volgt de periodekeuze) en de pagina "Overzicht"; beide blokken openen dezelfde pagina | drie keer dezelfde naam, twee gedragingen, plus een tab "Home" die zelf ook een overzicht is | de tabwortel "Overzicht" is de pagina; beide blokken en de aparte pagina vervallen; periodekeuze (Maand, Half jaar, Jaar) staat alleen daar |
| E2 | **Nog te verdelen** | zelfde getal (`remaining(in:)`) onder 4 namen op 10 plekken: Home-kaart `HomeView.swift:128-145`, Home-tegel "Over deze maand" met onderschrift "Nog te verdelen" `:244-246`, Savings "Over" `SavingsView.swift:61,228`, Savings-blok "Verdelen" `:130-137`, Overzicht "Over deze maand" en "Over" `SavingsPages.swift:30-52` (daar staat ook "Gemiddeld over per maand", een gemiddelde en dus een ander getal), Verdelen "Nog te verdelen" `:1408`, Bank "Over op de rekening" `:1734`, Dag voor dag "Nog te verdelen" `CashflowPages.swift:812`; "Over na uitgaven" `:1729` is een andere tussenstand | de gebruiker kan niet zien dat het hetzelfde getal is | een term: "Nog te verdelen" voor de huidige en komende maanden, "Overgehouden" voor afgelopen maanden en perioden; nooit kaal "Over" |
| E3 | **Inkomen** | "Salaris & inkomsten" (pagina, blok), "Salaris en inkomsten" (`SavingsPages.swift:1722`), "Inkomen" (tegels), "Overige inkomsten" (`:609`) tegenover "Overig" (tegel `SavingsView.swift:99`) | vier benamingen voor twee dingen | pagina "Inkomen" met onderdelen "Salaris" en "Overige inkomsten"; tegels dezelfde woorden |
| E4 | **Uitgaven** | geen pagina of blok "Uitgaven": ze staan als "Vaste uitgaven" en "Variabele uitgaven" onderaan Bankrekening (`SavingsPages.swift:1623-1624`); tegels heten "Vast" en "Variabel" (`SavingsView.swift:226-227`), "Bankuitgaven" (`HomeView.swift:155`), "Uitgaven deze maand" (`SavingsPages.swift:613`); de import spreekt van "vaste lasten" (`BackupUI.swift:10,290,972`); `Destination.expenses` bestaat maar opent Bankrekening | het belangrijkste onderdeel om te vullen is het moeilijkst te vinden | eigen pagina "Uitgaven" (Vast / Variabel) op 1 tik vanaf de tab; "lasten" overal "uitgaven"; "Bankuitgaven" wordt "Van je rekening" |
| E5 | **Bankrekening, Dag voor dag, Per dag, Komende 14 dagen** | Bankrekening bevat al "Per dag" (dagkiezer + grafiek) en "Komende 14 dagen"; de pagina "Dag voor dag" heeft dezelfde grafiek (`DayBalanceChart`, `CashflowPages.swift:517` en `:942`), een eigen bank-blok (`CashflowBankBlock` tegenover `BankFlowBlock`) en een eigen maandoverzicht (`CashflowOverviewBlock` tegenover pagina Overzicht); drie plekken met een eigen sluitcontrole ("Klopt met je dagoverzicht", `CashflowCheckBanner`, "Klopt met je overzicht") | drie pagina's tonen dezelfde maand uit een andere hoek | een pagina Bankrekening met segmenten Saldo / Dag voor dag / Boekingen; "Dag voor dag" is geen aparte bestemming meer; een melding bij afwijking in plaats van drie bevestigingen |
| E6 | **Verdelen, Inleg, Overschrijvingen, Overschrijfdag** | "Verdelen" (pagina, blok, kaart, chip "Geld verdelen"), "Overschrijvingen" (blok op Bankrekening met een kop naar Verdelen; toont dezelfde bedragen), "Inleg" (blok op Spaarpot en Belegging), "Overschrijfdag" op 3 plekken (`SavingsPages.swift:1483`, `PotPages.swift:882-893`, `PortfolioPages.swift:498-510`); inleg wordt ingesteld in het pot- of beleggingsformulier (de standaard), op Verdelen (per maand) en gelezen in de blokken "Inleg" | elk van de drie spreekt zijn eigen taal ("Standaard", "Maak dit je standaard", "Afwijkend") | "Inleg" voor het bedrag per pot of belegging, "Verdelen" voor de maandactie, "Overschrijfdag" voor de dag; het blok "Overschrijvingen" vervalt (zelfde cijfers staan op Verdelen) |
| E7 | **Buffer** | "Buffer" (blok, pagina, calculator, pot, door de aankoopcheck gelezen), "Bankbuffer" (blok op Bankrekening, `SavingsPages.swift:1946`), "Buffer op bankrekening" (Instellingen), "Gewenste bankbuffer" (tegel), "Doelbuffer", "Spaarpot Buffer", "Buffercalculator" (chip) | twee verschillende begrippen (noodgeld en minimumsaldo) onder dezelfde stam | "Noodbuffer" voor de calculator en de pot; "Minimumsaldo" voor wat op de betaalrekening moet blijven, op een plek in te stellen (zie par. 2.3 punt 5) |
| E8 | **Doelen, Spaardoel, Streefbedrag** | vier manieren om een doel in euro te maken (pot met doelbedrag en datum `PotPages.swift:872-879`; levensdoel `GoalEditSheet`; spaardoel-calculator; buffer-calculator) en vijf plekken die uitrekenen "hoeveel per maand en wanneer klaar": spaardoel-calculator (`SavingsGoalPages.swift:171-194`), Toekomstschatting "Streefbedrag" (`ProjectionPage.swift:140-143`), Buffer "Hoe snel?" (`BufferPages.swift:317-354`), Doel "Zo is het berekend" (`GoalPages.swift:386-407`), Spaarpot-doeltekst (`PotPages.swift:597-626`) | vijf rekenmachines, drie datamodellen, twee tabs | een plek "Doelen"; "Nieuw doel" kiest het soort (levensdoel, sparen voor een bedrag, noodbuffer); een spaarpotdoel is hetzelfde doel; Toekomstschatting blijft de vrije rekenmachine |
| E9 | **Versnellers** | pagina in Tools en dezelfde `AcceleratorsSection` ingebed in elk Doel (`GoalPages.swift:409`) | twee ingangen voor hetzelfde, in twee tabs | alleen in het Doel; het Tools-blok en de pagina vervallen |
| E10 | **Home, Savings, Tools** | Engelse namen; Tools bevat drie niet-verwante dingen (doelhulp, schatting, aankoop) | "Savings" bevat geld in en uit, spaarpotten, beleggingen, buffer en doelen | zie 4.5 |
| E11 | **Rendement** | "Rendement" als bedrag in euro (`PortfolioPages.swift:42,224`) en als percentage ("Rendement per jaar", "Verwacht rendement", "Rendement na kosten"); daarnaast "Rente", "Spaarrente", "Rentepercentage", "Rente per jaar" | een woord met twee betekenissen, twee woorden voor een betekenis | "Winst" voor euro's, "Rendement per jaar" voor procenten, "Rente" alleen voor een spaarpot |
| E12 | **Instellingen / Bewerken** | "Instellingen" = app-instellingen, maar ook een knop op Belegging (`PortfolioPages.swift:251`) en "Doel en instellingen" op Spaarpot (`PotPages.swift:455`); "Rente aanpassen", "Rente instellen" en "Doel en instellingen" openen dezelfde sheet (`PotPages.swift:455,490,500`), "Instellingen" en "Inleg aanpassen" ook (`PortfolioPages.swift:251,280`) | drie namen voor een bewerkformulier | een toolbarknop "Bewerken" per pagina |
| E13 | **Saldo** | "Saldo nu", "Saldo van vandaag", "Saldo aan het eind van vandaag", "Eind van <maand>", "Vermogen eind <maand>", "Verwacht saldo" | zes formuleringen voor twee momenten | "Saldo vandaag" en "Verwacht eind <maand>" |
| E14 | **Dag voor dag** | "Dag voor dag" (pagina en blok), "Per dag" (blok), "Per dag bekijken", "Dag voor dag bekijken", "Alle dagen bekijken", "dagoverzicht" (in teksten) | zes namen voor een onderdeel | "Dag voor dag" overal |
| E15 | **Meetpunt** | jargon in `PortfolioPages.swift:289,291` ("Meetpunten", "Nog geen meetpunten") en de uitleg van "Waarde bijwerken" | begrip dat alleen de ontwikkelaar kent | "Waarde-updates" |
| E16 | **Kies potten voor Home / Kies beleggingen** | 2 sheets, 5 aanroepen, 3 chips, een lege-plek-tegel; de kop van de beleggingskeuze zegt "beleggingssoorten" terwijl je beleggingen kiest (`HomeView.swift:562`) | een functie voor een detail van een paginaonderdeel | weg: het Overzicht toont de drie grootste potten en beleggingen met een link "Alle" |
| E17 | **Mijn beleggingen** | `PortfolioPages.swift:84` naast "Beleggingen" | bezittelijk voornaamwoord, dubbele naam | "Alle beleggingen" of geen kop |

### 4.2 Pagina's met te veel blokken

| Pagina | Kaarten | Bedieningselementen | Voorstel |
|---|---|---|---|
| Dag voor dag | 32 tot 39 (4 tot 8 + 28 tot 31 dagkaarten) | per dagkaart 2 tegels + rijen + 2 saldorijen | maandsamenvatting als 1 kaart, grafiek, daaronder een `List` met een sectie per dag |
| Bankrekening | 8 vast + 4 voorwaardelijk | 5 chips, 2 lijsten met "Toevoegen", datumkiezer, keuze 30 dagen of maand | segmenten Saldo / Dag voor dag / Boekingen en een aparte pagina Uitgaven; maximaal 4 kaarten per segment |
| Savings (tab) | 9 | periodekeuze die voor maar 4 van de 8 blokken geldt | verdwijnt in 4.5 |
| Spaarpot | 7 + verwijderknop | 4 chips voor bewegen, 5 knoppen die een formulier openen | 3 kaarten (Saldo, Komende boekingen, Geschiedenis); bewegen en bewerken in de toolbar; rente en saldo op datum naar het formulier of een uitklapper |
| Buffer | 7 | 3 velden, 3 keuzemenu's, 2 schakelaars, 2 schuiven, 4 knoppen | 3 kaarten: Jouw situatie (ingeklapt), Uitkomst met voortgang en verloop, Spaarpot aanmaken als actie |
| Spaardoel-calculator | 8 (5 afhankelijk) | 6 velden, 3 keuzes, 2 schakelaars, 6 knoppen | 4 kaarten: Uitkomst, Invoer, Verloop, Details in een uitklapper |
| Salaris & inkomsten | 5 | 15 tot 25 | hoofdpagina: deze maand + Overige inkomsten; "Standaard salaris" en schema naar een subpagina "Salaris instellen" |
| Home | 4 kaarten, 14 tegels, 2 grafieken | 5 chips | 3 kaarten, zonder dubbele cijfers (4.3) en zonder "Kies ..."-chips |
| Instellingen | 10 secties, 29 rijen | zie par. 2 | 6 groepen, 16 rijen |

### 4.3 Blokken die dezelfde cijfers herhalen

| # | Waar | Herhaling | Oplossing |
|---|---|---|---|
| H1 | Home | "Nog te verdelen" `HomeView.swift:145` en direct eronder de tegel "Over deze maand" `:244` (zelfde getal) | tegel weg |
| H2 | Home Spaarpotten | subtitel "Totaal <bedrag>" `:263` en tegel "Totaal gespaard" `:300` | subtitel weg |
| H3 | Overzicht | groot bedrag "Over deze maand" `SavingsPages.swift:33` en tegel "Over" `:50` | tegel weg |
| H4 | Salaris & inkomsten | totaal `:472` en tegel "Salaris" `:517`; tegel "Inkomen" met onderschrift "in je overzicht" `:519` | tegels weg |
| H5 | Bankrekening | saldo vandaag 3 keer in de eerste 4 kaarten (`:1654`, `CashflowPages.swift:462`, grafiek), eindsaldo van de maand 3 keer (`:1656`, `:1783`, "Verwacht verloop") | saldo op een plek, de dagkiezer alleen als de gekozen dag niet vandaag is |
| H6 | Bankrekening en Verdelen | "Binnen en eruit" (`:1712-1736`) en "Nog te verdelen" (`:1408-1418`) en "Overschrijvingen" (`:1860`) tonen inkomen, uitgaven en verdeeld drie keer | een bron per scherm |
| H7 | Spaarpot | saldo in "Saldo" `PotPages.swift:318`, in tegel "Saldo nu" `:356`, in "Saldo op datum" `:516` (standaard een maand vooruit) en in een regel "Verwacht eind" `:334` | een groot saldo plus verwachting |
| H8 | Beleggingen en Belegging | winst als `GainLabel` en als tegel "Rendement" in hetzelfde blok (`PortfolioPages.swift:38,42`; `:219,224`) | een van beide |
| H9 | Dag voor dag | blok "Bankrekening" (saldo nu, laagste saldo) herhaalt Bankrekening; "Je overzicht" herhaalt Overzicht (`CashflowPages.swift:730-838`) | verwijderen of vervangen door een link |
| H10 | Verdelen en Home | tegels Inkomen / Uitgaven / Verdeeld zijn de drie mini-tegels van `RemainingHeader` | een kaart |
| H11 | Zes schermen | de zin "Waarvan € x uit spaarpotten. Dat telt niet mee in Over." staat op 5 plekken (`SavingsPages.swift:38,1420`, `SavingsView.swift:66,233`, `HomeView.swift:166`), de afrondingsnotitie op 4 plekken (`SavingsPages.swift:60,1425`, `HomeView.swift:171`, `CashflowPages.swift:769`) | een tekst, bij een (i)-knop of onder de pagina |

### 4.4 Wat hoort bij elkaar

| Groep | Onderdelen en waar ze nu staan | Gebruik |
|---|---|---|
| Overzicht | tab Home, pagina Overzicht, Savings-blok Overzicht, Vermogen | wat staat er nu |
| Maand | Salaris & inkomsten, Uitgaven (verstopt), Verdelen, Bankrekening, Dag voor dag (verstopt) allemaal in Savings of nergens | elke maand |
| Sparen | Spaarpotten en Beleggingen (Home en Savings), Buffer-pot | af en toe |
| Plannen | Doelen, Spaardoel, Buffer (Savings) en Versnellers, Toekomstschatting, Aankoopcheck (Tools) | zelden |
| Beheer | Instellingen, Account, Back-up | zelden |

### 4.5 Voorstel navigatiestructuur (invoer voor de ontwerper)

```
TabView (.sidebarAdaptable; iPad en Mac: zijbalk)
 1 Overzicht    Nog te verdelen (kaart naar Verdelen) · Waar gaat je geld heen (grafiek, periodekeuze)
                · Vermogen (3 rijen naar Bankrekening, Spaarpotten, Beleggingen) · Komende dagen
 2 Maand        lijst: Inkomen · Uitgaven · Verdelen · Bankrekening (segmenten Saldo / Dag voor dag / Boekingen)
 3 Sparen       Spaarpotten (met noodbuffer) · Beleggingen (met knop Toekomstschatting)
 4 Plannen      Doelen (levensdoel, sparen voor een bedrag, noodbuffer, versnellers per doel)
                · Toekomstschatting · Aankoopcheck
 5 Instellingen Account (rij bovenaan) · Rekenen · Koersen · Gegevens · Indeling · Over   [Mac: Settings-scene]
```

| Nu | Straks |
|---|---|
| 3 tabs (Home, Savings, Tools) | 5 (Overzicht, Maand, Sparen, Plannen, Instellingen) |
| 18 pagina's + Instellingen en inlog | 15 (5 tabwortels + Inkomen, Uitgaven, Verdelen, Bankrekening, Spaarpot, Belegging, Doel, Toekomstschatting, Aankoopcheck, Account) |
| 17 sheetsoorten | 8: Spaarpot bewerken, Spaarpot bewegen, Belegging bewerken, Waarde bijwerken, Regel (inkomen/uitgave), Bankactie, Doel bewerken, Versneller toepassen; Instellingen, volgorde, wachtwoord, verwijderen, import en de twee keuzelijsten worden pagina's of vervallen |
| Pagina's op een tab: tot 39 kaarten | maximaal 5 kaarten of een `List` |
| Uitgaven toevoegen: 4 tikken + scrollen | 3 tikken zonder scrollen (Maand, Uitgaven, Toevoegen) |
| Instellingen: 10 secties | 6 groepen |

### 4.6 Termenlijst (een woord per begrip)

| Begrip | Vaste naam | Vervangt |
|---|---|---|
| wat er van het maandinkomen overblijft | Nog te verdelen (nu en komend), Overgehouden (verleden, periode) | Over, Over deze maand, Over op de rekening, Overschot, Gemiddeld over |
| salaris en extra inkomsten | Inkomen: Salaris, Overige inkomsten | Salaris & inkomsten, Salaris en inkomsten, Inkomsten, Overig |
| kosten | Uitgaven: Vast, Variabel | lasten, Bankuitgaven, Vast/Variabel als losse tegel |
| bedrag naar pot of belegging per maand | Inleg | Overschrijving, Verdeeld (als bedrag) |
| dag van de overschrijving | Overschrijfdag | Eigen overschrijfdag inleg, Overschrijfdag inleg |
| minimum op de betaalrekening | Minimumsaldo | Bankbuffer, Buffer op bankrekening, Gewenste bankbuffer |
| noodgeld | Noodbuffer | Buffer, Spaarpot Buffer |
| bedrag-doel | Doel | Spaardoel, Streefbedrag (veldnaam Doelbedrag mag) |
| winst in euro's | Winst | Rendement (euro) |
| procent per jaar | Rendement per jaar | Verwacht rendement, Rendement na kosten, Spaarrente (rente blijft voor potten) |
| saldo | Saldo vandaag, Verwacht eind <maand> | Saldo nu, Saldo van vandaag, Saldo aan het eind van vandaag |
| dagoverzicht | Dag voor dag | Per dag, Alle dagen, dagoverzicht |
| gemeten waarde | Waarde-update | Meetpunt |
| bewerken | Bewerken | Instellingen, Doel en instellingen, Rente aanpassen, Inleg aanpassen |

### 4.7 Zoeken ontbreekt

De app heeft geen zoekfunctie (`.searchable`: 0 treffers) terwijl onderdelen op 18 pagina's en in 17 sheets verspreid staan en tien ervan moeilijk te vinden zijn (par. 1.5). Voorstel: `.searchable` op het Overzicht (iPhone: `Tab(role: .search)`, iPad en Mac: bovenaan de zijbalk) met resultaten uit (1) een vaste index van de pagina's met hun alternatieve namen ("Uitgaven", "Dag voor dag", "Noodbuffer", "Rente", "Back-up", "Wachtwoord"), (2) namen van spaarpotten, beleggingen en doelen, (3) regels van inkomen en uitgaven. Een resultaat opent de pagina of het formulier. Dit lost de vindbaarheid op zonder de structuur af te hangen van de naam die iemand zich herinnert (HIG SRC-1 t/m SRC-3).

---

## 5. Eindrapport

### De 10 grootste problemen

| # | Probleem | Bestand | Voorstel |
|---|---|---|---|
| 1 | Instellingen is een sheet met 10 secties, sheets in de sheet, account midden tussen rekeninstellingen, en een account is verplicht om te beginnen | `RootView.swift:26`, `SettingsView.swift:18-151`, `CloudViews.swift:34-44`, `MyBuddyApp.swift:86-102` | volledige pagina (Mac: `Settings`-scene), Account als eigen pagina, 6 groepen (par. 2.4), account optioneel |
| 2 | Eigen tabbalk, pad wordt gewist bij tabwissel, Engelse namen, geen zijbalk op iPad en Mac | `RootView.swift:86-149`, `Router.swift:66-73`, `Router.swift:10-12` | `TabView(.sidebarAdaptable)`, pad per tab bewaren, 5 Nederlandse tabs (par. 4.5) |
| 3 | Beleggingengrafiek (en andere) werkt niet met wat je invult: zonder "Huidige waarde" geen waarde, geen punten en "Totaal ingelegd" telt niet mee; bewerken van "Totaal ingelegd" doet niets; "Terugkijken" doet niets; Home tekent een lege vlakte | `Invest.swift:38-41,152-170`, `PortfolioPages.swift:493-494,706`, `HomeView.swift:414`, `SavingsView.swift:276`, `Charts.swift:75-87` | startpunt uit `investedTotal` zonder meetpunt, lege staat bij minder dan 2 punten, tweede lijn "Ingelegd" (par. 3.11) |
| 4 | Alle inhoud staat in glas (115 kaarten) en elke knop is glas in glas (86 chips) | `Components.swift:70,298`, `RootView.swift:125,139` | inhoud in `List`/`Form`/materiaal, knoppen in `.bordered`, glas alleen voor de bedieningslaag |
| 5 | Het belangrijkste is moeilijk te vinden: uitgaven zitten als blok 7 van 12 in Bankrekening, Dag voor dag alleen via een chip, rekenhulpen verdeeld over Savings en Tools | `SavingsPages.swift:1623-1624`, `GoalPages.swift:240-255`, `ToolsView.swift:22-28` | tabs Overzicht, Maand, Sparen, Plannen (par. 4.5): Uitgaven op 2 tikken |
| 6 | Overvolle pagina's en herhaalde cijfers: Dag voor dag 32 tot 39 kaarten, Bankrekening 12, Buffer 7, Spaarpot 7, hetzelfde getal 2 tot 3 keer op een pagina | `CashflowPages.swift:985-991`, `SavingsPages.swift:1613-1629`, `HomeView.swift:145,244` | `List` met secties per dag, segmenten, maximaal 5 kaarten (par. 4.2 en 4.3) |
| 7 | Een begrip, meerdere namen: "Nog te verdelen" heet op 10 plekken 4 dingen, "Buffer" 7 dingen, inkomen 4, "Instellingen" 3, "Rendement" 2 betekenissen | zie par. 4.1 | termenlijst par. 4.6, een woord per begrip |
| 8 | Dynamic Type en aanraakdoelen: 5 vaste groottes, 49 krimpende teksten, vaste drie kolommen, knoppen van 42 pt, menuknoppen van 22 pt, 0 swipe-acties | `HomeView.swift:153-157,271-276`, `Theme.swift:39`, `SavingsPages.swift:788-797` | tekststijlen, `ViewThatFits`, 44 pt, swipe-acties en `List` |
| 9 | Contrast en toegankelijkheid: licht `.secondary` 2,8 tot 3,2:1 op 279 plekken, `warning` 2,5 tot 3,4:1, wit op donker accent 2,0:1, 6 van 8 grafieken zonder label, geen Reduce Motion of Transparency, geen koppen | `Theme.swift:60-63`, `Components.swift:81,148-192`, `Charts.swift:53-164` | kleuren uit par. 3.5, labels en koppen, `accessibilityReduce*` |
| 10 | macOS en iPad: geen Settings-scene, menubalk, sneltoetsen, zijbalk, tooltips of rechtermuisklik; balk onderin het Mac-venster | `MyBuddyApp.swift:20-41`, `RootView.swift:21` | `.commands`, `Settings`, `sidebarAdaptable`, `.help`, `contextMenu` per rij |

### Hoeveel vandaag

| Wat | Aantal |
|---|---|
| Tabs | 3 |
| Pagina's | 18 (3 tabwortels + 15 paginatypen, 17 `Destination`-cases) plus inlog en Instellingen |
| Sheets | 17 soorten, 26 plekken (5 soorten daarvan sheet-in-sheet), plus 4 bestandsdialogen en 17 bevestigingsdialogen |
| Blokken | 103 inhoudsblokken (91 `GlassBlock` + 12 `LinkedBlock`) en 12 losse glaskaarten; per scherm 3 (Tools) tot 39 (Dag voor dag) |
| Glazen knoppen | 86 |
| Grafieken | 8 soorten, 17 plekken |

### Volgorde van aanpak (voorstel)

1. **Grafiek en cijfers van beleggingen** (par. 3.11, C1 t/m C4): klein, raakt `Invest.swift` en drie schermen, lost een gemelde fout op en is onafhankelijk van de rest.
2. **Termenlijst en teksten** (par. 4.1, 4.3, 4.6, 2.3): alleen tekst, geen structuurwijziging; maakt de latere stappen eenduidig.
3. **Instellingen en Account als pagina** (par. 2.4): vraagt dat `AppStore` en `Router` boven de scenes staan (Mac) en haalt 6 sheets en `BackupHost` weg.
4. **Navigatie** (par. 4.5, 3.2): `TabView(.sidebarAdaptable)`, 5 Nederlandse tabs, pad per tab; raakt `RootView`, `Router`, `HomeView`, `SavingsView`, `ToolsView`, `DestinationView` en alle ingangen van par. 1.5.
5. **Componenten**: `GlassBlock`/`ChipButton` vervangen door `List`/`Form` en systeemknoppen, rij-acties, `ContentUnavailableView`, 44 pt (par. 3.3, 3.6, 3.10). Dit raakt bijna elk paginabestand; doe het per pagina na stap 4.
6. **Toegankelijkheid en contrast** (par. 3.5, 3.7, 3.8): kleurenset, labels, koppen, grafiekbeschrijvingen, Reduce Motion en Transparency; ook door te voeren terwijl stap 5 loopt.
7. **Mac en iPad** (par. 3.13, 3.14): menubalk, sneltoetsen, `Settings`-scene, `.help`, zoeken.

---

## 6. Bewijs en reproduceren

**Tellingen** (vanaf `/home/user/MyBuddy`, alleen lezen):

```
grep -rn "\.font(\.system(size" App                       # 5
grep -rn "minimumScaleFactor" App --include=*.swift       # 49
grep -rn "GlassBlock(" App --include=*.swift              # 92 (91 aanroepen + 1 in LinkedBlock)
grep -rn "LinkedBlock(" App --include=*.swift             # 12
grep -rn "\.sheet(" App --include=*.swift                 # 26
grep -rn "confirmationDialog(" App --include=*.swift      # 17
grep -rn "ChipButton(\|ChipLink(\|ChipLabel(" App         # 77 + 6 + 5 (2 daarvan in de definities)
grep -rn "accessibilityLabel\|accessibilityElement\|accessibilityAddTraits\|accessibilityHint\|accessibilityValue" App   # 33
grep -rn "foregroundStyle(.secondary)\|foregroundStyle(Color.secondary)" App   # 279
grep -rn "swipeActions\|TabView\|ContentUnavailableView\|\.commands\|keyboardShortcut\|\.help(\|accessibilityReduce" App   # 0
```

**Contrast**: `/tmp/claude-0/-home-user-MyBuddy/9beb118c-8e88-5a84-a4b5-426733aaf64d/scratchpad/audit/contrast.py` (Python 3). Rekent WCAG-contrast van de kleuren in `Theme.swift` tegen de negen `meshLight`/`meshDark`-kleuren, met en zonder een `.tile()`-laag (zwart of wit met 7% dekking). Glas, vibrancy en materiaal zijn niet meegerekend; de echte waarden liggen daar in de buurt maar kunnen afwijken. `.secondary` is gerekend als `#3C3C43` (licht) of `#EBEBF5` (donker) met 60% dekking.

**Beleggingsproef**: `/tmp/probe-audit` (Swift-pakket dat `App/Core` symlinkt, `@testable import`, uitvoer in `/tmp/probe-audit/output.txt`):

```
export PATH=/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin:$PATH
cd /tmp/probe-audit && swift build --scratch-path /tmp/sb-audit -Xswiftc -enable-testing && /tmp/sb-audit/debug/probe
```

Uitvoer (huidige maand 2026-10, `*` = verwacht):

```
A. zonder 'Huidige waarde': waarde = 0.0 | ingelegd = 0.0 | punten = 0
B. 'Terugkijken' 6/12/36 mnd: punten = 13 | eerste = 2026-10 | echte punten = 1       (alle drie gelijk)
B. reeks: 2026-10=4800 2026-11=5022* ... 2027-04=6151*
C. gevolgd, nog geen koers: waarde = 0.0 | punten = 0   ->  na koers 120: waarde = 1200.0, 7 punten
D. voorbeelddata 'Terugkijken' 6/12/36 mnd: punten = 18 | eerste = 2026-05            (alle drie gelijk)
F. bewerkscherm 'Totaal ingelegd' 5000 -> 6000: getoonde ingelegd = 5000.0 | opgeslagen = 6000.0
F. via 'Waarde bijwerken' (6000): getoonde ingelegd = 6000.0
G. inkomen = 3000.0 uitgaven = 3500.0 over = -500.0 -> balk 'Over' = 0.0
```

**Grenzen van dit onderzoek**: SwiftUI is hier niet gecompileerd of gedraaid. Maten van aanraakdoelen, het gedrag bij grote tekst, iPad en Mac zijn uit de code afgeleid, niet gemeten op een apparaat. De beleggingsproef toont het gedrag van de rekenmotor; hoe de grafiek er daarna precies uitziet (stip, stippellijn, lege vlakte) volgt uit `Charts.swift:53-94` en de aanroepen in `HomeView.swift`, `SavingsView.swift` en `PortfolioPages.swift`.
