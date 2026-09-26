#!/bin/bash
# release.sh — Kompletter Release: Prüfen -> Build -> DMG -> Prüfen -> appcast.xml (signiert) -> Prüfen.
#
# Voraussetzung: Sparkle-EdDSA-Privatkey liegt in der macOS-Keychain
# (einmalig via 'generate_keys' erzeugt; der Public Key steht in Info.plist).
# Vorher: MARKETING_VERSION und CURRENT_PROJECT_VERSION in project.yml erhöhen und committen.
#
# Ergebnis:
#   dist/MikaPlusPlayer-v<version>.dmg   -> als GitHub-Release-Asset hochladen
#   appcast.xml (Repo-Root)              -> committen & pushen (main-Branch), NACH dem Upload
#
# B09 · BUG-10: Der Feed wird aus der versionierten appcast.xml fortgeschrieben, nicht mehr aus
#               dist/appcast.xml (dort lag ein Altstand mit 1.0-Eintrag und Mukaarts-URLs).
# B09 · BUG-11: Gegenprüfungen vor dem Build, am gebauten Bundle/DMG und am neuen Feed
#               (scripts/b09_release_check.sh). Jeder Befund bricht ab, bevor appcast.xml geändert wird.
#
# Optionale Umgebungsvariablen:
#   GENERATE_APPCAST, SIGN_UPDATE   Pfade zu den Sparkle-Werkzeugen (Standard: build/dd/SourcePackages/artifacts)
#   SPARKLE_ED_KEY_FILE             Schlüsseldatei statt Keychain (--ed-key-file), z. B. für Probeläufe
#   STRENG=1                        auch offene Punkte ([ offen]) brechen ab
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GH_REPO="daumedia/MikaPlusPlayer"   # ggf. anpassen (muss zur SUFeedURL passen)
export GH_REPO
CHECK="$ROOT/scripts/b09_release_check.sh"

echo "==> Gegenprüfung vor dem Build"
bash "$CHECK" vor-build

bash "$ROOT/scripts/build-macos.sh"
bash "$ROOT/scripts/make-dmg.sh"

APP="$ROOT/build/MikaPlusPlayer.app"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
DMG="$ROOT/dist/MikaPlusPlayer-v$VER.dmg"

echo "==> Gegenprüfung am Bundle und DMG"
APP="$APP" DMG="$DMG" bash "$CHECK" nach-build

# Sparkle-Werkzeuge finden (liegen in den aufgelösten SPM-Artefakten).
GEN="${GENERATE_APPCAST:-$(find "$ROOT/build/dd/SourcePackages/artifacts" -name generate_appcast -type f 2>/dev/null | head -1)}"
[ -n "$GEN" ] || { echo "FEHLER: generate_appcast nicht gefunden."; exit 1; }
SIGN="${SIGN_UPDATE:-$(dirname "$GEN")/sign_update}"
[ -x "$SIGN" ] || { echo "FEHLER: sign_update nicht gefunden."; exit 1; }
KEY_ARGS=()
[ -n "${SPARKLE_ED_KEY_FILE:-}" ] && KEY_ARGS=(--ed-key-file "$SPARKLE_ED_KEY_FILE")

# Arbeitsordner: nur das neue DMG und eine Kopie der VERSIONIERTEN appcast.xml.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ROOT/appcast.xml" "$STAGE/appcast.xml"
cp "$DMG" "$STAGE/"

echo "==> appcast.xml fortschreiben (Build $BUILD, signiert)"
"$GEN" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} \
    --download-url-prefix "https://github.com/$GH_REPO/releases/download/v$VER/" \
    "$STAGE"
# Feed selbst signieren (Vorbereitung für SURequireSignedFeed, BUG-08). Apps ohne diesen Schlüssel
# ignorieren den Signaturblock am Dateiende.
"$SIGN" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} "$STAGE/appcast.xml"

echo "==> Gegenprüfung am neuen Feed"
APP="$APP" DMG="$DMG" FEED="$STAGE/appcast.xml" BASE_FEED="$ROOT/appcast.xml" bash "$CHECK" feed

cp "$STAGE/appcast.xml" "$ROOT/appcast.xml"

cat <<EOF

==> Release v$VER (Build $BUILD) vorbereitet und gegengeprüft.

Nächste Schritte (in dieser Reihenfolge):
  1) GitHub-Release "v$VER" im Repo $GH_REPO anlegen
  2) dist/MikaPlusPlayer-v$VER.dmg als Release-Asset hochladen
  3) appcast.xml committen & auf 'main' pushen
     (SUFeedURL: https://raw.githubusercontent.com/$GH_REPO/main/appcast.xml)
     appcast.xml danach nicht mehr von Hand ändern — die Feed-Signatur würde ungültig.

Für öffentliche Distribution: mit Developer ID signieren + notarisieren
(siehe README, Abschnitt "Öffentliche Distribution").
EOF
