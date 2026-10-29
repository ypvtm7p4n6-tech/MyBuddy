# MyBuddy: verdelen met een extra bedrag, extra overschrijfdata, de bankrekening als bestemming, doelen met meer potten, opnemen met bestemming en loon per maand (bouwplan 2)

Peildatum 29 oktober 2026. Basis: `HEAD` c0130b2 (golf 1 van `docs/work/plan.md`, de startdatum, is klaar en vastgelegd: 1957 tests groen, 10 overgeslagen). Dit plan hoort bij `docs/work/plan.md`: het gebruikt de bouwstenen van de startdatum (`counts(day:in:)`, `countedBankEntries`, `countedPotEntries`, `forEstimates`, `firstCountedDay(in:)`, de poort `docs/work/start-check.sh`) en voegt zich in de nog te bouwen golven van dat plan (golf 2, werkuren-Core, en golf 3A en 3B): par. 5 zet beide op één rij. Er is niets in `App/`, `CoreTests/` of `Tests/` aangepast; alleen dit plan en proefbestanden in `/tmp/arch-probe2/`.

De wens van de gebruiker (29 okt. 2026), in zes werkstukken:

| # | Wens | Kort |
|---|---|---|
| D1 | Naast een vast percentage ook een bedrag invullen dat er extra bij komt in dezelfde pot. | Percentage plus extra bedrag, standaard en per maand. |
| D2 | Meerdere data als overschrijfdag naast de standaarddag (op basis van je uitbetaaldag); een overschrijving op een andere dag gaat pas op die dag echt over. | Delen van de inleg op een eigen dag, standaard en per maand. |
| D3 | In Verdelen ook standaard naar je bankrekening kunnen overschrijven, zoals naar spaarpotten. | De bankrekening als rij in de verdeling (toewijzing zonder beweging). |
| D4 | Bij spaardoelen meerdere spaarpotten kunnen gebruiken. | Een doel uit meer potten. |
| D5 | Bij geld opnemen uit een pot aangeven waar het heen gaat (andere pot, bankrekening), en dat het er echt komt. | Opnemen en storten met bestemming en herkomst. |
| D6 | Het uurloon of salaris per maand kunnen aanpassen ("vanaf november uurloon Y in plaats van X"). | Loon per maand: een lijst met wijzigingen vanaf een maand. |

## Bewijs

**Wat is geprobeerd (29 okt., proefkopie van de stand van golf 1 in `/tmp/arch-probe2/ref3/`; referentiecode, tests, `core-edits-vs-golf1.diff` en prototypes van de poorten in `/tmp/arch-probe2/ref-verdelen/`; de bouwer neemt over of schrijft opnieuw).**
- Basislijn en samenvoeging: de stand van golf 1 (HEAD c0130b2) met alle Core- en tekstwijzigingen van dit plan: `swift test` **2053 tests, 10 overgeslagen, 0 fouten** (1957 bestaande, inclusief de byte-vergelijking van het oude opslagformaat `StartDateLegacyOutput` en op de bewuste tekstwijzigingen van 6.2 na ongewijzigd, plus 94 blijvende proeftests en 2 meetinstrumenten). `docs/work/start-check.sh` PASS op de samengevoegde stand. Typecontrole `/tmp/ctl-arch2/run-all.sh` (iOS en macOS, debug en release, plus de bestanden van `Tests/AppTests`): 0 fouten in alle zes varianten, 0 gebruiken van API's nieuwer dan iOS 18 of macOS 15.
- D1+D2+D3+D5: `ledgerScenario` is aan het EIND uitgebreid met een zesde reeks (zaad + 41_000: percentage met extra bedrag, extra overschrijfdata, bankdeel, opnemen of storten met bestemming) en een zevende (zaad + 47_000: loon per maand): in de eerste 200 datasets hebben 87 een percentage met extra bedrag, 91 extra overschrijfdata (67 ook per maand), 95 een bankdeel en 62 opnemen of storten met bestemming. Een onafhankelijke berekening van de stukken (gewone lussen, zonder `TransferMath`) legt zich naast elke overschrijving: dagen en bedragen kloppen in 384 pot-maanden met gesplitste overschrijvingen en 806 maanden met een extra bedrag. `LedgerConsistencyTests` slaagt op 200 en op 1200 zaadwaarden: het dagboek sluit (bank, potten, overzicht) op elke dag, ook met een startdatum midden in de maand (`StartDayPropertyTests`).
- D3, de keuze: `testTheBankShareMovesNoMoneyOnAnyDay` zet datasets met een bankdeel (428 maanden) naast dezelfde gegevens zonder bankdeel: banksaldo, potsaldo en gebeurtenissen van elke dag en het vermogen zijn gelijk, `remaining` is gelijk en `unassigned == remaining − toBank`; `testRemainingToTheBankReachesExactlyZero` (meer dan 300 maanden): "Rest naar bankrekening" brengt "nog te verdelen" op precies 0 zonder iets anders te veranderen. De Aankoopcheck, de Noodbuffer en de versnellers rekenen met `unassigned` en geven zonder bankdeel dezelfde getallen als voorheen.
- D4: een doel met twee potten rekent als een doel met eigen waarden met de som van de saldi en van de maandinleg (gelijke maanden tot het doel en gelijke voortgang); een doel met één pot is byte voor byte wat het was; zonder de sleutel `morePotIDs` (zoals een oudere app die leest) is het een doel met de eerste pot.
- D6: de uitbetalingen van 300 datasets, met wijzigingen van het loon per maand, een schema om de zoveel weken of dagen, een eigen salaris of eigen uren en een startdatum, komen overeen met een onafhankelijke berekening (`referenceSalarySettings`, `referenceSalaryPayouts`); het dagboek sluit.
- Prestaties: `monthLedger` op de zware testset (10 potten, 8 beleggingen, 5 jaar) mediaan 11 ms (13 ms met percentages), voor en na de wijziging; met het maximum van 12 extra overschrijfdata op alle 18 potten en beleggingen 31 ms (34 ms).
- Poorten: de prototypes in `ref-verdelen/tools/` (`verdelen-check.sh`, `contract-check2.sh`, `own-check2.sh`) draaien tegen de samengevoegde stand: `contract-check2.sh` vindt alle 97 namen van het contract van fase 1 en 2 (dat controleert ook de tekst van par. 3 tegen de code), `verdelen-check.sh 1` en `2 core` PASS, "2 maandcijfers" en "3" noemen precies de plekken die V3A en V3B/V3C nog moeten aanpassen (HomeHero, LibraryFigures, DistributePage, FlowPage, GoalPages, PurchasePages, DataPage), `own-check2.sh` leest het blok van par. 5. De navigatie (`Destination.wageChange`, de zoektermen) is in de proef meegenomen en draait in de tests.
- De impactlijst van de coördinator (`docs/work/impact2.md`) klopt met dit plan: D4 raakt de minste bestanden (de treffers in `SavingsGoalPages.swift`, `SavingsGoal.swift`, `HomePlanning.swift` en `ChartModels.swift` zijn woordtreffers op "spaardoel": de rekenpagina "Spaardoel berekenen" kent geen potten en blijft buiten dit plan), D6 de meeste, en D5 is klein omdat `transferPotToBank`, `transferBankToPot` en `transfer(from:to:)` al bestaan.

## 1. Besluiten (bindend; geen vragen)

| # | Besluit | Reden |
|---|---|---|
| **Algemeen** | | |
| A1 | **Volgorde en pakketten**: golf 1 van `plan.md` (startdatum) is klaar (HEAD c0130b2) → **fase 1: V1** (Core en teksten van D1 t/m D5, één bouwer) → **fase 2, tegelijk: `G2V2`** (golf 2 van `plan.md`, de werkuren-Core, en de loon-Core D6, één bouwer), **`V3A`** (pagina's Verdelen en alle maandcijfers) en **`V3B`** (pagina's Spaarpot, Opnemen en Doelen) → **fase 3, tegelijk: `G3A`** (golf 3A van `plan.md`, de agenda) en **`G3BV3C`** (golf 3B van `plan.md`, Salaris, met "Loon per maand"). Zes bouwers; par. 5. | V1 en G2 raken dezelfde bestanden (`Models`, `DayEvents`, `CloudSync`, `Overview`), D6 en G2 dezelfde functies (`SalarySchedule`): één bouwer per bestand per fase. De pagina's wachten alleen op V1 (V3A, V3B) of op `G2V2` (fase 3). |
| A2 | **Opslag**: elk nieuw veld wordt alleen geschreven als het iets zegt, wordt mild gelezen (`try?` of standaardwaarde, een onleesbaar element wordt overgeslagen) en een bestand zonder deze functies codeert byte voor byte als voorheen. `StartDateLegacyOutput` (golf 1) blijft ongewijzigd groen; nieuwe sleutels: `Pot/Holding.contributionExtra` en `extraTransfers`, `PercentRule.extra`, `MonthPlan.transferParts`, `FinanceData.bankShare` en `salaryChanges`, `LifeGoal.morePotIDs`. | Zelfde patroon als `MonthPlan` en `SalarySettings`; bewezen door de proeftests. |
| A3 | **Eén bron per grootheid**: het bedrag van een inleg komt uit `AllocationMath.cents(of:bases:)` en `allocationTotalCents`; de dag(en) waarop het geld beweegt uit `TransferMath.slices`; "nog te verdelen" uit `MonthFigures.unassigned`; het loon van een maand uit `salarySettings(in:)`; geld uit of naar een pot uit `withdraw` en `deposit`. Geen scherm en geen tweede functie rekent die zelf uit. Vier roosterwachters (A t/m D in par. 6.3, `verdelen-check.sh`). | Het dagboek, de saldi, Home en de grafieken blijven zo hetzelfde zeggen. |
| A4 | **Geen nieuwe `.sheet(`** (hoogstens 16, `.alert(` 0): bestaande bladen (`PotEditSheet`, `HoldingEditSheet`, `PotEntrySheet`, `GoalEditSheet`) en kaarten worden uitgebreid; de enige nieuwe pagina is `Destination.wageChange(YearMonth)` ("Loon wijzigen"). | Ontwerpregel; de teller staat op 14. |
| A5 | **Teksten en weergavehulpen** in Foundation-only bestanden `App/UI/DistributionText.swift`, `PotMoveText.swift`, `GoalPotsText.swift`, `WageText.swift` (met `WageEdit`) met een symlink in `CoreTests` (zoals `StartDateText`); de pagina's bevatten geen zin of keuze die een test niet kent. | Testbaar zonder SwiftUI. |
| A6 | **Oudere appversies** op andere apparaten kennen de nieuwe sleutels niet, laten ze weg bij opslaan en rekenen zonder (par. 7, risico 1). Alleen een doel met meer potten blijft leesbaar als doel met de eerste pot (D4.1). | Eerlijk benoemd; alle apparaten bijwerken. |
| **D1 Percentage plus extra bedrag** | | |
| D1.1 | Het extra bedrag is een veld van de percentageregel: `PercentRule.extra` (een maand) en `Pot/Holding.contributionExtra` (de standaard). Het bedrag van de maand is `percentage van het inkomen + extra`, elk op hele centen (half omhoog, het extra bedrag nooit onder 0), samen in `AllocationMath.cents(of:bases:)`. Bij een vast bedrag (modus Bedrag) bestaat het niet: dat bedrag is al het totaal. | Eén functie rekent het bedrag voor `monthFigures`, het dagboek, de potten, de beleggingen en de schattingen; ieder pad (`allocation`, `allocationCents`, `effectiveAllocation`, `MonthFiguresBuilder`, `estimatedAmount`) volgt vanzelf. |
| D1.2 | Randgevallen: percentage 0 met extra 50 is 50 (de modus blijft Percentage); zonder inkomen blijft alleen het extra bedrag; een extra bedrag onder 0, `NaN` of oneindig telt als 0; een percentage boven 100% met extra blijft toegestaan (de waarschuwing telt alleen percentages). | Gelijk aan de bestaande regels voor percentages. |
| D1.3 | Wisselen van modus behoudt het bedrag van de maand (naar Bedrag: percentage plus extra wordt het vaste bedrag; naar Percentage: begint bij de standaard, anders bij het percentage van het salaris dat het bedrag is, zonder extra). "Maak dit je standaard" neemt het extra bedrag mee. Alleen het percentage wijzigen laat het extra bedrag van de maand staan. | Het bedrag springt niet (zoals nu). |
| D1.4 | Meer verdeeld dan er is (`overAllocated`) telt het extra bedrag mee (het zit in `saved` of `invested`); "percentages samen boven 100%" blijft alleen over percentages gaan. | Een vast bedrag erbij is geen percentage. |
| **D2 Meerdere overschrijfdata** | | |
| D2.1 | Model: een **deel** (`TransferPart(day, amount)`) is een vast bedrag dat op een eigen dag (1...31, in een korte maand de laatste dag) wordt overgeschreven. De inleg van de maand blijft EEN bedrag (D1); de delen worden daar UIT gehaald en wat overblijft gaat op de standaarddag (`transferDay(for:in:)`: de dag van de maand, de eigen dag van de pot, anders je salarisdag). Standaard staan de delen op de pot of belegging (`extraTransfers`), per maand in `MonthPlan.transferParts[id]` (vervangt de standaard voor die maand, ook als lege lijst). | Op één scherm uit te leggen: "Waarvan € 50 op de 10e"; "Te verdelen", de maandcijfers en alle totalen veranderen niet, alleen wanneer het geld beweegt. |
| D2.2 | Vaste bedragen, geen aandelen. Zijn de delen samen meer dan de inleg van de maand, dan worden de laatste delen (op volgorde van dag) afgekapt en blijft er niets voor de standaarddag over; de pagina waarschuwt ("De extra data samen zijn € 40 meer dan de inleg"). Delen op dezelfde dag en delen op de standaarddag vallen samen in één overschrijving. Een negatieve inleg (geld terug naar de rekening) en een inleg van 0 hebben geen delen. Hoogstens 12 delen per pot. | Bewezen in `TransferMath`-tests en door de onafhankelijke berekening. |
| D2.3 | Echt pas op die dag: een deel is een eigen gebeurtenis (`toPot` of `toHolding`) op zijn dag, met `bankAmount` en `potAmount`; vóór het begin van die dag is niets bewogen (banksaldo, potsaldo, "Komende boekingen", Home, grafieken, waarde van een belegging), vanaf het begin van die dag wel. Het id van de gebeurtenis op de standaarddag blijft `toPot-<id>-<maand>`; een deel krijgt `-dd` erachter. | De bestaande kalenderdagregel; ids van oude gebeurtenissen blijven gelijk. |
| D2.4 | Met een startdatum telt elk stuk apart: een stuk vóór de startdag telt niet mee (niet in `allocationCents`, niet in de gebeurtenissen, niet in de potten); de rest wel. `transferCounts(_:in:)` van golf 1 blijft bestaan voor de standaarddag (de melding op de rij). | B2-regel van `plan.md`: een overschrijving vóór de start zit in je beginsaldo. |
| D2.5 | De geschiedenis verandert niet: wijzig je de standaarddelen van een pot of belegging (`setStandardTransferParts`, of via `updatePot` en `updateHolding`), dan legt de motor eerst de oude delen vast in al opgeslagen maanden vóór de lopende maand die geen eigen delen hebben. De lopende en de komende maanden volgen de nieuwe standaard. | Zoals `freezePastAllocations`: een nieuwe standaard verandert het verleden niet. |
| D2.6 | Een pot of belegging die wordt verwijderd, neemt zijn delen van de maanden mee. De bankrekening (D3) heeft geen delen. | Opruimen. |
| D2.7 | Delen van een maand die gelijk zijn aan de standaard worden niet als afwijking bewaard (`setTransferParts`): de maand blijft de standaard volgen; een lege lijst is wel een afwijking als de standaard delen heeft. Op Verdelen werkt de editor op een concept (4.1), want een rij met bedrag 0 bestaat niet in de opslag. | Anders bevriest een bewerkte maand de standaard en toont ze ten onrechte "Afwijkend". |
| **D3 De bankrekening in Verdelen** | | |
| D3.1 | **Betekenis (gekozen): een toewijzing zonder beweging, "Z1".** De bankrekening is een rij in Verdelen met dezelfde invoer als een pot (vast bedrag, of percentage plus extra bedrag; standaard en per maand) en betekent "dit deel van mijn inkomen blijft op mijn rekening". Het telt als verdeeld, dus "Nog te verdelen" kan op precies 0 uitkomen. Er gaat geen geld over: banksaldo, potsaldo, gebeurtenissen en dagboek zijn gelijk met en zonder deze rij (bewezen op 135 datasets). De rij heeft geen overschrijfdag en geen extra data. Afgewezen: Z2 (de rij als tijdinstrument: dat deel van het salaris komt pas op de datums van de rij op de bank) en Z3 (vaste overboeking pot → bank). | Z2 vraagt een tussenrekening die nergens bestaat: het salaris op de uitbetaaldag kleiner dan wat binnenkomt breekt `income == som van de binnenkomsten`, de salarisgebeurtenissen (`==` de uitbetalingen), de maandsom in `BankTimeline` en laat het banksaldo tussentijds onder het echte saldo zakken (grafiek, "onder nul"-melding). Z3 bestaat al per maand: een negatief bedrag bij een pot is "terug naar de rekening", en D5 doet het met de hand. Z1 raakt geen saldo en geen dag. Een latere keuze voor Z2 raakt alleen `BankShare.swift`, `planEvents` en het dagboek. |
| D3.2 | Opslag: `FinanceData.bankShare: BankShare` (de standaard; alleen geschreven als hij niet leeg is) en per maand onder het vaste pseudo-id `BankShare.id` (`00000000-0000-4000-8000-00000000BA4C`) in `MonthPlan.allocations` en `percentAllocations`. De bankrekening is een `ContributionSource`: `allocationRule`, `setAllocation`, `setAllocationPercent`, `AllocationEdit`, `makeStandard` en de rest werken met dat id. Een nieuwe standaard legt eerst de oude regel vast in de al opgeslagen maanden vóór de lopende maand (`freezePastBankShare`), anders veranderde het verleden. | Hergebruik: geen tweede stel functies. |
| D3.3 | **`remaining` blijft wat het was**: inkomen − bankuitgaven − gespaard − belegd, dus wat er op de rekening blijft (BankTimeline, het dagboek en Export rekenen ermee). Nieuw: `MonthFigures.toBank` (nooit negatief) en `unassigned = remaining − toBank`. **"Nog te verdelen" (huidige en komende maanden) toont `unassigned`, "Overgehouden" (verleden en periodes) toont `remaining`**: één functie, `MoneyLabels.left(_:of:current:isPeriod:)` (en `MonthBoard.left(current:)`, `MonthSummary.left(current:)`), kiest het getal bij het label; geen scherm leest `remaining` of `unassigned` zelf bij een van die labels (roosterwachter A). Wat "nog te verdelen" of "nog niet verdeeld" zegt rekent met `unassigned(in:)`/`estimatedUnassigned(in:)`: de Aankoopcheck, de Noodbuffer en de versneller "Zet je vrije ruimte in". `MonthBoard.allocated` blijft pot plus belegging (de som sluit); nieuw `distributed` (met de bankrekening) en `distributedShown(current:)` voor de meter "Verdeeld". | Zo blijft elke bestaande som en test gelijk; het enige nieuwe is wat het label "Nog te verdelen" zegt en dat de teksten van de Aankoopcheck, de Noodbuffer en de versnellers hetzelfde getal tonen als Verdelen. |
| D3.4 | Niet in Dag voor dag: geen nieuwe `DayEventKind`, geen rij in het dagboek (de uitkomst zou toch 0 zijn). `MonthLedger.toBank` toont het getal als cijfer; de csv-export blijft gelijk ("Over" is `remaining`). | Geen uitgebreide `switch`-lijsten in zes bestanden voor iets dat niets verplaatst. |
| D3.5 | Menu van Verdelen: "Rest naar bankrekening" (`sendRemainingToBank`: zet de rij op een vast bedrag gelijk aan het huidige bedrag plus `unassigned`, alleen als dat boven 0 is). "Rest over potten verdelen" verdeelt nu `unassigned`; "Standaardverdeling toepassen" en "Alles op nul zetten" nemen de bankrekening mee (en wissen de extra data van de maand). | De rest is wat nog niet is toegewezen. |
| D3.6 | De bankrekening heeft geen overschrijfdag en telt in de hele startmaand mee (zij verplaatst niets; de maand van een startdatum bepaalt het inkomen waar een percentage over rekent). Past het bankdeel niet in wat er is (`unassigned < 0`), dan meldt Verdelen "Je verdeelt € x meer dan je hebt" (`overAllocated` telt de bankrekening mee). | Eenvoud; geen aparte regel. |
| D3.7 | Waar het bankdeel verder zichtbaar is (par. 4.3): "Binnen en eruit" op Bankrekening krijgt een regel en een stuk van de meter "Bankrekening", de grafiek van het Maandoverzicht noemt het in de zin en in de annotatie van een verwachte maand (de staaf blijft op het inkomen sluiten), Home en de Bibliotheek tonen "Nog te verdelen" na het bankdeel, Dag voor dag zegt bij "Te verdelen t/m deze dag" hoeveel er aan de bankrekening is toegewezen, en de controlemeldingen van het dagboek heten "Over op je rekening" (zij gaan over `remaining`). | Elk scherm dat een getal bij "Nog te verdelen" toont moet hetzelfde zeggen als Verdelen. |
| **D4 Een doel uit meer spaarpotten** | | |
| D4.1 | Representatie: `funding` blijft `.pot(eerste)` en nieuw is `LifeGoal.morePotIDs: [UUID]?` (alleen geschreven bij meer dan één pot). Computed: `fundingPotIDs`, `isFunded(by:)`, `setFundingPots(_:)`. Geen nieuw geval in `GoalFunding`. | Een nieuw enum-geval laat elke oudere app het hele bestand als onleesbaar afkeuren (de automatische `Codable` van een enum met waarde); zo ziet een oudere app een doel met de eerste pot. Ook geen nieuwe verplichte `switch` in `Accelerators` (11 plekken). |
| D4.2 | Rekenregel (`goalInputs`): startbedrag = som van het saldo van nu van de bestaande potten; maandinleg = som van `estimatedAllocation(id, in: current)` (percentage, extra bedrag en schema-gemiddelde inbegrepen); rendement 0 zoals bij één pot; bron "N spaarpotten" (één pot: de naam). Eén pot geeft exact de getallen van vroeger. | Bewezen: gelijk aan een doel met eigen waarden met die sommen. |
| D4.3 | Een pot mag voor meer doelen meetellen: het saldo telt dan voor elk doel (geen verdeling). De pagina's zeggen het ("Deze spaarpot telt ook mee voor Auto"); `FinanceData.goals(usingPot:)`. | Eenvoudig en uitlegbaar; een verdeelsleutel is niet gevraagd. |
| D4.4 | Verwijder je een pot van een doel, dan houdt het doel zijn andere potten (de volgende wordt de eerste); zonder pot rekent het weer met de beleggingen (zoals altijd). | Zoals nu bij één pot. |
| D4.5 | Versnellers werken op de EERSTE pot van het doel (verhogen van de inleg, geld van de bank erin); potten die het doel voeden worden niet aangeboden als "overschot inzetten". De pagina Versnellers zegt het. | Beperkt de wijziging; verdelen over meer potten is een latere uitbreiding. |
| **D5 Opnemen met bestemming** | | |
| D5.1 | `enum MoneyEnd { outside, bank, pot(UUID) }`; `withdraw(fromPot:amount:to:note:date:)` en `deposit(toPot:amount:from:note:date:)` leggen twee gekoppelde boekingen (zelfde `pairID`, zelfde datum) via de bestaande `transferPotToBank`, `transferBankToPot` en `transfer(from:to:)`. **Wat "Opnemen" altijd deed blijft de standaard**: `.outside` = alleen de potkant, het geld verdwijnt uit het overzicht (de huidige schakelaar staat standaard uit). | Geverifieerd in `PotEntrySheet`: zonder "Naar de bankrekening" krijgt de bank niets; oude boekingen blijven gelijk. |
| D5.2 | "Opnemen" krijgt de keuze "Waar gaat het naartoe?" (Nergens (uit je overzicht), Bankrekening, elke andere pot); "Storten" de keuze "Waar komt het vandaan?". "Overboeken" blijft (pot → pot) en gebruikt dezelfde functie. Het bedrag komt echt aan: banksaldo en potsaldo van de dag, dagboek en geschiedenis van beide kanten; een helft verwijderen verwijdert de andere (bestaand). | Zoals de gebruiker vroeg; geen bestaande functie verdwijnt. |
| D5.3 | Randgevallen: dezelfde pot als bron en bestemming of een onbekende pot doet niets (`false`); verwijder je later de bestemmingspot, dan blijft de bronkant staan (het geld ging met de pot mee, zoals bij elke verwijderde pot) en het dagboek sluit; met een startdatum tellen beide helften op dezelfde dag mee. Bij bestemming Bankrekening zonder ingevuld saldo meldt het blad dat het saldo nog niet bekend is (de boeking begint dan het saldo). | Bestaand gedrag, zichtbaar gemaakt. |
| **D6 Loon per maand** | | |
| D6.1 | `FinanceData.salaryChanges: [SalaryChange]` (op maand gesorteerd, één per maand) naast `salary`, dat het loon van het begin blijft. Een wijziging (`from: YearMonth`, `hourlyRate?`, `fixedMonthly?`, `hoursPerWeek?`) verandert alleen de ingevulde velden en geldt vanaf haar maand tot de volgende. Het schema, de salarisdag, het anker en de soort (uurloon of vast bedrag) horen er niet bij: die blijven `SalaryScheduleEdit` (legt het verleden vast). | Eenvoudig en genoeg voor de vraag; wisselen van soort is een schemawijziging. |
| D6.2 | **Welke datum? De maand waarin de uitbetaling op je rekening komt** (de dag van de uitbetaling), ook als een deel van de uren in de maand ervoor is gewerkt, ook bij uren uit de agenda: de hele uitbetaling rekent met het loon van die maand. Eén functie: `salarySettings(forPayoutOn: CalendarDay)` (voor de werkuren uit de agenda) gelijk aan `salarySettings(in: maand)`. | De app rekent per maand; "salaris in november" krijgt het loon van november. Een latere keuze per gewerkte dag (of per maand van de uren) verandert alleen deze ene functie. |
| D6.3 | Een eigen salaris van een maand (`salaryOverride`) gaat voor en blijft het totaal; eigen uren (`hoursOverride`) rekenen met het loon van die maand; `freezeSalaryHistory` legt het verleden vast met het loon van elke maand. | Gelijk aan wat een maand nu al zegt. |
| D6.4 | Schattingen (`estimatedIncomeBases`, `estimatedFigures`, buffer, versnellers, doelen, toekomstschatting) rekenen met het loon van de maand die ze schatten: `salarySettings(in: maand)`; zonder maand het laatste loon (`latestSalarySettings`). De Aankoopcheck (`resolvedWage(manual:data:in:)`) rekent zonder maand met het loon van de lopende kalendermaand: ze gaat over wat je nu verdient. | Een verhoging vanaf januari telt in de toekomstschatting vanaf januari, maar niet in een aankoop van vandaag. |
| D6.5 | **`SalaryScheduleEdit.edit` blijft voor het schema; een nieuw bedrag gaat via `FinanceData.setWage(current:hourlyRate:fixedMonthly:hoursPerWeek:)`**: er is al een wijziging of er viel in de maanden ervoor salaris → een wijziging vanaf de lopende maand (er wordt NIETS vastgelegd); anders (nog niets in het verleden) wordt het loon zelf aangepast. De velden van de standaardkaart op Salaris gebruiken dit. | "Eerdere maanden houden hun loon zonder vastgelegde overschrijvingen." |
| D6.6 | Migratie: bestaande gegevens hebben één `SalarySettings` voor alle tijden en geen wijzigingen: alles blijft byte voor byte gelijk. | Standaard leeg. |
| D6.7 | Samenspel met de startdatum en de werkuren uit de agenda (`plan.md`): een wijziging in de startmaand geldt voor de uitbetalingen die meetellen; `exactPayCents(rate:weightedMinutes100:)` krijgt het uurloon van `salarySettings(forPayoutOn:)`. | Een bron voor het uurloon. |
| D6.8 | De pagina "Loon wijzigen" (`WageChangePage`, route `Destination.wageChange(YearMonth)`, geen blad) bewaart met een knop (geen live schrijven: het effect op een uitbetaling staat vooraf op de pagina), kiest een maand vanaf de lopende maand tot 24 maanden vooruit, bewaart per veld alleen wat afwijkt van het loon van de maand ervoor (`WageEdit.change`), waarschuwt bij een maand die al voorbij is (de motor staat het wel toe) en laat een wijziging verwijderen met een bevestiging. Op de pagina Salaris staat de lijst als kaart "Loon per maand" met de rij "Nu". | Een pagina is makkelijker te lezen en te testen dan een blad; de Foundation-only logica (`WageEdit`) staat in de tests. |

