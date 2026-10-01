# B10 · Website — Build-Bericht (Fehlerauftrag, **Teil 1** und **Teil 2**)

> **Teil 2 (2026-09-30)** steht unten im Abschnitt *Teil 2*. Behoben: BUG-02, BUG-07 und die übergebenen
> Website-Befunde BF-12, BF-16, BF-25, BF-81, BF-103, BF-107 sowie die Website-Hinweise aus B02, B05 und B08.
> **Offen:** BUG-01 (Vercel) und BUG-03 (Angaben des Nutzers).

Stand: 2026-09-16 · Eingang: Fehlerauftrag aus `qa-report.md` (Durchlauf 1, Status `review`) · Branch `sdd/rueckerfassung`, nichts committet
Stack: `nextjs-supabase` (nur Next.js-Teil) · Arbeitsbereich: nur `web/` und `features/B10-website/`

> **Das ist Teil 1.** Er behebt die website-internen Befunde, die nicht vom App-Verhalten abhängen:
> BUG-04, BUG-05, BUG-06, BUG-08, BUG-09, BUG-10 und BUG-11.
> **Offen für Teil 2** (nach den App-Reparaturen): **BUG-02** (Datenschutzerklärung und App-Verhalten), **BUG-03**
> (Pflichtangaben, braucht Nutzerangaben) und **BUG-07** (Werbeaussagen und Release).
> **BUG-01** (Seite nicht öffentlich) braucht Vercel-Zugang und ist nicht behoben.
> Keine Statusänderung in `features/index.md`. Nächster Schritt nach Teil 2: `/sdd-qa B10` (Durchlauf 2).

## 1 · Umgesetzt

Die Website fällt bei einer GitHub-Störung nicht mehr still auf das fest verdrahtete v1.1-DMG zurück. Sie verlinkt
dann die Seite des neuesten Releases, der Changelog zeigt einen Hinweis. Ein neues Release ohne DMG verlinkt seine
eigene Release-Seite. `/download` erzeugt im Fehlerfall höchstens eine GitHub-Anfrage je 5-Minuten-Fenster, und
gleichzeitige Aufrufe teilen sich eine Anfrage. `next` steht auf 16.3.3, `npm audit --omit=dev` ist leer.

Die Erststart-Anleitung beschreibt den Weg über Systemeinstellungen → Datenschutz & Sicherheit → „Open Anyway" und
nennt für macOS 14 zusätzlich Control-Klick → Öffnen. Beides ist durch Apple-Quellen belegt. Die Anleitung enthält
einen Prüfschritt mit `shasum -a 256`. Die SHA-256-Prüfsumme kommt aus dem Asset-`digest` der GitHub-API und steht
unter beiden Download-Schaltflächen und je Release im Changelog.

Alle Routen senden eine Content-Security-Policy und eine Permissions-Policy. Die Seiten rendern darunter ohne
Verstöße, das ist im Browser nachgewiesen, und eine Negativkontrolle schlägt an. Release-Notizen enthalten kein
`node="[object Object]"` mehr. Unterseiten haben eigenes `og:url`/`og:title`/`og:description` und behalten das
Vorschaubild.

| BUG | Grad | Ergebnis | Nachweis (Test) |
|---|---|---|---|
| BUG-04 | mittel | behoben, Teilaspekt „Limit je Client" offen (OF-06) | `M::AK-34/FB-21` (vorher todo), `M::AK-15`, `U::BUG-04` ×2 |
| BUG-05 | mittel | behoben | `H::FB-22` (vorher todo), `npm audit` unten |
| BUG-06 | mittel | behoben; Notarisierung bleibt B09 BUG-03 | `H::AK-09`, `H::AK-18/AK-19`, `H::AK-22/AK-23`, `U::BUG-06`, `M::AK-18/EC-04` |
| BUG-08 | mittel | behoben | `M::AK-34 (BUG-08)`, `U::AK-16/EC-03`, `U::AK-18`, `U::AK-32/AK-39`, `U::AK-33`, Gegenprobe mit totem API-Host |
| BUG-09 | niedrig | behoben; Restrisiko `'unsafe-inline'` (OF-05) | `H::FB-20` (vorher todo), **neu** `B::FB-20 (BUG-09)`, Negativkontrolle |
| BUG-10 | niedrig | behoben | `M::EC-07` (vorher todo) |
| BUG-11 | niedrig | behoben | `H::Hinweis (Code-Review)` (vorher todo, erweitert) |

Reihenfolge der Arbeit: zuerst BUG-05 als Versionsbasis, dann BUG-08 und BUG-04 (dieselbe Datei), BUG-06, BUG-09,
BUG-10 und BUG-11. Vor der ersten Änderung ist jeder BUG über seinen QA-Test reproduziert worden:

- BUG-04: 4 + 60 Aufrufe → 64 Upstream-Anfragen
- BUG-10: 7 Treffer
- BUG-05, BUG-09, BUG-11: die `todo`-Tests schlugen fehl

Danach sind alle erneut ausgeführt.

### Verifikation (gefiltert)

`npx tsc --noEmit && npm run lint && npm run build` (ohne `GITHUB_TOKEN`/`NEXT_PUBLIC_SITE_URL`, Node 26.8.2):

