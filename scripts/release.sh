#!/bin/bash
# release.sh — Kompletter Release (B09, Ablauf nach design.md vom 2026-10-02):
#   Prüfen -> Archivieren/Exportieren (Developer ID) -> Prüfen -> DMG -> DMG signieren -> Notarisieren -> Heften
#   -> Prüfen -> appcast.xml (Eintrag + Feed-Signatur) -> Prüfen.
# Reihenfolge ist Pflicht: Jeder Schritt verändert Bytes, die ein späterer signiert. Nach der EdDSA-Signatur werden
# weder DMG noch Feed mehr angefasst.
#
# Voraussetzungen:
#   - Sparkle-EdDSA-Privatkey in der macOS-Keychain (familienweit; Public Key in Info.plist).
#   - Zertifikat „Developer ID Application“ (Team CWJM4J4HFN) im Anmelde-Schlüsselbund.
#   - notarytool-Profil im Anmelde-Schlüsselbund, Name in NOTARY_PROFILE
#     (einmalig: xcrun notarytool store-credentials "<Name>" --apple-id … --team-id CWJM4J4HFN).
#   - Vorher: MARKETING_VERSION und CURRENT_PROJECT_VERSION in project.yml erhöhen und committen.
#
# Ergebnis:
#   dist/MikaPlusPlayer-v<version>.dmg            signiert, notarisiert, geheftet -> als GitHub-Release-Asset hochladen
#   dist/notarisierung-v<version>.json            Protokoll des Notardienstes
#   appcast.xml (Repo-Root)                       neuer Eintrag, Feed signiert -> per PR auf main, NACH dem Upload
#
# Umgebungsvariablen:
#   NOTARY_PROFILE                  Name des notarytool-Profils (Pflicht außer im Probemodus)
#   GENERATE_APPCAST, SIGN_UPDATE   Pfade zu den Sparkle-Werkzeugen (Standard: build/dd/SourcePackages/artifacts)
#   SPARKLE_ED_KEY_FILE             Schlüsseldatei statt Keychain (--ed-key-file), z. B. für Probeläufe
#   STRENG=1                        auch offene Punkte ([ offen]) brechen ab
#   PROBEMODUS=1                    ohne Developer ID und Notarisierung (Attrappen, Tests): DMG ad hoc signiert,
#                                   Notarisieren/Heften nur mit übersteuerten Werkzeugen; die Gegenprüfung meldet
#                                   Developer-ID-Punkte als „offen“. Ergebnis nicht veröffentlichen.
#   Prüfnähte: NOTARYTOOL, STAPLER, CODESIGN (Befehle), DMG_SIGN_IDENTITY (Vorgabe „Developer ID Application“,
#              im Probemodus „-“); build-macos.sh und make-dmg.sh sind eigene Skripte.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GH_REPO="daumedia/MikaPlusPlayer"   # ggf. anpassen (muss zur SUFeedURL passen)
export GH_REPO
CHECK="$ROOT/scripts/b09_release_check.sh"
PROBEMODUS="${PROBEMODUS:-0}"
export PROBEMODUS
NOTARYTOOL="${NOTARYTOOL:-xcrun notarytool}"
STAPLER="${STAPLER:-xcrun stapler}"
CODESIGN="${CODESIGN:-codesign}"
export NOTARYTOOL STAPLER
if [ "$PROBEMODUS" = "1" ]; then
    DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:--}"
    echo "!! PROBEMODUS: ohne Developer ID und Notarisierung — Ergebnis nicht veröffentlichen."
else
    DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-Developer ID Application}"
fi

# Sparkle-Werkzeuge finden (liegen in den aufgelösten SPM-Artefakten, die der Build anlegt). Gesucht wird direkt nach
# dem Build, damit ein fehlendes Werkzeug nicht erst nach der Notarisierung auffällt. B09 · BF-51: find scheitert ohne
# den Ordner; das darf das Skript unter „set -e“ nicht stumm beenden.
find_tool() { { find "$ROOT/build/dd/SourcePackages/artifacts" -name "$1" -type f 2>/dev/null || true; } | head -1; }

echo "==> Gegenprüfung vor dem Build"
bash "$CHECK" vor-build

bash "$ROOT/scripts/build-macos.sh"

APP="$ROOT/build/MikaPlusPlayer.app"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
DMG="$ROOT/dist/MikaPlusPlayer-v$VER.dmg"

GEN="${GENERATE_APPCAST:-$(find_tool generate_appcast)}"
[ -n "$GEN" ] && [ -x "$GEN" ] || { echo "FEHLER: generate_appcast nicht gefunden."; exit 1; }
SIGN="${SIGN_UPDATE:-$(dirname "$GEN")/sign_update}"
[ -x "$SIGN" ] || { echo "FEHLER: sign_update nicht gefunden."; exit 1; }
KEY_ARGS=()
[ -n "${SPARKLE_ED_KEY_FILE:-}" ] && KEY_ARGS=(--ed-key-file "$SPARKLE_ED_KEY_FILE")

echo "==> Gegenprüfung am exportierten Bundle"
APP="$APP" bash "$CHECK" nach-build

bash "$ROOT/scripts/make-dmg.sh"

