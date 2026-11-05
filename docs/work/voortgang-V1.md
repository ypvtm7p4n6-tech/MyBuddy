# Voortgang V1 (fase 1 van docs/work/plan2.md)

Bouwer V1 werkt rechtstreeks in /home/user/MyBuddy. Dit bestand houdt bij wat klaar is en wat nog moet (voor hervatten).
Controles: `swift test` met `--scratch-path /tmp/sb-V1` (PATH=/opt/swift/swift-wasm-6.0.3-RELEASE/usr/bin), typecontrole in `/tmp/ctl-V1`
(`/tmp/ctl-V1/run-all.sh quick` of zonder argument; opnieuw aan te maken met het recept in docs/design2/plan.md 5.4).
Basislijn gemeten op HEAD 0333505: 1957 tests, 10 overgeslagen, 0 fouten (141 s testen, 339 s met schone bouw).
Referentie (architect): /tmp/arch-probe2/ref-verdelen/ (core/, ui/, tests/, core-edits-vs-golf1.diff). V2-delen (loon, SalaryChange,
WageHistory, WageText, WageEdit, Destination.wageChange, reeks zaad + 47_000) zijn NIET van V1.

## Klaar
- [x] Poorten gekopieerd uit de proef: `docs/work/own-check2.sh`, `contract-check2.sh`, `verdelen-check.sh` (nog aan te passen: zie onder).
- [x] Stap 0: `VerdelenFixtures.swift`, `VerdelenLegacyOutput.swift` (vastgelegd op HEAD), `DistributionPersistenceTests`.
- [x] D1 percentage plus extra bedrag (Allocation, Models, SavingsDisplay, Fields, MoneyFigures, Accelerators-herstel); `ExtraAmountTests`.
- [x] D2 extra overschrijfdata (`Core/Transfers.swift`, DayEvents, Pots, Invest, Plan, SavingsDisplay, MoneyFigures); `TransferPartsTests`;
      onleesbare delen worden per element overgeslagen (`decodeTransferParts`).
- [x] D3 bankrekening (`Core/BankShare.swift`, Plan, Ledger, Models, Overview, CloudSync, Purchase, Buffer, Accelerators, MoneyFigures);
      `BankShareTests`.
- [x] D4 doel uit meer potten (`LifeGoal.morePotIDs`, mild gelezen via eigen `init(from:)`), `GoalPotsTests`.
- [x] D5 `Core/PotMoves.swift`; `PotMovesTests`.
- [x] Teksten: `UI/DistributionText.swift`, `PotMoveText.swift`, `GoalPotsText.swift` (symlinks in CoreTests), `TransferPartsEditor.swift`.
- [x] Zoektermen in `PageCatalog.swift`; `PageCatalogTests.testTheNewTermsOfRound2AreThere`; `SearchIndexTests` ("nog rente").
- [x] `sampleWithDistribution` (zonder loonwijziging: dat is V2).
- [x] `ledgerScenario` zesde reeks (zaad + 41_000) aan het eind; `LedgerConsistencyTests` en `StartDayPropertyTests` met orakel.

## Nog te doen
- [ ] Poorten afwerken en draaien (`contract-check2.sh 1`, `verdelen-check.sh 1`, `own-check2.sh 1 --only V1`, `design-checks.sh`, `start-check.sh`)
- [ ] Prestatiemeting `monthLedger` (mediaan <= 15 ms)
- [ ] volledige `swift test` (minstens 2040) en `/tmp/ctl-V1/run-all.sh` (0 fouten, 0 ONBEWAAKT)
- [ ] Eindrapport met WIRING voor G2V2: `salaryChanges` in `CloudSync.hasContent` en `Overview.isEmptyStart`, `setSalaryChange`-regel in
      `sampleWithDistribution`, `testContentChecksSeeABankShare` uitbreiden, `.wageChange` in `PageCatalogTests`.