```
tsc exit 0
> eslint
lint exit 0
▲ Next.js 16.3.3 (Turbopack)
✓ Compiled successfully in 500ms
Route (app)           Revalidate  Expire
┌ ○ /                         1h      1y
├ ○ /_not-found
├ ○ /apple-icon.png
├ ○ /changelog                1h      1y
├ ƒ /download
├ ○ /icon.png
├ ○ /opengraph-image
├ ○ /privacy
├ ○ /robots.txt
├ ○ /sitemap.xml
└ ○ /support
build exit 0
```

Testsuite gegen `next start -H 127.0.0.1 -p 3919`, danach beendet (Port 3919 antwortet danach nicht mehr, kein
`next-server`-Prozess übrig): `BASE_URL=http://127.0.0.1:3919 node --test --test-timeout=600000 tests/`

```
suite exit 0
ℹ /: CSP-Verstöße 0   ℹ /changelog: CSP-Verstöße 0   ℹ /privacy: CSP-Verstöße 0   ℹ /support: CSP-Verstöße 0
ℹ Konsole/Log/Netz: 0 Fehler oder Warnungen
ℹ im Fenster: 4 sequentielle Aufrufe → 0 Upstream-Anfragen; 60 parallele Aufrufe → 0 Upstream-Anfragen; Status: 302; neue Warnzeilen: 0
ℹ nach Ablauf des Fensters: 60 parallele Aufrufe → 1 Upstream-Anfrage(n)
ℹ 6 Aufrufe nach 200 → 0 Upstream-Anfragen
⚠ FB-15 (Befund) … # BUG-01 Website öffentlich nicht erreichbar
⚠ FB-03/FB-04/FB-05 (Befund) … # BUG-02 Datenschutzaussagen widersprechen dem App-Verhalten
⚠ FB-16/FB-17/FB-18 (Befund) … # BUG-03 Pflichtangaben fehlen
ℹ tests 65
ℹ pass 62
ℹ fail 0
ℹ todo 3
```

Vorher (Durchlauf 1): 61 Tests, 53 bestanden, 8 `todo`. Jetzt: 65 Tests, 62 bestanden, 3 `todo` (BUG-01, -02, -03).
Hinzugekommen sind 4 Tests:

- `U::BUG-06`
- `U::BUG-04` ×2
- `B::FB-20 (BUG-09)`

`npm audit`:

```
vorher  --omit=dev: {"high":3,"critical":1,"total":4}  (next GHSA-2xp9-vwfh-vxw4 + GHSA-p293-qw3h-jr36, postcss, sharp, nanoid)
nachher --omit=dev: found 0 vulnerabilities
nachher inkl. dev:  js-yaml 4.0.0 - 4.3.1 · Severity: high · GHSA-2883-xcg3-v3hh · 1 high severity vulnerability
npm ls: next@16.3.3 · eslint-config-next@16.3.3 · sharp@0.35.4 · postcss@8.5.23 · nanoid@3.3.19
```

Negativkontrolle BUG-09: Build-Kopie im Scratchpad mit zusätzlichem `script-src-elem 'self'` und API-Host
`api.github.invalid`, danach gelöscht.

```
✖ FB-20 (BUG-09): CSP und Permissions-Policy aktiv — …
ℹ /: CSP-Verstöße 17
  AssertionError [ERR_ASSERTION]: /: CSP-Verstöße   (directive: 'script-src-elem' ×17)
```

In derselben Kopie wurde der Ersatzpfad aus BUG-08 und BUG-04 mit unerreichbarem GitHub geprüft:

- Build: `[releases] request failed …` für beide Abfragen, `build exit 0`
- `/`: beide Schaltflächen `href="https://github.com/daumedia/MikaPlusPlayer/releases/latest"`, „Latest release on GitHub", kein „Version 1.1", keine Prüfsumme
- `/changelog`: „The version list could not be loaded from GitHub just now. Every release … is on the GitHub releases page", 0 `<article>`
- `/download` ×6: 6 × `302 https://github.com/daumedia/MikaPlusPlayer/releases/latest`, **1** Warnzeile im Serverprotokoll

`next dev` in der Kopie mit der echten `next.config.ts`: CSP enthält `'unsafe-eval'`. Der Browser-Test (Kopie mit
gelockertem Header-Regex) meldet 0 Verstöße und 0 Warnungen.

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-01** (hoch) — nicht behoben. Deployment Protection, Domain und Repository-Homepage liegen bei Vercel und
  GitHub; der Auftrag schließt diese Zugänge aus, die Adresse entscheidet der Nutzer (OF-04). Erneut beobachtet
  (`L::FB-15`, 2026-09-16):
  - `mikaplus-player.vercel.app/privacy` → 404 `DEPLOYMENT_NOT_FOUND`
  - letztes Production-Deployment → 302 `vercel.com/sso-api` mit `_vercel_sso_nonce`
  - `mikaplusplayer.com` → `ENOTFOUND`
- **BUG-02** (hoch) — Teil 2. Die Texte sollen das App-Verhalten *nach* den B01-Reparaturen beschreiben (Keychain,
  Cache, Store-Name), die gerade parallel laufen.
- **BUG-03** (hoch) — Teil 2. Braucht Verantwortlichen, Anschrift und Kontakt-E-Mail vom Nutzer sowie seine
  rechtliche Bewertung.
