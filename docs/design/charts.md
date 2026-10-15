# Grafieken: diagnose, oorzaak bij Beleggingen en voorstel voor een gedeelde grafieklaag

Peildatum 15 oktober 2026, `HEAD` ca0c945 (bij het lezen was alleen `docs/design/` gewijzigd; het herstelwerk in `App/` loopt door, dus zoek op het patroon, niet op het regelnummer). Dit document verandert niets in `App/` of `CoreTests/`. Regels uit `hig-notes.md` staan als `CHT-n`, `ACC-n`, `COL-n`.

**Hoe is dit gemeten.** Elke reeks hieronder is de echte uitvoer van `App/Core` in een proefpakket (`App/Core` en vier Foundation-only UI-bestanden als symlink), met "nu" = 15 oktober 2026 12:00 (Europe/Amsterdam). De views zelf kunnen hier niet draaien: SwiftUI en Charts zijn er niet. Wat een view "tekent" is dus afgeleid uit de code (met regelnummer) toegepast op die echte reeks, niet van een scherm gelezen. Het netwerk is niet aangeroepen (koersen). Pad, commando's en volledige uitvoer: bijlage A en `charts-prototype.md`.

---

## 1. Kern

**Oorzaak bij Beleggingen: een combinatie, met één hoofdoorzaak in Core.**

1. **Core tekent alleen uit meetpunten.** `historicState` geeft `nil` zonder meetpunt (`Invest.swift:41`), `portfolioSeries` slaat die maanden over (`:168`). `Totaal ingelegd`, `Inleg per maand`, startmaand, ticker en aantal doen niets zolang er geen meetpunt is: waarde, ingelegd en reeks zijn dan 0 (gemeten: scenario B1, B1c, B3, B3b, B4a).
2. **De invoer maakt zelden een meetpunt.** Een handmatige belegging krijgt er een alleen als `Huidige waarde` > 0 is ingevuld (`PortfolioPages.swift:706`, het veld staat alleen bij nieuw en zonder ticker, `:493`). Een gevolgde belegging krijgt er een pas als het ophalen van de koers slaagt (`AppStore.swift:145-170`) en het aantal > 0 is (`Invest.swift:270`). Offline, onbekende ticker of een leeg aantal: nooit een punt.
3. **De view dekt dat af met een onjuiste tekst.** `PortfolioPages.swift:66-75` toont de grafiek alleen bij `series.count > 1`; anders "De grafiek groeit mee zodra er meer meetpunten zijn" (`:72`). Met minstens één meetpunt komen er altijd 12 verwachte punten bij, dus de tekst verschijnt alleen bij **nul** punten: "meer" klopt niet, en de reeks was uit de planning af te leiden. Home (`HomeView.swift:414`) en Savings (`SavingsView.swift:276`) controleren niets en tonen een lege ruimte van 110 en 90 pt naast "€ 0".
4. **Met één meetpunt is het beeld nog steeds "stuk"**: één stip plus 12 maanden stippellijn, geen geschiedenis, een keuzebalk 6 mnd / 1 jaar / 3 jaar die niets verandert (sample: alle drie 18 punten), en y-labels die drie keer hetzelfde zeggen (`€1,1k | €1,1k | €1,1k`).
5. **De Chart-code zelf**: bij lezing geen fout gevonden voor geldige gegevens; weergave kon niet worden getest.

**Voorstel in drie lagen.** (a) Core: een afgeleid beginpunt uit `investedTotal` en de inleg voor beleggingen zonder meetpunt (voorgesteld, in een kopie van Core getest: zie 3.5). (b) Een Foundation-only modellaag `App/UI/ChartModels.swift` die per grafiek reeks, as, lege staat en VoiceOver-tekst bepaalt (gecompileerd en gedraaid, B3 in `charts-prototype.md`). (c) Vier SwiftUI-componenten (`TrendChart`, `StackedBarChart`, `DonutChart`, `ProgressMeter`) die alle grafiekplekken uit de inventaris vervangen.

**Status per grafiek** (functioneel gedrag met ingevulde gegevens; toegankelijkheid ontbreekt bij bijna alle en staat in 5):

| ID | Grafiek | Status |
|---|---|---|
| G1 | Beleggingen, Groei | werkt niet zonder meetpunt, werkt deels met |
| G2 | Beleggingen, Verdeling (donut) | werkt deels |
| G3 | Belegging, Koers laatste jaar | werkt deels |
| G4 | Belegging, Waarde | werkt niet zonder meetpunt, werkt deels met |
| G5 | Home en Savings, Beleggingen (kleine lijn) | werkt niet zonder meetpunt, werkt deels met |
| G6 | Per maand (gestapelde staven, 3 plekken) | werkt deels |
| G7 | Overzicht, Vermogen | werkt deels |
| G8 | Bank, Verwacht verloop | werkt deels |
| G9 | Saldo per dag (2 plekken) | werkt |
| G10 | Toekomstschatting, Verloop | werkt deels |
| G11 | Buffer, Verloop | werkt |
| G12 | Spaardoel, Verloop | werkt deels |
| G13 | Versnellers, doelcurve | werkt deels |
| G14 | Voortgangsbalk en -ring (14 plekken) | werkt deels |
| G15 | Binnen en eruit (segmentbalk) | werkt deels |
| G16 | Saldoverloop per spaarpot | bestaat niet |
| G17 | Aankoopcheck | geen datagrafiek (stapindicator, in orde) |

---

## 2. Alle grafieken en hun gegevensbron

Gezocht op `Chart`, `TimeLineChart`, `FlowChart`, `AllocationDonut`, `DayBalanceChart`, `SparkLine`, `ProgressRing`, `ProgressBar`, `SegmentBar`, `Canvas`, `Path(`, `Shape`, `GeometryReader` in `App/Pages` en `App/UI`. `SparkLine`, `Canvas` en eigen `Path` komen niet voor; `GlassSurface<S: InsettableShape>` (`Glass.swift:4`) is geen grafiek. De zes bestanden die Swift Charts importeren: `Charts.swift`, `CashflowPages.swift`, `BufferPages.swift`, `ProjectionPage.swift`, `SavingsGoalPages.swift`, `AcceleratorPages.swift`.

