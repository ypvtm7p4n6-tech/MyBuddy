#!/bin/bash
# Maakt screenshots van alle schermen in de iOS Simulator (debug-modus met voorbeelddata).
# Gebruik: scripts/ci-screenshots.sh [uitvoermap]
#
# De launch-argumenten staan in App/Debug/DebugLaunch.swift; dit script gebruikt alleen argumenten die daar bestaan:
#   -mybuddy-demo              voorbeelddata
#   -mybuddy-tab home|library|search      de tab (de oude namen overview, month, saving, planning, savings en tools werken nog als alias)
#   -mybuddy-open <pagina>     opent een pagina op de stapel van de tab (flow, tools, income, bank, pot0, goal0, layout, ...)
#   -mybuddy-hero 0|1|2        Home opent op hero-kaart 0, 1 of 2 (Nog te verdelen, Vermogen, Saldo vandaag)
#   -mybuddy-settings          pusht Instellingen op de stapel van de tab
#   -mybuddy-order home        opent het blad "Volgorde aanpassen" van Home
#   -mybuddy-period year       de periode van de maandpagina's
#   -mybuddy-scroll <punten>   schuift een pagina van kaarten (Home, Maandoverzicht, rekenpagina's) omhoog
#   -mybuddy-scroll-to <kop>   scrolt een lijstpagina naar de sectie met die koptekst (alleen koppen die bestaan, niet de maandkop)
set -euo pipefail

OUT="${1:-screenshots}"
mkdir -p "$OUT"
BUNDLE="nl.mybuddy.app"

udid_for() {
  # $1 = regex op de apparaatnaam, bijv. "iPhone 17 Pro \("
  xcrun simctl list devices available | grep -E "$1" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' || true
}

IPHONE=$(udid_for "iPhone 1[0-9] Pro \(")
[ -n "$IPHONE" ] || IPHONE=$(udid_for "iPhone [0-9]+ \(")
SMALL=$(udid_for "iPhone SE")
IPAD=$(udid_for "iPad Pro 1[0-9]")
[ -n "$IPAD" ] || IPAD=$(udid_for "iPad")
echo "iPhone=$IPHONE small=$SMALL ipad=$IPAD"

echo "== bouwen =="
xcodebuild -project MyBuddy.xcodeproj -scheme MyBuddy -destination "id=$IPHONE" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP=$(find build/Build/Products -maxdepth 3 -name MyBuddy.app | head -1)
echo "app=$APP"

shoot_device() {
  local udid="$1" label="$2" appearance="$3"
  [ -n "$udid" ] || { echo "geen apparaat voor $label"; return 0; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance "$appearance" || true
  xcrun simctl install "$udid" "$APP"
  shot() {
    local name="$1"; shift
    xcrun simctl terminate "$udid" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$udid" "$BUNDLE" -mybuddy-demo "$@" >/dev/null
    sleep 3
    xcrun simctl io "$udid" screenshot "$OUT/${label}-${appearance}-${name}.png" >/dev/null
  }

  # De drie tabs. Home: de drie hero-kaarten (de achtergrond volgt de zichtbare kaart) en de planken eronder; met
  # -mybuddy-scroll zie je ook de onderste plank, die de tabbalk niet mag afdekken.
  shot home -mybuddy-tab home -mybuddy-hero 0
  shot home-hero1 -mybuddy-tab home -mybuddy-hero 1
  shot home-hero2 -mybuddy-tab home -mybuddy-hero 2
  shot home-2 -mybuddy-tab home -mybuddy-scroll 650
  shot home-3 -mybuddy-tab home -mybuddy-scroll 1300
  # Bibliotheek: de groepen "Sparen en beleggen", "Plannen" en "Recent" (de kop "Deze maand" heeft de maand in de naam).
  shot library -mybuddy-tab library
  shot library-saving -mybuddy-tab library -mybuddy-scroll-to "Sparen en beleggen"
  shot library-planning -mybuddy-tab library -mybuddy-scroll-to "Plannen"
  shot library-recent -mybuddy-tab library -mybuddy-scroll-to "Recent"
  shot search -mybuddy-tab search

  if [ "$appearance" = "light" ]; then
    # Nieuwe pagina's en Instellingen als volle pagina achter de profielknop.
    shot flow -mybuddy-tab library -mybuddy-open flow
    shot flow-2 -mybuddy-tab library -mybuddy-open flow -mybuddy-scroll 650
    shot flow-year -mybuddy-tab library -mybuddy-open flow -mybuddy-period year
    shot tools -mybuddy-tab home -mybuddy-open tools
    shot settings -mybuddy-tab home -mybuddy-settings
    shot settings-layout -mybuddy-tab home -mybuddy-open layout
    shot order-home -mybuddy-tab home -mybuddy-order home
    # Deze maand
    shot income -mybuddy-tab library -mybuddy-open income
    shot bank -mybuddy-tab library -mybuddy-open bank
    shot bank-2 -mybuddy-tab library -mybuddy-open bank -mybuddy-scroll-to "Verwacht verloop"
    shot bank-3 -mybuddy-tab library -mybuddy-open bank -mybuddy-scroll-to "Geschiedenis"
    shot cashflow -mybuddy-tab library -mybuddy-open cashflow
    shot cashflow-2 -mybuddy-tab library -mybuddy-open cashflow -mybuddy-scroll-to "Saldo per dag"
    shot distribute -mybuddy-tab library -mybuddy-open distribute
    # Sparen en beleggen: de lijsten en de albumpagina's
    shot pots -mybuddy-tab library -mybuddy-open pots
    shot pot -mybuddy-tab library -mybuddy-open pot0
    shot pot-2 -mybuddy-tab library -mybuddy-open pot0 -mybuddy-scroll-to "Verloop"
    shot portfolio -mybuddy-tab library -mybuddy-open portfolio
    shot holding -mybuddy-tab library -mybuddy-open holding0
    shot holding-2 -mybuddy-tab library -mybuddy-open holding0 -mybuddy-scroll-to "Waarde-updates"
    # Plannen
    shot goals -mybuddy-tab library -mybuddy-open goals
    shot goal -mybuddy-tab library -mybuddy-open goal0
    shot goal-2 -mybuddy-tab library -mybuddy-open goal0 -mybuddy-scroll 700
    shot savingsgoal -mybuddy-tab library -mybuddy-open savingsgoal
    shot savingsgoal-2 -mybuddy-tab library -mybuddy-open savingsgoal -mybuddy-scroll 700
    shot buffer -mybuddy-tab library -mybuddy-open buffer
    shot buffer-2 -mybuddy-tab library -mybuddy-open buffer -mybuddy-scroll 700
    shot projection -mybuddy-tab library -mybuddy-open projection
    shot accelerators -mybuddy-tab library -mybuddy-open accelerators
    shot purchase -mybuddy-tab library -mybuddy-open purchase
    shot purchase-2 -mybuddy-tab library -mybuddy-open purchase -mybuddy-scroll 700
  fi
}

shoot_device "$IPHONE" iphone light
shoot_device "$IPHONE" iphone dark
shoot_device "$SMALL" small light
shoot_device "$IPAD" ipad light
shoot_device "$IPAD" ipad dark
ls -la "$OUT" | head -120
