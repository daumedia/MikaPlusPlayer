# MikaPlusPlayer

Ein IPTV-Player als **SwiftUI-Multiplatform-App** (iOS 17+ / macOS 14+, ein gemeinsames
Codebase). Importiert M3U/M3U8-Playlists per URL oder lokaler Datei, zeigt Sender mit
Suche, Gruppen-Filtern und Logos, verwaltet Favoriten über alle Playlists hinweg und
spielt Streams mit AVKit – oder optional VLCKit für rohe MPEG-TS-Streams (`.ts`).

## Features

- **Xtream-Codes-Login** (Host / Benutzername / Passwort) mit Format-Wahl **HLS** oder
  **MPEG-TS**. Senderliste wird direkt über `player_api.php` aufgebaut (robust auch dann,
  wenn der klassische `get.php`-M3U-Link blockiert ist).
- **Import** von M3U/M3U8-Playlists per **URL** oder **lokaler Datei** (`.m3u`/`.m3u8`).
- **Parser** liest `#EXTINF`-Attribute `tvg-id`, `tvg-logo`, `group-title`. Der Anzeigename
  ist der Text nach dem **ersten Komma außerhalb von Anführungszeichen** (quote-sicher).
- **Senderliste** mit Suche (`.searchable`) und horizontalen **Gruppen-Filter-Chips**,
  Logos via `AsyncImage`.
- **Favoriten** (Stern) als eigener Tab über alle Playlists (SwiftData `#Predicate`).
- **Remote-Playlists refreshen**; Favoriten bleiben dabei über `tvg-id`/Name erhalten.
- **Wiedergabe** mit `AVKit.VideoPlayer`, Status-Observer und Fehler-Fallback-View.

## Architektur

```
Sources/
  App/        MikaPlusPlayerApp (Entry + ModelContainer), ContentView (TabView)
  Models/     Playlist, Channel  (SwiftData @Model)
  Services/   M3UParser, PlaylistImporter, PlaybackEngine(+AVKit/+VLC)
  Views/      Playlists / Import / ChannelList / ChannelRow / Favorites / Player
  Resources/  Info.plist, MikaPlusPlayer.entitlements
```

Sauber getrennt in **App / Models / Services / Views**. Die Wiedergabe ist hinter dem
Protokoll `PlaybackEngine` gekapselt, sodass sich Engines (AVKit ↔ VLCKit) austauschen
lassen, ohne den restlichen Code anzufassen.

## Setup mit XcodeGen (empfohlen)

Das Repository enthält bewusst **kein** `.xcodeproj` – es wird aus `project.yml` generiert.

```sh
brew install xcodegen      # einmalig
cd MikaPlusPlayer
xcodegen generate          # erzeugt MikaPlusPlayer.xcodeproj
open MikaPlusPlayer.xcodeproj
```

In Xcode oben das passende **Schema** wählen und ⌘R:
- **`MikaPlusPlayer`** → iOS (Simulator/Gerät)
- **`MikaPlusPlayer-macOS`** → „My Mac" (enthält den Sparkle-Updater + Tests)

> **Struktur:** iOS und macOS sind **zwei schlanke Targets**, die sich **dasselbe Codebase
> (`Sources/`) teilen**. Grund: Der Sparkle-Auto-Updater ist macOS-only und lässt sich in
> einem einzelnen `supportedDestinations`-Target nicht sauber nur für macOS linken. Beide
> Targets erzeugen `MikaPlusPlayer.app`.