## 2. Core per wens (V1 bouwt 2.1 t/m 2.5 en 2.7; V2 bouwt 2.6)

Referentiecode: `/tmp/arch-probe2/ref-verdelen/` (`core/` = de nieuwe bestanden, `core-edits-vs-golf1.diff` = alle wijzigingen aan `App/` ten opzichte van golf 1 (HEAD c0130b2), `tests/` = de proeftests). De bouwer neemt de referentie over of schrijft opnieuw; wat hier staat is bindend, de referentie is het bewijs dat het past. Alles in dit hoofdstuk is Foundation-only en staat in `App/Core` (of, voor teksten en weergavehulpen, in `App/UI` met een symlink in `CoreTests`).

**Stap 0 (V1).** Basislijn: `/tmp/ctl-NAAM/run-all.sh` 0 fouten, `swift test` 1957 groen (10 overgeslagen), `docs/work/start-check.sh` PASS. Leg EERST de fixture van het oude formaat vast: `VerdelenLegacyOutput` (een vaste dataset met percentage-potten, een belegging, een doel met een pot, maanden met `allocations` en `percentAllocations`, een salaris met uurloon; de verwachte uitvoer is de byte-voor-byte uitvoer van de HUIDIGE `FinanceStorage.makeFileEncoder()`, als tekst in de test). `StartDateLegacyOutput` van golf 1 blijft ongewijzigd groen. Volgorde van bouwen: 2.1 (D1) → 2.2 (D2) → 2.3 (D3) → 2.4 (D4) → 2.5 (D5) → `ledgerScenario` en de eigenschapstests → teksten en weergavehulpen; na elke stap `swift test`.

### 2.1 D1: een percentage plus een extra bedrag

Regels:
1. Het bedrag van de maand is `percentCents(inkomen, percentage) + extraCents(extra)`, elk op hele centen (half omhoog), opgeteld met `CentsMath.add`. Eén functie rekent het: `AllocationMath.cents(of: PercentRule, bases:)`. Alles wat een bedrag nodig heeft (`monthFigures`, `allocation`, `allocationCents`, `effectiveAllocation`, `estimatedAmount`, het dagboek, de potten, de beleggingen, de schattingen) komt daar vanzelf uit.
2. `extra` hoort bij de modus Percentage (`PercentRule.extra` voor één maand, `Pot/Holding.contributionExtra` voor de standaard). Bij de modus Bedrag bestaat het niet: dat bedrag is al het totaal; een achtergebleven `contributionExtra` telt dan niet (`contributionRule` leest het alleen bij Percentage).
3. Randgevallen: percentage 0 met extra 50 is 50; zonder inkomen blijft alleen het extra bedrag over; een extra bedrag onder 0, `NaN` of oneindig telt als 0 (`extraCents`); percentage boven 100% met extra mag (de waarschuwing `percentagesOver100` telt alleen percentages, `percentOverrun` ongewijzigd); het extra bedrag wordt op hele centen bewaard.
4. Wisselen van modus behoudt het bedrag van de maand: naar Bedrag wordt het vaste bedrag het totaal (percentage plus extra); naar Percentage begint de maand bij de standaardregel als die een percentage of een extra bedrag heeft (`AllocationEdit.startingPercent`), anders bij het percentage van het salaris dat het huidige bedrag is, zonder extra. Alleen het percentage wijzigen laat het extra bedrag van de maand staan (`setAllocationPercent(extra: nil)`); "Maak dit je standaard" neemt het extra bedrag mee (`setContributionPercent(extra:)`).
5. Met een startdatum telt het extra bedrag mee als deel van het totaal van de maand: het percentage rekent over het inkomen dat meetelt (B5 van `plan.md`), het extra bedrag wordt niet evenredig verlaagd; welk stuk van het totaal meetelt hangt van de overschrijfdag(en) af (2.2).
6. Een versneller die een percentage-inleg verhoogt maakt er een vast bedrag van (bestaand gedrag, `estimatedDefaultAllocation` bevat het extra bedrag); het achtergebleven `contributionExtra` is dan inert. Het formulier van een pot of belegging bewaart `contributionExtra` alleen bij de modus Percentage.

| Bestand | Wijziging (referentie: `core-edits-vs-golf1.diff`) |
|---|---|
| `Core/Allocation.swift` | `PercentRule.extra` (init `extra: Double = 0`, sleutel `extra` alleen geschreven bij > 0 centen, mild gelezen); `AllocationMath.extraCents(_:)`, `cleanExtra(_:)`; `cents(of:bases:)`; `ContributionSource` krijgt `contributionExtra` en `extraTransfers`; `contributionRule`; `AllocationRule.summary` ("3,5% van je salaris plus € 25"); `rawCents(of:in:)`; `allocationTotalCents` en `allocationCents` (2.2); `setAllocationPercent(_:in:percent:basis:extra:)`, `setAllocationRule`, `setContributionPercent(_:percent:basis:extra:current:)`, `sameRule`, `percentAmount(_:of:extra:in:)`. |
| `Core/Models.swift` | `Pot.contributionExtra`, `Holding.contributionExtra` (sleutel, mild lezen, alleen schrijven bij > 0 centen). |
| `UI/SavingsDisplay.swift` | `AllocationEdit`: `startingPercent`, `setMode`, `setExtra`, `setBasis`, `makeStandard`, `resetToStandard`, `differsFromStandard` (ook voor de delen van 2.2). |
| `UI/Fields.swift` | `ContributionFields(extra: Binding<Double>? = nil, extraTitle:)`: een `NumberRow` "Extra bedrag erbij" onder de keuze, alleen bij Percentage en alleen als `extra` is meegegeven (de bankrij en oude aanroepen blijven gelijk). |
| `UI/DistributionText.swift` (nieuw) | `ExtraAmountText` (`title`, `footer`, `breakdown(percentAmount:extra:)`). |

### 2.2 D2: meerdere overschrijfdata

Model: een **deel** `TransferPart(day, amount)` is een vast bedrag dat op een eigen dag (1...31, in een korte maand de laatste dag) wordt overgeschreven. De inleg van de maand blijft ÉÉN bedrag (D1); de delen worden daar UIT gehaald, wat overblijft gaat op de standaarddag (`transferDay(for:in:)`: de dag van de maand, de eigen dag van de pot, anders de salarisdag). Standaarddelen staan op de pot of belegging (`extraTransfers`), delen van één maand in `MonthPlan.transferParts[id]` (vervangen de standaard voor die maand, ook als lege lijst).

Regels:
1. `TransferMath.slices(totalCents:parts:standardDay:month:)` is de ENIGE plek die een inleg over dagen verdeelt: een inleg van 0 geeft niets; een negatieve inleg (geld terug naar de rekening) of een inleg zonder delen is één stuk op de standaarddag; anders worden de delen op volgorde van dag van het totaal afgehaald (het laatste deel wordt afgekapt als ze samen meer zijn, dan blijft er niets voor de standaarddag over), stukken op dezelfde dag (ook op de standaarddag) vallen samen, een dag na het einde van de maand is de laatste dag, de uitkomst telt altijd precies `totalCents` op en is op dag gesorteerd. `normalized` maakt bedragen hele centen, laat delen van 0 of minder weg, voegt dezelfde dag samen en kapt af op `maxParts` = 12.
2. Echt pas op die dag: een stuk is een eigen gebeurtenis (`planEvents`: `toPot` of `toHolding`, `bankAmount` en `potAmount`) op zijn dag; het id van de standaarddag blijft `toPot-<id>-<maand>`, een deel krijgt `-dd` erachter (`FinanceData.transferEventID`). Vóór het begin van die dag is er niets bewogen (banksaldo, potsaldo, "Komende boekingen", Home, grafieken, waarde van een belegging), vanaf het begin van die dag wel. `potLedgers` en `potTimeline` lezen dezelfde stukken (`alloc-<maand>` en `alloc-<maand>-<dag>`), `Invest.settledAllocation(_:in:today:cache:)` laat een belegging per stuk meetellen.
3. De som van de maand verandert niet: `monthFigures`, `allocation(_:in:)` en alle totalen zien één bedrag; alleen wanneer het beweegt verschilt.
4. Met een startdatum telt elk stuk apart: een stuk vóór de startdag valt weg (niet in `allocationCents`, niet in de gebeurtenissen, niet in de potten), de rest telt (`countedTransferCents`). Zonder startdatum of in een gewone maand is dat het hele bedrag. `transferCounts` van golf 1 blijft bestaan; de melding bij een rij op Verdelen gebruikt `uncountedTransferSlices(for:in:)`, dat de stukken geeft die niet meetellen.
5. Een nieuwe standaard verandert het verleden niet: `setStandardTransferParts(_:parts:current:)` en `updatePot`/`updateHolding` leggen eerst de oude delen vast in de al opgeslagen maanden vóór de lopende maand die geen eigen delen hebben (`freezePastTransferParts`); de lopende en de komende maanden volgen de nieuwe standaard.
6. **`setTransferParts(_:in:parts:)` bewaart geen afwijking die gelijk is aan de standaard**: is de genormaliseerde lijst gelijk aan de standaard van de pot of belegging, dan wordt de eigen lijst van de maand weggehaald (de maand volgt de standaard, ook als die later verandert); een lege lijst terwijl de standaard delen heeft IS een afwijking (deze maand alles op de standaarddag). `clearTransferParts` haalt de afwijking weg ("Terug naar standaard"; `AllocationEdit.resetToStandard` doet dat samen met het bedrag).
7. "Maak dit je standaard" (`AllocationEdit.makeStandard`) neemt de delen van de maand mee naar de standaard (`setStandardTransferParts`) en wist daarna de eigen delen van de maand als die de lopende of een latere is.
8. `applyDefaultAllocations(in:)` (menu van Verdelen: "Standaardverdeling toepassen") wist de delen van de maand; "Alles op nul zetten" laat ze staan (niets om over te schrijven). Een pot of belegging die wordt verwijderd neemt zijn `transferParts` van de maanden mee (`deletePot`, `deleteHolding`). De bankrekening heeft geen delen (2.3).
9. Randgevallen die een test moet noemen: dag 31 in een maand van 30 of 28/29 dagen; februari in een schrikkeljaar; een deel vóór de startdag; een deel op de standaarddag; delen samen meer dan de inleg; een percentage van 0 met extra bedrag en delen; een extra bedrag zonder inkomen; een negatieve inleg met delen; een lege lijst als afwijking; delen bij een belegging met waardemeting op de dag van het deel.

