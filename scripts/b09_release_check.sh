#!/bin/bash
# b09_release_check.sh — Gegenprüfungen der Update-Kette (B09 · BUG-10/BUG-11, Durchlauf 2 2026-10-02).
#
# Übernommen aus dem QA-Vorschlag (Durchlauf 1, 2026-09-15) und in scripts/release.sh eingehängt.
# Findet, repariert nicht.
#
#   bash scripts/b09_release_check.sh vor-build     Quellstand: Feed-Adresse, appcast.xml, Versionen, Härtung, Git,
#                                                   Notar-Profil
#   APP=… bash scripts/b09_release_check.sh nach-build
#                                                   exportiertes Bundle: Developer ID, Team, Zeitstempel, Runtime je
#                                                   Komponente, Entitlements, Info.plist, Sprache (DMG=… zusätzlich: DMG)
#   APP=… DMG=… bash scripts/b09_release_check.sh nach-heften
#                                                   fertiges DMG: enthält das geprüfte Bundle, Developer ID, Ticket,
#                                                   Gatekeeper für DMG und App
#   APP=… DMG=… FEED=… bash scripts/b09_release_check.sh feed
#                                                   neuer Feed gegen die versionierte appcast.xml
#   bash scripts/b09_release_check.sh nach-merge    ausgelieferter Feed (daumedia- und Mukaarts-Adresse) = gemergte
#                                                   appcast.xml, Signatur gültig
#   bash scripts/b09_release_check.sh               vor-build, dazu nach-build, falls build/MikaPlusPlayer.app existiert
#
# Ergebnisarten:
#   [BEFUND]  blockiert das Release (Exit 1)
#   [ offen]  nur im Probemodus (PROBEMODUS=1, ohne Developer ID und Notarisierung): Punkte, die dort nicht erfüllbar
#             sind. Blockiert mit STRENG=1.
#   [  ok  ]  bestanden
#
# Umgebung (Prüfnähte für Tests, sonst Vorgaben):
#   PROBEMODUS=1        Developer-ID-, Zeitstempel-, Notarisierungs- und Gatekeeper-Punkte „offen“ statt Befund;
#                       vor-build verlangt kein Notar-Profil
#   NOTARY_PROFILE      Name des notarytool-Profils im Anmelde-Schlüsselbund (Pflicht außer im Probemodus)
#   NOTARYTOOL, STAPLER Befehle (Vorgabe: xcrun notarytool, xcrun stapler)
#   BUNDLE_ID           erwartete Bundle-ID (Vorgabe lu.daumedia.MikaPlusPlayer)
#   FEED_URLS           nach-merge: ausgelieferte Adressen (Vorgabe: daumedia- und Mukaarts-Raw-Adresse)
#   NACH_MERGE_FRIST    nach-merge: Sekunden, die auf den GitHub-Zwischenspeicher gewartet wird (Vorgabe 330)
#
# Exit 0 = keine Beanstandung · 1 = mindestens ein Befund · 2 = Aufruf-/Umgebungsfehler
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
while [ "$ROOT" != "/" ] && [ ! -f "$ROOT/project.yml" ]; do ROOT="$(dirname "$ROOT")"; done
[ -f "$ROOT/project.yml" ] || { echo "FEHLER: Repo-Wurzel (project.yml) nicht gefunden."; exit 2; }
cd "$ROOT"

PHASE="${1:-alle}"
GH_REPO="${GH_REPO:-daumedia/MikaPlusPlayer}"
INFO="Sources/Resources/Info.plist"
APPCAST="appcast.xml"
STRENG="${STRENG:-0}"
PROBEMODUS="${PROBEMODUS:-0}"
NOTARYTOOL="${NOTARYTOOL:-xcrun notarytool}"
STAPLER="${STAPLER:-xcrun stapler}"
BUNDLE_ID="${BUNDLE_ID:-lu.daumedia.MikaPlusPlayer}"
DOWNLOAD_PREFIX="https://github.com/$GH_REPO/releases/download/"
FAIL=0
OPEN=0

note() { printf '  [%s] %s\n' "$1" "$2"; }
bad()  { note "BEFUND" "$1"; FAIL=1; }
open_() { note " offen" "$1"; OPEN=1; }
ok()   { note "  ok  " "$1"; }
skip() { note " skip " "$1"; }
# Punkte, die Developer ID oder Notarisierung brauchen: Befund, im Probemodus „offen“.
dev_bad() { if [ "$PROBEMODUS" = "1" ]; then open_ "$1 (Probemodus)"; else bad "$1"; fi; }

plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null; }
yml_value() { # erster Wert eines Schlüssels in project.yml (ohne Anführungszeichen); leer, wenn der Wert leer ist
  sed -nE "s/^[[:space:]]*$1:[[:space:]]*\"?([^\"#[:space:]]*)\"?.*$/\1/p" project.yml | head -1
}
feed_versions() { grep -oE '<sparkle:version>[^<]+</sparkle:version>' "$1" 2>/dev/null | sed -E 's/<[^>]+>//g' | sort -n; }
feed_short_versions() { grep -oE '<sparkle:shortVersionString>[^<]+</sparkle:shortVersionString>' "$1" 2>/dev/null | sed -E 's/<[^>]+>//g'; }
max_feed_version() { feed_versions "$1" | tail -1; }
xpath() { xmllint --xpath "$1" "$2" 2>/dev/null; }
item_attr() { # item_attr <feed> <sparkle:version> <url|length|edSignature>
  xpath "string(//item[*[local-name()='version']='$2']/enclosure/@*[local-name()='$3'])" "$1"
}
enclosure_urls() { # alle Download-Adressen eines Feeds (Einträge und Deltas), je Zeile eine
  xpath "//enclosure/@url" "$1" | grep -oE 'url="[^"]*"' | sed -E 's/^url="(.*)"$/\1/'
}
ed25519() { xcrun swift "$ROOT/scripts/b09_ed25519.swift" "$@"; }

MARKETING="$(yml_value MARKETING_VERSION)"
BUILD="$(yml_value CURRENT_PROJECT_VERSION)"
TEAM_ID="${TEAM_ID:-$(yml_value DEVELOPMENT_TEAM)}"
PUBKEY="$(plist_get SUPublicEDKey "$INFO")"
FEEDURL="$(plist_get SUFeedURL "$INFO")"