> **Voraussetzung für die Kommandozeile:** `xcodebuild` benötigt das vollständige Xcode.
> Falls `xcode-select -p` auf `/Library/Developer/CommandLineTools` zeigt, entweder einmalig
> `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` setzen oder pro Aufruf
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild …` voranstellen.

### Code-Signing

- **macOS** (`MikaPlusPlayer-macOS`), `CODE_SIGN_STYLE = Manual`, Team `CWJM4J4HFN`:
  - **Debug**: „Sign to Run Locally" (`CODE_SIGN_IDENTITY = "-"`) → läuft **ohne** Zertifikat. Eigene
    Bundle-ID **`lu.daumedia.MikaPlusPlayer.debug`** (auch für den Test-Host): Datenbank, Einstellungen,
    Sparkle-Zustand und Schlüsselbund-Einträge der installierten App bleiben unberührt; Sparkle startet in Debug
    ohne automatische Prüfung, im Test-Host gar nicht.
  - **Release**: **Developer ID Application**, Hardened Runtime, ohne `get-task-allow`
    (`ENABLE_HARDENED_RUNTIME = YES`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`), Bundle-ID
    `lu.daumedia.MikaPlusPlayer`. Verteilt wird über Archivieren und Exportieren (`scripts/release.sh`). Ein
    ad-hoc-signierter Release-Build startet nicht mehr (ohne `disable-library-validation` lehnt die Hardened
    Runtime VLCKit ohne gleiche Team-ID ab); Release-Läufe zum Messen daher mit Developer ID oder als Kopie mit
    eigener Bundle-ID ohne Hardened Runtime.
- **iOS** (`MikaPlusPlayer`): `CODE_SIGN_STYLE = Automatic` mit hinterlegtem
  `DEVELOPMENT_TEAM` (in `project.yml`). Simulator läuft ohnehin team-frei.

> **Echtes iPhone/iPad:** Mit gesetztem Team erzeugt Xcode das Provisioning-Profil automatisch,
> sobald das Gerät angeschlossen und in Xcode bestätigt ist (bei persönlichem Team einmal das
> Gerät registrieren). Anderes Team? `DEVELOPMENT_TEAM` in `project.yml` ändern und neu generieren.

### Tests

Ein Unit-Test-Target (`MikaPlusPlayerTests`, macOS, gehostet von der Debug-App mit eigener Bundle-ID) deckt
Parser, Dienste und Oberfläche ab. Die Testaktion startet den Test-Host mit „Fensterzustand ignorieren“ und der
Umgebungsmarke `MIKA_TEST_HOST=1`:

```sh
xcodebuild test -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

### Alternativ: Projekt manuell in Xcode anlegen

1. **File → New → Project → Multiplatform → App**. Name `MikaPlusPlayer`,
   Interface **SwiftUI**, Storage **SwiftData**.
2. Den vorgenerierten `ContentView`/`App`-Stub löschen und den Ordner `Sources/`
   (App/Models/Services/Views) per Drag & Drop hinzufügen („Create groups").
3. **Deployment Targets** auf iOS 17.0 / macOS 14.0 setzen.
4. `Sources/Resources/Info.plist` als **Info.plist-Datei** des Targets eintragen
   (Build Setting `INFOPLIST_FILE`) **oder** die unten genannten Keys in die von Xcode
   generierte Info.plist übernehmen.
5. Für macOS: `Sources/Resources/MikaPlusPlayer.entitlements` als
   `CODE_SIGN_ENTITLEMENTS` der Mac-Variante setzen.

## App Transport Security (ATS)

IPTV-Streams laufen häufig über **unverschlüsseltes HTTP**. Damit iOS/macOS solche
Verbindungen zulässt, ist in `Info.plist` gesetzt:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

> Für eine App-Store-Einreichung empfiehlt Apple, statt `NSAllowsArbitraryLoads`
> gezielte `NSExceptionDomains` zu pflegen.

## macOS App Sandbox & Entitlements

Da die macOS-App **per DMG** (nicht über den App Store) verteilt wird und den **Sparkle-Updater**
nutzt, ist die **App-Sandbox deaktiviert** – wie bei den anderen Mika+ Apps. Datei
`Sources/Resources/MikaPlusPlayer.entitlements`:

| Entitlement | Wert | Zweck |
|---|---|---|
| `com.apple.security.app-sandbox` | `false` | keine Sandbox (DMG-Distribution + Sparkle) |

Seit dem Wechsel auf Developer ID (B09, 2026-10-02) entfällt `com.apple.security.cs.disable-library-validation`:
Der Export signiert VLCKit und Sparkle mit derselben Team-ID wie die App, die Library Validation der Hardened
Runtime lässt sie damit zu.

> Ohne Sandbox hat die App vollen Netzwerk-/Dateizugriff; die früheren
> `network.client`/`files.user-selected.read-only`-Einträge sind dann nicht mehr nötig.
> Für eine App-Store-Variante müsste die Sandbox wieder aktiviert und Sparkle entfernt werden.

## Wiedergabe & der Wechsel AVPlayer → VLCKit (für `.ts`-Streams)

**Wichtig:** `AVPlayer` kann **nur HLS** (`.m3u8`) und gängige Container – **keine rohen
MPEG-TS-Streams** (`.ts`). Für `.ts` wird **VLCKit** benötigt.

Die Auswahl erfolgt automatisch in `PlaybackEngineFactory.engine(for:)`:

- `.m3u8` / sonstige → `AVKitPlaybackEngine`
- `.ts` / `.mpegts` / … → `VLCPlaybackEngine` (falls VLCKit eingebunden), sonst Fallback AVKit

### VLCKit (SwiftPM-Binärpaket – bereits eingebunden)

VLCKit ist als **SwiftPM-Binärpaket** in `project.yml` verdrahtet:

```yaml
packages:
  VLCKitSPM:
    url: https://github.com/tylerjonesio/vlckit-spm
    exactVersion: "3.6.0"