| ID | View | Bestand:regel | Pagina | Gegevensfunctie |
|---|---|---|---|---|
| G1 | `TimeLineChart` | `PortfolioPages.swift:67` | Beleggingen, blok Groei | `portfolioSeries(from:count:current:only:today:)` `Invest.swift:152`, via `holdingState` `:62-85` en `historicState` `:38-59` |
| G2 | `AllocationDonut` (`Charts.swift:146`) | `PortfolioPages.swift:80` | Beleggingen, blok Verdeling | `valueByKind(current:today:)` `Invest.swift:182` |
| G3 | `TimeLineChart` | `PortfolioPages.swift:234` | Belegging (detail), Koers laatste jaar | `AppStore.priceHistory` `AppStore.swift:181`, `historyInEUR` `Quotes.swift:462` (Yahoo), `:658` (Stooq), `:923` (CoinGecko) |
| G4 | `TimeLineChart` | `PortfolioPages.swift:238` | Belegging (detail), Waarde | `portfolioSeries(only: [id])` |
| G5 | `TimeLineChart(showsAxes: false)` | `HomeView.swift:414`, `SavingsView.swift:276` | Home (`InvestBlock`), Savings (`PortfolioBlock`) | `portfolioSeries(from: now-6, count: 13)` |
| G6 | `FlowChart` (`Charts.swift:99`) | `SavingsPages.swift:69`, `HomeView.swift:237`, `SavingsView.swift:70` | Overzicht (Per maand), Home (`OverviewBlock`), Savings (`PeriodBlock`) | `summaries(from:count:current:)` `Plan.swift:451`, `summary(of:)` `:436` |
| G7 | `TimeLineChart` | `SavingsPages.swift:75` | Overzicht, blok Vermogen | `netWorthSeries` `Overview.swift:32` |
| G8 | `TimeLineChart` | `SavingsPages.swift:1929` (`BankForecastBlock` `:1920`) | Bankrekening, Verwacht verloop | `bankSeries` `Bank.swift:227` |
| G9 | `DayBalanceChart` | def `CashflowPages.swift:243`; gebruik `:517` (`BankDayBlock`) en `:942` (Dag voor dag) | Bankrekening (Per dag), Dag voor dag | `LedgerBook.days(from:to:)` `CashflowDisplay.swift:110`, `monthLedger` `Ledger.swift:197`, `DayChartItem` `CashflowDisplay.swift:443` |
| G10 | `Chart` (eigen) | `ProjectionPage.swift:128` | Toekomstschatting, Verloop | `Growth.curve` `Growth.swift:110`, `Growth.projection` |
| G11 | `BufferChart` | def `BufferPages.swift:481`; gebruik `:391` | Buffercalculator, Verloop | `BufferCalc.series` `Buffer.swift:276` |
| G12 | `SavingsGoalChart` | def `SavingsGoalPages.swift:655`; gebruik `:390` | Spaardoel, Verloop | `SavingsGoalPlan.series` `SavingsGoal.swift:225` |
| G13 | `GoalCurveChart` | def `AcceleratorPages.swift:585`; gebruik `:104` | Versnellers | `goalCurves` `Accelerators.swift:123` |
| G14 | `ProgressBar` (`Components.swift:211`), `ProgressRing` (`:194`) | `PotPages.swift:128,308`; `HomeView.swift:304,325`; `GoalPages.swift:98,312,366`; `SavingsGoalPages.swift:229,406`; `BufferPages.swift:44,279`; `SavingsPages.swift:1412`; `SavingsView.swift:137`; `ProjectionPage.swift:163` | Spaarpotten, Home, Doelen, Spaardoel, Buffer, Verdelen, Savings, Toekomstschatting | `potProgress` `Pots.swift:246`, `analyze().progress` `Goals.swift:183`, `BufferResult.progress`, `SavingsGoalPlan.progress`, `MonthFigures` |
| G15 | `SegmentBar` (`Components.swift:531`) | `SavingsPages.swift:1714` | Bankrekening, Binnen en eruit | `expenseOverview(in:)` |
| G16 | bestaat niet | `PotPages.swift`: `historyBlock` `:533` is een lijst, `dateBalanceBlock` `:506` een datumkiezer | Spaarpot (detail) | `potBalance(_:at:)` `Pots.swift:209`, `potFlows` `Interest.swift:286` |
| G17 | `PurchaseStepBar` (`PurchasePages.swift:109`) | `PurchasePages.swift:242` | Aankoopcheck | geen gegevens; de aankoopcheck heeft geen grafiek |

---

## 3. Beleggingen: oorzaak, reproductie, herstel

### 3.1 De keten, stap voor stap

| Stap | Wat gebeurt er | Waar |
|---|---|---|
| 1 | De gebruiker vult in: naam, soort, ticker, aantal stuks, huidige waarde (alleen nieuw en zonder ticker), totaal ingelegd, inleg per maand, rendement, kosten. Een startdatum bestaat niet: `Holding(name: "", startMonth: store.now)`. | `PortfolioPages.swift:409-515`, `:493`, `:682` |
| 2 | `save()` maakt alleen een meetpunt als `!tracked && manualValue > 0`. `addHolding` schrijft alleen een meetpunt als `initialValue` er is. | `PortfolioPages.swift:706-707`, `Invest.swift:210-215` |
| 3 | Een gevolgde belegging krijgt een meetpunt pas na `refreshPrices(force: true)` en alleen als `units > 0`. Een ticker zonder aantal wordt `units = nil`: de koers komt wel binnen (`lastPrice`), het meetpunt niet (gemeten B1c). | `PortfolioPages.swift:711-713`, `AppStore.swift:145-170`, `Invest.swift:265-273`, `PortfolioPages.swift:687` |
| 4 | Zonder meetpunt: `historicState` geeft `nil`, `holdingState` geeft `nil`, `portfolioSeries` slaat elke maand over. `portfolioValue`, `portfolioInvested`, `valueByKind`, `netWorthSeries` en `goalInputs(.portfolio)` lezen dezelfde functie: alles 0. | `Invest.swift:41`, `:168`, `:118`, `:173`, `Overview.swift:48`, `Goals.swift:183` |
| 5 | De pagina: `series.count > 1` anders de tekst "groeit mee"; Home en Savings tekenen een lege `Chart`. | `PortfolioPages.swift:66-75`, `HomeView.swift:414`, `SavingsView.swift:276` |

`investedTotal`, `monthlyContribution` en `startMonth` worden in `portfolioSeries` pas gebruikt als er al een meetpunt is: `investedTotal` alleen als beginwaarde van een nieuw meetpunt (`Invest.swift:213`, `:271`), de inleg alleen voor maanden ná het meetpunt (`:45-57`). Bij een pot werkt het anders: `potBalance` rekent uit de boekingen en de planning (`Pots.swift:189-210`), zonder meetpunt. Bij de bank is een onbekend beginsaldo echt onbekend (G8). Bij een belegging is het beginbedrag wel bekend zodra de gebruiker "Totaal ingelegd" invult, maar Core gebruikt het niet.

### 3.2 Reproductie (proefuitvoer, scenario's uit de opdracht)

"Punten" = wat `portfolioSeries(from: now-12, count: 25, ...)` voor de pagina teruggeeft (werkelijk + verwacht). Tickwaarden en y-labels in dit document: `Fmt.compact` op mijn benadering van de automatische ticks van Swift Charts (1, 2 of 5 maal een tientallige macht); de gelijke labels volgen uit `Fmt.compact` zelf, de precieze tickkeuze van Charts kon ik niet zien.

| Scenario | Ingevuld | Kop "Waarde / Ingelegd" | Punten | Wat de pagina toont |
|---|---|---|---|---|
| a sample | 3 beleggingen, 6 meetpunten elk | € 8.966 / € 8.200 | 18 (6+12), mei '26 t/m okt '27 | lijn, vlak, gestippelde verwachting; y `€8k, €10k, €12k` |
| b1 ticker, aantal 10, ingelegd 1000, nog geen koers | | € 0 / € 0 | **0** | tekst "groeit mee"; Home, Savings: lege ruimte; detail: geen blok Waarde |
| b1b zelfde, eerste koers (105) binnen | | € 1.050 / € 1.000 | 13 (1+12) | stip + stippellijn; y `€1,1k, €1,1k, €1,1k` |
| b1c ticker zonder aantal, koers komt binnen | | € 0 / € 0 | **0** (`lastPrice` 105, 0 meetpunten) | als b1 |
| b2 handmatige waarde 5000 | | € 5.000 / € 5.000 | 13 (1+12) | stip + stippellijn |
| b3 alleen inleg 200 | | € 0 / € 0 | **0** | als b1 |
| b3b ingelegd 3000 + inleg 200 | | € 0 / **€ 0** (3000 getypt) | **0** | als b1 |
| b4a startmaand 6 mnd terug (alleen via import of sync mogelijk) | ingelegd 2000, inleg 200 | € 0 / € 0 | **0** | als b1 |
| b5 deze maand, waarde 1000, inleg 100 | | € 1.000 | 13 (1+12) | stip + stippellijn |
| c twee beleggingen, start -8 en -2 mnd | | € 2.600 / € 2.300 | 21 (9+12) | totaal springt van 1.500 (jul) naar 2.100 (aug) doordat belegging B zijn eerste meetpunt krijgt (geen fout, wel een stap) |
| d tracked met maandelijkse historie (`importHistory`, 13 meetpunten) | | € 1.100 / € 1.000 | 25 (13+12) | lijn; `invested` is bij alle meetpunten de huidige 1000 |
| e alleen een spaarpot | | n.v.t. | 0 | `EmptyHint` "Nog geen beleggingen" (`PortfolioPages.swift:30`): in orde |
| f lege data | | n.v.t. | 0 | idem, in orde |
| g1 meetpunt met waarde 0 (via Waarde bijwerken; bij toevoegen wordt 0 genegeerd, dan als b3) | | € 0 | 13 | vlakke lijn op 0; labels `-€0, €0, €0` |
| g2 waarde 1000, inleg -300 | | € 1.000 | 13 | verwachte waarde daalt tot **-2.637**: een belegging kan niet onder 0 |
| g3 meetpunt -250 (alleen via sync/import) | | € -250 | 13 | y `-€260, -€255, -€250`; donut: 0 soorten |
| h 40 maanden meetpunten, 3 jaar terug | | | 49 (37+12) | in orde; 2,2 ms voor één belegging, 11 ms voor zes beleggingen met elk 40 meetpunten |

