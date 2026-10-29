# MyBuddy: verdelen, overschrijfdata, bankrekening als bestemming, doelen met meer potten, opnemen met bestemming en loon per maand (bouwplan 2)

STATUS: SKELET (de architect vult dit bestand stap voor stap; alles wat hieronder staat als "TODO" is nog niet klaar).

Peildatum 29 oktober 2026. Basis: `HEAD` a95891f (stabiele basislijn, 1848 tests groen) plus golf 1 van `docs/work/plan.md` (startdatum) als af gerekend. Zes wensen D1 t/m D6 (zie par. 1). Er is niets in `App/`, `CoreTests/` of `Tests/` aangepast; alleen dit plan en proefbestanden in `/tmp/arch-probe2/`.

## Bewijs
TODO

## 1. Besluiten (bindend; geen vragen)

(CONCEPT, wordt herschreven) D1 extra bedrag zit in de percentageregel (`PercentRule.extra`, `Pot/Holding.contributionExtra`); D2 delen `TransferPart(day, amount)` uit het totaal, rest op de standaarddag, standaard en per maand, vastgelegd bij wijziging; D3 bankrekening = toewijzing zonder beweging (`BankShare`, `MonthFigures.toBank`, `unassigned`), `remaining` blijft wat er op de rekening blijft; D4 `.pot(eerste)` + `LifeGoal.morePotIDs` (oude apps blijven leesbaar); D5 `MoneyEnd` + `withdraw/deposit`; D6 `FinanceData.salaryChanges` + `salarySettings(in:)`, maand van de uitbetaling.

## 2. Core per wens (D1 t/m D6)
TODO

## 3. Contract (namen, handtekeningen)
TODO

## 4. UI per pagina en bestand
TODO

## 5. Werkpakketten, golven, eigendom
TODO

<!-- EIGENDOM-BEGIN -->
```text
TODO
```
<!-- EIGENDOM-EINDE -->

## 6. Verificatie
TODO

## 7. Risico's en open punten voor de gebruiker
TODO

## 8. Samenvatting (maximaal 30 regels)
TODO
