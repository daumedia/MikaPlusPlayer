# B02 · M3U-Import — Systemdesign

Status: `rekonstruiert` · Stand: 2026-09-16 · Rekonstruktion aus dem Code (sdd-erfassen) · Stack-Profil: `swiftui-ios` + `swiftui-macos`

**Stand: `c01f1cf` + Reparatur B01 (2026-09-16).** Die Dateien und Methoden von B02 sind in diesem Stand
gegenüber `c01f1cf` unverändert; siehe Kopf von `spec.md`.

**Kein Code in diesem Dokument.** Beschrieben ist der Aufbau, wie er steht, nicht, wie er sein sollte.
Fragwürdiges ist markiert und verweist auf den *Fehlbestand* in `spec.md`. Fundstellen beziehen sich
auf `Sources/`.

## Überblick

Der Import hat zwei Eingänge im selben Sheet wie der Xtream-Login (B01).

**Reiter „URL":** Die Eingabe wird am Rand gekürzt und in eine Adresse umgewandelt. Ohne Schema bricht
der Import ab. `URLSession.shared` ruft die Adresse per GET ab. Ein Status außerhalb von 2xx wird zur
Meldung. Die Bytes werden als UTF-8 gelesen, ersatzweise als Latin-1. Der `M3UParser` zerlegt den Text
in kontextfreie `ParsedChannel`-Werte.

**Reiter „Datei":** Der System-Dateidialog (`fileImporter`) liefert eine Datei-Adresse. Die App holt sich
das Zugriffsrecht (nur iOS wirksam), liest die Datei vollständig und parst sie genauso.

In beiden Fällen legt der `PlaylistImporter` auf dem Main-Actor eine `Playlist` an und erzeugt je
Eintrag einen `Channel`. Er hängt jeden Sender einzeln an die Beziehung und speichert am Ende einmal.
Bei URL-Playlists bleibt die eingegebene Adresse als `sourceURL` stehen, einschließlich etwaiger
Zugangsdaten; daraus aktualisiert B03. Datei-Playlists haben keine Quelladresse.

Daneben meldet `Info.plist` die App als Öffner für M3U- und Textdateien an. Ein Handler dafür fehlt
im Code: SwiftUI öffnet beim Öffnen-Ereignis nur ein weiteres Fenster.

## Szenen und Einstiege

SwiftUI, keine Routen. Plattform in Klammern.

| Einstieg | Zweck | Zugang |
|---|---|---|
| Tab „Playlists" → `PlaylistsView` → „+" oder „Playlist importieren" → `.sheet` → Reiter „URL" | M3U per Adresse importieren (beide) | jeder Nutzer des Geräts, keine Anmeldung an der App |
| dasselbe Sheet → Reiter „Datei" → „Datei auswählen (.m3u/.m3u8)" → `fileImporter` | M3U aus einer Datei importieren (beide) | ebenso; macOS: jede für den Benutzer lesbare Datei, iOS: über den Dateien-Dialog |
| Finder „Öffnen mit" / `open -a` (macOS), „Öffnen in" (iOS) | ⚠ **kein Import**. macOS: zusätzliches leeres `WindowGroup`-Fenster; iOS: Datei landet in der Inbox (FB-06) | System, über `CFBundleDocumentTypes` |

Kein Deep Link, kein Menüeintrag, kein Tastenkürzel, kein Drag & Drop (AS-05).

## Komponentenstruktur

