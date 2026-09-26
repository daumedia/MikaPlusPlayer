# Features

Stand: 2026-09-26 · Stack-Profil: `swiftui-ios` + `swiftui-macos` · Bestandsprojekt, erfasst mit `sdd-erfassen`

| ID | Feature | Prio | Status | Abhängig von | Zuletzt |
|---|---|---|---|---|---|
| B01 | Xtream-Codes-Login | P0 | review | — | 2026-09-16 · QA 2: production-ready ja, offen nur mittel/niedrig (BF-40, BF-43–BF-46); nicht ausgeliefert |
| B02 | M3U-Import | P0 | building | — | 2026-09-26 · QA 1: hoch; Reparatur gemeinsam mit B03 geschrieben, kompiliert (macOS+iOS), aber **nicht verifiziert und nicht gereviewt** (Workflow angehalten); QA 2 offen |
| B03 | Playlist-Verwaltung | P0 | building | B01, B02 | 2026-09-26 · QA 1: hoch; Reparatur gemeinsam mit B02 geschrieben, kompiliert (macOS+iOS), aber **nicht verifiziert und nicht gereviewt** (Workflow angehalten); QA 2 offen |
| B04 | Senderliste | P0 | review | B03 | 2026-09-26 · QA 1: production-ready ja, höchster Grad mittel (BF-73–BF-86); Reparatur nicht begonnen |
| B05 | Favoriten | P1 | review | B03, B04 | 2026-09-26 · QA 1: production-ready ja, höchster Grad mittel (BF-87–BF-95); Teile über B02+B03 mitrepariert (unverifiziert) |
| B06 | Wiedergabe | P0 | review | B04 | 2026-09-26 · QA 1: hoch (BF-96–BF-98, gegengeprüft ✅); Reparatur nicht begonnen |
| B07 | Bild-in-Bild | P1 | review | B06 | 2026-09-26 · QA 1: hoch (BF-105, gegengeprüft ✅); Reparatur nicht begonnen |
| B08 | Multiview | P1 | review | B04, B06 | 2026-09-26 · QA 1: **kritisch** (BF-111 Absturz seit v1.1) + hoch (BF-112, BF-113), gegengeprüft ✅; Reparatur nicht begonnen |
| B09 | Auto-Update | P1 | review | — | 2026-09-16 · QA 2: production-ready nein — kritisch nur noch BF-01 (Nutzer/GitHub); code-seitig 8 behoben, 6 neu mittel/niedrig |
| B10 | Website | P2 | building | B09 | 2026-09-26 · QA 1: hoch; Reparatur Teil 1 fertig (7 BUGs), Teil 2 (Datenschutz, Aussagen) offen; QA 2 offen |

## Reihenfolge der Rückerfassung

B01 → B03 → B09 → B02 → B06 → B04 → B10 → B08 → B05 → B07

Nach Risiko, nicht nach Nummer. Die Rückerfassung ist die Eintrittskarte für `sdd-qa`, und die QA
ist hier ein Sicherheitsaudit.