Volledige uitvoer: `…/chart-probe/output.txt`, onderdeel `=== A.` t/m `=== H.`.

### 3.3 Waarom de pagina "groeit mee" zegt

De tekst (`PortfolioPages.swift:72`) is geschreven voor "nog maar één punt". Dat geval komt niet voor: zodra er één meetpunt is, voegt `portfolioSeries` de verwachte maanden t/m nu+12 toe (`count: monthsBack + 13`, `:20`). `series.count` is dus 0 of ≥ 13. De tekst staat daarmee alleen bij 0 punten, waar "meer meetpunten" niet klopt (er is er geen) en waar de reeks uit wat de gebruiker invulde af te leiden is (3.5). Core leidt dat nu niet af omdat `historicState` alleen meetpunten kent.

### 3.4 Wat er verder aan deze grafiek ontbreekt

| # | Bevinding | Bewijs |
|---|---|---|
| B-1 | De keuzebalk 6 mnd / 1 jaar / 3 jaar (`PortfolioPages.swift:59-64`) verandert het beeld niet zolang de eerste gegevens minder dan 6 maanden oud zijn: de reeks begint bij het eerste meetpunt, niet bij `now - monthsBack`. De balk staat ook bij 0 punten. | sample: 6, 12 en 36 mnd geven alle drie 18 punten, mei '26 t/m okt '27 |
| B-2 | De verwachting (12 maanden, vast) drukt het verleden plat: in het sample beslaat de werkelijke lijn (7.350 tot 8.966) het onderste derde van een as tot 12.573. | `output.txt` A |
| B-3 | y-labels uit `Fmt.compact` (`Formatting.swift:41-57`) hebben onder 1.000 hele euro's en daarboven één decimaal in duizendtallen. Bij een smalle reeks zijn naburige labels gelijk: `€1,1k, €1,1k, €1,1k` (b1b), `€4, €4, €4` voor een koers van 4,00 tot 4,33, `€1, €1` voor een koers van 0,50. 13 regels met dubbele labels in de proefuitvoer. | `output.txt`, "DUBBELE LABELS" |
| B-4 | x-as: de code stuurt de x-as nergens aan voor `TimeLineChart` en `FlowChart` (`chartAxes` doet alleen `chartYAxis`, `Charts.swift:8-25`): labels en tussenruimte zijn die van Swift Charts, in de taal van het toestel. Alleen `DayBalanceChart` (`CashflowPages.swift:305`) en `BufferChart` (`BufferPages.swift:513`) sturen hem aan. Met `showsAxes: false` (Home, Savings) zijn beide assen weg. Hoe de standaard-x-as er bij 18 of 49 maanden uitziet kon ik niet vaststellen. | code |
| B-5 | Aandachtspunt (leeswerk): het vlak onder de lijn (`AreaMark`, `Charts.swift:66`) suggereert een staafhoogte vanaf de onderrand, terwijl de y-as niet op 0 begint (`includesZero: false`, `:89`): een stijging van 1.050 naar 1.110 oogt als een verdubbeling. Bij een vlakke reeks (g1: min = max) is het domein van `.automatic(includesZero: false)` niet door de code vastgelegd; hoe Charts dat opvangt kon ik niet vaststellen. | code |
| B-6 | Eén werkelijk punt wordt een `PointMark` (`:84-87`), één verwacht punt zonder werkelijk punt wordt niet getekend (`future.count > 1`, `:75`). Beide gevallen vangen de pagina's niet af. | code |
| B-7 | Verdeling (G2): alleen bij meer dan één soort (`PortfolioPages.swift:78`); bij één soort verdwijnt het blok zonder uitleg. Kleur per plek in de rangorde (`Charts.swift:158-159`), terwijl `HoldingRow` en `HoldingTile` per soort kleuren (`PortfolioPages.swift:129`, `HomeView.swift:479`): dezelfde soort heeft twee kleuren. De legenda (`:160`) toont alleen de naam (`Grondstoffen / goud`), geen bedrag of percentage. | code |
| B-8 | Koers (G3): `Fmt.compact` rondt af op hele euro's (B-3). `history` wordt bij een nieuwe ticker niet leeggemaakt: faalt het ophalen, dan blijft de koers van de vorige ticker staan (`PortfolioPages.swift:363-374`). De koers-grafiek en de waarde-grafiek sluiten elkaar uit (`:232` `else if` `:236`): met internet zie je de koers, zonder internet de waarde. Alle punten krijgen de koers van vandaag voor valuta-omrekening (`Quotes.swift:467-468`). | code |
| B-9 | Detail "Waarde" (G4) verdwijnt zonder uitleg bij minder dan 2 punten (`PortfolioPages.swift:236`). | b1, b3 |
| B-10 | Een inleg na het meetpunt in dezelfde maand valt weg: meetpunt 15 okt, inleg 200 op de 25e: eind oktober 1.000, op 26 okt nog steeds 1.000, pas november 1.200. Dit is de bedoelde regel van `HoldingDayTests` (de inleg van de meetpuntmaand zit "in het meetpunt"), maar bij een nieuwe belegging met inleg ontbreekt de eerste inleg. | `output.txt` S2 |
| B-11 | Bij een gevolgde belegging negeert aantal x koers de inleg: 26 nov (inleg 100 van de 25e binnen) 1.100, 28 nov na koersvernieuwing met hetzelfde aantal 1.000. De waarde springt terug tenzij de gebruiker het aantal bijwerkt; de app doet dat nergens (`updateHolding`, `Invest.swift:226-229`, alleen bij handmatige wijziging). | `output.txt` S3 |

B-10 en B-11 zijn ontwerpvragen voor Core, geen oorzaak van "grafiek werkt niet". Ik raad aan ze apart te beslissen (3.5, punt C6).

### 3.5 Herstel in Core

| # | Functie | Gewenst gedrag |
|---|---|---|
| C1 | `historicState` (`Invest.swift:38`) en `holdingState` (`:70`) | Zonder meetpunt en met `investedTotal > 0` of een inleg ≠ 0 (vast bedrag of percentage > 0): een afgeleid beginpunt op `startMonth.firstDay` met `value = invested = max(0, investedTotal - som van de inleg van startMonth+1 t/m current)`. Voor de lopende maand telt een inleg alleen als zijn overschrijfdag al geweest is (dezelfde `DayMath.isPlanned`-regel als `:48-52`), zodat de waarde van nu gelijk is aan wat de gebruiker bij "Totaal ingelegd" typte. Geen schrijven naar `snapshots` (anders staat er een verzonnen punt in Meetpunten en de back-up); zodra er een echt meetpunt is, neemt dat het over. Zonder bedrag en zonder inleg: `nil`, dus lege staat. `historicState` krijgt daarvoor `current` als parameter (beide aanroepers hebben hem). |
| C2 | `HoldingState`, `PortfolioPoint` | `isEstimated: Bool`. Voor een punt: waar bij alle meegetelde beleggingen het beginpunt afgeleid is. De pagina toont "Geschat" bij het bedrag en verbergt "Rendement" (waarde = ingelegd, dus 0, onzin) zolang `isEstimated`. |
| C3 | `portfolioSeries` | Signatuur ongewijzigd. Nieuw: `portfolioDataStart(current:today:) -> YearMonth?` (eerste maand met een meetpunt of afgeleid beginpunt), zodat het venster (6 mnd, 1 jaar, 3 jaar, alles) bij de eerste gegevens begint en de keuzebalk alleen opties toont die verschillen (`PortfolioWindow.options`, B3 in `charts-prototype.md`). |
| C4 | `holdingState` na `current` (`:77-83`) | `value = max(0, value * (1 + rm) + a)`: een verwachte waarde onder 0 bestaat niet (g2: -2.637). |
| C5 | `valueByKind` (`:173`, `:182`) | Geen eigen wijziging: leest C1 via `holdingValueNow`. De filter `> 0` blijft; de pagina toont het totaal van de donut. |
| C6 | Open vraag voor de Core-eigenaar | B-10 (inleg van de meetpuntmaand) en B-11 (aantal bijhouden bij gevolgde beleggingen, bijvoorbeeld `unitsAsOf` en aantal += inleg / koers). Beide veranderen bestaande tests (`HoldingDayTests`, `InvestTests`); niet meenemen in dit herstel. |
| C7 | `netWorthSeries` (`Overview.swift:32`) | `NetWorthPoint.bankKnown: Bool` (nu telt een onbekend banksaldo als 0, `:50`). Het weglaten van maanden vóór `startMonth` hoort in de modelbouwer (6.3), niet in Core. |
| C8 | Nieuw: `potSeries(_:from:count:current:) -> [PotPoint]` in `Pots.swift` | Saldo per maand-einde en verwacht, op dezelfde manier als `netWorthSeries` het per pot doet (`potFlows(pot, throughMonth:)`, `flows.cents(before: m.endExclusive)`, `Overview.swift:35-40`). Voor G16. |

