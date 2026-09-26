# Mika+Player — Product Requirements Document

Stand: 2026-09-15 · Stufe Datenschutz: B · Stack-Profil: `swiftui-ios` + `swiftui-macos` · Artefaktpfad: `docs/`

> **Rekonstruiert, nicht geplant.** Dieses PRD wurde mit `sdd-erfassen` aus dem laufenden Code
> gelesen (Stand `main` @ `c01f1cf`). Was hier steht, beschreibt, was die App **tut** — nicht, was
> sie tun sollte. Abweichungen vom Wünschenswerten stehen unter *Datenschutz* und *Offene Punkte*.
> Nicht aus dem Code ablesbar und deshalb erfragt (2026-09-15): Zielgruppe, Vertriebsmodell,
> Stellenwert von iOS.

## Vision

Mika+Player ist ein nativer IPTV-Player für macOS und iOS aus der Mika+-Familie von daumedia.
Er spielt, was der Nutzer mitbringt — einen Xtream-Codes-Zugang, einen M3U-Link oder eine
Playlist-Datei — und bleibt auch bei Anbieterlisten mit mehr als 17.000 Sendern bedienbar.
Das Projekt ist in erster Linie **Referenz und Portfolio**: Es zeigt, wie die Mika+-Designsprache,
eine austauschbare Wiedergabe-Engine und Direktvertrieb mit Auto-Update in einer App zusammenkommen.

## Zielgruppe

| Gruppe | Situation | Was sie hier will |
|---|---|---|
| Portfolio-Betrachter (Interessenten, Kunden von daumedia) | stößt über Website oder GitHub auf das Projekt | beurteilen, wie sauber Code, Design und Auslieferung sind |
| Mac-Nutzer mit eigenem IPTV-Abo *(sekundär, abgeleitet aus der Website)* | will Sender ohne Browser oder Set-Top-Box am Mac schauen | Anbieterliste importieren, Sender schnell finden, abspielen — auch mehrere gleichzeitig |

## Im Scope

Gelesen aus dem Code. Plattform in Klammern; „beide" = iOS 17+ und macOS 14+.

- Anmeldung mit Xtream-Codes-Zugang (Host, Benutzername, Passwort, Format HLS oder MPEG-TS); Senderliste über `player_api.php` *(beide)*
- Import von M3U/M3U8-Playlists per URL oder lokaler Datei; quote-sicherer `#EXTINF`-Parser *(beide)*
- Playlist-Übersicht mit Aktualisieren (nur Remote-Playlists) und Löschen *(beide)*
- Senderliste mit Suche und Gruppen-Filter, datenbankgestützt für sehr große Listen *(beide)*
- Favoriten über alle Playlists hinweg, bleiben beim Aktualisieren erhalten *(beide)*
- Wiedergabe mit automatischer Engine-Wahl (AVKit für HLS, VLCKit für rohes MPEG-TS), Play/Pause, Stumm, Lautstärke, Vollbild, Tastatursteuerung *(beide)*
- Bild-in-Bild über das System-PiP, nur mit der AVKit-Engine *(beide; Auto-Start beim App-Wechsel nur iOS)*
- Multiview: bis zu vier Streams gleichzeitig in eigenem Fenster, Fokus- oder Raster-Layout, Ton nur beim fokussierten Stream *(nur macOS)*
- Auto-Update über Sparkle mit EdDSA-Signaturprüfung, manuell über „Nach Updates suchen …" *(nur macOS)*
- Marketing-Website (Next.js, Vercel) mit Features, FAQ, Changelog, Download-Weiterleitung, Datenschutz- und Support-Seite

## Nicht im Scope

Aus Code und Website abgeleitet — bei der Freigabe des PRD bestätigt oder korrigiert.