```
PlaylistsView                                    (B03) Übersicht, @Query nach createdAt ↓
└── .sheet(isPresented: showingImport)
    └── ImportPlaylistView                        eigener NavigationStack, .tint(playerAccent), macOS min. 420 × 360
        ├── Form
        │   ├── Picker „Quelle" (segmentiert)     Xtream | URL | Datei — Standard Xtream (B01)
        │   ├── Section „Name (optional)"         TextField, gemeinsam für alle Reiter
        │   ├── [URL] Section „Playlist-URL"
        │   │   ├── TextField „https://… .m3u8"   ohne Autokorrektur; iOS: ohne Großschreibung, URL-Tastatur
        │   │   └── Button „Von URL importieren"  disabled: urlString.isEmpty || isImporting
        │   │                                     Aktion: Task { importFromURL() }  ⚠ ungebunden (FB-08, FB-09)
        │   ├── [Datei] Section „Lokale Datei"
        │   │   └── Button „Datei auswählen (.m3u/.m3u8)"  disabled: isImporting → showingFileImporter = true
        │   ├── [Xtream] …                        → B01
        │   └── Zeile ProgressView + „Importiere…"  solange isImporting
        ├── Toolbar „Abbrechen"                    xtreamImportTask?.cancel(); dismiss()  ⚠ URL/Datei laufen weiter
        ├── .fileImporter(allowedContentTypes: [m3u, m3u8, .plainText], allowsMultipleSelection: false)
        │   └── handleFileResult                   Erfolg → Task { importFromFile(url) } ⚠ ungebunden
        │                                          Fehler → errorMessage = localizedDescription
        ├── .alert „Fehler" / „OK"                 gebunden an errorMessage != nil
        └── .onDisappear                           bricht nur den Xtream-Import ab

Aufrufkette URL
ImportPlaylistView.importFromURL()                 @MainActor (View)
  ├── isImporting = true … defer false            erst innerhalb der Aufgabe gesetzt (FB-09)
  └── PlaylistImporter(modelContext:)              neue Instanz je Aufruf, @MainActor @Observable
      └── importFromURL(urlString, name)
          ├── trim .whitespacesAndNewlines → URL(string:) → scheme != nil  sonst ImportError.invalidURL
          ├── fetchText(url)
          │   ├── URLRequest, cachePolicy .reloadIgnoringLocalCacheData   ⚠ schreibt trotzdem in den Cache (FB-02)
          │   ├── URLSession.shared.data(for:)     Warten auf das Netz: Main-Actor frei
          │   │                                    Standard: 60 s Leerlauf, Weiterleitungen folgen, Cookies, Basic-Auth
          │   ├── Status ∉ 200..<300 → ImportError.network("HTTP <n>")
          │   ├── andere Fehler → ImportError.network(localizedDescription)
          │   └── decodeText: UTF-8, sonst ISO-Latin-1, sonst ""
          ├── M3UParser.parse(text)                ⚠ ab hier bis save() blockiert (FB-04)
          ├── leer → ImportError.emptyPlaylist
          ├── Playlist(name: name leer ? host ?? "Playlist" : name, sourceURL: url, lastRefreshed: now) → insert
          ├── attach(parsed, preservedFavorites: [])   je Eintrag Channel(…, playlist:, playlistID:) → insert → channels.append
          │                                            channelCount = channels.count        ⚠ quadratisch (FB-04)
          └── modelContext.save()
  ├── Erfolg → dismiss()
  └── Fehler → errorMessage → Alert                ⚠ auch wenn das Sheet schon geschlossen ist (FB-08)

Aufrufkette Datei
ImportPlaylistView.importFromFile(url)             name.isEmpty ? nil : name
  └── PlaylistImporter.importFromFile(url, name)
      ├── startAccessingSecurityScopedResource() … defer stop (falls true)
      ├── Data(contentsOf:)                        synchron auf dem Main-Actor; Fehler → ImportError.fileAccessDenied
      ├── decodeText → M3UParser.parse → leer → emptyPlaylist
      ├── Playlist(name: name ?? Dateiname ohne letzte Endung)   sourceURL nil, lastRefreshed nil
      ├── attach(parsed, preservedFavorites: [])
      └── modelContext.save()

M3UParser.parse(text)                              reine Funktion, kein Zustand außer „pending"
  ├── text.split(whereSeparator: \.isNewline)      Character.isNewline: LF, CR, CRLF, VT, FF, U+0085, U+2028, U+2029
  ├── Zeile trim .whitespaces, leer → weiter
  ├── hasPrefix("#EXTINF:") → pending = parseExtInf(Zeile)
  │   ├── firstUnquotedComma: Zähler für "…" → Name = Rest, getrimmt
  │   └── keyValueAttributes(vor dem Komma): key = Buchstaben/Ziffern/-/_ · optional Leerzeichen · = · "Wert"
  │       tvg-id | tvg-logo | group-title (lowercased), leer → nil, letzter gewinnt
  ├── hasPrefix("#") → ignorieren; "#EXTGRP:" setzt Gruppe, wenn pending ohne Gruppe
  └── sonst Adresszeile: ohne pending → verwerfen; pending verbrauchen;
      URL(string:) mit scheme != nil        ⚠ jedes Schema (FB-05)
      → ParsedChannel(name leer ? lastPathComponent : name, url, URL(string: logo), group, tvgID)

Öffnen aus dem System (macOS)
LaunchServices → Apple Event „open documents" → SwiftUI-App ohne Handler
  └── WindowGroup erzeugt ein neues Fenster ContentView  ⚠ kein Import, keine Meldung (FB-06)
```

