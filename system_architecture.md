# Architectuur (voor vervolgwerk)

## Lagen
- `App/Core/`: alleen Foundation, geen SwiftUI. Waardetypes en rekenregels. Wordt in de app direct meegecompileerd en in `CoreTests/` (SwiftPM, via symlink) getest. Nieuwe rekenlogica hoort hier, met een test.
- `App/UI/`: thema (`Theme`, `MeshBackground`), glas (`Glass.swift`), herbruikbare onderdelen (`Components`, `Fields`, `Charts`).
- `App/Pages/`: schermen. `*View` = tab, `*Page` = detailpagina, `*Sheet` = invulscherm.
- `AppStore` (`@MainActor @Observable`): bezit `FinanceData`, slaat op, haalt koersen op. **Elke wijziging via `store.mutate { $0.xyz }`**, nooit `data` direct aanpassen, anders wordt er niet opgeslagen.
- `Router`: tab (Home, Savings, Tools), drie navigatiepaden, instellingenblad, en `focusMonth` + `periodMode` die de Savings-pagina's delen. Blokken openen vanaf Home zetten die eerst terug op de huidige maand (`showCurrentMonth`).
- `App/Cloud` + `App/Core/Firebase*.swift`/`CloudSync*.swift`: inloggen en synchroniseren via de Firebase REST-API (geen SDK). `AppStore.onDataChanged` meldt wijzigingen, `applyRemote` neemt wijzigingen van andere apparaten over zonder echo.

## Navigatie
Elk blok is een `LinkedBlock` (hele kaart) of een `GlassBlock` met `headerLink` (alleen de kop, als de kaart zelf losse tegels met eigen links bevat). Alle bestemmingen staan in `enum Destination`; `DestinationView` koppelt ze aan pagina's. Een nieuwe pagina = een case + een regel in `DestinationView`.

## Rekenmodel
- Bedragen zijn `Double` in euro's, afgerond met `.cents`.
- `YearMonth` is de eenheid van tijd. Een `MonthPlan` wordt bewaard voor maanden ≤ nu (`materialize`) en voor maanden die je bewerkt; verder wordt hij afgeleid (`synthesizedPlan`) uit terugkerende regels en standaardinleg. Daardoor veranderen oude maanden niet als je een standaard wijzigt.
- Alles rekent **per dag** (`DayEvents.swift`): salaris/inkomen (salarisdag of eigen dag), uitgaven (eigen dag; een deel kan uit potten komen: `MoneyLine.potShares`), verdeling over potten/beleggingen op de overschrijfdag, handmatige bankboekingen en rente. Pot-saldo `potBalance(_:asOf:)` = boekingen + inleg/uitgaven/rente tot en met die dag; `potBalanceNow` is het saldo van nu. Er is geen aparte "saldo"-opslag. `remaining(in:)` = inkomen − uitgaven van de bank − verdeeld.
- Rente (`Interest.swift`): uitbetalingen worden als `PotEntry(kind: .interest)` met een deterministisch id opgeslagen (`applyDueInterest`, idempotent); toekomstige uitbetalingen zijn verwacht en tellen mee in prognoses.
- Overboekingen tussen bank en pot, of pot en pot, delen een `pairID`: verwijderen haalt beide kanten weg.
- Bankrekening en beleggingen werken met meetpunten (`BankSnapshot`, `ValueSnapshot`): laatste meetpunt + boekingen daarna (planboekingen op de dag van het meetpunt gelden als al verwerkt). Na de huidige maand groeit een belegging met `netReturn` (rendement − kosten).
- Doelen: `goalInputs` → `analyze` (looptijd via maandelijkse simulatie, `Growth.monthsToReach`). Versnellers (`Accelerators.swift`) zijn kandidaten uit de eigen cijfers; elk is een `ScenarioChange` die opgeteld kan worden. Toepassen (`apply`) past pot-inleg, uitgaven, beleggingen of het doel echt aan en bewaart alleen de oude waarden van wat veranderde (`AppliedAccelerator.before`), zodat `restoreAccelerator` het kan terugdraaien.
- Opslag: `FinanceStorage` schrijft één JSON-bestand atomisch. `FinanceData` decodeert met `decodeIfPresent`, zodat nieuwe velden oude bestanden niet breken. Een onleesbaar bestand wordt apart bewaard, nooit overschreven.

## Koersen
`QuoteService` (protocol) → `YahooQuoteService` (zoeken, koers, historie, wisselkoers naar EUR). `YahooParser` is los testbaar. Koers ophalen maakt via `recordPrice` een `ValueSnapshot` (één per dag).

## Opmaak
Vaste radii: kaart 30 → tegel 14 (= 30 − 16 inset) → chip 10. Glas via `glassCard`/`glassSurface`, met `Material` als terugval onder iOS/macOS 26. Kleuren staan in `Theme`; pot- en beleggingskleuren uit `Theme.palette`.

## Bekende open punten
- Het SwiftUI-deel kan alleen op macOS gecompileerd worden (CI); `App/Core` compileert en test ook op Linux.
- Geen meldingen. Synchronisatie loopt via Firebase (zie `firebase/README.md`), niet via iCloud (dat vraagt een betaald ontwikkelaarsaccount). Instellingen van de buffer-calculator, het spaardoel-concept en het uurloon voor de aankoopcheck staan per account in UserDefaults en gaan dus niet mee met back-up of sync.
- Yahoo Finance is onofficieel; houd `QuoteService` als enige koppelvlak.