echo "==> DMG signieren ($DMG_SIGN_IDENTITY)"
if [ "$DMG_SIGN_IDENTITY" = "-" ]; then
    $CODESIGN --force --sign - -i lu.daumedia.MikaPlusPlayer.dmg "$DMG"
else
    $CODESIGN --force --sign "$DMG_SIGN_IDENTITY" --timestamp -i lu.daumedia.MikaPlusPlayer.dmg "$DMG"
fi

if [ "$PROBEMODUS" = "1" ] && [ "$NOTARYTOOL" = "xcrun notarytool" ]; then
    echo "==> [Probe] Notarisieren und Heften übersprungen"
else
    echo "==> Notarisieren (Profil ${NOTARY_PROFILE:-<fehlt>}, wartet auf das Ergebnis)"
    NOTAR_JSON="$(mktemp)"
    # Exit-Code bei „Invalid“/„Rejected“ ist nicht dokumentiert: ausgewertet wird das Ergebnisfeld „status“.
    $NOTARYTOOL submit "$DMG" --keychain-profile "${NOTARY_PROFILE:?NOTARY_PROFILE fehlt}" --wait --output-format json > "$NOTAR_JSON" || true
    NOTAR_ID="$(plutil -extract id raw -o - "$NOTAR_JSON" 2>/dev/null || true)"
    NOTAR_STATUS="$(plutil -extract status raw -o - "$NOTAR_JSON" 2>/dev/null || true)"
    NOTAR_LOG="$ROOT/dist/notarisierung-v$VER.json"
    if [ -n "$NOTAR_ID" ]; then
        $NOTARYTOOL log "$NOTAR_ID" --keychain-profile "$NOTARY_PROFILE" "$NOTAR_LOG" >/dev/null 2>&1 \
            || echo "WARNUNG: Notar-Protokoll ließ sich nicht abholen (ID $NOTAR_ID)."
    fi
    rm -f "$NOTAR_JSON"
    if [ "$NOTAR_STATUS" != "Accepted" ]; then
        echo "FEHLER: Notarisierung nicht angenommen (Status „${NOTAR_STATUS:-unbekannt}“, ID ${NOTAR_ID:-keine}). Protokoll: $NOTAR_LOG"
        exit 1
    fi
    echo "    angenommen (ID $NOTAR_ID), Protokoll: dist/$(basename "$NOTAR_LOG")"

    echo "==> Heften"
    $STAPLER staple "$DMG"
    $STAPLER validate "$DMG"
fi

echo "==> Gegenprüfung am fertigen DMG"
APP="$APP" DMG="$DMG" bash "$CHECK" nach-heften

# Arbeitsordner: nur das fertige DMG und eine Kopie der VERSIONIERTEN appcast.xml.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ROOT/appcast.xml" "$STAGE/appcast.xml"
cp "$DMG" "$STAGE/"

echo "==> appcast.xml fortschreiben (Build $BUILD, signiert)"
# --maximum-versions 0: alle bisherigen Einträge bleiben (Standard wäre 3 je Zweig, BF-47); die Gegenprüfung „feed“
# verlangt genau die Einträge der versionierten appcast.xml plus den neuen.
"$GEN" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} --maximum-versions 0 \
    --download-url-prefix "https://github.com/$GH_REPO/releases/download/v$VER/" \
    "$STAGE"
# Feed signieren (B09 · BF-08: Apps ab 1.2 verlangen die Signatur, SURequireSignedFeed). Apps ohne diesen Schlüssel
# ignorieren den Signaturblock am Dateiende.
"$SIGN" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} "$STAGE/appcast.xml"

echo "==> Gegenprüfung am neuen Feed"
APP="$APP" DMG="$DMG" FEED="$STAGE/appcast.xml" BASE_FEED="$ROOT/appcast.xml" bash "$CHECK" feed

cp "$STAGE/appcast.xml" "$ROOT/appcast.xml"

cat <<EOF

==> Release v$VER (Build $BUILD) vorbereitet und gegengeprüft.

Nächste Schritte (in dieser Reihenfolge):
  a) Pflichtproben vor dem Veröffentlichen (Ergebnis in den Build-Bericht):
     - Kurztest Wiedergabe (Betreiber): dieses DMG installieren, echte Sender als HLS und MPEG-TS, mit Ton (OF-09)
     - Übergangsprobe 1.1 -> $VER: eine installierte v1.1 nimmt einen notarisierten Test-Build mit hoher
       Build-Nummer aus einem eigenen Test-Feed an und verlangt danach die Feed-Signatur (Entscheidung 14)
     - Offline-Erststart: App aus diesem DMG nach /Applications kopieren, Netz trennen, erster Start (Entscheidung 2)
  b) GitHub-Release "v$VER" im Repo $GH_REPO anlegen, dist/MikaPlusPlayer-v$VER.dmg als Asset hochladen,
     danach appcast.xml per Pull Request auf 'main' bringen.
     appcast.xml danach nicht mehr von Hand ändern — die Feed-Signatur würde ungültig.
  c) Nach dem Merge: bash scripts/b09_release_check.sh nach-merge
     (ausgelieferter Feed an der daumedia- und der Mukaarts-Adresse = gemergte Datei, Signatur gültig)
EOF