### Beteiligte Typen

| Typ | Datei | Rolle in B02 |
|---|---|---|
| `ImportPlaylistView` | `Views/ImportPlaylistView.swift` | Formular, Zustand (`source`, `urlString`, `name`, `isImporting`, `showingFileImporter`, `errorMessage`), erlaubte Dateitypen (`:36-42`), Start der Importe (`:192-224`), Alert |
| `PlaylistImporter` | `Services/PlaylistImporter.swift` | `importFromURL` (`:50-68`), `importFromFile` (`:190-214`), `attach` (`:284-305`), `fetchText` (`:307-321`), `decodeText` (`:324-328`); `ImportError` (`:4-18`) |
| `M3UParser`, `ParsedChannel` | `Services/M3UParser.swift` | Parser (`:22-155`), DTO gemeinsam mit B01 (`:6-12`) |
| `Playlist`, `Channel` | `Models/` | Persistenz, siehe unten |
| `CFBundleDocumentTypes` | `Resources/Info.plist:68-82` | Registrierung als Öffner, ohne Gegenstück im Code |
| `StreamURLResolver` | `Services/StreamURLResolver.swift:25` | (B01) reicht M3U-Adressen unverändert durch |
| `AppPersistence` | `Services/AppPersistence.swift` | (B01) Speicherort; Umstellung nur `isXtream` (`:131`); einmaliges Cache-Leeren (`:221-226`) |

## Datenmodell

Aus `docs/datenmodell.md`, beschränkt auf das, was B02 schreibt. B02 führt **keine** neuen Felder ein
und ändert das Schema nicht. Eine Migration ist nicht nötig; es gilt der app-weite Stand ohne
`VersionedSchema` (DM-04).

### Entität `Playlist` (Tabelle `ZPLAYLIST`)

| Feld | Typ | Pflicht | URL-Import | Datei-Import |
|---|---|---|---|---|
| `id` | `UUID` | ja | `UUID()` | `UUID()` |
| `name` | `String` | ja | Eingabe unverändert; leer → `url.host`, ohne Host „Playlist" | Eingabe unverändert; leer → Dateiname ohne letzte Endung |
| `sourceURL` | `URL?` | nein | ⚠ gekürzte Eingabe **unverändert**, einschließlich Query, Benutzerinfo, Fragment; bei `data:` der ganze Inhalt (FB-01, OF-02) | `nil` |
| `createdAt` | `Date` | ja | Anlagezeitpunkt | Anlagezeitpunkt |
| `lastRefreshed` | `Date?` | nein | Zeitpunkt des Imports | `nil` |
| `isXtream` | `Bool` | ja | `false` | `false` |
| `xtreamOutput` | `String?` | nein | `nil` | `nil` |
| `channelCount` | `Int` | ja | Anzahl nach `attach` | Anzahl nach `attach` |
| `channels` | `[Channel]` | — | alle Sender, `cascade` | alle Sender, `cascade` |

Abgeleitet: `isRemote` = `sourceURL != nil` → Globus-Symbol und „Aktualisieren" (B03), auch bei `file:`
und `data:` aus dem URL-Feld.

### Entität `Channel` (Tabelle `ZCHANNEL`)