- Mitgelieferte Sender, Abo-Verkauf oder -Vermittlung (Website: „ships no channels and resolves no subscriptions")
- Programmführer (EPG) — `tvg-id` wird gelesen, dient aber nur als Schlüssel für Favoriten
- Video on Demand, Serien, Catch-up — `XtreamClient` fragt ausschließlich `get_live_streams` ab
- Aufnahme, Timeshift, Zurückspulen
- Konten, Synchronisation, Cloud-Backup (alles bleibt lokal)
- Telemetrie, Analytics, Fehler-Tracking — weder in der App noch auf der Website
- Mac App Store (Sandbox ist wegen Sparkle deaktiviert, dadurch nur Direktvertrieb)

## Erfolgskriterien

Nicht festgelegt. Im Code nicht ablesbar und bei der Erfassung nicht erfragt — siehe *Offene Punkte*.

## Rahmenbedingungen

| Thema | Entscheidung (Ist-Stand) |
|---|---|
| Stack-Profil | `swiftui-ios` für die Projektstruktur (XcodeGen, `project.yml` ist die Wahrheit), `swiftui-macos` für den Vertrieb (DMG + Sparkle). **Abweichung vom macOS-Profil:** kein `Package.swift`, sondern zwei XcodeGen-Targets (`MikaPlusPlayer` iOS, `MikaPlusPlayer-macOS`) über ein gemeinsames `targetTemplate`, weil Sparkle macOS-only ist. Website: Next.js 16 + Tailwind 4, **ohne** Supabase |
| Plattformen | iOS 17+ und macOS 14+, **gleichwertig** (erfragt 2026-09-15). Ausgeliefert wird bisher nur macOS; iOS-Vertrieb ist für später vorgesehen |
| Backend | keins. Persistenz ausschließlich lokal über SwiftData (`Playlist`, `Channel`) |
| Umgebungen | keine getrennten Umgebungen — ohne Backend nicht nötig. Debug/Release nur als Build-Konfiguration |
| Datenregion | App: nur lokal auf dem Gerät. Website: Vercel (Region nicht festgelegt), Downloads über GitHub |
| Sprachen | App-Oberfläche **nur Deutsch**, als Literale im Code (keine String-Kataloge). Website **nur Englisch** |
| Monetarisierung | kostenlos. Öffentliches Repository `daumedia/MikaPlusPlayer`, als Open Source gedacht (erfragt 2026-09-15) |
| Vertrieb macOS | DMG über GitHub Releases, **ad-hoc signiert, nicht notarisiert** (`CODE_SIGN_IDENTITY = "-"`). Letztes Release `v1.1` vom 2026-06-23 |
| Vertrieb iOS | keiner. Signatur automatisch mit Team `CWJM4J4HFN` |
| Sicherheitsrelevante Build-Einstellungen | macOS: App-Sandbox **aus**, `disable-library-validation` **an**. Beide Plattformen: `NSAllowsArbitraryLoads = true` (HTTP überall erlaubt) |
| Abhängigkeiten | `VLCKitSPM` 3.6.0 (exakt gepinnt, beide Targets), `Sparkle` ≥ 2.6.0 (nur macOS) |
| Tests | XCTest, nur macOS-Target: `M3UParserTests` (4), `XtreamCodesTests` (4), `PlaybackEngineTests` (6). Keine UI-Tests, keine iOS-Tests |

### Externe Dienste

| Dienst | Wofür | Welche Daten gehen hin |
|---|---|---|
| IPTV-Anbieter (vom Nutzer eingegebener Host) | Authentifizierung, Kategorien, Senderliste, Streams | Xtream-Benutzername und -Passwort **im Klartext über HTTP** (als Query-Parameter und im Stream-Pfad), IP-Adresse, abgerufene Sender |
| Beliebige Hosts aus einer M3U-URL | Playlist-Abruf und Streams | IP-Adresse; ggf. in der URL enthaltene Zugangsdaten |
| Logo-Hosts (aus `tvg-logo` bzw. `stream_icon`) | Senderlogos in der Liste | IP-Adresse, beim Scrollen durch die Senderliste |
| GitHub (`raw.githubusercontent.com`, `github.com`) | Sparkle-Feed `appcast.xml`, DMG-Download | IP-Adresse, App-Version (Sparkle-Standard) |
| Vercel | Hosting der Website | Server-Logs der Besucher |
| GitHub REST API (serverseitig, Website) | aktuelles Release für Download-Link und Changelog | keine Nutzerdaten; optional `GITHUB_TOKEN` als Server-Umgebungsvariable |

## Datenschutz — Kurzfassung

**Stufe B**, weil die App zwar weder eigene Konten noch ein Backend hat, aber **Zugangsdaten zu
einem kostenpflichtigen Drittanbieter-Konto** speichert und überträgt. Xtream-Benutzernamen sind
häufig E-Mail-Adressen oder Kundennummern und damit personenbezogen. Stufe A würde den
Prüfkatalog auf *Missbrauch* und *Geheimnisse* verkürzen. Ungeprüft blieben dann genau die
Abschnitte *Personenbezogene Daten* (Speicherort, Logs) und *Weitergabe*, in denen das
Hauptrisiko dieser App liegt. Nicht C: Senderfavoriten können zwar Rückschlüsse auf Herkunft,
Religion oder politische Haltung zulassen, verlassen das Gerät aber nie.

`docs/datenschutz.md` existiert noch nicht. Pro Feature konkretisiert die jeweilige `spec.md`.

Was heute app-weit gilt (gelesen, nicht gewünscht):

- Alle Nutzerdaten — Playlists, Senderlisten, Favoriten, Zugangsdaten — liegen lokal in der
  SwiftData-Datenbank. Kein Sync, keine Kopie außerhalb des Geräts.
- Keine Telemetrie, keine Analytics, kein Fehler-Tracking, kein Logging von Nutzerdaten
  (kein `print`, `Logger` oder `os_log` im Code).
- Zugangsdaten gehen ausschließlich an den Host, den der Nutzer eingegeben hat.
- Löschen einer Playlist entfernt kaskadierend alle ihre Sender, einschließlich der Favoriten
  und der darin gespeicherten Zugangsdaten. Löschen der App entfernt alles.

Was heute app-weit gilt und **fragwürdig** ist — Details im Fehlbestand von `docs/datenmodell.md`:

- Xtream-Passwörter liegen **im Klartext** in der Datenbank, nicht in der Keychain: einmal in
  `Playlist.sourceURL` und zusätzlich in **jeder** `Channel.streamURL` (`/live/<user>/<pass>/<id>.ts`)
  — bei 17.000 Sendern also 17.000-mal.
- Ein eingegebenes `https://` wird beim Xtream-Login **zwangsweise auf `http://` umgeschrieben**.
  Zugangsdaten gehen dadurch immer unverschlüsselt über das Netz. Die Datenschutzseite der
  Website legt das offen; README und CLAUDE.md erwähnen es nicht.

## Feature-Roadmap

Ein **Inventar, keine Planung** — alles existiert und steht auf `bestand`. Pflege und Status in
`features/index.md`.

| ID | Feature | Prio | Kurzbeschreibung | Abhängig von |
|---|---|---|---|---|
| B01 | Xtream-Codes-Login | P0 | Anmeldung mit Host/Benutzer/Passwort, Senderliste über `player_api.php`, Formatwahl HLS/MPEG-TS | — |
| B02 | M3U-Import | P0 | Playlist per URL oder lokaler Datei importieren, quote-sicher parsen | — |
| B03 | Playlist-Verwaltung | P0 | Übersicht aller Playlists, Aktualisieren (Remote), Löschen (kaskadierend) | B01, B02 |
| B04 | Senderliste | P0 | Sender einer Playlist durchsuchen und nach Gruppe filtern, Logos anzeigen | B03 |
| B05 | Favoriten | P1 | Sender markieren, eigener Tab über alle Playlists, Erhalt beim Aktualisieren | B03, B04 |
| B06 | Wiedergabe | P0 | Engine-Wahl nach URL, Steuerung, Vollbild, Tastatur, Fehleranzeige | B04 |
| B07 | Bild-in-Bild | P1 | System-PiP für AVKit-Streams, Auto-Start beim App-Wechsel auf iOS | B06 |
| B08 | Multiview | P1 | bis zu vier Streams gleichzeitig, Fokus/Raster, Audio-Fokus (macOS) | B04, B06 |
| B09 | Auto-Update | P1 | Sparkle-Updater mit EdDSA, Release-Skripte, `appcast.xml` (macOS) | — |
| B10 | Website | P2 | Marketingseite mit Download, Changelog, FAQ, Datenschutz (Vercel) | B09 |

`P0` = ohne das ist es kein Player. `P1` = prägt das Produkt. `P2` = Begleitmaterial.

**Reihenfolge der Rückerfassung:** nach Risiko, nicht nach Nummer — Begründung in `features/index.md`.

## Offene Punkte

Alle vom 2026-09-15.

- **Erfolgskriterien** sind nicht festgelegt. Für ein Referenzprojekt z. B. Downloads je Release,
  Anfragen über die Website oder Anzahl der Apps, die das Muster übernehmen — noch zu entscheiden.
- **Keine `LICENSE`-Datei.** Das Repository ist öffentlich und als Open Source gedacht. Ohne Lizenz
  gilt aber rechtlich „alle Rechte vorbehalten" — niemand darf den Code verwenden.
- **Artefakte öffentlich:** `docs/` und `features/` werden in ein öffentliches Repository
  eingecheckt, einschließlich Fehlbestand, QA-Befunden und Auditbericht — also auch
  Sicherheitslücken, bevor sie behoben sind. Bewusst so entschieden am 2026-09-15.
- **Sprachbruch:** App-Oberfläche nur Deutsch, Website nur Englisch und auf internationale
  Mac-Nutzer ausgerichtet. `CFBundleDevelopmentRegion` steht auf `$(DEVELOPMENT_LANGUAGE)`.
- **`main` ist unveröffentlicht voraus.** Seit `v1.1` (2026-06-23) sind Bild-in-Bild, der
  Anzeigename „Mika+Player", der Owner-Wechsel zu `daumedia` (inkl. neuer `SUFeedURL`) und das
  neue App-Icon hinzugekommen — ohne Release und ohne Versionssprung (`MARKETING_VERSION` 1.1,
  Build 2). Die Website bewirbt Bild-in-Bild bereits.
- **Website verspricht mehr als der Code:** „double-clicking a .m3u opens it here". `Info.plist`
  registriert den Dokumenttyp, im Code gibt es aber keinen `onOpenURL`- oder Dokument-Handler.
- **Keine Notarisierung.** Die FAQ erklärt Nutzern den Gatekeeper-Umweg (Rechtsklick → Öffnen).
  Das Stack-Profil verlangt für eine Veröffentlichung Developer ID + Notarisierung.
- **`docs/datenschutz.md` fehlt**, obwohl Stufe B es vorsieht.
- **iOS gleichwertig, aber ungetestet:** Alle Tests laufen im macOS-Target. iOS-spezifisches
  Verhalten (Orientierungswechsel im Vollbild, Hintergrund-Audio, Auto-PiP) hat keinen Test.
- **README teils veraltet:** beschreibt das App-Icon als „roten Verlauf" (heute Violett/Mint)
  und nennt unter *Tests* nur den Parser.