**Proef van C1 in een kopie van Core** (`…/chart-fixcheck`, `Invest.swift` gepatcht, de hele `CoreTests` ertegenaan): zie 3.7.

### 3.6 Herstel in de view

- **Groei-blok** (`PortfolioPages.swift:58-76`): `TrendChart(PortfolioTrend.model(...))`. Drie toestanden uit één model: lege staat (`model.empty`), afgeleid (`model.note` "Geschat uit je inleg: je hebt nog geen koers of waarde ingevuld. Vul een waarde in of ververs de koers voor het echte verloop."), normaal. De keuzebalk alleen als `PortfolioWindow.options(availableMonths:)` iets te kiezen geeft; de tekst "groeit mee" vervalt.
- **Home en Savings** (`HomeView.swift:414`, `SavingsView.swift:276`): dezelfde model, `size: .compact`, zonder as maar met begin- en eindwaarde als tekst; bij een lege staat één regel "Vul een waarde in om je groei te zien".
- **Detail** (`PortfolioPages.swift:232-240`): één blok met segment "Koers | Waarde" (koers alleen als de belegging gevolgd wordt); `history = []` aan het begin van `loadHistory`; laadstaat met `ProgressView`; foutstaat met "Opnieuw proberen".
- **Invoer** (`HoldingEditSheet`): "Huidige waarde" ook bij een belegging met ticker (leeg = koers x aantal zodra binnen) en bij wijzigen; een ticker zonder aantal krijgt onder het veld "Vul ook het aantal stuks in, anders kan de app de waarde niet uitrekenen".
- **Verdeling**: `DonutChart(DonutModel.holdingKinds(...))` ook bij één soort; kleur per soort; lijst met bedrag en percentage eronder.
- **Kop** (`PortfolioPages.swift:35-47`): "Geschat" onder het bedrag bij `isEstimated`; "Rendement" toont "–".

### 3.7 Falende testbeschrijving en proef

`…/chart-tests/Tests/MyBuddyCoreTests/PortfolioSeriesDerivedTests.swift` (volledige tekst in `charts-prototype.md`) draait nu tegen `HEAD`: 5 tests, **3 falen** (`testHoldingWithOnlyInvestedTotalHasAValueAndASeries`, `testHoldingWithOnlyAMonthlyContributionHasASeries`, `testTickerWithUnitsButNoPriceStillGivesASeriesFromInvestedTotal`), 2 slagen als vangnet (`testMeasuredHoldingIsUnchangedByTheFallback`, `testHoldingWithoutAnyDataStaysEmpty`). Fout: `("[]") is not equal to ("[3000.0, 3200.0, 3400.0, 3600.0]")` en `("0.0") is not equal to ("3000.0")`.

Bewijs dat het herstel werkt (prototype, `Prototype.swift`): met een afgeleid beginpunt geven b1, b3, b3b en b4a een reeks (13, 13, 13 en 19 punten), kop "Waarde" = het getypte bedrag (b1 € 1.000, b3b € 3.000, b4a € 2.000), een belegging zonder bedrag en zonder inleg blijft leeg (lege staat), en het sample is ongewijzigd (18 punten, € 8.966).

**Proef van C1 in een kopie van Core** (`…/chart-fixcheck`: `Invest.swift` gepatcht, diff in `charts-prototype.md`; de hele `CoreTests`-map ertegenaan):

- De 5 tests uit deze paragraaf slagen alle vijf (`…/chart-tests-fixed`).
- De volledige suite (1.492 tests, 10 overgeslagen, 130 s): **1 test faalt**, met 3 asserties: `HoldingDayTests.testHoldingWithoutMeasurementHasNoStateNow` (`HoldingDayTests.swift:217-225`). Die test legt precies het oude gedrag vast: een belegging met 100 inleg per maand sinds augustus en zonder meetpunt heeft geen waarde (`XCTAssertNil`, waarde 0, lege `valueByKind`). Met C1 is de waarde 100 (de inleg van september; die van oktober is op 14 oktober nog gepland). Die test moet mee veranderen; dat is de bedoelde gedragswijziging. Alle andere tests blijven groen, onder meer `InvestTests`, de overige `HoldingDayTests`, `OverviewTests`, `GoalTests` en `AcceleratorPercentTests`.
- Niet gemeten: de suite tegen ongewijzigde `HEAD` in dezelfde run (de ene falende test is aan de patch toe te schrijven).

---

## 4. Scenario-matrix

ok = zoals het hoort, deels = werkt maar met een gebrek (zie kolom Opmerking), fout = grafiek leeg of verkeerd, n.v.t. = niet van toepassing, n.g.m. = niet gemeten. Scenario's: a sample, b nieuwe gebruiker, c twee startmaanden, d koershistorie, e alleen potten, f leeg, g nul of negatief, h lang (36 maanden).

| Grafiek | a | b | c | d | e | f | g | h | Opmerking |
|---|---|---|---|---|---|---|---|---|---|
| G1 Groei | ok | fout (0 punten bij b1, b1c, b3, b3b; stip bij b2, b5) | ok (stap) | ok | ok (EmptyHint) | ok (EmptyHint) | deels | ok | B-1 t/m B-6 |
| G2 Verdeling | ok | deels (1 soort: blok weg) | ok | deels | weg | weg | deels (0 slices) | n.v.t. | B-7 |
| G3 Koers | n.g.m. | n.g.m. | n.v.t. | deels (labels) | n.v.t. | n.v.t. | n.v.t. | n.v.t. | B-8; reeks synthetisch |
| G4 Waarde | ok | fout (blok weg) | ok | deels (niet naast koers) | n.v.t. | n.v.t. | deels | ok | B-9 |
| G5 Home/Savings | ok | fout (lege ruimte) | ok | ok | ok | ok | deels | n.v.t. | geen controle |
| G6 Per maand | deels (jaar: 4 lege staven) | deels (Home: 4 van 6 leeg) | n.v.t. | n.v.t. | ok | fout (lege assen) | deels | n.v.t. (max 12) | overschrijding onzichtbaar |
| G7 Vermogen | deels (jaar: 4 maanden 0, sprong) | deels (bank onbekend = 0) | n.v.t. | n.v.t. | ok | deels (vlak 0) | n.g.m. | ok (5 ms) | `Overview.swift:50` |
| G8 Bank verloop | ok | fout zonder banksaldo (blok weg), ok met | n.v.t. | n.v.t. | n.v.t. | fout (blok weg) | n.g.m. | ok (3 ms) | `SavingsPages.swift:1926` |
| G9 Saldo per dag | ok | ok met saldo; zonder: tekst (Bank) of niets (Dag voor dag) | n.v.t. | n.v.t. | n.v.t. | idem | ok (negatief, vlak) | n.v.t. | maandvenster met 1 dag: foute tekst |
| G10 Toekomstschatting | ok (eind = uitkomst) | n.v.t. | n.v.t. | n.v.t. | n.v.t. | deels (3 vlakke nullijnen) | ok (-5%) | deels (100 jaar) | scenario's onleesbaar bij 100 jaar |
| G11 Buffer | ok | n.v.t. | n.v.t. | n.v.t. | n.v.t. | ok (tekst) | ok (sparen 0: vlak) | ok (97 punten) | |
| G12 Spaardoel | ok | n.v.t. | n.v.t. | n.v.t. | n.v.t. | n.v.t. | fout (al bereikt en doel 0: geen lijn) | ok (163 punten) | `SavingsGoalPages.swift:680` |
| G13 Versnellers | deels (1 van 2 doelen mist laatste punt) | n.v.t. | n.v.t. | n.v.t. | n.v.t. | n.g.m. | n.v.t. | n.v.t. | `AcceleratorPages.swift:598-607` |
| G14 Voortgang | ok | n.v.t. | n.v.t. | n.v.t. | deels (pot zonder doel: ring vol) | n.v.t. | ok (NaN, inf, negatief begrensd) | n.v.t. | `HomeView.swift:325`, `PotPages.swift:308` |