| Rang | Feature | Warum an dieser Stelle |
|---|---|---|
| 1 | **B01** Xtream-Codes-Login | Personendaten: nimmt Zugangsdaten entgegen, speichert sie im Klartext (DM-01), erzwingt HTTP |
| 1 | **B03** Playlist-Verwaltung | Personendaten: liest die gespeicherten Zugangsdaten beim Refresh zurück und sendet sie erneut; einziger Löschweg für Nutzerdaten (DM-08, DM-10) |
| 2 | **B09** Auto-Update | der einzige Weg, auf dem neuer Code auf fremde Rechner kommt. Die Integrität hängt allein an EdDSA: ad-hoc signiert, nicht notarisiert, Library-Validation aus, `get-task-allow` in v1.1, Feed-URL gewechselt, Schlüssel familienweit geteilt |
| 2 | **B02** M3U-Import | beliebige Hosts, parst unvertraute Dateien und Netzantworten; URL kann Zugangsdaten tragen; Dokumenttyp ohne Handler (AS-01) |
| 2 | **B06** Wiedergabe | Streams von beliebigen Hosts durch VLCKit (nativer Parser für unvertraute Medien); Zugangsdaten stehen in jeder Stream-URL und können in Fehlermeldungen landen |
| 2 | **B04** Senderliste | lädt Logos von beliebigen Hosts (IP-Abfluss beim Scrollen); Sucheingabe; Performance bei 17.000 Sendern ohne Index (DM-05, DM-07) |
| 2 | **B10** Website | trägt die einzige Datenschutzerklärung — sie muss zum Code passen; serverseitiger GitHub-Token; verspricht nachweislich mehr als der Code |
| 2 | **B08** Multiview | bis zu vier parallele Verbindungen zum Anbieter; hält `Channel`-Objekte über Refresh/Löschen hinweg (DM-10, AS-02) |
| 4 | **B05** Favoriten | rein lokal; bekannter Befund DM-06 ist funktional, nicht sicherheitsrelevant |
| 4 | **B07** Bild-in-Bild | Darstellung auf Systemfunktion, keine eigenen Daten oder Verbindungen |

## Zuschnitt

Ausgangspunkt für die Rückerfassung je Feature. Dateien aus der Kartierung, in Phase 2 zu bestätigen.
Die Auffälligkeiten sind **Hinweise zum Prüfen**, keine festgestellten Befunde.

