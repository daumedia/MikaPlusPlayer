#!/bin/bash
# build-macos.sh — Baut die macOS-App für die Verteilung und legt sie unter build/MikaPlusPlayer.app ab.
#
# B09 · BF-03 (2026-10-02): Archivieren (Release) und Exportieren mit Methode „Developer ID“
# (scripts/ExportOptions-DeveloperID.plist). Der Export signiert die App samt eingebetteter Frameworks mit Developer ID
# und sicherem Zeitstempel. Voraussetzung: Zertifikat „Developer ID Application“ des Teams im Anmelde-Schlüsselbund.
#
# PROBEMODUS=1: ohne Developer ID — Archiv ad hoc signiert, kein Export (nur für Proben; ohne disable-library-validation
# startet ein ad-hoc-signiertes Release mit Hardened Runtime nicht, BF-09).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DD="$ROOT/build/dd"
ARCHIVE="$ROOT/build/MikaPlusPlayer.xcarchive"
EXPORT="$ROOT/build/export"

# Die Projektdatei ist nicht versioniert: Sprache, Signatur und Bundle-ID kommen aus project.yml.
command -v xcodegen >/dev/null 2>&1 || { echo "FEHLER: xcodegen nicht installiert (brew install xcodegen)."; exit 1; }
echo "==> xcodegen generate"
xcodegen generate >/dev/null

SIGN_ARGS=()
[ "${PROBEMODUS:-0}" = "1" ] && SIGN_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual)

echo "==> xcodebuild archive (Release, macOS)"
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild archive \
    -project MikaPlusPlayer.xcodeproj \
    -scheme MikaPlusPlayer-macOS \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DD" \
    -archivePath "$ARCHIVE" \
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} | tail -3

if [ "${PROBEMODUS:-0}" = "1" ]; then
    echo "==> [Probe] kein Export, App aus dem Archiv"
    SRC="$ARCHIVE/Products/Applications/MikaPlusPlayer.app"
else
    echo "==> xcodebuild -exportArchive (Developer ID)"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$ROOT/scripts/ExportOptions-DeveloperID.plist" \
        -exportPath "$EXPORT" | tail -3
    SRC="$EXPORT/MikaPlusPlayer.app"
fi
[ -d "$SRC" ] || { echo "FEHLER: App nicht gefunden: $SRC"; exit 1; }

mkdir -p "$ROOT/build"
rm -rf "$ROOT/build/MikaPlusPlayer.app"
# ditto erhält Signaturen, erweiterte Attribute und symbolische Links der Frameworks
ditto "$SRC" "$ROOT/build/MikaPlusPlayer.app"

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/build/MikaPlusPlayer.app/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT/build/MikaPlusPlayer.app/Contents/Info.plist")
echo "==> Fertig: build/MikaPlusPlayer.app (v$VER, Build $BUILD)"