# … unter dem App-Target:
dependencies:
  - package: VLCKitSPM
    product: VLCKitSPM
```

- Liefert ein **xcframework für iOS + macOS + tvOS** – ein Paket für beide Plattformen.
- **Importname im Code: `import VLCKitSPM`** (re-exportiert `VLCMediaPlayer`, `VLCMedia`, …).
- Beim ersten Build lädt Xcode ein großes Binary (mehrere hundert MB) – das dauert.
- Der VLC-Code steht hinter
  `#if canImport(VLCKitSPM) || canImport(MobileVLCKit) || canImport(VLCKit)` – entfernt man
  das Paket wieder, **baut die App weiterhin** und fällt auf AVKit zurück.

> **Hinweis iOS-Simulator (Apple Silicon):** Manche VLCKit-Binärbuilds enthalten keine
> arm64-Simulator-Slice. Falls der Simulator-Build deshalb fehlschlägt, auf einem echten
> iOS-Gerät oder unter macOS testen.

### Alternative: CocoaPods

Statt SPM lässt sich VLCKit auch via CocoaPods einbinden (`pod 'MobileVLCKit'` für iOS bzw.
`pod 'VLCKit'` für macOS, dann `.xcworkspace` öffnen). Die `canImport`-Guards greifen auch
dann automatisch – kein Code-Change nötig.

### Ohne VLCKit

Entfernt man `VLCKitSPM` aus `project.yml`, baut die App weiterhin und spielt HLS/`.m3u8`
über AVKit. Rohe `.ts`-Streams zeigen dann den Fehler-Fallback mit Hinweis auf VLCKit.

### Eine eigene Engine einhängen

1. Neue Klasse erstellen, die `PlaybackEngine` implementiert
   (`state`, `load`, `play`, `pause`, `makePlayerView`).
2. In `PlaybackEngineFactory.engine(for:)` für den gewünschten `StreamType` zurückgeben.

Kein anderer Teil der App muss angefasst werden – Views sprechen nur `any PlaybackEngine` an.

## Xtream-Codes-Zugang nutzen

Im Import-Sheet den Reiter **Xtream** wählen und Host, Benutzername, Passwort eingeben
(Host mit/ohne `http://` und Port, z. B. `dein-anbieter.tld`). Format **HLS** oder **MPEG-TS**
wählen, dann *Anmelden & importieren*. Die App lädt Kategorien + Live-Sender über
`player_api.php` und legt eine refreshbare Playlist an.

> **Wichtig zur Formatwahl:** Viele Panels blockieren den **HLS**-Endpunkt
> (`/live/…/<id>.m3u8` → HTTP 407) und liefern nur **rohes MPEG-TS** (`.ts`). Da AVPlayer
> kein rohes TS kann, ist für solche Anbieter **VLCKit nötig** (ist eingebunden, siehe oben).
> Deshalb ist **MPEG-TS** der Standard. Falls dein Anbieter funktionierendes HLS bietet,
> kannst du auf HLS umstellen und ohne VLCKit auskommen.

