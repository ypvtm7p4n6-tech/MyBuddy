#!/usr/bin/env bash
# Behoud-controle voor ontwerp 2 (docs/design2/plan.md, par. 5.3): elke sleutelaanroep van de oude kaarten heeft nog een
# gebruiker in de pagina's, zodat geen getal, rekenregel of keuze verloren gaat bij het ombouwen van de schil.
# Gebruik: docs/design2/keep-check.sh [--final]
#   zonder --final : tijdens de bouw. De oude kaarten in App/Pages/Tabs/ tellen als gebruiker.
#   met --final    : oplevering (pakket 3). App/Pages/Tabs/ is weg, dus de nieuwe schermen moeten de aanroepen zelf doen.
# Een gebruiker is een bestand in App/Pages/ (of App/RootView.swift) dat de aanroep bevat. De definitie zelf staat in App/Core of
# App/UI en telt niet mee. Exit 1 als een aanroep geen gebruiker meer heeft.
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /home/user/MyBuddy)" || exit 2
FINAL=0; [ "${1:-}" = "--final" ] && FINAL=1
SCOPE=(App/Pages App/RootView.swift)
KEYS=(
  'netWorth(at:'
  'NetWorthTrend.model'
  'MonthBoard('
  'periodSummary('
  'StackedBarModel.months'
  'income(in:'
  'expenseOverview('
  'monthFigures('
  'bankBalanceNowIfKnown'
  'LedgerBook('
  'UpcomingDaysWindow.'
  'homePots()'
  'homeHoldings()'
  'PortfolioTrend.model'
  'FavoritePotsSheet('
  'FavoriteHoldingsSheet('
  'GoalMath.hubSubtitle'
  'BufferCalc.summary'
  'accelerators(for'
  'Growth.projection'
  'PurchaseCalc.resolvedWage'
  'BlockOrderSheet('
  'SyncAttentionBanner('
  'CashflowCheckBanner('
  'loadSampleData()'
  'refreshPrices(force: true)'
  'PotsGoalProgress('
  'savedTowardGoals'
)
FAIL=0
for key in "${KEYS[@]}"; do
  users=$(grep -rlF --include=*.swift -- "$key" "${SCOPE[@]}" 2>/dev/null | { if [ "$FINAL" = 1 ]; then grep -v '^App/Pages/Tabs/'; else cat; fi; } | wc -l | tr -d ' ')
  if [ "$users" -ge 1 ]; then
    printf '%-34s %s gebruiker(s)  PASS\n' "$key" "$users"
  else
    printf '%-34s %s gebruiker(s)  FAIL\n' "$key" "$users"; FAIL=1
  fi
done
echo
[ "$FAIL" = 0 ] && echo "KEEP: ALLES PASS" || { echo "KEEP: ER ZIJN FAILS (een sleutelaanroep van de oude kaarten heeft geen gebruiker meer)"; exit 1; }