| Feld | Typ | Pflicht | Was B02 hineinschreibt |
|---|---|---|---|
| `id` | `UUID` | ja | `UUID()` |
| `name` | `String` | ja | Text nach dem ersten Komma außerhalb von `"…"`, getrimmt; leer → letzter Pfadabschnitt der Adresse; **ungekürzt**, Steuerzeichen bleiben (FB-03, EC-06) |
| `streamURL` | `URL` | ja | ⚠ Adresszeile unverändert, jedes Schema (FB-05), Zugangsdaten im Klartext, falls enthalten (FB-01) |
| `logoURL` | `URL?` | nein | `URL(string: tvg-logo)`, jedes Schema, auch relativ; ungültige Zeichen prozentkodiert |
| `group` | `String?` | nein | `group-title`, ersatzweise erstes nicht-leeres `#EXTGRP`; Rand-Leerzeichen bleiben |
| `tvgID` | `String?` | nein | `tvg-id`, leer → `nil`; Rand-Leerzeichen bleiben |
| `isFavorite` | `Bool` | ja | `false` (beim Import; B03 übergibt gemerkte Favoriten) |
| `playlist` / `playlistID` | `Playlist?` / `UUID?` | nein | die neue Playlist bzw. ihre `id`, je Sender einzeln gesetzt |

Beziehungen: Eine `Playlist` hat viele `Channel`, Löschregel `cascade`.
Indizes: keine zusätzlichen (DM-05); B02 filtert nicht.

### Außerhalb des Schemas gespeichert

| Ort | Inhalt | Entsteht durch |
|---|---|---|
| Datenbank macOS `~/Library/Application Support/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store`, iOS App-Container | die Tabellen oben; nicht vom Backup ausgeschlossen | `AppPersistence.configuration` (B01) |
| `Cache.db`, macOS `~/Library/Caches/lu.daumedia.MikaPlusPlayer/`, iOS `Library/Caches` | ⚠ Anfrage-Adresse samt Query und Antwortkörper jeder M3U-URL, sofern der Server kein `no-store` schickt (FB-02) | `URLSession.shared` / `URLCache.shared` (512 KB Speicher, 20 MB Platte; ausgeführt) |
| Cookie-Speicher der App (`HTTPCookieStorage.shared`) | Cookies, die der Server setzt; beim nächsten Abruf zurückgeschickt | Standardverhalten von `URLSession.shared` (AK-36); Ablage auf der Platte nicht beobachtet |
| iOS `Documents/Inbox` | über „Öffnen in" übergebene Dateien, nie verarbeitet (EC-23) | System, wegen `CFBundleDocumentTypes` *(gelesen)* |
| macOS Fensterzustand (`$TMPDIR/<Bundle-ID>.savedState`) | zusätzliche leere Fenster aus „Öffnen mit" (EC-22) | Fensterwiederherstellung des Systems |

### Nicht persistiert

`ParsedChannel`, der Text der Liste, der Formularzustand des Sheets, die gewählte Datei-Adresse. Die
Datei selbst wird nicht kopiert.

## Zugriffsregeln

Die App hat keine Konten und keine Rollen. Zugriffsregeln greifen nur über das Betriebssystem.

| Wer | Darf lesen | Darf schreiben | Erzwungen durch |
|---|---|---|---|
| Nutzer der App | alle Playlists und Sender; Quelladresse und Stream-Adressen sind in der Oberfläche nicht zu sehen | anlegen (B02), aktualisieren und löschen (B03), nicht ändern | nichts, Einzelnutzer |
| die App selbst (macOS) | jede Datei, die der Benutzer lesen darf, über den Dialog oder eine `file:`-Adresse; jede Adresse jedes Schemas, das `URLSession` kennt | — | **nichts**: App-Sandbox aus (`MikaPlusPlayer.entitlements:7-8`); der Dialog ist nur Bedienung |
| die App selbst (iOS) | nur über den Dateien-Dialog gewählte Dateien, mit vorübergehendem Zugriffsrecht | — | iOS-Sandbox und security-scoped URL *(gelesen)* |
| andere Prozesse desselben macOS-Benutzers | ⚠ Datenbank, `Cache.db`, Cookies samt Zugangsdaten aus M3U-Links | dieselben Dateien | nichts: Sandbox aus, kein Schlüsselbund für M3U (FB-01) |
| andere Apps unter iOS | nichts | nichts | iOS-App-Sandbox |
| Backup (Time Machine, iCloud- oder Geräte-Backup) | ⚠ Datenbank samt M3U-Zugangsdaten | — | bewusst kein `isExcludedFromBackup` (B01-Annahme 7), für M3U nicht zutreffend (FB-01) |
| Mitleser im Netz | ⚠ vollständige Adresse samt Query bei `http://` | — | nichts: ATS global aus (`Info.plist:37-41`); kein Hinweis im URL-Reiter (OF-05) |
| Server der URL bzw. Weiterleitungsziel | Adresse, IP, Kopfzeilen (App-Name, Build, System, Sprache), Cookies, Basic-Auth bei Anforderung | Cookies | protokollbedingt; Basic-Auth nicht an fremde Weiterleitungsziele (ausgeführt) |
| Absender einer Playlist | legt Stream- und Logo-Adressen fest, die B04/B06 später öffnen | — | ⚠ nichts: keine Schema-Prüfung (FB-05) |

