# MyBuddy v3: ontwerp en afspraken

Dit document is het gedeelde contract voor alle bouwers. Wie een bestand "bezit", mag het aanpassen.
Alle andere bestanden alleen lezen. Moet je iets in een bestand van een ander veranderen: zet het
onder **WIRING** in je eindrapport.

**Stand na ontwerp 2 (Apple Muziek en Apple TV).** De rekenmotor, de modelvelden en de afspraken over bedragen en tests hieronder
gelden ongewijzigd. De schermen zijn vervangen: drie tabs (Home, Bibliotheek, Zoeken), Instellingen achter een profielknop, planken en
albumpagina's in plaats van blokken met glas. De paragrafen "Blokken en pagina's (UI)" en "Blokken verplaatsen" beschrijven de huidige
stand (blok-id's, bestemmingen, termen); de opbouw van het ontwerpsysteem staat in `system_architecture.md` en alle besluiten in
`docs/design2/plan.md`. De tabel "Eigendom per bouwer" is die van de v3-bouw en alleen nog historisch: het eigendom van ontwerp 2 staat in
`docs/design2/plan.md` (blok "Eigendom per golf", gecontroleerd door `docs/design2/own-check.sh`).

## Algemene afspraken

- Alle tekst in de UI is Nederlands, "je"-vorm, kort. Code-commentaar Nederlands, zoals in de rest van de app.
- Swift 5-modus, iOS 18 / macOS 15, SwiftUI, `@Observable`. Geen nieuwe pakketten of dependencies.
- `App/Core/*` is Foundation-only en compileert ook op Linux (tests). Netwerk: `#if canImport(FoundationNetworking) import FoundationNetworking #endif`.
- **Bedragen worden altijd afgerond getoond**: `Fmt.euro(x)` (= hele euro's). Alleen eenheidsprijzen waar centen
  ertoe doen (uurloon, koers, rente-uitkomst onder 10 euro) gebruiken `Fmt.euroExact(x)`. Percentages: `Fmt.percent(x)` (max 1 decimaal).
  Rekenwaarden in Core blijven op centen (`.cents`); afronden is een weergaveregel. Invulvelden mogen wel decimalen tonen.
- Elke nieuwe pagina: `PageScaffold(title:)` (kaarten) of `ListScaffold(title:)` (lijst), kaarten met `Card`/`LinkCard`, knoppen in de
  inhoud met `PillButton`/`PillLink` of `ActionButton`/`ActionLink` (minimaal `Theme.minTapTarget` hoog), tegels met `.tile()`/`StatTile`,
  lijstrijen met `MediaRow`/`MediaRowLabel`. Een pagina die in de Bibliotheek of Zoeken moet staan krijgt een regel in `PageCatalog`.
  Kijk naar bestaande pagina's voor de stijl en naar `system_architecture.md` ("Ontwerpsysteem v2").
- Animaties: gebruik `Theme.motion`/`Theme.quickMotion` (`.smooth`/`.snappy`, kort, 0.25-0.35s) via `.animated(by:)`, dat Verlaag
  beweging respecteert. Bedragen krijgen `.contentTransition(.numericText())`; lijsten/blokken animeren bij toevoegen/verwijderen.
  Geen harde sprongen, geen animatie op elke frame van een slider-drag.
- Elk nieuw `Codable` veld: `decodeIfPresent` met standaardwaarde (oude bestanden moeten blijven laden).
- Tests: elke Core-wijziging krijgt XCTest-tests in `CoreTests/Tests/MyBuddyCoreTests/`. Verwachte waarden onafhankelijk
  narekenen (geen implementatie kopiëren). Tests mogen niet van de klok afhangen (gebruik vaste datums, `day(m, d)` helper).

## Verifiëren (lokaal)

```
export PATH=/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin:$PATH
cd /home/user/MyBuddy/CoreTests && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -20
```
Dit compileert `App/Core` + alle tests en draait ze. **Core moet altijd groen zijn voordat je klaar meldt.**
SwiftUI-bestanden kunnen hier niet gecompileerd worden. Controleer die met de syntaxcheck én door elke aanroep naar
een ander bestand letterlijk te vergelijken met de definitie (naam, labels, volgorde, typen, optionals):
```
P=/tmp/claude-0/-home-user-MyBuddy/9beb118c-8e88-5a84-a4b5-426733aaf64d/scratchpad
$P/venv/bin/python $P/check_swift.py App/Pages/<bestand>.swift
```
Let extra op de bekende valkuilen: tuple-destructuring in `ForEach` (gebruik Identifiable structs), `if` binnen
`AxisContentBuilder` (grafieken staan in `Charts.swift`; schrijf geen eigen assen), schaduwende namen in initializers, `@Bindable` voor
`@Observable` bindings, `private` properties die buiten het type gebruikt worden, ontbrekende `import Charts`, iOS 26-API's buiten
`#available`, alleen-iOS-API's buiten `#if os(iOS)`.
De hele app (ook de SwiftUI-laag) controleer je met de nagebootste typecheck `/tmp/ctl-all/run-all.sh` (0 fouten vereist); die vervangt
Xcode niet.

## Nieuwe modelvelden (staan al in `Models.swift`, niet hernoemen)

- `SalarySettings.payDay` (standaard 25): dag waarop salaris en extra inkomsten (zonder eigen dag) binnenkomen.
- `MoneyLine.day: Int?` (1...31) en `MoneyLine.potShares: [PotShare]`; helpers `fromPots`, `fromBank`, `[MoneyLine].totalFromPots`.
  Inkomsten: dag = `day ?? payDay`. Uitgaven: dag = `day ?? 1`. Bij een uitgave gaat `fromBank` van de bank en elk `PotShare` uit zijn pot.
- `MonthPlan.transferDay: Int?`: overschrijfdag voor de hele maandverdeling. Volgorde: `plan.transferDay ?? pot/holding.transferDay ?? payDay`.
- `Pot.interestRate` (breuk per jaar), `interestPayout` (`InterestPayout`), `interestPayoutDay`, `interestPayoutMonth`, `Pot.transferDay`, `Holding.transferDay`.
- `PotEntryKind.interest` ("Rente") en `.expense` ("Uitgave betaald").
- `AppSettings.blockOrder: [String: [String]]`: eigen blokvolgorde per pagina. Sinds ontwerp 2 leest alleen `"overview"` (Home) een
  volgorde; de sleutels `home`, `savings`, `tools` (v3) en `month`, `saving`, `planning` (ontwerp 1) blijven ongemoeid in de gegevens en
  worden bij het lezen omgezet (`BlockOrderMigration`, alleen lezen).
- `FinanceData.appliedAccelerators: [AppliedAccelerator]` (met `AcceleratorBackup`) en `FinanceData.modifiedAt`.
- `AppStore`: `today`, `onDataChanged`, `applyRemote(_:)`; `mutate` zet `modifiedAt` en slaat niets op als er niets veranderde.

## Rekenmotor (Core): dag voor dag

Bezitter: ENGINE-agent. Bestanden: `YearMonth.swift`, `Plan.swift`, `Pots.swift`, `Bank.swift`, `Overview.swift`,
`Expenses.swift`, `SampleData.swift`, nieuw `DayEvents.swift` en `Interest.swift`, plus de bijbehorende tests.
Andere bouwers coderen tegen **precies deze signaturen**:

```swift
// YearMonth
var dayCount: Int                         // aantal dagen in de maand
func date(day: Int) -> Date               // 12:00 lokale tijd; dag geklemd op 1...dayCount
static func clampedDay(_ day: Int) -> Int // 1...31

// Dagen en regels (Plan.swift)
func salaryDay() -> Int
func incomeDay(of line: MoneyLine) -> Int      // line.day ?? salaryDay()
func expenseDay(of line: MoneyLine) -> Int     // line.day ?? 1
func transferDay(for id: UUID, in month: YearMonth) -> Int
func expensesFromPots(in month: YearMonth) -> Double
func expensesFromBank(in month: YearMonth) -> Double       // expensesTotal - expensesFromPots
// remaining(in:) = income - expensesFromBank - saved - invested   (GEWIJZIGD: pot-betaalde uitgaven kosten dit maandbudget niets)
// MonthSummary krijgt `fromPots: Double`; `remaining` gebruikt dezelfde formule. `expenses` blijft het totaal.

// Dagoverzicht (DayEvents.swift)
enum DayEventKind: String, Codable { case salary, income, expense, toPot, toHolding, interest, bankEntry }
struct DayEvent: Identifiable, Equatable {
    var id: String
    var date: Date                   // op de dag zelf, 12:00
    var day: Int
    var title: String
    var kind: DayEventKind
    var bankAmount: Double           // effect op de bankrekening (+ erbij, − eraf; 0 voor het potdeel van een uitgave en voor rente)
    var potAmount: Double            // effect op een spaarpot (0 als geen pot)
    var potID: UUID?
    var holdingID: UUID?
    var lineID: UUID?
    var isPlanned: Bool              // ligt na het moment `asOf` (zie dayEvents)
}
func dayEvents(in month: YearMonth, asOf today: Date = Date()) -> [DayEvent]   // gesorteerd op datum
func eventsOnDay(_ date: Date, asOf today: Date = Date()) -> [DayEvent]

struct BankDayPoint: Identifiable, Equatable { var date: Date; var balance: Double; var events: [DayEvent]; var id: Date { date } }
func bankBalance(on date: Date) -> Double?          // saldo aan het EIND van die dag; nil zolang er geen saldo bekend is
func bankDailySeries(from: Date, to: Date, asOf today: Date = Date()) -> [BankDayPoint]   // 1 punt per dag, max 800 dagen, alleen vanaf de eerste bekende dag
func lowestBankPoint(in month: YearMonth) -> BankDayPoint?   // laagste dagsaldo van de maand (voor "let op: je gaat onder nul")

// Bank (Bank.swift) - bestaande namen blijven, betekenis wordt dag-nauwkeurig
func bankBalance(at month: YearMonth) -> Double?    // = bankBalance(on: laatste dag van de maand)
func bankBalanceNow(current: YearMonth, today: Date = Date()) -> Double   // saldo van vandaag (of einde van `current` als vandaag daarbuiten valt), 0 als onbekend

// Spaarpotten (Pots.swift)
func potBalance(_ id: UUID, asOf date: Date) -> Double      // saldo aan het eind van die dag
func potBalance(_ id: UUID, at month: YearMonth) -> Double  // = asOf laatste dag van de maand
func potBalanceNow(_ id: UUID, current: YearMonth, today: Date = Date()) -> Double
func totalSaved(current: YearMonth, today: Date = Date()) -> Double
func totalSaved(asOf date: Date) -> Double
// Inleg telt pas mee vanaf de overschrijfdag; uitgaven uit een pot tellen vanaf de uitgavedag; rente vanaf de uitbetaaldag.
// PotTimelineItem krijgt `kind: PotTimelineKind` (.allocation, .manual, .interest, .expense).

// Rente (Interest.swift)
struct InterestPayment: Identifiable, Equatable { var potID: UUID; var date: Date; var amount: Double; var isProjected: Bool; var id: String }
func interestPayments(for potID: UUID, from: Date, to: Date, asOf today: Date = Date()) -> [InterestPayment]  // opgeslagen + verwachte
func nextInterestPayment(for potID: UUID, asOf today: Date = Date()) -> InterestPayment?
@discardableResult mutating func applyDueInterest(upTo date: Date = Date()) -> Int
//   Boekt ontbrekende uitbetalingen ≤ date als PotEntry(kind: .interest) met een DETERMINISTISCHE id (afgeleid van pot + periode),
//   dus twee apparaten of twee aanroepen maken nooit dubbele boekingen. Idempotent.
// Rente per periode = rente/12 × som van het saldo op de eerste dag van elke maand in de periode (alleen maanden vanaf de pot-startmaand),
// afgerond op centen. Geen rente over rente binnen één periode. Een pot zonder rente (0) levert niets op.
```

`AppStore` roept `applyDueInterest` aan bij opstarten en `refreshClock()` (integrator doet dat; ENGINE meldt het onder WIRING).

## Blokken en pagina's (UI)

Tabs (`AppTab`): **Home**, **Bibliotheek** en **Zoeken**. Instellingen is geen tab: de profielknop rechtsboven op de drie wortels opent de
pagina `.settingsRoot` op de stapel van de tab (iPhone en iPad); op de Mac is het het `Settings`-venster. Elke tab heeft een eigen
`NavigationStack` met het pad `router.paths[tab]`; een pagina opent op de stapel waar je bent (`router.open`).

- **Home**: de hero (drie kaarten: Nog te verdelen, Vermogen, Saldo vandaag; geen blok, vast bovenaan) en vijf planken in de volgorde van
  de gebruiker: Komende dagen, Spaarpotten, Beleggingen, Doelen, Hulpmiddelen. Zonder gegevens een welkomstkaart met "Salaris instellen"
  en "Voorbeelddata laden".
- **Bibliotheek**: 13 rijen in drie groepen, daarna Recent. Deze maand: Maandoverzicht, Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor
  dag. Sparen en beleggen: Spaarpotten, Beleggingen. Plannen: Doelen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck.
- **Zoeken**: tien bladertegels (Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag, Spaarpotten, Beleggingen, Doelen, Hulpmiddelen,
  Instellingen), of resultaten per groep.
- Albumpagina's: spaarpot, belegging en doel (`AlbumHeader` als eerste rij van de lijst).

**Bestemmingen** (`enum Destination`, de tabel met titel, symbool, tint en groep is `PageCatalog`): `home`, `library` (alleen wortels),
`flow` (Maandoverzicht), `income`, `salary`, `expenses`, `distribute`, `bank`, `cashflow` (Dag voor dag), `pots`, `pot(id)`, `portfolio`,
`holding(id)`, `goals`, `goal(id)`, `savingsGoal` (vanaf Doelen), `accelerators`, `buffer`, `projection`, `purchase`, `tools` (Hulpmiddelen),
`settingsRoot`, `settings(SettingsPage)`. Een bestemming zonder rij in de Bibliotheek is bereikbaar via zijn ouder (`Destination.parents`,
`PageInfo.reachableFrom`). Maandpagina's (`flow`, `income`, `expenses`, `distribute`, `bank`, `cashflow`) openen vanaf Home, de Bibliotheek en
Zoeken op de huidige maand (`showsCurrentMonth`); daarna bladert de maandbalk.

**Blok-id's voor de volgorde** (`AppSettings.blockOrder`, alleen sleutel `overview` = Home): `upcoming` (Komende dagen), `pots`
(Spaarpotten), `invest` (Beleggingen), `goals` (Doelen), `tools` (Hulpmiddelen). Het id `wealth` uit een eerdere ronde is hero 2 en wordt
bij het lezen overgeslagen. Oude pagina's, nu alleen nog sleutels in de opgeslagen gegevens: `home`: `overview`, `pots`, `invest`;
`savings`: `period`, `income`, `bank`, `distribute`, `pots`, `buffer`, `portfolio`, `goals`; `tools`: `accelerators`, `projection`,
`purchase`; `month`: `flow`, `income`, `expenses`, `distribute`, `bank`, `days`; `saving`: `pots`, `portfolio`; `planning`: `goals`,
`buffer`, `accelerators`, `projection`, `purchase`.

**Termen** (een woord per begrip): tabs **Home**, **Bibliotheek**, **Zoeken**; "Toon alles" (met het label van de plank, bijvoorbeeld "Toon
alle spaarpotten"), **Maandoverzicht**, **Hulpmiddelen**, **Recent**, **Blader**; groepskoppen "Deze maand", "Sparen en beleggen", "Plannen".
"Kies potten voor Home…", "Kies beleggingen voor Home…", bladen "Spaarpotten op Home" en "Beleggingen op Home". Verboden: "Overzicht" als
pagina- of tabnaam (`Importoverzicht` mag), "Savings", "Tools", "Portefeuille".

### Blokken verplaatsen
Niet zichtbaar als knop. Lang indrukken op een plankkop op Home (contextmenu): "Volgorde aanpassen…" opent een sheet met een lijst
(`.onMove`, bewerkmodus altijd aan) + "Klaar" en "Standaardvolgorde"; dezelfde lijst staat in Instellingen, Indeling. Opslaan in
`AppSettings.blockOrder["overview"]`. Alleen Home heeft een volgorde; hero en Bibliotheek staan vast.

## Eigendom per bouwer (v3-bouw, historisch)

| Bouwer | Bezit |
|---|---|
| ENGINE | Core rekenmotor (zie hierboven) + tests |
| MONEY-A | `Pages/SavingsPages.swift`, `Pages/CashflowPages.swift` (inkomsten/uitgaven met dag en pot-bron, verdelen met overschrijfdag, bankpagina met dagoverzicht) |
| MONEY-B | `Pages/PotPages.swift` (rente-instellingen, potgeschiedenis met rente en pot-uitgaven, saldo op datum) |
| SHELL | `Router.swift`, `RootView.swift`, `Pages/DestinationView.swift`, `Pages/HomeView.swift`, `Pages/SavingsView.swift`, `Pages/ToolsView.swift`, `UI/*` (Components, Theme, Glass, Charts, Fields), `Debug/DebugLaunch.swift`, `scripts/ci-screenshots.sh`, animaties, tabbalk, blokvolgorde |
| GOALS | `Pages/GoalPages.swift` (behalve versnellers), `Pages/SavingsGoalPages.swift`, `Core/Goals.swift`, `Core/SavingsGoal.swift` |
| ACCEL | `Core/Accelerators.swift`, `Pages/AcceleratorPages.swift` |
| PURCHASE | `Core/Purchase.swift`, `Pages/PurchasePages.swift` |
| XLSX | `Core/Zip.swift`, `Core/XLSX.swift`, `Core/ImportMapping.swift`, `Core/Export.swift`, `UI/BackupUI.swift` |
| FIREBASE | `Cloud/*`, `Auth/*`, `Config/*`, `MyBuddyApp.swift`, `Pages/SettingsView.swift`, `firebase/*`, `Tests/AppTests/*` |

Altijd gedeeld en alleen door de integrator (hoofdsessie) aan te passen: `Models.swift`, `AppStore.swift`, `project.yml`, `README.md`, `.github/*`.