# Alle Download-Adressen eines Feeds liegen unter den GitHub-Releases dieses Repositorys (BF-48).
check_download_urls() { # check_download_urls <feed> <bezeichnung>
  local urls fremd n
  urls="$(enclosure_urls "$1")"
  n="$(printf '%s\n' "$urls" | grep -c . )"
  fremd="$(printf '%s\n' "$urls" | grep . | grep -vE "^${DOWNLOAD_PREFIX//./\\.}v[^/]+/[^/]+$")"
  if [ "$n" -eq 0 ]; then bad "$2: keine Download-Adressen gefunden"
  elif [ -n "$fremd" ]; then bad "$2: Download-Adresse außerhalb von ${DOWNLOAD_PREFIX}: $(printf '%s' "$fremd" | tr '\n' ' ')"
  else ok "$2: alle $n Download-Adressen unter $DOWNLOAD_PREFIX"; fi
}

# ---------------------------------------------------------------------------------------------
vor_build() {
  echo "== vor-build · Feed-Adresse (FB-01) =="
  case "$FEEDURL" in
    *[Mm]ukaarts*) bad "SUFeedURL zeigt auf den freien Mukaarts-Namensraum: $FEEDURL" ;;
    "https://raw.githubusercontent.com/$GH_REPO/main/appcast.xml") ok "SUFeedURL: $FEEDURL" ;;
    *) bad "SUFeedURL passt nicht zu GH_REPO=$GH_REPO: ${FEEDURL:-<fehlt>}" ;;
  esac
  [ -n "$PUBKEY" ] && ok "SUPublicEDKey vorhanden" || bad "SUPublicEDKey fehlt in $INFO"

  echo "== vor-build · versionierte appcast.xml (FB-10, BF-48) =="
  if [ ! -f "$APPCAST" ]; then bad "appcast.xml fehlt im Repository"; else
    grep -qi mukaarts "$APPCAST" && bad "appcast.xml enthält Mukaarts-URLs" || ok "keine Mukaarts-URLs"
    feed_versions "$APPCAST" | grep -qx 1 && bad "nie veröffentlichter 1.0-Eintrag (sparkle:version 1) in appcast.xml" || ok "kein 1.0-Eintrag"
    TITLE="$(xpath 'string(/rss/channel/title)' "$APPCAST")"
    [ "$TITLE" = "Mika+Player" ] && ok "Kanaltitel „Mika+Player“" || bad "Kanaltitel „${TITLE}“ statt „Mika+Player“"
    check_download_urls "$APPCAST" "versionierte appcast.xml"
  fi
  if [ -f dist/appcast.xml ] && grep -qi mukaarts dist/appcast.xml; then
    skip "dist/appcast.xml ist Altstand (1.0/Mukaarts) — wird von release.sh nicht mehr verwendet"
  fi

  echo "== vor-build · Versionen (FB-02, BF-50) =="
  HIGHEST="$(max_feed_version "$APPCAST")"
  if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
    bad "CURRENT_PROJECT_VERSION ist keine ganze Zahl: ${BUILD:-<fehlt>}"
  elif [ -n "$HIGHEST" ] && [ "$BUILD" -le "$HIGHEST" ]; then
    bad "CURRENT_PROJECT_VERSION=$BUILD ist nicht größer als die höchste sparkle:version $HIGHEST im Feed — keine Installation bekäme das Update"
  else
    ok "CURRENT_PROJECT_VERSION=$BUILD > höchste sparkle:version ${HIGHEST:-<keine>}"
  fi
  if ! [[ "$MARKETING" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    bad "MARKETING_VERSION ist leer oder keine Versionsnummer: „${MARKETING}“ (DMG-Name, Tag und Anzeigeversion entstünden daraus)"
  elif feed_short_versions "$APPCAST" | grep -qxF "$MARKETING"; then
    bad "MARKETING_VERSION=$MARKETING ist schon veröffentlicht (Tag v$MARKETING und DMG-Name kollidieren) — Anzeigeversion anheben"
  else
    ok "MARKETING_VERSION=$MARKETING noch nicht im Feed"
  fi

  echo "== vor-build · Härtung und Sparkle-Konfiguration (FB-03/FB-08/FB-12, BF-08) =="
  grep -qE '^[[:space:]]*ENABLE_HARDENED_RUNTIME:[[:space:]]*YES' project.yml && ok "ENABLE_HARDENED_RUNTIME: YES" || bad "Hardened Runtime im Release nicht aktiviert (project.yml)"
  grep -qE '^[[:space:]]*CODE_SIGN_INJECT_BASE_ENTITLEMENTS:[[:space:]]*NO' project.yml && ok "CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO (kein get-task-allow)" || bad "CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO fehlt — Release bekäme get-task-allow"
  if awk '/^  Sparkle:/{s=1;next} s&&/^  [^ ]/{s=0} s' project.yml | grep -qE 'exactVersion:'; then
    ok "Sparkle exakt gepinnt ($(awk '/^  Sparkle:/{s=1;next} s&&/^  [^ ]/{s=0} s' project.yml | sed -nE 's/.*exactVersion:[[:space:]]*"?([^"]+)"?.*/\1/p'))"
  else bad "Sparkle nicht mit exactVersion gepinnt"; fi
  [ "$(plist_get SUVerifyUpdateBeforeExtraction "$INFO")" = "true" ] && ok "SUVerifyUpdateBeforeExtraction gesetzt" || bad "SUVerifyUpdateBeforeExtraction fehlt — DMG würde vor der Signaturprüfung eingehängt (und die Feed-Pflicht ließe den Updater nicht starten)"
  [ "$(plist_get SURequireSignedFeed "$INFO")" = "true" ] && ok "SURequireSignedFeed gesetzt" || bad "SURequireSignedFeed fehlt (BF-08: ab 1.2 Pflicht)"

  echo "== vor-build · Notar-Profil (BF-03) =="
  if [ "$PROBEMODUS" = "1" ]; then
    skip "Probemodus: kein Notar-Profil verlangt"
  elif [ -z "${NOTARY_PROFILE:-}" ]; then
    bad "NOTARY_PROFILE nicht gesetzt (Name des notarytool-Profils im Schlüsselbund)"
  elif $NOTARYTOOL history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1; then
    ok "Notar-Profil „${NOTARY_PROFILE}“ vorhanden und gültig"
  else
    bad "Notar-Profil „${NOTARY_PROFILE}“ fehlt im Schlüsselbund oder ist ungültig (xcrun notarytool store-credentials …)"
  fi

  echo "== vor-build · Git-Stand (FB-11) =="
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    bad "kein Git-Arbeitsverzeichnis"
  else
    DIRTY="$(git -C "$ROOT" status --porcelain 2>/dev/null)"
    [ -z "$DIRTY" ] && ok "Arbeitsverzeichnis sauber ($(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null))" || bad "Arbeitsverzeichnis nicht sauber ($(printf '%s\n' "$DIRTY" | wc -l | tr -d ' ') Einträge) — Release wäre keinem Commit zuzuordnen"
    git -C "$ROOT" rev-parse -q --verify "refs/tags/v$MARKETING" >/dev/null 2>&1 && bad "Tag v$MARKETING existiert bereits" || ok "Tag v$MARKETING noch nicht vorhanden (lokal)"
  fi
}

# ---------------------------------------------------------------------------------------------
# Signatur einer Komponente: Developer ID Application, Team, sicherer Zeitstempel, Runtime (nur Programme).
check_component() { # check_component <pfad> <bezeichnung> <programm: 1|0>
  local dv
  dv="$(codesign -dvvv "$1" 2>&1)"
  if echo "$dv" | grep -q 'Signature=adhoc'; then
    dev_bad "$2: ad hoc signiert, keine Developer ID (BF-03)"
  elif echo "$dv" | grep -qE '^Authority=Developer ID Application: '; then
    ok "$2: Developer ID Application"
  else
    dev_bad "$2: nicht mit „Developer ID Application“ signiert ($(echo "$dv" | sed -nE 's/^Authority=//p' | head -1))"
  fi
  local team; team="$(echo "$dv" | sed -nE 's/^TeamIdentifier=//p')"
  [ "$team" = "not set" ] && team=""
  [ "$team" = "$TEAM_ID" ] && ok "$2: Team $TEAM_ID" || dev_bad "$2: Team „${team:-<keins>}“ statt $TEAM_ID"
  echo "$dv" | grep -qE '^Timestamp=' && ok "$2: sicherer Zeitstempel" || dev_bad "$2: kein sicherer Zeitstempel"
  if [ "$3" = "1" ]; then
    echo "$dv" | grep -qE '^CodeDirectory.*flags=.*runtime' && ok "$2: Hardened Runtime" || bad "$2: Hardened Runtime nicht aktiv"
  fi
}

nach_build() {
  APP="${APP:-build/MikaPlusPlayer.app}"
  echo "== nach-build · Bundle $APP (FB-03/FB-04/FB-05, BF-03, BF-09) =="
  if [ ! -d "$APP" ]; then bad "kein Bundle unter $APP"; return; fi
  codesign --verify --deep --strict "$APP" 2>/dev/null && ok "codesign --verify --deep --strict" || bad "Code-Signatur ungültig (codesign --verify --deep --strict)"
  check_component "$APP" "App" 1
  # Eingebettete Komponenten: Frameworks, Hilfsprogramme, XPC-Dienste (Sparkle, VLCKit)
  while IFS= read -r part; do
    [ -n "$part" ] || continue
    case "$part" in
      *.framework) check_component "$part" "${part#"$APP"/Contents/}" 0 ;;
      *) check_component "$part" "${part#"$APP"/Contents/}" 1 ;;
    esac
  done < <(find "$APP/Contents/Frameworks" ! -type l \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name 'Autoupdate' \) 2>/dev/null | sort)

  ENTS="$(mktemp)"; codesign -d --entitlements - --xml "$APP" > "$ENTS" 2>/dev/null
  [ "$(plist_get com.apple.security.get-task-allow "$ENTS")" = "true" ] && bad "get-task-allow im Bundle (Debug-Berechtigung im Release)" || ok "kein get-task-allow"
  [ "$(plist_get com.apple.security.cs.disable-library-validation "$ENTS")" = "true" ] && bad "disable-library-validation gesetzt (BF-09: mit Developer ID nicht mehr nötig)" || ok "kein disable-library-validation"
  rm -f "$ENTS"

  PL="$APP/Contents/Info.plist"
  [ "$(plist_get CFBundleIdentifier "$PL")" = "$BUNDLE_ID" ] && ok "Bundle-ID $BUNDLE_ID" || bad "Bundle-ID $(plist_get CFBundleIdentifier "$PL") ≠ $BUNDLE_ID (Debug-Build statt Release?)"
  [ "$(plist_get CFBundleVersion "$PL")" = "$BUILD" ] && ok "CFBundleVersion $BUILD = project.yml" || bad "CFBundleVersion $(plist_get CFBundleVersion "$PL") ≠ CURRENT_PROJECT_VERSION $BUILD (Build veraltet?)"
  [ "$(plist_get CFBundleShortVersionString "$PL")" = "$MARKETING" ] && ok "CFBundleShortVersionString $MARKETING = project.yml" || bad "CFBundleShortVersionString $(plist_get CFBundleShortVersionString "$PL") ≠ MARKETING_VERSION $MARKETING"
  [ "$(plist_get SUFeedURL "$PL")" = "$FEEDURL" ] && ok "SUFeedURL im Bundle = Info.plist" || bad "SUFeedURL im Bundle weicht ab: $(plist_get SUFeedURL "$PL")"
  [ "$(plist_get SUPublicEDKey "$PL")" = "$PUBKEY" ] && ok "SUPublicEDKey im Bundle = Info.plist" || bad "SUPublicEDKey im Bundle weicht ab"
  [ "$(plist_get SUVerifyUpdateBeforeExtraction "$PL")" = "true" ] && ok "SUVerifyUpdateBeforeExtraction im Bundle" || bad "SUVerifyUpdateBeforeExtraction fehlt im Bundle"
  [ "$(plist_get SURequireSignedFeed "$PL")" = "true" ] && ok "SURequireSignedFeed im Bundle" || bad "SURequireSignedFeed fehlt im Bundle (BF-08)"
  [ "$(plist_get CFBundleDevelopmentRegion "$PL")" = "de" ] && ok "Entwicklungssprache de" || bad "CFBundleDevelopmentRegion „$(plist_get CFBundleDevelopmentRegion "$PL")“ statt de (OF-01)"
  LOCS="$(plist_get CFBundleLocalizations "$PL" | sed -nE 's/^[[:space:]]+([^[:space:]]+)$/\1/p' | tr '\n' ' ')"
  [ "$LOCS" = "de " ] && ok "Lokalisierung [de]" || bad "CFBundleLocalizations „${LOCS}“ statt [de] (OF-01)"

  if [ -n "${DMG:-}" ]; then dmg_checks; fi
}