| Bestand | Wijziging |
|---|---|
| `Core/Transfers.swift` (nieuw) | `TransferPart`, `TransferSlice`, `TransferMath` (`maxParts`, `normalized`, `slices`, `overflowCents`), `FinanceData`: `standardTransferParts(of:)`, `transferParts(for:in:)`, `hasTransferPartsOverride`, `transferSlices(for:in:totalCents:)`, `transferSlices(for:in:)`, `uncountedTransferSlices`, `countedTransferCents(_:id:in:parts:)`, `transferEventID(prefix:id:month:slice:)`, `setTransferParts`, `clearTransferParts`, `setStandardTransferParts`, `freezePastTransferParts`. |
| `Core/Models.swift` | `Pot/Holding.extraTransfers` en `MonthPlan.transferParts` (sleutels; alleen schrijven als niet leeg; mild lezen). |
| `Core/Allocation.swift` | `effectiveAllocation`, `allocationCents`, `allocation(_:in:cache:)` rekenen via `countedTransferCents`; `allocationTotalCents` is het hele bedrag zonder startfilter. |
| `Core/DayEvents.swift` | `planEvents`: per pot en belegging een gebeurtenis per stuk. |
| `Core/Pots.swift` | `potLedgers` en `potTimeline` per stuk (alleen stukken die `counts(day:in:)`); `updatePot` en `deletePot` zoals boven. |
| `Core/Invest.swift` | `settledAllocation`, gebruikt door `derivedOpening` en de waardeberekening; `updateHolding`, `deleteHolding`. |
| `Core/Plan.swift` | `allocation(_:in:)` = `CentsMath.value(allocationCents(...))`; `applyDefaultAllocations` wist `transferParts`. |
| `UI/DistributionText.swift` | `TransferPartsText` (`title` "Extra overschrijfdagen", `addTitle`, `partTitle`, `summary(slices:standardDay:)`, `explanation`, `overflowWarning`, `shortMonthNote`, `accessibilityLabel`). |
| `UI/TransferPartsEditor.swift` (nieuw, SwiftUI) | De lijst met delen (4.1). |

### 2.3 D3: de bankrekening in Verdelen

**Betekenis (gekozen): een toewijzing zonder beweging.** De rij "Bankrekening" in Verdelen heeft dezelfde invoer als een pot (vast bedrag, of percentage plus extra bedrag; standaard en per maand; "Afwijkend", "Terug naar standaard", "Maak dit je standaard") en betekent: "dit deel van mijn inkomen blijft op mijn rekening". Het telt als verdeeld, dus "Nog te verdelen" kan op precies 0 uitkomen. Er gaat geen geld over: banksaldo, potsaldo, gebeurtenissen en dagboek zijn gelijk met en zonder de rij. De rij heeft geen overschrijfdag en geen delen.

De drie lezingen naast elkaar (de keuze is beslist op wat de rest van de app moet blijven zeggen):

| | **Z1b: toewijzing zonder beweging (gekozen)** | Z2: tijdinstrument | Z3: vaste overboeking pot naar bank |
|---|---|---|---|
| Betekenis | "dit blijft op mijn rekening", telt als verdeeld | het deel komt pas op de datums van de rij op de bank (het salaris staat eerst elders) | elke maand een bedrag uit een pot naar de bank |
| Beweegt er geld? | nee | ja, de bank krijgt het salaris later | ja, pot naar bank |
| `income` = som van de binnenkomsten | blijft | breekt | blijft |
| Salarisgebeurtenissen = uitbetalingen | blijft | breekt | blijft |
| Maandsom van `BankTimeline` (`figures.remaining`) | blijft | breekt | blijft |
| Banksaldo tussen salarisdag en datum | gelijk | lager dan het echte saldo (een rekening die nergens bestaat; "onder nul"-melding) | gelijk |
| "Nog te verdelen" kan 0 worden | ja | ja | nee |
| Bestaande tests en teksten | allemaal gelijk | tientallen aanpassingen | geen |
| Bewijs | `testTheBankShareMovesNoMoneyOnAnyDay` (135 datasets, 428 maanden met een bankdeel naast dezelfde gegevens zonder: banksaldo, potsaldo en gebeurtenissen van elke dag en het vermogen gelijk), `testRemainingToTheBankReachesExactlyZero` (meer dan 300 maanden) | niet gebouwd | niet gebouwd; bestaat al per maand als negatief bedrag bij een pot (`allowsNegativeAmount`) en als D5 met de hand |

Z1a (de bankrij verlaagt `remaining`) is afgewezen: dan zouden "Overgehouden", `BankTimeline`, de export en alle geschiedenis een ander getal tonen dan wat er echt op de rekening blijft. **Wat het getal is** (hele centen, `MonthFigures`):
- `remaining` = inkomen − bankuitgaven − gespaard − belegd: wat er op de rekening blijft, ongewijzigd, ook in het verleden. `BankTimeline`, `MonthLedger.allReconciles`, de csv-export ("Over") en alle bestaande tests rekenen ermee.
- `toBank` = het deel van de verdeling dat aan de bankrekening is toegewezen (nooit negatief: een negatief bedrag telt als 0).
- `unassigned` = `remaining − toBank`: wat er nog niet is toegewezen (kan negatief zijn). **Dit is het getal bij het label "Nog te verdelen"** (huidige en komende maanden); het verleden en de periodes (Half jaar, Jaar) tonen met het label "Overgehouden" `remaining`. Eén functie kiest het getal bij het label: `MoneyLabels.left(_:of:current:isPeriod:)` (en `MonthBoard.left(current:)`, `MonthSummary.left(current:)`); geen scherm leest `remaining` of `unassigned` zelf bij een van die labels (roosterwacht 6.3). Zonder bankdeel zijn ze gelijk, dus elk bestaand scherm blijft gelijk.
- `FinanceData.unassigned(in:)` en `estimatedUnassigned(in:)` zijn de bronnen voor alles wat "nog te verdelen" of "nog niet verdeeld" zegt: de Aankoopcheck (`PurchaseContext.remainingThisMonth`), de Noodbuffer (`defaultMonthlySaving`) en de versneller "Zet je vrije ruimte in" met zijn controle "je verdeelt dan meer dan je inkomen". Wat geld verplaatst (`BankTimeline`, `MonthLedger`, `Export`) blijft op `remaining`.
- `overAllocated` telt `toBank` mee (`allocated = saved + invested + toBank`): past het bankdeel niet, dan meldt Verdelen "Je hebt meer verdeeld dan er te verdelen was" (bestaande `.overAllocated`-melding). `MonthBoard.allocated` blijft pot plus belegging (de som `inkomen − bankuitgaven − allocated = remaining` sluit); nieuw is `MonthBoard.distributed` (met de bankrekening) voor de meter "Verdeeld" op Verdelen.

Opslag en regels: `FinanceData.bankShare: BankShare` (de standaard; alleen geschreven als hij afwijkt van `BankShare()`), per maand onder het vaste pseudo-id `BankShare.id` (`00000000-0000-4000-8000-00000000BA4C`) in `MonthPlan.allocations` en `percentAllocations`. `BankShare` is een `ContributionSource` (`startMonth` = jaar 1, geen delen): `allocationRule`, `setAllocation`, `setAllocationPercent`, `setContributionAmount/Percent`, `AllocationEdit` en `makeStandard` werken met dat id. `defaultAllocationRule` geeft vóór de startmaand `.amount(0)`. Een nieuwe standaard legt de oude regel eerst vast in de al opgeslagen maanden vóór de lopende maand zonder eigen regel (`freezePastBankShare`), anders verandert het verleden. `synthesizedPlan`, `materialize` en `applyDefaultAllocations` nemen de bankrij mee als `bankShare != BankShare()`, "Alles op nul zetten" ook; `spreadRemainingOverPots` verdeelt `unassigned` (het bankdeel is al verdeeld); `sendRemainingToBank(in:)` ("Rest naar bankrekening") zet de rij op het huidige bedrag plus `unassigned`, alleen als dat boven 0 is. `percentOverrun` telt het percentage van de bankrij mee. De rij telt in de hele startmaand mee (zij verplaatst niets; het inkomen van de startmaand bepaalt waar een percentage over rekent). Niet in Dag voor dag: geen nieuw `DayEventKind`, geen rij in het dagboek (de uitkomst zou 0 zijn); `MonthLedger.toBank` toont het getal.

**Het besluit is geïsoleerd**: kiest de gebruiker later toch Z2, dan verandert alleen `Core/BankShare.swift`, `planEvents` en het dagboek; `MoneyLabels.left` en de schermen blijven.

| Bestand | Wijziging |
|---|---|
| `Core/BankShare.swift` (nieuw) | `BankShare`, `MonthFigures.unassigned`, `FinanceData.hasBankShare`, `bankShareAmount(in:)`, `unassigned(in:)`, `estimatedUnassigned(in:)`, `freezePastBankShare`, `sendRemainingToBank`. |
| `Core/Plan.swift` | `MonthSummary.toBank/unassigned`, `MonthFigures.toBank` (klem op 0) en `overAllocated`, `PeriodSummary.toBank/unassigned`, `monthFigures(of:...)` zet `f.toBank`, `synthesizedPlan`, `materialize`, `applyDefaultAllocations`, `clearAllocations`, `spreadRemainingOverPots`, `monthSummary`. |
| `Core/Ledger.swift` | `MonthLedger.toBank` en `unassigned`. |
| `Core/Allocation.swift` | `defaultAllocationRule`, `contributionRule(of:)`, `setContributionPercent/Amount`, `syncCurrentMonth`, `percentOverrun`, `setAllocationPercent` (grondslag) kennen `BankShare.id`. |
| `Core/Models.swift`, `Overview.swift`, `CloudSync.swift` | `bankShare` (sleutel, mild lezen, alleen schrijven als niet leeg); `isEmptyStart` en `hasContent` tellen `bankShare != BankShare()` als inhoud. |
| `Core/Purchase.swift`, `Buffer.swift`, `Accelerators.swift` | `PurchaseContext.make` (`remainingThisMonth`), `BufferCalc.defaultMonthlySaving` en de versneller "Zet je vrije ruimte in" (met zijn controle "je verdeelt dan meer dan je inkomen" in `performAccelerator`) lezen `estimatedUnassigned(in:)`/`unassigned(in:)`; `restoreAcceleratorFields` zet ook `contributionExtra` terug. |
| `UI/MoneyFigures.swift` | `MonthBoard.toBank`, `unassigned`, `distributed`, `left(current:isPeriod:)`, `leftIsNegative(current:isPeriod:)`, `distributedShown(current:isPeriod:)`, `roundingHidesLeftSum(current:isPeriod:)`; `MonthSummary.left(current:)`; `MoneyLabels.left`; `PeriodSummary.figures` met `toBank`; `ContributionInfo` (`slices`, `hasParts`, `transferNote`, `baseText`, `standardValue`, `standardCaption`) en `ContributionPreview.resolve(extra:)` (D1 en D2). |
| `UI/DistributionText.swift` | `BankShareText` (`title` "Bankrekening", `subtitle` "Blijft op je rekening", `symbol` "building.columns", `restTitle` "Rest naar bankrekening", `explanation`, `caption(toBankCents:)`, `summaryNote(toBankCents:)`). |

### 2.4 D4: een doel uit meer spaarpotten

Representatie: `LifeGoal.funding` blijft `.pot(eerste)` en nieuw is `LifeGoal.morePotIDs: [UUID]?` (alleen geschreven bij meer dan één pot). Een nieuw geval in `GoalFunding` is verboden: de automatische `Codable` van een enum met waarde laat elke oudere app het HELE bestand als onleesbaar afkeuren, terwijl een oudere app nu het doel met de eerste pot ziet (`testAnOlderAppReadsAMultiPotGoalAsAGoalWithTheFirstPot`).

Regels:
1. `LifeGoal.fundingPotIDs` (de eerste pot dan `morePotIDs`, zonder dubbelen, leeg bij een andere financiering), `isFunded(by:)`, `setFundingPots(_:)` (geen pot = `.portfolio` en `morePotIDs = nil`; één pot = `.pot(id)` zoals altijd bewaard; meer potten = `.pot(eerste)` plus de rest).
2. `goalInputs` (`Goals.swift`): startbedrag = som van `potBalanceNow` van de bestaande potten, maandinleg = som van `estimatedAllocation(id, in: current)` (percentage, extra bedrag en schema-gemiddelde inbegrepen), rendement 0, bron "N spaarpotten" (één pot: zijn naam; geen bestaande pot: "Spaarpot" met 0, zoals altijd). Eén pot geeft exact de getallen en de bytes van vroeger (`testAGoalWithOnePotIsExactlyWhatItWas`); twee potten rekenen als een doel met eigen waarden met de sommen (`testTheOutcomeEqualsOneGoalWithTheSummedValues`).
3. Een pot mag voor meer doelen meetellen: het saldo telt dan voor elk doel (geen verdeelsleutel); `FinanceData.goals(usingPot:)` geeft de doelen die een pot gebruiken (voor de waarschuwing "Deze spaarpot telt ook mee voor Auto").
4. Een pot verwijderen haalt hem uit elk doel dat hem gebruikte (`deletePot`: `setFundingPots(de rest)`; de volgende pot wordt de eerste; zonder pot rekent het doel weer met de beleggingen).
5. Versnellers werken op de EERSTE pot van het doel; potten die het doel voeden worden niet aangeboden als "overschot inzetten" (`isFunded(by:)` in `Accelerators.swift`); herstellen van een versneller zet `morePotIDs` terug (`restoreAcceleratorFields(.funding)`). De pagina Versnellers zegt het (`GoalPotsText.acceleratorNote`).
6. Zie "spaardoelen" als de doelen van de pagina Doelen (pensioen, vakantie, parttime, eigen doel). De rekenpagina "Spaardoel berekenen" kent geen potten en blijft zoals ze is.
7. Met een startdatum verandert er niets aan de regels: het doel rekent met het saldo van nu (`potBalanceNow`, dat de startdatum al kent) en met de inleg van een gemiddelde maand (`estimatedAllocation`, hele startmaand); een pot zonder boekingen vóór de start telt gewoon mee.

| Bestand | Wijziging |
|---|---|
| `Core/Models.swift` | `LifeGoal.morePotIDs` (sleutel, alleen schrijven bij een waarde). |
| `Core/Goals.swift` | `fundingPotIDs`, `isFunded(by:)`, `setFundingPots(_:)`, `goals(usingPot:)`, `goalInputs`. |
| `Core/Pots.swift` | `deletePot` (regel 4). |
| `Core/Accelerators.swift` | `isFunded(by:)` bij "Spaarpotten boven hun doel"; `morePotIDs` herstellen. |
| `UI/GoalPotsText.swift` (nieuw) | `GoalPotsText` (`pickerTitle` "Spaarpotten", `pickerFooter`, `needsOnePot`, `acceleratorNote`, `potNames`, `sharedWarning(otherGoalNames:)`, `potLine(goalNames:)`, `sourceLine(potNames:)`). |

### 2.5 D5: opnemen en storten met bestemming of herkomst

`enum MoneyEnd: Hashable { outside, bank, pot(UUID) }`; `FinanceData.withdraw(fromPot:amount:to:note:date:) -> Bool` en `deposit(toPot:amount:from:note:date:) -> Bool` (`@discardableResult`) leggen twee gekoppelde boekingen (zelfde `pairID`, zelfde datum) via de BESTAANDE `transferPotToBank`, `transferBankToPot` en `transfer(from:to:)`; `.outside` is alleen de potkant en is wat "Opnemen" en "Storten" altijd deden (de standaardkeuze, oude boekingen blijven gelijk). Het geld komt echt aan: het banksaldo (of het saldo van de andere pot) van de dag, het dagboek en de geschiedenis van beide kanten.

Regels: bedrag op hele centen en > 0, een onbekende pot, dezelfde pot als bron en bestemming of een onbekende doelpot doet niets (`false`); de functie controleert het saldo NIET (zoals nu houdt het blad `canSave` dat bij: opnemen hoogstens het saldo); een helft verwijderen verwijdert de andere (bestaand: `deletePotEntry`, `deleteBankEntry`); verwijder je later de doelpot, dan blijft de bronkant staan (het geld ging met de pot mee, zoals bij elke verwijderde pot, `testDeletingTheDestinationPotKeepsTheLedgerClosed`) en sluit het dagboek; met een startdatum tellen beide helften op dezelfde dag mee of niet (`testBothHalvesFollowTheStartDate`); bij bestemming of herkomst Bankrekening zonder ingevuld saldo begint de boeking het saldo (het blad zegt dat: `PotMoveText.bankUnknownNote`). Geen nieuwe code in `Bank.swift` of `Pots.swift` buiten wat boven staat. De `// raw:`-poort (`start-check.sh`) geldt: `PotMoves.swift` leest de ruwe lijsten niet.

| Bestand | Wijziging |
|---|---|
| `Core/PotMoves.swift` (nieuw) | `MoneyEnd`, `withdraw`, `deposit`. |
| `UI/PotMoveText.swift` (nieuw) | `PotMoveDirection`, `PotMoveText` (`outsideTitle` "Nergens (uit je overzicht)", `bankTitle`, `question`, `title(_:in:)`, `choices(excluding:in:)`, `footer`, `bankUnknownNote`). |

### 2.6 D6: loon per maand (V2, samen met golf 2 van `plan.md`)

`FinanceData.salaryChanges: [SalaryChange]` (op maand gesorteerd, één per maand) naast `salary`, dat het loon van het begin blijft (en alles wat niet met het bedrag te maken heeft: schema, salarisdag, anker, soort). `SalaryChange` (`from: YearMonth`, `hourlyRate?`, `fixedMonthly?`, `hoursPerWeek?`) verandert alleen de ingevulde velden en geldt vanaf haar maand tot de volgende.

**De datum (beslist): het loon van een uitbetaling is dat van de kalendermaand waarin de uitbetaling op je rekening komt**, ook als een deel van de uren in de maand ervoor is gewerkt en ook bij uren uit de agenda (de hele uitbetaling rekent met het loon van de maand van de uitbetaaldag). Dit staat op ÉÉN plek: `FinanceData.salarySettings(forPayoutOn: CalendarDay)` = `salarySettings(in: day.yearMonth)`. Een latere keuze (per gewerkte dag, of per maand van de uren) verandert alleen deze functie.

Regels:
1. `salarySettings(in:)` = `salary` met alle wijzigingen met `from <= maand` toegepast op volgorde (per veld wint de laatste); zonder wijzigingen is het `salary` zelf. `latestSalarySettings` = het loon na de laatste wijziging (voor teksten en beginwaarden zonder maand). `salaryChange(effectiveIn:)` (de rij "Nu") en `salaryChange(startingIn:)`.
2. `setSalaryChange(_:)` vervangt de wijziging van dezelfde maand, bewaart geen negatieve, `NaN` of oneindige bedragen (die velden worden nil) en laat een lege wijziging weg; de lijst blijft gesorteerd. `removeSalaryChange(from:)`.
3. Alles wat een loon van een maand nodig heeft leest `salarySettings(in: maand)`: `salaryPayoutCents`, `salaryCents`, `scheduledSalary`, `salaryHours`, `estimatedIncomeBases`, `estimatedFigures` (en zo `estimatedRemaining`/`estimatedUnassigned`), `averageMonthlyAmount` (schattingen), de versneller "Werk 2 uur extra" (loon van de lopende maand), `monthlyIncomeGap(for:in:)` en `neededCapital(for:drawdownReturn:in:)` van parttime-doelen (maand optioneel; zonder maand het laatste loon), `effectiveHourlyWage(in:)` (zonder maand het laatste loon) en `PurchaseCalc.resolvedWage(manual:data:in:)` van de aankoopcheck (zonder maand het loon van de lopende kalendermaand), `goalTemplate` (de uren van een nieuw parttime-doel) en de tekst van een versneller. Plekken die het SCHEMA lezen (`salary.isMonthly`, `payDay`, `anchor`, `cycleInterval`, `schedule`, `mode`) blijven `salary`.
4. Een eigen salaris van een maand (`salaryOverride`) gaat voor en is het totaal; eigen uren (`hoursOverride`) rekenen met het loon van die maand; `freezeSalaryHistory` legt het verleden vast met het loon van elke maand (het rekent al via `salaryCents`).
5. **`SalaryScheduleEdit.edit` blijft voor het schema** (soort, salarisdag, interval, anker; het legt het verleden vast). Een nieuw bedrag (uurloon, vast bedrag, uren per week) gaat via `FinanceData.setWage(current:hourlyRate:fixedMonthly:hoursPerWeek:)`: is er al een wijziging of viel er in de maanden ervoor salaris (`hasSalary(before:)`), dan wordt het een wijziging vanaf de lopende maand (er wordt NIETS vastgelegd); anders (nog niets in het verleden) wordt het loon zelf aangepast, zoals vroeger. De velden van de standaardkaart op Salaris en het veld "Uren per week" van de aankoopcheck gebruiken dit.
6. **Werkuren uit de agenda (G2):** `workPayoutCents(on:)` en `workReport(forPayoutOn:asOf:)` rekenen met `salarySettings(forPayoutOn: dag).hourlyRate`; `exactPayCents(rate:weightedMinutes100:)` krijgt dat uurloon; een periode die over de maandgrens loopt (24 okt t/m 20 nov, uitbetaling op 25 nov) rekent HELEMAAL met het loon van november. `usesCalendarHours` en de gemiddelde uren voor schattingen lezen `salarySettings(in:)` (het veld `hoursPerWeek` is "gemiddeld aantal uren").
7. **Startdatum:** een wijziging in of vóór de startmaand geldt voor de uitbetalingen die meetellen (vanaf de startdag); een wijziging na de startmaand verandert niets aan de startmaand. Een wijziging vóór `startMonth` is toegestaan en werkt vanaf `startMonth` (de lijst toont haar nog wel).
8. **Migratie:** bestaande gegevens hebben één `SalarySettings` en geen wijzigingen: de uitvoer van elke encoder is byte voor byte gelijk (`testWithoutChangesTheFileIsIdentical`, `VerdelenLegacyOutput`). `salaryChanges` wordt alleen geschreven als de lijst niet leeg is; een onleesbare wijziging wordt overgeslagen (`LossyBox`), de rest blijft; `isEmptyStart` en `hasContent` tellen wijzigingen als inhoud; `CloudSync.withoutMarketData` laat ze staan.
9. `WageEdit` (Foundation-only, in `UI/WageText.swift`): de logica van de pagina "Loon wijzigen" zonder SwiftUI (4.6): `start(_:month:)` (de waarden waar het formulier mee begint = `salarySettings(in: maand)`), `change(_:month:hourlyRate:fixedMonthly:hoursPerWeek:) -> SalaryChange` (een veld dat gelijk is aan het loon van de maand ervoor, op centen of op 0,001 uur, blijft nil: het volgt dat loon), `payoutPreview(_:month:change:) -> (old: Double, new: Double)` (het bedrag van een uitbetaling in `month` zonder en met de wijziging, voor "Een uitbetaling gaat van … naar …").