Rekentijd per `body`-aanroep (debugbouw op Linux, ter indicatie): `netWorthSeries` 12 mnd 3,3 ms; `summaries` 12 mnd 0,6 ms; `bankSeries` 16 mnd 4,5 ms; `portfolioSeries` 49 mnd 2,4 ms; twee maanden dagboek 5,2 ms. Geen reden voor caching.

---

## 5. Per grafiek: wat is mis, oorzaak, herstel, lege staat, toegankelijkheid

Alle VoiceOver-teksten hieronder zijn de echte uitvoer van de modelbouwers uit het prototype (sample, 15 oktober 2026), tenzij `[tekst]` erbij staat. Overal geldt: geen enkele grafiek heeft nu een `AXChartDescriptor` (`grep accessibilityChartDescriptor App/` = 0, CHT-2); alleen `DayBalanceChart` (`CashflowPages.swift:315`) en `BufferChart` (`BufferPages.swift:526`) hebben een vast label zonder waarden; geen enkele grafiek leest `accessibilityReduceMotion` (ACC-4), terwijl allemaal `.animation(Theme.motion, ...)` hebben.

### G1, G4, G5 Beleggingen: Groei, Waarde, Home en Savings
- **Mis:** zie 3.1 t/m 3.4 en de matrix.
- **Oorzaak:** zie 3.1.
- **Herstel:** C1 t/m C5 en 3.6; component `TrendChart`.
- **Lege staat** (uit `PortfolioTrend.empty`): geen beleggingen: "Nog geen beleggingen. Voeg een ETF, aandeel, crypto of spaarrekening toe." [Belegging toevoegen]. Ticker zonder aantal: "Vul het aantal stuks in. Met een ticker en een aantal rekent de app de waarde van VWCE uit." [Aantal invullen]. Gevolgd zonder koers en zonder bedrag: "Wachten op de koers. Zodra de koers binnen is, zie je hier je waarde. Controleer anders je internet en de ticker." [Koers vernieuwen]. Overig: "Nog geen waarde. Vul de huidige waarde of het ingelegde bedrag van een belegging in, dan tekent de app je groei." [Waarde invullen]. Home, Savings: één regel.
- **VoiceOver** (sample): "Waarde van je beleggingen. Nu 8.966 euro. Sinds mei 2026 plus 1.616 euro. Verwacht in oktober 2027: 12.573 euro." Afgeleid (b1): "Waarde van je beleggingen. Nu 1.000 euro. Verwacht in oktober 2027: 1.058 euro." met onderschrift "Geschat uit je inleg …".

### G2 Verdeling
- **Mis:** B-7.
- **Herstel:** `DonutChart` met `DonutModel.holdingKinds`: ook bij één soort (volle ring, 100%), kleur per `HoldingKind` (`colorIndex`), totaal in het midden, lijst met naam, bedrag en percentage eronder (CHT-12), `.chartLegend(.hidden)`.
- **Lege staat:** "Nog geen verdeling. Zodra een belegging een waarde heeft, zie je hier hoe je geld over soorten is verdeeld."
- **VoiceOver:** "Verdeling van je beleggingen over 3 soorten: Indexfonds / ETF 55 procent (4.888 euro), Obligaties 27 procent (2.423 euro), Crypto 18 procent (1.656 euro)."

### G3 Koers laatste jaar
- **Mis:** B-3 en B-8. Koers 100,02 tot 105,36: labels `€102, €104`; 4,00 tot 4,33: `€4, €4, €4, €4`.
- **Herstel:** `PriceTrend` (nog te schrijven, zelfde vorm als `PortfolioTrend`) met `ChartAxis.yLabels` (bij tickafstand < 1 euro met centen: `€4,00, €4,10, €4,20, €4,30`, bij 0,50 tot 0,51 drie decimalen); `history = []` bij start van `loadHistory`; segment Koers | Waarde; laad- en foutstaat in het blok.
- **Lege staat:** laden: `ProgressView` met "Koershistorie ophalen". Fout: "Koershistorie niet beschikbaar. {fout} Controleer je internet en de ticker." [Opnieuw proberen].
- **VoiceOver** [tekst]: "Koers van {ticker} het afgelopen jaar. Nu {koers} euro. Laagste {min} euro, hoogste {max} euro."

### G6 Per maand (gestapelde staven)
- **Mis:** maanden vóór de startmaand zijn lege staven (jaarmodus sample: jan t/m apr; Home bij een nieuwe gebruiker: 4 van 6); bij een tekort (uitgaven 3.700, inkomen 3.000) is de stapel 4.100 hoog zonder dat de grafiek aangeeft waar het inkomen ophoudt, en `Over` wordt op 0 afgekapt (`Charts.swift:124`); een negatieve verdeling (-150) geeft een staaf onder nul en een stapel van 3.150 boven inkomen 3.000; bij lege data zes groepen nulstaven zonder uitleg; verwachte maanden verschillen alleen door `opacity(0.55)` (`:134`), de soorten alleen door kleur (flowExpenses/flowSaved lopen bij deuteranopie in elkaar over, COL-7); legenda alleen op de Overzichtspagina, op Home een losse `FlowLegend` (`HomeView.swift:211`).
- **Herstel:** `StackedBarModel.months(_:startMonth:)` laat maanden vóór `startMonth` weg, tekent per maand een inkomenslijn (`RuleMark`) zodat een tekort zichtbaar boven de lijn uitsteekt, laat `Over` op `max(0, remaining)`, en bouwt per maand een VoiceOver-regel. Verwacht = gestippelde rand plus "(verwacht)" in de samenvatting. Tik op een staaf (`chartXSelection`) toont de bedragen per soort als tekst (tweede kanaal naast kleur).
- **Lege staat:** "Nog geen maanden om te tonen. Vul je salaris of een uitgave in, dan zie je per maand waar je geld heen gaat." [Salaris instellen]
- **VoiceOver** (descriptor per maand): "december 2026 (verwacht): inkomen 3.474 euro, uitgaven 1.650 euro, gespaard 342 euro, belegd 250 euro, over 1.232 euro." Bij een tekort: "…, tekort 1.100 euro."

