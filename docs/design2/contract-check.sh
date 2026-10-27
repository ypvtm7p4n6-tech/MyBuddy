#!/usr/bin/env bash
# Contractcontrole voor ontwerp 2: bestaat elk symbool uit par. 2.3 en 2.4 van docs/design2/plan.md met de goede handtekening?
# Gebruik: docs/design2/contract-check.sh [1|2|final] [--base <commit>]
#   1      na pakket 1 (fundament en schil): de bouwstenen, de componenten, de schil, de tijdelijke wortels; en: geen rekenwijziging
#          (`git diff --stat <basis> -- App/Core CoreTests/Sources` is leeg) en de test van opgeslagen gegevens bestaat.
#   2      bovendien na golf 2 (2A t/m 2D): Home, Bibliotheek, Zoeken en de nieuwe functies.
#   final  na pakket 3: bovendien mag geen overgangsvorm meer bestaan (oude padnamen, compat-typen, tijdelijke tabnamen).
# <basis> is de stand voor ontwerp 2 (standaard 1b98404, de laatste codecommit voor het plan; --base <commit> past dat aan).
# Twee soorten controle:
#   need <soort> <naam>        het type bestaat (struct/enum/class)
#   sig  <Naam> <regex> <wat>  binnen het type <Naam> (de eerste 15000 tekens na de declaratie) komt <regex> voor:
#                              dat is de handtekening (labels, typen). Een oud type met dezelfde naam maar een
#                              oude init slaagt hier dus niet.
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /home/user/MyBuddy)" || exit 2
WAVE="${1:-1}"; shift 2>/dev/null
BASE="1b98404"
if [ "${1:-}" = "--base" ]; then BASE="${2:-$BASE}"; fi
MISSING=0
need() {
  if ! grep -rqE --include=*.swift "^[[:space:]]*(@[A-Za-z]+(\([^)]*\))?[[:space:]]+)*((public|private|fileprivate|final) )*$1 $2\b" App; then echo "ONTBREEKT: $1 $2"; MISSING=1; fi
}
needs() { grep -rqE --include=*.swift -- "$1" App || { echo "ONTBREEKT: $2"; MISSING=1; }; }
sig() {
  local name="$1" re="$2" what="$3"
  if ! grep -rPzq --include=*.swift "(?s)(struct|enum|class|extension)[ ]+$name\b[^\n]*\{.{0,15000}?$re" App; then
    echo "HANDTEKENING KLOPT NIET: $name ($what)"; MISSING=1
  fi
}
absent() {  # absent <regex> <wat>   (alleen voor "final")
  local n; n=$(grep -rnE --include=*.swift -- "$1" App | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then echo "OVERGANGSVORM NOG AANWEZIG ($n): $2"; MISSING=1; fi
}
case "$WAVE" in 1|2|final) ;; *) echo "gebruik: contract-check.sh [1|2|final] [--base <commit>]"; exit 2 ;; esac

# ---- Bestaande bouwstenen blijven (par. 2.5) ----
for n in AppDomain; do need enum $n; done
for n in PageScaffold ListScaffold Card LinkCard SectionHeader NavigationRow BigAmount StatTile FigureRow AmountRow SymbolBadge \
         IconButton ActionButton ActionLink ActionGroup EmptyHint NoticeCard MonthBar PeriodPicker RowAction SheetScaffold \
         BlockOrderList BlockOrderSheet ProgressMeter SegmentedMeter; do need struct $n; done
need enum BlockOrderMigration
sig PageScaffold 'large\s*:\s*Bool' 'PageScaffold(title:large:)'
sig ListScaffold 'large\s*:\s*Bool' 'ListScaffold(title:large:)'
sig Card 'headerLink\s*:\s*Destination\?' 'Card(title:symbol:domain:subtitle:headerLink:)'
sig LinkCard 'showsCurrentMonth\s*:\s*Bool' 'LinkCard(showsCurrentMonth:)'
sig NavigationRow 'destination\s*:\s*Destination' 'NavigationRow(destination:)'
sig ActionButton 'prominent\s*:\s*Bool' 'ActionButton(prominent:)'
sig BigAmount 'label\s*:\s*String\?' 'BigAmount(label:)'
sig MonthBar 'month\s*:\s*Binding<YearMonth>\?' 'MonthBar(month:)'
for n in TrendChart StackedBarChart DonutChart; do need struct $n; done
sig TrendChart 'nonNegative\s*:\s*Bool' 'TrendChart(nonNegative:)'

