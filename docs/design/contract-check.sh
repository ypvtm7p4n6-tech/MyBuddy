#!/usr/bin/env bash
# Contractcontrole: bestaat elk symbool uit par. 4.4 van docs/design/plan.md? Gebruik: contract-check.sh [0|1|alles]
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /home/user/MyBuddy)"
WAVE="${1:-alles}"; MISSING=0
need() {  # need <soort> <naam>
  if ! grep -rqE --include=*.swift "^[[:space:]]*((public|private|fileprivate|final) )*$1 $2\b" App; then echo "ONTBREEKT: $1 $2"; MISSING=1; fi
}
needs() { grep -rqE --include=*.swift -- "$1" App || { echo "ONTBREEKT: $2"; MISSING=1; }; }
if [ "$WAVE" != 1 ]; then
  # golf 0: 0A
  for n in AppDomain; do need enum $n; done
  for n in PageScaffold ListScaffold Card LinkCard SectionHeader NavigationRow BigAmount StatTile FigureRow AmountRow SymbolBadge \
           IconButton ActionButton ActionLink ActionGroup EmptyHint NoticeBanner MonthBar RowAction SheetScaffold BlockOrderList BlockOrderSheet; do need struct $n; done
  for s in 'static let canvas' 'static let textSecondary' 'static let accentFill' 'static let onAccent' 'static let chartExpenses' 'static let minTapTarget' \
           'func animated<' 'func rowActions\(' 'func blockOrderToolbar\('; do needs "$s" "$s"; done
  # golf 0: 0B
  for n in AppTab SettingsPage Destination NavigationRules; do need enum $n; done
  need "final class" Router; need "final class" ActiveSession; need struct TabStack; need struct DestinationView
  # golf 0: F
  for n in TrendChart StackedBarChart DonutChart ProgressMeter SegmentedMeter DonutModel StackedBarModel; do need struct $n; done
  for n in ChartSize PortfolioTrend PriceTrend NetWorthTrend BankTrend DayBalanceTrend ProjectionTrend BufferTrend SavingsGoalTrend GoalCurveTrend PotTrend; do need enum $n; done
  needs 'var colorIndex' 'HoldingKind.colorIndex'; needs 'func potSeries\(' 'potSeries'
fi
if [ "$WAVE" != 0 ]; then
  # golf 1
  for n in OverviewTab MonthTab SavingTab PlanningTab IncomePage SalaryPage ExpensesPage DistributePage BankPage UpcomingDaysCard PotsPage PotDetailPage \
           PortfolioPage HoldingDetailPage PotsSummaryCard PortfolioSummaryCard GoalsPage GoalDetailPage SavingsGoalPage AcceleratorsPage BufferPage \
           ProjectionPage PurchasePage GoalsSummaryCard BufferSummaryCard AcceleratorsSummaryCard ProjectionSummaryCard PurchaseSummaryCard \
           SettingsView SettingsDestination SettingsPane SyncAttentionBanner AuthView; do need struct $n; done
  need enum BankSection
fi
[ "$MISSING" = 0 ] && echo "CONTRACT COMPLEET" || { echo "CONTRACT ONVOLLEDIG"; exit 1; }
