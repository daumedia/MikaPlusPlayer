#!/bin/bash
# b09_release_check.sh — Gegenprüfungen der Update-Kette (B09 · BUG-10/BUG-11).
#
# Übernommen aus dem QA-Vorschlag (Durchlauf 1, 2026-09-15) und in scripts/release.sh eingehängt.
# Findet, repariert nicht.
#
#   bash scripts/b09_release_check.sh vor-build     Quellstand: Feed-Adresse, appcast.xml, Versionen, Härtung, Git
#   APP=… DMG=… bash scripts/b09_release_check.sh nach-build
#                                                   gebautes Bundle und DMG: Signatur, Entitlements, Runtime
#   APP=… DMG=… FEED=… bash scripts/b09_release_check.sh feed
#                                                   neuer Feed gegen die versionierte appcast.xml
#   bash scripts/b09_release_check.sh               vor-build, dazu nach-build, falls build/MikaPlusPlayer.app existiert
#
# Ergebnisarten:
#   [BEFUND]  blockiert das Release (Exit 1)
#   [ offen]  bekannter offener Punkt, der Apple-Team, Schlüssel oder eine Nutzerentscheidung braucht
#             (BUG-03, BUG-08 Feed-Pflicht, BUG-09). Blockiert nur mit STRENG=1.
#   [  ok  ]  bestanden
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
FAIL=0
OPEN=0

note() { printf '  [%s] %s\n' "$1" "$2"; }
bad()  { note "BEFUND" "$1"; FAIL=1; }
open_() { note " offen" "$1"; OPEN=1; }
ok()   { note "  ok  " "$1"; }
skip() { note " skip " "$1"; }

plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null; }
yml_value() { # erster Wert eines Schlüssels in project.yml (ohne Anführungszeichen)
  sed -nE "s/^[[:space:]]*$1:[[:space:]]*\"?([^\"#[:space:]]+)\"?.*$/\1/p" project.yml | head -1
}
feed_versions() { grep -oE '<sparkle:version>[^<]+</sparkle:version>' "$1" 2>/dev/null | sed -E 's/<[^>]+>//g' | sort -n; }
feed_short_versions() { grep -oE '<sparkle:shortVersionString>[^<]+</sparkle:shortVersionString>' "$1" 2>/dev/null | sed -E 's/<[^>]+>//g'; }
max_feed_version() { feed_versions "$1" | tail -1; }
xpath() { xmllint --xpath "$1" "$2" 2>/dev/null; }
item_attr() { # item_attr <feed> <sparkle:version> <url|length|edSignature>
  xpath "string(//item[*[local-name()='version']='$2']/enclosure/@*[local-name()='$3'])" "$1"
}
ed25519() { xcrun swift "$ROOT/scripts/b09_ed25519.swift" "$@"; }

MARKETING="$(yml_value MARKETING_VERSION)"
BUILD="$(yml_value CURRENT_PROJECT_VERSION)"
PUBKEY="$(plist_get SUPublicEDKey "$INFO")"
FEEDURL="$(plist_get SUFeedURL "$INFO")"