Implementierung: `Services/XtreamCodes.swift` (Credentials/URL-Bau) und
`Services/XtreamClient.swift` (player_api → `ParsedChannel`). Benutzername und Passwort liegen
im Schlüsselbund (`Services/XtreamCredentialStore.swift`), nicht in der Datenbank; abspielbare
Stream-Adressen bildet erst `Services/StreamURLResolver.swift` beim Abspielen. Ein eingegebenes
`https://` bleibt erhalten, ohne Schema wird `http://` verwendet.

## Release & Auto-Update (Sparkle + DMG)

Die macOS-App enthält den **Sparkle-Auto-Updater** (wie die anderen Mika+ Apps) und wird als signiertes,
notarisiertes **DMG** verteilt. Im App-Menü direkt nach „Über Mika+Player“: **„Nach Updates suchen …“**
(manuelle Prüfung), **„Automatisch nach Updates suchen“** und **„Updates automatisch installieren“** (Schalter
für Sparkles eigene Einstellungen; der zweite ist ausgegraut, solange die automatische Prüfung aus ist).

**Konfiguration:**
- `Info.plist`: `SUFeedURL` (appcast im Repo) + `SUPublicEDKey` (familienweiter EdDSA-Public-Key) +
  `SUVerifyUpdateBeforeExtraction` (EdDSA-Signatur des DMG wird **vor** dem Einhängen geprüft) +
  `SURequireSignedFeed` (ab 1.2: nur ein signierter Feed wird angenommen; Sparkles Notweg nach 20 Tagen
  durchgehend falsch signierter Feeds bleibt). `SUEnableAutomaticChecks` kommt aus der Build-Einstellung
  `MIKA_SPARKLE_AUTOMATIC_CHECKS` (Release `YES`, macOS-Debug `NO`).
- Sprache: Entwicklungssprache `de` (`project.yml`) und `CFBundleLocalizations [de]`. Sparkle-Fenster und
  Systemmenüs erscheinen deutsch, auch System-Fehlertexte (iOS und macOS).
- Sparkle ist nur am **macOS-Target** als SPM-Dependency, exakt gepinnt auf **2.9.3** (`project.yml`).
  Der Updater-Code (`Services/SparkleUpdater.swift`, `Views/UpdateMenu.swift`) ist mit `#if os(macOS)` gekapselt.
- `appcast.xml` ist für Git unveränderlich (`.gitattributes`: keine Zeilenende-Umwandlung), sonst passt die
  Feed-Signatur nicht mehr.

**Privater Signaturschlüssel:** liegt in der macOS-Keychain (einmalig via Sparkles
`generate_keys` erzeugt; hier bereits vorhanden und familienweit geteilt). Niemals committen.

### Release bauen

Voraussetzungen auf dem Release-Rechner: Zertifikat **Developer ID Application** (Team `CWJM4J4HFN`) und ein
notarytool-Profil im Anmelde-Schlüsselbund (einmalig
`xcrun notarytool store-credentials "<Profil>" --apple-id … --team-id CWJM4J4HFN`).

```sh
NOTARY_PROFILE=<Profil> bash scripts/release.sh
```

Ablauf (Reihenfolge ist Pflicht, weil jeder Schritt Bytes verändert, die ein späterer signiert):
Gegenprüfung **vor-build** → `scripts/build-macos.sh` (xcodegen, Archivieren, Exportieren mit
`scripts/ExportOptions-DeveloperID.plist`) → Gegenprüfung **nach-build** → `scripts/make-dmg.sh` → DMG mit
Developer ID signieren → notarisieren (Ergebnis „Accepted“ aus der JSON-Ausgabe, Protokoll nach
`dist/notarisierung-v<version>.json`) → heften → Gegenprüfung **nach-heften** → `generate_appcast`
(`--maximum-versions 0`, alle Einträge bleiben) → `sign_update` über den Feed → Gegenprüfung **feed**.

Erzeugt:
- `dist/MikaPlusPlayer-v<version>.dmg` (signiert, notarisiert, geheftet)
- `appcast.xml` (Repo-Root): die **versionierte** `appcast.xml` plus der neue Eintrag, Feed signiert.