# ---- Foundation-only bouwstenen (par. 2.3) ----
need enum TileHue; need struct TileColors; need enum TilePalette; need enum ShelfMetrics
need enum LibrarySection; need struct PageInfo; need enum PageCatalog; need enum SearchGroup
sig TileHue 'static func forIndex\(_ index: Int\) -> TileHue' 'TileHue.forIndex(_:)'
sig TileHue 'case olive, teal, mustard, terracotta, slate, plum, sage, brown' 'TileHue-cases in volgorde van Theme.palette'
sig TileColors 'let top: UInt32' 'TileColors.top'
sig TileColors 'let bottomHC: UInt32' 'TileColors.bottomHC'
sig TilePalette 'static func colors\(_ hue: TileHue\) -> TileColors' 'TilePalette.colors(_:)'
sig TilePalette 'static let canvasLight: UInt32 = 0xEEF1E2' 'TilePalette.canvasLight'
sig TilePalette 'static let backdropAlphaDark = 0\.55' 'TilePalette.backdropAlphaDark'
sig TilePalette 'static func luminance\(_ hex: UInt32\) -> Double' 'TilePalette.luminance'
sig TilePalette 'static func contrast\(_ a: UInt32, _ b: UInt32\) -> Double' 'TilePalette.contrast'
sig TilePalette 'static func blend\(_ fg: UInt32, over bg: UInt32, alpha: Double\) -> UInt32' 'TilePalette.blend'
sig ShelfMetrics 'static let heroPeek = 8\.0' 'ShelfMetrics.heroPeek'
sig ShelfMetrics 'static func margin\(compact: Bool\) -> Double' 'ShelfMetrics.margin'
sig ShelfMetrics 'static func spacing\(compact: Bool\) -> Double' 'ShelfMetrics.spacing'
sig ShelfMetrics 'static func tileWidth\(in length: Double, spacing: Double\) -> Double' 'ShelfMetrics.tileWidth'
sig ShelfMetrics 'static func wideTileWidth\(in length: Double, spacing: Double\) -> Double' 'ShelfMetrics.wideTileWidth'
sig ShelfMetrics 'static func heroWidth\(in length: Double, spacing: Double\) -> Double' 'ShelfMetrics.heroWidth'
sig ShelfMetrics 'static func showsHeroCarousel\(in length: Double\) -> Bool' 'ShelfMetrics.showsHeroCarousel'
sig LibrarySection 'case month, saving, planning' 'LibrarySection-cases'
sig PageInfo 'let reachableFrom: Destination\?' 'PageInfo.reachableFrom'
sig PageInfo 'let section: LibrarySection\?' 'PageInfo.section'
sig PageCatalog 'static let all: \[PageInfo\]' 'PageCatalog.all'
sig PageCatalog 'static var library: \[PageInfo\]' 'PageCatalog.library'
sig PageCatalog 'static func library\(in section: LibrarySection\) -> \[PageInfo\]' 'PageCatalog.library(in:)'
sig PageCatalog 'static func info\(_ destination: Destination\) -> PageInfo\?' 'PageCatalog.info(_:)'
sig PageCatalog 'static let browse: \[Destination\]' 'PageCatalog.browse'
sig SearchGroup 'case pages, pots, holdings, goals, lines, settings' 'SearchGroup-cases'
sig SearchEntry 'var hue: TileHue' 'SearchEntry.hue'
sig SearchEntry 'var group: SearchGroup' 'SearchEntry.group'
sig SearchIndex 'static func grouped\(for query: String, in data: FinanceData\)' 'SearchIndex.grouped(for:in:)'

