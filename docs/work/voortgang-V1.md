# Voortgang V1 (fase 1 van docs/work/plan2.md)

Bouwer V1 werkt rechtstreeks in /home/user/MyBuddy. Dit bestand houdt bij wat klaar is en wat nog moet (voor hervatten).
Controles: `swift test` met `--scratch-path /tmp/sb-V1` (PATH=/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin), typecontrole in `/tmp/ctl-V1`
(`/tmp/ctl-V1/run-all.sh` of `quick`; opnieuw aan te maken met het recept in docs/design2/plan.md 5.4).
Basislijn op HEAD 0333505: 1957 tests, 10 overgeslagen, 0 fouten (op 29 oktober). Referentie van de architect: /tmp/arch-probe2/ref-verdelen/.
De V2-delen (loon, SalaryChange, WageHistory, WageText, WageEdit, Destination.wageChange, reeks zaad + 47_000) zijn NIET van V1.

## Klaar (5 november 2026)
- [x] Poorten: `docs/work/own-check2.sh`, `contract-check2.sh` (147 namen van fase 1), `verdelen-check.sh` (controle C en D): PASS.
- [x] Stap 0: `VerdelenFixtures.swift`, `VerdelenLegacyOutput.swift` (vastgelegd op HEAD), `DistributionPersistenceTests`.
- [x] D1 percentage plus extra bedrag, D2 extra overschrijfdata (`Core/Transfers.swift`), D3 bankrekening (`Core/BankShare.swift`),
      D4 doel uit meer potten (`LifeGoal.morePotIDs`, mild gelezen), D5 opnemen/storten met bestemming (`Core/PotMoves.swift`).
- [x] Teksten en hulpen: `UI/DistributionText.swift`, `PotMoveText.swift`, `GoalPotsText.swift` (symlinks in CoreTests),
      `UI/TransferPartsEditor.swift` (met previews).
- [x] Zoektermen in `PageCatalog.swift` + tests; `sampleWithDistribution` (zonder loonwijziging).
- [x] Tests: `ExtraAmountTests`, `TransferPartsTests`, `BankShareTests`, `PotMovesTests`, `GoalPotsTests`, `DistributionTextTests`,
      `PotMoveTextTests`, `GoalPotsTextTests`, `DistributionPersistenceTests`; `ledgerScenario` zesde reeks (zaad + 41_000) aan het eind,
      orakel voor stukken en bankdeel in `LedgerConsistencyTests` en `StartDayPropertyTests` (ook op 1200 zaadwaarden groen).
- [x] `swift test`: 2080 tests, 10 overgeslagen, 1 fout: de bestaande, klokafhankelijke `NowAndOverflowTests.testAbsurdMonthKeysAreIgnoredInsteadOfCrashing`
      (faalt sinds 1 november ook op de onaangeraakte basis 0333505; `addPot(openingBalance:)` zonder `now`).
- [x] Typecontrole `/tmp/ctl-V1/run-all.sh`: 0 fouten in alle zes varianten, 0 onbewaakt.
- [x] `monthLedger` op de zware set (10 potten, 8 beleggingen, 5 jaar): mediaan 11 tot 13 ms zonder, 25 ms met drie extra data per lijn.

## Nog te doen
- Niets voor V1. Zie het eindrapport voor WIRING (G2V2: salaryChanges in `hasContent`/`isEmptyStart`, loonregel in `sampleWithDistribution`,
  zevende reeks in `ledgerScenario`) en de klokafhankelijke bestaande test.
