# B10 · Website — Systemdesign

Status: `rekonstruiert` · Stand: 2026-09-15 · Stack-Profil: `nextjs-supabase` (nur der Next.js-Teil, **ohne** Supabase) · Rekonstruktion aus dem Code (sdd-erfassen)

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau von `web/` @ `c01f1cf`, wie er ist — nicht, wie er sein
sollte. Befunde stehen in `spec.md` unter *Fehlbestand*.

## Überblick

Eine reine Informationsseite ohne Datenbank, ohne Anmeldung und ohne Formulare. Alle Seiten sind Server Components;
nur der Multiview-Nachbau läuft im Browser. Texte liegen getrennt vom Layout in `content/`, feste Werte (Repository,
Mindest-macOS, Navigation, Site-URL) in `lib/site.ts`. Einzige Laufzeitdatenquelle ist die GitHub-REST-API: Sie
liefert das neueste Release für Download-Schaltfläche und `/download` sowie die Release-Liste für den Changelog.
Beide Abfragen laufen nur auf dem Server, werden eine Stunde gecacht und fallen bei jedem Fehler auf ein fest
eingebautes Ersatz-Release `v1.1` zurück, damit Build und Download nie an GitHub scheitern.

## Abweichungen vom Stack-Profil

| Profil sagt | Ist-Stand | Anmerkung |
|---|---|---|
| Code unter `src/app`, `src/components`, `src/lib` | ohne `src/`: `web/app`, `web/components`, `web/lib`, zusätzlich `web/content` | Alias `@/*` zeigt auf `web/` (`tsconfig.json:21-23`) |
| Komponenten in `components/<bereich>/` | flach in `components/` | elf Dateien |
| Supabase-Clients, Migrationen, RLS | entfällt | keine Datenhaltung |
| Vitest und Playwright, Tests neben der Datei | **keine Tests** | nur `npm run lint` und `npm run build` |
| Verifikation `npx tsc --noEmit`, `npm run lint`, `npm run build` | `next build` prüft Typen selbst | `lint` = `eslint` mit `eslint-config-next` |
| Deployment per `git push`, Hoster am Branch | Vercel am Repository, *Root Directory* `web`, *Ignored Build Step* für Swift-Commits | laut `web/README.md:61-81`, nicht im Repository konfiguriert (kein `vercel.json`) |

## Seiten und Routen

| Route | Zweck | Zugang | Rendering |
|---|---|---|---|
| `/` | Vorstellung, Download, Einrichtung in drei Schritten, Funktionen, Multiview, Voraussetzungen | öffentlich | statisch, ISR 3600 s (wegen GitHub-Abfrage) |
| `/changelog` | alle Releases (max. 20) mit Notizen und DMG-Link | öffentlich | statisch, ISR 3600 s |
| `/support` | Erststart, Playlist hinzufügen, Tastatur, FAQ | öffentlich | statisch |
| `/privacy` | Datenschutzhinweise zu App und Website | öffentlich | statisch |
| `/download` | stabiler Kurzlink, 302 auf das DMG des neuesten Releases | öffentlich, in `robots.txt` gesperrt | dynamisch (Route Handler, nur `GET`/`HEAD`) |
| `/robots.txt` | Crawler-Regeln | öffentlich | statisch, `app/robots.ts` |
| `/sitemap.xml` | vier Seiten mit Build-Zeitpunkt | öffentlich | statisch, `app/sitemap.ts` |
| `/opengraph-image` | Vorschaubild 1200 × 630 | öffentlich | statisch beim Build erzeugt, `app/opengraph-image.tsx` |
| `/icon.png`, `/apple-icon.png` | Favicon, Apple-Touch-Icon | öffentlich | Dateikonvention in `app/` |
| `/icon-512.png` | Symbol für Kopfzeile und OG-Bild | öffentlich | `public/` |
| `/_next/image` | Bildoptimierung für `icon-512.png` | öffentlich, nur lokale Quellen | Next.js/Vercel |
| alles andere | 404-Seite | öffentlich | `_not-found`, statisch |

## Komponentenstruktur

