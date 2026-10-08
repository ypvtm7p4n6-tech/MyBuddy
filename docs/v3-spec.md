# MyBuddy v3: ontwerp en afspraken

Dit document is het gedeelde contract voor alle bouwers. Wie een bestand "bezit", mag het aanpassen.
Alle andere bestanden alleen lezen. Moet je iets in een bestand van een ander veranderen: zet het
onder **WIRING** in je eindrapport.

## Algemene afspraken

- Alle tekst in de UI is Nederlands, "je"-vorm, kort. Code-commentaar Nederlands, zoals in de rest van de app.
- Swift 5-modus, iOS 18 / macOS 15, SwiftUI, `@Observable`. Geen nieuwe pakketten of dependencies.
- `App/Core/*` is Foundation-only en compileert ook op Linux (tests). Netwerk: `#if canImport(FoundationNetworking) import FoundationNetworking #endif`.
- **Bedragen worden altijd afgerond getoond**: `Fmt.euro(x)` (= hele euro's). Alleen eenheidsprijzen waar centen
  ertoe doen (uurloon, koers, rente-uitkomst onder 10 euro) gebruiken `Fmt.euroExact(x)`. Percentages: `Fmt.percent(x)` (max 1 decimaal).
  Rekenwaarden in Core blijven op centen (`.cents`); afronden is een weergaveregel. Invulvelden mogen wel decimalen tonen.
- Elke nieuwe pagina: `PageScaffold(title:)`, blokken met `GlassBlock`/`LinkedBlock`, knoppen met `ChipButton`/`ChipLink`/`ChipGrid`
  (allemaal even hoog: `Theme.buttonHeight`), tegels met `.tile()`/`StatTile`. Kijk naar bestaande pagina's voor de stijl.
- Animaties: gebruik `.smooth`/`.snappy` (kort, 0.25-0.35s). Bedragen krijgen `.contentTransition(.numericText())` en
  een `.animation(.smooth, value:)` op de waarde; lijsten/blokken `withAnimation(.smooth)` bij toevoegen/verwijderen.
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
`AxisContentBuilder` (gebruik `.chartAxes(shown:)`), schaduwende namen in initializers, `@Bindable` voor `@Observable` bindings,
`private` properties die buiten het type gebruikt worden, ontbrekende `import Charts`.

## Nieuwe modelvelden (staan al in `Models.swift`, niet hernoemen)

- `SalarySettings.payDay` (standaard 25): dag waarop salaris en extra inkomsten (zonder eigen dag) binnenkomen.
- `MoneyLine.day: Int?` (1...31) en `MoneyLine.potShares: [PotShare]`; helpers `fromPots`, `fromBank`, `[MoneyLine].totalFromPots`.
  Inkomsten: dag = `day ?? payDay`. Uitgaven: dag = `day ?? 1`. Bij een uitgave gaat `fromBank` van de bank en elk `PotShare` uit zijn pot.
- `MonthPlan.transferDay: Int?`: overschrijfdag voor de hele maandverdeling. Volgorde: `plan.transferDay ?? pot/holding.transferDay ?? payDay`.
- `Pot.interestRate` (breuk per jaar), `interestPayout` (`InterestPayout`), `interestPayoutDay`, `interestPayoutMonth`, `Pot.transferDay`, `Holding.transferDay`.
- `PotEntryKind.interest` ("Rente") en `.expense` ("Uitgave betaald").
- `AppSettings.blockOrder: [String: [String]]`: eigen blokvolgorde per pagina ("home", "savings", "tools").
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

Tabs: **Home**, **Savings**, **Tools** (`AppTab.tools`, pad `router.toolsPath`).

- **Home**: Nog te verdelen (header), blokken Overzicht, Spaarpotten, Beleggingen (alle drie even groot, zoals nu).
- **Savings**: periodekeuze + blokken: Overzicht (`PeriodBlock`), Inkomen (`IncomeBlock`), Bankrekening (`BankBlock`),
  Verdelen (`DistributeBlock`), Spaarpotten (`PotsSummaryBlock`), Buffer (`BufferBlock`),
  **Beleggingen** (de oude "Portefeuille", `PortfolioBlock`, titel "Beleggingen", opent `.portfolio`),
  **Doelen** (`GoalsHubBlock`, één blok dat spaardoelen en levensdoelen samenvoegt, opent `.goals`).
- **Tools**: Versnellers (`AcceleratorsBlock`), Toekomstschatting (`ProjectionBlock`), Aankoopcheck (`PurchaseBlock`, opent `.purchase`).
- Destinations: bestaande + `.purchase` (`PurchasePage`) en `.cashflow` (`CashflowPage`, dag voor dag). `.savingsGoal` blijft bereikbaar vanuit de doelenpagina.
- Blok-id's voor de volgorde (`AppSettings.blockOrder`): home: `overview`, `pots`, `invest`; savings: `period`, `income`, `bank`, `distribute`, `pots`, `buffer`, `portfolio`, `goals`; tools: `accelerators`, `projection`, `purchase`.

### Blokken verplaatsen
Niet zichtbaar als knop. Lang indrukken op een blok (contextmenu): "Volgorde aanpassen…" opent een sheet met een lijst
(`.onMove`, bewerkmodus altijd aan) + "Klaar" en "Standaardvolgorde". Opslaan in `AppSettings.blockOrder`. Home houdt de
drie blokken even groot.

## Eigendom per bouwer

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