# ---- Navigatie (par. 1.2, 2.3) ----
need enum AppTab; need enum Destination; need enum SettingsPage; need enum NavigationRules; need enum SearchIndex
need "final class" Router; need "final class" ActiveSession; need struct TabStack; need struct TabRoot; need struct DestinationView
need struct AppCommands; need struct SearchEntry; need struct SettingsScene; need struct RootView
sig AppTab 'case home, library, search' 'AppTab.home/library/search'
for c in flow tools settingsRoot; do sig Destination "case\\b[^\\n]*\\b$c\\b" "Destination.$c"; done
sig Destination 'case home, library' 'Destination.home/library'
sig Destination 'case settings\(SettingsPage\)' 'Destination.settings(_)'
sig Destination 'var parents: \[Destination\]' 'Destination.parents'
sig NavigationRules 'static func normalize\(' 'NavigationRules.normalize'
sig NavigationRules 'static func push\(' 'NavigationRules.push'
sig NavigationRules 'static func go\(_ destination: Destination, from current: AppTab, path: \[Destination\]\)' 'NavigationRules.go(_:from:path:)'
sig Router 'var tab: AppTab' 'Router.tab'
sig Router 'var paths: \[AppTab: \[Destination\]\]' 'Router.paths'
sig Router 'func pathBinding\(for tab: AppTab\) -> Binding<\[Destination\]>' 'Router.pathBinding(for:)'
sig Router 'func select\(_' 'Router.select'
sig Router 'func popToRoot\(_' 'Router.popToRoot'
sig Router 'func open\(_ destination: Destination\)' 'Router.open'
sig Router 'func go\(_ destination: Destination\)' 'Router.go'
sig Router 'func requestSearch\(\)' 'Router.requestSearch'
sig Router 'func showCurrentMonth\(_' 'Router.showCurrentMonth'
sig Router 'func shiftPeriod\(_' 'Router.shiftPeriod'
sig Router 'func resetFocus\(to' 'Router.resetFocus'
sig Router 'var searchRequest' 'Router.searchRequest'
sig Router 'var settingsRequest: SettingsPage\?' 'Router.settingsRequest'
sig Router 'var orderPage: BlockPage\?' 'Router.orderPage'
sig TabStack 'init\(_ tab' 'TabStack(_ tab:)'
sig ActiveSession 'func unregister\(store' 'ActiveSession.unregister(store:)'
sig BlockPage '\s*case overview\s+var id: String' 'BlockPage heeft alleen .overview (allCases == [.overview])'
sig BlockPage 'BlockInfo\(id: "upcoming"' 'BlockPage.overview: upcoming'
sig BlockPage 'BlockInfo\(id: "tools"' 'BlockPage.overview: tools'

# ---- Kleur en maten (par. 2.1, 2.4: Theme.swift) ----
sig TileHue 'var top: Color' 'TileHue.top'
sig TileHue 'var bottom: Color' 'TileHue.bottom'
sig TileHue 'var gradient: LinearGradient' 'TileHue.gradient'
sig AppDomain 'var hue: TileHue' 'AppDomain.hue'
for s in 'static let onTile\b' 'static let onTileSecondary\b' 'static let heroRadius: CGFloat = 28' 'static let cardRadius: CGFloat = 20' \
         'static let tileRadius: CGFloat = 12' 'static let shelfMaxWidth: CGFloat = 1120' 'static let backdropHeight: CGFloat = 420' \
         'static func hue\(_ paletteIndex: Int\) -> TileHue'; do sig Theme "$s" "Theme: $s"; done
sig EnvironmentValues 'var backdropHue: TileHue' 'EnvironmentValues.backdropHue'
sig EnvironmentValues 'var tileHue: TileHue' 'EnvironmentValues.tileHue'
sig PageScaffold 'var fullBleed' 'PageScaffold(fullBleed:)'

# ---- SwiftUI-componenten (par. 2.4) ----
for n in BackdropGradient GradientSurface ArtworkTile PosterCard ShelfCard BrowseTile TilePressStyle ShelfAction Shelf HeroCarousel HeroCard \
         MediaRowLabel MediaRow AlbumHeader PillButton PillLink PillRow ProfileButton DestinationLink; do need struct $n; done