```
app/layout.tsx                      Schriften (next/font/google, selbst gehostet), Metadaten, Viewport-Farben,
│                                   <html lang="en">, Skip-Link
├── SiteHeader                      sticky; Symbol + Wordmark → "/"; NAV aus lib/site.ts + GitHub-Link
│   └── Wordmark                    "Mika" + akzentfarbenes "+" + "Player"
├── <main id="main">
│   ├── app/page.tsx  (/)           async, ruft getLatestRelease()
│   │   ├── Hero
│   │   │   ├── DownloadButton      href = DMG-URL (sonst Release-Seite, praktisch unerreichbar), Version · MB · MIN_MACOS
│   │   │   ├── GatekeeperNote      Rechtsklick-→-Öffnen-Hinweis
│   │   │   └── MultiviewDemo       "use client"; useState activeIndex; nur Fokus-Layout
│   │   │       └── WindowFrame     macOS-Fensterrahmen mit Titel
│   │   ├── "You bring / The app adds / It never does"   feste Texte
│   │   ├── Section "Getting started"                     SETUP_STEPS
│   │   ├── ChannelListDemo         CSS-Nachbau (erfundene Sender), WindowFrame
│   │   ├── Section "What it does"                        FEATURE_GROUPS × FEATURES
│   │   ├── Multiview-Abschnitt
│   │   │   └── MultiviewDemo withLayoutToggle           zusätzlich useState layout (focus/grid) in der Toolbar
│   │   ├── ScreenshotStrip         rendert nichts, solange SCREENSHOTS leer ist; sonst next/image
│   │   └── Section "What it needs" drei Karten, DownloadButton, Links GitHub und /support
│   ├── app/changelog/page.tsx      async, ruft getReleases(); je Release: Titel, <time>, ReleaseNotes, Links
│   │   └── ReleaseNotes            react-markdown + remark-gfm; h1/h2 → h3, a → neuer Tab, img/hr → nichts
│   ├── app/support/page.tsx        Erststart (feste Liste), SETUP_STEPS, DEMO_PLAYLIST, KEYS (fest), FAQ als <details>
│   └── app/privacy/page.tsx        feste Texte, LAST_UPDATED als Konstante
└── SiteFooter                      Wordmark, Kurztext, NAV, Issues, Source

app/download/route.ts               GET → getLatestRelease() → NextResponse.redirect(dmg.url, 302)
app/robots.ts · app/sitemap.ts      aus SITE_URL
app/opengraph-image.tsx             ImageResponse; liest public/icon-512.png als data-URL
Section                             Eyebrow + h2 + optionaler Lead (Muster PlayerHeader)
lib/releases.ts                     gh() · pickDmg() · toRelease() · getLatestRelease() · getReleases() · FALLBACK_RELEASE
lib/format.ts                       formatBytes (÷ 1024², "MB") · formatDate (en-US, UTC)
app/globals.css                     Farb-Tokens hell/dunkel aus PlayerTheme, Utilities headline/eyebrow/badge/card,
                                    prose-Farben, prefers-reduced-motion
```

## Datenquellen

Keine Tabellen. An ihrer Stelle:

### Inhalte im Repository

