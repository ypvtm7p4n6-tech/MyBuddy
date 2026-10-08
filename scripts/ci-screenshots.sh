#!/bin/bash
# Maakt screenshots van alle schermen in de iOS Simulator (debug-modus met voorbeelddata).
# Gebruik: scripts/ci-screenshots.sh [uitvoermap]
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
  shot home -mybuddy-tab home
  shot home-2 -mybuddy-tab home -mybuddy-scroll 650
  shot savings -mybuddy-tab savings
  shot savings-2 -mybuddy-tab savings -mybuddy-scroll 650
  shot invest -mybuddy-tab investing
  shot invest-2 -mybuddy-tab investing -mybuddy-scroll 650
  if [ "$appearance" = "light" ]; then
    shot savings-year -mybuddy-tab savings -mybuddy-period year
    shot overview -mybuddy-tab home -mybuddy-open overview
    shot income -mybuddy-tab savings -mybuddy-open income
    shot bank -mybuddy-tab savings -mybuddy-open bank
    shot bank-2 -mybuddy-tab savings -mybuddy-open bank -mybuddy-scroll 700
    shot bank-3 -mybuddy-tab savings -mybuddy-open bank -mybuddy-scroll 1400
    shot distribute -mybuddy-tab savings -mybuddy-open distribute
    shot pots -mybuddy-tab savings -mybuddy-open pots
    shot pot -mybuddy-tab savings -mybuddy-open pot0
    shot buffer -mybuddy-tab savings -mybuddy-open buffer
    shot buffer-2 -mybuddy-tab savings -mybuddy-open buffer -mybuddy-scroll 700
    shot portfolio -mybuddy-tab investing -mybuddy-open portfolio
    shot holding -mybuddy-tab investing -mybuddy-open holding0
    shot projection -mybuddy-tab investing -mybuddy-open projection
    shot savingsgoal -mybuddy-tab investing -mybuddy-open savingsgoal
    shot savingsgoal-2 -mybuddy-tab investing -mybuddy-open savingsgoal -mybuddy-scroll 700
    shot goals -mybuddy-tab investing -mybuddy-open goals
    shot goal -mybuddy-tab investing -mybuddy-open goal0
    shot goal-2 -mybuddy-tab investing -mybuddy-open goal0 -mybuddy-scroll 700
    shot accelerators -mybuddy-tab investing -mybuddy-open accelerators
    shot settings -mybuddy-tab home -mybuddy-settings
  fi
}

shoot_device "$IPHONE" iphone light
shoot_device "$IPHONE" iphone dark
shoot_device "$SMALL" small light
shoot_device "$IPAD" ipad light
ls -la "$OUT" | head -80
