# B01 · Xtream-Codes-Login — Systemdesign

Status: `rekonstruiert` · Stand: 2026-09-15 · Rekonstruktion aus dem Code (sdd-erfassen) · Stack-Profil: `swiftui-ios` + `swiftui-macos`

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau, wie er auf `main` @ `c01f1cf` steht,
nicht, wie er sein sollte. Fragwürdiges ist markiert und verweist auf den *Fehlbestand* in `spec.md`.

## Überblick

Das Import-Sheet nimmt Host, Benutzername, Passwort und Format entgegen. Ein Tipp auf „Anmelden &
importieren" startet eine Hintergrundaufgabe. Sie legt einen `PlaylistImporter` an, der den
`XtreamClient` ruft. Der Client normalisiert den Host (immer `http://`) und fragt nacheinander
`player_api.php` ab: Anmeldung, Live-Kategorien, Live-Streams. Aus der Antwort baut er für jeden
Stream eine fertige Abspieladresse `http://host/live/<benutzer>/<passwort>/<id>.<ts|m3u8>` und gibt
kontextfreie `ParsedChannel`-Objekte zurück. Diese Form nutzt auch der M3U-Import (B02). Der
Importer legt daraus auf dem Main-Actor eine `Playlist` mit allen `Channel`-Datensätzen an und
speichert. Die Zugangsdaten stehen danach im Klartext in der Playlist-Adresse und in jeder
Stream-Adresse. Aus der Playlist-Adresse liest B03 sie beim Aktualisieren zurück.

## Szenen und Einstiege

SwiftUI, keine Routen. Plattform in Klammern.

| Einstieg | Zweck | Zugang |
|---|---|---|
| Tab „Playlists" → `PlaylistsView` → „+" im Kopf oder „Playlist importieren" im leeren Zustand → `.sheet` | öffnet `ImportPlaylistView` (beide) | jeder Nutzer des Geräts, keine Anmeldung an der App |
| `ImportPlaylistView`, Reiter „Xtream" (Standard) | Zugangsdaten eingeben, Format wählen, importieren (beide) | ebenso |

Kein Deep Link, kein Menüeintrag, kein Tastenkürzel (AS-05).

## Komponentenstruktur

```
PlaylistsView                                   (B03) Übersicht, @Query sortiert nach createdAt ↓
└── .sheet(isPresented: showingImport)
    └── ImportPlaylistView                       eigener NavigationStack, .tint(playerAccent),
        │                                        macOS min. 420 × 360
        ├── Form
        │   ├── Picker „Quelle" (segmentiert)    Xtream | URL | Datei — Standard Xtream
        │   ├── Section „Name (optional)"        TextField, gemeinsam für alle Reiter
        │   ├── [Xtream] Section „Xtream-Codes-Zugang"
        │   │   ├── TextField Host               ohne Autokorrektur; iOS: ohne Großschreibung, URL-Tastatur
        │   │   ├── TextField Benutzername       ohne Autokorrektur; iOS: ohne Großschreibung
        │   │   └── SecureField Passwort         verdeckt; kein textContentType gesetzt
        │   ├── [Xtream] Section „Stream-Format" Picker HLS (.m3u8) | MPEG-TS (.ts), Standard MPEG-TS,
        │   │                                    Footer = XtreamOutput.hint
        │   ├── [Xtream] Section
        │   │   └── Button „Anmelden & importieren"  disabled: !isComplete || isImporting
        │   │                                        Aktion: Task { importFromXtream() }  (ungebunden)
        │   ├── [URL] / [Datei]                  → B02
        │   └── Zeile ProgressView + „Importiere…"  sichtbar solange isImporting
        ├── Toolbar: „Abbrechen" (cancellationAction) → dismiss(), bricht die Aufgabe NICHT ab
        └── .alert „Fehler" / „OK"               gebunden an errorMessage != nil

Aufrufkette beim Import
ImportPlaylistView.importFromXtream()           @MainActor (View)
  ├── guard isComplete (praktisch unerreichbar, Button ist unter derselben Bedingung deaktiviert)
  ├── isImporting = true … defer false
  └── PlaylistImporter(modelContext:)            neue Instanz je Aufruf, @MainActor @Observable
      └── importFromXtream(credentials, output, name)
          ├── XtreamClient(credentials).fetchLiveChannels(output)     nicht isoliert, async
          │   ├── XtreamCredentials.baseURL()     trim · https→http · http:// ergänzen · / abschneiden ·
          │   │                                   Pfad und Query leeren (Fragment bleibt)
          │   ├── get(action: nil)                  → AuthResponse   → auth == 1 sonst .auth
          │   ├── get("get_live_categories")        → [Category]     → Wörterbuch id → Name, erste gewinnt
          │   ├── get("get_live_streams")           → [Stream]
          │   └── je Stream: String-Interpolation der Stream-Adresse → ParsedChannel
          │       get(): URLComponents + queryItems(username, password[, action]) ·
          │              URLSession.shared · cachePolicy .reloadIgnoringLocalCacheData ·
          │              timeoutInterval 60 · Status 2xx prüfen · JSONDecoder
          ├── leer → ImportError.emptyPlaylist
          ├── Playlist(name, sourceURL: playerAPIURL(), lastRefreshed: now, isXtream: true,
          │            xtreamOutput: rawValue) → insert
          ├── attach(parsed, preservedFavorites: [])  Channel je ParsedChannel, playlistID, channelCount
          └── modelContext.save()
  ├── Erfolg → dismiss()
  └── Fehler → errorMessage = error.localizedDescription → Alert
```