Gegenprüfungen (`scripts/b09_release_check.sh`, einzeln aufrufbar):
- **vor-build**: Feed-Adresse, sauberer Feed, alle Download-Adressen unter
  `github.com/daumedia/MikaPlusPlayer/releases/download/`, Build-Nummer größer als die höchste `sparkle:version`,
  Anzeigeversion gesetzt und noch nicht veröffentlicht, Härtung, Feed-Pflicht, Sparkle-Pin, Notar-Profil,
  sauberer Git-Stand.
- **nach-build**: jede Komponente (App, Frameworks, Sparkle-Hilfsprogramme) mit Developer ID, Team, sicherem
  Zeitstempel und – bei Programmen – Hardened Runtime; Entitlements ohne `get-task-allow` und
  `disable-library-validation`; Bundle-ID, Versionen, Schlüssel, Feed-Pflicht und Sprache im Bundle.
- **nach-heften**: App im DMG = geprüftes Bundle, DMG mit Developer ID, Ticket gültig, Gatekeeper nimmt DMG und App an.
- **feed**: Einträge = versionierter Feed + neuer Build, bestehende unverändert, Download-Adressen, Länge,
  EdDSA-Signatur des DMG und des Feeds gegen `SUPublicEDKey` (`scripts/b09_ed25519.swift`).
- **nach-merge**: ausgelieferte Datei an der daumedia- und der alten Mukaarts-Adresse = gemergte Datei
  (wartet bis zu 5½ Minuten auf GitHubs Zwischenspeicher), Signatur gültig.

Jeder `[BEFUND]` bricht ab, bevor `appcast.xml` geändert wird. `PROBEMODUS=1` (nur für Proben und Tests) läuft ohne
Developer ID und Notarisierung und meldet diese Punkte als `[ offen]`; ein solches Ergebnis wird nicht veröffentlicht.

### Veröffentlichen (GitHub Releases)

1. **Pflichtproben** (vorher, Ergebnis in den Build-Bericht): Kurztest der Wiedergabe mit dem echten Anbieter
   (HLS und MPEG-TS, mit Ton); Übergangsprobe 1.1 → neue Version über einen eigenen Test-Feed; Offline-Erststart
   der App aus dem DMG.
2. GitHub-Release **`v<version>`** im Repo anlegen (Standard: `daumedia/MikaPlusPlayer` –
   in `Info.plist`/`scripts/release.sh` anpassbar) und `dist/MikaPlusPlayer-v<version>.dmg` als Asset hochladen.
3. **Danach** `appcast.xml` per Pull Request auf **`main`** bringen (vorher liefe der Download ins Leere).
   `appcast.xml` nicht mehr von Hand ändern – die Feed-Signatur würde ungültig.
4. Nach dem Merge: `bash scripts/b09_release_check.sh nach-merge`.

Version erhöhen (vor dem Release, beides **Pflicht**): `MARKETING_VERSION` **und**
`CURRENT_PROJECT_VERSION` in `project.yml`. Sparkle vergleicht nur `CURRENT_PROJECT_VERSION`
(`CFBundleVersion`); ist sie nicht größer als die höchste `sparkle:version` im Feed, bekommt keine
Installation das Update. Änderung committen, dann `scripts/release.sh`.

## Test einer Playlist

Eine frei verfügbare Demo-Playlist (öffentliche Sender) lässt sich per URL importieren,
z. B. das `iptv-org`-Sammelverzeichnis (`https://iptv-org.github.io/iptv/index.m3u`).
HLS-Einträge (`.m3u8`) spielen über AVKit; `.ts`-Einträge benötigen VLCKit.

## Bekanntes / Grenzen

- `AVPlayer` spielt keine rohen MPEG-TS-Streams – dafür VLCKit (eingebunden, siehe oben).
- Viele Xtream-Panels blockieren `get.php`/HLS – die App nutzt daher `player_api.php`.
- Sehr große Playlists (z. B. 17k Sender): Senderliste ist DB-gestützt (`@Query`) und
  bleibt flüssig; der Import selbst kann einige Sekunden dauern.
- App-Icon liegt unter `Sources/Resources/Assets.xcassets/AppIcon.appiconset` (roter
  Verlauf + weißes Play-Glyph, im Stil der Mika+ Familie). Neu generierbar mit Pillow.
- `NSAllowsArbitraryLoads` ist für die Entwicklung gesetzt; vor Release einschränken.
```