# DMG enthält genau das geprüfte Bundle und trägt den erwarteten Namen.
dmg_checks() {
  echo "== DMG ${DMG:-<keins>} (FB-05/FB-13) =="
  if [ -z "${DMG:-}" ] || [ ! -f "$DMG" ]; then bad "kein DMG"; return; fi
  [ "$(basename "$DMG")" = "MikaPlusPlayer-v$MARKETING.dmg" ] && ok "DMG-Name passt zur Version" || bad "DMG-Name $(basename "$DMG") ≠ MikaPlusPlayer-v$MARKETING.dmg"
  MNT="$(mktemp -d)"
  if hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$DMG" >/dev/null 2>&1; then
    INNER="$MNT/MikaPlusPlayer.app"
    if [ -d "$INNER" ]; then
      H_APP="$(codesign -dvvv "$APP" 2>&1 | sed -nE 's/^CDHash=//p')"
      H_DMG="$(codesign -dvvv "$INNER" 2>&1 | sed -nE 's/^CDHash=//p')"
      [ -n "$H_APP" ] && [ "$H_APP" = "$H_DMG" ] && ok "App im DMG ist das geprüfte Bundle (CDHash $H_APP)" || bad "App im DMG weicht vom geprüften Bundle ab (CDHash ${H_DMG:-?} ≠ ${H_APP:-?})"
    else bad "DMG enthält keine MikaPlusPlayer.app"; fi
    hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || hdiutil detach "$MNT" -force -quiet >/dev/null 2>&1
  else bad "DMG lässt sich nicht einhängen"; fi
  rmdir "$MNT" 2>/dev/null
}