## Missbrauchsschutz

| Stelle | Limit | Verhalten bei Überschreitung | Wo konfiguriert |
|---|---|---|---|
| „Von URL importieren", „Datei auswählen" | deaktiviert während eines Imports | ⚠ `isImporting` wird erst in der Aufgabe gesetzt: zwei Klicks im selben Durchlauf starten zwei Importe (FB-09) | `ImportPlaylistView.swift:110, 119, 193, 215` |
| „Abbrechen" | **keins** für URL/Datei | Sheet schließt, Import läuft weiter, späterer Fehler im losgelösten Fenster (FB-08) | `ImportPlaylistView.swift:133-136` |
| Größe der Antwort bzw. Datei | **keins** | alles wird in den Speicher geladen (FB-03) | — |
| Anzahl Sender, Länge von Name, Gruppe, Adressen | **keins** | alles wird angelegt und gespeichert (FB-03) | — |
| Leerlauf je Abruf | 60 s ohne Daten | „Netzwerkfehler: The request timed out." | Standard von `URLRequest` |
| Gesamtdauer des Abrufs | **keins** | langsames Senden hält den Import offen (FB-03) | — |
| Dauer von Parsen und Anlegen | **keins**, auf dem Main-Actor | Oberfläche steht still, 17.000 Sender 286,6 s (FB-04) | `PlaylistImporter.swift:22` |
| Weiterleitungen | 20, danach Fehler | „Netzwerkfehler: too many HTTP redirects" | Standard von `URLSession` |
| Schemata in Stream- und Logo-Adressen | **keins**, nur „hat ein Schema" | alles wird übernommen (FB-05) | `M3UParser.swift:48, 53` |
| Dateitypen im Dialog | M3U-Playlist und alles, was `public.plain-text` entspricht | andere Dateien sind im Dialog ausgegraut | `ImportPlaylistView.swift:36-42` |

## Externe Dienste

| Dienst | Wofür | Was geht hin | Was wird vorher entfernt |
|---|---|---|---|
| Server der eingegebenen URL | Abruf der Liste (GET) | ⚠ vollständige Adresse samt Query mit etwaigen Zugangsdaten, auch über `http://`; IP-Adresse; `User-Agent: Mika+Player/<Build> CFNetwork/… Darwin/…`, `Accept-Language` mit Systemsprache, `Accept`, `Accept-Encoding`; gespeicherte Cookies des Hosts; bei 401 Basic-Auth aus der Benutzerinfo | nur das Fragment; sonst nichts |
| Ziel einer Weiterleitung | wie oben | genau die Adresse aus `Location`, Kopfzeilen, Cookies des Ziel-Hosts; **keine** Basic-Auth des ursprünglichen Hosts | — |
| Logo-Hosts aus `tvg-logo` | in B02 nur gespeichert, geladen in B04 | in B02 nichts | — |
| Stream-Hosts aus den Adresszeilen | in B02 nur gespeichert, abgerufen in B06/B08 | in B02 nichts | — |

Kein KI-Dienst, keine Analyse, kein Fehler-Tracking, kein Server von daumedia.

## Erkennbare Entscheidungen

