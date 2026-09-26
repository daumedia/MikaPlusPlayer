#!/bin/bash
# b09_release_check.sh — Release-Preflight für die Update-Kette (B09).
#
# Reproduziert die ausführbaren QA-Nachweise aus Durchlauf 1 (2026-09-15) als
# Skript, das VOR einem Release laufen soll. Es findet, es repariert nicht.
# Exit-Code 0 = keine Beanstandung, 1 = mindestens ein Befund.
#
# Aufruf:  bash scripts/b09_release_check.sh
# Optional: APP=build/MikaPlusPlayer.app DMG=dist/MikaPlusPlayer-v1.1.dmg bash scripts/b09_release_check.sh
set -uo pipefail

# Repo-Wurzel robust finden (Aufstieg zu project.yml), egal von wo aufgerufen.
ROOT="$(cd "$(dirname "$0")" && pwd)"
while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/project.yml" ]; do ROOT="$(dirname "$ROOT")"; done
[ -f "$ROOT/project.yml" ] || { echo "FEHLER: Repo-Wurzel (project.yml) nicht gefunden."; exit 2; }
cd "$ROOT"
APP="${APP:-build/MikaPlusPlayer.app}"
DMG="${DMG:-$(ls -1 dist/*.dmg 2>/dev/null | head -1)}"
INFO="Sources/Resources/Info.plist"
FAIL=0
note() { printf '  [%s] %s\n' "$1" "$2"; }
bad()  { note "BEFUND" "$1"; FAIL=1; }
ok()   { note "  ok  " "$1"; }

echo "== 1 · Feed-Namensraum (FB-01) =="
FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO" 2>/dev/null || true)
case "$FEED" in
  *mukaarts*|*Mukaarts*) bad "SUFeedURL zeigt auf den freien Mukaarts-Namensraum: $FEED" ;;
  *daumedia*)            ok  "SUFeedURL: $FEED" ;;
  *)                     bad "SUFeedURL unerwartet: $FEED" ;;
esac

echo "== 2 · Versionierter appcast.xml sauber (FB-10) =="
if grep -qi mukaarts appcast.xml 2>/dev/null; then bad "appcast.xml enthält Mukaarts-URLs"; else ok "keine Mukaarts-URLs in appcast.xml"; fi
if grep -q "<sparkle:version>1</sparkle:version>" appcast.xml 2>/dev/null; then bad "nie veröffentlichter 1.0-Eintrag in appcast.xml"; else ok "kein 1.0-Eintrag"; fi

echo "== 3 · Kein Altstand in dist/appcast.xml (FB-10) =="
if [ -f dist/appcast.xml ] && grep -qi mukaarts dist/appcast.xml; then
  bad "dist/appcast.xml enthält Mukaarts-URLs — release.sh würde sie über appcast.xml kopieren"
else ok "dist/appcast.xml fehlt oder ist sauber"; fi

echo "== 4 · Build-Nummer erhöht (FB-02) =="
CUR=$(grep -oE 'CURRENT_PROJECT_VERSION: *"?[0-9]+' project.yml | grep -oE '[0-9]+' | head -1)
if [ "${CUR:-0}" -le 2 ]; then bad "CURRENT_PROJECT_VERSION=$CUR (≤ veröffentlichte v1.1 Build 2) — Release erreicht keine Installation"; else ok "CURRENT_PROJECT_VERSION=$CUR"; fi

echo "== 5 · Signatur & Härtung des Bundles (FB-03/FB-05) =="
if [ -d "$APP" ]; then
  ENT=$(codesign -d --entitlements - "$APP" 2>/dev/null | tr -d '\n')
  echo "$ENT" | grep -q "get-task-allow" && bad "get-task-allow im Bundle gesetzt (Debug-Berechtigung im Release)" || ok "kein get-task-allow"
  DVOUT=$(codesign -dvvv "$APP" 2>&1)
  echo "$DVOUT" | grep -q "flags=.*runtime" && ok "Hardened Runtime aktiv" || bad "Hardened Runtime nicht aktiv"
  echo "$DVOUT" | grep -qi "adhoc" && bad "ad-hoc signiert (keine Developer ID)" || ok "nicht ad-hoc signiert"
  if spctl -a -vv "$APP" 2>&1 | grep -q accepted; then ok "spctl akzeptiert (notarisiert)"; else bad "spctl lehnt das Bundle ab (nicht notarisiert)"; fi
else
  note " skip " "kein $APP — Build zuerst (scripts/build-macos.sh)"
fi

echo "== 6 · DMG signiert/notarisiert (FB-05) =="
if [ -n "${DMG:-}" ] && [ -f "$DMG" ]; then
  if spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | grep -q accepted; then ok "DMG akzeptiert"; else bad "DMG ohne verwertbare Signatur ($DMG)"; fi
else
  note " skip " "kein DMG in dist/"
fi

echo "== 7 · Feed-Signatur verlangt (FB-08) =="
grep -q "<key>SURequireSignedFeed</key>" "$INFO" && ok "SURequireSignedFeed gesetzt" || bad "SURequireSignedFeed fehlt — Feed nur durch TLS geschützt"

echo
if [ "$FAIL" -eq 0 ]; then echo "== Ergebnis: keine Beanstandung =="; else echo "== Ergebnis: BEFUNDE offen (siehe oben) =="; fi
exit "$FAIL"