| Bestand | Wijziging |
|---|---|
| `Core/WageHistory.swift` (nieuw) | `SalaryChange`, `salarySettings(in:)`, `salarySettings(forPayoutOn:)`, `latestSalarySettings`, `salaryChange(effectiveIn:)`, `salaryChange(startingIn:)`, `setSalaryChange`, `removeSalaryChange(from:)`, `hasSalary(before:)`, `setWage(current:...)`, `LossyBox`. |
| `Core/Models.swift`, `Overview.swift`, `CloudSync.swift` | `salaryChanges` (sleutel; mild lezen met `LossyBox`; alleen schrijven als niet leeg); inhoudscontrole. |
| `Core/SalarySchedule.swift` | de plekken van regel 3 (`salaryPayoutCents`, `salaryCents`, `scheduledSalary`, `salaryHours`, `estimated*`); samen met de plekken van golf 2 (`workPayoutCents`). |
| `Core/Purchase.swift`, `Core/Goals.swift`, `Core/Accelerators.swift` | `effectiveHourlyWage(in:)`, `resolvedWage(manual:data:in:)`, `monthlyIncomeGap(for:in:)`, `neededCapital(...in:)` (`goalInputs` geeft `current` door), `goalTemplate`, de uurloonplekken van de versneller en `monthlyIncomeGap(for: g, in: current)` bij "Lagere kosten". |
| `UI/WageText.swift` (nieuw) | `WageText` (`sectionTitle` "Loon per maand", `pageTitle` "Loon wijzigen", `addTitle`, `footer`, `fromTitle`, `valueText`, `rowLine`, `baseLine`, `effectNote`, `deleteMessage`), `WageEdit`. |
| `Core/SampleData.swift` | `sampleWithDistribution(now:)` krijgt in V2 de regel `d.setSalaryChange(SalaryChange(from: current.adding(1), hourlyRate: d.salary.hourlyRate + 1))`. |

### 2.7 Overal: opslag, back-up, sync, export

Elk nieuw veld wordt alleen geschreven als het iets zegt, mild gelezen (`decodeLenient`, `try?`, een onleesbaar element wordt overgeslagen) en een bestand zonder deze functies codeert byte voor byte als voorheen; de encoders blijven `.sortedKeys`. Nieuwe sleutels: `PercentRule.extra`, `Pot/Holding.contributionExtra` en `extraTransfers`, `MonthPlan.transferParts`, `FinanceData.bankShare` en `salaryChanges`, `LifeGoal.morePotIDs`. `CloudSync`: `hasContent` en `Overview.isEmptyStart` tellen `bankShare` en `salaryChanges` als inhoud; `withoutMarketData` verandert niet. `Export.swift` (csv) en `ImportMapping.swift` veranderen niet ("Over" is `remaining`); `BackupService` rondreist de nieuwe velden via `Codable` (een test per veld). Oudere appversies op andere apparaten kennen de sleutels niet, laten ze weg bij opslaan en rekenen zonder (7, risico 1).

## 3. Contract (namen, handtekeningen, opslag)

Alles hieronder is bindend: dezelfde namen, dezelfde parameterlabels. Nieuwe parameters van bestaande functies hebben een standaardwaarde, zodat elk bestaand scherm en elke bestaande test ongewijzigd compileert. Nieuwe typen hebben nieuwe, unieke namen (`CoreTests` en de app zijn één module per doel).

### 3.1 Nieuwe bestanden

| Pad | Pakket | Inhoud |
|---|---|---|
| `App/Core/Transfers.swift` | V1 | 3.3: `TransferPart`, `TransferSlice`, `TransferMath`, `FinanceData`-extensie. |
| `App/Core/BankShare.swift` | V1 | 3.3: `BankShare`, `MonthFigures.unassigned`, `FinanceData`-extensie. |
| `App/Core/PotMoves.swift` | V1 | 3.3: `MoneyEnd`, `withdraw`, `deposit`. |
| `App/Core/WageHistory.swift` | G2V2 | 3.3: `SalaryChange`, `salarySettings(in:)` en de rest, `LossyBox`. |
| `App/UI/DistributionText.swift` | V1 | `ExtraAmountText`, `TransferPartsText`, `BankShareText` (3.5). Foundation-only. |
| `App/UI/PotMoveText.swift` | V1 | `PotMoveDirection`, `PotMoveText`. Foundation-only. |
| `App/UI/GoalPotsText.swift` | V1 | `GoalPotsText`. Foundation-only. |
| `App/UI/WageText.swift` | G2V2 | `WageText`, `WageEdit`. Foundation-only. |
| `App/UI/TransferPartsEditor.swift` | V1 | `TransferPartsEditor` (SwiftUI, 4.1). |
| `App/Pages/Month/WageChangePage.swift` | G2V2 (plaatshouder), G3BV3C (de pagina) | `WageChangePage(month:)` (4.6). |
| `CoreTests/Tests/MyBuddyCoreTests/DistributionText.swift`, `PotMoveText.swift`, `GoalPotsText.swift`, `WageText.swift` | V1 (drie), G2V2 (één) | Symlinks naar `../../../App/UI/<naam>.swift` (zoals `StartDateText.swift`). Geen symlink voor `TransferPartsEditor.swift` (SwiftUI). `CoreTests/Sources/MyBuddyCore` is al een map-symlink naar `App/Core`: nieuwe Core-bestanden doen vanzelf mee. |

### 3.2 Opslag (sleutels, standaard, wanneer geschreven)

| Type | Eigenschap | Sleutel | Standaard | Geschreven als |
|---|---|---|---|---|
| `PercentRule` | `extra: Double` | `extra` | 0 | `AllocationMath.extraCents(extra) != 0` (bedrag via `cleanExtra`) |
| `Pot`, `Holding` | `contributionExtra: Double` | `contributionExtra` | 0 | extra bedrag > 0 centen |
| `Pot`, `Holding` | `extraTransfers: [TransferPart]` | `extraTransfers` | `[]` | niet leeg |
| `MonthPlan` | `transferParts: [String: [TransferPart]]` | `transferParts` | `[:]` | niet leeg (een sleutel met een lege lijst is een afwijking en wordt wel geschreven) |
| `FinanceData` | `bankShare: BankShare` | `bankShare` | `BankShare()` | `bankShare != BankShare()` |
| `FinanceData` | `salaryChanges: [SalaryChange]` | `salaryChanges` | `[]` | niet leeg |
| `LifeGoal` | `morePotIDs: [UUID]?` | `morePotIDs` | `nil` | niet nil (alleen bij meer dan één pot) |
| `TransferPart` | `day`, `amount` | `day`, `amount` | 1, 0 | altijd beide; `amount` via `cleanExtra` |
| `SalaryChange` | `from`, `hourlyRate?`, `fixedMonthly?`, `hoursPerWeek?` | gelijk | alleen `from` | elk veld alleen als ingevuld en eindig |
| `BankShare` | `monthlyContribution`, `contributionMode`, `contributionPercent`, `contributionBasis`, `contributionExtra` | gelijk | `0`, `.fixed`, `0`, `.salary`, `0` | elk veld alleen als het afwijkt |

Lezen: `decodeLenient`/`try?` met de standaardwaarde; een onleesbare wijziging in `salaryChanges` wordt overgeslagen (`[LossyBox<SalaryChange>]`, daarna `compactMap` en op maand gesorteerd). Geen enkele bestaande sleutel verandert van naam of betekenis; `GoalFunding` krijgt GEEN nieuw geval.

### 3.3 Core (handtekeningen)

```swift
// Core/Transfers.swift (V1)
struct TransferPart: Codable, Equatable, Hashable, Identifiable {
    var day: Int; var amount: Double; var id: Int { day }
    init(day: Int, amount: Double)
}
struct TransferSlice: Equatable { var day: Int; var cents: Int; var isStandard: Bool }
enum TransferMath {
    static let maxParts = 12
    static func normalized(_ parts: [TransferPart]) -> [TransferPart]
    static func slices(totalCents: Int, parts: [TransferPart], standardDay: Int, month: YearMonth) -> [TransferSlice]
    static func overflowCents(totalCents: Int, parts: [TransferPart]) -> Int
}
extension FinanceData {
    func standardTransferParts(of id: UUID) -> [TransferPart]
    func transferParts(for id: UUID, in month: YearMonth) -> [TransferPart]
    func hasTransferPartsOverride(_ id: UUID, in month: YearMonth) -> Bool
    func transferSlices(for id: UUID, in month: YearMonth, totalCents: Int) -> [TransferSlice]
    func transferSlices(for id: UUID, in month: YearMonth) -> [TransferSlice]
    func uncountedTransferSlices(for id: UUID, in month: YearMonth) -> [TransferSlice]
    func countedTransferCents(_ totalCents: Int, id: UUID, in month: YearMonth, parts: [TransferPart]) -> Int
    static func transferEventID(prefix: String, id: UUID, month: YearMonth, slice: TransferSlice) -> String
    mutating func setTransferParts(_ id: UUID, in month: YearMonth, parts: [TransferPart])
    mutating func clearTransferParts(_ id: UUID, in month: YearMonth)
    mutating func setStandardTransferParts(_ id: UUID, parts: [TransferPart], current: YearMonth)
    mutating func freezePastTransferParts(_ id: UUID, parts: [TransferPart], start: YearMonth, before current: YearMonth)
}

// Core/BankShare.swift (V1)
struct BankShare: Codable, Equatable, ContributionSource {
    static let id: UUID          // 00000000-0000-4000-8000-00000000BA4C
    static let key: String       // id.uuidString
    var id: UUID { get }; var startMonth: YearMonth { get }        // YearMonth(year: 1, month: 1)
    var monthlyContribution: Double; var contributionMode: ContributionMode
    var contributionPercent: Double; var contributionBasis: IncomeBasis; var contributionExtra: Double
    var extraTransfers: [TransferPart] { get }                     // altijd []
    init()
}
extension MonthFigures { var unassigned: Int { get } }             // remaining - toBank
extension FinanceData {
    var hasBankShare: Bool { get }
    func bankShareAmount(in month: YearMonth) -> Double
    func unassigned(in month: YearMonth) -> Double                 // CentsMath.value(monthFigures(month).unassigned)
    func estimatedUnassigned(in month: YearMonth) -> Double        // CentsMath.value(estimatedFigures(month).unassigned)
    mutating func freezePastBankShare(rule: AllocationRule, before current: YearMonth)
    mutating func sendRemainingToBank(in month: YearMonth)
}

// Core/PotMoves.swift (V1)
enum MoneyEnd: Hashable { case outside, bank, pot(UUID) }
extension FinanceData {
    @discardableResult mutating func withdraw(fromPot id: UUID, amount: Double, to destination: MoneyEnd,
                                              note: String = "", date: Date = Date()) -> Bool
    @discardableResult mutating func deposit(toPot id: UUID, amount: Double, from source: MoneyEnd,
                                             note: String = "", date: Date = Date()) -> Bool
}

// Core/WageHistory.swift (G2V2)
struct SalaryChange: Codable, Equatable, Identifiable {
    var from: YearMonth; var hourlyRate: Double?; var fixedMonthly: Double?; var hoursPerWeek: Double?
    var id: String { from.key }; var isEmpty: Bool { get }
    init(from: YearMonth, hourlyRate: Double? = nil, fixedMonthly: Double? = nil, hoursPerWeek: Double? = nil)
}
extension FinanceData {
    func salarySettings(in month: YearMonth) -> SalarySettings
    func salarySettings(forPayoutOn day: CalendarDay) -> SalarySettings      // = salarySettings(in: day.yearMonth): de datumregel D6.2
    var latestSalarySettings: SalarySettings { get }
    func salaryChange(effectiveIn month: YearMonth) -> SalaryChange?
    func salaryChange(startingIn month: YearMonth) -> SalaryChange?
    mutating func setSalaryChange(_ change: SalaryChange)
    mutating func removeSalaryChange(from month: YearMonth)
    func hasSalary(before current: YearMonth) -> Bool
    mutating func setWage(current: YearMonth, hourlyRate: Double? = nil, fixedMonthly: Double? = nil, hoursPerWeek: Double? = nil)
}
struct LossyBox<T: Decodable>: Decodable { let value: T? }
```

`FinanceData` krijgt `var salaryChanges: [SalaryChange] = []` en `var bankShare = BankShare()`; `MonthPlan` krijgt `var transferParts: [String: [TransferPart]] = [:]`; `Pot` en `Holding` krijgen `contributionExtra` en `extraTransfers`; `LifeGoal` krijgt `morePotIDs`. `LifeGoal` (Goals.swift): `var fundingPotIDs: [UUID] { get }`, `func isFunded(by potID: UUID) -> Bool`, `mutating func setFundingPots(_ ids: [UUID])`; `FinanceData.goals(usingPot potID: UUID) -> [LifeGoal]`.

### 3.4 Gewijzigde handtekeningen (alle nieuwe parameters hebben een standaardwaarde)

| Was | Wordt |
|---|---|
| `PercentRule.init(percent:basis:)` | `init(percent:basis:extra: Double = 0)` |
| `setAllocationPercent(_:in:percent:basis:)` | `…basis: IncomeBasis? = nil, extra: Double? = nil` (nil = het extra bedrag van de maand blijft) |
| `setContributionPercent(_:percent:basis:current:)` | `setContributionPercent(_:percent:basis:extra: Double? = nil, current:)` |
| `percentAmount(_:of:in:)` | `percentAmount(_:of:extra: Double = 0, in:)` |
| `ContributionSource` | + `var contributionExtra: Double { get }`, `var extraTransfers: [TransferPart] { get }` |
| `AllocationMath.cents(of: PercentRule, bases:)` | zelfde handtekening, nu percentage plus extra |
| `effectiveAllocation`, `allocationCents`, `allocation(_:in:cache:)` | zelfde handtekeningen, rekenen via `countedTransferCents`; nieuw `allocationTotalCents(_:key:in:storedPlan:basesFor:)` en `rawCents(of:in:)` |
| `MonthFigures` | + `var toBank = 0` (laatste stored property, standaard 0), + `unassigned`; `overAllocated` telt `toBank` mee; in `monthFigures(of:)` wordt `toBank` op 0 geklemd |
| `MonthSummary`, `MonthLedger` | + `var toBank: Double = 0` (laatste stored property) en `var unassigned: Double { get }` (= `remaining − toBank` op centen); `PeriodSummary`: `toBank` (som) en `unassigned` berekend |
| `FinanceData.effectiveHourlyWage()` | `effectiveHourlyWage(in month: YearMonth? = nil)` (zonder maand het laatste loon, `latestSalarySettings`) |
| `PurchaseCalc.resolvedWage(manual:data:)` | `resolvedWage(manual:data:in month: YearMonth? = nil)` (zonder maand het loon van de lopende kalendermaand, `YearMonth.current()`: de Aankoopcheck gaat over wat je nu verdient; `HomePlanning` en `PurchasePages` blijven zo ongewijzigd compileren) |
| `FinanceData.goalTemplate(_:)` | het begin van de uren van een nieuw parttime-doel is `salarySettings(in: YearMonth.current()).hoursPerWeek` |
| `monthlyIncomeGap(for:)`, `neededCapital(for:drawdownReturn:)` | `…(for:in month: YearMonth? = nil)`, `…drawdownReturn:in month: YearMonth? = nil)`; `goalInputs` geeft `current` door |
| `ContributionFields` (SwiftUI) | + `extra: Binding<Double>? = nil`, `extraTitle = ExtraAmountText.title` |
| `ContributionPreview.resolve(_:percent:basis:month:)` | `resolve(_:percent:basis:extra: Double = 0, month:)` |
| `AllocationEdit` | + `setExtra(_:id:month:extra:)`, + `differsFromStandard(_:id:month:)`; `resetToStandard` en `makeStandard` nemen de delen mee |
| `ContributionInfo` | + `var slices: [TransferSlice]`, `var hasParts: Bool`; `transferNote(to:)`, `baseText`, `standardValue`, `standardCaption` kennen delen en extra bedrag |
| `DistributeText.transferCaption(_:id:month:today:)` | zelfde handtekening; bij meer dan één stuk "Wordt overgeschreven: € 50 op de 10e en € 150 op de 25e · salarisdag" |
| `BarEntry` (ChartModels.swift) | + `var toBank: Double = 0` (laatste, standaard 0) en `var unassigned: Double { get }`; `detailRows` en `text` van een verwachte maand kennen het bankdeel ("Aan bankrekening toegewezen", "Nog te verdelen"); een maand die voorbij is of de huidige maand (`isProjected == false`) blijft "Overgehouden" met `remaining` |
| `MoneyLabels` | + `static func left(_ figures: MonthFigures, of month: YearMonth, current: YearMonth, isPeriod: Bool = false) -> Int` |
| `MonthBoard` | + `toBank`, `unassigned`, `distributed`, `left(current:isPeriod:) -> Double`, `leftIsNegative(current:isPeriod:) -> Bool`, `distributedShown(current:isPeriod:) -> Double` (bankrekening erbij als het getal "Nog te verdelen" is), `roundingHidesLeftSum(current:isPeriod:) -> Bool` (`remaining`, `allocated`, `isNegative` en `roundingHidesSum` blijven); `MonthSummary.left(current:) -> Double` |
| `BankFlowFigures` (CashflowDisplay.swift) | + `month`, `toBank`, `unassigned`, `left(current:) -> Double`; `isEmpty` telt `toBank` mee; de meldingen van `LedgerCheck.overviewIssues` heten "Over op je rekening" |
| `DayBalanceRows` (CashflowPages.swift, SwiftUI) | + `toBank: Double = 0` |
| `Destination` (NavigationModel.swift) | + `case wageChange(YearMonth)`; `isTabRoot` false, `parents` = `[.income, .salary]`, `NavigationRules.go` opent in de Bibliotheek (3.8) |

### 3.5 Foundation-only hulpen in `App/UI` (alleen tekst en keuzes; bedragen en dagen komen uit de rekenmotor)