| # | Entscheidung | Alternative | Warum so |
|---|---|---|---|
| 1 | Anzeigename = Text nach dem ersten Komma **außerhalb** von Anführungszeichen | erstes Komma überhaupt; letztes Komma | Kommentar `M3UParser.swift:14-21`, CLAUDE.md, README, Test `testQuoteSafeNameWithCommas`: Anbieter schreiben Kommas in `group-title` und Namen |
| 2 | Parser als reine Funktion mit DTO `ParsedChannel` | Parser legt `Channel` direkt an | Kommentar `M3UParser.swift:3-5`: testbar ohne `ModelContext`; gemeinsam mit B01 |
| 3 | Nur `tvg-id`, `tvg-logo`, `group-title`, `#EXTGRP` | `tvg-name`, `#EXTVLCOPT`, `url-tvg` | Grund nicht erkennbar; `tvg-id` dient nur als Favoriten-Schlüssel (B05) (OF-09) |
| 4 | UTF-8 mit Latin-1-Fallback, `charset` der Antwort ignoriert | Kodierung aus Kopfzeile/BOM, UTF-16, Windows-1252, zeilenweise Erkennung | Kommentar `PlaylistImporter.swift:323`; weiter nicht begründet (OF-06) |
| 5 | Adresszeile nur mit Schema, sonst verworfen; jedes Schema erlaubt | relative Adressen auflösen; Allowlist `http`, `https` (+ ggf. `rtsp`, `udp`) | Test `testSkipsInvalidURL` hält das Verwerfen fest; eine Allowlist ist nicht erkennbar erwogen (FB-05, OF-04) |
| 6 | Abruf über `URLSession.shared` mit `.reloadIgnoringLocalCacheData` | eigene `ephemeral`-Session ohne Cache und Cookies, mit Größen- und Gesamtgrenze, wie B01 sie für Xtream gebaut hat | Grund nicht erkennbar; dass die Policy das Schreiben in den Cache nicht verhindert, wurde offenbar nicht bedacht (FB-02, FB-03) |
| 7 | ⚠ Parsen, Anlegen und Speichern auf dem Main-Actor, Beziehung je Sender | eigener `ModelContext` im Hintergrund, Beziehung blockweise (B01 BUG-12) | Kommentar `PlaylistImporter.swift:20-21`: „läuft auf dem MainActor, da SwiftData-Objekte hier erzeugt/verändert werden". Die Kosten der Einzelzuweisung sind nicht erkannt (FB-04) |
| 8 | Eingegebene URL unverändert als `sourceURL` | Zugangsdaten abtrennen und in den Schlüsselbund legen, wie B01 für Xtream | Grund nicht erkennbar; vermutlich, damit B03 ohne weiteren Zustand aktualisieren kann (FB-01) |
| 9 | Datei-Playlist ohne `sourceURL`, nicht aktualisierbar | Security-scoped Bookmark speichern und neu einlesen | Kommentar `PlaylistImporter.swift:208` |
| 10 | Dateidialog erlaubt zusätzlich `public.plainText` | nur `.m3u`/`.m3u8` | Grund nicht erkennbar; vermutlich für Listen, die als `.txt` ausgeliefert werden |
| 11 | ⚠ `CFBundleDocumentTypes` mit `public.m3u-playlist` **und** `public.text`, Rang `Default`, ohne Handler | `onOpenURL`/`handlesExternalEvents` mit Import; nur `public.m3u-playlist`; Rang `Alternate`; Registrierung weglassen | Kommentar `Info.plist:68` „Importierbare Dokumenttypen"; der Handler wurde nie gebaut (FB-06, FB-07) |
| 12 | ⚠ Ungebundene `Task` für URL- und Datei-Import | gebundene, abbrechbare Aufgabe wie seit B01 für Xtream | Grund nicht erkennbar; B01 hat den Xtream-Zweig umgestellt, diese beiden nicht (FB-08, FB-09) |
| 13 | Button-Sperre nur bei leerem Feld (`isEmpty`) | getrimmte Prüfung wie `XtreamCredentials.isComplete` | Grund nicht erkennbar; die Meldung „Die angegebene URL ist ungültig." fängt den Fall ab |
| 14 | Fehler als Alert mit `localizedDescription`, Systemtexte ungefiltert | eigene deutsche Meldungen je Fehlerart | Grund nicht erkennbar (OF-08) |
| 15 | Name ohne Eingabe = Host bzw. Dateiname, Eingabe ungekürzt | Name aus `#PLAYLIST:`/`#EXTM3U`-Attribut, Eingabe trimmen | Grund nicht erkennbar; gleich wie bei Xtream (B01 Entscheidung 15) |
| 16 | Keine Dublettenprüfung beim Import | vorhandene Playlist mit gleicher `sourceURL` aktualisieren | Grund nicht erkennbar (OF-01) |

