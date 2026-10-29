# Impact van de nieuwe wensen D1 t/m D6 (code-graaf en tekstzoeken)

Peildatum 29 oktober 2026, basis HEAD c0130b2 (startdatum klaar). Bron: een graphify-graaf van alle code (9081 punten, AST, 25.774 verbindingen) plus tekstzoeken op de kernnamen. 'Treffers' = hoe vaak de kernnamen in het bestand voorkomen (inclusief commentaar). De graaf koppelt aanroepen op NAAM en is dus een overschatting: elke treffer die alleen uit de graaf kwam is hier nagezocht in de tekst en alleen opgenomen als hij klopte (`Interest.swift` en `RecurringSeries.swift` bleken valse treffers).

## Wat de analyse al laat zien

- **D5 is klein.** De Core kent het al: `transferPotToBank(potID:amount:note:date:)` (bankboeking plus opnameboeking met dezelfde `pairID`), `transferBankToPot` en `transfer(from:to:)` (pot naar pot, ook met `pairID`); `deletePotEntry` en `deleteBankEntry` verwijderen de andere helft mee. In `PotEntrySheet` (`App/Pages/Saving/PotSheets.swift`, regels 90 t/m 146) heeft Opnemen alleen de schakelaar 'Naar de bankrekening' (uit = een losse opname: het geld verdwijnt uit de app) en 'Overboeken' naar een andere pot is een aparte actie. Wat ontbreekt is één keuze 'Waar gaat het naartoe?' (bankrekening, een andere pot of buiten de app) in het Opnemen-blad; de Core hoeft nauwelijks te veranderen.
- **D4 raakt de minste bestanden.** `GoalFunding` (`Models.swift`) heeft `.portfolio`, `.pot(UUID)` en `.custom(...)`; `deletePot` in `Pots.swift` zet een doel met die pot terug naar `.portfolio`. De rekenstukken zitten in `Accelerators.swift`, `SavingsGoal.swift` en `Goals.swift`; de schermen in `SavingsGoalPages.swift`, `GoalPages.swift` en `Home/HomePlanning.swift`.
- **D6 raakt de meeste bestanden** (38 in `App/`): het salaris wordt overal gelezen (`SalarySchedule.swift`, `SalaryPage.swift`, `Models.swift`, `SavingsDisplay.swift`, `Allocation.swift`, `Accelerators.swift`, `Buffer.swift`, `Purchase.swift`, `Goals.swift`).
- **D1 en D2 raken `Accelerators.swift`**: 34 treffers op `contributionMode/Percent/Basis` en `monthlyContribution`; de versnellers rekenen met de inleg per pot. Een extra bedrag naast een percentage (D1) moet daar ook in, anders wijken de doelen af van het dagboek.
- **De startdatum hangt aan de overschrijfdag.** `Allocation.swift` en `StartDate.swift` gebruiken `transferCounts(_:in:)` ('een inleg met een overschrijfdag vóór de startdatum telt niet'). Bij meerdere overschrijfdagen (D2) moet die regel per deel gelden.

## D1 percentage + extra bedrag

22 bestanden in `App/` met treffers; 68 testbestanden noemen deze namen (die moeten mee of worden aangevuld).

| Bestand | Treffers |
|---|---|
| `App/Core/Allocation.swift` | 74 |
| `App/Core/Models.swift` | 45 |
| `App/Core/Accelerators.swift` | 34 |
| `App/Core/Invest.swift` | 13 |
| `App/Core/Plan.swift` | 11 |
| `App/Core/SampleData.swift` | 10 |
| `App/Pages/Saving/PotSheets.swift` | 9 |
| `App/Pages/Saving/HoldingSheets.swift` | 8 |
| `App/Core/Pots.swift` | 8 |
| `App/Core/Purchase.swift` | 5 |
| `App/UI/SavingsDisplay.swift` | 4 |
| `App/UI/MoneyFigures.swift` | 4 |
| `App/Core/DayEvents.swift` | 4 |
| `App/Pages/Month/DistributePage.swift` | 2 |
| `App/Core/SalarySchedule.swift` | 2 |
| `App/Core/ImportMapping.swift` | 2 |
| `App/UI/Charts.swift` | 1 |
| `App/Pages/BufferPages.swift` | 1 |
| `App/Debug/DebugLaunch.swift` | 1 |
| `App/Core/SavingsGoal.swift` | 1 |
| `App/Core/Overview.swift` | 1 |
| `App/Core/CloudSync.swift` | 1 |

