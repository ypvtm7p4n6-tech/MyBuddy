# MyBuddy: startdatum, uren uit je agenda en toeslagen (bouwplan)

Peildatum 27 oktober 2026, basis `HEAD` b944e43 (ontwerp 2 gebouwd en goedgekeurd). Uitvoerbaar bouwplan voor twee wensen: (1) werkuren uit de iCloud-agenda "werken" (gewerkt en gepland) met toeslagen (zondag keer 1,5, feestdag keer 2) en pauzeregels; (2) een startdatum waarop "alles pas begint". Er is niets in `App/`, `CoreTests/` of `Tests/` aangepast; alleen dit plan en proefbestanden in `/tmp/arch-probe/`.

**Bewijs (27 okt., proefkopie van `App/`; referentiecode, tests en `core-edits-vs-HEAD.diff` in `/tmp/arch-probe/ref-werkuren/`; de bouwer neemt over of schrijft opnieuw).**
- Basislijn: `swift test` 1848 tests (10 overgeslagen: live netwerk) groen; `run-all.sh` 0 fouten.
- Startdatum: met de plekken van 2.2 blijven alle 1848 tests groen (zonder `startDay` rekent alles identiek). Een eigenschapstest over 1500 datasets (16.517 maanden, 582 met een deelmaand) bewijst: het dagboek sluit (bank, potten, overzicht), maanden na de start zijn gelijk aan startdag 1, de startmaand is startdag 1 min wat ervoor valt, vóór de start geen banksaldo en geen potsaldo. Het eerste prototype gaf 28 afwijkingen doordat de standaard-salarisdag met de startdag meeschoof: vandaar B4.
- Werkuren: Pasen (Meeus/Jones/Butcher) klopt met `dateutil` voor 301 jaren; de 25-uurs en 23-uursdag splitsen goed met `Calendar` op Linux (`Europe/Amsterdam`); een eigenschapstest over 600 datasets (6.605 maanden, 3.155 uitbetalingen uit de agenda, 248 gemengd met het gemiddelde, 4.101 helemaal verwacht) sluit en het rapport van een uitbetaling is gelijk aan haar bedrag.
- EventKit: stub met Apple's handtekeningen (documentatie-JSON), adapter en controller typechecken in `run-all.sh` (iOS en macOS, debug en release) met 0 fouten. Apple's Build Settings Reference kent `ENABLE_RESOURCE_ACCESS_CALENDARS` ("enables read-write access to the user's calendar") en `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`.

## 1. Besluiten (bindend; geen vragen)