need enum ArtworkSize; need enum PillStyle
sig BackdropGradient 'init\(hue: TileHue = \.olive\)' 'BackdropGradient(hue:)'
sig GradientSurface 'init\(hue: TileHue, radius: CGFloat = Theme\.tileRadius, @ViewBuilder content' 'GradientSurface(hue:radius:content:)'
sig ArtworkSize 'case row, fill, header' 'ArtworkSize-cases'
sig ArtworkTile 'init\(symbol: String, hue: TileHue, size: ArtworkSize = \.fill, progress: Double\? = nil, progressLabel: String\? = nil\)' 'ArtworkTile.init'
sig PosterCard 'init\(symbol: String, hue: TileHue, title: String, subtitle: String\? = nil, value: String\? = nil,' 'PosterCard.init'
sig PosterCard 'progress: Double\? = nil, progressLabel: String\? = nil, destination: Destination\? = nil,' 'PosterCard.init (vervolg)'
sig PosterCard 'showsCurrentMonth: Bool = false, action: \(\(\) -> Void\)\? = nil\)' 'PosterCard.init (einde)'
sig ShelfCard 'init\(hue: TileHue\? = nil, destination: Destination\? = nil, showsCurrentMonth: Bool = false,' 'ShelfCard.init'
sig BrowseTile 'init\(title: String, symbol: String, hue: TileHue, destination: Destination,' 'BrowseTile.init'
sig BrowseTile 'showsCurrentMonth: Bool = false, opensViaRouter: Bool = false\)' 'BrowseTile.init (showsCurrentMonth, opensViaRouter)'
sig ShelfAction 'init\(_ title: String, symbol: String, role: ButtonRole\? = nil, action: @escaping \(\) -> Void\)' 'ShelfAction.init'
sig Shelf 'init\(_ title: String, subtitle: String\? = nil, showAll: Destination\? = nil, showAllLabel: String\? = nil,' 'Shelf.init'
sig Shelf 'showAllShowsCurrentMonth: Bool = false,' 'Shelf.init (showAllShowsCurrentMonth)'
sig Shelf 'actions: \[ShelfAction\] = \[\], orderID: String\? = nil, wide: Bool = false,' 'Shelf.init (vervolg)'
sig Shelf 'items: \[Item\], @ViewBuilder tile: @escaping \(Item\) -> Tile\)' 'Shelf.init (einde)'
sig HeroCarousel 'init\(ids: \[String\], selection: Binding<String\?>\? = nil, @ViewBuilder card: @escaping \(String\) -> Card\)' 'HeroCarousel.init'
sig HeroCard 'init\(hue: TileHue, eyebrow: String, symbol: String, @ViewBuilder content: \(\) -> Content, @ViewBuilder pills: \(\) -> Pills\)' 'HeroCard.init'
sig HeroCard 'init\(hue: TileHue, eyebrow: String, symbol: String, @ViewBuilder content: \(\) -> Content\)' 'HeroCard.init zonder pillen'
needs 'func heroPanel\(\) -> some View' 'View.heroPanel()'
sig MediaRowLabel 'init\(symbol: String, hue: TileHue, title: String, subtitle: String\? = nil, value: String\? = nil,' 'MediaRowLabel.init'
sig MediaRowLabel 'valueColor: Color = \.primary, progress: Double\? = nil, showsChevron: Bool = false\)' 'MediaRowLabel.init (einde)'
sig MediaRow 'valueColor: Color = \.primary, progress: Double\? = nil, destination: Destination,' 'MediaRow.init'
sig MediaRow 'showsCurrentMonth: Bool = false\)' 'MediaRow.init (einde)'
sig AlbumHeader 'init\(symbol: String, hue: TileHue, title: String, subtitle: String\? = nil, figureLabel: String\? = nil,' 'AlbumHeader.init'
sig AlbumHeader 'figure: Double\? = nil, figureColor: Color = \.primary, progress: Double\? = nil, progressLabel: String\? = nil,' 'AlbumHeader.init (vervolg)'
sig AlbumHeader 'facts: \[String\] = \[\], @ViewBuilder pills: \(\) -> Pills, @ViewBuilder extra: \(\) -> Extra\)' 'AlbumHeader.init (einde)'
needs 'func albumHeaderRow\(\) -> some View' 'View.albumHeaderRow()'
sig PillStyle 'case prominent, secondary, onTile' 'PillStyle-cases'
sig PillButton 'init\(_ title: String, symbol: String\? = nil, style: PillStyle = \.secondary, role: ButtonRole\? = nil,' 'PillButton.init'
sig PillLink 'init\(_ title: String, symbol: String\? = nil, style: PillStyle = \.secondary, destination: Destination,' 'PillLink.init'
sig PillRow 'init\(spacing: CGFloat = 8' 'PillRow.init'
sig ProfileButton 'init\(\)' 'ProfileButton()'
needs 'func profileToolbarItem\(\) -> some View' 'View.profileToolbarItem()'

# ---- Tijdelijke wortels en nieuwe pagina's (pakket 1) ----
for n in HomeTab LibraryTab SearchTab FlowPage ToolsPage; do need struct $n; sig $n 'var body' "$n()"; done