- **BUG-07** (mittel) — Teil 2. Die Aussagen hängen am App-Stand und am nächsten Release (B02, B07, B09); Lizenz und
  Sprachhinweis sind Nutzerentscheidungen. Dazu gehört der App-Name in den Erststart-Schritten („Mika+Player" statt
  `MikaPlusPlayer.app`, FB-12). Er wurde in den neuen BUG-06-Texten bewusst nicht angefasst.
- **BUG-04, Teilaspekt „Limit je Client"** — nicht in der Anwendung lösbar:
  - Ein verlässliches Limit je Client auf Vercel braucht gemeinsamen Speicher, also eine neue Abhängigkeit.
  - Richtiger Ort ist eine Rate-Limit-Regel der Vercel Firewall für `/download` plus ein gesetztes `GITHUB_TOKEN`
    (5000 statt 60 Anfragen je Stunde), beides mit Vercel-Zugang (OF-06).
  - Das eingebaute Fehlerfenster wirkt je Server-Prozess, auf Vercel also je warmer Funktionsinstanz.
  - Getestet: 60 gleichzeitige Aufrufe ergeben weiterhin 60 × 302, es gibt kein 429.
- **BUG-06, Notarisierung** — braucht Developer ID und Apple-Team (B09 BUG-03). Dass „Open Anyway" auf macOS 27
  tatsächlich freigibt, ist weiter **nicht ausgeführt**: Es gibt keine Finder-Klick-Automatisierung, und wegen der
  Tonvorgabe wurde keine App gestartet. Belegt ist der Weg durch Apple-Quellen:
  - „Updates to runtime protection in macOS Sequoia", developer.apple.com/news/?id=saqachfa, 6. August 2024
  - Mac User Guide „Open a Mac app from an unknown developer" (mh40616), aktuelle Fassung und Fassung macOS 14
- **BUG-09, Restrisiko** — `script-src 'unsafe-inline'` bleibt; eine Nonce würde ISR und statische Seiten abschalten
  (OF-05).