### B01 · Xtream-Codes-Login — beide Plattformen
- **Dateien:** `Views/ImportPlaylistView.swift` (Tab „Xtream"), `Services/XtreamCodes.swift`, `Services/XtreamClient.swift`, `Services/PlaylistImporter.swift` (`importFromXtream`), `Models/Playlist.swift`
- **Tests:** `XtreamCodesTests` (4)
- **Hinweise:** Klartext in `sourceURL` und jeder `streamURL` (DM-01) · `https://` → `http://` · Benutzer/Passwort ohne Prozentkodierung in den Stream-Pfad interpoliert · `playlistURL(output:)` (get.php) nur von Tests benutzt · Standardformat MPEG-TS

### B02 · M3U-Import — beide Plattformen
- **Dateien:** `Views/ImportPlaylistView.swift` (Tabs „URL", „Datei"), `Services/M3UParser.swift`, `Services/PlaylistImporter.swift` (`importFromURL`, `importFromFile`, `decodeText`), `Resources/Info.plist` (Dokumenttyp)
- **Tests:** `M3UParserTests` (4)
- **Hinweise:** keine Größenbegrenzung für Download oder Datei · `fileImporter` erlaubt `public.plainText` · Dokumenttyp ohne Handler (AS-01); Website verspricht Doppelklick-Import

### B03 · Playlist-Verwaltung — beide Plattformen
- **Dateien:** `Views/PlaylistsView.swift`, `Services/PlaylistImporter.swift` (`refresh`, `attach`), `Models/Playlist.swift`
- **Tests:** keine
- **Hinweise:** Löschen ohne Rückfrage (DM-08) · Refresh lädt alle Sender in den Speicher (DM-07) und ersetzt alle `Channel`-Objekte (DM-10) · `lastRefreshed` wird nie angezeigt

### B04 · Senderliste — beide Plattformen
- **Dateien:** `Views/ChannelListView.swift`, `Views/ChannelRowView.swift`, `Models/Channel.swift`
- **Tests:** keine
- **Hinweise:** Logos per `AsyncImage` von beliebigen Hosts · keine Indizes (DM-05) · Gruppenliste im Speicher (DM-07)

### B05 · Favoriten — beide Plattformen
- **Dateien:** `Views/FavoritesView.swift`, `Views/ChannelRowView.swift` (Stern), `Models/Channel.swift` (`favoriteKey`), `Services/PlaylistImporter.swift` (`refresh`)
- **Tests:** keine
- **Hinweise:** `favoriteKey` nicht eindeutig (DM-06) · Favoriten verschwinden mit ihrer Playlist

### B06 · Wiedergabe — beide Plattformen
- **Dateien:** `Views/PlayerView.swift`, `Services/PlaybackEngine.swift`, `Services/AVKitPlaybackEngine.swift`, `Services/VLCPlaybackEngine.swift`, `Services/PlayerLayerView.swift`
- **Tests:** `PlaybackEngineTests` (4 von 6, ohne die beiden PiP-Tests)
- **Umfasst:** Engine-Wahl nach Endung, Steuerung, HUD, Vollbild (iOS/macOS), Tastatursteuerung
- **Hinweise:** Engine-Wahl nur nach Dateiendung (`.m3u` → HLS) · Fehlermeldungen der Engines werden ungefiltert angezeigt · Fehleransicht verweist auf README (DS-06) · VLC-Engine ohne `stop`/`deinit` · Vollbildfenster bei mehreren Fenstern (AS-03) · iPhone-Orientierung (AS-04)

### B07 · Bild-in-Bild — beide Plattformen, nur AVKit-Engine
- **Dateien:** `Services/AVKitPlaybackEngine.swift` (PiP-Controller, Delegate), `Services/PlaybackEngine.swift` (Protokoll-Defaults), `Views/PlayerView.swift` (Button, Taste P, `onDisappear`)
- **Tests:** `PlaybackEngineTests` (2)
- **Hinweise:** in keinem Release enthalten (seit v1.1 nur auf `main`), Website bewirbt es · für `.ts`-Streams nicht verfügbar · Auto-Start nur iOS

### B08 · Multiview — nur macOS
- **Dateien:** `Services/MultiviewSession.swift`, `Views/MultiviewScreen.swift`, `Views/MultiviewTile.swift`, `Views/ChannelRowView.swift` (⊞-Button), `App/MikaPlusPlayerApp.swift` (Fenster)
- **Tests:** keine
- **Hinweise:** max. 4 Streams, Anbieter erlauben oft nur eine Verbindung · hält `Channel`-Objekte (DM-10) · eine Session für alle Hauptfenster (AS-02)

### B09 · Auto-Update — nur macOS
- **Dateien:** `Services/SparkleUpdater.swift`, `App/MikaPlusPlayerApp.swift` (Menü), `Resources/Info.plist` (`SU*`), `Resources/MikaPlusPlayer.entitlements`, `scripts/release.sh`, `scripts/build-macos.sh`, `scripts/make-dmg.sh`, `appcast.xml`, `project.yml` (Signatur)
- **Tests:** keine
- **Hinweise:** ad-hoc signiert, nicht notarisiert · `disable-library-validation` · installierte v1.1 mit `get-task-allow = true` · `SUFeedURL` von `Mukaarts` auf `daumedia` gewechselt, v1.1 fragt noch die alte URL ab (derzeit erreichbar) · EdDSA-Schlüssel familienweit geteilt · `main` seit v1.1 ohne Versionssprung · keine Schema-Migration bei Updates (DM-04)

### B10 · Website — Next.js unter `web/`, Vercel
- **Dateien:** `web/app/*` (Start, Changelog, Datenschutz, Support, Download-Route, OG-Bild, Sitemap, robots), `web/components/*`, `web/content/*`, `web/lib/releases.ts`, `web/lib/site.ts`
- **Tests:** keine
- **Hinweise:** Datenschutzseite ist die einzige Datenschutzerklärung · `GITHUB_TOKEN` optional serverseitig · verspricht Doppelklick-Import (fehlt) und bewirbt Bild-in-Bild (nicht released) · nur Englisch, App nur Deutsch · keine Lizenz im Repo, obwohl auf den Quellcode verwiesen wird