### Beteiligte Typen

| Typ | Datei | Rolle in B01 |
|---|---|---|
| `ImportPlaylistView` | `Views/ImportPlaylistView.swift` | Formular, Zustand (`xtreamHost`, `xtreamUser`, `xtreamPassword`, `xtreamOutput`, `name`, `isImporting`, `errorMessage`), Start des Imports, Alert |
| `XtreamOutput` | `Services/XtreamCodes.swift:5-34` | Enum `hls`/`mpegts`: Beschriftung, Hinweistext, Dateiendung der Stream-Adresse |
| `XtreamCredentials` | `Services/XtreamCodes.swift:37-117` | Wertetyp Host/Benutzer/Passwort; `baseURL()`, `playerAPIURL()`, `isComplete`; `init?(playerAPIURL:)` nur für B03; `playlistURL(output:)` ungenutzt |
| `XtreamClient` | `Services/XtreamClient.swift` | Netzwerk und Dekodierung, `XtreamError` mit drei Meldungen, private DTOs `AuthResponse`, `Category`, `Stream`, `FlexibleID` |
| `PlaylistImporter` | `Services/PlaylistImporter.swift:61-85, 154-175` | einziger Ort, der `Playlist`/`Channel` anlegt; `ImportError.emptyPlaylist` |
| `ParsedChannel` | `Services/M3UParser.swift:6-12` | DTO, gemeinsam mit B02 |
| `Playlist`, `Channel` | `Models/` | Persistenz, siehe unten |

## Datenmodell

Aus `docs/datenmodell.md`, beschränkt auf das, was B01 schreibt. B01 führt **keine** neuen Felder
ein und keine Schemaänderung. Eine Migration ist nicht nötig; es gilt der app-weite Stand ohne
`VersionedSchema` (DM-04).

### Entität `Playlist` (Tabelle `ZPLAYLIST`)

| Feld | Typ | Pflicht | Was B01 hineinschreibt |
|---|---|---|---|
| `id` | `UUID` | ja | `UUID()` |
| `name` | `String` | ja | Eingabe unverändert; leer → `baseURL().host` (ohne Schema und Port), ersatzweise `"Xtream"` |
| `sourceURL` | `URL?` | nein | ⚠ `http://<host>[:<port>]/player_api.php?username=<…>&password=<…>`, **Klartext** (FB-01) |
| `createdAt` | `Date` | ja | Zeitpunkt der Anlage |
| `lastRefreshed` | `Date?` | nein | Zeitpunkt des Imports |
| `isXtream` | `Bool` | ja | `true` |
| `xtreamOutput` | `String?` | nein | `"mpegts"` oder `"hls"`. Der Kommentar `Playlist.swift:21` nennt abweichend `"m3u8"/"ts"` (DM-11) |
| `channelCount` | `Int` | ja | Anzahl der angelegten Sender |
| `channels` | `[Channel]` | — | alle Sender, `cascade` |

### Entität `Channel` (Tabelle `ZCHANNEL`)