```swift
enum ExtraAmountText { static let title = "Extra bedrag erbij"; static let footer: String
    static func breakdown(percentAmount: Double, extra: Double) -> String? }
enum TransferPartsText {
    static let title = "Extra overschrijfdagen", addTitle = "Dag toevoegen", resetTitle = "Terug naar standaard", makeStandardTitle = "Maak dit je standaard"
    static func partTitle(_ part: TransferPart) -> String                    // "€ 50 op de 10e"
    static func summary(slices: [TransferSlice], standardDay: Int) -> String // "Alles op de 25e" / "€ 50 op de 10e en € 150 op de 25e"
    static func explanation(standardDay: Int) -> String
    static func overflowWarning(overflowCents: Int) -> String?
    static func shortMonthNote(parts: [TransferPart]) -> String?
    static func accessibilityLabel(_ part: TransferPart) -> String
    static func beforeStartNote(_ slices: [TransferSlice]) -> String?        // "Telt niet mee: € 150 op de 3e valt vóór je startdatum." (één stuk op de standaarddag: `StartDateText.transferBeforeStart`)
    static func standardParts(_ parts: [TransferPart]) -> String?            // "met € 40 op de 10e" (nil zonder delen)
}
enum TransferPartsDraft {
    static func displayed(draft: [TransferPart], stored: [TransferPart]) -> [TransferPart]   // het concept zolang het (genormaliseerd) gelijk is aan wat is opgeslagen
}
enum BankShareText { static let title = "Bankrekening", subtitle = "Blijft op je rekening", symbol = "building.columns", restTitle = "Rest naar bankrekening", explanation: String
    static func caption(toBankCents: Int) -> String
    static func summaryNote(toBankCents: Int) -> String? }
enum PotMoveDirection { case withdraw, deposit }
enum PotMoveText { static let outsideTitle = "Nergens (uit je overzicht)", bankTitle = "Bankrekening"
    static func question(_ direction: PotMoveDirection) -> String            // "Waar gaat het naartoe?" / "Waar komt het vandaan?"
    static func title(_ end: MoneyEnd, in data: FinanceData) -> String
    static func choices(excluding potID: UUID, in data: FinanceData) -> [MoneyEnd]   // [.outside, .bank] + andere potten
    static func footer(_ direction: PotMoveDirection, end: MoneyEnd, amount: Double, in data: FinanceData) -> String
    static func bankUnknownNote(amount: Double) -> String }
enum GoalPotsText { static let pickerTitle = "Spaarpotten", pickerFooter: String, needsOnePot = "Kies minstens één spaarpot.", acceleratorNote: String
    static func potNames(_ names: [String]) -> String
    static func sharedWarning(otherGoalNames: [String]) -> String?
    static func potLine(goalNames: [String]) -> String?
    static func sourceLine(potNames names: [String]) -> String }
enum WageText { static let sectionTitle = "Loon per maand", pageTitle = "Loon wijzigen", addTitle = "Loon wijzigen vanaf een maand", footer: String, emptyHint: String, pastMonthWarning: String
    static func fromTitle(_ month: YearMonth) -> String
    static func valueText(_ change: SalaryChange, mode: SalaryMode, isMonthly: Bool) -> String
    static func rowLine(_ change: SalaryChange, mode: SalaryMode, isMonthly: Bool) -> String
    static func baseLine(settings: SalarySettings, until first: YearMonth) -> String
    static func effectNote(old: Double, new: Double, isMonthly: Bool) -> String?
    static func deleteMessage(month: YearMonth) -> String }
enum WageEdit {
    static func start(_ data: FinanceData, month: YearMonth) -> SalarySettings
    static func change(_ data: FinanceData, month: YearMonth, hourlyRate: Double, fixedMonthly: Double, hoursPerWeek: Double) -> SalaryChange
    static func payoutPreview(_ data: FinanceData, month: YearMonth, change: SalaryChange) -> (old: Double, new: Double)
}
```

Termen (termenlijst, geen synoniemen): "Extra bedrag erbij", "Extra overschrijfdagen", "Dag toevoegen", "Bankrekening", "Rest naar bankrekening", "Nog te verdelen", "Overgehouden", "Waar gaat het naartoe?", "Waar komt het vandaan?", "Nergens (uit je overzicht)", "Spaarpotten", "Loon per maand", "Loon wijzigen". Bedragen met `Fmt.euro`/`Fmt.euroExact`, dagen met `DayText.ordinal`, lijsten met `DayText.list`, nooit met de hand opgemaakte spaties.

### 3.6 Regels voor achterwaartse compatibiliteit (elk met een test)

1. **Bytes:** gegevens zonder de nieuwe functies coderen byte voor byte als op HEAD c0130b2 (`VerdelenLegacyOutput`, `StartDateLegacyOutput`); de nieuwe sleutels komen alleen voor als ze iets zeggen.
2. **Terug en weer:** een bestand met alle nieuwe sleutels leest terug en codeert gelijk (rondreis via `FinanceStorage` en `BackupService`); een onleesbaar element van een nieuwe lijst wordt overgeslagen, de rest blijft.
3. **Oudere app:** een bestand met `morePotIDs` is voor een oudere app een doel met één pot (de sleutel ontbreekt na het weghalen: `testAnOlderAppReadsAMultiPotGoalAsAGoalWithTheFirstPot`); een oudere app laat de nieuwe sleutels weg bij opslaan (risico 1).
4. **Overal één bron:** `AllocationMath.cents(of:bases:)`, `TransferMath.slices`, `MonthFigures.unassigned`, `salarySettings(in:)`, `withdraw`/`deposit` (roosterwachters in 6.3).
5. **Ledger:** `ledgerScenario` krijgt de nieuwe reeksen AAN HET EIND, zodat bestaande zaadwaarden gelijk blijven: eerst zaad + 41_000 (V1), daarna door `G2V2` zaad + 37_000 (uren uit agenda, golf 2 van `plan.md`) en zaad + 47_000 (loon per maand).
6. **De `// raw:`-poort** (`docs/work/start-check.sh`) blijft PASS: de nieuwe bestanden lezen `bankEntries`, `bankSnapshots` en `potEntries` niet zelf.

### 3.7 Plekken die "Nog te verdelen" of "Overgehouden" tonen (D3; allemaal via `MoneyLabels.left` of `MonthBoard.left(current:)`)

`DistributePage` (`DistributeSummaryCard`: getal, kleur, meter), `FlowPage` (`FlowContent.leftTile`, `figuresGroup`, `monthsGroup`/`monthDetail`), `LibraryFigures.distributeRow`, `HomeHero` (`HomeDistributeHero`, `HomeHeroNotes`: `board.left(current:)` en `leftIsNegative`), `ChartModels` (`StackedBarModel.months`: de staaf blijft sluiten op het inkomen met "over" = `remaining`; de zin en `BarEntry.detailRows` van een huidige of verwachte maand zeggen "Nog te verdelen" = `unassigned` en een regel "Aan bankrekening toegewezen"), `CashflowDisplay` (de controlemelding noemt het getal `remaining`: de tekst wordt "Over op je rekening", want het is geen "Nog te verdelen" meer), `Purchase`, `Buffer` en `Accelerators` (Core, 2.3). Niet aanraken: `Export.swift`, `BankTimeline`, `MonthLedger.allReconciles`.

### 3.8 Navigatie (V2 voegt de bestemming toe, V1 de zoektermen)

`Destination.wageChange(YearMonth)`: exact vijf uitputtende `switch`-plekken breken (bewezen in de proef): `NavigationModel.swift` ×3 (`isTabRoot`: false; `parents`: `[.income, .salary]`; `NavigationRules.go`: Bibliotheek met ouders), `SearchIndex.swift` ×1 (`entries`: geen eigen ingang, zoals `.pot`), `DestinationView.swift` ×1 (`case .wageChange(let month): WageChangePage(month: month)`). **Let op (de typecontrole van de app ziet dit niet):** `NavigationModel.swift` is een Foundation-bestand dat ook als symlink in het testpakket staat en daar komt `YearMonth` uit `MyBuddyCore`; het bestand krijgt bovenaan `#if canImport(MyBuddyCore)`, `@testable import MyBuddyCore`, `#endif` (zoals `StartDateText.swift`), anders compileert `Destination` niet in de tests. `NavigationRulesTests.swift` en `PageCatalogTests.swift` krijgen `@testable import MyBuddyCore`; `NavigationTestSupport`: `allDestinations()` krijgt `.wageChange(<een maand>)`, `ordinal` een nieuw nummer (`caseCount` 24) en `expectedParents` `[.income, .salary]`; `SearchIndexTests.requiresPageEntry`: `.wageChange` is `false`. `PageCatalog` blijft 19 pagina's (een bestemming met een ouder hoeft er niet in). Zoektermen in `PageCatalog.swift` (V1, geen nieuwe pagina's): `.distribute` + "extra bedrag", "bankrekening", "rest naar bankrekening", "extra overschrijfdagen", "overschrijfdata"; `.salary` + "loon per maand", "loonsverhoging", "uurloon wijzigen", "vanaf een maand"; `.pots` + "opnemen naar", "overboeken", "bestemming"; `.goals` + "meer spaarpotten". `PageCatalogTests` krijgt `testTheNewTermsOfRound2AreThere` (zoals `testTheNewTermsOfFlowAndToolsAreThere`).

## 4. UI per pagina en bestand

Regels voor elk scherm van deze ronde (als `plan.md` 5 en `docs/design2/plan.md` par. 0 en 2): geen nieuwe `.sheet(` (hoogstens 16, nu 14) en geen `.alert(`; bestaande bladen (`PotEditSheet`, `HoldingEditSheet`, `PotEntrySheet`, `GoalEditSheet`) en kaarten worden uitgebreid; de ENIGE nieuwe pagina is `WageChangePage` (route `Destination.wageChange(YearMonth)`). Componenten: `PageScaffold`/`ListScaffold`, `Card`, `NumberRow`, `ActionButton`, `NavigationRow`, `ChoiceRow`, `MonthExplanation`, `MonthWarningLine`, `DayPickerRow`, `ContributionFields`, `AmountRow`, `StatTile`/`FigureRow`; kleuren `Theme.*` (geen `.secondary`, `.white`, `.black`), Dynamic Type, `Theme.minTapTarget`, `Theme.textSecondary` voor uitleg, `withAnimation(reduceMotion ? nil : Theme.motion)`; bedragen en dagen uit de hulpen van 3.5. Elke nieuwe of gewijzigde kaart of blad krijgt previews (gevuld, donker, grote tekst, leeg of fout) en VoiceOver-teksten (`accessibilityElement(children: .combine)` voor een rij met bedrag, een `accessibilityLabel` met het onderwerp bij invoer, een kop als `.isHeader`). Op de Mac gelden dezelfde pagina's; `docs/design/precheck.sh` op elk aangeraakt bestand.

### 4.1 `TransferPartsEditor` en de concepten (V1)

`App/UI/TransferPartsEditor.swift` (SwiftUI; de referentie staat als nieuw bestand in `core-edits-vs-golf1.diff`): `TransferPartsEditor(parts: Binding<[TransferPart]>, standardDay: Int, totalCents: Int? = nil, emptyHint:)`. Per deel een tegel: `Picker("Dag van de maand")` (menu; alleen dagen die geen ander deel al heeft, dus nooit twee delen op één dag), `NumberRow("Bedrag")`, `ActionButton("Verwijder deze dag", role: .destructive)`; onder de lijst `ActionButton(TransferPartsText.addTitle)` (verdwijnt bij `TransferMath.maxParts`), `TransferPartsText.explanation`, `shortMonthNote` (vanaf dag 29) en, met `totalCents`, `overflowWarning` als `TransferMath.overflowCents` > 0. Een nieuw deel begint op de eerste vrije dag vanaf de dag vóór de standaarddag, met bedrag 0 (het wordt pas bewaard met een bedrag: `normalized` laat 0 weg). VoiceOver: elk deel is één element met `TransferPartsText.accessibilityLabel`.

**De editor werkt op een CONCEPT**: een bewaarde lijst wordt genormaliseerd (delen van 0 vallen weg), dus een rij met bedrag 0 kan niet rechtstreeks aan de opslag hangen. Het blad van een pot of belegging heeft al een concept (`@State`). Op Verdelen (opslag per maand) houdt de pagina een `@State draft` bij: laden uit `transferParts(for:in:)` bij verschijnen en bij een andere maand of pot; elke wijziging van `draft` roept `store.mutate { $0.setTransferParts(id, in: month, parts: draft) }`; een wijziging van buiten (andere maand, "Terug naar standaard") vervangt `draft` alleen als `TransferPartsDraft.displayed(draft:stored:)` een andere lijst geeft (`TransferMath.normalized(draft) != TransferMath.normalized(stored)`), zodat een nieuwe rij met bedrag 0 blijft staan terwijl je typt. `TransferPartsDraft.displayed` staat in `DistributionText.swift` (Foundation-only, getest).

### 4.2 Verdelen (V3A: `Pages/Month/DistributePage.swift`, nieuw `DistributeParts.swift` en `DistributePreviews.swift`)

1. **Menu** (werkbalk, `.disabled(beforeStart)`): "Standaardverdeling toepassen", "Rest over potten verdelen", **"Rest naar bankrekening"** (`Label(BankShareText.restTitle, systemImage: BankShareText.symbol)`, `change { $0.sendRemainingToBank(in: month) }`, uitgeschakeld als `d.unassigned(in: month) <= 0`), "Alles op nul zetten".
2. **`DistributeSummaryCard`**: `figures = d.monthFigures(month)`; het getal is `MoneyLabels.left(figures, of: month, current: store.now)` (cent) onder het label van `MoneyLabels.remainingLabel`; rood als dat getal < 0. De meter en de tegel "Verdeeld" tonen `distributed` (pot, belegging en bankrekening) voor de huidige en de komende maanden en `allocated` (zonder bankrekening) voor het verleden (`MonthBoard.distributedShown(current:)`, zodat inkomen min uitgaven min verdeeld = het getoonde getal sluit); `MonthBoard.roundingHidesLeftSum(current:)` bepaalt de afrondingsregel. Nieuw: `MonthExplanation(BankShareText.summaryNote(toBankCents: figures.toBank))` als die er is. De waarschuwingen (`allocationWarnings`) blijven; "Je hebt meer verdeeld dan er te verdelen was" komt nu ook als het bankdeel te groot is.
3. **Elke rij van een pot of belegging** (`MonthAllocationRow`): `ContributionFields(..., extra: extraBinding, extraTitle: ExtraAmountText.title)` met `extraBinding` get = `rule.extra`, set = `AllocationEdit.setExtra` (alleen bij Percentage); onder het veld `MonthExplanation(ExtraAmountText.breakdown(percentAmount:extra:))` als er een extra bedrag is; de badge "Afwijkend" en de rij "Standaard" volgen `AllocationEdit.differsFromStandard` (ook voor eigen delen) en de tekst "Standaard: …" noemt de standaarddelen (`TransferPartsText.standardParts`). Het bijschrift is `DistributeText.transferCaption` (bij meer dan één stuk "Wordt overgeschreven: € 50 op de 10e en € 150 op de 25e · salarisdag"). De melding bij een startdatum wordt `TransferPartsText.beforeStartNote(d.uncountedTransferSlices(for: id, in: month))` (vervangt `transferCounts` + `StartDateText.transferBeforeStart`).
4. **Extra overschrijfdagen** per pot of belegging (alleen bij `month >= startMonth` en een bedrag > 0): een `DisclosureGroup` (dicht, `@State`) met kop `TransferPartsText.title` en onderkop `TransferPartsText.summary(slices: d.transferSlices(for: id, in: month), standardDay: d.transferDay(for: id, in: month))`; inhoud `TransferPartsEditor(parts: $draft, standardDay:, totalCents: d.rawCents(of: rule, in: month))` met het concept van 4.1. De afwijking verdwijnt met "Terug naar standaard" (`AllocationEdit.resetToStandard` wist ook de eigen delen) en met "Maak dit je standaard" (neemt de delen mee).
5. **Nieuwe kaart "Bankrekening"** (`Card(title: BankShareText.title, symbol: BankShareText.symbol, domain: .money, subtitle: BankShareText.subtitle)`) tussen Beleggen en Overschrijfdag, altijd zichtbaar (ook zonder potten): één rij met dezelfde `MonthAllocationRow` (id `BankShare.id`, naam `BankShareText.title`, `allowsNegativeAmount: false`, geen delen, geen overschrijfdag-bijschrift maar `BankShareText.caption(toBankCents:)`), daaronder `MonthExplanation(BankShareText.explanation)`. De rij heeft dezelfde invoer, "Afwijkend", "Terug naar standaard" en "Maak dit je standaard". `.disabled(month < d.startMonth)`.
6. De uitklapper "Overschrijfdag" blijft (dag van de maand); zijn uitleg krijgt één zin: "Een deel van een inleg kan op een eigen dag overgaan: zie Extra overschrijfdagen bij de pot." De uitleg onder de potten verwijst naar het extra bedrag en de extra dagen.
7. VoiceOver: de rij Bankrekening leest "Bankrekening, blijft op je rekening"; de uitklapper leest de samenvatting als waarde; het getal "Nog te verdelen" leest label en bedrag (bestaand). Previews (`DistributePreviews.swift`, host met `FinanceData.sampleWithDistribution`): gevuld, donker, grote tekst, met een bankdeel dat te groot is (rood), met delen die samen te veel zijn (waarschuwing), een maand vóór de startdatum, een startmaand met een deel vóór de startdag, leeg.

### 4.3 Maandcijfers en labels (V3A)

Alle plekken van 3.7 lezen het getal bij het label uit `MoneyLabels.left` of `MonthBoard.left(current:)`; zonder bankdeel verandert er niets.
- `Pages/Month/FlowPage.swift`: `leftTile` toont `MoneyLabels.left(period.figures, of: focus, current: now, isPeriod: mode != .month)`; "Gemiddeld overgehouden per maand" blijft op `period.remaining`; `monthsGroup` toont `summary.left(current: now)` (kleur naar het teken van dat getal); `monthDetail` blijft.
- `Pages/Library/LibraryFigures.swift` (`distributeRow`): getal en teken uit `MoneyLabels.left`; "Je hebt te veel verdeeld" bij `left < 0` en `available >= 0`.
- `Pages/Home/HomeHero.swift`: `board.left(current: month)` en `board.leftIsNegative(current: month)`; `HomeHeroNotes.list` krijgt een regel `HomeHeroNote(id: "bank", text: BankShareText.summaryNote(...), symbol: "building.columns")` als er een bankdeel is.
- `UI/ChartModels.swift`: `BarEntry.toBank`; `StackedBarModel.months` houdt de staaf gelijk (uitgaven, gespaard, belegd, over = `max(0, remaining)`: de stapel sluit op het inkomen) maar de zin van een huidige of verwachte maand en `BarEntry.detailRows` zeggen "Nog te verdelen" = `unassigned` en voegen "Aan bankrekening toegewezen" toe; `StackedBarModelTests` krijgt de gevallen.
- `UI/CashflowDisplay.swift` en `Pages/Bank/BankBalance.swift`: `BankFlowFigures` krijgt `toBank` en `unassigned` en `left(current:)`; "Binnen en eruit" toont na "Inleg in beleggingen" een regel "Bankrekening" (`CashflowText.signed(-toBank)`, alleen met bankdeel), de meter een stuk "Bankrekening" (`Theme.chartFree` met `.opacity(0.5)`) en de laatste regel het getal bij het label; de waarschuwing "Je geeft meer uit en verdeelt meer dan je inkomen" volgt `left < 0`; de controlemeldingen van `overviewIssues` heten "Over op je rekening" (en "… op de laatste dag"): het getal is `remaining`.
- `Pages/CashflowPages.swift` (`DayBalanceRows`): nieuw `toBank: Double = 0`; de rij "Te verdelen t/m deze dag" houdt zijn naam; bij een bankdeel zegt het detail "Opgebouwd in de maand. Van het totaal aan het eind van de maand heb je € 300 aan je bankrekening toegewezen." (zonder bankdeel de bestaande tekst); `BankDaySection` geeft `ledger.toBank` door.
- Bewuste `// remaining: <reden>`-regels (gate A van 6.3): `ChartModels.swift` (`let remaining = s.remaining`: de staaf sluit op het inkomen), `CashflowDisplay.swift` (de twee `compare("Over op je rekening", …)`: controle van het dagboek), `FlowPage.swift` (`period.remaining` voor "Gemiddeld overgehouden per maand"). De rest van de treffers (HomeHero, LibraryFigures, DistributePage, FlowPage) wordt `left(current:)`; zo meldt de referentie na V3A geen treffers meer.
- Niet aanraken: `Export.swift` ("Over"), `BankTimeline`, `MonthLedger.allReconciles`.