## Abdeckung der Akzeptanzkriterien

Umgedreht: Was erfüllt das Kriterium heute?

| AK | Erfüllt durch | Anmerkung |
|---|---|---|
| AK-01 | `ImportPlaylistView.swift:47-50, 52-54, 97-121` | Name-Feld gemeinsam für alle Reiter; `urlString` bleibt als `@State` beim Reiterwechsel |
| AK-02 | `ImportPlaylistView.swift:99-104` | |
| AK-03 | `ImportPlaylistView.swift:110, 119` | `isEmpty` ohne Trim |
| AK-04 | `ImportPlaylistView.swift:110, 119, 123-128, 193-194, 215-216` | „Abbrechen" ohne `disabled` |
| AK-05 | `ImportPlaylistView.swift:36-42, 139-145`; `UTType` `public.m3u-playlist` (Endungen `m3u`, `m3u8`) ⊂ `public.plain-text` | beide Endungen ergeben denselben Typ, der erste Eintrag der Liste ist doppelt |
| AK-06 | `ImportPlaylistView.swift:192-202`; `PlaylistImporter.swift:50-68`; Anzeige `PlaylistsView.swift:8, 128, 137` | |
| AK-07 | `PlaylistImporter.swift:62` | `url.host` ohne Port |
| AK-08 | `PlaylistImporter.swift:51-53, 63, 309-311` | Prozentkodierung durch `URL(string:)` des Systems (macOS 27; ältere Systeme liefern bei Leerzeichen `nil`, nicht geprüft) |
| AK-09 | `PlaylistImporter.swift:311-315` | Antwort-Kopfzeilen außer Status werden nicht ausgewertet |
| AK-10 | `PlaylistImporter.swift:312-314, 60` | |
| AK-11 | `URLSession.shared` ohne Delegate: Standard folgt Weiterleitungen | kein App-Code |
| AK-12 | `PlaylistImporter.swift:51-54, 318-320` | Texte aus `URLError` |
| AK-13 | `PlaylistImporter.swift:51-53` (nur `scheme != nil`), `URLSession` kann `file:` und `data:` | ⚠ OF-02 |
| AK-14 | `URLSession.shared` mit Standard-Authentifizierung aus der Benutzerinfo | kein App-Code |
| AK-15 | `PlaylistImporter.swift:50-68`, keine Prüfung auf Vorhandenes | ⚠ OF-01 |
| AK-16 | `PlaylistImporter.swift:190-214`, v. a. `:207-209`; `PlaylistsView.swift:40-46, 128` | |
| AK-17 | `PlaylistImporter.swift:199-205` (kein Typ-Check nach dem Dialog) | |
| AK-18 | `PlaylistImporter.swift:197-202` | alle Lesefehler auf eine Meldung abgebildet |
| AK-19 | `PlaylistImporter.swift:194-195` | nur iOS wirksam |
| AK-20 | `M3UParser.swift:29-48` | |
| AK-21 | `M3UParser.swift:51, 73-107` | Tests `testQuoteSafeNameWithCommas`, `testMinimalEntry` |
| AK-22 | `M3UParser.swift:110-154` | |
| AK-23 | `M3UParser.swift:36-42` | Test `testExtGrpFallback` |
| AK-24 | `M3UParser.swift:29` | `Character.isNewline` |
| AK-25 | `PlaylistImporter.swift:324-328` | |
| AK-26 | `PlaylistImporter.swift:60, 205`; `M3UParser.swift:46-48` | Test `testSkipsInvalidURL` |
| AK-27 | `ImportPlaylistView.swift:146-150, 199-201, 221-223` | |
| AK-28 | `PlaylistImporter.swift:318-320`; Timeout-Standard von `URLRequest` | |
| AK-29 | `ImportPlaylistView.swift:106, 133-136, 154, 192-202, 208, 214-224` | ⚠ FB-08 |
| AK-30 | `ImportPlaylistView.swift:106, 110, 193` | ⚠ FB-09 |
| AK-31 | `Info.plist:68-82`; `MikaPlusPlayerApp.swift:29-35` (`WindowGroup` ohne `handlesExternalEvents`); kein `onOpenURL` in `Sources/` | ⚠ FB-06 |
| AK-32 | `Info.plist:74-80` | ⚠ FB-07 |
| AK-33 | `PlaylistImporter.swift:12-15, 313, 319` (eigene Texte ohne Adresse; `URLError.localizedDescription` ohne Adresse) | für die geprüften Fehlerarten belegt |
| AK-34 | `PlaylistImporter.swift:63, 289-298`; `StreamURLResolver.swift:25`; `AppPersistence.swift:16-17, 131` | ⚠ FB-01 |
| AK-35 | `PlaylistImporter.swift:309-311` (`URLSession.shared`) | ⚠ FB-02 |
| AK-36 | `URLSession.shared` (Standard-Kopfzeilen, `HTTPCookieStorage.shared`) | kein App-Code; `User-Agent` aus `CFBundleName` und `CFBundleVersion` |
| AK-37 | `PlaylistImporter.swift:199, 311`; `M3UParser.swift` ohne Kürzung | ⚠ FB-03 |
| AK-38 | `URLRequest.timeoutInterval` Standard 60 s, keine Gesamtfrist | ⚠ FB-03 |
| AK-39 | `M3UParser.swift:48, 53` | ⚠ FB-05 |
| AK-40 | `PlaylistImporter.swift:22, 58-66, 199-212, 289-304` | ⚠ FB-04 |
| AK-41 | Fehlen jedes Logging-Aufrufs in `Sources/`; Protokoll von CFNetwork | |
| AK-42 | Löschweg B03 (`PlaylistImporter.delete`, `PlaylistsView.swift:104-107`), SQLite-Checkpoint beim Schließen | gehört zu B03, hier nur für den Katalog |
| AK-43 | Repository-Historie | kein Code, Zustand des Repos |