# ---------------------------------------------------------------------------------------------
nach_heften() {
  APP="${APP:-build/MikaPlusPlayer.app}"
  DMG="${DMG:-$(ls -1 dist/*.dmg 2>/dev/null | head -1)}"
  dmg_checks
  [ -n "${DMG:-}" ] && [ -f "$DMG" ] || return
  echo "== nach-heften · Signatur, Ticket, Gatekeeper (BF-03) =="
  DV="$(codesign -dvvv "$DMG" 2>&1)"
  if echo "$DV" | grep -qE '^Authority=Developer ID Application: '; then ok "DMG mit Developer ID signiert"
  else dev_bad "DMG nicht mit Developer ID signiert"; fi
  local team; team="$(echo "$DV" | sed -nE 's/^TeamIdentifier=//p')"; [ "$team" = "not set" ] && team=""
  [ "$team" = "$TEAM_ID" ] && ok "DMG: Team $TEAM_ID" || dev_bad "DMG: Team „${team:-<keins>}“ statt $TEAM_ID"
  $STAPLER validate "$DMG" >/dev/null 2>&1 && ok "Notarisierungs-Ticket geheftet und gültig" || dev_bad "kein gültiges Notarisierungs-Ticket am DMG (stapler validate)"
  spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | grep -q accepted && ok "Gatekeeper nimmt das DMG an" || dev_bad "Gatekeeper lehnt das DMG ab"
  spctl -a -vv -t exec "$APP" 2>&1 | grep -q accepted && ok "Gatekeeper nimmt die App an" || dev_bad "Gatekeeper lehnt die App ab"
}