### G7 Vermogen
- **Mis:** jaarmodus sample: jan t/m apr als `werkelijk` met waarde 0, dan een sprong naar 15.964 (mei); bank onbekend telt als 0 (`Overview.swift:50`), dus bij een nieuwe gebruiker zonder banksaldo is het vermogen te laag zonder aanwijzing in de lijn (alleen een tekst eronder, `SavingsPages.swift:83`); lege data: een vlakke nullijn met een degeneratieve as; alle-verwacht (focus 2027): alleen stippellijn, zonder vlak, in orde.
- **Herstel:** `NetWorthTrend.model` laat maanden vóór `startMonth` weg; C7 (`bankKnown`) voor een noot "Zonder banksaldo"; lege staat bij 0 totaal.
- **Lege staat:** "Nog geen vermogen. Vul een banksaldo, een spaarpot of een belegging in." [Banksaldo invullen]
- **VoiceOver** [tekst uit sample]: "Vermogen aan het eind van de maand. Oktober 2026: 25.300 euro (bank 10.830, spaarpotten 5.504, beleggingen 8.966). Sinds mei 2026 plus 9.336 euro."

### G8 Bank, Verwacht verloop
- **Mis:** zonder banksaldo verdwijnt het blok geheel, zonder uitleg (`SavingsPages.swift:1926`); met één saldo een stip plus 12 maanden stippellijn (in orde).
- **Herstel:** `BankTrend.model`, lege staat in plaats van verdwijnen.
- **Lege staat:** "Banksaldo onbekend. Vul je saldo van vandaag in, dan zie je hier het verwachte verloop." [Saldo invullen]
- **VoiceOver** [tekst uit sample]: "Verwacht banksaldo per maand-einde. Oktober 2026: 10.830 euro. Verwacht in oktober 2027: 25.609 euro."

### G9 Saldo per dag
- **Mis:** niets in de reeks (sample: 30 dagen, 7.873 tot 10.830; vlakke lijn krijgt een as van ±50 euro, `CashflowPages.swift:261`; negatief en vlak ok). Randgevallen: maandvenster met saldo op alleen de laatste dag: 1 dag, `days.count > 1` is onwaar (`:516`) en de tekst zegt "nog niet bekend" terwijl 1 dag bekend is; op "Dag voor dag" verdwijnt het blok zonder tekst (`:940`); labels `€1k | €1k` bij een vlak saldo van 1.000; label zonder waarden (`:315`).
- **Herstel:** zelfde `TrendChart` met `xAxis: .days` en markeringen "Nul" en "Laagste"; bij 1 dag een stip met tekst; lege staat in plaats van verdwijnen.
- **Lege staat:** bestaand ("Voor deze periode is je saldo nog niet bekend.") plus [Saldo invullen]; ook op Dag voor dag.
- **VoiceOver** [tekst]: "Banksaldo per dag, 15 oktober tot 13 november. Laagste saldo 7.873 euro op {dag}, saldo op het eind 10.830 euro." plus descriptor met elke dag.

### G10 Toekomstschatting
- **Mis:** de reeks klopt (laatste punt = uitkomst, verschil ≤ 0,01; 10 jaar: 49.691, 56.383, 64.053). Gebreken: bij lege gegevens (`Gebruik mijn beleggingen` geeft 0, 0, 5%) drie vlakke nullijnen op elkaar met een as van 0 tot 0 en geen uitleg; het streefbedrag staat niet in de grafiek; de drie lijnen verschillen alleen door kleur (`ProjectionPage.swift:132-134`, `flowExpenses`, `accent`, `flowInvested`); 100 jaar: 3,98 mln, 19,1 mln en 98,3 mln op één as, de voorzichtige lijn is vlak; horizon 0 eindigt op 0,1 maand (verschil 0,25 tot 0,56 euro, onschadelijk).
- **Herstel:** `ProjectionTrend.model` met `xAxis: .elapsed(unit)`; scenario's als lijnstijl + symbool (vol, gestreept, gestippeld); markering "Streefbedrag" als `target > 0`; lege staat bij start en inleg 0.
- **Lege staat:** "Vul een startbedrag of een inleg in, dan zie je drie mogelijke verlopen."
- **VoiceOver** [tekst]: "Toekomstschatting over 10 jaar. Voorzichtig 49.691 euro, verwacht 56.383 euro, optimistisch 64.053 euro. Daarvan ingelegd 38.966 euro."

### G11 Buffer
- **Mis:** niets in de reeks (sample: doel 4.887, heeft 3.450, 150 per maand, doel in 10 maanden, 17 punten; al vol 13 punten; sparen 0: 25 punten vlak; vanaf 0: 97 punten). Lege staat bestaat (`BufferPages.swift:393`). Het moment waarop het doel gehaald wordt staat niet in de grafiek; label zonder waarden.
- **Herstel:** `BufferTrend.model` met markering "Doel bereikt in augustus 2027" (alleen tekst en `RuleMark`); verder ongewijzigd.
- **VoiceOver** [tekst]: "Buffer: nu 3.450 euro van een doel van 4.887 euro. Met 150 euro per maand is het doel bereikt in augustus 2027."

### G12 Spaardoel
- **Mis:** al bereikt (start 6.000, doel 5.000) en doel 0: `chosenOutcome.months` is 0, dus 1 waarde en `guard values.count > 1` (`SavingsGoalPages.swift:680`) laat de lijn "Mijn inleg" weg; blijft alleen de doelstreep plus, omdat inleg ≠ benodigd, een vlakke lijn "Benodigde inleg" van 25 punten (gemeten). Lijnen alleen door kleur (accent en flowInvested, `:706-707`). Verder in orde (voorbeeld 25 punten, 600 maanden 163 punten).
- **Herstel:** `SavingsGoalTrend.model`: bij `plan.isReached` een lege staat in plaats van een grafiek; anders minimaal `plan.months` maanden; "Benodigde inleg" als gestreepte lijn met symbool; markering "Doel 5.000"; `ChartAxis.downsample` houdt het laatste punt.
- **Lege staat:** "Je hebt dit bedrag al. Je saldo is hoger dan je doel."
- **VoiceOver** [tekst]: "Spaardoel 5.000 euro in 24 maanden. Met 205 euro per maand haal je het in oktober 2028."

### G13 Versnellers (doelcurve)
- **Mis:** de uitdunning (`AcceleratorPages.swift:598-607`, `i += step`) tekent het laatste punt alleen als `(count-1) % step == 0`: "4 dagen werken" 406 waarden, stap 4, laatste getekende index 404 van 405 (gemeten): de lijn eindigt een maand te vroeg, net waar het doel gehaald wordt. "Met pensioen" 501 waarden, stap 5, index 500: in orde. `Nu` is `Color.gray` op de olijf-mesh (laag contrast, COL-3). Zonder gegevens (start 0, inleg 0) is "nooit" het antwoord en toont de pagina geen grafiek (in orde).
- **Herstel:** `ChartAxis.downsample` (houdt eerste en laatste punt, gemeten: 406, 501, 100, 101 en 50 punten behouden alle het laatste); lijnstijl vol en gestreept in plaats van grijs en accent.
- **Lege staat:** "Kies een versneller om te zien hoeveel sneller je je doel haalt."
- **VoiceOver** [tekst]: "Met pensioen: nu in 488 maanden, met je keuze in 414 maanden."

### G14 Voortgangsbalk en -ring
- **Mis:** een pot zonder doel krijgt een **volle ring** (`progress ?? 1`, `HomeView.swift:325`, `PotPages.swift:308`); geen enkele `ProgressBar`, `ProgressRing` of `SegmentBar` heeft `accessibilityValue` of -label (`Components.swift:194-226`, `:531-560`); `ProgressBar` tekent minstens `height` breed (`:223`), dus 0,5% oogt als 8 pt; "te veel verdeeld" is alleen kleur (`SavingsPages.swift:1412`, `SavingsView.swift:137`); de uitdrukking `min(1, max(0, x))` uit de views begrenst NaN (0), oneindig (1) en negatief (0) al (uitdrukking zelf gemeten).
- **Herstel:** `ProgressMeter(value: Double?, ...)`: `nil` tekent niets en de pagina toont "Geen doel ingesteld"; `accessibilityElement(children: .ignore)`, label en waarde; breedte exact `breedte x waarde`; boven 100% een vinkje.
- **VoiceOver** [tekst]: "Voortgang spaarpot Vakantie: 43 procent, 1.032 euro van 2.400 euro."