| Feld | Typ | Pflicht | Was B01 hineinschreibt |
|---|---|---|---|
| `id` | `UUID` | ja | `UUID()` |
| `name` | `String` | ja | `name` aus `get_live_streams`, unverändert (auch leer) |
| `streamURL` | `URL` | ja | ⚠ `http://<host>[:<port>]/live/<benutzer>/<passwort>/<stream_id>.<ts\|m3u8>`, **Klartext**, per Interpolation ohne Kodierung (FB-01, FB-06) |
| `logoURL` | `URL?` | nein | `stream_icon`, leer oder `null` → `nil`; beliebiger Host |
| `group` | `String?` | nein | Kategoriename über `category_id`, sonst `nil` |
| `tvgID` | `String?` | nein | `epg_channel_id`, leer oder `null` → `nil` |
| `isFavorite` | `Bool` | ja | `false` |
| `playlist` / `playlistID` | `Playlist?` / `UUID?` | nein | die neue Playlist bzw. ihre `id` |

Beziehungen: Eine `Playlist` hat viele `Channel`, Löschregel `cascade`.
Indizes: keine zusätzlichen (DM-05); B01 filtert nicht.

### Außerhalb des Schemas gespeichert

| Ort | Inhalt | Entsteht durch |
|---|---|---|
| `default.store`, macOS `~/Library/Application Support/`, iOS App-Container | die Tabellen oben | `MikaPlusPlayerApp.swift:7-15`, Standard-`ModelConfiguration` |
| `Cache.db`, macOS `~/Library/Caches/lu.daumedia.MikaPlusPlayer/`, iOS `Library/Caches` | ⚠ die drei Anfrage-Adressen mit Zugangsdaten samt Antworten (FB-03) | Standardverhalten von `URLSession.shared` / `URLCache.shared` (512 KB Speicher, 20 MB Platte) |

### Nicht persistiert

`XtreamCredentials`, `XtreamOutput`, `ParsedChannel`, die DTOs des Clients, der Formularzustand
des Sheets. Das Passwort bleibt nach dem Import im `@State` des Sheets, bis das Sheet verschwindet.

## Zugriffsregeln

Die App hat keine Konten und keine Rollen. Zugriffsregeln greifen nur über das Betriebssystem.

| Wer | Darf lesen | Darf schreiben | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | alle Playlists und Sender; das Passwort ist in der Oberfläche nirgends zu sehen | anlegen (B01), aktualisieren und löschen (B03), nicht ändern | nichts, Einzelnutzer |
| andere Prozesse desselben macOS-Benutzers | ⚠ `default.store` und `Cache.db` samt Zugangsdaten | dieselben Dateien | **nichts**: App-Sandbox aus (`MikaPlusPlayer.entitlements:7-8`), keine Keychain (FB-01, FB-09) |
| andere Apps unter iOS | nichts | nichts | iOS-App-Sandbox des Systems |
| Backup (Time Machine, iCloud- oder Geräte-Backup) | ⚠ Datenbank und Cache | — | kein `isExcludedFromBackup` (FB-08) |
| Mitleser im Netz (WLAN, Proxy, Anbieter-Netz) | ⚠ Benutzername und Passwort in jeder Anfrage und jedem Stream-Abruf | — | nichts: HTTP erzwungen, ATS global aus (FB-02) |
| IPTV-Anbieter bzw. Weiterleitungsziel | Zugangsdaten, IP-Adresse | — | protokollbedingt; Weiterleitungen werden befolgt (OF-04) |

## Missbrauchsschutz