# ---------------------------------------------------------------------------------------------
feed() {
  FEED="${FEED:?FEED=<neuer appcast> fehlt}"
  BASE="${BASE_FEED:-$APPCAST}"
  DMG="${DMG:?DMG=<Release-DMG> fehlt}"
  echo "== feed · $FEED gegen $BASE (FB-10/FB-11, BF-47, BF-48) =="
  [ -f "$FEED" ] || { bad "neuer Feed fehlt"; return; }
  xmllint --noout "$FEED" 2>/dev/null && ok "gültiges XML" || bad "Feed ist kein gültiges XML"
  TITLE="$(xpath 'string(/rss/channel/title)' "$FEED")"
  [ "$TITLE" = "$(xpath 'string(/rss/channel/title)' "$BASE")" ] && ok "Kanaltitel unverändert („${TITLE}“)" || bad "Kanaltitel geändert: „${TITLE}“"
  grep -qi mukaarts "$FEED" && bad "neuer Feed enthält Mukaarts-URLs" || ok "keine Mukaarts-URLs"
  check_download_urls "$FEED" "neuer Feed"

  # release.sh ruft generate_appcast mit --maximum-versions 0 auf: Es behält alle Einträge. Erwartet sind also genau die
  # Einträge des versionierten Feeds plus der neue (BF-47).
  EXPECTED="$( (feed_versions "$BASE"; echo "$BUILD") | sort -n | uniq | tr '\n' ' ')"
  ACTUAL="$(feed_versions "$FEED" | tr '\n' ' ')"
  [ "$ACTUAL" = "$EXPECTED" ] && ok "Einträge = versionierter Feed + Build $BUILD ($ACTUAL)" || bad "Einträge weichen ab: ${ACTUAL:-<keine>} statt $EXPECTED (Altstand zurück oder Eintrag verloren?)"
  for V in $(feed_versions "$BASE"); do
    if [ "$(item_attr "$FEED" "$V" url)" = "$(item_attr "$BASE" "$V" url)" ] && [ "$(item_attr "$FEED" "$V" edSignature)" = "$(item_attr "$BASE" "$V" edSignature)" ]; then
      ok "bestehender Eintrag $V unverändert"
    else bad "bestehender Eintrag $V verändert (URL oder Signatur)"; fi
  done

  URL="$(item_attr "$FEED" "$BUILD" url)"
  WANT="${DOWNLOAD_PREFIX}v$MARKETING/$(basename "$DMG")"
  [ "$URL" = "$WANT" ] && ok "Download-URL $URL" || bad "Download-URL ${URL:-<fehlt>} ≠ $WANT"
  SHORT="$(xpath "string(//item[*[local-name()='version']='$BUILD']/*[local-name()='shortVersionString'])" "$FEED")"
  [ "$SHORT" = "$MARKETING" ] && ok "shortVersionString $MARKETING" || bad "shortVersionString ${SHORT:-<fehlt>} ≠ $MARKETING"
  LEN="$(item_attr "$FEED" "$BUILD" length)"
  SIZE="$(stat -f %z "$DMG" 2>/dev/null)"
  [ -n "$LEN" ] && [ "$LEN" = "$SIZE" ] && ok "length $LEN = DMG-Größe" || bad "length ${LEN:-<fehlt>} ≠ DMG-Größe $SIZE"
  SIG="$(item_attr "$FEED" "$BUILD" edSignature)"
  if [ -z "$SIG" ]; then bad "neuer Eintrag ohne sparkle:edSignature"
  elif ed25519 archiv "$PUBKEY" "$DMG" "$SIG" >/dev/null 2>&1; then ok "EdDSA-Signatur des DMG gültig gegen SUPublicEDKey"
  else bad "EdDSA-Signatur des DMG passt NICHT zu SUPublicEDKey (falscher Schlüssel oder DMG verändert)"; fi

  ed25519 feed "$PUBKEY" "$FEED" >/dev/null 2>&1; RC=$?
  case "$RC" in
    0) ok "Feed-Signatur gültig gegen SUPublicEDKey" ;;
    2) bad "Feed ist nicht signiert (release.sh signiert ihn mit sign_update)" ;;
    *) bad "Feed-Signatur ungültig" ;;
  esac
}

