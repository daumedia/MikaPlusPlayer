# B10 · Website — Build-Bericht (Fehlerauftrag, **Teil 1**)

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