### G15 Binnen en eruit (segmentbalk)
- **Mis:** bij een tekort (`leftAfterTransfers < 0`) is de balk gewoon vol, het tekort staat alleen in een tekstregel; elk segment is minstens 4 pt (`Components.swift:549`), vijf segmenten kunnen samen breder worden dan de balk; alleen kleur; geen label.
- **Herstel:** `ProgressMeter` in segmentvorm: segmenten in een vaste volgorde met de bedragen als tekst eronder (die staan al in `FlowRow`), `accessibilityValue` "Vast 925 euro, variabel 540 euro, …".

### G16 Saldoverloop per spaarpot (bestaat niet)
- **Mis:** een spaarpot heeft een lijst (`historyBlock`) en een datumkiezer (`dateBalanceBlock`) maar geen verloop, terwijl Core het per maand kan uitrekenen (C8).
- **Herstel:** `potSeries` (C8), `TrendChart(PotTrend.model(...))` onder het blok Saldo in `PotDetailPage`, met de doelstreep (`goalAmount`) en "Doel bereikt in {maand}" (`potGoalMonth`, `Pots.swift:258`).
- **Lege staat:** "Nog geen verloop. Zodra er een boeking of inleg is, zie je hier het saldo per maand."
- **VoiceOver** [tekst]: "Saldo van {pot} per maand-einde. Nu {saldo} euro. Doel {doel} euro."

### G17 Aankoopcheck
Geen datagrafiek. `PurchaseStepBar` (`PurchasePages.swift:109-132`) is een stapindicator met eigen label ("Stap 2 van 3: Uren"); in orde, geen werk.

---

## 6. Gedeelde grafieklaag

### 6.1 Opbouw

Twee lagen, zodat de logica te testen is zonder SwiftUI (zoals `CashflowDisplay.swift`, dat als symlink in `CoreTests` staat):

1. `App/UI/ChartModels.swift`, Foundation-only. Typen: `ChartPoint` (met soort `actual`, `estimated`, `projected`), `ChartLine` (met `segments`, lijnstijl, rol), `ChartMarker` (doel, nul, drempel), `ChartEmpty` (symbool, titel, uitleg, actie), `TrendModel`, `DonutModel`, `StackedBarModel`. Hulpfuncties in `ChartAxis` (`domain`, `ticks`, `yLabels`, `monthLabel`, `monthStride`, `downsample`) en `ChartText` (bedragen voor VoiceOver). Per pagina een modelbouwer: `PortfolioTrend`, `PriceTrend`, `NetWorthTrend`, `BankTrend`, `DayBalanceTrend`, `ProjectionTrend`, `BufferTrend`, `SavingsGoalTrend`, `GoalCurveTrend`, `PotTrend`; `DonutModel.holdingKinds`; `StackedBarModel.months`.
2. `App/UI/Charts.swift`: `TrendChart`, `StackedBarChart`, `DonutChart`, `ProgressMeter`, `ChartEmptyView` (SwiftUI). Ze lezen alleen het model.

**Gecompileerd en gedraaid** (B3 in `charts-prototype.md`): alle typen en functies in 1 behalve `PriceTrend`, `NetWorthTrend`, `BankTrend`, `DayBalanceTrend`, `ProjectionTrend`, `BufferTrend`, `SavingsGoalTrend`, `GoalCurveTrend` en `PotTrend`; die zijn dunne bouwers rond bestaande Core-functies met dezelfde vorm als `PortfolioTrend`. **Alleen syntaxis gecontroleerd** (tree-sitter, 0 foutknopen): de SwiftUI-schets (B4 in `charts-prototype.md`); die is niet gecompileerd.

### 6.2 Componenten en API

```swift
// Lijn en vlak, met afgeleid en verwacht deel, markeringen en een lege staat.
TrendChart(model: TrendModel, size: .compact | .regular | .tall = .regular,
           showsAxes: Bool = true, nonNegative: Bool = false,
           onAction: (ChartEmpty.Action) -> Void = { _ in })

// Gestapelde staven per maand, met een inkomenslijn.
StackedBarChart(model: StackedBarModel, height: CGFloat = 180, showsAxes: Bool = true)

// Verdeling: ring met totaal in het midden en een lijst met bedrag en percentage eronder.
DonutChart(model: DonutModel, height: CGFloat = 160)

// Voortgang: balk of ring. value == nil tekent niets.
ProgressMeter(value: Double?, tint: Color, style: .bar(height:) | .ring(lineWidth:),
              label: String, valueText: String)
```

Een pagina schrijft bijvoorbeeld:

```swift
let model = PortfolioTrend.model(d, window: window, current: now, today: today, derived: derived)
TrendChart(model: model, size: .tall, nonNegative: true) { action in handle(action) }
```

Wat een pagina dus niet meer zelf doet: reeksen afdunnen, as en labels kiezen, een lege staat verzinnen, een VoiceOver-tekst schrijven.

### 6.3 Pagina naar component

| Pagina | Nu | Straks |
|---|---|---|
| Beleggingen, Groei | `TimeLineChart` | `TrendChart(PortfolioTrend.model(...), size: .tall)`, keuzebalk uit `PortfolioWindow.options` |
| Home, Savings, Beleggingen | `TimeLineChart(showsAxes: false)` | `TrendChart(..., size: .compact, showsAxes: false)` plus begin- en eindwaarde als tekst |
| Belegging, Koers | `TimeLineChart` | `TrendChart(PriceTrend.model(history:))` |
| Belegging, Waarde | `TimeLineChart` | `TrendChart(PortfolioTrend.model(only: id))`, naast Koers in één blok met segment |
| Beleggingen, Verdeling | `AllocationDonut` | `DonutChart(DonutModel.holdingKinds(...))` |
| Overzicht, Home, Savings | `FlowChart` | `StackedBarChart(StackedBarModel.months(..., startMonth:))` |
| Overzicht, Vermogen | `TimeLineChart` | `TrendChart(NetWorthTrend.model(...))` (maanden vóór `startMonth` weg) |
| Bank, Verwacht verloop | `TimeLineChart` | `TrendChart(BankTrend.model(...))` met lege staat |
| Saldo per dag (2x) | `DayBalanceChart` | `TrendChart(DayBalanceTrend.model(days:selected:))`, `xAxis: .days` |
| Toekomstschatting | `Chart` | `TrendChart(ProjectionTrend.model(...))`, `xAxis: .elapsed(unit)` |
| Buffer | `BufferChart` | `TrendChart(BufferTrend.model(...))` |
| Spaardoel | `SavingsGoalChart` | `TrendChart(SavingsGoalTrend.model(plan:now:))` |
| Versnellers | `GoalCurveChart` | `TrendChart(GoalCurveTrend.model(curves:start:))` |
| Spaarpot (nieuw) | niets | `TrendChart(PotTrend.model(...))` |
| Voortgang (14 plekken), Binnen en eruit | `ProgressBar`, `ProgressRing`, `SegmentBar` | `ProgressMeter` |

### 6.4 Conventies (voor alle componenten)