# ---- Sheets die golf 2 laat staan (par. 4) ----
sig PotEditSheet 'pot\s*:\s*Pot\?' 'PotEditSheet(pot:)'
sig HoldingEditSheet 'holding\s*:\s*Holding\?' 'HoldingEditSheet(holding:)'
for n in FavoritePotsSheet FavoriteHoldingsSheet BankActionSheet PotEntrySheet ValueUpdateSheet GoalEditSheet; do need struct $n; done
sig BankActionSheet 'action' 'BankActionSheet(action:)'
sig PotEntrySheet 'action' 'PotEntrySheet(pot:action:)'

# ---- Geen rekenwijziging, bewaarde gegevens (par. 5.3) ----
changes=$(git diff --stat "$BASE" -- App/Core CoreTests/Sources 2>/dev/null | tail -n 1)
if [ -n "$changes" ]; then echo "REKENWIJZIGING: App/Core of CoreTests/Sources is veranderd sinds $BASE: $changes"; MISSING=1; fi
if ! grep -q "func testAnOldBlockOrderWithEveryKeyLoadsOnHome" CoreTests/Tests/MyBuddyCoreTests/BlockOrderMigrationTests.swift 2>/dev/null; then
  echo "ONTBREEKT: de test van opgeslagen gegevens in BlockOrderMigrationTests (oude blockOrder laadt op Home)"; MISSING=1
fi

# ---- Golf 2 ----
if [ "$WAVE" = 2 ] || [ "$WAVE" = final ]; then
  need enum UpcomingDaysWindow
  needs 'static func nextPayment\(in book: LedgerBook, today: Date\)' 'UpcomingDaysWindow.nextPayment(in:today:)'
  need struct RecentItem; need enum RecentActivity
  sig RecentActivity 'static func items\(in data: FinanceData, asOf: Date, limit: Int = 5\) -> \[RecentItem\]' 'RecentActivity.items(in:asOf:limit:)'
  for n in HomeTab LibraryTab SearchTab FlowPage ToolsPage; do absent "TIJDELIJK[^\n]* wortel van|TIJDELIJKE wortel" "tijdelijke wortel nog aanwezig ($n)"; break; done
fi

# ---- Na pakket 3 ----
if [ "$WAVE" = final ]; then
  absent 'homePath|savingsPath|toolsPath|showSettings' 'Router-compat of oude padnamen'
  absent 'GlassBlock|LinkedBlock|Chip(Button|Link|Grid|Label)\b|MeshBackground|ProgressRing|ProgressBar|SegmentBar' 'compat-componenten'
  absent 'Theme\.(flow[A-Z]|olive|buttonHeight|chipRadius)|static let (olive|flow[A-Z])|buttonHeight' 'oude thematokens'
  absent 'searchToolbarButton|PeriodControl|TabPressStyle|TabAmountLink' 'oude zoekknop en tabhulpen'
  absent 'static var (overview|month|saving|planning): AppTab' 'tijdelijke tabnamen (LegacyTabNames)'
  absent 'case home, savings, tools|BlockPage\.(month|saving|planning|home|savings|tools)\b|isLegacy|OrderedBlocks|blockOrderToolbar' 'BlockPage-compatcases en blokvolgorde-compat'
  absent '\b(HomePotsCard|HomeHoldingsCard|UpcomingDaysCard|FavoriteTileGrid|FavoritePotTile|FavoriteHoldingTile|FavoriteSlotTile|PotsSummaryCard|PortfolioSummaryCard|GoalsSummaryCard|BufferSummaryCard|AcceleratorsSummaryCard|ProjectionSummaryCard|PurchaseSummaryCard|EqualSizeGrid)\b' 'oude kaarten, tegels en hun raster'
  absent '\b(OverviewTab|MonthTab|SavingTab|PlanningTab|OverviewHero|OverviewWealthCard|OverviewWelcome|OverviewCheckBanner|MonthFlowCard)\b' 'oude tabroots en hun kaarten'
  absent 'TimeLineChart|FlowChart|AllocationDonut|TimePoint|chartAxes|glassCard|glassButton|showsSettings' 'oude grafiek- en glascompat'
  if [ -d App/Pages/Tabs ]; then echo "OVERGANGSVORM NOG AANWEZIG: App/Pages/Tabs"; MISSING=1; fi
fi
[ "$MISSING" = 0 ] && echo "CONTRACT COMPLEET" || { echo "CONTRACT ONVOLLEDIG"; exit 1; }
