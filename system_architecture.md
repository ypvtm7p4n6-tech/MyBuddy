# Architectuur (voor vervolgwerk)

## Lagen
- `App/Core/`: alleen Foundation, geen SwiftUI. Waardetypes en rekenregels. Wordt in de app direct meegecompileerd en in `CoreTests/` (SwiftPM, via symlink) getest. Nieuwe rekenlogica hoort hier, met een test.
- `App/UI/`: thema (`Theme`, `MeshBackground`), glas (`Glass.swift`), herbruikbare onderdelen (`Components`, `Fields`, `Charts`).
- `App/Pages/`: schermen. `*View` = tab, `*Page` = detailpagina, `*Sheet` = invulscherm.
- `AppStore` (`@MainActor @Observable`): bezit `FinanceData`, slaat op, haalt koersen op. **Elke wijziging via `store.mutate { $0.xyz }`**, nooit `data` direct aanpassen, anders wordt er niet opgeslagen.
- `Router`: tab, drie navigatiepaden, instellingenblad, en `focusMonth` + `periodMode` die de Savings-pagina's delen.

## Navigatie
Elk blok is een `LinkedBlock` (hele kaart) of een `GlassBlock` met `headerLink` (alleen de kop, als de kaart zelf losse tegels met eigen links bevat). Alle bestemmingen staan in `enum Destination`; `DestinationView` koppelt ze aan pagina's. Een nieuwe pagina = een case + een regel in `DestinationView`.

## Rekenmodel
- Bedragen zijn `Double` in euro's, afgerond met `.cents`.
- `YearMonth` is de eenheid van tijd. Een `MonthPlan` wordt bewaard voor maanden ≤ nu (`materialize`) en voor maanden die je bewerkt; verder wordt hij afgeleid (`synthesizedPlan`) uit terugkerende regels en standaardinleg. Daardoor veranderen oude maanden niet als je een standaard wijzigt.
- Pot-saldo = boekingen + maandverdelingen vanaf `startMonth`. Er is geen aparte "saldo"-opslag.
- Bankrekening en beleggingen werken met meetpunten (`BankSnapshot`, `ValueSnapshot`): laatste meetpunt + overschot/inleg van latere maanden. Na de huidige maand groeit een belegging met `netReturn` (rendement − kosten).
- Doelen: `goalInputs` → `analyze` (looptijd via maandelijkse simulatie, `Growth.monthsToReach`). Versnellers (`Accelerators.swift`) zijn kandidaten uit de eigen cijfers; elk is een `ScenarioChange` die opgeteld kan worden. Alleen kandidaten die iets opleveren worden getoond.
- Opslag: `FinanceStorage` schrijft één JSON-bestand atomisch. `FinanceData` decodeert met `decodeIfPresent`, zodat nieuwe velden oude bestanden niet breken. Een onleesbaar bestand wordt apart bewaard, nooit overschreven.

## Koersen
`QuoteService` (protocol) → `YahooQuoteService` (zoeken, koers, historie, wisselkoers naar EUR). `YahooParser` is los testbaar. Koers ophalen maakt via `recordPrice` een `ValueSnapshot` (één per dag).

## Opmaak
Vaste radii: kaart 30 → tegel 14 (= 30 − 16 inset) → chip 10. Glas via `glassCard`/`glassSurface`, met `Material` als terugval onder iOS/macOS 26. Kleuren staan in `Theme`; pot- en beleggingskleuren uit `Theme.palette`.

## Bekende open punten
- Nog nooit gecompileerd in deze omgeving (geen Swift-toolchain). Eerste build kan kleine compilerfouten geven.
- Geen iCloud-sync en geen meldingen. Wel: JSON-back-up exporteren en importeren (Instellingen, via fileExporter/fileImporter) en CSV-export van uitgaven.
- Yahoo Finance is onofficieel; houd `QuoteService` als enige koppelvlak.