# ---------------------------------------------------------------------------------------------
# Nach dem Merge: Die ausgelieferte Datei muss byte-gleich mit der gemergten sein (Zeilenenden, Zwischenspeicher) und
# eine gültige Signatur tragen — an der daumedia-Adresse und an der alten Mukaarts-Adresse, die v1.1 abfragt (BF-01).
nach_merge() {
  local urls="${FEED_URLS:-https://raw.githubusercontent.com/$GH_REPO/main/appcast.xml https://raw.githubusercontent.com/Mukaarts/MikaPlusPlayer/main/appcast.xml}"
  local frist="${NACH_MERGE_FRIST:-330}" pause="${NACH_MERGE_PAUSE:-30}"
  echo "== nach-merge · ausgelieferter Feed = gemergte appcast.xml (AK-12, BF-01) =="
  [ -f "$APPCAST" ] || { bad "appcast.xml fehlt"; return; }
  local want; want="$(shasum -a 256 "$APPCAST" | cut -d' ' -f1)"
  ed25519 feed "$PUBKEY" "$APPCAST" >/dev/null 2>&1 && ok "gemergte appcast.xml: Signatur gültig" || bad "gemergte appcast.xml: Signatur ungültig oder fehlt"
  local url tmp got ende
  for url in $urls; do
    tmp="$(mktemp)"; ende=$(( $(date +%s) + frist )); got=""
    while :; do
      if curl -fsSL --max-time 30 -o "$tmp" "$url" 2>/dev/null; then got="$(shasum -a 256 "$tmp" | cut -d' ' -f1)"; else got=""; fi
      [ "$got" = "$want" ] && break
      [ "$(date +%s)" -ge "$ende" ] && break
      sleep "$pause"
    done
    if [ "$got" = "$want" ]; then
      ok "$url liefert die gemergte Datei"
      ed25519 feed "$PUBKEY" "$tmp" >/dev/null 2>&1 && ok "$url: Signatur gültig" || bad "$url: Signatur ungültig"
    else
      bad "$url liefert nach ${frist}s nicht die gemergte Datei (${got:-nicht abrufbar})"
    fi
    rm -f "$tmp"
  done
}

case "$PHASE" in
  vor-build) vor_build ;;
  nach-build) nach_build ;;
  nach-heften) nach_heften ;;
  feed) feed ;;
  nach-merge) nach_merge ;;
  alle) vor_build; if [ -d "${APP:-build/MikaPlusPlayer.app}" ]; then nach_build; else echo "== nach-build =="; skip "kein ${APP:-build/MikaPlusPlayer.app}"; fi ;;
  *) echo "Aufruf: $0 [vor-build|nach-build|nach-heften|feed|nach-merge|alle]"; exit 2 ;;
esac

echo
if [ "$STRENG" = "1" ] && [ "$OPEN" -eq 1 ]; then FAIL=1; fi
if [ "$FAIL" -eq 0 ]; then
  [ "$OPEN" -eq 1 ] && echo "== Ergebnis: keine Befunde, offene Punkte siehe [ offen] ==" || echo "== Ergebnis: keine Beanstandung =="
else
  echo "== Ergebnis: BEFUNDE — Release abbrechen =="
fi
exit "$FAIL"
