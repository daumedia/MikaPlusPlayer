# Features

Stand: 2026-10-01 · Stack-Profil: `swiftui-ios` + `swiftui-macos` · Bestandsprojekt, erfasst mit `sdd-erfassen`

| ID | Feature | Prio | Status | Abhängig von | Zuletzt |
|---|---|---|---|---|---|
| B01 | Xtream-Codes-Login | P0 | review | — | 2026-09-16 · QA 2: production-ready ja, offen nur mittel/niedrig (BF-40, BF-43–BF-46); nicht ausgeliefert |
| B02 | M3U-Import | P0 | building | — | 2026-09-28 · Reparatur verifiziert, Review: Nacharbeit (R-01–R-11 alle behoben, u. a. Sterne beim Aktualisieren 10/10 erhalten) eingespielt; QA 2 offen |
| B03 | Playlist-Verwaltung | P0 | building | B01, B02 | 2026-09-28 · Reparatur verifiziert, Review: Nacharbeit (R-01–R-11 alle behoben, u. a. Sterne beim Aktualisieren 10/10 erhalten) eingespielt; QA 2 offen |
| B04 | Senderliste | P0 | building | B03 | 2026-10-01 · Reparatur fertig und gereviewt; Nacharbeit R-1/R-2 fertig und verifiziert (R-1 nachgebessert für inaktive Fenster, neu OF-09), R-3–R-5 offen; BUG-06/-13/-14 teilweise (OF-07/OF-08); QA 2 offen |
| B05 | Favoriten | P1 | building | B03, B04 | 2026-10-01 · Reparatur fertig, verifiziert (macOS 519 Tests, 0 Fehlschläge; iOS gebaut) und gereviewt: Nachbesserungen F-04 und R-1 (inaktive Fenster), neu OF-10; BUG-02/-04/-09 behoben, BUG-01/-10/-11 über B02+B03; BUG-03, BUG-05–08 warten auf OF; QA 2 offen |
| B06 | Wiedergabe | P0 | building | B04 | 2026-09-28 · Reparatur fertig (476 Tests grün) und gereviewt: in Ordnung, 4 geringe Funde; BUG-03 (libVLC) wartet auf OF-06; QA 2 offen |
| B07 | Bild-in-Bild | P1 | building | B06 | 2026-09-29 · Reparatur fertig und gereviewt: in Ordnung (0 wichtige Funde); BUG-02/-06 warten auf OF-04/OF-03; QA 2 offen |
| B08 | Multiview | P1 | building | B04, B06 | 2026-09-29 · Reparatur fertig und gereviewt: in Ordnung, Absturz (BF-111) in allen vier Wegen behoben; 2 geringe Funde; BUG-08/-09 warten auf OF; QA 2 offen |
| B09 | Auto-Update | P1 | building | — | 2026-10-02 · Entscheidungen (`sdd-klaeren`): OF-11 Menü wie Sparkle (EC-11 neu), OF-12 Schalter wie gebaut (AK-31 ergänzt), OF-13 englische Reste hinnehmen, OF-14 17 Kriterien neu gefasst (AK-14 bis zur Notarisierung, AK-26 bis zum Ruleset unerfüllt) · nächster Schritt `/sdd-qa B09` in neuer Session · 2026-10-02 · Bau Durchlauf 2 (`sdd-build`, Branch `sdd/b09-bau`, nicht committet): Fehlerauftrag und Zielentwurf umgesetzt, Gesamtlauf 546 Tests grün bis auf 2 zeitabhängige (einzeln grün), Developer-ID-Export belegt; offen: Test-Notarisierung (notarytool-Profil fehlt), Pflichtproben; weiter `/sdd-klaeren B09` (OF-11–14), dann `/sdd-qa B09` · 2026-09-16 · QA 2: production-ready nein — kritisch nur noch BF-01 (Nutzer/GitHub); code-seitig 8 behoben, 6 neu mittel/niedrig · Entscheidungen 2026-10-01: BF-01 Übergangs-Release; BF-03/-05/-09 Developer ID (Zertifikat vorhanden); BF-07 Ruleset auf `main`; BF-08 Feed-Pflicht (Zeitpunkt OF-07); BF-18/-47/-48/-49/-50/-51/-119 beheben; BF-06 zurückgestellt bis Developer-ID-Release; OF-01 App deutsch (AK-01/02 neu), OF-02 Menüschalter (AK-31 neu), OF-04 2FA an, OF-05 Schlüssel wird gesichert, OF-06 Version 1.2, OF-07 Feed-Pflicht ab 1.2 (AK-12 neu), OF-08 Hinweis bessern, OF-09 Kurztest vor Release, OF-10 wie BF-49/119; OF-03 durch QA beantwortet · 2026-10-02: `design.md` als Zielentwurf überarbeitet (`sdd-architektur`, gegengeprüft), neu OF-11–OF-15; OF-15 entschieden (20-Tage-Notweg, AK-12 neu gefasst), OF-11–OF-14 bis nach dem Bau zurückgestellt; BF-06 neu entschieden: eigener Update-Schlüssel ab dem Release nach 1.2 (Annahme vom 01.10. war falsch) · nächster Schritt `/sdd-build B09` mit Befunden **und** Entwurf (Freigabe Betreiber 2026-10-02) |
| B10 | Website | P2 | review | B09 | 2026-09-30 · QA 2: production-ready nein — hoch nur BF-19 (Vercel) und BF-21 (Pflichtangaben), beide brauchen dich; 8 BUGs bestätigt behoben; neu BF-120 (next-Advisory, mittel) + 5 niedrig · Entscheidungen 2026-10-01: BF-19 freischalten nach BF-21 (vor Release 1.2); BF-21 beheben, Angaben liefert der Betreiber (neu OF-12); BF-120 next ≥ 16.3.6; BF-121–BF-125 beheben; BF-22 akzeptiert · nächster Schritt: OF-12 beantworten, dann `/sdd-build B10` |

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