### 4.4 Spaarpot, belegging en geld bewegen (V3B)

- **`PotEditSheet` en `HoldingEditSheet`** (`Pages/Saving/PotSheets.swift`, `HoldingSheets.swift`): nieuwe `@State extra` en `parts: [TransferPart]` (in `signature` en `load()`); `ContributionFields(..., extra: mode == .percentage ? $extra : nil, ...)`; `ContributionPreview.resolve(..., extra: extra, ...)` (de regel "= € x" is percentage plus extra, de uitleg `ExtraAmountText.footer` onder het veld); `prefill(for:)`: van Percentage naar Bedrag wordt het bedrag `percentAmount(percent, of: basis, extra: extra, in:)` en `extra` gaat naar 0, van Bedrag naar Percentage begint `extra` op 0; `draftPot()`/`draftHolding()`: `contributionExtra = mode == .percentage ? AllocationMath.cleanExtra(extra) : 0` en `extraTransfers = TransferMath.normalized(parts)`. Onder "Eigen overschrijfdag" een sectie "Extra overschrijfdagen" met `TransferPartsEditor(parts: $parts, standardDay: transferDay ?? d.salaryDay(in: store.now), totalCents: d.rawCents(of: draft.contributionRule, in: store.now))`; de footer van "Geld" noemt de delen. Bewaren blijft `updatePot`/`updateHolding` (die het verleden van de delen vastleggen).
- **`PotEntrySheet`** (opnemen en storten; `PotSheets.swift`): de schakelaar `viaBank` vervalt. `@State end: MoneyEnd = .outside` en bij Opnemen en Storten één `Picker(PotMoveText.question(direction), selection: $end)` met `PotMoveText.choices(excluding: pot.id, in: data)` en `PotMoveText.title`; `canSave`: Opnemen `amount <= saldo + 0,005`; Storten uit een pot `amount <= saldo van die pot + 0,005`; `entryFooter` toont `PotMoveText.footer(direction, end:, amount:, in:)`, bij `.bank` zonder bekend banksaldo `PotMoveText.bankUnknownNote(amount:)` en de bestaande waarschuwing bij een startdatum; `hasChanges` telt `end != .outside`. Bewaren: `store.mutate { $0.withdraw(fromPot: id, amount: a, to: end, note: n) }` of `deposit(toPot:amount:from:note:)`; "Overboeken" blijft `transfer(from:to:amount:)`. Standaard blijft "Nergens (uit je overzicht)": wat Opnemen altijd deed.
- **Pagina's van de pot** (`PotDetailSections.swift`, `MoneyViews.swift`): `ContributionSummary` toont bij `info.hasParts` een regel "Overschrijving: € 50 op de 10e en € 150 op de 25e" (`TransferPartsText.summary`); het bijschrift van `transferNote(to:)` is bijgewerkt (Core/UI, V1). Een pot die een doel voedt toont onder zijn doelregel `GoalPotsText.potLine(goalNames:)` met een `NavigationRow` per doel (`d.goals(usingPot:)`). `PotHistorySections`/`RecentActivity` tonen de twee helften van een verplaatsing al als boekingen in beide geschiedenissen; geen wijziging.
- Previews (`SavingPreviews.swift`): Opnemen met bestemming Bankrekening en een andere pot, Storten uit een pot, een pot met extra bedrag en delen, een belegging met delen.

### 4.5 Doelen met meer spaarpotten (V3B: `Pages/GoalPages.swift`, `Pages/AcceleratorPages.swift`, `Pages/Planning/PlanningPreviews.swift`)

- **`GoalEditSheet`**: de keuze "Waaruit?" heet "Spaarpotten" (was "Een spaarpot"); `@State potIDs: [UUID]` (uit `goal.fundingPotIDs`) vervangt `potID`; bij Spaarpotten een rij per pot (`Toggle(pot.name)`, volgorde van de potten) onder de kop `GoalPotsText.pickerTitle` met `GoalPotsText.pickerFooter`; per aangevinkte pot die ook een ander doel voedt `MonthWarningLine(GoalPotsText.sharedWarning(otherGoalNames:))`; zonder pot `GoalPotsText.needsOnePot` en `canSave` uit; `builtGoal()` gebruikt `setFundingPots`. De eerste pot voorselecteren als je Spaarpotten kiest (zoals nu). Zonder spaarpotten blijft "Je hebt nog geen spaarpotten."
- **Doelpagina** ("Zo is het berekend"): bij meer dan één pot onder de tegels `PlanningFootnote(GoalPotsText.sourceLine(potNames:))`; de uitleg van een parttime-doel rekent met het loon van de lopende maand: `d.monthlyIncomeGap(for: goal, in: store.now)` en `d.salarySettings(in: store.now).hoursPerWeek`. Bij een versneller op een doel met meer potten staat `GoalPotsText.acceleratorNote` op de pagina Versnellers.
- Niet aanraken: `SavingsGoalPages.swift`, `SavingsGoal.swift` (de rekenpagina "Spaardoel berekenen" kent geen potten) en `HomePlanning.swift`.

### 4.6 Salaris: Loon per maand (V3C, in dezelfde bouwbeurt als golf 3B van `plan.md`)

**`SalaryPage`** (`Pages/Month/SalaryPage.swift`; volgorde van de kaarten: Standaard salaris, **Loon per maand**, de uren van de volgende uitbetalingen (3B van `plan.md`), Wanneer krijg je salaris):
- De velden Uurloon, Uren per week en Per maand/Per uitbetaling van de standaardkaart lezen `store.data.salarySettings(in: store.now)` en schrijven met `store.mutate { $0.setWage(current: store.now, ...) }` (NIET via `SalaryScheduleEdit.edit`); de Soort-keuze, het schema, de salarisdag, het interval en het anker blijven `SalaryScheduleEdit` (legt het verleden vast). Met wijzigingen staat onder de velden `MonthExplanation("Dit is het loon van deze maand. Wijzigingen per maand staan hieronder bij Loon per maand.")`.
- **Kaart "Loon per maand"** (`Card(title: WageText.sectionTitle, symbol: "eurosign.arrow.circlepath", domain: .money)`): zonder wijzigingen `MonthExplanation(WageText.emptyHint)`; met wijzigingen eerst `WageText.baseLine(settings: d.salary, until: eerste.from)` (geen link), dan per wijziging een `NavigationRow(title: WageText.fromTitle(c.from), subtitle: WageText.valueText(c, mode: d.salary.mode, isMonthly: d.salary.isMonthly), destination: .wageChange(c.from))`, de rij die nu geldt (`d.salaryChange(effectiveIn: store.now)`) met de badge "Nu"; daaronder `ActionButton(title: WageText.addTitle, symbol: "plus.circle") { router.open(.wageChange(store.now.adding(1))) }` en `MonthExplanation(WageText.footer)`. Elke rij is één VoiceOver-element met `WageText.rowLine`.
- **`WageChangePage(month:)`** (`Pages/Month/WageChangePage.swift`, titel `WageText.pageTitle`, `PageScaffold`; V2 levert een plaatshouder met dezelfde init): kaart "Vanaf welke maand?" met `Picker("Vanaf", selection: $month)` (menu; van de lopende maand tot 24 maanden vooruit, plus de maand van een bestaande wijziging als die daarbuiten valt); kaart "Nieuw loon" met bij een uurloon `NumberRow("Uurloon")` en `NumberRow("Uren per week", unit: .plain("uur"))`, bij een vast bedrag `NumberRow(isMonthly ? "Per maand" : "Per uitbetaling")` en `NumberRow("Uren per week")` (voor het uurloon in de Aankoopcheck); de velden beginnen bij `WageEdit.start(d, month:)` en worden opnieuw geladen als de maand verandert; eronder `MonthExplanation(WageText.effectNote(old:new:isMonthly:))` uit `WageEdit.payoutPreview` (niet bij `usesCalendarHours`: dan rekent de uitbetaling met je agenda); ligt de maand in het verleden `MonthWarningLine(WageText.pastMonthWarning)`. Knoppen: `ActionButton("Bewaar", prominent)` → `store.mutate { $0.setSalaryChange(WageEdit.change(...)) }` en `dismiss()`, uitgeschakeld als de wijziging leeg is (`change.isEmpty`: niets wijkt af van het loon van de maand ervoor); `ActionButton("Verwijder deze wijziging", role: .destructive)` alleen als `d.salaryChange(startingIn: month) != nil`, met `.confirmationDialog` en `WageText.deleteMessage(month:)`. Een pagina, geen blad; `Destination.wageChange(month)` (3.8); geen eigen zoekingang (je komt er via Salaris).
- Overige leesplekken van het loon (3.4/2.6): `Pages/PurchasePages.swift` (het veld "Uren per week" in `weeklyHoursBinding` leest `salarySettings(in: store.now).hoursPerWeek` en schrijft met `setWage(current: store.now, hoursPerWeek:)`; `showsWeeklyHours` leest `salarySettings(in: store.now)`; `autoWage` is `effectiveHourlyWage(in: store.now)`), `Pages/Settings/DataPage.swift` (`configuredSalary` = `salarySettings(in: month).monthlyAmount()`), en `Core/Goals.swift` (`goalTemplate`: de beginwaarde van de uren van een nieuw parttime-doel is `salarySettings(in: YearMonth.current()).hoursPerWeek`; dat doet V2).
- Previews (`WagePreviews.swift`): geen wijzigingen, twee wijzigingen met "Nu", `WageChangePage` nieuw/bewerken/verwijderen, uurloon en vast bedrag, donker, grote tekst, een maand in het verleden.

### 4.7 Navigatie, zoeken, debug, screenshots, documentatie

- **V1:** zoektermen in `PageCatalog.swift` (3.8) en `PageCatalogTests`; `SampleData.sampleWithDistribution(now:)`.
- **V2:** `Destination.wageChange(YearMonth)` en de vijf `switch`-plekken (3.8), `NavigationTestSupport.allDestinations()` en `NavigationRulesTests` (de gevallen van `.wageChange`: onder Inkomen en Salaris, nooit een herhaling in het pad), plaatshouder `WageChangePage`.
- **G3A (in dezelfde bouwbeurt als de agenda van `plan.md`, want die bezit deze bestanden):** `DebugLaunch.swift`: in `destination(named:)` `case "wagechange": return .wageChange(store.now.adding(1))`; in `apply(to:store:)` vóór de rest `if arguments.contains("-mybuddy-demo-verdelen") { store.mutate { $0 = FinanceData.sampleWithDistribution(now: Date()); $0.materialize(upTo: store.now) } }`; kopregel van de doc-comment: "`-mybuddy-demo -mybuddy-demo-verdelen` (voorbeelddata met een extra bedrag, extra overschrijfdag, bankdeel en een loonwijziging)". `scripts/ci-screenshots.sh` (in het blok `if [ "$appearance" = "light" ]`, achter `shot distribute`): `shot distribute-extra -mybuddy-demo-verdelen -mybuddy-tab library -mybuddy-open distribute`, `shot distribute-extra-2 -mybuddy-demo-verdelen -mybuddy-tab library -mybuddy-open distribute -mybuddy-scroll 700`, `shot salary-wage -mybuddy-demo-verdelen -mybuddy-tab library -mybuddy-open salary -mybuddy-scroll 450`, `shot wage-change -mybuddy-demo-verdelen -mybuddy-tab library -mybuddy-open wagechange`; en in de kop van het script de regel `-mybuddy-demo-verdelen`. `README.md` en `system_architecture.md`: per wens één alinea (D1 t/m D6 in 3 tot 4 regels: wat de gebruiker ziet, waar de rekenregel staat: `AllocationMath.cents(of:)`, `TransferMath.slices`, `BankShare`/`MonthFigures.unassigned`, `withdraw`/`deposit`, `LifeGoal.morePotIDs`, `salarySettings(in:)`), de tabel van `Destination` en de lijst van roosterwachters (6.3). `Tests/AppTests` krijgt niets nieuws (de schermen zijn dun; de logica staat in `CoreTests`).

## 5. Werkpakketten, golven, eigendom

**Volgorde** (golf 1 van `plan.md`, de startdatum, is klaar en vastgelegd: HEAD c0130b2): **fase 1: V1** → **fase 2: `G2V2`, `V3A` en `V3B` tegelijk** → **fase 3: `G3A` en `G3BV3C` tegelijk**. Zes bouwers in totaal. De fasen van dit plan zijn niet de golven van `plan.md`: golf 2 (werkuren-Core) wordt gebouwd door `G2V2` samen met de loon-Core (D6), golf 3A door `G3A`, golf 3B door `G3BV3C` samen met de pagina's van D6. De eigendomsregels hieronder zijn een bovenverzameling van de regels van `plan.md` voor golf 2 en 3: vanaf nu gebruikt de coördinator `docs/work/own-check2.sh`, niet meer `own-check.sh` (dat de bestanden van deze ronde niet kent).

| Pakket | Fase | Wat | Bestanden (hoofdlijn) | Wacht op |
|---|---|---|---|---|
| **V1** | 1 | Core en teksten van D1 t/m D5; poorten | `Core/` (2.1 t/m 2.5, 2.7), `UI/` (MoneyFigures, SavingsDisplay, Fields, DistributionText, PotMoveText, GoalPotsText, TransferPartsEditor), `PageCatalog`, `CoreTests`, `docs/work` | niets |
| **G2V2** | 2 | Golf 2 van `plan.md` (werkuren-Core) en de loon-Core (D6, 2.6); `Destination.wageChange` | `Core/`, `UI/WageText.swift`, `UI/WorkDisplay.swift`, `NavigationModel`, `SearchIndex`, `DestinationView`, `SettingsDestination`, plaatshouders, `CoreTests` | V1 |
| **V3A** | 2 | Verdelen en alle maandcijfers (4.2, 4.3) | `Pages/Month/Distribute*`, `FlowPage`, `LibraryFigures`, `HomeHero`, `Bank*`, `CashflowPages`, `ChartModels`, `CashflowDisplay` | V1 |
| **V3B** | 2 | Spaarpot, belegging, opnemen en doelen (4.4, 4.5) | `Pages/Saving/*`, `GoalPages`, `AcceleratorPages`, `MoneyViews` | V1 |
| **G3A** | 3 | Golf 3A van `plan.md` (agenda, project, instellingen) plus de aansluitingen van 4.7 | `Calendar/`, `MyBuddyApp`, `RootView`, `Debug/`, `project.yml`, `.github/`, `scripts/`, `README.md`, `system_architecture.md` | G2V2 |
| **G3BV3C** | 3 | Golf 3B van `plan.md` (Salaris en teksten) plus "Loon per maand" (4.6) | `SalaryPage`, `WageChangePage`, `IncomePage`, `PurchasePages`, `DataPage`, `HomeShelves`, `CashflowPages` | G2V2 |

**Leeswijzer** (wat elke bouwer leest, naast de regels van `plan.md` voor zijn eigen golf):

| Pakket | Leest in dit plan |
|---|---|
| V1 | par. 1 (A1 t/m A6, D1 t/m D5), 2 (kop en 2.1 t/m 2.5, 2.7), 3 (alles behalve 3.3 `WageHistory`, 3.5 `WageText` en `WageEdit`, de rij `Destination`), 5, 6 |
| G2V2 | par. 1 (A, D6, D2.7 en D3.3 voor de Core die ze raken), 2.6, 3.2 tot en met 3.5 (de loonregels), 3.8, 5, 6.2 (V2) en 6.3 (B, C) |
| V3A | par. 1 (D1 t/m D3), de regels van 2.2 en 2.3, 3.4, 3.5, 3.7, 4.1 tot en met 4.3, 5, 6.3 (A) |
| V3B | par. 1 (D1, D2, D4, D5), 3.5, 4.1, 4.4, 4.5, 5 |
| G3A | par. 4.7, 5, 6.1 |
| G3BV3C | par. 1 (D6), 2.6, 3.5 (`WageText`, `WageEdit`), 4.6, 5, 6.3 (A en B) |

