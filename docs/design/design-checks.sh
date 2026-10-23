#!/usr/bin/env bash
# Ontwerpcontrole voor MyBuddy (docs/design/plan.md, par. 7.2, aangevuld met par. 5.2 van docs/design2/plan.md).
# Gebruik: docs/design/design-checks.sh [--final] [pad ...]     (zonder pad: heel App/)   (scripts/design-checks.sh is een kopie)
#   zonder --final : tijdens de bouw. Overgangsvormen (compat-laag, de oude tabroots in Pages/Tabs, de oude kaarten) tellen niet mee.
#   met --final    : oplevering (pakket 3 van ontwerp 2). Geen enkele overgangsvorm mag nog bestaan.
# Elke regel: naam | verwachting | aantal gevonden | PASS/FAIL. Exit 1 bij een FAIL.
# Regels met "min:N" gelden alleen bij een volledige run (zonder pad): een los bestand hoeft niet alles te bevatten.
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /home/user/MyBuddy)" || exit 2
FINAL=0; [ "${1:-}" = "--final" ] && { FINAL=1; shift; }
FULL=0; [ "$#" -eq 0 ] && FULL=1
SCOPE=("${@:-App}")
FAIL=0
report() {
  local verdict=PASS; [ "$4" = 1 ] || { verdict=FAIL; FAIL=1; }
  printf '%-58s verwacht %-7s gevonden %-4s %s\n' "$1" "$2" "$3" "$verdict"
}
# chk <naam> <0|max:N|min:N> <regex> [structureel-uitgezonderd-bestand-regex] [overgang-uitgezonderd-bestand-regex]
#   structureel: bestanden waar het patroon hoort te staan (altijd uitgezonderd).
#   overgang   : bestanden die pas in pakket G schoon zijn (alleen uitgezonderd zonder --final).
chk() {
  local name="$1" rule="$2" re="$3" skip="${4:-^\$}" trans="${5:-^\$}"
  [ "$FINAL" = 1 ] && trans='^$'
  case "$rule" in min:*) [ "$FULL" = 1 ] || return 0 ;; esac
  local n; n=$(grep -rnHE --include=*.swift -- "$re" "${SCOPE[@]}" 2>/dev/null | grep -vE "$skip" | grep -vE "$trans" | wc -l | tr -d ' ')
  local ok=0
  case "$rule" in
    0)     [ "$n" -eq 0 ] && ok=1 ;;
    min:*) [ "$n" -ge "${rule#min:}" ] && ok=1 ;;
    max:*) [ "$n" -le "${rule#max:}" ] && ok=1 ;;
  esac
  report "$name" "$rule" "$n" "$ok"
}
# Meerregelig (PCRE): een pictogram-alleen-knop zonder IconButton
chkml() {
  local name="$1" re="$2"
  local n; n=$(grep -rPzo --include=*.swift -- "$re" "${SCOPE[@]}" 2>/dev/null | tr '\0' '\n' | grep -c "Button" )
  local ok=0; [ "$n" -eq 0 ] && ok=1
  report "$name" 0 "$n" "$ok"
}
echo "== Typografie en maten"
chk "vaste lettergrootte"                  0 '\.font\(\.system\(size'
chk "caption2 (11 pt)"                     0 '\.caption2'
chk "afgeronde cijfers (design: .rounded)" 0 'design: *\.rounded'
chk "krimpende tekst buiten BigAmount"     0 'minimumScaleFactor' 'App/UI/Components.swift'
chk "lichte lettergewichten"               0 'weight\(\.(light|thin|ultraLight)\)|\.fontWeight\(\.(light|thin|ultraLight)\)'
# App/Core normaliseert hier tickers en valutacodes (invoer), er staat geen UI-tekst.
chk "HOOFDLETTERS in de UI"                0 '\.uppercased\(\)' 'App/Core/'
chk "vaste hoogte 20-43 pt op knop/rij"    0 '\.frame\((width|height|minHeight|minWidth): *(2[0-9]|3[0-9]|4[0-3])(\.0)?\)' 'App/UI/Charts.swift|App/UI/Components.swift|App/UI/Meters.swift'
chk "minTapTarget bestaat (iOS 44, macOS 28)" min:1 'minTapTarget'
echo "== Kleur en glas"
chk "Color(hex: buiten Theme"              0 'Color\(hex:' 'App/UI/Theme.swift'
chk "Color(red:/UIColor( buiten Theme"     0 'Color\(red:|UIColor\(|NSColor\(' 'App/UI/Theme.swift'
chk ".secondary als tekst/pictogramkleur"  0 'foregroundStyle\(\.secondary\)|Color\.secondary|foregroundColor\(\.secondary\)'
# Ontwerp 2: wit en zwart zijn tokens (Theme.onTile, Theme.heroPanelFill); `\b` laat `.whitespaces` ongemoeid.
chk "wit/zwart als kleur (.white/.black/Color.white)" 0 '(Color)?\.(white|black)\b' 'App/UI/Theme\.swift'
chk "glas op inhoud (glassCard/Surface/Effect)" 0 'glassCard\(|glassSurface\(|\.glassEffect\(' 'App/UI/Glass.swift' 'App/UI/Charts.swift'
chk "oude glasblokken (GlassBlock/LinkedBlock)" 0 'GlassBlock\(|LinkedBlock\(' '^$' 'App/UI/Components.swift'
chk "oude chips (ChipButton/Link/Grid/Label)"   0 'Chip(Button|Link|Grid|Label)\(' '^$' 'App/UI/Components.swift'
chk "MeshBackground"                       0 'MeshBackground' '^$' 'App/UI/Theme.swift|App/UI/Components.swift'
chk "oude tinten (Theme.olive*, Theme.flow*)" 0 'Theme\.(olive|oliveDeep|oliveLight|flow[A-Z][a-z]+)\b' '^$' 'App/UI/Theme.swift|App/UI/Charts.swift'
chk "Theme.buttonHeight (moet minTapTarget zijn)" 0 'Theme\.buttonHeight' '^$' 'App/UI/Theme.swift|App/UI/Components.swift'
echo "== Navigatie en sheets"
chk "Instellingen als sheet / showSettings" 0 'showSettings|SettingsView\(\) *\}|sheet\(.*Settings' '^$' 'App/Router.swift'
chk "oude padnamen (homePath/savingsPath/toolsPath)" 0 'homePath|savingsPath|toolsPath' '^$' 'App/Router.swift|App/Debug/DebugLaunch.swift'
chk "eigen tabbalk"                        0 'GlassTabBar|barBackdrop'
chk "TabView aanwezig (app + Mac-instellingen)" min:2 'TabView *[\(\{]'
chk "TabView niet vaker dan 3"             max:3 'TabView *[\(\{]'
# Home krijgt er drie nieuwe; de oude kaarten (nog in gebruik tot pakket 3) tellen niet-final niet mee. De eindstand is weer 16.
chk ".sheet( in de hele app (nu 26)"       max:16 '\.sheet\(' '^$' 'App/Pages/Tabs/|App/Pages/Saving/FavoriteCards\.swift|App/Pages/Bank/UpcomingDays\.swift'
chk "alert()"                              0 '\.alert\('
# UIDevice in SyncController is het apparaatlabel van de synchronisatie (een naam), geen layoutkeuze.
chk "apparaattype als layoutkeuze"         0 'UIDevice|userInterfaceIdiom|UIScreen' 'App/Cloud/SyncController\.swift:[0-9]+:.*UIDevice'
chk "navigationBarTitleDisplayMode buiten Components" 0 'navigationBarTitleDisplayMode' 'App/UI/Components.swift'
chk "veeg-om-te-sluiten bij wijzigingen"  min:1 'interactiveDismissDisabled'
chk "zoeken (searchable)"                  min:1 '\.searchable\('
chk "Settings-scene (macOS)"               min:1 '^[[:space:]]*Settings[[:space:]]*\{'
echo "== Ontwerp 2: schil, planken en kleurverloop"
chk "zoektab (Tab(value: AppTab.search, role: .search)" min:1 'Tab\(value: AppTab\.search, role: \.search'
chk "geen tab Instellingen"                0 'Tab\("Instellingen"'
chk "profielknop op de tabwortels"         min:3 'profileToolbarItem\(\)'
chk "planken (Shelf)"                      min:5 '[^A-Za-z]Shelf\('
chk "albumkoppen (AlbumHeader)"            min:3 'AlbumHeader\('
chk "hero-carrousel (HeroCarousel)"        min:1 'HeroCarousel\('
# De galerij en de previews (alleen debug) tonen het kleurverloop los van een pagina.
chk "BackdropGradient( alleen in Backdrop/Components" 0 'BackdropGradient\(' 'App/UI/Backdrop\.swift|App/UI/Components\.swift|App/UI/TileGallery\.swift|App/UI/DesignPreviews\.swift'
chk "scrollTargetBehavior alleen in Shelf/Hero" 0 'scrollTargetBehavior' 'App/UI/Shelf\.swift|App/UI/Hero\.swift'
chk "Destination.tab en de oude AppTab-cases" 0 'destination\.tab\b|AppTab\.(overview|month|saving|planning|settings)\b'
# Alleen met --final: de oude tabroots, de oude zoekknop en de tijdelijke namen van de schil zijn weg.
chk "oude zoekknop, PeriodControl, TabPressStyle (final)" 0 'searchToolbarButton|PeriodControl|TabPressStyle' '^$' 'App/Pages/Tabs/|App/UI/Components\.swift'
chk "tijdelijke tabnamen (LegacyTabNames)" 0 'static var (overview|month|saving|planning): AppTab' '^$' 'App/Navigation/LegacyTabNames\.swift'
if [ "$FINAL" = 1 ]; then
  n=$(find App/Pages/Tabs -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')
  ok=0; [ "$n" -eq 0 ] && ok=1; report "Pages/Tabs bestaat niet meer (final)" 0 "$n" "$ok"
fi
echo "== Toegankelijkheid en beweging"
chk "animation(Theme.motion buiten Components" 0 '\.animation\(Theme\.(motion|quickMotion)' 'App/UI/Components.swift|App/UI/Motion.swift'
chk "Reduce Motion gelezen"                min:1 'accessibilityReduceMotion'
chk "Reduce Transparency gelezen"          min:1 'accessibilityReduceTransparency'
chk "koppen (isHeader)"                    min:8 'isHeader|accessibilityHeading'
chk "haptiek (sensoryFeedback)"            min:5 'sensoryFeedback'
chk "swipe-acties op rijen"                min:6 'swipeActions|rowActions\('
chk "contextmenu / rowActions"             min:6 'contextMenu|rowActions\('
chk "lege staat (ContentUnavailableView)"  min:3 'ContentUnavailableView'
chk "ellipsis.circle als rijmenu"          0 'ellipsis\.circle' 'toolbar|Toolbar'
chkml "icoonknop zonder IconButton"        'Button[^{]{0,80}\{[^}]{0,200}\}\s*label:\s*\{\s*Image\(systemName'
echo "== Grafieken"
chk "import Charts buiten Charts.swift"    0 'import Charts' 'App/UI/Charts.swift'
chk "Chart( buiten Charts.swift"           0 '[^a-zA-Z]Chart *[\(\{]' 'App/UI/Charts.swift'
chk "accessibilityChartDescriptor"         min:3 'accessibilityChartDescriptor'
chk "oude grafiektypen"                    0 'TimeLineChart|FlowChart|AllocationDonut|DayBalanceChart|BufferChart|SavingsGoalChart|GoalCurveChart|ProgressBar\(|ProgressRing\(|SegmentBar\(' '^$' 'App/UI/Components.swift|App/UI/Charts.swift'
echo "== Verhuisde of herbouwde typen (par. 6.6): de oude namen bestaan niet meer"
chk "NoticeBanner (nu NoticeCard)"         0 '\bNoticeBanner\b'
chk "GainLabel (nu GainBadge)"             0 '\bGainLabel\b'
chk "Home-keuzebladen onder oude naam"     0 '\b(PotPickerSheet|HoldingPickerSheet|PotMiniTile|EmptySlotTile|HoldingTile|PotsTotals)\b'
chk "MonthPickerBlock (nu MonthBar)"       0 '\bMonthPickerBlock\b'
echo "== Taal (termenlijst)"
# ImportMapping.swift herkent oude invoerwoorden (vaste lasten, ...) in bestanden van gebruikers; wat de gebruiker ziet is aangepast.
# Ontwerp 2: "Home" is de tabnaam (B2) en dus toegestaan; het woord "Overzicht" als pagina- of tabnaam vervalt (`Importoverzicht` mag).
chk "Engelse tabnamen/oude termen"         0 '"(Savings|Tools)"|Portefeuille|Mijn beleggingen|Salaris & inkomsten|Bankuitgaven|Saldo nu|Bankbuffer|Spaarpot Buffer|Per dag bekijken|Dag voor dag bekijken|Alle dagen bekijken|Meetpunt|vaste lasten|Buffer op bankrekening' 'App/Core/ImportMapping\.swift'
# De tests in CoreTests controleren juist dat het woord er niet in zit, dus daar staat de letterlijke tekst.
chk "het woord Overzicht als titel (B2)"   0 '"Overzicht"' 'CoreTests/' 'App/Pages/Tabs/'
echo "== Instellingen en account: geen sheets (alleen bij een volledige run)"
if [ "$FULL" = 1 ]; then
  SET=(App/Pages/Settings App/Pages/SettingsView.swift App/Auth App/Cloud App/UI/BackupUI.swift App/UI/MarketDataUI.swift)
  n=$(grep -rnE --include=*.swift '\.sheet\(|\.fullScreenCover\(' "${SET[@]}" 2>/dev/null | wc -l | tr -d ' ')
  ok=0; [ "$n" -eq 0 ] && ok=1; report "sheet in Instellingen/Account/Back-up" 0 "$n" "$ok"
fi
echo
[ "$FAIL" = 0 ] && echo "ALLES PASS" || { echo "ER ZIJN FAILS"; exit 1; }