| Stelle | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| „Anmelden & importieren" | ein laufender Import je Sheet, Button währenddessen deaktiviert | Button nicht bedienbar; Rennen beim Doppelklick möglich (EC-19) | `ImportPlaylistView.swift:86, 157-158` |
| Wiederholte Fehlanmeldungen | **keins** | Button nach jedem Fehler sofort wieder aktiv (FB-04) | — |
| Leerlauf je Anfrage | 60 s ohne Daten | „Netzwerkfehler: The request timed out." | `XtreamClient.swift:77` |
| Gesamtdauer eines Imports | **keins** | langsames Tröpfeln hält den Import offen (FB-05) | — |
| Antwortgröße, Anzahl Streams | **keins** | alles wird in den Speicher geladen und angelegt (FB-05) | — |
| Anfragen je Import | drei, nacheinander, keine Wiederholung | beim ersten Fehler Abbruch | `XtreamClient.swift:31-42` |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| IPTV-Panel am eingegebenen Host, `/player_api.php` | Anmeldung, Live-Kategorien, Live-Streams | ⚠ Benutzername und Passwort als Query-Parameter **über HTTP**, auch bei `https`-Eingabe; die IP-Adresse; die Standard-Kopfzeilen von `URLSession`, nicht mitgeschnitten | nichts; nur Leerzeichen am Rand von Benutzer und Passwort |
| Ziel einer HTTP-Weiterleitung des Panels | wie oben, wenn das Panel umleitet | was die Weiterleitungsadresse enthält, im Test die vollständigen Zugangsdaten | nichts (OF-04) |
| Logo-Hosts aus `stream_icon` | in B01 nur gespeichert, geladen erst in B04 | in B01 nichts | — |
| Stream-Abruf am eingegebenen Host, `/live/…` | in B01 nur gebaut, abgerufen erst in B06/B08 | in B01 nichts | — |