| # | Besluit | Reden |
|---|---|---|
| B1 | **Startdatum = `FinanceData.startDay: CalendarDay?`** (opgeslagen als "2026-11-03"); `startDate: Date?` is afgeleid (12:00, voor datumkiezers). `startMonth` blijft opgeslagen en is altijd de maand van `startDay` (`setStart(_:)`). | Een dag zonder tijdzone verschuift niet tussen apparaten (zoals het salarisanker); ruim 120 aanroepen van `startMonth` en het back-upformaat blijven werken. |
| B2 | Zonder `startDay` rekent alles precies als nu (ook met boekingen van vóór de startmaand). Met `startDay` telt wat ervoor valt niet; het blijft bewaard. | "Oude data blijft identiek": bewezen met de 1848 tests. |
| B3 | Eén primitief `firstCountedDay(in:)`. Geplande dingen: `counts(day:in:)`. Handmatige boekingen en saldi: `countedBankEntries`, `countedPotEntries`, `countedBankSnapshots` (grens: begin van de startdag). Een grep-poort bewaakt de ruwe lijsten. | Elke plek die zelf een som of dag uitrekent moet hetzelfde filter gebruiken, anders sluit het dagboek niet. |
| B4 | De standaard-salarisdag (`salaryDay(in:)`, `salaryPayDays(in:)`) en overschrijfdagen volgen het SCHEMA, niet de startdag. Valt zo'n dag vóór de start, dan telt die inkomst of inleg niet mee: wat toen gebeurde zit in je beginsaldo. | Bewezen met de eigenschapstest. |
| B5 | Startmaand: een eigen salaris of eigen uren is het totaal dat telt, gelijk verdeeld over de uitbetalingen vanaf de startdag; een inleg als percentage rekent over het inkomen dat meetelt. | Uitlegbaar: wat je invult is wat meetelt. |
| B6 | Schattingen (buffer, aankoopcheck, versnellers, doelen, toekomstschatting) rekenen met een HELE startmaand (`forEstimates`). | Anders onderschat je in je eerste maand inkomen en uitgaven. |
| B7 | Beleggingen: waarde-updates blijven (een eigen tijdlijn van een externe rekening); alleen hun inleg volgt de regel. Rente heeft geen eigen regel nodig (saldo op de 1e is 0). | Eén plek per begrip. |
| B8 | UI: subpagina `.settings(.startDate)` "Startdatum" van Gegevens (eerste rij; op de Mac een push in de pane Gegevens), een pil "Beginnen op een datum" op de lege start van Home, vindbaar via Zoeken. Keuzes: "Alleen de startdatum instellen" of "Alles wissen en opnieuw beginnen vanaf deze datum" (bevestiging); daarna "Beginsaldo op <datum>" voor bank en potten. | Pagina's, geen sheets; geen pane voor iets dat je eenmaal doet. |
| B9 | Werkuren-instellingen in `FinanceData.work: WorkSettings` (bron, agendanaam, periode, regels, afgeleide diensten), niet in `SalarySettings`. Regels of bron wijzigen legt het verleden NIET vast (anders stem je niet af op je loonstrook); "Eerdere maanden vastleggen" doet dat expliciet (`freezeSalaryHistory`). Een nieuw uurloon blijft via `SalaryScheduleEdit` (legt het verleden vast). | Gewerkte uren van het verleden tellen mee; een verhoging verandert het verleden niet. |
| B10 | Diensten: alleen `[beginminuut, eindminuut]` (minuten sinds 1970) in `WorkSnapshot`, met het opgehaalde venster en de dag van de laatste verversing; nooit titel, notitie, plaats of deelnemer. Overlap wordt samengevoegd. | Privacy; ± 25 bytes per dienst. |
| B11 | Periode van een uitbetaling. Maandelijks: de kalendermaand van de uitbetaling ("deze") of de maand ervoor ("vorige"). Om de N weken of dagen: de 7N (of N) dagen die OP de uitbetaaldag eindigen ("deze") of de periode daarvoor. Instelling "Uren van": Deze periode / De vorige periode (standaard deze). | Perioden sluiten aan; de pagina toont de datums. |
| B12 | Terugval: dagen NA de laatste dienst én na de dag van de laatste verversing rekenen met de handmatige uren (`hoursPerCycle`), naar verhouding van het aantal dagen; een periode helemaal in dat gebied geeft exact het handmatige bedrag (`payoutAmount()`). Het bedrag hangt nooit van de klok af. | Een rooster is maar weken vooruit bekend; geen gat in je prognose. |
| B13 | Rekenen: dienst per kalenderdag gesplitst met `Calendar` (dagen van 23 en 25 uur), onbetaalde pauze uit de tabel naar de duur van de HELE dienst en evenredig verdeeld (grootste rest), factor per dag (hoogste wint; instelbaar op optellen), bedrag = uurloon × (minuten × factor) / 60, eenmaal op hele centen (half omhoog, exact in decimalen). | Als `exactHourlyPay`. |
| B14 | Feestdagen uitgerekend, elk met een schakelaar: standaard aan Nieuwjaarsdag, Eerste en Tweede Paasdag, Koningsdag, Hemelvaartsdag, Eerste en Tweede Pinksterdag, Eerste en Tweede Kerstdag; standaard uit Goede Vrijdag, Bevrijdingsdag, Oudejaarsdag (hele dag); plus eigen datums. Standaard toeslagen "Zondag 1,5" en "Feestdag 2,0" (aanpasbaar, uitzetbaar); pauzetabel "vanaf 5,5 uur 30 min" (rijen toevoegen kan). | Wat de gebruiker noemde. |
| B15 | Agenda op NAAM (standaard "werken", hoofdletter- en accentongevoelig, alle agenda's met die naam); lijst om een andere te kiezen. Hele-dag-afspraken: genegeerd, of "tellen als N uur" (pauzeregels gelden). Afgewezen, geannuleerde en afspraken van meer dan 16 uur tellen niet. | Identifiers verschillen per apparaat. |
| B16 | EventKit staat alleen in `App/Calendar/EventKitWorkCalendar.swift` (actor) achter het Foundation-only protocol `WorkCalendarSource` (`App/Core`, testbaar met een nagemaakte agenda). `WorkCalendarController` (@MainActor @Observable) staat op `MyBuddyApp`, zoals `auth` en `cloud`. | De rekenmotor hangt nooit van EventKit af. |
| B17 | Verversen alleen bij bron "agenda" en alleen als nodig (nieuwe dag, ander venster, andere naam): bij het actief worden van de app, bij `EKEventStoreChanged` (2 s gedempt) en met "Nu verversen". Toestemming vragen gebeurt alleen na een tik van de gebruiker. | Geen vraag bij het opstarten. |
| B18 | **Geen betaald Apple-account nodig voor EventKit**: iOS vraagt alleen de plist-sleutel, macOS alleen het sandbox-entitlement `com.apple.security.personal-information.calendars` (geen aanvraag of provisioning). Wel nodig voor TestFlight en App Store, los van EventKit. | Apple-documentatie. |
| B19 | Entitlement via build setting `ENABLE_RESOURCE_ACCESS_CALENDARS: YES` naast de bestaande `ENABLE_APP_SANDBOX`, `ENABLE_USER_SELECTED_FILES` en `ENABLE_OUTGOING_NETWORK_CONNECTIONS` (zelfde mechanisme, geen `CODE_SIGN_ENTITLEMENTS`-bestand dat de rest kan verdringen). Terugval: zie 4.2. | Eén regel, niets bestaands verandert. |
| B20 | Synchroniseren: `CloudSync.withoutMarketData` laat `work.snapshot` weg (net als koersen): twee apparaten die tegelijk verversen geven geen conflict. Een snapshot-wijziging van één kant gaat gewoon mee. | Bestaand patroon. |
| B21 | Pagina "Werkuren" (`SettingsPage.workHours`) in de groep Rekenen (Rekenen, Werkuren, Koersen); op de Mac een zevende pane. | Het gaat over hoe cijfers worden uitgerekend. |
| B22 | Niet in deze ronde: tijdvensters (avond, nacht), cao-specifieke regels, meer agenda's met eigen regels, bruto-netto, werkgeverskosten. | Dagregels dekken de vraag. |

## 2. Startdatum (golf 1, één bouwer)

### 2.1 Wat telt (R1 t/m R8)

R1 **Gepland** telt alleen als de dag op of na de startdag valt: salaris (uitbetalingen), extra inkomsten (eigen dag, anders de salarisdag van de maand), uitgaven (eigen dag, anders de 1e), inleg (overschrijfdag), rente. Maanden vóór de startmaand: niets (zoals nu). R2 **Handmatig** (bank- en potboekingen, ingevulde banksaldi) van vóór het begin van de startdag telt niet en blijft bewaard (een eerdere startdatum brengt ze terug). R3 De startmaand is een deelmaand: `monthFigures`, `expenseOverview`, `salaryAmount`, de gebeurtenissen en `MonthLedger` tellen alleen vanaf de startdag; `allReconciles` blijft waar. R4 Vóór de startdag is het banksaldo onbekend (nil) en zijn potten 0; een beginsaldo is gewoon een ingevuld saldo en `.opening`-boekingen op de startdag. R5 Salaris om de zoveel weken of dagen: uitbetalingen vanaf de startdag; `setStart` zet een impliciet anker (payDay van de startmaand) eerst vast zodat uitbetalingen niet verschuiven; `nextPayDate(after:)` nooit vóór de startdag. R6 Overschrijving en percentage: B5. R7 Rente: geen code, wel een test (geen uitbetaling in de startmaand vóór de startdag). R8 Een startdatum is geen "gegevens": `isEmptyStart` en `hasContent` negeren hem.

### 2.2 Plekken (alles wat nu `startMonth` als grens gebruikt, of ruwe boekingen leest)

| Bestand | Wijziging |
|---|---|
| `Core/StartDate.swift` (nieuw) | `effectiveStartDay` (alleen als in `startMonth`), `firstDay`, `startDate`, `firstCountedDay(in:)` (1 / startdag / `Int.max`), `counts(day:in:)`, `transferCounts(_:in:)`, `startCutoff`, `countedBankEntries/countedPotEntries/countedBankSnapshots` (zonder startdag: de ruwe lijst, geen kopie), `entriesBefore(_:)`, `setStart(_:)`, `forEstimates`, `setOpeningBalances(on:bank:pots:)` (idempotent: vervangt "Beginsaldo"-saldo en `.opening`-boekingen van die dag). Referentie: `ref-werkuren/core/StartDate.swift`. |
| `Core/Models.swift` | `startDay` + sleutel; lenient decoderen (onleesbare dag: genegeerd; dag buiten `startMonth`: `startMonth` volgt de dag); EIGEN `encode(to:)` met dezelfde sleutels als nu en `startDay` alleen als gezet (oude data byte-gelijk; stap 0: leg de uitvoer van de HUIDIGE encoder vast als testfixture). |
| `Core/SalarySchedule.swift` | `salaryPayoutCents` (maandelijks: salarisdag < startdag: geen uitbetaling; weken/dagen: dagen filteren; terugvaldag ook), `salaryCents` (maandelijks via de uitbetalingen als `firstCountedDay > 1`), `scheduledSalary`, `salaryHours` (via nieuw `countedSalaryPayDays(in:)`), `nextPayDate`. `salaryPayDays(in:)` en `salaryDay(in:)` blijven het schema volgen (B4). `estimated*` (5 functies): guard `if firstCountedDay(in: month) > 1, month >= startMonth { return forEstimates.<zelfde>() }`. |
| `Core/Plan.swift` | `monthFigures(of:...)`: inkomstenregels op `incomeDay(of:in:)`, uitgaven op `expenseDay(of:)`; `extraIncomeTotal`; `allocation(_:in:)` met `transferCounts`. |
| `Core/Allocation.swift` | `incomeBases(of:in:)` (regels), `allocationCents` (alle drie de vormen) en `effectiveAllocation(...).amount` via `transferCounts`. |
| `Core/DayEvents.swift` | `planEvents.add(...)` weigert dagen < grens; `bankEntryEvents` en rente-boekingen uit `counted*`. |
| `Core/Expenses.swift`, `Core/Interest.swift` | `expenseOverview` filtert regels; opgeslagen rente via `countedPotEntries`. |
| `Core/Bank.swift`, `Core/Ledger.swift` | `BankTimeline` (`startMonth(for:)`, init, handmatige boekingen), `sortedBankSnapshots`, `hasBankBalance` en de lussen in `monthLedger` lezen `counted*`; `averageMonthlyExpenses` rekent met `forEstimates`. |
| `Core/Pots.swift` | `potLedgers` en `potTimeline`: boekingen via `countedPotEntries`, potdelen van uitgaven alleen als `counts(day: expenseDay(of:))`; `addPot(openingBalance:now:)`: een beginsaldo vóór de startdag komt op de startdag. |
| `Core/Buffer.swift` (2x), `Pages/BufferPages.swift` (1x) | `data.forEstimates.expenseOverview(in:)`. |
| `AppStore.swift` | `setStart(_:)` (mutate + `materialize(upTo: now)`), `eraseEverything(startingOn:)` (nieuwe `FinanceData` met de startdag; account blijft, het wissen van `AccountPrefs` blijft in de aanroeper, gedeeld met `DataPage`), `setOpeningBalances`. |
| `Core/Formatting.swift` | `Fmt.longDate(CalendarDay)` ("3 november 2026"). |
| Volgt vanzelf | `MonthBoard`, `PeriodSummary`, `summaries`, `netWorth*`, `bankBalance*`, `potBalance*`, `applyDueInterest` lezen de bronnen hierboven. |
| Niet aanraken | `Export.swift` (CSV-transacties blijven alle boekingen), `Accelerators.swift`, `ImportMapping.swift`, `Invest.swift`; de 286 plekken in `CoreTests` die `startMonth` gebruiken blijven zoals ze zijn. |

Poort: `docs/work/start-check.sh` (nieuw, grep): in `App/` mag een LUS of bewerking over `bankEntries`, `bankSnapshots` of `potEntries` (`in ...`, `.map`, `.filter`, `.sorted`, `.min`, `.max`, `.reduce`, `.enumerated`, `.last`) alleen met het commentaar `// raw: <reden>` op dezelfde regel (overboekingen verwijderen, zoeken op id, export, back-up); `Models.swift`, `StartDate.swift`, `Accelerators.swift`, `Export.swift`, `CloudSync.swift`, `Overview.swift` en `HomePreviews.swift` zijn uitgezonderd. Elke andere treffer is een fout.

### 2.3 UI

- **`Pages/Settings/StartDatePage.swift`** (`ListScaffold`, titel "Startdatum", `SettingsPage.startDate`, symbool `calendar.badge.plus`, ouder `.data`). Secties: (1) uitleg-voetnoot "Alles begint op deze dag. Wat je daarvoor invulde telt niet mee, ook al blijft het bewaard."; (2) `DatePicker` ("Begin op", `.date`, 1 jan 2000 t/m vandaag + 1 jaar) en de huidige stand (`StartDateText.summary`); (3) "Wat verandert er?": aantallen vóór de gekozen dag (boekingen bank, boekingen potten, ingevulde saldi, maanden), live; (4) `Picker(.inline)`: "Alleen de startdatum instellen" / "Alles wissen en opnieuw beginnen vanaf deze datum"; (5) `ActionButton` "Startdatum instellen" (prominent; bij de tweede keuze rood, met `confirmationDialog` en de cloudwaarschuwing zoals `DataPage`); (6) "Beginsaldo op <datum>" (alleen met startdatum): `NumberRow` voor de bankrekening en elke spaarpot (beginwaarde: wat er die dag nu staat) en "Beginsaldo bewaren"; voetnoot "Het saldo op deze dag, met alles wat die dag al gebeurd is."
- `App/UI/StartDateText.swift` (Foundation-only, symlink in `CoreTests`): `summary`, `beforeStartNote`, `partialMonthNote(month)`, `warning(counts)`, `hiddenEntriesNote`, `eraseMessage(cloud:)`. Termen: "ingevulde saldi", nooit "meetpunt".
- `DataPage`: eerste sectie met `SettingsLinkRow(page: .startDate, title: "Startdatum", subtitle: StartDateText.summary(...))`. `HomeWelcome`: `PillButton("Beginnen op een datum", symbol: "calendar.badge.plus", style: .onTile) { router.go(.settings(.startDate)) }` naast "Salaris instellen"; bij een ingestelde startdatum een regel "Je begint op 3 november."
- Maandpagina's: de teksten "Maanden vóór je startmaand (…)" (`IncomePage`, `ExpensesPage`, `DistributePage`, `MoneyLines`, `LibraryFigures`, `MonthBoard`) worden `StartDateText.beforeStartNote`; in de startmaand een regel `partialMonthNote`; `MoneyLinesSection` toont regels vóór de startdag als "Telt niet mee (vóór je startdatum)" en telt ze niet in het totaal; `DistributePage` legt uit dat een inleg met een eerdere overschrijfdag niet meetelt.
- Boekingen: de lijsten (Bankrekening, spaarpot, Recent) tonen alleen wat meetelt (`BankHistoryItem.items`, `RecentActivity`, `PotDisplay` lezen `counted*`) met onderaan `hiddenEntriesNote` (link naar Startdatum); `BankActionSheet` en `PotEntrySheet` waarschuwen bij een datum vóór de startdatum.
- `NavigationModel.swift` (`.startDate`; `title` "Startdatum"; `parent` `.data`), `SettingsDestination`, `SearchIndex` (termen: beginnen, startdatum, begindatum, vanaf, opnieuw beginnen, eerste dag, beginsaldo), `DebugLaunch` (`startdate`).

### 2.4 Tests (golf 1, nieuwe bestanden met unieke namen; minimaal 1848 + 40)

`StartDateModelTests` (rondreis ook via `BackupService` en `FinanceStorage`, onleesbaar of afwijkend, oude fixture byte-gelijk, `setStart` en het vastgezette anker), `StartDateFiguresTests` (salaris maandelijks vóór en na de startdag, weken en dagen, uitgaven zonder dag, extra inkomsten, inleg met overschrijfdag vóór de start, percentage over deelinkomen, overschrijving verdeeld over de uitbetalingen vanaf de start, `scheduledSalary`, `salaryHours`, `nextPayDate`, `expenseOverview`), `StartDateLedgerTests` (boekingen en saldi vóór de start tellen niet en komen terug bij een eerdere startdatum, `bankBalance` nil en potsaldo 0 ervoor, `entriesBefore`, `setOpeningBalances` idempotent, rente en `applyDueInterest` in de startmaand), `StartDateEstimatesTests` (buffer, aankoopcheck, `estimatedRemaining`, `averageMonthlyExpenses` gelijk aan startdag 1), `StartDateTextTests`, `NavigationRulesTests` (11 pagina's), `SearchIndexTests`, `EmptyStartTests`. **Eigenschapstest** `StartDayPropertyTests`: referentie `ref-werkuren/tests/StartDayProofTests.swift`, 300 zaadwaarden (omgevingsvariabele voor meer), orakel via de gebeurtenissen van startdag 1; breid `ledgerScenario` uit met een vijfde reeks (zaad + 29_000) AAN HET EIND zodat bestaande zaadwaarden gelijk blijven (kenmerken "startdatum midden in de maand" en "boekingen vóór de start") en laat het orakel van het banksaldo in `LedgerTestSupport` boekingen en saldi vóór de startdag overslaan.

## 3. Werkuren in Core (golf 2, één bouwer; alles Foundation-only, `App/Core`)

### 3.1 Typen (referentie: `ref-werkuren/core/`)

- `WorkShift`: `startMinute`, `endMinute` (minuten sinds 1970), `init?(start:end:)` (op de minuut afgekapt, einde > begin), `durationMinutes`, opgeslagen als `[b, e]`, `normalized(_:)` (sorteren, dubbelen weg, overlap samenvoegen), `pieces(calendar:)` (per kalenderdag). `WorkMath.distribute(_:over:)` (grootste rest, bij gelijk het vroegste deel). `LossyArray<T>` (slaat onleesbare elementen over).
- `PayRuleKind` (`.weekday(1...7)` met 1 = zondag, `.holiday`, `.date(CalendarDay)`; opgeslagen als "weekday:1", "holiday", "date:2026-12-05"), `PayRule` (id, kind, factor 0...10, `isEnabled`), `BreakRule` (id, `fromHours`, `minutes`), `PayCombine` (`.highest` standaard, `.add`: 1 + som van (factor − 1)), `HolidayKind` (twaalf soorten, `standard` = de negen die aanstaan) en `HolidaySettings` (`enabled: Set<HolidayKind>`, `custom: [CalendarDay]`; schrijft alleen wat afwijkt), `WorkRules` (`payRules` met vaste id's voor "Zondag 1,5" en "Feestdag 2,0", `breakRules` met "vanaf 5,5 uur 30 min", `combine`, `holidays`; alleen afwijkingen worden geschreven; lenient per element).
- `DutchHolidays`: `easter(year:)` (Meeus/Jones/Butcher, formule in `ref-werkuren/core/WorkRules.swift`), `kingsDay(year:)` (27 april, zondag: 26 april; vóór 2014 "Koninginnedag" 30 april, zondag: 29 april), `day(of:year:)`, `holidays(year:settings:)`, `isHoliday(_:settings:)` (zonder lijst te bouwen: vaste datums plus `dag − Pasen` ∈ {−2, 0, 1, 39, 49, 50}).
- `HoursSource` (`.manual`, `.calendar`), `HoursPeriodBasis` (`.current`, `.previous`), `WorkSnapshot` (`shifts`, `from`, `through`, `fetchedDay`, `calendarTitle`), `WorkSettings` (`hoursSource`, `calendarTitle` "werken", `periodBasis`, `allDayShiftHours: Double?`, `rules`, `snapshot`; `hasUserContent` negeert de snapshot).
- `WorkPeriods.period(forPayoutOn:salary:basis:)` (B11), `WorkLedger` (per kalenderdag: betaalde minuten, pauzeminuten, gewogen minuten × factor in honderdsten, minuten per factor, aantal diensten; `total(_:)` over een dagbereik), `WorkHoursReport` (gewerkt, gepland, verwacht, pauze, per factor, aantal diensten, bedrag in centen), `SalarySettings.exactPayCents(rate:weightedMinutes100:)` (Decimal, half omhoog), `PayoutHours` (`paidMinutes`, `expectedMinutes`).
- `FinanceData`: `startDay` is van golf 1; golf 2 voegt `work` toe met `didSet { derivedWork = DerivedWork() }` en `derivedWork` (tussenopslag van het `WorkLedger`, zoals `DerivedPlans`; geldig voor de huidige tijdzone), de `encode(to:)` van golf 1 schrijft `work` alleen als het afwijkt, `usesCalendarHours` (uurloon én bron agenda), `workReport(forPayoutOn:asOf:)`, `workPayoutCents(on:)`, `averageAgendaHoursPerWeek(weeks: 12)` (betaalde uren per week over de laatste volle weken; voor de knop "Gemiddelde uit je agenda invullen").
- `SalaryPayout.hours: PayoutHours?` en `DayEvent.detail: String?` (beide met standaardwaarde nil achteraan, dus bestaande aanroepen compileren); `planEvents` zet `detail` op de salarisgebeurtenis.
- `CalendarAccess`, `CalendarInfo`, `CalendarFetch`, `WorkCalendarSource` (zie 4.1), `CalendarTitle.matches`, `WorkCalendarWindow.window(for:today:)` en `needsRefresh`, en `FinanceData.applyCalendarFetch(_:today:) -> Bool` (bewaart de snapshot; niets bij een agenda die niet bestaat).

### 3.2 Rekenregels

1. **Dienst naar stukken.** Elke dag van een dienst is een stuk (`startOfDay` en `date(byAdding: .day)` van `YearMonth.calendar`; op 26 okt 2025 telt de dag 25 uur). Verstreken minuten tellen, dus za 22:00 tot zo 06:00 bij het einde van de zomertijd is 9 uur (120 + 420 minuten).
2. **Pauze.** `breakMinutes(forShiftMinutes:)`: de rij met de hoogste grens die niet boven de dienst ligt (grens inclusief: 5 u 30 min krijgt 30 min, 5 u 29 min niets), nooit meer dan de dienst. Verdeeld over de stukken met `distribute` (30 min over 120 en 420 minuten geeft 7 en 23). Betaald = stuk − aandeel pauze.
3. **Factor van een dag** (in honderdsten): `.highest`: de hoogste van de ingeschakelde toeslagen die voor die dag gelden, zonder toeslag 100; `.add`: `max(0, 100 + Σ(factor − 100))`. Een zondag die feestdag is geeft 200 (of 250 bij optellen). Een `.date`-toeslag geldt voor die datum.
4. **Bedrag** = `exactPayCents(rate:, weightedMinutes100:)` over de som van (betaalde minuten × factor) van de periode, plus de verwachte minuten × 100; 14,35 × 8,5 u × 1,5 = 182,96. Eenmaal afronden per uitbetaling.
5. **Wat de agenda kent** (B12): `known = max(fetchedDay, laatste dag met een dienst)`; dagen ≤ `known` komen uit de agenda (een dag zonder dienst is 0), dagen erna uit `hoursPerCycle × (dagen / periodelengte)`. Is de hele periode na `known` (of is er geen snapshot): precies `payoutAmount()`. Gewerkt = dagen t/m vandaag (per kalenderdag, zoals de rest van de app), gepland = daarna; dit bepaalt alleen de tekst, nooit het bedrag.
6. **Koppeling** in `salaryPayoutCents` en `salaryCents`: bij `usesCalendarHours` zonder `salaryOverride` en zonder `hoursOverride` van de maand is elke uitbetaling `workPayoutCents(on:)`; die overschrijvingen gaan voor (eigen uren rekenen uren × uurloon, zonder toeslagen; zeg dat in de UI). `scheduledSalary` en `salaryHours` volgen. `averageMonthlyAmount` (schattingen) blijft op de handmatige uren. De uren van een uitbetaling na de startdatum tellen altijd volledig, ook als een deel van de periode vóór de startdatum ligt (het geld komt na de start).
7. **Venster** (`WorkCalendarWindow.window`): van `firstDay − (2 × cyclus + 7 dagen, maandelijks 69)`, maar niet later dan vandaag − 62 dagen, tot vandaag + 366 dagen; `needsRefresh` bij geen snapshot, andere naam, `fetchedDay != vandaag` of een venster dat niet meer past.

### 3.3 Opslag, back-up, sync

`CloudSync.withoutMarketData`: `result.work.snapshot = nil` (doc bijwerken); `hasContent` en `Overview.isEmptyStart`: `work.hasUserContent`; de back-up en het lokale bestand nemen `work` mee via Codable; een bestand zonder werkuren blijft byte-gelijk. Bestandsgrootte: ± 25 bytes per dienst, circa 400 diensten per jaar.

### 3.4 Teksten (`App/UI/WorkDisplay.swift`, Foundation-only, symlink in `CoreTests`)

`WorkText`: `hours(minutes)` ("38,5 uur"), `payoutDetail(PayoutHours?)` ("uit agenda: 38,5 uur"; gemengd "uit agenda: 24 uur, plus 14,5 uur uit je gemiddelde"; helemaal verwacht "verwacht uit je gemiddelde: 38,5 uur"), `periodText(range)` ("24 okt t/m 20 nov"), `breakdown(report, rules)` (regels: Uren, Gewerkt, Gepland, Verwacht, Toeslag per factor, Pauze, Bedrag), `factorText` ("× 1,5"), `ruleTitle`, `breakTitle`, `accessText(CalendarAccess)` (titel, uitleg, of er actie nodig is), `lastRefreshText`, `settingsSummary`. Plus `NavigationModel` (`.workHours`, titel "Werkuren", symbool `clock`, geen ouder, zevende element van `panes`), `SearchIndex` (agenda, uren, toeslag, zondag, feestdag, pauze, werken, rooster, diensten, kalender; `PageCatalog` blijft gelijk: instellingenpagina's staan daar bewust niet in) en een minimale `WorkHoursPage` (placeholder die golf 3A vervangt) zodat de app compileert.

### 3.5 Tests (golf 2; minimaal 1848 + 40 + 80)

`WorkShiftTests` (minuut afkappen, einde ≤ begin, rondreis `[b, e]`, onleesbare diensten overslaan, `normalized`, `pieces` met 25- en 23-uursdag in `Europe/Amsterdam` met `XCTSkip` als de zone ontbreekt, `distribute` optelt altijd), `WorkRulesTests` (pauzegrenzen 5:29 en 5:30, meer rijen, uitzetten, wissen; factor hoogste en optellen, uitgezette toeslag, `.date`; standaard schrijft niets; lenient), `DutchHolidaysTests` (Pasen 2024-2035: 03-31, 04-20, 04-05, 03-28, 04-16, 04-01, 04-21, 04-13, 03-28, 04-17, 04-09, 03-25; negen feestdagen per jaar en `isHoliday` op elke dag van het jaar gelijk aan de lijst; Hemelvaart 2025-05-29, 2026-05-14; Koningsdag 2025 en 2031 op 26 april, 2013 op 30 april; een standaard feestdag uitzetten; extra's en eigen dagen), `WorkHoursTests` (periodes maandelijks, om de 4 weken, om de N dagen, deze en vorige; afronding 55,94 × 10,75 × 3; terugval en gemengd; `hoursOverride` en `salaryOverride` gaan voor; vast salaris negeert de agenda; `salaryHours`, `scheduledSalary`; uren vóór de startdatum tellen mee voor een uitbetaling erna; een onafhankelijke referentie die per minuut met `Calendar` telt, naast `SalaryTestSupport`), `WorkCalendarCoreTests` (naam vergelijken, venster, `needsRefresh`, `applyCalendarFetch` met een nagemaakte `WorkCalendarSource`; een lege agenda die wel is ververst geeft 0 uur, een onbekende agenda laat de oude diensten staan), `WorkPersistenceTests` (rondreis, oud bestand zonder nieuwe sleutels, `withoutMarketData`, `hasContent`, `isEmptyStart`, back-up in en uit), `WorkDisplayTests`, uitbreiding van `NavigationRulesTests` (12 pagina's, 7 panes) en `SearchIndexTests`, en `WorkAgendaPropertyTests` (referentie `ref-werkuren/tests/WorkAgendaProofTests.swift`, 300 zaadwaarden, met vorige en deze periode, een horizon van de agenda, een startdatum en een eigen-uren-maand) plus een zesde reeks (zaad + 37_000) in `ledgerScenario` met het kenmerk "uren uit agenda", zodat `LedgerConsistencyTests` het meetelt.

## 4. Agenda-adapter en schermen (golf 3: 3A en 3B tegelijk)

### 4.1 Protocol, adapter, controller (3A)

`protocol WorkCalendarSource: Sendable` (Core): `access()`, `requestAccess()`, `calendars()`, `fetch(calendarTitle:from:to:allDayShiftHours:) async throws -> CalendarFetch`, `changes() -> AsyncStream<Void>`. `actor EventKitWorkCalendar` (`App/Calendar/`, referentie in `ref-werkuren/calendar/`):

| EventKit (Apple-documentatie) | Gebruik |
|---|---|
| `EKEventStore.authorizationStatus(for: .event)`; `.fullAccess` en `.writeOnly` zijn iOS 17 / macOS 14 | `.fullAccess` is `granted`; `.writeOnly`, `.denied`, `.restricted`, `.notDetermined` |
| `requestFullAccessToEvents() async throws -> Bool` (iOS 17, macOS 14; de app begint op iOS 18 en macOS 15: geen `#available`), daarna `reset()` | toestemming vragen; zonder `reset()` ziet een eerder gemaakte winkel geen gegevens |
| `calendars(for: .event)`; `EKCalendar.title`, `calendarIdentifier`, `source.title`, `type` | agendakeuze op naam (`.birthday` weglaten) |
| `predicateForEvents(withStart:end:calendars:)`, `events(matching:)` | per jaar een vraag (EventKit zoekt hooguit vier jaar per vraag); synchroon, dus in de actor; terugkerende afspraken komen als losse voorkomens (`occurrenceDate`) |
| `EKEvent.startDate`, `endDate` (`Date!`), `isAllDay`, `status == .canceled`, `attendees`, `EKParticipant.isCurrentUser`, `participantStatus == .declined` | filteren; alleen begin en einde verlaten de actor |
| `Notification.Name.EKEventStoreChanged` | `NotificationCenter.addObserver(forName:object:queue:using:)` in `changes()` (niet de iOS 26-variant `EKEventStore.EventStoreChanged`) |

`WorkCalendarController` (`@MainActor @Observable`, staat op `MyBuddyApp`, ook in de `SettingsScene` geïnjecteerd): `access`, `calendars`, `isRefreshing`, `lastFetch`, `lastError`, `changeCount`; `prepare()` (leest toestemming, geen vraag), `requestAccess()`, `refresh(into: AppStore, force:)` (alleen als `access.canRead`; `needsRefresh` of `force`; `store.mutate { _ = $0.applyCalendarFetch(...) }`). `RootView`: `.task` en `scenePhase == .active` verversen bij bron agenda; `.onChange(of: changeCount)` na 2 s. `.environment(workCalendar)` op beide scenes. De waarnemer in `changes()` bewaart zijn token in een `@unchecked Sendable`-doos (anders een Swift 6-waarschuwing). `Tests/AppTests/WorkCalendarControllerTests.swift`: nagemaakte bron (toegang geweigerd laat oude diensten staan, geen agenda gevonden, verversen schrijft de snapshot). Een `-mybuddy-demo` sessie krijgt `DemoWorkCalendar` (DEBUG, vaste diensten rond vandaag) en `-mybuddy-demo-hours` zet de voorbeelddata op uurloon uit de agenda.

### 4.2 Project, plist, entitlement (3A)

`project.yml`, target `MyBuddy`, `settings.base` (naast de bestaande sandbox-regels):

```yaml
ENABLE_RESOURCE_ACCESS_CALENDARS: YES
INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription: "MyBuddy leest alleen het begin en einde van afspraken in de agenda die je kiest (standaard 'werken') om je werkuren en salaris uit te rekenen. Titels en notities worden niet gelezen of bewaard."
```

De plist-sleutel geldt voor iOS én macOS (sinds iOS 17 en macOS 14); zonder hem stort de app bij de toestemmingsvraag in. Het entitlement wordt door Xcode uit de build setting gemaakt (zoals bij `ENABLE_USER_SELECTED_FILES`); er komt geen entitlements-bestand bij, zodat `ENABLE_APP_SANDBOX`, netwerk en bestanden onaangetast blijven. **Poort in CI** (`.github/workflows/ci.yml`, job `build-macos`, na het bouwen): zoek `MyBuddy.app.xcent` in DerivedData en `grep -q personal-information.calendars`; ontbreekt het bestand: waarschuwing (`::warning::`), staat het erin zonder de sleutel: fout. **Terugval als de poort faalt**: in `project.yml` onder het target `entitlements: { path: App/MyBuddy.entitlements, properties: { com.apple.security.personal-information.calendars: true } }` (XcodeGen schrijft het bestand en zet `CODE_SIGN_ENTITLEMENTS`; Xcode voegt de sandbox-instellingen uit de build settings erbij) en controleer met `codesign -d --entitlements :-` op een Mac. Voor draaien op een toestel volstaat een gratis "Personal Team".

### 4.3 Typecontrole (3A, stap 0)

In `/tmp/ctl-all`: kopieer `ref-werkuren/stubs/EventKit.swift` naar `stubs/EventKit/EventKit.swift`, voeg `build EventKit` toe na `build Security` in `build-stubs.sh` en bouw de stubs voor iOS en macOS; voeg aan `stubs/UIKit/UIKit.swift` toe `open class UIApplication: NSObject { public static let openSettingsURLString: String = "app-settings:" }` (Apple: `class let`, iOS 8). Wat de nieuwe schermen verder missen komt met zijn Apple-handtekening. Poort: `run-all.sh` 0 fouten, 0 `ONBEWAAKT`.

### 4.4 Pagina Werkuren (3A; `Pages/Settings/WorkHoursPage.swift` en `WorkHoursParts.swift`)

`ListScaffold(title: "Werkuren")`, geen sheets. Secties in deze volgorde:
1. **Melding** (alleen bij een probleem, `SettingsNotice`): `notDetermined` ("MyBuddy mag je agenda nog niet lezen", knop "Toegang geven"); `denied` en `restricted` (uitleg en knop "Open Instellingen": iOS `UIApplication.openSettingsURLString`, macOS `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`, via `openURL`); `writeOnly` ("Zet de toegang op volledig"); geen agenda met die naam; een foutmelding. De rest van de pagina blijft bruikbaar.
2. **Urenbron**: `Toggle("Uren uit je agenda")` (bij uit: handmatig; aanzetten vraagt zo nodig toegang); bij een vast salaris uitgeschakeld met een rij naar Salaris. Voetnoot over het verleden: "Dit geldt ook voor eerdere maanden vanaf je startdatum."
3. **Agenda**: `Picker("Agenda", ...)` met de titels uit `controller.calendars` (bewaart de naam), "Gevonden: 1 agenda (iCloud)" of "2 agenda's met deze naam: beide tellen mee"; `Toggle("Hele-dag-afspraken tellen mee")` met `IntStepperRow` "Uren per hele dag" (1...16); "Laatst bijgewerkt: vandaag 14:02, 312 diensten" (`lastRefreshText`), een regel met wat is overgeslagen ("2 afgewezen, 1 hele dag, 1 langer dan 16 uur") en `ActionButton("Nu verversen")`.
4. **Periode**: `Picker("Uren van")`: "Deze periode" / "De vorige periode", met de datums van de volgende uitbetaling (`periodText`).
5. **Toeslagen**: rij per toeslag (`Toggle` met `ruleTitle` en `NumberRow` "Factor" met `unit: .plain("×")`, `range: 0...10`), swipe om te verwijderen, `Menu("Toeslag toevoegen")` (Weekdag, Feestdag, Eigen datum met `DatePicker`), `Picker("Bij meer toeslagen")`: "Hoogste telt" / "Optellen".
6. **Pauzes**: rij per regel (`NumberRow` "Vanaf" in uur en `IntStepperRow` "Onbetaalde pauze" in min), swipe, "Pauzeregel toevoegen", voetnoot "De pauze is onbetaald en gaat van de dienst af."
7. **Feestdagen**: een schakelaar per soort (`HolidayKind`, twaalf), "Eigen feestdag toevoegen" met datums (swipe); voetnoot met de eerstvolgende feestdagen en "Oudejaarsdag geldt de hele dag".
8. **Voorbeeld**: de volgende twee uitbetalingen (`AmountRow`: datum, uren, gewerkt/gepland/verwacht, toeslag per factor, pauze, bedrag; `accessibilityElement(children: .combine)`).
9. **Beheer**: "Gemiddelde uit je agenda invullen" (zet `hoursPerWeek`), "Eerdere maanden vastleggen" (`confirmationDialog`, `freezeSalaryHistory(before: now)`); voetnoot "MyBuddy bewaart alleen begin en einde van je diensten, geen titels of notities."
`SettingsView`: rij `SettingsLinkRow(page: .workHours, subtitle: WorkText.settingsSummary(...))` tussen Rekenen en Koersen; `SettingsScene`: `Tab("Werkuren", systemImage: "clock", value: SettingsPage.workHours)` tussen Rekenen en Koersen; `SettingsDestination`; `AboutPage` (privacyregel over de agenda); `DebugLaunch` (`workhours`); `scripts/ci-screenshots.sh` (Werkuren, Startdatum, Salaris met uren uit agenda); `README.md` en `system_architecture.md`.

### 4.5 Salaris, Inkomen, Home, Dag voor dag (3B; alleen lezen uit `FinanceData`, geen controller)

- **`SalaryPage`** bij uurloon: na "Uurloon" twee `ChoiceRow`s "Uren per week invullen" / "Uren uit je agenda" (bindt `work.hoursSource`, zonder `SalaryScheduleEdit`, voetnoot over het verleden en "Maanden zonder diensten in je agenda krijgen geen salaris"); bij agenda: het veld heet "Gemiddeld aantal uren per week" met de uitleg "Voor schattingen en voor wat nog niet in je agenda staat", een `NavigationRow` naar `.settings(.workHours)`, en de formule vervangen door "Uurloon × uren uit je agenda, met toeslagen en pauzes". Nieuwe kaart `SalaryHoursCard` (`Pages/Month/SalaryHoursCard.swift`) "Uren van de volgende uitbetalingen": per uitbetaling (twee) datum, periode, `WorkText.breakdown` (uren, gewerkt/gepland/verwacht, toeslag per factor, pauze, bedrag) en de terugvaltekst "verwacht uit je gemiddelde" als er niets uit de agenda komt.
- **`IncomePage`** (`IncomeSalarySection`): ondertitel van elke uitbetaling krijgt `payoutDetail`; de overschrijvingsrijen noemen bij agenda "Eigen uren rekenen uren × uurloon, zonder toeslagen".
- **Dag voor dag en Home**: `DayEventRow` en `HomeDayEventLine` tonen `event.detail` (voetnoot) bij de salarisgebeurtenis: "uit agenda: 38,5 uur". VoiceOver leest het mee.
- Teksten volgens de termenlijst (docs/design/plan.md 2.8, design2 1.6), Dynamic Type, `Theme.minTapTarget`, `Theme.textSecondary` voor uitleg; geen nieuwe `.sheet(`.

## 5. Werkpakketten, golven, eigendom

Volgorde: **golf 1 (startdatum) -> golf 2 (werkuren Core) -> golf 3 (3A en 3B tegelijk)**: vier bouwers in totaal. Elk bestand heeft per golf één eigenaar; een fout in andermans bestand laat je staan en meld je (`docs/work/own-check.sh --owner <pad> <golf>`). Regels voor elke bouwer: lees par. 0 en 2 van `docs/design2/plan.md` (componenten), nieuwe typen met nieuwe namen, iOS 26-API's achter `#available`, alleen-iOS achter `#if os(iOS)`, per nieuw scherm een `#Preview`, `docs/design/precheck.sh` op elk aangeraakt bestand.

**Golf 1 - Startdatum.** Stap 0: basislijn (`run-all.sh` 0 fouten; `swift test` 1848 groen) en de fixture van het oude formaat (uitvoer van de HUIDIGE `FinanceStorage.makeEncoder()` voor een vaste dataset). Dan 2.2 in de volgorde van de tabel, na elke groep `swift test`; dan 2.3; schrijf `docs/work/own-check.sh` (kopie van `docs/design2/own-check.sh` met `docs/work/plan.md`) en `docs/work/start-check.sh`. *Klaar*: `run-all.sh` 0 fouten; `swift test` minimaal 1888 groen en de bestaande 1848 ongewijzigd groen; `start-check.sh`, `design-checks.sh`, `own-check.sh 1` PASS; zonder `startDay` is de uitvoer van elke encoder byte-gelijk aan HEAD.

**Golf 2 - Werkuren Core.** Referentie `ref-werkuren/core/` en `core-edits-vs-HEAD.diff`; par. 3 met de tests van 3.5. *Klaar*: `run-all.sh` 0 fouten; `swift test` minimaal 1968 groen; de eigenschapstests dekken de kenmerken "uren uit agenda" (minstens 8 datasets) en "startdatum"; `own-check.sh 2` PASS. Niet aanraken: `App/Pages` buiten de placeholder, `App/Calendar`.

**Golf 3A - Agenda, Instellingen, project.** 4.1 tot en met 4.4, de stubs (4.3) als stap 0. *Klaar*: `run-all.sh` 0 fouten, 0 `ONBEWAAKT`; `swift test` ongewijzigd groen; `design-checks.sh` PASS; de CI-poort van 4.2 staat erin; elk nieuw scherm heeft previews (gevuld, donker, grote tekst, geen toegang, geen agenda).

**Golf 3B - Salaris en teksten.** 4.5. *Klaar*: `run-all.sh` 0 fouten; `design-checks.sh` PASS; previews (agenda, helemaal verwacht, gemengd, vast salaris). 3A en 3B raken elkaars bestanden niet; 3B leest geen controller.

### Eigendom per golf

<!-- EIGENDOM-BEGIN -->
```text
# pad (meest specifiek wint) | golf1 | golf2 | golf3   ("-" = niemand, "C" = de coördinator; 3A en 3B zijn de twee bouwers van golf 3)
App/ - - -
App/Core/ 1 2 -
App/Core/CloudSync.swift - 2 -
App/AppStore.swift 1 - -
App/UI/ - - -
App/UI/StartDateText.swift 1 - -
App/UI/WorkDisplay.swift - 2 -
App/UI/CashflowDisplay.swift 1 - -
App/UI/RecentActivity.swift 1 - -
App/UI/PotDisplay.swift 1 - -
App/UI/MoneyFigures.swift 1 - -
App/Navigation/NavigationModel.swift 1 2 -
App/Navigation/SearchIndex.swift 1 2 -
App/Navigation/SettingsScene.swift - - 3A
App/Pages/ - - -
App/Pages/Settings/StartDatePage.swift 1 - -
App/Pages/Settings/DataPage.swift 1 - -
App/Pages/Settings/SettingsDestination.swift 1 2 3A
App/Pages/Settings/WorkHoursPage.swift - 2 3A
App/Pages/Settings/WorkHoursParts.swift - - 3A
App/Pages/Settings/SettingsView.swift - - 3A
App/Pages/Settings/AboutPage.swift - - 3A
App/Pages/Home/HomeWelcome.swift 1 - -
App/Pages/Home/HomeShelves.swift - - 3B
App/Pages/Month/SalaryPage.swift - - 3B
App/Pages/Month/SalaryHoursCard.swift - - 3B
App/Pages/Month/IncomePage.swift 1 - 3B
App/Pages/Month/ExpensesPage.swift 1 - -
App/Pages/Month/DistributePage.swift 1 - -
App/Pages/Month/MoneyLines.swift 1 - -
App/Pages/Library/LibraryFigures.swift 1 - -
App/Pages/BufferPages.swift 1 - -
App/Pages/Bank/ 1 - -
App/Pages/Saving/ 1 - -
App/Pages/CashflowPages.swift - - 3B
App/Calendar/ - - 3A
App/MyBuddyApp.swift - - 3A
App/RootView.swift - - 3A
App/Debug/ - - 3A
CoreTests/ 1 2 -
Tests/AppTests/ - - 3A
project.yml - - 3A
.github/ - - 3A
scripts/ - - 3A
README.md - - 3A
system_architecture.md - - 3A
docs/work/ 1 - -
docs/work/plan.md C C C
```
<!-- EIGENDOM-EINDE -->

## 6. Verificatie

1. **Typecontrole** (de enige compiler hier): `/tmp/ctl-all/run-all.sh` (50 s; per bouwer een eigen kopie volgens `docs/design2/plan.md` 5.4, met `/tmp/ctl-NAAM`): `TOTAAL fouten (alle varianten): 0` en 0 `ONBEWAAKT`; tijdens het werk `run-all.sh quick`.
2. **Core-tests**: `cd CoreTests && swift test --scratch-path /tmp/sb-NAAM` (Swift 6.0.3 in `/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin`; 3,5 min): groen, per golf minimaal 1888, 1968 en 1968.
3. `docs/design/design-checks.sh` PASS (let op: `.sheet(` hoogstens 16, `.alert(` 0, geen `.secondary`, geen `.white`/`.black`, geen "Meetpunt"), `docs/work/start-check.sh`, `docs/work/own-check.sh <golf>`.
4. **CI** (de coördinator pusht na elke golf naar een `claude/**`-tak): iOS en macOS bouwen, tests, de entitlementpoort van 4.2, screenshots.
5. Handmatig op een toestel (hier niet uitvoerbaar): toestemming vragen en weigeren, agenda met en zonder 'werken', dienst over middernacht en de zomertijdwissel, afgewezen afspraak, wijzigen in de Agenda-app terwijl MyBuddy openstaat, Mac met en zonder entitlement, startdatum midden in de maand, beginsaldo's.

## 7. Risico's en eerlijke beperkingen

| # | Risico | Aanpak |
|---|---|---|
| 1 | Geen toestel en geen echte EventKit-test: de adapter is alleen typegecontroleerd (tegen een stub met Apple's handtekeningen). Niet te zien: de toestemmingsvraag, `reset()` na toestemming, terugkerende of afgewezen afspraken (Exchange, Google), prestaties bij een grote agenda. | De Core is volledig getest met een nagemaakte agenda; de adapter is dun en één bestand; de handmatige lijst van 6.5; fouten staan in `lastError`. |
| 2 | Het entitlement via een build setting is hier niet te controleren (CI bouwt zonder ondertekening). | CI-poort op het `.xcent`-bestand; terugval met `entitlements:` (4.2). |
| 3 | Alleen dagregels: geen avond- of nachttoeslag, Oudejaarsdag geldt de hele dag. | B22; de dagsplitsing maakt een tijdvenster later een kleine uitbreiding. |
| 4 | Betaalritmes verschillen (een periode kan een paar dagen vóór de uitbetaling eindigen): twee vaste keuzes, deze en vorige periode. | De pagina toont de exacte datums; een verschuiving in dagen kan later. |
| 5 | Dagen volgen de tijdzone van het apparaat (`YearMonth.calendar`): reizen of twee zones kan andere dagen en feestdagen geven. | Gelijk aan de rest van de app; tests zetten de zone expliciet. |
| 6 | De agenda is de waarheid voor het verleden: een maand zonder diensten krijgt geen salaris en nieuwe regels veranderen eerdere maanden (B9). | Voetnoot op Salaris en Werkuren; "Eerdere maanden vastleggen". |
| 7 | Deelmaand: percentage-inleg rekent over het inkomen dat meetelt, een eigen salaris is het totaal dat telt (B5), beleggingen houden hun waarde-updates (B7). | Uitleg op de pagina Startdatum en tests. |
| 8 | Oudere appversies op andere apparaten kennen `startDay` en `work` niet en schrijven ze weg. | Alle apparaten bijwerken; verder blijft het formaat gelijk. |

## 8. Samenvatting (maximaal 30 regels)

1. Startdatum: `FinanceData.startDay: CalendarDay?`, `startMonth` volgt; zonder veld rekent alles identiek (1848 tests blijven groen). Eén primitief `firstCountedDay(in:)`; geplande dingen op dagniveau, handmatige boekingen en saldi via `counted*`; schattingen met een hele startmaand.
2. UI: pagina "Startdatum" onder Gegevens, pil op de lege Home, "alleen instellen" of "alles wissen", beginsaldo's op de startdag.
3. Werkuren: `FinanceData.work` (bron, agendanaam, periode, toeslagen, pauzetabel, feestdagen, afgeleide diensten als `[begin, einde]`, geen titels). Dienst per kalenderdag gesplitst (zomertijd goed), factor per dag (hoogste telt of optellen), eenmaal afronden per uitbetaling.
4. Een uitbetaling betaalt de uren van haar periode (deze of vorige); wat de agenda niet kent valt terug op de handmatige uren.
5. EventKit alleen in `EventKitWorkCalendar` achter een protocol; verversen bij actief worden, bij wijziging en met een knop; toestemming alleen na een tik. `ENABLE_RESOURCE_ACCESS_CALENDARS: YES` en `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`; geen betaald account nodig.
6. Schermen: Werkuren (groep Rekenen, zevende pane op de Mac), "Uren uit je agenda" op Salaris, "uit agenda: 38,5 uur" bij Dag voor dag en Home.
7. Vier bouwers (golf 1, golf 2, golf 3A, golf 3B); poorten: `run-all.sh` 0 fouten, `swift test` (1888, daarna 1968), `design-checks.sh`, `start-check.sh`, `own-check.sh`, CI.
8. Beperkingen: geen echte EventKit-test, alleen dagregels, entitlement pas in CI te zien, tijdzone van het apparaat.
