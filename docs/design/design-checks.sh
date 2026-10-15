#!/usr/bin/env bash
# Ontwerpcontrole voor MyBuddy. Gebruik: scripts/design-checks.sh [pad ...]   (zonder pad: heel App/)
# Elke regel: naam | verwachting | aantal gevonden | PASS/FAIL. Exit 1 bij een FAIL.
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /home/user/MyBuddy)"
SCOPE=("${@:-App}")
FAIL=0
# chk <naam> <max|min:N|eq:N> <regex> [uitgezonderd-bestand-regex]
chk() {
  local name="$1" rule="$2" re="$3" skip="${4:-^$}"
  local n; n=$(grep -rnE --include=*.swift -- "$re" "${SCOPE[@]}" 2>/dev/null | grep -vE "$skip" | wc -l | tr -d ' ')
  local ok=0
  case "$rule" in
    0)     [ "$n" -eq 0 ] && ok=1 ;;
    min:*) [ "$n" -ge "${rule#min:}" ] && ok=1 ;;
    max:*) [ "$n" -le "${rule#max:}" ] && ok=1 ;;
  esac
  report "$name" "$rule" "$n" "$ok"
}
report() {
  local verdict=PASS; [ "$4" = 1 ] || { verdict=FAIL; FAIL=1; }
  printf '%-52s verwacht %-7s gevonden %-4s %s\n' "$1" "$2" "$3" "$verdict"
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
chk "krimpende tekst buiten Components"    0 'minimumScaleFactor' 'App/UI/Components.swift'
chk "lichte lettergewichten"               0 'weight\(\.(light|thin|ultraLight)\)|\.fontWeight\(\.(light|thin|ultraLight)\)'
chk "HOOFDLETTERS in de UI"                0 '\.uppercased\(\)'
chk "vaste hoogte 20-43 pt op knop/rij"    0 '\.frame\((width|height|minHeight|minWidth): *(2[0-9]|3[0-9]|4[0-3])(\.0)?\)' 'App/UI/Charts.swift|Components.swift'
echo "== Kleur en glas"
chk "Color(hex: buiten Theme"              0 'Color\(hex:' 'App/UI/Theme.swift'
chk "Color(red:/UIColor( buiten Theme"     0 'Color\(red:|UIColor\(|NSColor\(' 'App/UI/Theme.swift'
chk ".secondary als tekst/pictogramkleur"  0 'foregroundStyle\(\.secondary\)|Color\.secondary|foregroundColor\(\.secondary\)'
chk "wit als voorgrond"                    0 'foregroundStyle\(\.white\)|foregroundStyle\(Color\.white\)|foregroundColor\(\.white\)'
chk "glas op inhoud (glassCard/Surface/Effect)" 0 'glassCard\(|glassSurface\(|\.glassEffect\(' 'App/UI/Glass.swift|App/UI/Charts.swift'
chk "oude glasblokken (GlassBlock/LinkedBlock)" 0 'GlassBlock\(|LinkedBlock\(' 'App/UI/Components.swift'
chk "oude chips (ChipButton/Link/Grid/Label)"   0 'Chip(Button|Link|Grid|Label)\(' 'App/UI/Components.swift'
chk "MeshBackground"                       0 'MeshBackground' 'App/UI/Theme.swift'
chk "tint op kaart (tint: Theme.olive)"    0 'tint: *Theme\.olive'
echo "== Navigatie en sheets"
chk "Instellingen als sheet / showSettings" 0 'showSettings|SettingsView\(\) *\}|sheet\(.*Settings'
chk "eigen tabbalk"                        0 'GlassTabBar|barBackdrop'
chk "TabView aanwezig (app + Mac-instellingen)" min:2 'TabView *[\(\{]'
chk "TabView niet vaker dan 3"             max:3 'TabView *[\(\{]'
chk ".sheet( in de hele app (nu 26)"       max:16 '\.sheet\('
chk "alert()"                              0 '\.alert\('
chk "apparaattype als layoutkeuze"         0 'UIDevice|userInterfaceIdiom|UIScreen'
chk "navigationBarTitleDisplayMode buiten Components" 0 'navigationBarTitleDisplayMode' 'App/UI/Components.swift'
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
chk "oude grafiektypen"                    0 'TimeLineChart|FlowChart|AllocationDonut|DayBalanceChart|BufferChart|SavingsGoalChart|GoalCurveChart|ProgressBar\(|ProgressRing\(|SegmentBar\(' 'App/UI/Components.swift'
echo "== Taal (termenlijst)"
chk "Engelse tabnamen/oude termen"         0 '"(Home|Savings|Tools)"|Portefeuille|Mijn beleggingen|Salaris & inkomsten|Bankuitgaven|Saldo nu|Bankbuffer|Spaarpot Buffer|Kies potten|Kies beleggingen|Per dag bekijken|Dag voor dag bekijken|Alle dagen bekijken|Meetpunt|vaste lasten|Buffer op bankrekening'
echo "== Instellingen en account: geen sheets (alleen bij een volledige run)"
if [ "$#" -eq 0 ]; then
  SET=(App/Pages/Settings App/Pages/SettingsView.swift App/Auth App/Cloud App/UI/BackupUI.swift App/UI/MarketDataUI.swift)
  n=$(grep -rnE --include=*.swift '\.sheet\(|\.fullScreenCover\(' "${SET[@]}" 2>/dev/null | wc -l | tr -d ' ')
  ok=0; [ "$n" -eq 0 ] && ok=1; report "sheet in Instellingen/Account/Back-up" 0 "$n" "$ok"
  n=$(grep -rnE --include=*.swift 'Theme\.buttonHeight' App 2>/dev/null | wc -l | tr -d ' ')
  ok=0; [ "$n" -eq 0 ] && ok=1; report "Theme.buttonHeight (moet minTapTarget zijn)" 0 "$n" "$ok"
fi
echo
[ "$FAIL" = 0 ] && echo "ALLES PASS" || { echo "ER ZIJN FAILS"; exit 1; }