| Datei | Inhalt | Verwendet in | Pflege |
|---|---|---|---|
| `content/features.ts` | 8 Funktionen mit `kicker` ∈ Library/Playback/System, `title`, `body` | `/` | von Hand; Aussagen teils falsch (FB-01, FB-02, FB-06 bis FB-09) |
| `content/setup-steps.ts` | 3 Schritte `channel` „01"–„03", `title`, `body` | `/`, `/support` | von Hand |
| `content/faq.ts` | 9 Fragen/Antworten | `/support` | von Hand; FB-03, FB-11 |
| `content/changelog-overrides.ts` | `NOTE_OVERRIDES`: Tag → englischer Markdown-Text; nur `v1.1` | `lib/releases.ts` (Changelog, Ersatz-Release) | von Hand, laut Kommentar künftig überflüssig, wenn Release-Texte englisch auf GitHub stehen |
| `content/screenshots.ts` | `SCREENSHOTS`: leer | `ScreenshotStrip` | Dateien nach `public/screenshots/` legen und eintragen |
| `lib/site.ts` | `SITE_NAME`, `SITE_TAGLINE`, `REPO_OWNER` `daumedia`, `REPO_NAME`, `GITHUB_URL`, `RELEASES_URL`, `ISSUES_URL`, `MIN_MACOS` „macOS 14 Sonoma", `DEMO_PLAYLIST`, `SITE_URL`, `NAV` | überall | von Hand |
| `lib/releases.ts` · `FALLBACK_RELEASE` | fest: `v1.1`, Titel, Datum, DMG-Name, -URL, 36 455 860 Bytes | bei jedem GitHub-Fehler | von Hand, nicht durch `scripts/release.sh` (FB-19) |
| Texte direkt in Seiten | Hero, Voraussetzungen, Tastatur (`KEYS`), Erststart, gesamte Datenschutzseite | `/`, `/support`, `/privacy` | von Hand; widerspricht `web/README.md:15` („edit `content/`, not the pages") |

### GitHub-REST-API

| Abfrage | Aufrufer | Verwendete Felder | Abbildung |
|---|---|---|---|
| `GET /repos/daumedia/MikaPlusPlayer/releases/latest` | `getLatestRelease()` → `/`, `/download` | `tag_name`, `name`, `body`, `published_at`, `html_url`, `assets[].name/size/content_type/browser_download_url/download_count` | `Release`; ohne DMG → DMG aus `FALLBACK_RELEASE`, übrige Felder vom neuen Release |
| `GET /repos/daumedia/MikaPlusPlayer/releases?per_page=20` | `getReleases()` → `/changelog` | wie oben, zusätzlich `draft` | Entwürfe gefiltert, Vorabversionen nicht; leere Liste oder Fehler → `[FALLBACK_RELEASE]` |

Gemeinsam für beide (`gh()` in `lib/releases.ts:62-91`):

| Aspekt | Ist-Stand |
|---|---|
| Header | `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent: mikaplusplayer-website`, optional `Authorization: Bearer $GITHUB_TOKEN` |
| Cache | `fetch` mit `next: { revalidate: 3600, tags: ["github-releases"] }` — Next.js legt **nur Status 200** im Daten-Cache ab; der Tag wird nirgends ausgelöst |
| Fehler | nicht-2xx → `console.warn` mit Pfad, Status, `x-ratelimit-remaining`, Rückgabe `null`; Netzwerkfehler → `console.warn` mit Fehlerobjekt, Rückgabe `null` |
| Nicht genutzt | `downloadCount` und `isFallback` werden befüllt, aber nirgends angezeigt oder ausgewertet |

### Umgebungsvariablen

| Variable | Gelesen in | Pflicht | Wirkung | Im Browser-Bundle |
|---|---|---|---|---|
| `GITHUB_TOKEN` | `lib/releases.ts:68-70` | nein | hebt das GitHub-Limit von 60 auf 5000 Anfragen je Stunde | nein (geprüft, AK-38) |
| `NEXT_PUBLIC_SITE_URL` | `lib/site.ts:14` | nein, laut README nur Production | Basis für Canonical, OG, Sitemap, robots | als Wert in HTML/Metadaten, kein Geheimnis |
| `VERCEL_PROJECT_PRODUCTION_URL` | `lib/site.ts:15-16` | nein, von Vercel gesetzt | Ersatz für die Site-URL | wie oben |

## Zugriffsregeln

| Wer | Darf lesen | Darf schreiben | Erzwungen durch |
|---|---|---|---|
| jeder Besucher | alle Seiten, Metadaten-Routen, `/download` | nichts — es gibt keinen Schreibpfad | keine Regel nötig; Route Handler `/download` exportiert nur `GET` (`POST` → 405) |
| Server (Build und Laufzeit) | GitHub-Releases, optional mit Token | nichts | — |
| Vercel-Projekt | — | Deployment Protection ist live aktiv (FB-15) | Plattformeinstellung, nicht im Repository |

## Missbrauchsschutz

| Endpunkt | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| `/download` | **keins** | jeder Aufruf startet eine Server-Funktion; Erfolgsfall aus dem Daten-Cache, Fehlerfall fragt GitHub jedes Mal neu (FB-21) | — |
| `/`, `/changelog` | kein eigenes; ISR: höchstens eine Neuberechnung je Stunde | Auslieferung aus dem Cache (`s-maxage=3600, stale-while-revalidate`) | `revalidate` in `lib/releases.ts:5` |
| `/privacy`, `/support`, Metadaten | kein eigenes; statisch | Auslieferung aus dem Cache | Build |
| `/_next/image` | nur lokale Quellen (keine `images.remotePatterns`) | fremde URL → 400 | Next.js-Standard |
| GitHub-API (ausgehend) | 60/h ohne Token je IP, 5000/h mit Token | Warnung im Log, Ersatz-Release | GitHub |
| gesamte Seite | Plattformschutz von Vercel (nicht im Repository sichtbar) | unbekannt | Vercel |

### Sicherheits-Header

Gesetzt in `next.config.ts:5-19` für `/:path*`, gelten auch in `next dev`:

| Header | Wert |
|---|---|
| `X-Content-Type-Options` | `nosniff` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `X-Frame-Options` | `DENY` |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains; preload` |
| `X-Powered-By` | abgeschaltet (`poweredByHeader: false`) |
| `Content-Security-Policy`, `Permissions-Policy` | **nicht gesetzt** (FB-20) |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| GitHub REST API | Release-Daten beim Build und bei der Neuberechnung | Anfrage vom Server: fester User-Agent, optional Token. **Keine Besucherdaten** | — (nichts Personenbezogenes enthalten) |
| GitHub (`github.com`, Release-Assets) | DMG-Download | Browser des Besuchers direkt: IP, User-Agent, Referer (nur Ursprung). GitHub zählt Downloads | nichts; die Website ist nicht beteiligt |
| Google Fonts | Schriftdateien beim **Build** (`next/font/google`) | Anfrage vom Build-Rechner, keine Besucherdaten | — ; Besucher laden Schriften vom eigenen Ursprung |
| Vercel | Hosting, CDN, Bildoptimierung, Server-Funktion `/download`, Server-Logs | alle Anfragen der Besucher (IP, User-Agent, Pfad, Zeit); Speicherdauer im Repository nicht festgelegt | nichts; kein AV-Vertrag dokumentiert (FB-17) |
| iptv-org.github.io | Beispiel-Playlist auf `/support` | nur bei Klick durch den Besucher | — |

## Caching und Revalidierung

- **Build:** `/` und `/changelog` werden mit den GitHub-Daten vorgerendert; der Daten-Cache (`.next/cache/fetch-cache`)
  enthält beide Antworten, wenn sie 200 waren.
- **Laufzeit, Seiten:** ausgeliefert aus dem ISR-Cache; nach 3600 s löst die nächste Anfrage im Hintergrund eine
  Neuberechnung aus. Liefert GitHub dabei einen Fehler, wird die Seite **ohne Fehler** mit dem Ersatz-Release neu
  erzeugt und für die nächste Stunde ausgeliefert.
- **Laufzeit, `/download`:** bei jedem Aufruf `getLatestRelease()`; Treffer im Daten-Cache → keine GitHub-Anfrage
  (gemessen). Kein Treffer oder abgelaufener Eintrag → Anfrage; nur eine 200-Antwort wird wieder gecacht.
- **Kein On-Demand:** der Tag `github-releases` ist vorbereitet, aber es gibt keinen Webhook und kein
  `revalidateTag` (OF-03). Ein neues Release erscheint spätestens nach einer Stunde plus Neuberechnung.

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Release-Daten zur Laufzeit von GitHub statt Versionsnummer im Code | Version bei jedem Release in die Seite schreiben | Kommentar `web/README.md:28-30`: „Nothing about the current version is hard-coded … updates the site within the hour" |
| 2 | Fester Ersatz-Release statt Build-Abbruch bei GitHub-Fehler | Build scheitern lassen | Kommentar `lib/releases.ts:89`: „A build must never fail because GitHub is down" |
| 3 | Neues Release ohne DMG behält alten Link | Schaltfläche ausblenden oder auf Release-Seite zeigen | Kommentar `lib/releases.ts:125`: Upload läuft noch; Beschriftung dabei nicht angepasst (OF-01) |
| 4 | DMG über Content-Type, ersatzweise Endung | nur Dateiname | Grund nicht erkennbar; robust gegen Umbenennung |
| 5 | `/download` als dynamischer Route Handler mit 302 | statische Weiterleitung in `next.config.ts` | Kommentar `app/download/route.ts:4` („Stable short link"), `web/README.md:42`; ein fester Redirect müsste bei jedem Release geändert werden. Warum 302 und nicht 307/308, ist nicht dokumentiert |
| 6 | `/download` in `robots.txt` gesperrt, nicht in der Sitemap | indexieren lassen | Grund nicht erkennbar; vermutlich keine DMG-Links in Suchergebnissen |
| 7 | Englische Ersatztexte für deutsche GitHub-Release-Notizen | Release-Texte auf GitHub übersetzen | Kommentar `content/changelog-overrides.ts:1-5`; Übergangslösung |
| 8 | Markdown ohne `rehype-raw`, Bilder und Trennlinien unterdrückt, Links in neuem Tab | HTML durchlassen oder Text ohne Markdown | Grund für die Unterdrückung nicht erkennbar; Effekt: fremdes HTML wird maskiert (AK-20) |
| 9 | Multiview und Senderliste als CSS-Nachbau statt Screenshots | echte Bildschirmfotos | Kommentar `web/README.md:57-58`: „cannot go stale and hold no real channel names" |
| 10 | Schriften über `next/font/google` (beim Build geladen, selbst ausgeliefert) | Google-Fonts-CDN oder Systemschriften | Datenschutzseite: „no fonts loaded from third parties"; Nebenwirkung: Build braucht Google (EC-08) |
| 11 | Sicherheits-Header in `next.config.ts` statt `vercel.json` | `vercel.json` | Kommentar `web/README.md:80-81`: gelten dann auch in `next dev` |
| 12 | Farben 1:1 aus `PlayerTheme.swift`, dunklere Akzentvarianten für Text | App-Rot unverändert für Text | Kommentar `app/globals.css:17-18`, `web/README.md:50-52`: Kontrast 3,5 : 1 auf hellem Grund |
| 13 | HSTS mit `includeSubDomains; preload` | nur `max-age` | Grund nicht erkennbar; bindet alle Subdomains der künftigen Domain an HTTPS |
| 14 | Keine Analytics, keine Cookies, kein Kontaktformular | Vercel Analytics, Formular | Datenschutzseite und Startseite („no analytics"); Kontakt nur über GitHub Issues |
| 15 | Unauthentifizierte GitHub-Abfrage als Normalfall, Token optional | Token Pflicht | `web/README.md:32-40`; bei geteilten Vercel-IPs anfällig (EC-01) |

## Abdeckung der Akzeptanzkriterien

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `next build`; ISR-Dauer der Seiten ergibt sich aus der `fetch`-Option `revalidate: 3600` in `lib/releases.ts:75`; Route Handler `app/download/route.ts` | Routenübersicht aus dem Build-Log |
| AK-02 | `next.config.ts:4-19` | |
| AK-03 | Next.js aus ISR-Einstellung (`revalidate: 3600`) bzw. statischer Seite | |
| AK-04 | Next.js `_not-found`, `trailingSlash`-Standard | |
| AK-05 | `components/site-header.tsx`, `components/wordmark.tsx`, `lib/site.ts:20-24` | Breakpoints `sm` (640 px), `min-[380px]` |
| AK-06 | `components/site-footer.tsx` | |
| AK-07 | `app/layout.tsx:76,80-85` | |
| AK-08 | `app/globals.css:10-44`, `app/layout.tsx:64-69` | |
| AK-09 | `app/page.tsx:20-39`, `components/download-button.tsx`, `components/gatekeeper-note.tsx`, `lib/format.ts:1-3` | |
| AK-10 | `components/multiview-demo.tsx`, `components/window-frame.tsx` | einzige Client Component |
| AK-11 | `app/page.tsx:51-212`, `components/section.tsx`, `components/channel-list-demo.tsx`, `content/features.ts`, `content/setup-steps.ts` | |
| AK-12 | `components/screenshot-strip.tsx:5`, `content/screenshots.ts:10` | |
| AK-13 | `app/layout.tsx:33-62`, `app/opengraph-image.tsx` | |
| AK-14 | `app/download/route.ts:5-9` | Handler liest keinen Request |
| AK-15 | `lib/releases.ts:73-76` (Daten-Cache) | |
| AK-16 | `lib/releases.ts:125-126`, `components/download-button.tsx:26-29` | OF-01 |
| AK-17 | `lib/releases.ts:93-105` | |
| AK-18 | `app/changelog/page.tsx`, `lib/releases.ts:129-136`, `lib/format.ts:5-13` | Vorabversionen: OF-02 |
| AK-19 | `lib/releases.ts:114`, `content/changelog-overrides.ts`, `components/release-notes.tsx:6` | |
| AK-20 | `components/release-notes.tsx:10-24` mit Standardverhalten von `react-markdown` 10.1.0 (kein `rehype-raw`, `defaultUrlTransform`) | Nachweis per Nachbau |
| AK-21 | Server Component `components/release-notes.tsx` (ohne `"use client"`) | |
| AK-22 | `app/support/page.tsx`, `content/setup-steps.ts`, `content/faq.ts`, `lib/site.ts:11` | |
| AK-23 | `app/support/page.tsx:99-119` (`<details>`/`<summary>`, `group-open:rotate-45`) | |
| AK-24 | `app/privacy/page.tsx` | falsche Aussagen: FB-03, FB-04, FB-05, FB-17 |
| AK-25 | `app/privacy/page.tsx:64-75`; Gegenstück in der App `XtreamCodes.swift:69-74` | |
| AK-26 | `app/privacy/page.tsx:77-84` | |
| AK-27 | `app/robots.ts` | |
| AK-28 | `lib/site.ts:13-18` | |
| AK-29 | `app/sitemap.ts` | `lastModified = new Date()` beim Build |
| AK-30 | `app/opengraph-image.tsx`, `app/icon.png`, `app/apple-icon.png`, `public/icon-512.png` | |
| AK-31 | `lib/releases.ts:62-70` | |
| AK-32 | `lib/releases.ts:78-85,122,133`, `FALLBACK_RELEASE` `:46-60` | |
| AK-33 | `lib/releases.ts:87-90` | |
| AK-34 ⚠ | `app/download/route.ts`, `lib/releases.ts:73-90`; Next.js cacht nur Status 200 (`next/dist/server/lib/patch-fetch.js`) | als Fehler eingestuft → FB-21 |
| AK-35 | kein Code setzt Cookies; keine `middleware.ts`/`proxy.ts`, keine Auth | lokal geprüft; live siehe FB-15 |
| AK-36 | `app/layout.tsx:2,9-28` (`next/font/google` selbst gehostet), keine Script-Einbindungen | |
| AK-37 | `components/download-button.tsx:10-13` (einfacher Link), `next.config.ts:11` | |
| AK-38 | `lib/releases.ts` nur aus Server Components und dem Route Handler importiert; `.gitignore:34` | |
| AK-39 | `lib/releases.ts:79-83,88` | |
| AK-40 | Next.js-Bildoptimierung ohne `images.remotePatterns` in `next.config.ts` | |
| AK-41 | Aufbau aller Seiten: keine `<form>`, keine Server Actions, einziger Route Handler ohne Request-Auswertung | |

### Ohne AK-Zuordnung

Hinweise auf toten oder unfertigen Code — keine übersehenen Kriterien:

| Stelle | Befund |
|---|---|
| `lib/releases.ts:11,103` · `downloadCount` | befüllt, nirgends angezeigt |
| `lib/releases.ts:22-23,59,116` · `isFallback` | befüllt, nirgends ausgewertet — die Seite kann einen GitHub-Ausfall nicht anzeigen |
| `components/download-button.tsx:6` · Rückfall auf `htmlUrl` | unerreichbar, weil `getLatestRelease` immer ein DMG liefert (EC-15) |
| `lib/releases.ts:75` · Tag `github-releases` | nirgends ausgelöst (OF-03) |
| `app/globals.css:67` · `--radius-hud` | im Website-Code nicht verwendet |
| `components/screenshot-strip.tsx` | vollständig, aber ohne Daten nie sichtbar |