- **Dev-Abhängigkeit** `js-yaml` (hoch, GHSA-2883-xcg3-v3hh) kommt nur über ESLint, liegt nicht im Produktionsbaum und
  war nicht Teil des Auftrags („keine weiteren Pakete").

## 3 · Getroffene Annahmen

Alle ohne Rückfrage entschieden (Zielmodus), zur Bestätigung durch den Nutzer:

1. **Fehlerfenster 5 Minuten** für `/download` (`DOWNLOAD_RETRY_AFTER_MS`). In dieser Zeit fragt `/download` nach
   einem Fehler nicht erneut, auch wenn GitHub sich schon erholt hat. Besucher landen dann höchstens 5 Minuten lang
   auf der Release-Seite statt direkt beim DMG.
2. **Das Fenster gilt nur für `/download`**, nicht für `/` und `/changelog`. Grund: Eine ISR-Neuberechnung ohne eigene
   `fetch`-Ausführung würde die stündliche Revalidierung verlieren. Die Seiten waren durch ISR ohnehin auf eine
   Neuberechnung je Stunde begrenzt.
3. **Ersatzziel `…/releases/latest`** statt der Release-Liste. Per GET geprüft: GitHub leitet auf das neueste Release
   weiter (302 → `/releases/tag/v1.1`); Vorabversionen schließt GitHub aus, wie die API.
4. **Release ohne DMG → dessen Release-Seite** statt des alten DMG. Damit gilt die Beschriftung „Version X" ohne Größe;
   OF-01 ist gegenstandslos (OF-07).
5. **Prüfsumme nur aus GitHub** (`digest`, nur `sha256:` mit 64 Hex-Zeichen). Sie weist nach, dass die Datei der am
   Release hängenden entspricht, nicht mehr. Ein kompromittiertes GitHub-Konto deckt sie nicht ab. Die Support-Seite
   sagt dazu nur „A match means the file is exactly the one attached to the GitHub release" und verspricht keinen
   Schutz darüber hinaus. Abgeglichen mit `shasum -a 256 dist/MikaPlusPlayer-v1.1.dmg` → identisch. Dass die
   GitHub-Release-Seite den digest ebenfalls zeigt, ist per GET belegt (`expanded_assets/v1.1` enthält
   `sha256:8da0620e…`). Die Seite verweist trotzdem nur auf die eigene Anzeige.
6. **`nanoid` im Lockfile angehoben** (`npm update nanoid`, 3.3.16 → 3.3.19): innerhalb der vorhandenen Range von
   `postcss`, kein neues Paket, `package.json` unverändert. Die QA hat es unter BUG-05 geführt.
7. **`sharp`-Plattformpakete:** `npm install` hat zwei optionale Lockfile-Einträge ergänzt
   (`@img/sharp-freebsd-wasm32`, `@img/sharp-webcontainers-wasm32`) sowie verschachtelte Versionen unter
   `@next/eslint-plugin-next`. Das sind Folgen der Versionsanhebung, keine neuen direkten Abhängigkeiten. npm meldet,
   dass das Install-Skript von `unrs-resolver` nicht in `allowScripts` steht; Lint und Build laufen.
8. **CSP ohne `upgrade-insecure-requests`**, anders als die Next.js-Vorlage: HSTS deckt Produktion ab, und die
   Direktive würde lokale `http://`-Prüfläufe brechen. `img-src 'self'` ohne `data:`/`blob:`, weil nichts davon
   geladen wird (im Browser mit 0 Verstößen belegt).
9. **Tests angepasst, wo sich das geprüfte Ist durch die Reparatur ändert:**
   - AK-09, AK-16, AK-18, AK-22, AK-32, AK-33, AK-34
   - In `download-upstream.test.mjs` steht der PII-Test jetzt vor den AK-34-Tests: Als erster `/download`-Aufruf
     erzeugt er genau eine Upstream-Anfrage. Die Test-Kopie verkürzt das Fenster auf 4 s (dokumentiert im Dateikopf).
   - Die Spec-Kriterien selbst sind unverändert (nur *Offene Fragen*: OF-05 bis OF-07).
10. **Kleiner Nebenbefund:** `npx prettier --version` wurde einmal zur Prüfung aufgerufen und hat Prettier dabei in den
    npx-Cache geladen, nicht ins Projekt. Formatiert wurde damit nichts.

## 4 · Systemweite Änderungen

- **Abhängigkeiten:** `next` und `eslint-config-next` 16.2.12 → 16.3.3 (`web/package.json`, `web/package-lock.json`).
  Transitiv: `postcss` 8.5.23, `sharp` 0.35.4, `nanoid` 3.3.19. Keine neue direkte Abhängigkeit.
- **Sicherheits-Header** für alle Routen, auch `next dev`: `Content-Security-Policy` und `Permissions-Policy`
  (`web/next.config.ts`). Jede künftige Fremdressource wird geblockt, etwa Analytics, eingebettete Videos, externe
  Bilder, Screenshots von fremden Hosts oder ein Kontaktformular an Dritte. Sie braucht dann eine bewusste
  CSP-Änderung.
- **Datenschicht `web/lib/releases.ts`** (API geändert):
  - `FALLBACK_RELEASE` und `Release.isFallback` entfernt.
  - `getLatestRelease()` gibt jetzt `Release | null` zurück, `getReleases()` gibt `Release[] | null` zurück.
  - `DmgAsset.sha256` ist neu, dazu `getLatestReleaseForDownload()` und `DOWNLOAD_RETRY_AFTER_MS`.
  - `DownloadButton` nimmt `Release | null`.
- **Neue Konstante** `LATEST_RELEASE_URL` in `web/lib/site.ts`.
- **Neues Modul** `web/lib/metadata.ts` (`OPEN_GRAPH_DEFAULTS`, `pageMetadata`). `/changelog`, `/privacy` und
  `/support` exportieren `generateMetadata` statt `metadata`; das Root-Layout nutzt `OPEN_GRAPH_DEFAULTS`.
- **Sichtbare Texte:**
  - Erststart-Hinweis auf `/`, Erststart-Abschnitt auf `/support` (neu mit Sprungziel `#first-launch`, fünf statt vier
    Schritte)
  - FAQ-Antwort „macOS says the app cannot be opened"
  - englischer v1.1-Ersatztext (letzter Satz)
  - neue Zeile „SHA-256 …" unter den Download-Schaltflächen und im Changelog
  - Changelog-Hinweis bei GitHub-Störung
- **Nicht angefasst:** `Sources/`, `Tests/`, `project.yml`, `scripts/` (auch nicht `scripts/release.sh`: Für den
  Ersatz muss B09 nichts mehr pflegen; der englische Ersatztext `content/changelog-overrides.ts` bleibt Handarbeit je
  Release → B09), `features/index.md`, `features/befunde.md`. Kein `xcodebuild`, kein Deployment, keine Vercel-CLI,
  nichts auf GitHub. Netz nur lesend: GitHub-API und Release-Seite per GET, Apple-Dokumentation, npm-Registry.
- **Tests unter `web/tests/`:**
  - geändert: `releases.unit.test.mjs`, `site.http.test.mjs`, `download-upstream.test.mjs`
  - ergänzt: `browser.cdp.test.mjs` (neuer CSP-Test)
  - unverändert: `live.readonly.test.mjs`

---

# Teil 2 · Fehlerauftrag 2026-09-30

Stand: 2026-09-30 · Eingang: Fehlerauftrag aus `qa-report.md` (BUG-02, BUG-07) und die an B10 übergebenen Befunde aus
`features/befunde.md` (BF-12, BF-16, BF-25, BF-81, BF-103, BF-107), dazu die Website-Hinweise in den QA-Berichten von B02
(Doppelklick-Import), B05 (Favoriten-Schlüssel, FAQ „Nowhere“) und B08 („das große Bild wandert mit“).
Branch `sdd/reparaturen`, nichts committet. Arbeitsbereich: nur `web/` und `features/B10-website/`.
Parallel liefen die B05-Reparatur und ein B04-Review; `Sources/`, `Tests/` und `project.yml` wurden nicht angefasst, kein
`xcodebuild`. Keine Statusänderung in `features/index.md`. Nächster Schritt: `/sdd-qa B10` (Durchlauf 2).

**Maßstab:** Die Website beschreibt, was man herunterladen kann. Das ist das Release **v1.1**:
- Tag `v1.1` = `907c9f8`
- `appcast.xml`: nur 1.1
- `dist/MikaPlusPlayer-v1.1.dmg`
- GitHub-Release v1.1

Jede Aussage über die App ist gegen `git show v1.1:<Datei>` abgeglichen. Die Messwerte stammen aus den QA-Durchläufen 1
von B01–B05, B08 und B09. Deren geprüfter Code ist in den betroffenen Dateien gleich v1.1: `git diff v1.1 c01f1cf --
Sources` ändert nur Bild-in-Bild-Code, drei Überschriften, einen Kommentar, das App-Symbol und `Info.plist`
(Anzeigename, Feed). Die Reparaturen auf `main` und
im Arbeitsbaum sind nicht veröffentlicht. Die Seite erwähnt sie nicht, auch nicht als „in der nächsten Version“.

## 1 · Umgesetzt

| Auftrag | Ergebnis | Nachweis (Test) |
|---|---|---|
| BUG-02 (hoch) Datenschutzerklärung | behoben | `H::FB-03/FB-04/FB-05 (BUG-02 behoben)` (vorher `todo`, erweitert), **neu** `H::BUG-02 (Soll)`, `B::AK-23/EC-11` |
| BF-12 (B09 BUG-12) User-Agent, automatische Prüfung | behoben | **neu** `H::BF-12/BF-16` |
| BF-16 (B09 BUG-16) Update-Weg | behoben | **neu** `H::BF-12/BF-16` |
| BUG-07 = BF-25 (mittel) Werbeaussagen | behoben; Lizenz offen (OF-09) | **neu** `H::BUG-07 / BF-25 / …`, `H::AK-05…`, `H::AK-11/AK-12`, `H::AK-22/AK-23` |
| BF-81 (B04 BUG-13) Leistungsaussagen | behoben (Texte = Messwerte) | `H::BUG-07 / … / BF-81 …` |
| BF-103 (B06 BUG-05) Rückmeldung je Taste | behoben | `H::BUG-07 / … / BF-103 …`, `H::AK-22/AK-23` |
| BF-107 (B07 BUG-04) Bild-in-Bild nur HLS | behoben durch Entfernen: v1.1 hat gar kein Bild-in-Bild | `H::BUG-07 / … / BF-107` |
| Hinweis B02 Doppelklick-Import | behoben | `H::BUG-07 …` |
| Hinweis B05 Favoriten „tvg-id“, FAQ „Nowhere“ | behoben | `H::BUG-07 …`, `H::FB-03…` |
| Hinweis B08 „das große Bild wandert mit“ | behoben | `H::BUG-07 …` (Bildunterschrift, „Known issue in 1.1“) |
| BUG-03 (hoch) Pflichtangaben | **nicht behoben** (Nutzerangaben), ein irreführender Satz korrigiert | `H::FB-16/FB-17/FB-18` bleibt `todo` |
| BUG-01 (hoch) Seite nicht öffentlich | **nicht behoben** (Vercel) | `L::FB-15` bleibt `todo` |

**Datenschutzseite** (`web/app/privacy/page.tsx`, neu geschrieben, Aufbau nach AK-24 erhalten). Sie gilt ausdrücklich
für „version 1.1 of the Mac app“ und verlinkt den Quelltext `tree/v1.1`. Sie beschreibt:
- **Speicherort und Kopien:**
  - `~/Library/Application Support/default.store`, nicht verschlüsselt, kein Schlüsselbund
  - Xtream-Zugangsdaten im Klartext in der Playlist-Adresse und in jeder Sender-Adresse; M3U-Link samt Token
  - für jeden Prozess des Benutzers lesbar, in Time Machine enthalten
  - HTTP-Cache `~/Library/Caches/lu.daumedia.MikaPlusPlayer` mit Zugangsdaten, Antworten, Listen und Logos
  - Cookies unter `~/Library/HTTPStorages/…`
  - Einstellungen `~/Library/Preferences/lu.daumedia.MikaPlusPlayer.plist`
  - Reste nach dem Löschen einer Playlist
- **Removing everything** (neu): Die App zu löschen entfernt nichts; Anleitung mit allen Orten. Warnung, dass
  `default.store` der SwiftData-Standardname ist und von einer anderen App ohne Sandbox geteilt werden kann;
  Time-Machine-Kopien bleiben.
- **Empfänger:** Jede Verbindung trägt die IP-Adresse. Eigene Anfragen senden einen User-Agent mit App-Name, Build und
  Netzwerk-Komponenten sowie die Systemsprache.
  - Anbieter: Weiterleitungen werden samt Zugangsdaten befolgt, Cookies.
  - Stream-Server (neu): bei M3U jeder beliebige Server.
  - Logo-Hosts: automatisch, auch über HTTP und Weiterleitungen. Aus der Auswahl erfahren sie Liste, Suche, Filter und
    bei jedem Öffnen des Favoriten-Tabs genau die Favoriten; nicht abschaltbar.
  - GitHub/Sparkle: automatisch etwa einmal täglich, erstmals direkt nach dem ersten Start, ohne Rückfrage, ohne
    Schalter. Feed auf `raw.githubusercontent.com`, User-Agent mit App- und Sparkle-Version, kein Systemprofil,
    Update-Download von `github.com`.
- **Xtream über HTTP:** ergänzt, dass die Zugangsdaten jede Anfrage und jeden Stream begleiten; `http://`-M3U-Links
  ebenso.
- **Website:** „Both receive your IP address, as any web server does“ statt „Neither of those tells us who you are“;
  `/download` als Server-Funktion benannt statt „no server“.
- „Last updated 30 September 2026“.

**Übrige Seiten:**
- **Start** (`web/app/page.tsx`):
  - Spalten „The app adds“ und „It never does“ ohne „all local“ und „send your data anywhere“, mit Link auf `/privacy`.
  - Senderliste „Seventeen thousand channels, searchable“ mit Messwerten statt „as fast as you can type“.
  - Multiview-Bildunterschrift mit der MPEG-TS-Einschränkung.
  - Karte „macOS 14“ mit „The app's interface is in German.“
- **Funktionen** (`web/content/features.ts`), sieben statt acht:
  - Bild-in-Bild entfernt.
  - „Search across 17,000 channels“ mit Pausen und Importdauer.
  - „Favourites across playlists“ mit tvg-id-oder-Name-Regel und deren Folgen.
  - Tasten ohne P, Rückmeldung nur für Play/Pause, Lautstärke, Stumm.
  - „Updates through Sparkle“ mit Rückfrage und Opt-in.
  - „Three ways in“ ohne Doppelklick-Import.
- **FAQ** (`web/content/faq.ts`): drei Antworten neu.
  - Listengröße: Import und Aktualisieren etwa 4½ min, Löschen bis etwa 2 min, keine Reaktion während des Laufs.
  - „Where does my data go?“: ohne „Nowhere“.
  - „How do updates arrive?“: Sparkle-Ablauf, Menüeintrag „Nach Updates suchen …“.
- **Support** (`web/app/support/page.tsx`):
  - App-Name `MikaPlusPlayer` in den Erststart-Schritten und im Einleitungssatz.
  - Tastentabelle ohne P, Satz zur Rückmeldung darunter.
- **Changelog:** Satz zum Update-Weg (`web/app/changelog/page.tsx:21`). Die Ersatznotizen zu v1.1 haben die Zeile
  „Known issue in 1.1“ (`web/content/changelog-overrides.ts`).
- **Einrichtung** (`web/content/setup-steps.ts`): Reiter „Datei (file)“.
- **Fußzeile:** „An IPTV player with its source on GitHub.“ statt „open-source“.

**Reproduktion vor der Änderung:**
- Gesamtsuite am alten Stand: 65 Tests, 62 bestanden, 3 `todo`. BUG-02 rot mit „FB-03: „nothing goes to us““.
- Die vier neuen Tests gegen den alten Build: alle 4 rot. Erste Meldungen:
  - „nothing goes to us“
  - „Seite nennt die beschriebene Version“
  - „BF-12: automatische Prüfung genannt“
  - „/: Bild-in-Bild ist nicht im Release v1.1“
- Treffer der alten Aussagen je Seite stehen unter BUG-02 und BUG-07 im `qa-report.md`.
- Danach sind alle Tests erneut gelaufen, siehe unten.

### Verifikation (gefiltert)

`npx tsc --noEmit && npm run lint && npm run build` (ohne `GITHUB_TOKEN`/`NEXT_PUBLIC_SITE_URL`/
`VERCEL_PROJECT_PRODUCTION_URL`, Node 26.10.0):

```
tsc exit 0
> eslint
lint exit 0
▲ Next.js 16.3.3 (Turbopack)
✓ Compiled successfully in 584ms
Route (app)           Revalidate  Expire
┌ ○ /                         1h      1y
├ ○ /_not-found
├ ○ /apple-icon.png
├ ○ /changelog                1h      1y
├ ƒ /download
├ ○ /icon.png
├ ○ /opengraph-image
├ ○ /privacy
├ ○ /robots.txt
├ ○ /sitemap.xml
└ ○ /support
build exit 0
```

Die Suite lief gegen `next start -H 127.0.0.1 -p 3927` und wurde danach beendet: Port 3927 antwortet nicht mehr, es
läuft kein `next-server`- und kein `chrome-headless-shell`-Prozess mehr. Aufruf:
`BASE_URL=http://127.0.0.1:3927 node --test --test-timeout=600000 tests/`

```
suite exit 0
ℹ /: CSP-Verstöße 0   ℹ /changelog: CSP-Verstöße 0   ℹ /privacy: CSP-Verstöße 0   ℹ /support: CSP-Verstöße 0
ℹ Konsole/Log/Netz: 0 Fehler oder Warnungen
ℹ /privacy: 23 Anfragen, fremd: 0; Schriften: 4; Bilder: 1   (vorher ebenso 23)
ℹ im Fenster: 4 sequentielle Aufrufe → 0 Upstream-Anfragen; 60 parallele Aufrufe → 0 Upstream-Anfragen; Status: 302; neue Warnzeilen: 0
ℹ nach Ablauf des Fensters: 60 parallele Aufrufe → 1 Upstream-Anfrage(n)
ℹ 6 Aufrufe nach 200 → 0 Upstream-Anfragen
⚠ FB-15 (Befund) … # BUG-01 Website öffentlich nicht erreichbar
⚠ FB-16/FB-17/FB-18 (Befund) … # BUG-03 Pflichtangaben fehlen
ℹ tests 68
ℹ pass 66
ℹ fail 0
ℹ todo 2
```

Vorher (Teil 1): 65 Tests, 62 bestanden, 3 `todo`. Jetzt: 68 Tests, 66 bestanden, 2 `todo` (BUG-01, BUG-03).
Hinzugekommen sind 3 Tests: `H::BUG-02 (Soll)`, `H::BF-12/BF-16`, `H::BUG-07 / BF-25 / BF-81 / BF-103 / BF-107`. Der
erste Gesamtlauf nach der Änderung hatte 1 Fehlschlag: `M::AK-34 (BUG-08)` prüfte „kein fest verdrahtetes v1.1“ über
jedes Vorkommen von „Version 1.1“ im Text, und das enthält jetzt der Funktionstext. Die Prüfung zielt jetzt auf
Schaltflächen-Link und Beschriftung (siehe Annahme 4). Die Gegenprobe gegen den Build mit Release-Daten findet
„Version 1.1 · “ weiterhin (`true`).

Die Datenschutzseite wurde in 390 px Breite gesichtet (Headless-Screenshot im Scratchpad, danach gelöscht): Die langen
Pfade brechen um, es gibt keinen horizontalen Überlauf.

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-01** (hoch) — nicht behoben. Braucht Vercel (Deployment Protection, Domain) und die GitHub-Homepage des
  Repositorys; die Adresse ist eine Nutzerentscheidung (OF-04). Erneut beobachtet am 2026-09-30 (`L::FB-15`):
  - `mikaplus-player.vercel.app/privacy` → 404 `DEPLOYMENT_NOT_FOUND`
  - neuestes Production-Deployment → 302 `vercel.com/sso-api` mit `_vercel_sso_nonce`
  - `mikaplusplayer.com` → `ENOTFOUND`

  Die korrigierte Datenschutzerklärung ist damit weiter nicht öffentlich.
- **BUG-03** (hoch) — nicht behoben. Es fehlen Verantwortlicher, Anschrift, nicht öffentliche Kontakt-E-Mail,
  Rechtsgrundlagen, Speicherdauer der Vercel-Logs, Betroffenenrechte und Beschwerdestelle. Dazu kommt die rechtliche
  Bewertung durch den Nutzer. Nichts wurde erfunden, es gibt keine sichtbaren Platzhalter. Nur der irreführende Satz aus
  FB-17 ist ersetzt (siehe oben).
- **FB-13 Lizenz** — Die falsche Aussage „open-source“ ist entfernt. Ob und welche Lizenz vergeben wird, entscheidet der
  Nutzer (OF-09).
- **Das App-Verhalten selbst** bleibt in v1.1, wie die Seite es jetzt beschreibt: Klartext, Cache, Logos ohne Wahl,
  Tempo, Doppelklick. Das behebt erst das nächste Release, und mit ihm muss die Seite erneut angepasst werden (OF-10).
- **Nicht beschrieben**, weil keiner Aussage der Seite widersprechend (OF-11): der Absturz im Multiview-Raster
  (B08 BUG-01, kritisch, in v1.1 enthalten) und weitere Fehler von v1.1 ohne Bezug zu einer Werbeaussage.
- **Nicht ausgeführt:**
  - Der Sparkle-Dialog (Knöpfe, Kontrollkästchen) ist aus der B09-Spec (AK-06) übernommen, am echten Fenster wurde er
    nicht beobachtet. Die App wurde wegen der Nutzerdaten- und Tonvorgaben nicht gestartet.
  - Der genaue User-Agent-String von v1.1 ist nicht mitgeschnitten. Die Seite nennt deshalb nur die Bestandteile
    (App-Name, Build/Version, Netzwerk-Komponenten bzw. Sparkle-Version). Belegt ist das durch B02 AK-36, B04 BUG-06
    und B09 AK-23 an Builds mit gleichem Netzcode.

## 3 · Getroffene Annahmen

Alle ohne Rückfrage entschieden (Zielmodus), zur Bestätigung durch den Nutzer:

1. **Unveröffentlichte Verbesserungen erscheinen nirgends**, auch nicht als „coming soon“. Das betrifft Bild-in-Bild,
   Doppelklick-Import, Schlüsselbund, eigenen Speicherort, Cache-Reparaturen, schnellere Liste und signierten Feed. Der
   Auftrag sagt „lieber weglassen“. Deshalb hat „What it does“ sieben statt acht Funktionen; ersetzt wurde nichts.
2. **Messwerte stehen gerundet auf der Seite:**
   - Öffnen bis 0,9 s
   - erstes Zeichen, Suche leeren, Chip abwählen 0,3–0,6 s
   - Import und Aktualisieren etwa 4½ min
   - Löschen bis etwa 2 min

   Sie gelten „on our test Mac“ bzw. „in our measurements“. Gemessen hat die QA unter Last auf einem Mac mit macOS 27,
   mit Mock-Server und einem Build, dessen Listen- und Importcode gleich v1.1 ist. Andere Macs können abweichen.
3. **Sprachhinweis als Tatsachenangabe:** „The app's interface is in German.“ In Teil 1 war offen, ob das eine
   Nutzerentscheidung ist. Entschieden wird damit nichts, die Angabe beschreibt v1.1. Ob die App übersetzt wird, bleibt
   PRD-Frage. Die englischen Nachbauten bleiben unverändert.
4. **Test `M::AK-34 (BUG-08)` umgestellt:** Er prüft den fest verdrahteten v1.1-DMG-Link und die Beschriftung
   „Version 1.1 · …“ im von Markup befreiten Text, dazu beide Beschriftungen „Latest release on GitHub · macOS 14
   Sonoma or later“. Vorher prüfte er jedes „Version 1.1“ im HTML. Die Absicht (kein Ersatz-Release) bleibt, die
   Gegenprobe ist oben belegt.
5. **Warnung zu `default.store`:** Die Seite rät, die Datei zuerst in den Papierkorb zu legen, statt sie sofort zu
   löschen. Der Name ist der SwiftData-Standard, und eine fremde App ohne Sandbox kann dieselbe Datei nutzen (B01 BUG-04,
   QA-2 H-9). Ob das auf einem Nutzer-Mac vorkommt, ist nicht feststellbar.
6. **Feed-Adresse ohne Kontonamen:** Die Seite nennt `raw.githubusercontent.com`, nicht den alten Kontonamen im Pfad
   von v1.1. Das ist ein Sicherheitsbefund (B09 BUG-01, kritisch), keine Datenschutzfrage. Die Seite soll nicht auf ihn
   hinweisen.
7. **Satz aus FB-17 im Rahmen von BUG-02 ersetzt:** „Both receive your IP address, as any web server does“. Das ist
   eine Tatsache über jeden Webserver, keine Aussage über Vercels Speicherdauer (die bleibt BUG-03).
8. **Datum „Last updated 30 September 2026“:** Der Seiteninhalt hat sich geändert, deshalb weicht es vom Wortlaut in
   AK-24 ab (OF-08).
9. **Die Ersatznotizen zu v1.1** (`changelog-overrides.ts`) haben eine Zeile „Known issue in 1.1“ bekommen. Sie sind
   die englische Fassung der Release-Notizen, und der dort übernommene Satz „Clicking a tile moves both the sound and
   the large picture“ trifft für MPEG-TS nicht zu (B08 BUG-02). Der deutsche Text auf GitHub bleibt unverändert, denn
   GitHub liegt außerhalb des Auftrags.

## 4 · Systemweite Änderungen

- **Keine neue Abhängigkeit**, kein `npm install`, `package.json` und `package-lock.json` unverändert. Keine Änderung
  an `next.config.ts`, CSP, Routen, Datenschicht (`web/lib/`) oder Komponenten außer `site-footer.tsx`.
- **Sichtbare Texte** auf allen vier Seiten und in der Fußzeile, siehe *Umgesetzt*. Neu sind der Abschnitt „Removing
  everything“ und der Punkt „Stream servers.“ auf `/privacy`, der Link von der Startseite auf `/privacy` sowie die
  Zeile unter der Tastentabelle. Eine Funktion und eine Taste sind entfallen.
- **Kopplung an das Release:** Die Texte nennen jetzt ausdrücklich „version 1.1“, die Download-Schaltfläche folgt
  dagegen dem neuesten GitHub-Release. Ein neues Release macht die Seite ohne Textpflege falsch (OF-10). Die Stellen
  findet `grep -rn "1\.1" web/app web/content`.
- **Tests unter `web/tests/`:**
  - geändert: `site.http.test.mjs` (3 neue Tests, 5 Wortlaut-Tests), `browser.cdp.test.mjs` (FAQ-Wortlaut),
    `download-upstream.test.mjs` (AK-34)
  - unverändert: `releases.unit.test.mjs`, `live.readonly.test.mjs`
- **`features/B10-website/`:**
  - `spec.md`: nur *Offene Fragen*, OF-08 bis OF-11
  - `qa-report.md`: Vermerke unter BUG-01, BUG-02, BUG-03, BUG-07
  - dieser Bericht
- **Nicht angefasst:** `Sources/`, `Tests/`, `project.yml`, `scripts/`, `appcast.xml`, `features/index.md`,
  `features/befunde.md` und die Berichte anderer Features. Die Vermerke zu BF-12/16/81/103/107 stehen deshalb nur hier
  und im B10-`qa-report.md`, nicht in den Berichten von B04, B06, B07 und B09. Kein `xcodebuild`, kein Deployment,
  nichts auf Vercel oder GitHub. Die App wurde nicht gestartet. Nutzerdaten wurden nicht gelesen, unter `~/Library`
  nur Dateinamen gelistet.
- **Aufgeräumt:**
  - `next start` auf Port 3927 beendet (zweimal: vor und nach der Änderung), `chrome-headless-shell` beendet
  - Temp-Kopien des Mock-Tests (`b10-qa-*`) und Browser-Profile (`b10-cdp-*`) räumen die Tests selbst weg, geprüft:
    keine übrig
  - Logs und Screenshot im Scratchpad gelöscht
  - Fremd und nicht von diesem Lauf: 8 leere `b10-src-*` in `$TMPDIR`, angelegt 20:25, kein Test unter `web/tests`
    nutzt dieses Präfix; stehen gelassen