### Code ohne AK-Zuordnung

Hinweise auf toten Code oder auf Verhalten, das einem anderen Feature gehört:

- **`PlaylistImporter.isWorking`** (`PlaylistImporter.swift:32, 55-56, 191-192`): wird gesetzt, aber vom
  Sheet nicht beobachtet, weil jeder Aufruf eine eigene Instanz erzeugt (wie B01).
- **`handleFileResult`, Zweig `.failure`** (`ImportPlaylistView.swift:209-210`): zeigt den Systemtext,
  wenn der Dateidialog selbst scheitert. Nicht ausgeführt, weil der Dialog nicht geöffnet wurde.
- **`handleFileResult`, `urls.first` leer** (`:207`): stiller Abbruch; bei `allowsMultipleSelection:
  false` praktisch unerreichbar.
- **Doppelter Eintrag in `allowedTypes`** (`:38-39`): `m3u` und `m3u8` ergeben denselben Typ
  `public.m3u-playlist` (ausgeführt), ohne Folge.
- **`ParsedChannel: Equatable`** (`M3UParser.swift:6`): im App-Code nicht verglichen.
- **`refresh`, Zweig M3U** (`PlaylistImporter.swift:246-249`): gehört zu B03, nutzt `fetchText` und
  Parser aus B02.
- **`ImportError.invalidURL`** wird nur von `importFromURL` geworfen, nicht beim Datei-Import.

### Bestehende Tests

`Tests/M3UParserTests.swift`, 4 Tests, nur macOS-Target:

| Test | Prüft | Deckt |
|---|---|---|
| `testQuoteSafeNameWithCommas` | Name mit Komma, Komma in `group-title`, `tvg-id`, `tvg-logo`, Adresse | AK-21, AK-22 |
| `testMinimalEntry` | `#EXTINF` ohne Attribute | AK-20, AK-21 |
| `testSkipsInvalidURL` | ungültige Adresszeile wird übersprungen, der nächste Eintrag bleibt | AK-26, EC-03 |
| `testExtGrpFallback` | `#EXTGRP` ohne `group-title` | AK-23 |

Ohne Test: `importFromURL`, `importFromFile`, `fetchText`, `decodeText` (Kodierung), Zeilenenden,
unbalancierte Anführungszeichen, Schemata, die Oberfläche beider Reiter, `CFBundleDocumentTypes`,
Laufzeit großer Listen. Seit der B01-Reparatur läuft der Test-Host mit In-Memory-Datenbank; die
Parser-Tests brauchen keine.
