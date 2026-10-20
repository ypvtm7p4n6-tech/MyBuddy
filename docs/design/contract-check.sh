#!/usr/bin/env bash
# Contractcontrole: bestaat elk symbool uit par. 4.4 van docs/design/plan.md, met de goede handtekening?
# Gebruik: docs/design/contract-check.sh [0|1|alles|final]
#   0     golf 0 (0A, 0B, F)           1     golf 1 (A, B1, B2, C, D, E)      alles  beide
#   final na pakket G: bovendien mag geen overgangsvorm meer bestaan (oude padnamen, compat-typen).
# Twee soorten controle:
#   need <soort> <naam>        het type bestaat (struct/enum/class)
#   sig  <Naam> <regex> <wat>  binnen het type <Naam> (de eerste 3000 tekens na de declaratie) komt <regex> voor:
#                              dat is de handtekening (labels, typen). Een oud type met dezelfde naam maar een
#                              oude init slaagt hier dus niet.
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /home/user/MyBuddy)" || exit 2
WAVE="${1:-alles}"; MISSING=0
need() {
  if ! grep -rqE --include=*.swift "^[[:space:]]*((public|private|fileprivate|final) )*$1 $2\b" App; then echo "ONTBREEKT: $1 $2"; MISSING=1; fi
}
needs() { grep -rqE --include=*.swift -- "$1" App || { echo "ONTBREEKT: $2"; MISSING=1; }; }
sig() {
  local name="$1" re="$2" what="$3"
  if ! grep -rPzq --include=*.swift "(?s)(struct|enum|class|extension)[ ]+$name\b[^\n]*\{.{0,3000}?$re" App; then
    echo "HANDTEKENING KLOPT NIET: $name ($what)"; MISSING=1
  fi
}
absent() {  # absent <regex> <wat>   (alleen voor "final")
  local n; n=$(grep -rnE --include=*.swift -- "$1" App | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then echo "OVERGANGSVORM NOG AANWEZIG ($n): $2"; MISSING=1; fi
}
if [ "$WAVE" = 0 ] || [ "$WAVE" = alles ] || [ "$WAVE" = final ]; then
  # golf 0: 0A
  for n in AppDomain; do need enum $n; done
  for n in PageScaffold ListScaffold Card LinkCard SectionHeader NavigationRow BigAmount StatTile FigureRow AmountRow SymbolBadge \
           IconButton ActionButton ActionLink ActionGroup EmptyHint NoticeCard MonthBar PeriodPicker RowAction SheetScaffold \
           BlockOrderList BlockOrderSheet ProgressMeter SegmentedMeter; do need struct $n; done
  need enum BlockOrderMigration
  for s in 'static (let|var) canvas' 'static (let|var) textSecondary' 'static (let|var) accentFill' 'static (let|var) onAccent' \
           'static (let|var) chartExpenses' 'static (let|var) minTapTarget' 'func animated<' 'func rowActions\(' \
           'func blockOrderToolbar\(' 'func searchToolbarButton\('; do needs "$s" "$s"; done
  sig PageScaffold 'large\s*:\s*Bool' 'PageScaffold(title:large:)'
  sig ListScaffold 'large\s*:\s*Bool' 'ListScaffold(title:large:)'
  sig Card 'headerLink\s*:\s*Destination\?' 'Card(title:symbol:domain:subtitle:headerLink:)'
  sig Card 'domain\s*:\s*AppDomain\?' 'Card(domain:)'
  sig LinkCard 'destination\s*:\s*Destination' 'LinkCard(destination:)'
  sig LinkCard 'showsCurrentMonth\s*:\s*Bool' 'LinkCard(showsCurrentMonth:)'
  sig NavigationRow 'destination\s*:\s*Destination' 'NavigationRow(destination:)'
  sig ActionLink 'destination\s*:\s*Destination' 'ActionLink(destination:)'
  sig ActionButton 'prominent\s*:\s*Bool' 'ActionButton(prominent:)'
  sig IconButton 'symbol\s*:\s*String' 'IconButton(_ label:symbol:)'
  sig EmptyHint 'style\s*:\s*Style' 'EmptyHint(style:)'
  sig NoticeCard 'actionTitle\s*:\s*String\?' 'NoticeCard(text:symbol:actionTitle:action:)'
  sig MonthBar 'month\s*:\s*Binding<YearMonth>\?' 'MonthBar(month:)'
  sig SheetScaffold 'hasChanges\s*:\s*Bool' 'SheetScaffold(hasChanges:)'
  sig SheetScaffold 'saveChoices\s*:\s*SaveChoices\?' 'SheetScaffold(saveChoices:)'
  sig ProgressMeter 'value\s*:\s*Double\?' 'ProgressMeter(value: Double?)'
  sig ProgressMeter 'valueText\s*:\s*String' 'ProgressMeter(valueText:)'
  sig BigAmount 'label\s*:\s*String\?' 'BigAmount(label:)'
  sig BlockOrderList 'page\s*:\s*BlockPage' 'BlockOrderList(page:)'
  sig BlockOrderMigration 'static func migrate\(' 'BlockOrderMigration.migrate'
  # golf 0: 0B
  for n in AppTab SettingsPage Destination NavigationRules SearchIndex; do need enum $n; done
  need "final class" Router; need "final class" ActiveSession; need struct TabStack; need struct DestinationView
  sig NavigationRules 'static func normalize\(' 'NavigationRules.normalize'
  sig NavigationRules 'static func push\(' 'NavigationRules.push'
  sig NavigationRules 'static func go\(' 'NavigationRules.go'
  sig Router 'func go\(_' 'Router.go'
  sig Router 'func popToRoot\(_' 'Router.popToRoot'
  sig Router 'func pathBinding\(for' 'Router.pathBinding(for:)'
  sig Router 'var searchRequest' 'Router.searchRequest'
  sig ActiveSession 'func unregister\(store' 'ActiveSession.unregister(store:)'
  sig TabStack 'init\(_ tab' 'TabStack(_ tab:)'
  sig SettingsPage 'case importReview' 'SettingsPage.importReview'
  sig AppTab 'case[^\n]*\boverview\b[^\n]*\bmonth\b[^\n]*\bsaving\b[^\n]*\bplanning\b[^\n]*\bsettings\b' 'AppTab-cases'
  # golf 0: F
  for n in TrendChart StackedBarChart DonutChart DonutModel StackedBarModel; do need struct $n; done
  for n in ChartSize PortfolioTrend PriceTrend NetWorthTrend BankTrend DayBalanceTrend ProjectionTrend BufferTrend SavingsGoalTrend GoalCurveTrend PotTrend; do need enum $n; done
  sig TrendChart 'model\s*:\s*TrendModel' 'TrendChart(model:)'
  sig TrendChart 'nonNegative\s*:\s*Bool' 'TrendChart(nonNegative:)'
  sig StackedBarChart 'model\s*:\s*StackedBarModel' 'StackedBarChart(model:)'
  sig DonutChart 'model\s*:\s*DonutModel' 'DonutChart(model:)'
  needs 'var colorIndex' 'HoldingKind.colorIndex'; needs 'func potSeries\(' 'potSeries'
  needs 'var isEstimated' 'isEstimated (HoldingState, PortfolioPoint)'
  needs 'func portfolioDataStart\(' 'portfolioDataStart'
fi
if [ "$WAVE" = 1 ] || [ "$WAVE" = alles ] || [ "$WAVE" = final ]; then
  # golf 1
  for n in OverviewTab MonthTab SavingTab PlanningTab IncomePage SalaryPage ExpensesPage DistributePage BankPage UpcomingDaysCard PotsPage PotDetailPage \
           PortfolioPage HoldingDetailPage PotsSummaryCard PortfolioSummaryCard HomePotsCard HomeHoldingsCard FavoritePotsSheet FavoriteHoldingsSheet \
           GoalsPage GoalDetailPage SavingsGoalPage AcceleratorsPage BufferPage \
           ProjectionPage PurchasePage GoalsSummaryCard BufferSummaryCard AcceleratorsSummaryCard ProjectionSummaryCard PurchaseSummaryCard \
           SettingsView SettingsDestination SettingsPane SyncAttentionBanner AuthView GainBadge; do need struct $n; done
  need enum BankSection
  sig BankPage 'section\s*:\s*BankSection' 'BankPage(section:)'
  sig PotDetailPage 'potID\s*:\s*UUID' 'PotDetailPage(potID:)'
  sig HoldingDetailPage 'holdingID\s*:\s*UUID' 'HoldingDetailPage(holdingID:)'
  sig GoalDetailPage 'goalID\s*:\s*UUID' 'GoalDetailPage(goalID:)'
  sig SettingsDestination 'page\s*:\s*SettingsPage' 'SettingsDestination(page:)'
  sig SettingsPane 'page\s*:\s*SettingsPage' 'SettingsPane(page:)'
  sig MoneyLineSheet 'defaultExpenseKind\s*:\s*ExpenseKind' 'MoneyLineSheet(line:kind:month:defaultExpenseKind:)'
  sig GainBadge 'fraction\s*:\s*Double\?' 'GainBadge(gain:fraction:)'
  sig HoldingEditSheet 'holding\s*:\s*Holding\?' 'HoldingEditSheet(holding:)'
  sig PotEditSheet 'pot\s*:\s*Pot\?' 'PotEditSheet(pot:)'
  for n in OverviewTab MonthTab SavingTab PlanningTab; do sig $n 'var body' "$n() zonder parameters"; done
fi
if [ "$WAVE" = final ]; then
  absent 'homePath|savingsPath|toolsPath|showSettings' 'Router-compat of oude padnamen'
  absent 'GlassBlock\(|LinkedBlock\(|Chip(Button|Link|Grid|Label)\(|MeshBackground' 'compat-componenten'
  absent 'struct (HomeView|SavingsView|ToolsView)\b' 'oude tabroots'
  absent 'Theme\.(flow[A-Z]|olive|buttonHeight)' 'oude thematokens'
  absent 'case home, savings, tools|case \.home:|case \.savings:|case \.tools:' 'BlockPage-compatcases'
fi
[ "$MISSING" = 0 ] && echo "CONTRACT COMPLEET" || { echo "CONTRACT ONVOLLEDIG"; exit 1; }