| Onderwerp | Regel |
|---|---|
| x-as | Maanden: label om de `ChartAxis.monthStride(span:)` maanden (1 tot 7 maanden: elke maand, 8 tot 14: om de 2, 15 tot 26: om de 3, 27 tot 50: om de 6, daarboven jaarlijks), korte Nederlandse maand uit `Fmt.shortMonth`, bij januari met jaartal (`jan '27`). Dagen: `DayText.short`. Toekomstschatting: verstreken tijd in de gekozen eenheid. De component stuurt de x-as altijd zelf aan (`.chartXAxis`, B-4). |
| y-as | Eigen tickwaarden (`ChartAxis.ticks`) en labels (`ChartAxis.yLabels`): zo kort mogelijk (`€8k`), maar nooit twee gelijke naburige labels; onder 10.000 liever `€1.050` dan `€1,1k`; bij tickafstand < 1 euro centen (`€4,10`), bij nog kleinere afstand drie decimalen. Getest op acht gevallen (b1b, koers 4,00 tot 4,33, koers 0,50 tot 0,51, vlak 0, vlak 1.000, negatief, normaal, met NaN en oneindig): overal unieke labels en `lo < hi` (`probe proto`). |
| Domein | `ChartAxis.domain`: altijd `lo < hi`, alleen eindige waarden, 8% ruimte, bij een vlakke reeks 5% of minstens 1 euro; `includeZero` voor staven en voortgang; `nonNegative` voor beleggingen en potten. Het domein staat dus altijd vast en hangt niet af van hoe `.automatic(includesZero: false)` een vlakke reeks opvangt. Het vlak onder de lijn blijft een stijlkeuze voor het werkelijke deel (B-5 is een aandachtspunt). |
| Soorten punten | werkelijk: volle lijn en vlak; afgeleid: volle dunne lijn met korte stippen, geen vlak, met `note` erbij; verwacht: gestreepte lijn. Eén werkelijk punt: stip (`PointMark` met symbool). Segmenten sluiten aan op het laatste punt van het vorige. |
| Niet alleen kleur (CHT-5, COL-4) | Meer dan één lijn: verschil in lijnstijl (vol, gestreept, gestippeld) en bij `accessibilityDifferentiateWithoutColor` een symbool per reeks en een tekstlabel bij het laatste punt. Staven: vaste volgorde, de bedragen als tekst na een tik, inkomenslijn als `RuleMark`. Donut: lijst met naam, bedrag, percentage; `angularInset` blijft 1,5. Markeringen (doel, nul) hebben een tekstlabel. |
| Lege staat (CHT-7, EMP-4) | `model.empty != nil` toont `ContentUnavailableView` met symbool, titel, uitleg en hooguit één knop, op dezelfde hoogte als de grafiek (geen sprong in de pagina). Compact (Home): één regel. Nul punten is nooit een lege `Chart`; één punt is een stip met uitleg; pas vanaf twee punten een lijn. |
| Toegankelijkheid (CHT-2) | `.accessibilityChartDescriptor(...)` met titel, `model.summary` en elk punt (x als categorie, y numeriek met `ChartText.euro`); API gecontroleerd tegen Apple's documentatie: `AXChartDescriptorRepresentable` (`makeChartDescriptor`, `updateChartDescriptor`), `AXChartDescriptor(title:summary:xAxis:yAxis:additionalAxes:series:)`, `AXCategoricalDataAxisDescriptor(title:categoryOrder:)`, `AXNumericDataAxisDescriptor(title:range:gridlinePositions:valueDescriptionProvider:)`, `AXDataSeriesDescriptor(name:isContinuous:dataPoints:)`, `AXDataPoint(x:y:additionalValues:label:)`, allemaal iOS 15 en macOS 12. Kleine lijnen: een samenvattend label volstaat. Zichtbaar onderschrift met de kernwaarde (CHT-6). |
| Beweging (ACC-4, MOT-5) | `@Environment(\.accessibilityReduceMotion)`: dan `.animation(nil, ...)`. Een grafiek die met animatie verandert, verandert ook zijn samenvatting. |
| Hoogtes (CHT-11) | `.compact` 96 (Home, Savings), `.regular` 180, `.tall` 240 (hoofdgrafiek van de pagina). Nu: 90, 110, 120, 130, 150, 160, 170, 190, 200, 210. |
| Kleuren (CHT-4) | Waarde en saldo: `accent`; verwacht: dezelfde kleur gestreept; doel: grijze gestreepte `RuleMark`; tekort en negatief: `negative`; uitgaven, gespaard, belegd, over: `flow*`; beleggingssoorten: vaste kleur per `HoldingKind`. Geen eigen kleuren per grafiek (nu `Theme.warning`, `Color.gray`, `flowExpenses` verspreid). De grafiek tekent geen eigen achtergrond (geen glas op glas, GLS-2). |
| Interactie | Optioneel `chartXSelection` (iOS 17, macOS 14): `RuleMark` met datum en waarde; alles wat erin staat staat ook zonder interactie als tekst. |

### 6.5 Tests en volgorde

Tests in `CoreTests` (nieuwe bestanden, `ChartModels.swift` als symlink): `PortfolioSeriesDerivedTests` (de 5 uit 3.7), `ChartAxisTests` (domein `lo < hi` voor vlak, nul, NaN; `yLabels` uniek voor de acht gevallen uit 6.4; `ticks` binnen het domein; `monthStride`; `downsample` houdt eerste en laatste punt), `PortfolioTrendTests` (vier lege staten, `estimated`, `PortfolioWindow.options` voor 0, 1, 2, 7, 8 en 14 maanden), `DonutModelTests` (kleur per soort, aandelen tellen op tot 1, één soort), `StackedBarModelTests` (maanden vóór start weg, tekort boven de inkomenslijn, lege staat), `ChartSegmentTests` (aansluitpunt, één punt is een stip).

Volgorde: (1) C1 t/m C5 met de tests uit 3.7; (2) `ChartModels.swift` en zijn tests; (3) `TrendChart` en G1, G4, G5 (lost de melding van de gebruiker op); (4) `DonutChart` (G2); (5) `StackedBarChart`, G7, G8 (de lege staten); (6) G9 t/m G13; (7) C8 en G16; (8) `ProgressMeter` (G14, G15) en het verwijderen van `TimeLineChart`, `FlowChart`, `AllocationDonut`, `BufferChart`, `SavingsGoalChart`, `GoalCurveChart`, `DayBalanceChart`.

---

## 7. Wat ik niet heb kunnen vaststellen

- Hoe Swift Charts de x-as, een vlakke reeks (`includesZero: false`) en de gradient-`AreaMark` daadwerkelijk tekent: geen SwiftUI hier. B-4 en B-5 zijn leeswerk, geen waarneming. De opdracht noemt dat er "alleen y-as labels" staan; uit de code volgt dat de x-as niet is uitgeschakeld voor `TimeLineChart` en `FlowChart` (alleen bij `showsAxes: false`), maar ook niet is aangestuurd. Op een toestel te controleren.
- De koersen zelf (netwerk, Yahoo, Stooq, CoinGecko) en dus G3 met echte data. De y-labels van G3 zijn gemeten met synthetische reeksen.
- Of de eigenaar van Core B-10 en B-11 als fout of als bedoeld beschouwt.
- De SwiftUI-schets (`Charts.sketch.swift`) is alleen op syntaxis gecontroleerd; de AX-namen zijn gecontroleerd tegen Apple's documentatie-JSON, de `Chart`-modifiers niet gecompileerd.

---

## Bijlage A. Proefpakketten en commando's

Alle paden onder `/tmp/claude-0/-home-user-MyBuddy/9beb118c-8e88-5a84-a4b5-426733aaf64d/scratchpad`.

| Pakket | Doel |
|---|---|
| `chart-probe` | reeksen per grafiek en scenario; symlink naar `App/Core` en `App/UI/{CashflowDisplay,PotDisplay,SavingsDisplay,MoneyFigures}.swift`; prototype `ChartModels.swift`, `Prototype.swift`, `ModelProbe.swift` |
| `chart-tests`, `chart-tests-fixed` | `PortfolioSeriesDerivedTests` tegen `HEAD` (3 falen) en tegen de gepatchte kopie (5 slagen) |
| `chart-fixcheck` | kopie van `App/Core` met C1 in `Invest.swift`, de hele `CoreTests` ertegenaan |
| `chart-sketch` | `Charts.sketch.swift`, SwiftUI-schets (syntaxcontrole) |

```
export PATH=/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin:$PATH
cd <scratchpad>/chart-probe && swift build --scratch-path /tmp/sb-chartprobe
TZ=Europe/Amsterdam /tmp/sb-chartprobe/debug/probe all      # of: hold | extra | other | time | edge | proto | model
cd <scratchpad>/chart-tests && swift test --scratch-path /tmp/sb-charttests --filter PortfolioSeriesDerivedTests
```

Volledige uitvoer: `chart-probe/output.txt` (716 regels). Broncode van het prototype, de falende tests en de schets: `docs/design/charts-prototype.md`.