## D2 meerdere overschrijfdagen

25 bestanden in `App/` met treffers; 36 testbestanden noemen deze namen (die moeten mee of worden aangevuld).

| Bestand | Treffers |
|---|---|
| `App/UI/MoneyFigures.swift` | 16 |
| `App/Core/DayEvents.swift` | 13 |
| `App/Core/Models.swift` | 12 |
| `App/Pages/Saving/PotSheets.swift` | 8 |
| `App/Pages/Saving/HoldingSheets.swift` | 8 |
| `App/Core/Plan.swift` | 6 |
| `App/UI/SavingsDisplay.swift` | 5 |
| `App/Core/Ledger.swift` | 5 |
| `App/Pages/Month/DistributePage.swift` | 4 |
| `App/Core/StartDate.swift` | 4 |
| `App/Core/Pots.swift` | 4 |
| `App/Core/Allocation.swift` | 4 |
| `App/Core/Invest.swift` | 3 |
| `App/Core/ImportMapping.swift` | 2 |
| `App/UI/PotDisplay.swift` | 2 |
| `App/Pages/Saving/PotDetailSections.swift` | 2 |
| `App/Core/Overview.swift` | 1 |
| `App/Core/CloudSync.swift` | 1 |
| `App/Core/SampleData.swift` | 1 |
| `App/UI/MoneyViews.swift` | 1 |
| `App/Pages/PotPages.swift` | 1 |
| `App/Pages/Saving/HoldingDetailSections.swift` | 1 |
| `App/Pages/Saving/HoldingRow.swift` | 1 |
| `App/Pages/Saving/HoldingDetailPage.swift` | 1 |
| `App/Pages/Saving/PotDetailPage.swift` | 1 |

## D3 bankrekening bij Verdelen

24 bestanden in `App/` met treffers; 41 testbestanden noemen deze namen (die moeten mee of worden aangevuld).

| Bestand | Treffers |
|---|---|
| `App/Core/Plan.swift` | 38 |
| `App/UI/MoneyFigures.swift` | 26 |
| `App/UI/ChartModels.swift` | 19 |
| `App/Core/ImportMapping.swift` | 14 |
| `App/Core/Ledger.swift` | 9 |
| `App/Pages/Month/FlowPage.swift` | 8 |
| `App/Pages/Home/HomeHero.swift` | 7 |
| `App/Core/SalarySchedule.swift` | 7 |
| `App/Core/Invest.swift` | 7 |
| `App/Pages/Month/DistributePage.swift` | 6 |
| `App/Core/Allocation.swift` | 5 |
| `App/UI/CashflowDisplay.swift` | 4 |
| `App/Pages/Library/LibraryFigures.swift` | 4 |
| `App/Core/Expenses.swift` | 4 |
| `App/Core/Export.swift` | 2 |
| `App/UI/Charts.swift` | 2 |
| `App/Pages/Saving/HoldingDetailSections.swift` | 2 |
| `App/Core/Accelerators.swift` | 2 |
| `App/AppStore.swift` | 1 |
| `App/Core/Bank.swift` | 1 |
| `App/UI/MoneyViews.swift` | 1 |
| `App/UI/PotDisplay.swift` | 1 |
| `App/Pages/PortfolioPages.swift` | 1 |
| `App/Pages/Saving/HoldingSheets.swift` | 1 |

## D4 doel met meerdere potten

9 bestanden in `App/` met treffers; 14 testbestanden noemen deze namen (die moeten mee of worden aangevuld).