In de tekst heet het D6-deel van `G2V2` (de loon-Core) kortweg V2 en het D6-deel van `G3BV3C` (de pagina's) V3C. De pagina's wachten alleen op de Core: `V3A` en `V3B` op V1 (zij hebben niets van `G2V2` nodig), `G3A` en `G3BV3C` op `G2V2`. `V3A`, `V3B` en `G2V2` raken elkaars bestanden niet; dat dwingt `own-check2.sh` af.

**Bouwrecept voor fase 2 (drie bouwers, één werkboom).** `G2V2` verandert de Core terwijl `V3A` en `V3B` ertegen typechecken: een half werkende Core van `G2V2` zou hun controle breken. Daarom werken `V3A` en `V3B` in een EIGEN KOPIE van de werkboom van na fase 1: `rsync -a --exclude .build --exclude .git /home/user/MyBuddy/ /tmp/ws-NAAM/`, een privé-kopie van de controlescripts (`cp -r /tmp/ctl-all /tmp/ctl-NAAM`, in `make.sh` de bronmap `/tmp/ws-NAAM/App`) en `swift test --scratch-path /tmp/sb-NAAM` in `/tmp/ws-NAAM/CoreTests`. Aan het eind kopiëren ze ALLEEN hun eigen bestanden (volgens `own-check2.sh 2 --owner`) terug naar de hoofdboom; de coördinator draait daarna alle poorten op de hoofdboom. `G2V2` werkt rechtstreeks in de hoofdboom en houdt `App/Core` na elke stap compileerbaar (`run-all.sh quick` 0 fouten). In fase 1 en 3 werkt de bouwer(s) in de hoofdboom (fase 3: de bestanden zijn disjunct en de Core staat vast).

Regels voor elke bouwer: lees par. 0 en 2 van `docs/design2/plan.md` (componenten) en par. 1 tot en met 4 van dit plan; nieuwe typen met nieuwe namen (3.1); iOS 26-API's achter `#available`, alleen-iOS achter `#if os(iOS)`; per nieuw scherm een `#Preview`; `docs/design/precheck.sh` op elk aangeraakt bestand; een fout in andermans bestand laat je staan en meld je (`docs/work/own-check2.sh --owner <pad> <fase>`); wat dit plan een test noemt, bouw je mee en je laat de bestaande tests staan (hun tekst of getal alleen wijzigen als 6.2 dat noemt).

**Fase 1, V1.** Stap 0 en volgorde: 2 (kop). Eerst de nieuwe poorten (kleine scripts in `docs/work/`; werkende prototypes staan in `ref-verdelen/tools/`): `own-check2.sh` (kopie van `own-check.sh` met `docs/work/plan2.md`, kolommen `fase1 fase2 fase3`, een pad zonder regel telt overal als "-", extra optie `--only <eigenaar>`: meldt de veranderde bestanden die van een andere eigenaar zijn), `contract-check2.sh <fase>` (zoekt elke naam van 3.3 tot en met 3.5 van die fase met `grep -q "<declaratie>" <bestand>` en faalt bij een ontbrekende naam of een ontbrekend bestand), `verdelen-check.sh <fase>` (6.3). Dan 2.1 t/m 2.5, 2.7, de teksten (3.5), `TransferPartsEditor`, de zoektermen, `sampleWithDistribution`, de proeftests als blijvende tests (6.2) en de eigenschapstests. *Klaar*: `run-all.sh` 0 fouten en 0 `ONBEWAAKT`; `swift test` minimaal 2040 groen (1957 bestaande ongewijzigd, op de bewuste tekstwijzigingen van 6.2 na, plus de 74 gevallen van de proef en minstens 9 voor de opslag); `start-check.sh`, `design-checks.sh`, `verdelen-check.sh 1`, `contract-check2.sh 1`, `own-check2.sh 1` PASS; elk bestand zonder de nieuwe functies codeert byte-gelijk aan HEAD; `monthLedger` mediaan hoogstens 15 ms (de referentie meet 11 tot 13 ms voor en na). Niet aanraken: `App/Pages` (geen enkel scherm), `StartDate.swift`, `Export.swift`, `ImportMapping.swift`.

**Fase 2, G2V2.** Golf 2 van `plan.md` (par. 3 daar, met zijn tests van 3.5) en 2.6 hier, in deze volgorde: eerst `WageHistory.swift` en `Models` (`salaryChanges`), dan de leesplekken van 2.6 (regel 3), dan de werkuren-Core van `plan.md`: `workPayoutCents(on:)` en `workReport(forPayoutOn:asOf:)` gebruiken `salarySettings(forPayoutOn:)`; `usesCalendarHours`; dan `Destination.wageChange`, de vijf `switch`-plekken, `NavigationTestSupport`, de plaatshouders `WageChangePage(month:)` (toont alleen de titel en de maand) en `WorkHoursPage`; dan `WageText.swift` met `WageEdit`. `ledgerScenario` krijgt zijn reeksen AAN HET EIND: + 37_000 (uren uit agenda, van `plan.md`) en + 47_000 (loon per maand). *Klaar*: `run-all.sh` 0 fouten; `swift test` minimaal (het aantal na fase 1) + 80 (golf 2 van `plan.md`) + 40 (D6) groen, dus bij 2040 na fase 1 minstens 2160; de eigenschapstests dekken de kenmerken "uren uit agenda" (minstens 8 datasets), "startdatum" en "loon per maand" (minstens 8 datasets met een wijziging, 8 met een schema om de zoveel weken of dagen en een wijziging, 8 met een eigen salaris of eigen uren naast een wijziging); `verdelen-check.sh 2 core` (controle B in `App/Core` en C), `contract-check2.sh 2`, `own-check2.sh 2 --only G2V2` PASS. Niet aanraken: `App/Pages` buiten de plaatshouders en `DestinationView`, `App/Calendar`.

**Fase 2, V3A en V3B.** Elk zijn onderdeel van 4, in een eigen kopie (bouwrecept). `V3A`: 4.2 en 4.3; *klaar*: `run-all.sh` 0 fouten; `design-checks.sh`; `verdelen-check.sh 2 maandcijfers` (controle A: elke `.remaining` in `App/Pages` en `App/UI` is vervangen door `left(current:)` of heeft `// remaining: <reden>`); `own-check2.sh 2 --only V3A`; previews van 4.2; de uitbreidingen van `StackedBarModelTests` en `CashflowDisplayTests` (minstens 12 gevallen, waaronder de twee van de proef: bankdeel in de zin, in `detailRows`, in `BankFlowFigures`, `DayBalanceRows`-tekst, de meldingstekst "Over op je rekening"); `swift test` ongewijzigd groen. `V3B`: 4.4 en 4.5; *klaar*: `run-all.sh` 0 fouten; `design-checks.sh` (`.sheet(` blijft 14); `own-check2.sh 2 --only V3B`; de previews van 4.4 en 4.5; elk nieuw VoiceOver-label; `swift test` ongewijzigd groen. Beide leggen hun pagina's-logica niet in de view: wat een tekst of een keuze is staat al in de hulpen van 3.5 (V1).

**Fase 3, G3A.** Golf 3A van `plan.md` (par. 4.1 tot en met 4.4 daar) en 4.7 hier (alleen de aansluitingen: `DebugLaunch`, `ci-screenshots.sh`, `README.md`, `system_architecture.md`). **G3BV3C.** Golf 3B van `plan.md` (par. 4.5 daar) en 4.6 hier, in één keer in `SalaryPage.swift` (de volgorde van de kaarten staat in 4.6). *Klaar* (beide): `run-all.sh` 0 fouten en 0 `ONBEWAAKT`; `design-checks.sh`; `verdelen-check.sh 3` (alle controles, ook B in `App/Pages`); `own-check2.sh 3`; `swift test` ongewijzigd groen; de previews van 4.6 (`G3BV3C`); de CI van de coördinator groen (iOS, macOS, tests, screenshots).

### Wat dit plan verandert aan `plan.md`

1. B9 (laatste zin): een nieuw uurloon of vast bedrag gaat niet meer via `SalaryScheduleEdit.edit` maar via `FinanceData.setWage` (2.6, regel 5); het schema blijft `SalaryScheduleEdit`. "Eerdere maanden vastleggen" (`freezeSalaryHistory`) blijft bestaan.
2. 3.2 regel 4 en 6 (werkuren): het uurloon van `exactPayCents(rate:weightedMinutes100:)` en van `hoursOverride` komt uit `salarySettings(forPayoutOn:)` (2.6, regel 6); `usesCalendarHours` blijft op `salary.mode`.
3. 4.5 (`SalaryPage`): de volgorde van de kaarten staat in 4.6 hier; de velden van de standaardkaart schrijven met `setWage`.
4. 5 (eigendom): vanaf nu geldt het blok hieronder voor golf 2, 3A en 3B (het is een bovenverzameling van het blok van `plan.md`); `docs/work/own-check.sh` blijft bestaan voor golf 1 maar wordt niet meer gebruikt.
5. De ledger-reeksen: `plan.md` noemt de zesde reeks (zaad + 37_000); omdat V1 eerst klaar is staat die van V1 (zaad + 41_000) ervoor en volgt die van golf 2 erna, elk AAN HET EIND. De nummering in de commentaren doet er niet toe, alleen de volgorde van toevoegen.

### Eigendom per fase

<!-- EIGENDOM-BEGIN -->
```text
# pad (meest specifiek wint) | fase1 | fase2 | fase3   ("-" = niemand, "C" = de coördinator)
# fase 1: V1. fase 2: G2V2 (golf 2 van plan.md plus loon-Core), V3A, V3B. fase 3: G3A (golf 3A van plan.md), G3BV3C (golf 3B van plan.md plus Loon per maand).
App/ - - -
App/Core/ V1 G2V2 -
App/Navigation/ - - -
App/Navigation/PageCatalog.swift V1 - -
App/Navigation/NavigationModel.swift - G2V2 -
App/Navigation/SearchIndex.swift - G2V2 -
App/Navigation/SettingsScene.swift - - G3A
App/UI/ - - -
App/UI/DistributionText.swift V1 - -
App/UI/PotMoveText.swift V1 - -
App/UI/GoalPotsText.swift V1 - -
App/UI/TransferPartsEditor.swift V1 - -
App/UI/MoneyFigures.swift V1 - -
App/UI/SavingsDisplay.swift V1 - -
App/UI/Fields.swift V1 - -
App/UI/WageText.swift - G2V2 -
App/UI/WorkDisplay.swift - G2V2 -
App/UI/ChartModels.swift - V3A -
App/UI/CashflowDisplay.swift - V3A -
App/UI/MoneyViews.swift - V3B -
App/Pages/ - - -
App/Pages/DestinationView.swift - G2V2 -
App/Pages/Month/DistributePage.swift - V3A -
App/Pages/Month/DistributeParts.swift - V3A -
App/Pages/Month/DistributePreviews.swift - V3A -
App/Pages/Month/FlowPage.swift - V3A -
App/Pages/Library/LibraryFigures.swift - V3A -
App/Pages/Home/HomeHero.swift - V3A -
App/Pages/Home/HomePreviews.swift - V3A -
App/Pages/Bank/BankBalance.swift - V3A -
App/Pages/Bank/BankDays.swift - V3A -
App/Pages/CashflowPages.swift - V3A G3BV3C
App/Pages/Saving/PotSheets.swift - V3B -
App/Pages/Saving/HoldingSheets.swift - V3B -
App/Pages/Saving/PotDetailSections.swift - V3B -
App/Pages/Saving/SavingPreviews.swift - V3B -
App/Pages/GoalPages.swift - V3B -
App/Pages/AcceleratorPages.swift - V3B -
App/Pages/Planning/PlanningPreviews.swift - V3B -
App/Pages/Month/WageChangePage.swift - G2V2 G3BV3C
App/Pages/Month/WagePreviews.swift - - G3BV3C
App/Pages/Month/SalaryPage.swift - - G3BV3C
App/Pages/Month/SalaryHoursCard.swift - - G3BV3C
App/Pages/Month/IncomePage.swift - - G3BV3C
App/Pages/Home/HomeShelves.swift - - G3BV3C
App/Pages/PurchasePages.swift - - G3BV3C
App/Pages/Settings/DataPage.swift - - G3BV3C
App/Pages/Settings/SettingsDestination.swift - G2V2 G3A
App/Pages/Settings/WorkHoursPage.swift - G2V2 G3A
App/Pages/Settings/WorkHoursParts.swift - - G3A
App/Pages/Settings/SettingsView.swift - - G3A
App/Pages/Settings/AboutPage.swift - - G3A
App/Calendar/ - - G3A
App/MyBuddyApp.swift - - G3A
App/RootView.swift - - G3A
App/Debug/ - - G3A
CoreTests/ V1 G2V2 -
CoreTests/Tests/MyBuddyCoreTests/V3A/ - V3A -
CoreTests/Tests/MyBuddyCoreTests/V3B/ - V3B -
CoreTests/Tests/MyBuddyCoreTests/V3C/ - - G3BV3C
CoreTests/Tests/MyBuddyCoreTests/StackedBarModelTests.swift V1 V3A -
CoreTests/Tests/MyBuddyCoreTests/CashflowDisplayTests.swift V1 V3A -
Tests/AppTests/ - - G3A
project.yml - - G3A
.github/ - - G3A
scripts/ - - G3A
README.md - - G3A
system_architecture.md - - G3A
docs/work/ V1 - -
docs/work/plan.md C C C
docs/work/plan2.md C C C
docs/work/impact2.md C C C
```
<!-- EIGENDOM-EINDE -->

Toelichting: `App/Core/` heeft in fase 2 één eigenaar (`G2V2`): V3A en V3B hebben geen Core-wijziging nodig; hebben ze die toch, dan melden ze het. De proef-symlinks in `CoreTests/Tests/MyBuddyCoreTests/` (`DistributionText.swift` e.d.) vallen onder `CoreTests/` (V1, `WageText.swift` G2V2). Een pad zonder regel telt overal als "-". `docs/work/plan.md` en `docs/work/plan2.md` zijn van de coördinator; de scripts van V1 staan in `docs/work/`.

## 6. Verificatie

### 6.1 Poorten (elke bouwer, vóór "klaar")

1. **Typecontrole** (de enige compiler hier, Swift 6.0.3 met nagemaakte frameworks): `/tmp/ctl-NAAM/run-all.sh` (50 s; per bouwer een eigen kopie met `cp -r /tmp/ctl-all /tmp/ctl-NAAM`, de bronmap in `make.sh` aanpassen): `TOTAAL fouten (alle varianten): 0` en 0 `ONBEWAAKT`; tijdens het werk `run-all.sh quick`. Een fout in andermans bestand meld je (`own-check2.sh --owner`).
2. **Core-tests**: `cd CoreTests && swift test --scratch-path /tmp/sb-NAAM` met `PATH=/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin:$PATH` (±3 minuten; de referentie draait 2053 tests in 166 s): 0 fouten; de minima per pakket staan in 6.2.
3. `docs/design/design-checks.sh` PASS (`.sheet(` hoogstens 16, nu 14; `.alert(` 0; geen `.secondary`, geen `.white`/`.black`, geen "Meetpunt"), `docs/work/start-check.sh` PASS, `docs/work/verdelen-check.sh <fase>` (6.3), `docs/work/contract-check2.sh <fase>`, `docs/work/own-check2.sh <fase>` (en `--only <eigenaar>`).
4. **CI** (de coördinator pusht na elke fase naar een `claude/**`-tak): iOS en macOS bouwen, tests, screenshots (de nieuwe regels van 4.7 na fase 3).
5. **Handmatig op een toestel** (hier niet uitvoerbaar, 7 risico 2): Verdelen met een percentage plus extra bedrag, een extra overschrijfdag (de pot en het banksaldo veranderen pas op die dag: Bankrekening en Dag voor dag), de rij Bankrekening en "Rest naar bankrekening" (Nog te verdelen 0, banksaldo ongewijzigd), Opnemen naar de bankrekening en naar een andere pot (beide geschiedenissen, banksaldo, pot), een doel met twee potten (Doelen en Versnellers), Loon wijzigen vanaf volgende maand (Salaris, Inkomen, Dag voor dag op de uitbetaaldag), een startdatum midden in de maand met een deel vóór de startdag, VoiceOver op de nieuwe rijen, iPad en Mac (pane en breedte), een bestand van de nieuwe versie openen op een apparaat met de oude versie.

### 6.2 Tests per pakket (nieuwe bestanden met unieke klassenamen; de bestaande tests blijven staan)

De proeftests staan in `/tmp/arch-probe2/ref-verdelen/tests/` onder `*ProofTests`; de bouwer neemt ze over onder de blijvende naam hieronder (of schrijft ze opnieuw met dezelfde gevallen) en voegt de extra gevallen toe. De referentie draait alles samen op de stand van golf 1: 1957 bestaande plus 96 nieuwe tests (94 blijvende en 2 meetinstrumenten), 2053 in totaal, 0 fouten. In de referentie zitten V1 en V2 door elkaar: `LedgerTestSupport.swift` heeft twee blokken (de zesde reeks, zaad + 41_000, is van V1; de zevende, zaad + 47_000, met `referenceSalarySettings`, is van V2), `LedgerConsistencyTests.swift` de dekkingsregel "loon per maand" (V2) en `StartDayPropertyTests.swift` de regel met `referenceSalarySettings(...)` (V2); alles met `SalaryChange`, `salaryChanges`, `setWage` of `WageEdit` hoort bij V2, de rest bij V1.

**V1 (minstens 2040 groen in totaal: 1957 + de 74 gevallen hieronder + minstens 9):**

| Bestand | Gevallen (de namen van de proef; "nieuw" = extra) |
|---|---|
| `ExtraAmountTests` (D1) | `testPercentagePlusExtraIsOneAmount`, `testPercentageZeroWithExtraWorksAsAFixedAmount`, `testExtraWithoutIncomeKeepsOnlyTheExtra`, `testExtraAlsoWorksForAMonthOverride`, `testExtraSurvivesMakeStandardAndModeSwitch`, `testNonsenseExtraIsIgnored`, `testOldFilesEncodeByteIdenticalWithoutAnExtra`; nieuw: het extra bedrag telt mee in `overAllocated` maar niet in `percentTotal`; schattingen (gemiddelde maand) bevatten het extra bedrag; een versneller die een percentage verhoogt zet percentage plus extra om in één vast bedrag; het extra bedrag in een startmaand wordt niet evenredig verlaagd |
| `TransferPartsTests` (D2) | `testSlicesWithoutPartsAreOneTransfer`, `testSlicesCarvePartsOutOfTheTotal`, `testPartsOnTheStandardDayMergeIntoOneTransfer`, `testPartsLargerThanTheTotalAreCutAndNothingRemains`, `testDay31InAShortMonthIsTheLastDay`, `testNegativeAndZeroTotalsHaveNoParts`, `testNormalizedMergesSortsAndLimits`, `testPotAndBankMoveOnlyOnTheDayOfAPart`, `testTheMonthTotalDoesNotDependOnTheParts`, `testAMonthOverrideReplacesTheStandardAndAnEmptyListClearsIt`, `testChangingTheStandardPartsKeepsThePast`, `testTheStartDateDropsEarlyPartsOnly`, `testAStartDateAfterTheStandardDayButBeforeAPartKeepsOnlyThePart`, `testPercentageLinesSplitToo`, `testHoldingValueCountsAPartFromItsDay`, `testPotTimelineShowsEachPartOnItsDate`, `testDeletingAPotRemovesItsMonthParts`, `testMakeStandardAndResetCoverTheParts`, `testUncountedSlicesListWhatTheStartDateDrops`, `testUpcomingBookingsShowEachPartInOrder`, `testOldFilesWithoutPartsReencodeIdentically`; nieuw: `testSetTransferPartsEqualToTheStandardClearsTheOverride`, `testFebruaryInALeapYearAndAShortMonth` (28, 29, 30), `testAPartOnTheFirstOfTheMonthAndInterest`, `testAnExtraDateBeforeTheStartDateInsideTheStartMonth`, `testTwelvePartsAreTheLimit`, `testPartsWithAZeroPercentageAndAnExtraAmount` |
| `BankShareTests` (D3) | `testTheBankShareMovesNoMoneyOnAnyDay` (eigenschap: ≥ 100 datasets met een bankdeel naast dezelfde zonder: banksaldo, potsaldo en gebeurtenissen van elke dag, vermogen en `remaining` gelijk; `unassigned == remaining − toBank`), `testRemainingToTheBankReachesExactlyZero`, `testABankShareLargerThanTheRemainderIsOverAllocated`, `testStandardBankShareAsPercentagePlusExtraAndPast`, `testStandardDistributionAndZeroTheMonthIncludeTheBank`, `testSpreadRemainingOverPotsLeavesTheBankShareAlone`, `testTheLabelFigureFollowsTheMonth`, `testOldFilesWithoutABankShareStayIdenticalAndTheKeyIsInert`, `testTheBankShareCountsInTheWholeStartMonth`, `testContentChecksSeeABankShareAndWageChanges` (de loonwijzigingen komen in V2), `testTheLedgerCarriesTheBankShareAsAFigureOnly`, `testTheSampleWithDistributionShowsTheNewPossibilities` (de regel over het uurloon van volgende maand komt in V2, samen met de loonwijziging in `sampleWithDistribution`); nieuw: een negatief bankbedrag telt als 0; `unassigned(in:)` en `estimatedUnassigned(in:)` voeden de Aankoopcheck, de Noodbuffer en de versneller "Zet je vrije ruimte in" (en zonder bankdeel zijn de uitkomsten gelijk aan die op `remaining`); `MonthBoard.left(current:)`, `leftIsNegative`, `distributedShown`, `roundingHidesLeftSum`; `MoneyLabels.left` voor maand, toekomst, verleden en periode |
| `PotMovesTests` (D5) | `testWithdrawToTheBankArrivesOnTheBank`, `testWithdrawToAnotherPotArrivesThere`, `testWithdrawOutsideOnlyTouchesThePot`, `testDepositFromBankPotAndOutside`, `testInvalidMovesDoNothing`, `testBothHalvesFollowTheStartDate`, `testDeletingTheDestinationPotKeepsTheLedgerClosed`, `testRandomMovesKeepEverythingClosed` (eigenschap over de dagboekhouding) |
| `GoalPotsTests` (D4) | de acht gevallen van `GoalPotsProofTests` (som van saldi en inleg, gelijk aan een doel met eigen waarden, één pot is byte-gelijk, oudere app ziet de eerste pot, een pot verwijderen, een pot voor meer doelen, `setFundingPots` normaliseert, versnellers bieden de potten van het doel niet aan); nieuw: een versneller herstellen zet `morePotIDs` terug; een doel met een pot zonder `morePotIDs` rondreist byte-gelijk |
| `DistributionTextTests`, `PotMoveTextTests`, `GoalPotsTextTests` | de gevallen van `DistributionTextProofTests` en `TextProofTests`; nieuw: `TransferPartsText.beforeStartNote`, `DistributeText.transferCaption` en `ContributionInfo` met delen en extra bedrag, `TransferPartsDraft.displayed` (een rij met bedrag 0 blijft staan), `TransferPartsText.standardParts`, `ContributionPreview.resolve(extra:)` |
| `DistributionPersistenceTests` | `VerdelenLegacyOutput` (byte-gelijk aan HEAD), rondreis van elke nieuwe sleutel via `FinanceStorage` en `BackupService`, een onleesbaar deel wordt overgeslagen, `hasContent`/`isEmptyStart` met een bankdeel, `withoutMarketData` laat de nieuwe velden staan |
| `PageCatalogTests`, `SearchIndexTests` | `testTheNewTermsOfRound2AreThere` (de termen, het zoeken, 19 pagina's; de controle dat `.wageChange` geen eigen zoekregel heeft voegt `G2V2` toe, want die bestemming bestaat pas in fase 2). Bewuste wijziging: `SearchIndexTests.testMultiWordQueryNeedsEveryWord` gebruikt "nog rente" in plaats van "nog bankrekening" als vraag zonder uitkomst (Verdelen heeft nu de term "bankrekening") |
| Eigenschapstests | `ledgerScenario` krijgt een zesde reeks (zaad + 41_000) AAN HET EIND met de kenmerken "percentage met extra bedrag", "extra overschrijfdagen (ook per maand)", "bankdeel", "opnemen of storten met bestemming"; `LedgerConsistencyTests` (200 zaadwaarden, 1200 met de omgevingsvariabele) en `StartDayPropertyTests` krijgen het orakel van `referenceTransferSlices` (gewone lussen zonder `TransferMath`), `toBank` zonder dagfilter en de dekkingscontroles: minstens 8 datasets per kenmerk (de referentie haalt in de eerste 200: 87 percentage met extra, 91 extra overschrijfdata waarvan 67 per maand, 95 bankdeel, 62 verplaatsingen met bestemming, 384 pot-maanden met gesplitste overschrijvingen, 806 maanden met een extra bedrag) |

**V2 (met `G2V2`; minstens het aantal na fase 1 plus 120 groen in totaal, dus 2160 bij 2040 na fase 1):**

| Bestand | Gevallen |
|---|---|
| `WageHistoryTests` (D6) | `testWithoutChangesEverythingIsAsBefore`, `testANewHourlyRateFromNovember`, `testAFixedAmountAndHoursChange`, `testTheNewestChangeInEffectWins`, `testTheWageOfThePayoutMonthDecides`, `testAnOwnSalaryOrOwnHoursOfAMonthStillApply`, `testEstimatesUseTheWageOfTheEstimatedMonth`, `testFreezingTheHistoryUsesTheWageOfEachMonth`, `testSetWageKeepsThePastWithoutWritingOverrides`, `testSetWageOnFreshDataEditsTheBase`, `testNonsenseAmountsAreNotKept`, `testRemovingAChangeRestoresThePreviousWage`, `testAWageChangeInTheStartMonthOfAStartDate`, `testWithoutChangesTheFileIsIdentical`, `testAnUnreadableChangeIsSkippedAndTheRestStays`; nieuw: een wijziging vóór de startmaand; twee wijzigingen in dezelfde maand vervangen elkaar; de Aankoopcheck, parttime-doelen en de versneller "Werk 2 uur extra" rekenen met het loon van de lopende maand |
| `WageCalendarTests` | de uren uit de agenda (golf 2 van `plan.md`) over een loonwijziging heen: een periode 24 oktober t/m 20 november met uitbetaling op 25 november rekent helemaal met het loon van november; een uitbetaling op de 1e van een maand rekent met die maand; met `hoursOverride` en met `salaryOverride` in dezelfde maand |
| `WagePayoutPropertyTests` | `testPayoutsMatchAnIndependentCalculationOnRandomDatasets` (300 datasets: wijzigingen per maand, schema om de zoveel weken of dagen, eigen salaris of eigen uren, startdatum; `referenceSalarySettings`, `referenceSalaryPayouts`) en het dagboek sluit; de reeks zaad + 47_000 in `ledgerScenario` (AAN HET EIND, na + 41_000 van V1 en + 37_000 van golf 2) met de kenmerken "loon per maand" en "loon vanaf de lopende maand" |
| `WageTextTests`, `WageEditTests` | `WageText` (rijen, basisregel, effectregel, verwijdertekst, lege staat, maand in het verleden); `WageEdit.start`, `change` (een gelijk veld blijft nil), `payoutPreview` |
| `NavigationRulesTests`, `SearchIndexTests` | `NavigationTestSupport` (`allDestinations()`, `ordinal` met `caseCount` 24, `expectedParents`) en `requiresPageEntry` kennen `.wageChange`; de bestaande padtests lopen er vanzelf overheen (onder `[.income, .salary]`, nooit een herhaling in het pad) |
| golf 2 van `plan.md` | de tests van 3.5 daar (minstens 80) |

**V3A:** `V3A/BankShareDisplayTests` en de uitbreiding van `StackedBarModelTests` en `CashflowDisplayTests` (minstens 12 gevallen: de zin en `detailRows` van een huidige en een verwachte maand met een bankdeel, het verleden zonder, `BankFlowFigures` met `toBank`/`left(current:)`, de tekst van `DayBalanceRows`, de meldingen "Over op je rekening"). Bewuste wijziging van twee bestaande verwachtingen in `CashflowDisplayTests` (regels 259 en 260): de meldingen heten voortaan "Over op je rekening:" en "Over op je rekening op de laatste dag:". **V3B** en **G3A/G3BV3C:** geen eigen Core-tests; hun logica staat in de hulpen van V1 en V2.

**Randgevallen die minstens één test noemt** (vink af bij "klaar"): dag 31 in een korte maand en februari (28 en 29), een extra datum vóór de startdatum, een extra datum op de standaarddag, delen die samen meer zijn dan de inleg, percentage 0 met een extra bedrag, een extra bedrag zonder inkomen, een bankrij groter dan wat er over is, een bestemmingspot die later wordt verwijderd, een pot als bestemming en als bron (beide richtingen), een doel met een verwijderde pot, een loonwijziging in de maand van de startdatum, een loonwijziging met een eigen salaris van die maand, uren uit de agenda over een loonwijziging heen, `CloudSync`, `Export`, `ImportMapping` en `BackupService` ongebroken (de bestaande tests blijven groen).

### 6.3 Roosterwachters (grep-poorten: `docs/work/verdelen-check.sh <fase>`)

Eén bron per grootheid (A3 in par. 1). Gebruik `verdelen-check.sh <fase> [onderdeel]`: `1`, `2 core` (`G2V2`), `2 maandcijfers` (`V3A`) en `3` (alles; ook B in `App/Pages` en `App/UI`). Een Python-script in de stijl van `start-check.sh` (`// reden`-schema; tekst tussen aanhalingstekens telt niet, wat in een `\( … )` staat wel); de referentie staat in `ref-verdelen/tools/verdelen-check.sh` en geeft de plaats van elke treffer:
- **A (fase 2 en 3): "Nog te verdelen" komt uit één functie.** In `App/Pages` en `App/UI` staat de eigenschap `.remaining` (van `MonthFigures`, `MonthBoard`, `MonthSummary`, `PeriodSummary`, `MonthLedger`) alleen op een regel met `// remaining: <reden>` (bijvoorbeeld de staaf die op het inkomen sluit, het gemiddelde "overgehouden", de controle van het dagboek); uitgezonderd `MoneyFigures.swift`. Een bestand met `MoneyLabels.remaining` of `remainingLabel(` bevat ook `MoneyLabels.left(` of `.left(current:`.
- **B (fase 2: `App/Core`; fase 3: ook `App/Pages` en `App/UI`): het loon komt uit één functie.** `salary.hourlyRate`, `salary.fixedMonthly`, `salary.hoursPerWeek`, `salary.monthlyAmount(`, `salary.payoutAmount(`, `salary.averageMonthly`, `salary.defaultMonthlyHours`, `salary.hoursPerCycle` en `salary.exactHourlyPay` staan niet buiten `Models.swift`, `WageHistory.swift`, `SalarySchedule.swift` en `SampleData.swift` tenzij de regel `// wage: <reden>` heeft; het schema (`isMonthly`, `payDay`, `schedule`, `anchor`, `mode`) mag overal.
- **C (vanaf fase 1): de dagen van een inleg komen uit één functie.** `DayEvents.swift`, `Pots.swift` en `Invest.swift` bevatten `TransferMath.slices(` en `Transfers.swift` bevat `countedTransferCents`; `DayEvents.swift` roept `allocationCents(` niet aan (alleen `allocationTotalCents(`); `enum GoalFunding` heeft precies de gevallen `portfolio`, `pot` en `custom`.
- **D (vanaf fase 1): de proefregels van golf 1 blijven.** `start-check.sh` PASS (de nieuwe bestanden lezen `bankEntries`, `bankSnapshots` en `potEntries` niet ruw).
Het script faalt met exit 1 bij een treffer en meldt per fase hoeveel plekken een reden hebben (zoals `start-check.sh --list`).

## 7. Risico's en open punten voor de gebruiker

### 7.1 Risico's en eerlijke beperkingen

| # | Risico | Aanpak |
|---|---|---|
| 1 | **Oudere appversies op andere apparaten** kennen de nieuwe sleutels niet, laten ze weg bij opslaan en rekenen zonder: een percentage zonder extra bedrag, geen bankrij, geen extra overschrijfdata, geen loonwijzigingen. Via de synchronisatie kan zo een oude versie het bestand van een nieuwe versie terugzetten zonder deze velden. Alleen een doel met meer potten blijft leesbaar (als doel met de eerste pot). | Alle apparaten bijwerken; de nieuwe velden worden alleen geschreven als ze iets zeggen, dus wie ze niet gebruikt merkt niets; `GoalFunding` krijgt geen nieuw geval (anders weigert een oude app het hele bestand). |
| 2 | **Geen toestel en geen Xcode hier.** De Core is volledig getest (Swift 6.0.3 op Linux, 2053 tests in de referentie); de schermen zijn alleen typegecontroleerd tegen nagemaakte frameworks. Niet te zien: hoe `DisclosureGroup`, een menu-`Picker` in een `Form`, de nieuwe tegels en de grafiek met bankdeel eruitzien en voelen, VoiceOver, de Mac-pane. | Dunne schermen, logica in testbare hulpen (3.5), previews en de CI van de coördinator (iOS, macOS, screenshots); de handmatige lijst van 6.1. |
| 3 | **De betekenis van de bankrekening (D3) is de meest dubbelzinnige keuze** (zie 7.2, punt 1). Gekozen is de lezing die niets aan saldo's, dagboek en bestaande getallen verandert. | De keuze is geïsoleerd (2.3: `BankShare.swift`, `MonthFigures.unassigned`, `MoneyLabels.left`, `planEvents`); een andere lezing is een kleine omzetting. |
| 4 | **"Nog te verdelen" heeft nu twee getallen.** Met een bankdeel verschilt wat er op de rekening blijft (`remaining`: Overgehouden, het dagboek, de export) van wat nog niet is toegewezen (`unassigned`: Nog te verdelen, Aankoopcheck, Noodbuffer, Versnellers). Zonder bankdeel zijn ze gelijk. | Eén functie kiest het getal bij het label (`MoneyLabels.left`), twee roosterwachters (6.3, A en B) en teksten die het bankdeel noemen; de Dag-voor-dag-regel zegt wat er is toegewezen. |
| 5 | **Het loon van een maand (D6) is een keuze** (7.2, punt 2). Een wijziging in het verleden verandert ook al voorbije maanden (de pagina waarschuwt). | `salarySettings(forPayoutOn:)` is de ene plek; `setWage` legt voor de standaardkaart het verleden niet vast maar maakt een wijziging vanaf de lopende maand. |
| 6 | **Een gewijzigd loon op de standaardkaart werkt anders dan vroeger**: eerder legde elke wijziging het verleden vast als eigen salaris per maand (`SalaryScheduleEdit.edit`); nu ontstaat vanaf het eerste salaris een rij bij "Loon per maand". Het zichtbare resultaat is gelijk (eerdere maanden houden hun loon), de opslag niet. | Alleen het bedrag gaat via `setWage`; het schema (soort, salarisdag, interval, anker) blijft `SalaryScheduleEdit`. `freezeSalaryHistory` blijft werken (het rekent via `salaryCents`). |
| 7 | **Delen zijn vaste bedragen**, geen aandelen of percentages: gaat de inleg van een maand omlaag (percentage, lager salaris), dan worden de laatste delen afgekapt en blijft er niets voor de standaarddag over (een waarschuwing meldt het). | Gekozen voor uitlegbaarheid; `TransferMath.overflowCents` voedt de waarschuwing. |
| 8 | **Een pot die meer doelen voedt telt voor elk doel helemaal mee** (geen verdeelsleutel), en versnellers werken alleen op de eerste pot van een doel. | De pagina's zeggen het (`GoalPotsText`); een verdeelsleutel is een latere uitbreiding. |
| 9 | **Opnemen naar een andere pot of de bank controleert het saldo van de bestemming niet; storten uit de bank controleert het banksaldo niet** (zoals nu). Bij een onbekend banksaldo begint de boeking het saldo. | `PotMoveText.bankUnknownNote`; `canSave` houdt het saldo van de bronpot bij. |
| 10 | **Prestaties:** meer gebeurtenissen per pot en maand (hoogstens 13 per pot). Gemeten op de zware testset van `ledgerPerformanceData` (10 potten en 8 beleggingen, 5 jaar): `monthLedger` mediaan 11 ms (13 ms met percentages) zonder delen, zoals voor de wijziging; met het maximum van 12 extra overschrijfdata op ALLE 18 potten en beleggingen 31 ms (34 ms met percentages, maximum 48 ms). Normaal gebruik (0 tot 2 delen) merkt niets. | De grens van 12 delen (`TransferMath.maxParts`); `PerfProbeTests` in `ref-verdelen/tests/` is een meetinstrument, geen blijvende test; de bestaande prestatietests blijven groen. |
| 11 | **Fase 2 is het enige moment met drie bouwers in één werkboom**: een half werkende Core kan de typecontrole van een ander breken. | Het bouwrecept van 5 (V3A en V3B in een eigen kopie; `G2V2` houdt de Core compileerbaar). |
| 12 | **De referentiecode is een bewijs, geen afgewerkt product**: zij is geschreven tegen de stand van golf 1, de teksten zijn gevoelig voor de termenlijst en de schermen (4) zijn niet in de proef gebouwd. | Het contract (3) en de tests (6.2) zijn bindend, de referentie is optioneel over te nemen. |

### 7.2 Open punten voor de gebruiker (beslist, maar echt dubbelzinnig; wijzig de keuze zonder grote ombouw)

1. **De bankrekening in Verdelen (D3).** Gekozen: een rij die zegt "dit deel blijft op mijn rekening" en meetelt als verdeeld, zonder dat er geld beweegt (zo kan "Nog te verdelen" op 0 uitkomen). Bedoel je dat je salaris eerst op een andere rekening binnenkomt en je daar op bepaalde dagen een bedrag naar je bankrekening overmaakt (dus dat je saldo pas op die dag stijgt), dan is dat een andere lezing (Z2 in 2.3): die vraagt een tussenrekening en verandert het dagboek. Zeg het, dan wordt het die lezing; het blijft een kleine ombouw in `BankShare.swift`, `planEvents` en het dagboek.
2. **Welk loon geldt voor een uitbetaling (D6).** Gekozen: het loon van de maand waarin het geld op je rekening komt. Heb je vanaf 1 november een nieuw uurloon en wordt het salaris over oktober pas op 25 november betaald, dan rekent die uitbetaling met het loon van november. Bedoel je het loon van de gewerkte dagen, dan verandert alleen `salarySettings(forPayoutOn:)`.
3. **"Spaardoelen" (D4)** zijn de doelen van de pagina Doelen (pensioen, vakantie, parttime, eigen doel). De rekenpagina "Spaardoel berekenen" gebruikt geen spaarpotten en blijft zoals ze is. Een pot die twee doelen voedt telt voor elk doel helemaal mee.
4. **Extra overschrijfdata (D2)** zijn vaste bedragen op een eigen dag van de maand (1 t/m 31, in een korte maand de laatste dag), naast de standaarddag die je salarisdag of de eigen dag van de pot is. Een deel als percentage, of een dag die "n dagen na je salaris" is, is niet gebouwd.
5. **Opnemen en storten (D5):** de standaardkeuze blijft "Nergens (uit je overzicht)" (zoals vroeger de schakelaar uit); een bestemming kies je erbij. Wil je dat Opnemen standaard naar de bankrekening gaat, dan is dat één standaardwaarde in het blad.
6. **Extra bedrag (D1)** werkt alleen bij de inlegwijze Percentage (bij een vast bedrag is dat bedrag al het totaal) en geldt elke maand; je kunt het per maand afwijkend instellen.
7. **Aankoopcheck, Noodbuffer en Versnellers** rekenen met wat er nog niet is toegewezen ("Nog te verdelen"), dus het bankdeel telt daar niet als vrije ruimte; zonder bankrij verandert er niets.

## 8. Samenvatting (maximaal 30 regels)

1. Zes wensen in één ronde op de stand van golf 1 (HEAD c0130b2): D1 percentage plus extra bedrag, D2 meerdere overschrijfdata, D3 de bankrekening in Verdelen, D4 een doel uit meer potten, D5 opnemen en storten met bestemming, D6 loon per maand. Bewijs: referentiecode en proeftests in `/tmp/arch-probe2/ref-verdelen/`; alle 2053 tests groen (1957 bestaande), typecontrole 0 fouten in alle varianten, `start-check.sh` PASS.
2. **D1:** `PercentRule.extra` en `Pot/Holding.contributionExtra`; het bedrag is percentage plus extra, op hele centen, in ÉÉN functie (`AllocationMath.cents(of:bases:)`); zonder inkomen blijft het extra bedrag over.
3. **D2:** een `TransferPart(dag, bedrag)` wordt uit de inleg van de maand gehaald, de rest gaat op de standaarddag; `TransferMath.slices` is de enige plek die dagen verdeelt; elk stuk is een eigen gebeurtenis en beweegt pas op zijn dag (bank, pot, belegging, dagboek); standaard en per maand, het verleden blijft staan, met een startdatum telt elk stuk apart.
4. **D3 (de keuze):** de bankrij is een **toewijzing zonder beweging**: `remaining` blijft wat er op de rekening blijft, `unassigned = remaining − toBank` is het getal bij "Nog te verdelen" (via `MoneyLabels.left`); "Rest naar bankrekening" brengt het op 0. Bewezen: met en zonder bankdeel zijn banksaldo, potsaldo en dagboek van elke dag gelijk. Afgewezen: Z2 (tijdinstrument, breekt het dagboek) en Z3 (vaste overboeking pot naar bank). Geïsoleerd in `BankShare.swift`.
5. **D4:** `.pot(eerste)` plus `LifeGoal.morePotIDs` (geen nieuw enum-geval: een oudere app ziet de eerste pot); saldo en inleg van alle potten tellen op; een pot verwijderen laat de rest staan.
6. **D5:** `MoneyEnd` en `withdraw`/`deposit` bovenop de bestaande gekoppelde boekingen; standaard blijft "Nergens (uit je overzicht)", Bankrekening en andere pot komen echt aan.
7. **D6 (de datumregel):** `FinanceData.salaryChanges`; het loon van een uitbetaling is dat van de **maand waarin ze op je rekening komt** (`salarySettings(forPayoutOn:)`, één plek); `setWage` maakt vanaf de lopende maand een wijziging zonder het verleden vast te leggen; zonder wijzigingen byte-gelijk.
8. **Opslag:** nieuwe sleutels alleen als ze iets zeggen, mild gelezen; een bestand zonder deze functies codeert byte voor byte als voorheen.
9. **UI:** geen nieuw blad (`.sheet(` blijft 14); uitbreidingen van Verdelen (extra bedrag, extra overschrijfdagen, kaart Bankrekening, menu), de bladen van pot, belegging en doel, Opnemen met één bestemmingskeuze en Salaris met "Loon per maand"; één nieuwe pagina `WageChangePage`.
10. **Pakketten:** V1 (Core D1 t/m D5) → tegelijk `G2V2` (werkuren-Core van `plan.md` en loon-Core), `V3A` (Verdelen en maandcijfers), `V3B` (pot, opnemen, doelen) → tegelijk `G3A` (agenda) en `G3BV3C` (Salaris en Loon per maand). Zes bouwers; eigendom per fase in het blok van par. 5, `own-check2.sh`.
11. **Poorten:** `run-all.sh` 0 fouten, `swift test` (V1 ≥ 2040, daarna +120), `design-checks.sh`, `start-check.sh`, `verdelen-check.sh` (één bron per grootheid), `contract-check2.sh`, `own-check2.sh`, CI.
12. **Beperkingen:** geen toestel en geen Xcode hier; de lezing van D3 en de loonmaand van D6 zijn keuzes (7.2); oudere apps laten de nieuwe velden weg.