Kein KI-Dienst, keine Analyse, kein Fehler-Tracking, kein Server von daumedia.

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Senderliste über `player_api.php` (JSON) | klassischer `get.php`-M3U-Link über den vorhandenen M3U-Parser; der Code dafür existiert noch (`playlistURL(output:)`) | Kommentar `XtreamClient.swift:3-6`, README, CLAUDE.md: viele Panels sperren `get.php` („HTTP 885 hinter Cloudflare") |
| 2 | ⚠ Schema immer `http://`, eingegebenes `https://` wird überschrieben | `https` beibehalten; erst TLS versuchen, dann nach Rückfrage auf HTTP zurückfallen | Kommentar `XtreamCodes.swift:64`: „viele IPTV-Panels bedienen nur HTTP". Warum eine ausdrückliche `https`-Eingabe nicht respektiert wird, ist nicht erkennbar |
| 3 | Standardformat MPEG-TS | HLS als Standard (spielt ohne VLCKit) | Kommentar `ImportPlaylistView.swift:29-30`: Panels wie Telecasty sperren HLS (HTTP 407) |
| 4 | ⚠ Zugangsdaten als Teil von `sourceURL` gespeichert | Keychain-Eintrag je Playlist, `sourceURL` ohne Geheimnis | Kommentar `XtreamCodes.swift:83-84`: Refresh (B03) rekonstruiert daraus. Warum nicht die Keychain, ist nicht erkennbar |
| 5 | ⚠ Stream-Adressen beim Import fertig gebaut und je Sender gespeichert | nur `stream_id` speichern, Adresse beim Abspielen aus Keychain und Host bauen | Grund nicht erkennbar; vermutlich, damit Xtream und M3U dieselbe `ParsedChannel`-Form und denselben Wiedergabepfad nutzen |
| 6 | Gemeinsames DTO `ParsedChannel` statt direkter `@Model`-Erzeugung im Client | Client legt `Channel` selbst an | Kommentar `M3UParser.swift:3-5`: testbar ohne `ModelContext`, nicht an einen Actor gebunden |
| 7 | Drei Anfragen nacheinander | Kategorien und Streams parallel | Grund nicht erkennbar |
| 8 | Erfolg allein an `user_info.auth == 1` | zusätzlich `status`, `exp_date`, `max_connections` auswerten | Grund nicht erkennbar (OF-03) |
| 9 | Stream-Host = eingegebener Host, `server_info.url` des Panels ignoriert | vom Panel gemeldeten Host und Port verwenden | Grund nicht erkennbar; schützt nebenbei davor, dass ein Panel die Streams auf einen fremden Host lenkt |
| 10 | `FlexibleID` nur für `stream_id` | auch für `category_id`, wie der Kommentar ankündigt; tolerante Dekodierung je Eintrag | Grund nicht erkennbar (FB-07) |
| 11 | Neue `PlaylistImporter`-Instanz je Aktion, Fortschritt über eigenen `isImporting`-Zustand | ein Importer im Environment, dessen `isWorking` die View beobachtet | Grund nicht erkennbar; `isWorking` bleibt dadurch für das Sheet wirkungslos |
| 12 | Ungebundener `Task` im Button | `.task`-gebundene oder abbrechbare Aufgabe, die „Abbrechen" beendet | Grund nicht erkennbar (OF-02) |
| 13 | Fehler als Alert mit `localizedDescription`, Systemtexte ungefiltert | eigene deutsche Meldungen je `URLError`-Code | Grund nicht erkennbar (OF-06) |
| 14 | `timeoutInterval = 60`, `cachePolicy = .reloadIgnoringLocalCacheData` | eigene `URLSession` mit `ephemeral`-Konfiguration ohne Cache und mit Gesamt-Timeout | Grund nicht erkennbar; dass die Policy das Schreiben in den Cache nicht verhindert, wurde offenbar nicht bedacht (FB-03) |
| 15 | Name der Playlist ungekürzt übernommen | Leerzeichen trimmen, leer → Host | Grund nicht erkennbar |

## Abdeckung der Akzeptanzkriterien

Umgedreht: Was erfüllt das Kriterium heute? Fundstellen beziehen sich auf `Sources/`.

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `PlaylistsView.swift:17-24, 91, 70-72` (Einstiege, Sheet); `ImportPlaylistView.swift:18, 45-48, 50-52, 56-69, 80-87, 121, 141-143` | Reiter-Standard `.xtream` |
| AK-02 | `ImportPlaylistView.swift:31, 70-79`; `XtreamCodes.swift:13-25` | Beschriftung und Hinweis aus `XtreamOutput` |
| AK-03 | `ImportPlaylistView.swift:86, 148-150`; `XtreamCodes.swift:114-116` (`isComplete`, trimmt nur `.whitespaces`) | Test `XtreamCodesTests.testIncompleteCredentials` |
| AK-04 | `ImportPlaylistView.swift:57-67` | |
| AK-05 | `ImportPlaylistView.swift:86, 101, 110, 114-119, 123-125, 157-158` | „Abbrechen" ohne `disabled` |
| AK-06 | `ImportPlaylistView.swift:161-162`; `PlaylistImporter.swift:74-83`; Anzeige `PlaylistsView.swift:8, 128, 137` | |
| AK-07 | `PlaylistImporter.swift:73`; `XtreamCodes.swift:65-81` | `name.isEmpty` ohne Trim |
| AK-08 | `XtreamClient.swift:35-56` (Wörterbuch `uniquingKeysWith: first`, `compactMap`, Leerwert-Filter); `PlaylistImporter.swift:154-175` | nur `get_live_streams` |
| AK-09 | `PlaylistImporter.swift:61-85`, keine Prüfung auf Vorhandenes | ⚠ OF-01 |
| AK-10 | `XtreamClient.swift:31, 35, 42, 61-72` | kein `get.php`-Aufruf im App-Code |
| AK-11 | `XtreamCodes.swift:65-81` | Tests `testBuildsURLFromBareHost`, `testNormalizesSchemePortAndSlash`, beide über `get.php` statt `player_api.php` |
| AK-12 | `XtreamCodes.swift:69-74`; `Info.plist:39-40` | ⚠ FB-02; Test `testDowngradesHTTPS` hält das Herabstufen als gewollt fest |
| AK-13 | `XtreamClient.swift:27-28, 67-68`; `XtreamCodes.swift:91-92` | `.whitespaces` ohne Zeilenumbrüche |
| AK-14 | `XtreamClient.swift:46-47` (Interpolation; `URL(string:)` kodiert nur, was in einer URL ungültig ist — beim Ausführen Leerzeichen, Nicht-ASCII, Zeilenumbruch, einzelnes `%` —, nicht aber `#`, `?`, `/`); `URLQueryItem` in `XtreamClient.swift:66-71` | ⚠ FB-06 |
| AK-15 | `XtreamCodes.swift:28-33`; `XtreamClient.swift:43-46, 127-134` | `server_info` wird nicht dekodiert |
| AK-16 | `XtreamClient.swift:32, 18, 94-100` | |
| AK-17 | `XtreamClient.swift:79-81, 19` | |
| AK-18 | `XtreamClient.swift:82, 85-86` | |
| AK-19 | `PlaylistImporter.swift:71`; `ImportError.emptyPlaylist` `PlaylistImporter.swift:13` | |
| AK-20 | `XtreamClient.swift:77, 87-88` | Systemtext englisch, weil das Bundle nur `en` als Lokalisierung hat |
| AK-21 | `XtreamClient.swift:26, 17`; `XtreamCodes.swift:77` | |
| AK-22 | `PlaylistImporter.swift:69-71` (alle Fehler vor `insert`); `ImportPlaylistView.swift:134-138, 158, 163-165` | |
| AK-23 | `XtreamClient.swift:15-20, 79-89` (eigene Texte ohne Adresse; `URLError.localizedDescription` ohne Adresse) | nur für die geprüften Fehlerarten belegt |
| AK-24 | `PlaylistImporter.swift:76, 162`; `XtreamClient.swift:46` | ⚠ FB-01 |
| AK-25 | `XtreamClient.swift:75-78` (`URLSession.shared`) | ⚠ FB-03 |
| AK-26 | `URLSession.shared` ohne Delegate, Standard: Weiterleitungen folgen | ⚠ OF-04 |
| AK-27 | Fehlen jedes Logging-Aufrufs in `Sources/` | nicht ausgeführt |
| AK-28 | `MikaPlusPlayerApp.swift:7-15`; `MikaPlusPlayer.entitlements:7-8` | ⚠ FB-08, FB-09 |
| AK-29 | `PlaylistsView.swift:39-52, 104-107` (nur „Aktualisieren" und „Löschen"); keine Bearbeiten-Ansicht | Löschen gehört zu B03 |
| AK-30 | Repository-Historie (Beispielwerte in `Tests/XtreamCodesTests.swift`, Platzhalter in Kommentaren) | kein Code, Zustand des Repos |

### Code ohne AK-Zuordnung

Hinweise auf toten Code oder auf Verhalten, das einem anderen Feature gehört:

- **`XtreamCredentials.playlistURL(output:)`** (`XtreamCodes.swift:97-112`): wird von der App nie
  aufgerufen, nur von `XtreamCodesTests`. Drei der vier bestehenden Tests prüfen die
  Host-Normalisierung deshalb über eine Adresse, die die App gar nicht benutzt. Die tatsächlich
  benutzte `playerAPIURL()` und die Stream-Adressen haben keinen Test.
- **`PlaylistImporter.isWorking`** (`PlaylistImporter.swift:29, 66-67`): wird gesetzt, aber vom
  Sheet nicht beobachtet, weil jeder Aufruf eine eigene Instanz erzeugt.
- **Meldung „Bitte Host, Benutzername und Passwort ausfüllen."** (`ImportPlaylistView.swift:153-156`):
  praktisch unerreichbar, weil der Button unter derselben Bedingung deaktiviert ist.
- **`XtreamError.invalidHost` in `get()`** (`XtreamClient.swift:62-64, 72`): nur erreichbar, wenn
  aus einer bereits gültigen Basisadresse keine Adresse entsteht; beim Ausführen nicht aufgetreten.
- **`XtreamCredentials.init?(playerAPIURL:)`** (`XtreamCodes.swift:50-61`): gehört zum Aktualisieren
  (B03). Beim Ausführen belegt: stellt Schema, Host, Port, Benutzer und Passwort wieder her, nimmt
  bei doppelten Parametern den ersten und liefert `nil`, wenn Benutzer oder Passwort fehlen.
- **Kommentare mit abweichenden Angaben:** `Playlist.swift:21` nennt `"m3u8"/"ts"` (DM-11),
  `XtreamClient.swift:126` nennt `category_id` als flexibel (FB-07).

### Bestehende Tests

`Tests/XtreamCodesTests.swift`, 4 Tests, nur macOS-Target:

| Test | Prüft | Deckt |
|---|---|---|
| `testBuildsURLFromBareHost` | `get.php`-Adresse aus Host ohne Schema | AK-11, indirekt |
| `testNormalizesSchemePortAndSlash` | Port und Schrägstrich, über `get.php` | AK-11, indirekt |
| `testDowngradesHTTPS` | `https` → `http` | AK-12 (hält das ⚠-Verhalten als gewollt fest) |
| `testIncompleteCredentials` | leerer Host → `nil`; `isComplete` | AK-03, AK-21 teilweise |

Ohne Test: `XtreamClient` insgesamt, `playerAPIURL()`, die Stream-Adressen, alle Fehlermeldungen,
`PlaylistImporter.importFromXtream`, die Oberfläche.