| Bestand | Treffers |
|---|---|
| `App/Pages/SavingsGoalPages.swift` | 20 |
| `App/Core/Accelerators.swift` | 19 |
| `App/Core/SavingsGoal.swift` | 15 |
| `App/Pages/GoalPages.swift` | 5 |
| `App/Pages/Home/HomePlanning.swift` | 4 |
| `App/Core/Models.swift` | 2 |
| `App/UI/ChartModels.swift` | 2 |
| `App/Core/Pots.swift` | 1 |
| `App/Core/Goals.swift` | 1 |

## D5 opnemen met bestemming

15 bestanden in `App/` met treffers; 19 testbestanden noemen deze namen (die moeten mee of worden aangevuld).

| Bestand | Treffers |
|---|---|
| `App/Core/Bank.swift` | 23 |
| `App/Core/Pots.swift` | 17 |
| `App/Core/Models.swift` | 10 |
| `App/Pages/Saving/PotSheets.swift` | 6 |
| `App/UI/RecentActivity.swift` | 6 |
| `App/Pages/GoalPages.swift` | 5 |
| `App/Pages/Saving/PotDetailPage.swift` | 5 |
| `App/Pages/Saving/PotHistorySections.swift` | 4 |
| `App/Core/Accelerators.swift` | 3 |
| `App/Core/Goals.swift` | 3 |
| `App/Core/SampleData.swift` | 2 |
| `App/UI/CashflowDisplay.swift` | 2 |
| `App/Pages/Home/HomeSupport.swift` | 2 |
| `App/Pages/Bank/BankActionSheet.swift` | 2 |
| `App/Core/Ledger.swift` | 1 |

## D6 loon per maand

38 bestanden in `App/` met treffers; 65 testbestanden noemen deze namen (die moeten mee of worden aangevuld).

| Bestand | Treffers |
|---|---|
| `App/Pages/Month/SalaryPage.swift` | 28 |
| `App/Core/Models.swift` | 27 |
| `App/Core/SalarySchedule.swift` | 22 |
| `App/UI/SavingsDisplay.swift` | 14 |
| `App/Core/Allocation.swift` | 11 |
| `App/Core/Accelerators.swift` | 9 |
| `App/UI/MoneyFigures.swift` | 8 |
| `App/Pages/PurchasePages.swift` | 7 |
| `App/Core/SampleData.swift` | 6 |
| `App/Core/Goals.swift` | 5 |
| `App/Core/Buffer.swift` | 4 |
| `App/Pages/GoalPages.swift` | 4 |
| `App/Core/Purchase.swift` | 3 |
| `App/Pages/Month/IncomePage.swift` | 3 |
| `App/Navigation/NavigationModel.swift` | 3 |
| `App/Core/CloudSync.swift` | 2 |
| `App/UI/CashflowDisplay.swift` | 2 |
| `App/Pages/Month/DistributePage.swift` | 2 |
| `App/Pages/BufferPages.swift` | 2 |
| `App/Pages/Saving/PotSheets.swift` | 2 |
| `App/Pages/Saving/HoldingSheets.swift` | 2 |
| `App/Core/DayEvents.swift` | 2 |
| `App/Core/Overview.swift` | 1 |
| `App/Core/Plan.swift` | 1 |
| `App/Pages/PortfolioPages.swift` | 1 |
| `App/Pages/Month/MoneyLineSheet.swift` | 1 |
| `App/Pages/Month/FlowPage.swift` | 1 |
| `App/Pages/DestinationView.swift` | 1 |
| `App/Pages/ProjectionPage.swift` | 1 |
| `App/Pages/Settings/DataPage.swift` | 1 |
| `App/Pages/Home/HomeWelcome.swift` | 1 |
| `App/Pages/Bank/BankBalance.swift` | 1 |
| `App/Pages/Bank/BankDays.swift` | 1 |
| `App/Pages/CashflowPages.swift` | 1 |
| `App/Navigation/SearchIndex.swift` | 1 |
| `App/Navigation/PageCatalog.swift` | 1 |
| `App/Debug/DebugLaunch.swift` | 1 |
| `App/Core/Ledger.swift` | 1 |