# ---------------------------------------------------------------------------------------------
vor_build() {
  echo "== vor-build · Feed-Adresse (FB-01) =="
  case "$FEEDURL" in
    *[Mm]ukaarts*) bad "SUFeedURL zeigt auf den freien Mukaarts-Namensraum: $FEEDURL" ;;
    "https://raw.githubusercontent.com/$GH_REPO/main/appcast.xml") ok "SUFeedURL: $FEEDURL" ;;
    *) bad "SUFeedURL passt nicht zu GH_REPO=$GH_REPO: ${FEEDURL:-<fehlt>}" ;;
  esac
  [ -n "$PUBKEY" ] && ok "SUPublicEDKey vorhanden" || bad "SUPublicEDKey fehlt in $INFO"

  echo "== vor-build · versionierte appcast.xml (FB-10) =="
  if [ ! -f "$APPCAST" ]; then bad "appcast.xml fehlt im Repository"; else
    grep -qi mukaarts "$APPCAST" && bad "appcast.xml enthält Mukaarts-URLs" || ok "keine Mukaarts-URLs"
    feed_versions "$APPCAST" | grep -qx 1 && bad "nie veröffentlichter 1.0-Eintrag (sparkle:version 1) in appcast.xml" || ok "kein 1.0-Eintrag"
    TITLE="$(xpath 'string(/rss/channel/title)' "$APPCAST")"
    [ "$TITLE" = "Mika+Player" ] && ok "Kanaltitel „Mika+Player“" || bad "Kanaltitel „${TITLE}“ statt „Mika+Player“"
  fi
  if [ -f dist/appcast.xml ] && grep -qi mukaarts dist/appcast.xml; then
    skip "dist/appcast.xml ist Altstand (1.0/Mukaarts) — wird von release.sh nicht mehr verwendet"
  fi

  echo "== vor-build · Versionen (FB-02) =="
  HIGHEST="$(max_feed_version "$APPCAST")"
  if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
    bad "CURRENT_PROJECT_VERSION ist keine ganze Zahl: ${BUILD:-<fehlt>}"
  elif [ -n "$HIGHEST" ] && [ "$BUILD" -le "$HIGHEST" ]; then
    bad "CURRENT_PROJECT_VERSION=$BUILD ist nicht größer als die höchste sparkle:version $HIGHEST im Feed — keine Installation bekäme das Update"
  else
    ok "CURRENT_PROJECT_VERSION=$BUILD > höchste sparkle:version ${HIGHEST:-<keine>}"
  fi
  if feed_short_versions "$APPCAST" | grep -qxF "$MARKETING"; then
    bad "MARKETING_VERSION=$MARKETING ist schon veröffentlicht (Tag v$MARKETING und DMG-Name kollidieren) — Anzeigeversion anheben"
  else
    ok "MARKETING_VERSION=$MARKETING noch nicht im Feed"
  fi

  echo "== vor-build · Härtung und Sparkle-Konfiguration (FB-03/FB-08/FB-12) =="
  grep -qE '^[[:space:]]*ENABLE_HARDENED_RUNTIME:[[:space:]]*YES' project.yml && ok "ENABLE_HARDENED_RUNTIME: YES" || bad "Hardened Runtime im Release nicht aktiviert (project.yml)"
  grep -qE '^[[:space:]]*CODE_SIGN_INJECT_BASE_ENTITLEMENTS:[[:space:]]*NO' project.yml && ok "CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO (kein get-task-allow)" || bad "CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO fehlt — Release bekäme get-task-allow"
  if awk '/^  Sparkle:/{s=1;next} s&&/^  [^ ]/{s=0} s' project.yml | grep -qE 'exactVersion:'; then
    ok "Sparkle exakt gepinnt ($(awk '/^  Sparkle:/{s=1;next} s&&/^  [^ ]/{s=0} s' project.yml | sed -nE 's/.*exactVersion:[[:space:]]*"?([^"]+)"?.*/\1/p'))"
  else bad "Sparkle nicht mit exactVersion gepinnt"; fi
  [ "$(plist_get SUVerifyUpdateBeforeExtraction "$INFO")" = "true" ] && ok "SUVerifyUpdateBeforeExtraction gesetzt" || bad "SUVerifyUpdateBeforeExtraction fehlt — DMG würde vor der Signaturprüfung eingehängt"
  if [ "$(plist_get SURequireSignedFeed "$INFO")" = "true" ]; then
    ok "SURequireSignedFeed gesetzt"
  else
    open_ "SURequireSignedFeed fehlt (BUG-08) — erst setzen, wenn die veröffentlichte appcast.xml signiert ist"
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
nach_build() {
  APP="${APP:-build/MikaPlusPlayer.app}"
  echo "== nach-build · Bundle $APP (FB-03/FB-04/FB-05) =="
  if [ ! -d "$APP" ]; then bad "kein Bundle unter $APP"; return; fi
  codesign --verify --deep --strict "$APP" 2>/dev/null && ok "codesign --verify --deep --strict" || bad "Code-Signatur ungültig (codesign --verify --deep --strict)"
  ENTS="$(mktemp)"; codesign -d --entitlements - --xml "$APP" > "$ENTS" 2>/dev/null
  [ "$(plist_get com.apple.security.get-task-allow "$ENTS")" = "true" ] && bad "get-task-allow im Bundle (Debug-Berechtigung im Release)" || ok "kein get-task-allow"
  [ "$(plist_get com.apple.security.cs.disable-library-validation "$ENTS")" = "true" ] && open_ "disable-library-validation gesetzt (BUG-09: bei ad-hoc-Signatur nötig, mit Developer ID entfernen)"
  rm -f "$ENTS"
  DV="$(codesign -dv "$APP" 2>&1)"
  echo "$DV" | grep -qE '^CodeDirectory.*flags=.*runtime' && ok "Hardened Runtime aktiv" || bad "Hardened Runtime nicht aktiv"
  if echo "$DV" | grep -q 'Signature=adhoc'; then
    open_ "ad-hoc signiert, keine Developer ID (BUG-03)"
  else ok "nicht ad-hoc signiert"; fi
  spctl -a -vv "$APP" 2>&1 | grep -q accepted && ok "spctl akzeptiert das Bundle" || open_ "spctl lehnt das Bundle ab (nicht notarisiert, BUG-03)"

  PL="$APP/Contents/Info.plist"
  [ "$(plist_get CFBundleVersion "$PL")" = "$BUILD" ] && ok "CFBundleVersion $BUILD = project.yml" || bad "CFBundleVersion $(plist_get CFBundleVersion "$PL") ≠ CURRENT_PROJECT_VERSION $BUILD (Build veraltet?)"
  [ "$(plist_get CFBundleShortVersionString "$PL")" = "$MARKETING" ] && ok "CFBundleShortVersionString $MARKETING = project.yml" || bad "CFBundleShortVersionString $(plist_get CFBundleShortVersionString "$PL") ≠ MARKETING_VERSION $MARKETING"
  [ "$(plist_get SUFeedURL "$PL")" = "$FEEDURL" ] && ok "SUFeedURL im Bundle = Info.plist" || bad "SUFeedURL im Bundle weicht ab: $(plist_get SUFeedURL "$PL")"
  [ "$(plist_get SUPublicEDKey "$PL")" = "$PUBKEY" ] && ok "SUPublicEDKey im Bundle = Info.plist" || bad "SUPublicEDKey im Bundle weicht ab"
  [ "$(plist_get SUVerifyUpdateBeforeExtraction "$PL")" = "true" ] && ok "SUVerifyUpdateBeforeExtraction im Bundle" || bad "SUVerifyUpdateBeforeExtraction fehlt im Bundle"

  DMG="${DMG:-$(ls -1 dist/*.dmg 2>/dev/null | head -1)}"
  echo "== nach-build · DMG ${DMG:-<keins>} (FB-05/FB-13) =="
  if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then bad "kein DMG"; return; fi
  [ "$(basename "$DMG")" = "MikaPlusPlayer-v$MARKETING.dmg" ] && ok "DMG-Name passt zur Version" || bad "DMG-Name $(basename "$DMG") ≠ MikaPlusPlayer-v$MARKETING.dmg"
  if spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | grep -q accepted; then ok "DMG signiert/akzeptiert"; else open_ "DMG ohne verwertbare Signatur (BUG-03)"; fi
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
feed() {
  FEED="${FEED:?FEED=<neuer appcast> fehlt}"
  BASE="${BASE_FEED:-$APPCAST}"
  DMG="${DMG:?DMG=<Release-DMG> fehlt}"
  echo "== feed · $FEED gegen $BASE (FB-10/FB-11) =="
  [ -f "$FEED" ] || { bad "neuer Feed fehlt"; return; }
  xmllint --noout "$FEED" 2>/dev/null && ok "gültiges XML" || bad "Feed ist kein gültiges XML"
  TITLE="$(xpath 'string(/rss/channel/title)' "$FEED")"
  [ "$TITLE" = "$(xpath 'string(/rss/channel/title)' "$BASE")" ] && ok "Kanaltitel unverändert („${TITLE}“)" || bad "Kanaltitel geändert: „${TITLE}“"
  grep -qi mukaarts "$FEED" && bad "neuer Feed enthält Mukaarts-URLs" || ok "keine Mukaarts-URLs"

  EXPECTED="$( (feed_versions "$BASE"; echo "$BUILD") | sort -n | uniq | tr '\n' ' ')"
  ACTUAL="$(feed_versions "$FEED" | tr '\n' ' ')"
  [ "$ACTUAL" = "$EXPECTED" ] && ok "Einträge = versionierter Feed + Build $BUILD ($ACTUAL)" || bad "Einträge weichen ab: ${ACTUAL:-<keine>} statt $EXPECTED (Altstand zurück oder Eintrag verloren?)"
  for V in $(feed_versions "$BASE"); do
    if [ "$(item_attr "$FEED" "$V" url)" = "$(item_attr "$BASE" "$V" url)" ] && [ "$(item_attr "$FEED" "$V" edSignature)" = "$(item_attr "$BASE" "$V" edSignature)" ]; then
      ok "bestehender Eintrag $V unverändert"
    else bad "bestehender Eintrag $V verändert (URL oder Signatur)"; fi
  done

  URL="$(item_attr "$FEED" "$BUILD" url)"
  WANT="https://github.com/$GH_REPO/releases/download/v$MARKETING/$(basename "$DMG")"
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

case "$PHASE" in
  vor-build) vor_build ;;
  nach-build) nach_build ;;
  feed) feed ;;
  alle) vor_build; if [ -d "${APP:-build/MikaPlusPlayer.app}" ]; then nach_build; else echo "== nach-build =="; skip "kein ${APP:-build/MikaPlusPlayer.app}"; fi ;;
  *) echo "Aufruf: $0 [vor-build|nach-build|feed|alle]"; exit 2 ;;
esac

echo
if [ "$STRENG" = "1" ] && [ "$OPEN" -eq 1 ]; then FAIL=1; fi
if [ "$FAIL" -eq 0 ]; then
  [ "$OPEN" -eq 1 ] && echo "== Ergebnis: keine Befunde, offene Punkte siehe [ offen] ==" || echo "== Ergebnis: keine Beanstandung =="
else
  echo "== Ergebnis: BEFUNDE — Release abbrechen =="
fi
exit "$FAIL"
