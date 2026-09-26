# B06 · Wiedergabe — Spezifikation

Status: `rekonstruiert` · Stand: `c01f1cf` + Reparatur B01 (2026-09-16) · Rekonstruktion aus dem Code (sdd-erfassen), erstellt 2026-09-16

> **Rekonstruiert, nicht geplant.** Beschrieben ist, was der Code **tut**, und zwar auf dem Stand `c01f1cf`
> einschließlich der noch nicht committeten Reparatur von B01 (eingefrorene Kopie vom 2026-09-16). Seit dieser
> Reparatur entsteht die abspielbare Adresse im `StreamURLResolver` aus Schlüsselbund und gespeicherter Adresse,
> nicht mehr direkt aus `Channel.streamURL`. Kriterien mit ⚠ beschreiben fragwürdiges Ist-Verhalten. Sie stehen
> bewusst als Kriterium hier, damit `sdd-qa` sie reproduziert. Wo sie als Fehler eingestuft sind, steht ein
> Verweis auf *Fehlbestand*.
>
> **Wie belegt.** Am 2026-09-16 **ausgeführt** in einer Kopie im Scratchpad: eigene Bundle-ID
> `lu.daumedia.MikaPlusPlayer.b06probe`, eigene DerivedData, Datenbank im Speicher bzw. als Temp-Datei, eigener
> Schlüsselbund-Dienst, Sparkle abgeschaltet. Die Streams kamen von einem lokalen Mock (`127.0.0.1:18906`):
> ffmpeg-Testbild **ohne Tonspur** als HLS-VOD, Live-HLS, Live-MPEG-TS in Echtzeit, MP4, dazu 401, 403, 404,
> HTML-Seiten, Hänger, verzögerter Start und Abbruch mitten im Stream. Zugangsdaten sind erfunden
> (`qa-user` / `qa-pass-123`). Vier Wege:
> 1. **macOS-XCTest** gegen beide Engines, mit Zustandsprotokoll, Rohzuständen von VLC und dem Protokoll des Mocks.
> 2. **macOS-App** mit zeitgesteuerter Sonde. Sie öffnet den Player in einem Tab-Stapel und sendet Tasten über
>    `NSApp.sendEvent`. Knopfaktionen löst sie über dieselbe Funktion aus, die der Knopf aufruft. Dazu kommen
>    Fensterbilder, Unified Log und stdout/stderr.
> 3. **macOS-App auf dem echten Navigationsweg** (Playlists → Senderliste → Player → Zurück), bedient über
>    synthetische Mausklicks.
> 4. **iPhone-17-Simulator** (iOS 26.5) für Vollbild und Ausrichtung.
>
> **Ohne Ton.** Kein Stream hatte eine Tonspur. Lautstärke und Stumm sind am Zustand der Engine geprüft
> (`AVPlayer.volume`/`isMuted`, VLC `audio.volume`/`audio.muted`), nicht am Gehör. Unbehandelte Tasten liefen
> gegen einen Wächter, der den Systembeep durch eine Protokollzeile ersetzt.
>
> **Nicht bedient:** echte Klicks, Tipps und Tastendrücke eines Menschen, Mauszeiger am oberen Rand im
> Vollbild, iPad, Hardware-Tastatur unter iOS, Bildschirmsperre, echte Geräte, Wiedergabe mit Ton. Solche
> Kriterien tragen den Vermerk *(gelesen)*. Bild-in-Bild gehört zu **B07** und ist dort belegt.
>
> **Evidenz:** `qa-erfassung/sonde-protokoll.txt` (alle Läufe, Mock-Protokoll, Log-Prüfungen),
> `qa-erfassung/sonde.patch` (Sonden-Code gegen die Kopie), Bilder `qa-erfassung/mac-01…13`,
> `iphone-14…15`. Die Kopie im Scratchpad ist gelöscht.

## Zweck

Wer in der Senderliste oder bei den Favoriten einen Sender antippt, sieht ihn sofort im Player. Die App wählt
dafür selbst die passende Engine. Streams lassen sich per Maus, Touch oder Tastatur pausieren, stummschalten,
leiser und lauter stellen und im Vollbild ansehen. Scheitert die Wiedergabe, soll der Player das anzeigen und
einen neuen Versuch anbieten.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| B04 Senderliste | rekonstruiert | öffnet den Player (Karte → `PlayerView`); ebenso die Favoriten (B05) |
| B01 Xtream-Codes-Login | building | liefert Zugangsdaten im Schlüsselbund und den `StreamURLResolver`; setzt das Standardformat MPEG-TS, damit laufen Xtream-Sender standardmäßig über VLC |
| B02 M3U-Import | bestand | liefert Stream-Adressen unverändert aus fremden Playlists, also beliebige Hosts und Schemata |

Auf B06 bauen auf: B07 (Bild-in-Bild im selben Player, nur AVKit) und B08 (Multiview mit denselben Engines).

## User Stories

- **US-01** · Als Zuschauer möchte ich einen Sender antippen und er soll spielen, ohne dass ich wissen muss,
  ob es HLS oder MPEG-TS ist.
- **US-02** · Als Zuschauer möchte ich pausieren, stummschalten und die Lautstärke ändern, am Mac auch per Tastatur.
- **US-03** · Als Zuschauer möchte ich den Sender im Vollbild sehen und genauso schnell wieder herauskommen.
- **US-04** · Als Zuschauer möchte ich erfahren, wenn ein Sender nicht spielt, und es erneut versuchen können.

## Nicht im Scope

- Bild-in-Bild: Knopf, Taste P als PiP-Funktion, automatischer Start, Schutzabfrage beim Verlassen → **B07**.
  Hier steht P nur für die VLC-Engine (AK-20).
- Mehrere Streams gleichzeitig → **B08**. Die Engines sind dieselben, ihr Verhalten (AK-05 bis AK-12) gilt dort mit.
- Anlage, Speicherung und Umstellung der Zugangsdaten, Bildung der gespeicherten Adresse → **B01**. Hier geht es
  nur darum, dass der Player sie beim Öffnen abruft (AK-03, AK-04).
- Liste, Suche und Navigation bis zur Karte → **B04**; Favoritenstern → **B05**.
- Suchen, Zeitleiste, Timeshift, Aufnahme, EPG, Untertitel- und Tonspurwahl: nicht vorhanden (PRD, *Nicht im Scope*).
- Verhalten beim Löschen oder Aktualisieren einer Playlist, während ihr Sender spielt (DM-10) → **B03**, hier nur
  als Randfall (EC-11).

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. Nötig sind ein lokaler Server, der HLS, MP4 und rohes MPEG-TS
in Echtzeit ausliefert und seine Anfragen protokolliert, sowie Fehlerantworten (401, 403, 404, HTML, Hänger,
Abbruch). Streams ohne Tonspur genügen.

### Öffnen und Engine-Wahl

- **AK-01** · Angenommen, eine Senderliste oder die Favoriten sind offen, wenn eine Senderkarte angetippt wird,
  dann öffnet sich der Player im selben Navigationsstapel. Die Fläche ist schwarz, in der Mitte dreht sich ein
  weißer Ladekreis, und der Stream startet von selbst, nicht stumm, mit 100 % Lautstärke. Unter iOS steht der
  Sendername klein in der Navigationsleiste. Unter macOS trägt das Fenster den Sendernamen als Titel; in der
  Symbolleiste stehen „Zurück" und die Tab-Auswahl. *(ausgeführt macOS auf dem echten Weg und in der Sonde,
  iOS in der Sonde)*
- **AK-02** · Angenommen, ein Sender wird geöffnet, dann entscheidet allein die letzte Dateiendung im Pfad der
  abspielbaren Adresse über die Engine. Groß- und Kleinschreibung sowie Query und Fragment zählen nicht:
  | Endung bzw. Adresse | Engine |
  |---|---|
  | `.ts`, `.mpegts`, `.mts`, `.m2ts` (auch `.TS`, `a.ts?token=…`, `a.ts#…`, `a.m3u8.ts`, `file:///…/a.ts`) | VLC |
  | `.m3u8`, `.m3u` (auch `.M3U8`, `a.ts.m3u8`) | AVKit |
  | alles andere: `.mp4`, `.mkv`, keine Endung (`/live/u/p/101`), `play.php?file=a.ts`, `a.ts%20`, `rtmp://`, `rtsp://`, `udp://` | AVKit |
  Die App fragt nie nach der Engine und wechselt sie bei einem Fehler nicht. *(ausgeführt, 25 Adressen)*
- **AK-03** · Angenommen, der Sender gehört zu einer Xtream-Playlist, deren Zugangsdaten im Schlüsselbund
  liegen, wenn er geöffnet wird, dann ruft der Player
  `<Host>/live/<Benutzername>/<Passwort>/<stream_id>.<ts|m3u8>` ab. Benutzername und Passwort sind je als
  Pfadabschnitt prozentkodiert (`qa user` → `qa%20user`, `a/b#c?d.m3u8` → `a%2Fb%23c%3Fd.m3u8`). Die Engine
  folgt der Endung der `stream_id` und nicht dem Passwort. Adressen aus M3U-Playlists gehen unverändert an die
  Engine, samt Benutzerinfo und Token in der Query. Eine Xtream-Playlist im Altbestand, deren Adresse die
  Zugangsdaten noch selbst trägt, spielt ebenfalls unverändert. *(ausgeführt)*
- **AK-04** · Angenommen, die Zugangsdaten einer Xtream-Playlist fehlen im Schlüsselbund, wenn einer ihrer
  Sender geöffnet wird, dann erscheint ohne Ladekreis die Fehleransicht (AK-13) mit „Die Zugangsdaten dieser
  Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren.". Es geht keine
  Anfrage an den Server. „Erneut versuchen" liest den Schlüsselbund neu und zeigt dieselbe Meldung. Ist die
  gespeicherte Adresse unbrauchbar (kein `/live/`), lautet die Meldung „Die Stream-Adresse ist ungültig.".
  *(ausgeführt; Bild `mac-10`)*

### Zustände und Fehler mit AVKit (HLS, MP4, alles ohne TS-Endung)

- **AK-05** · Angenommen, ein HLS-Stream (VOD oder live) oder ein MP4 mit Byte-Range-Unterstützung ist
  erreichbar, dann verschwindet der Ladekreis, sobald das Bild bereit ist (lokal nach 0,1 bis 0,3 s), und die
  Steuerung erscheint (AK-13). Ein Live-HLS-Stream lädt die Playlist alle 2 s neu und jedes neue Segment.
  *(ausgeführt)*
- **AK-06** · Angenommen, die Wiedergabe mit AVKit scheitert, dann zeigt der Player die Fehleransicht (AK-13) mit
  dem **englischen Systemtext** der Engine, ungefiltert:
  | Ursache | angezeigter Text | nach |
  |---|---|---|
  | HTTP 404 | „The requested URL was not found on this server." | < 0,5 s |
  | HTTP 403 | „You do not have permission to access the requested resource." | < 0,5 s |
  | HTTP 401 mit `WWW-Authenticate` | „The operation couldn’t be completed. (NSURLErrorDomain error -1013.)" | < 0,5 s |
  | Port geschlossen | „Could not connect to the server." | < 0,5 s |
  | Hostname nicht auflösbar | „A server with the specified hostname could not be found." | < 0,5 s |
  | HTML-Seite unter `.m3u8` | „unsupported URL" | < 0,5 s |
  | HTML-Seite unter `.mp4`; roher Live-TS ohne Endung | „Operation Stopped" | < 0,5 s |
  | M3U-Senderliste unter `.m3u` | „The operation couldn’t be completed. (CoreMediaErrorDomain error -12646.)" | < 0,5 s |
  | Server nimmt an, antwortet nie (`.m3u8`) | „resource unavailable" | ≈ 40 s Ladekreis |
  | Server nimmt an, antwortet nie (`.mp4`) | „The operation could not be completed" | ≈ 120 s Ladekreis |
  | Live-HLS bricht mitten im Stream ab | „The network connection was lost." | ≈ 31 s Standbild, Steuerung wie bei laufendem Stream |
  *(ausgeführt; Bilder `mac-08`, `mac-09`; Sprache → OF-01)*
- **AK-07** · Angenommen, der erste Abruf einer Live-HLS-Playlist wird 25 s verzögert, dann zeigt der Player den
  Ladekreis, bis AVKit nach etwa 20 s einen neuen Abruf startet, und spielt danach normal. *(ausgeführt)*
- **AK-08** · Angenommen, die Fehleransicht ist zu sehen, wenn „Erneut versuchen" betätigt wird, dann lädt
  dieselbe Engine die Adresse neu: kurz Ladekreis, eine neue Anfrage beim Server, bei fortbestehendem Fehler
  wieder die Fehleransicht. Eine Begrenzung oder Wartezeit zwischen Versuchen gibt es nicht. *(ausgeführt über
  die Aktion des Knopfs, zweimal; kein echter Klick)*

### Zustände und Fehler mit VLC (`.ts`, `.mpegts`, `.mts`, `.m2ts`)

- **AK-09** · Angenommen, ein roher MPEG-TS-Stream mit einer dieser Endungen ist erreichbar, dann spielt er über
  VLC. Der Ladekreis verschwindet nach etwa 0,1 s, das Bild läuft, die Steuerung erscheint. *(ausgeführt, alle
  vier Endungen und `.TS`, jeweils 60 s)*
- **AK-10** ⚠ · Angenommen, ein `.ts`-Stream antwortet mit HTTP 401, 403 oder 404, oder der Host ist nicht
  erreichbar (Port geschlossen, Name nicht auflösbar), dann dreht sich der **Ladekreis unbegrenzt** (beobachtet
  60 s). Es erscheint keine Meldung und kein „Erneut versuchen". Die Meldung „VLC konnte den Stream nicht
  abspielen." erschien in keinem geprüften Fall. Bei 401, 403 und 404 erhält der Server je Öffnen vier
  Anfragen. Ein Anmeldedialog von VLC erscheint bei 401 nicht. *(ausgeführt; Bild `mac-11`; als Fehler eingestuft → FB-01)*
- **AK-11** ⚠ · Angenommen, ein `.ts`-Stream liefert gar nichts (Verbindung angenommen, keine Daten), startet
  verzögert oder liefert eine HTML-Seite, dann verschwindet der Ladekreis trotzdem nach etwa 0,1 s. Der Player
  gilt als „läuft": schwarze Fläche, die Steuerung erscheint und blendet aus, keine Meldung. So bleibt es
  (beobachtet 200 s). Bei der HTML-Seite bleibt je nach Lauf auch der Ladekreis stehen. *(ausgeführt; Bild
  `mac-12`; als Fehler eingestuft → FB-01)*
- **AK-12** ⚠ · Angenommen, ein laufender `.ts`-Stream bricht ab (Server schließt die Verbindung), dann bleibt
  das letzte Bild stehen. Es gibt keinen Ladekreis, keine Meldung, und der Player gilt weiter als „läuft".
  *(ausgeführt, 60 s nach dem Abbruch; Bild `mac-13`; als Fehler eingestuft → FB-01)*

### Fehleransicht, Steuerung und HUD

- **AK-13** ⚠ · Angenommen, die Wiedergabe ist gescheitert (AK-04, AK-06), dann liegt über der schwarzen Fläche
  ein Kasten mit Warndreieck, „Wiedergabe fehlgeschlagen", der Meldung und dem Button „Erneut versuchen"
  (Akzentfarbe). Die Steuerung ist ausgeblendet. Endet die **gespeicherte** Adresse des Senders auf `.ts`,
  `.mpegts`, `.mts` oder `.m2ts`, steht zusätzlich „Hinweis: Rohe MPEG-TS-Streams (.ts) benötigen VLCKit –
  siehe README.". VLCKit ist eingebunden. Der Hinweis erscheint deshalb in der Praxis nur bei fehlenden
  Xtream-Zugangsdaten, und gerade bei echten VLC-Fehlern (AK-10) nie. *(ausgeführt; Bild `mac-10`; als Fehler
  eingestuft → FB-04)*
- **AK-14** · Angenommen, ein Stream spielt, dann liegen oben rechts der Vollbild-Knopf (links daneben ggf.
  Bild-in-Bild, B07) und unten links Play/Pause und Stumm: weiße Symbole auf halbtransparentem Schwarz. Diese
  Steuerung ist nur im Zustand „läuft" zu sehen, nie beim Laden und nie in der Fehleransicht. Sie blendet etwa
  3,5 s nach dem **Öffnen** des Players aus (gemessen 3,6 s), nicht 3,5 s nach Spielbeginn. Ein Tipp bzw. Klick
  auf das Bild schaltet sie ein oder aus. Play/Pause, Stumm, F und P blenden sie für weitere 3,5 s ein, die
  Lautstärketasten nicht. *(ausgeführt macOS mit synthetischem Klick; Bild `mac-01`)*
- **AK-15** · Angenommen, ein Stream spielt, wenn Play/Pause betätigt oder die Leertaste gedrückt wird, dann
  hält der Stream an bzw. läuft weiter. Mittig erscheint 0,9 s lang ein HUD mit dem Symbol des **neuen**
  Zustands (Pause-Balken beim Anhalten, Dreieck beim Fortsetzen). Der Knopf unten links zeigt dann ▶ bzw. ❚❚.
  *(ausgeführt, beide Engines: AVKit Rate 0/1, VLC `paused`/`playing`; Bilder `mac-02`, `mac-05`)*
- **AK-16** · Angenommen, ein Stream spielt, wenn Stumm betätigt oder M bzw. m gedrückt wird, dann schaltet der
  Ton um. Das HUD zeigt 0,9 s lang den durchgestrichenen bzw. normalen Lautsprecher, der Knopf ebenso. Der
  Lautstärkewert bleibt. *(ausgeführt, beide Engines; Bild `mac-04`)*
- **AK-17** · Angenommen, ein Stream spielt, wenn ↑, + oder = bzw. ↓ oder - gedrückt wird, dann ändert sich die
  Lautstärke um 5 Prozentpunkte. Das HUD zeigt 0,9 s lang Symbol, Balken und Prozentwert. Sie bleibt zwischen
  0 % und 100 %: Dreimal ↑ bei 100 % bleibt 100 %, zwanzigmal ↓ von 100 % erreicht 0 %. Jede Änderung auf einen
  Wert über 0 % **hebt eine Stummschaltung auf**, auch ↓. Jeder neu geöffnete Player beginnt bei 100 % und nicht
  stumm; nichts davon wird gespeichert. Die Systemlautstärke bleibt unberührt. *(ausgeführt, beide Engines;
  Bild `mac-03`; ↓ hebt Stumm auf → OF-02)*
- **AK-18** · Angenommen, der Player hat den Tastaturfokus (macOS; iPad/iPhone mit Hardware-Tastatur *(gelesen)*),
  dann gilt:
  - Leertaste, ↑, ↓, +, =, -, M, F, P sind belegt, unabhängig von Umschalt und Feststelltaste. Auch mit ⌘ lösen
    sie aus, soweit kein Menübefehl die Kombination belegt (⌘F schaltet das Vollbild).
  - Esc ist nur im Vollbild belegt.
  - Andere Tasten (geprüft x, k, 1, ←, →, Return) tun nichts, und **macOS gibt den Warnton aus**. Tab und Esc
    außerhalb des Vollbilds tun nichts, ohne Warnton.
  *(ausgeführt, Warnton über den Beep-Wächter festgestellt, nicht gehört)*
- **AK-19** · Angenommen, der Player wurde geöffnet, dann reagiert er ohne vorherigen Klick auf Tasten. Das
  bleibt so nach dem Wechsel ins und aus dem Vollbild, nach einem Klick auf das Bild und nach der Rückkehr aus
  dem anderen Tab. *(ausgeführt macOS)*
- **AK-20** · Angenommen, ein `.ts`-Sender spielt über VLC, wenn P gedrückt wird, dann blendet sich nur die
  Steuerung ein; es gibt keinen Warnton und kein HUD. *(ausgeführt; Bild-in-Bild selbst → B07)*

### Vollbild

- **AK-21** · Angenommen, ein Stream spielt am Mac, wenn der Vollbild-Knopf betätigt oder F gedrückt wird, dann
  wechselt das Fenster in das native Vollbild von macOS (eigener Space, ganze Bildschirmgröße). Titel,
  Symbolleiste mit „Zurück" und Tab-Auswahl verschwinden. Die Knöpfe rücken 24 pt vom Rand ab. Esc, F oder der
  Knopf führen zurück in die vorherige Fenstergröße. Wird der Player im Vollbild verlassen („Zurück"), verlässt
  auch das Fenster das Vollbild. *(ausgeführt; Bild `mac-05`)*
- **AK-22** · Angenommen, der Player ist am Mac im Vollbild, wenn der Mauszeiger in die oberen 90 pt kommt, dann
  erscheinen Symbolleiste und Steuerung, solange er dort bleibt. *(gelesen)*
- **AK-23** ⚠ · Angenommen, am Mac sind zwei Hauptfenster offen, der Player liegt in Fenster A, und Fenster B ist
  das aktive Fenster, wenn die Vollbild-Aktion des Players ausgelöst wird, dann geht **Fenster B** ins Vollbild
  (mit seiner Senderliste). Fenster A verliert Titel und Symbolleiste, bleibt aber ein normales Fenster.
  Dieselbe Aktion noch einmal holt B zurück. *(ausgeführt über die Aktion des Knopfs, während B
  Schlüsselfenster war; ob ein echter Klick in A das auslösen kann, ist nicht geprüft, weil ein Klick A
  normalerweise erst aktiviert; Bilder `mac-06`, `mac-07`; als Fehler eingestuft → FB-06)*
- **AK-24** ⚠ · Angenommen, das Player-Fenster wird am Mac über den grünen Fensterknopf oder das Menü ins
  Vollbild geschaltet, dann bleibt der Player in der Fensterdarstellung. Titel und Symbolleiste verschwinden
  nicht dauerhaft, und die Knöpfe behalten den normalen Abstand. Das erste F danach blendet nur Titel und
  Symbolleiste aus; erst das zweite F verlässt das Vollbild. *(ausgeführt über `toggleFullScreen` wie der grüne
  Knopf; der umgekehrte Fall — Verlassen über den grünen Knopf — gelesen; als Fehler eingestuft → FB-06)*
- **AK-25** ⚠ · Angenommen, ein Stream spielt auf dem **iPhone**, wenn Vollbild eingeschaltet wird, dann
  verschwinden Navigationsleiste, Tab-Leiste, Statusleiste und Home-Indikator, und die Ansicht dreht in
  **Querformat rechts**. Das gilt auch, wenn das Gerät vorher in Querformat links stand. Beim Ausschalten, und
  ebenso beim Verlassen des Players im Vollbild, dreht die Ansicht ins **Hochformat**, auch wenn das Gerät
  vorher quer lag. *(ausgeführt iPhone-17-Simulator; Bilder `iphone-14`, `iphone-15`; Absicht → OF-03)*
- **AK-26** · Angenommen, das Gerät ist ein iPad, dann blendet Vollbild die Leisten aus, ohne die Ausrichtung
  zu ändern. *(gelesen)*

### Verlassen, Tabwechsel, Hintergrund

- **AK-27** · Angenommen, ein Stream spielt, wenn in den anderen Tab gewechselt wird, dann hält er an. Bei der
  Rückkehr läuft er in derselben Engine weiter, ohne neuen Aufbau. *(ausgeführt macOS)*
- **AK-28** ⚠ · Angenommen, ein Stream spielt, wenn der Nutzer den Player mit „Zurück" verlässt, dann hält die
  Wiedergabe an. Die Engine und ihre Verbindung werden aber **nicht zuverlässig beendet**:
  - Auf dem echten Weg (Senderliste → Player → Zurück) blieb die Engine des zuerst geöffneten Senders erhalten,
    bis der nächste Sender geöffnet wurde (12 s). In der Sonde blieben verlassene Player bis zum Beenden der App
    erhalten (über 45 s).
  - Solange sie leben, holt die AVKit-Engine auch **pausiert** alle 2 s die Live-Playlist und jedes neue Segment,
    genauso viel wie beim Abspielen. Im anderen Tab laufen so zwei Engines parallel.
  - Die VLC-Engine hält die Verbindung offen, liest aber nicht weiter (beobachtet 93 s bis zum Beenden der App).
  - Andere Male war die Engine 0,2 bis 2 s nach „Zurück" freigegeben und die Verbindung geschlossen.
  *(ausgeführt macOS, Protokoll des Mocks; iOS einmal sofort freigegeben; als Fehler eingestuft → FB-02)*
- **AK-29** ⚠ · Angenommen, ein `.ts`-Sender lädt noch, wenn der Nutzer den Player verlässt, dann wirkt die
  Pause nicht. VLC startet den Stream nach dem Verlassen trotzdem und empfängt ihn mit voller Datenrate. Die App
  hält ihn für pausiert, bis die Engine freigegeben wird (beobachtet 26 s). Hätte der Stream Ton, wäre er zu hören
  *(nicht gehört: stumm geprüft über den VLC-Zustand „playing" und die Datenmenge am Server)*.
  *(ausgeführt; als Fehler eingestuft → FB-02)*
- **AK-30** · Angenommen, unter iOS läuft ein Stream über AVKit, wenn die App in den Hintergrund geht, dann
  läuft die Wiedergabe weiter (Hintergrundmodus `audio`, Audio-Sitzung `.playback`), ohne Zeitgrenze. Die
  VLC-Engine aktiviert keine Audio-Sitzung; wie sie sich im Hintergrund mit Ton verhält, ist nicht prüfbar, ohne
  Ton abzuspielen. *(AVKit: belegt in B07 AK-21; VLC gelesen → OF-05)*

### Datenschutz und Missbrauchsschutz

Fragenkatalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog). Jede Frage hat ein Kriterium, ein
„trifft nicht zu, weil …" oder einen Eintrag im *Fehlbestand*.

- **AK-31** · Angenommen, die Wiedergabe scheitert aus einem der Gründe in AK-04, AK-06, AK-10 bis AK-12, dann
  enthält nichts Sichtbare die Stream-Adresse, den Host, den Benutzernamen oder das Passwort. *(ausgeführt:
  15 AVKit-Fälle, davon 2 mit Xtream-Adresse, beide Resolver-Meldungen; VLC zeigt ohnehin keinen Text;
  Bilder `mac-08` bis `mac-13`)*
- **AK-32** · Angenommen, ein Xtream-Sender wird abgespielt, dann erhält der Server des Anbieters
  (ausschließlich dieser Host) Benutzername und Passwort im Pfad jeder Anfrage:
  - bei `.ts` einmal je Öffnen (VLC, `Range: bytes=0-`, User-Agent `VLC/3.0.21 LibVLC/3.0.21`),
  - bei `.m3u8` alle 2 s mit der Playlist und mit jedem relativ adressierten Segment (User-Agent
    `AppleCoreMedia/… (Macintosh; U; Intel Mac OS X 27_0; de_de)`, also Systemversion und Sprache),
  - bei „Erneut versuchen" erneut.
  Ohne `https://` im Host läuft das unverschlüsselt (B01). Andere Empfänger gibt es nicht.
  *(ausgeführt, Protokoll des Mocks)*
- **AK-33** · Angenommen, die Mac-App läuft normal (nicht als Test-Host), wenn Xtream-Sender abgespielt werden
  oder scheitern, dann stehen weder Passwort noch Stream-Adresse im Unified Log. Verbindungen erscheinen dort nur
  mit gehashtem Host und „url hash". VLC schreibt nichts auf stdout/stderr außer „creating player instance using
  shared library". *(ausgeführt, 7 App-Läufe, `log stream --level debug`; Gegenprobe Test-Host → EC-10)*
- **AK-34** · Angenommen, der Player wurde benutzt, dann ist davon nichts in der Datenbank gespeichert: keine
  Lautstärke, kein Stumm, keine Position, kein zuletzt gesehener Sender. Der HTTP-Cache der App bleibt leer. Die
  Einstellungen der App enthalten danach den Schlüssel `VLCParams` (Startparameter von VLCKit, u. a.
  `--verbose=4`, `--extraintf=macosx_dialog_provider`). Außerdem legt libVLC unter macOS die Konfigurationsdatei
  `~/Library/Preferences/<Bundle-ID>/vlcrc` an (88 KB). *(Cache, Einstellungen und `vlcrc` ausgeführt unter der
  Sonden-ID, Inhalt der `vlcrc` nicht untersucht; Datenbank gelesen)*
- **AK-35** ⚠ · Angenommen, eine Playlist verweist auf einen `.ts`-Stream eines beliebigen Hosts, wenn der Sender
  geöffnet wird, dann verarbeitet die eingebettete **libVLC 3.0.21** den unvertrauten Datenstrom im Prozess der
  App. Unter macOS läuft die App ohne Sandbox. Für diese Version hat VideoLAN im Dezember 2025 Sicherheitslücken
  veröffentlicht, darunter CVE-2025-51602, behoben in 3.0.22. Das eingebundene Paket `vlckit-spm` ist exakt auf
  3.6.0 (Februar 2025) gepinnt und hat keine neuere Version. Schema und Ziel werden nicht eingegrenzt:
  `file:///…ts` geht an VLC, Adressen im lokalen Netz an die jeweilige Engine. *(Version ausgeführt über den
  User-Agent, Tags abgefragt 2026-09-16, Bulletin gelesen; Angriff nicht ausgeführt; als Fehler eingestuft → FB-03)*

#### Katalog, Frage für Frage

| # | Katalogfrage | Antwort für B06 |
|---|---|---|
| 1.1 | Welche personenbezogenen Daten? | Xtream-Benutzername und -Passwort im Pfad jeder Stream-Anfrage (AK-32); IP-Adresse, gewählter Sender und Zeitpunkt gegenüber dem Anbieter; Systemversion und Sprache im User-Agent von AVKit. Gespeichert wird nichts (AK-34) |
| 1.2 | Besondere Kategorien? | Der gesehene Sender kann Rückschlüsse zulassen (Religion, Herkunft, politische Haltung). Er geht zwangsläufig an den Anbieter und wird in der App nicht gespeichert. Sichtbarkeit über Bild-in-Bild → B07 |
| 1.3 | Wo gespeichert, wie lange? | Nirgends dauerhaft (AK-34). Die Zugangsdaten liest der Player nur aus dem Schlüsselbund (B01) und hält sie in der Adresse der laufenden Engine, solange diese lebt — wegen FB-02 teils deutlich länger als der Player sichtbar ist |
| 1.4 | Landen sie in Logs? | Im normalen Betrieb nein (AK-33). Im Test-Host von `xcodebuild` ja, mit Speicherung im Log (EC-10). In Fehlermeldungen nein (AK-31) |
| 2.1 | Welche externen Dienste? | Nur der Host aus der Stream-Adresse: bei Xtream der eingegebene Anbieter, bei M3U jeder beliebige Host, auch im lokalen Netz oder `file://` (AK-35). Keine Analyse, kein Fehler-Tracking |
| 2.2 | Was wird übertragen, was vorher entfernt? | Siehe AK-32; entfernt wird nichts. Die Zugangsdaten im Pfad verlangt das Xtream-Protokoll; HTTP ohne Verschlüsselung folgt aus dem Host (B01) und `NSAllowsArbitraryLoads` |
| 2.3 | Standort des Dienstes, AV-Vertrag? | Trifft nicht zu, weil der Nutzer den Anbieter selbst wählt und direkt mit ihm spricht; daumedia empfängt nichts |
| 2.4 | Training mit dem Payload? | Trifft nicht zu, weil kein KI-Dienst beteiligt ist |
| 3.1 | Wer darf sehen, ändern, löschen? | Sehen kann jeder, der auf den Bildschirm schaut. Es gibt keine gespeicherten Daten des Players, die jemand ändern oder löschen könnte |
| 3.2 | Erzwungen in DB oder Anwendung? | Trifft nicht zu, weil der Player keine Daten mit Zugriffsregeln hat. Die Zugangsdaten schützt der Schlüsselbund (B01) |
| 3.3 | Fremde ID? | Trifft nicht zu, weil es keinen Server der App und keine per ID abrufbaren Ressourcen gibt |
| 3.4 | Rollen? | Trifft nicht zu, weil die App keine Konten und keine Rollen hat |
| 4.1 | Rate Limit auf Anmeldung u. ä. | Die Stream-Endpunkte gehören dem Anbieter. „Erneut versuchen" hat keine Drosselung, eine Anfrage je Betätigung (AK-08); die Bremse aus B01 gilt nur für `player_api.php`. Kein eigener Befund, weil jede Anfrage eine bewusste Handlung ist |
| 4.2 | Rate Limit für Kostenpflichtiges | Für den Betreiber trifft das nicht zu. Beim Anbieter zählen gleichzeitige Verbindungen: Nicht beendete Engines halten Verbindungen, und das nächste Öffnen baut eine weitere auf (AK-28, AK-29) → **FB-02** |
| 4.3 | Kosten je Aufruf | Datenvolumen des Nutzers: pausierte bzw. verlassene AVKit-Player laden weiter, VLC lädt nach Verlassen während des Ladens mit voller Rate (AK-28, AK-29) → **FB-02**. Hintergrundwiedergabe ohne Zeitgrenze (AK-30) |
| 4.4 | Unvertraute Inhalte: Größe, Typ, Prüfung | Streams beliebiger Hosts gehen ungeprüft an AVFoundation bzw. libVLC; der Typ wird nur an der Endung erkannt (AK-02). libVLC 3.0.21 hat bekannte Lücken → **FB-03** |
| 4.5 | Wo greift das Limit? | AVKit bricht Hänger nach ≈ 40 s (HLS) bzw. ≈ 120 s (MP4) selbst ab (AK-06). VLC hat keine Grenze, die App auch nicht (AK-10, AK-11) → **FB-01** |
| 5.1 | Konto selbst löschen? | Trifft nicht zu, weil der Player kein Konto und keine eigenen Daten hat |
| 5.2 | Was wird dabei gelöscht? | Trifft nicht zu, siehe 5.1 und AK-34 |
| 5.3 | Was bleibt, und warum? | `VLCParams` in den Einstellungen und die VLC-Konfigurationsdatei `vlcrc` (AK-34); Personendaten darin nicht erwartet, Inhalt nicht untersucht |
| 5.4 | E-Mail-Adresse wieder frei? | Trifft nicht zu, weil die App keine Registrierung hat |
| 5.5 | Datenexport? | Trifft nicht zu, weil der Player keine Daten erzeugt |
| 6.1 | Welche Schlüssel braucht das Feature? | Keine App-Schlüssel. Es liest das Xtream-Passwort des Nutzers aus dem Schlüsselbund (B01) |
| 6.2 | Welche dürfen zum Client? | Trifft nicht zu, weil es keinen Server gibt |
| 6.3 | Steht Echtes im Repository? | Nein. Die Historie der Player- und Engine-Dateien (4 Commits) enthält keine Stream-Adressen und keine Zugangsdaten (`git log -p`, 2026-09-16) |
| 6.4 | Vorlagen `.env.example` / `Secrets.example.xcconfig` | Trifft nicht zu, weil B06 keine Build-Geheimnisse braucht |

## Edge Cases

Ist-Verhalten. „(ausgeführt)" heißt mit der Sonde belegt, „(gelesen)" heißt aus dem Code abgeleitet.

- **EC-01** · Roher Live-TS unter einer Adresse **ohne Endung** (manche Panels liefern M3U-Links so) → AVKit,
  „Operation Stopped", kein Versuch mit VLC, kein Hinweis. *(ausgeführt → OF-04)*
- **EC-02** · Adresse auf `.m3u`, die eine Senderliste statt HLS liefert → AVKit, „The operation couldn’t be
  completed. (CoreMediaErrorDomain error -12646.)". Liefert sie echtes HLS, spielt sie. *(ausgeführt)*
- **EC-03** · Eine abgeschlossene `.ts`-**Datei** mit Byte-Range spielt auch über AVKit. Nur rohes **Live**-TS ohne
  Länge scheitert dort („Operation Stopped"). Ein Build ohne VLCKit würde `.ts`-Livestreams mit „Operation
  Stopped" und dem README-Hinweis ablehnen. *(ausgeführt, AVKit erzwungen)*
- **EC-04** · MP4 oder anderes VOD läuft bis zum Ende → Das Bild steht, der Player gilt weiter als „läuft", der
  Knopf zeigt ❚❚. Es gibt keine Ende-Anzeige. Beim VLC-Dateiende würde der Player in den Ladekreis fallen
  (Zustand „ended" → „idle"). *(MP4 ausgeführt; VLC-Ende gelesen)*
- **EC-05** · Leertaste, während ein `.ts`-Stream noch lädt → Die Pause wirkt nicht (wie AK-29), der Knopf zeigt
  aber ▶. Der nächste Druck ruft „Play" auf. *(an der Engine ausgeführt: App „pausiert", VLC „playing")*
- **EC-06** · Lautstärke in 5-%-Schritten → Die Werte sind Gleitkommazahlen (0,8999…). Angezeigt wird gerundet;
  beim 19. Schritt 5 %, beim 20. genau 0 %. *(ausgeführt)*
- **EC-07** · ⌘ plus eine belegte Taste ohne Menübefehl (z. B. ⌘F) → wirkt wie die Taste allein. *(ausgeführt)*
- **EC-08** · App nicht aktiv oder anderes Fenster aktiv → Tasten erreichen den Player nicht; die
  Vollbild-Aktion trifft dann das Schlüsselfenster oder, ohne Schlüsselfenster, das Hauptfenster (AK-23).
  *(gelesen; in der Sonde beobachtet, als eine fremde App den Fokus nahm)*
- **EC-09** · Live-HLS ist beim Öffnen verzögert oder bricht ab → Bis AVKit aufgibt (≈ 31–40 s), zeigt der Player
  Standbild bzw. Ladekreis ohne Hinweis (AK-06, AK-07). *(ausgeführt)*
- **EC-10** · Die App läuft als Test-Host von `xcodebuild test` → CFNetwork und das Netzwerk-Framework schreiben
  die vollständigen Stream-Adressen samt Benutzername und Passwort in das Unified Log. Sie sind danach mit
  `log show` abrufbar, obwohl Private-Data-Logging systemweit aus ist. Betrifft nur Entwicklerrechner, nicht die
  ausgelieferte App (AK-33). *(ausgeführt: 10 Zeilen im Mitschnitt, 8 im gespeicherten Log)*
- **EC-11** · Die Playlist des laufenden Senders wird gelöscht oder aktualisiert (B03) → Der Player hält das
  `Channel`-Objekt weiter. „Erneut versuchen" nach dem Löschen einer Xtream-Playlist meldet fehlende
  Zugangsdaten, weil das Löschen den Schlüsselbund-Eintrag entfernt. *(gelesen, nicht ausgeführt)*
- **EC-12** · Zwei Hauptfenster mit je einem Player → zwei unabhängige Engines und Verbindungen, Tasten nur im
  aktiven Fenster. *(gelesen)*
- **EC-13** · Das Player-Fenster wird am Mac geschlossen (⌘W) → Der Player verschwindet und pausiert (wie
  „Zurück"). Ob Engine und Verbindung dann enden, ist nicht geprüft (vgl. AK-28). *(gelesen)*
- **EC-14** · Kennwort mit `/`, `#`, `?` oder `.m3u8` → Die Adresse bleibt gültig, und die Engine folgt der Endung der
  `stream_id` (AK-03). *(ausgeführt)*
- **EC-15** · Adresse mit Schema `rtmp://`, `rtsp://` oder `udp://` → AVKit, das diese Schemata nicht spielt. Auf VLC
  wird nicht ausgewichen. *(Engine-Wahl ausgeführt, Wiedergabe gelesen)*
- **EC-16** · Steuerung über schwarzem Rand (Letterbox) → Die halbtransparent schwarzen Kreise sind dort
  unsichtbar, nur die weißen Symbole bleiben. *(ausgeführt, Bild `mac-03`)*

## Offene Fragen

Alle vom 2026-09-16. Entscheidung durch den Nutzer (Michael Ferreira), vor der Reparaturrunde nach der QA von B06.

- **OF-01** · Sollen Fehlermeldungen im Player englische, teils kryptische Systemtexte zeigen („Operation
  Stopped", „unsupported URL" für eine HTML-Seite, „CoreMediaErrorDomain error -12646")? Die Oberfläche ist sonst
  deutsch (analog B01 OF-06). *(AK-06)*
- **OF-02** · Soll ↓ bzw. - eine Stummschaltung aufheben (AK-17)? Heute macht „leiser" einen stummen Stream hörbar.
- **OF-03** · iPhone-Vollbild: immer Querformat **rechts** und beim Verlassen immer Hochformat (AK-25) — oder der
  Lage des Geräts folgen und die vorherige Ausrichtung wiederherstellen?
- **OF-04** · Soll die Engine-Wahl außer der Endung auch den Inhalt berücksichtigen oder bei „Operation Stopped"
  auf VLC ausweichen (EC-01, EC-15)? CLAUDE.md und Website beschreiben die Wahl nach Endung als gewollt.
- **OF-05** · Soll die VLC-Engine unter iOS wie AVKit im Hintergrund weiterspielen (Audio-Sitzung), oder ist das
  Anhalten im Hintergrund gewollt (AK-30)? Mit stummen Streams nicht prüfbar.

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus dem Code belegt. Kein Kriterium: `sdd-qa` prüft nichts davon als
bestanden, sondern nimmt es als Suchliste.

- **FB-01 · VLC-Fehler erreichen die Oberfläche nie; der Player lädt endlos, zeigt Schwarz oder ein Standbild.**
  Fundstelle: `VLCPlaybackEngine.swift:80-99`. Der Delegate liest den Zustand erst in einer späteren
  Main-Actor-Aufgabe aus `mediaPlayer.state`, nicht aus der Benachrichtigung. Belegt ist die Folge „error" →
  „stopped" innerhalb derselben Millisekunde; beide Aufgaben lesen „stopped", daraus wird `.idle`. `.buffering`
  wird als `.playing` gewertet, auch ohne ein einziges empfangenes Byte. `.paused` (HTML-Inhalt, Abbruch) fällt in
  `default: break`. `PlayerView.swift:100-103` zeigt für `.idle` den Ladekreis. Eine Zeitgrenze gibt es weder in
  der Engine noch im Player.
  Folge: Xtream-Sender laufen standardmäßig über VLC (B01 AK-02). Gesperrte oder abgelaufene Konten (401/403),
  gelöschte Sender (404), Hänger und Abbrüche sehen für den Nutzer alle wie „lädt noch" oder „läuft" aus
  (andere HTTP-Fehler wie 407 nicht geprüft, gleicher Codepfad). Die vorhandene Fehleransicht mit
  „Erneut versuchen" und die Meldung „VLC konnte den Stream nicht abspielen." sind für diese Engine praktisch
  unerreichbar. Die Absicht ist eindeutig: Der Code enthält den Fehlerzweig, und README und CLAUDE.md beschreiben
  einen Fehler-Fallback. (AK-10, AK-11, AK-12)
- **FB-02 · Verlassen beendet die Wiedergabe nicht: Engines und Verbindungen überleben den Player, VLC spielt
  nach Verlassen während des Ladens weiter.**
  Fundstelle: `PlayerView.swift:83-92` ruft beim Verschwinden nur `pause()`. Die Engine lebt als `@State`
  (`PlayerView.swift:17`), wie lange, entscheidet SwiftUI. Das Protokoll kennt kein `stop()`
  (`PlaybackEngine.swift:35-81`), keine Engine hat ein `deinit`, das die Wiedergabe beendet
  (`AVKitPlaybackEngine.swift:145-148` beendet nur Beobachter; `VLCPlaybackEngine.swift` hat keins).
  `VLCPlaybackEngine.swift:49` pausiert nur, wenn VLC schon spielt. Der Code-Kommentar in
  `MultiviewSession.swift:69-70` benennt die Lücke selbst: „die Engines haben keinen `deinit`/`stop`, sonst liefe
  Audio weiter".
  Folge: Nach „Zurück" lädt ein Live-HLS-Stream bis zur Freigabe unverändert weiter; gemessen 12 s bis über 45 s,
  alle 2 s Playlist und Segment. VLC hält die Verbindung zum Anbieter offen (93 s). Beim nächsten Sender entsteht
  eine zweite Verbindung. Viele Abos erlauben nur eine, der neue Sender kann dann scheitern — unter VLC ohne
  sichtbaren Grund (FB-01). Wer einen ladenden `.ts`-Sender verlässt, hört ihn gegebenenfalls danach im
  Hintergrund, ohne Knopf zum Anhalten. Datenvolumen und Akku werden ohne Nutzen verbraucht. (AK-28, AK-29)
- **FB-03 · Unvertraute Streams laufen durch eine veraltete libVLC mit bekannten Sicherheitslücken, ohne Sandbox
  und ohne Eingrenzung von Schema und Ziel.**
  Fundstelle: `project.yml:17-19` (`tylerjonesio/vlckit-spm`, `exactVersion: "3.6.0"`, Binärpaket eines Dritten,
  kein Release von VideoLAN); eingebettet ist libVLC 3.0.21 (User-Agent). `VLCPlaybackEngine.swift:40-46`
  übergibt jede Adresse ungeprüft. `PlaybackEngine.swift:13-19` prüft nur die Endung, nicht Schema oder Host.
  `MikaPlusPlayer.entitlements:7-12`: Sandbox aus, Library Validation aus.
  Nachweis: Das VideoLAN Security Bulletin zu VLC 3.0.22 (Dezember 2025) nennt für 3.0.21 und älter
  CVE-2025-51602 und weitere Lücken, u. a. im CEA-708-Untertiteldecoder, der in MPEG-TS-Videoströmen vorkommt,
  sowie im MP4-, Ogg-, ASF- und WebVTT-Demuxer und bei MMS. Angriffsweg sind „maliciously crafted files or
  streams". Das Paket hat außer 3.6.0 keine neuere Version (`git ls-remote`, 2026-09-16).
  Folge: Jeder Host, der in einer importierten Playlist steht, kann der App einen präparierten Stream liefern.
  Belegt ist mindestens ein Absturz. Code-Ausführung schließt VideoLAN nicht aus. Sie liefe unter macOS mit allen
  Rechten des Benutzers, im Prozess, der die Xtream-Zugangsdaten aus dem Schlüsselbund lesen darf. Zusätzlich
  öffnet die App auf Anweisung einer Playlist `file://`-Adressen und Ziele im lokalen Netz. (AK-35)
- **FB-04 · Die Fehleransicht schickt Endnutzer zur README und behauptet, VLCKit fehle.**
  Fundstelle: `PlayerView.swift:220-223`, Bedingung `PlayerView.swift:234-236` (Endung der gespeicherten
  Adresse, nicht „VLCKit fehlt"). README, Abschnitt „Ohne VLCKit", beschreibt den Hinweis nur für Builds ohne
  VLCKit. Entspricht DS-06.
  Folge: Mit eingebundenem VLCKit erscheint der Hinweis genau dann, wenn die Ursache eine andere ist
  (fehlende Zugangsdaten, AK-04), und nie bei echten VLC-Fehlern (FB-01). Er verweist Endnutzer auf ein
  Entwicklerdokument. (AK-13)
- **FB-05 · Die Website verspricht HUD-Rückmeldung für jede Taste; F, Esc und P haben keine.**
  Fundstelle: `web/content/features.ts:38` („On-screen feedback confirms each one, then disappears"),
  `web/app/support/page.tsx:66-71` (Tastenliste inklusive P ohne Einschränkung). Im Code zeigen nur Play/Pause,
  Stumm und Lautstärke ein HUD (`PlayerView.swift:348-371`). F, Esc und P blenden höchstens die Steuerung ein
  (`PlayerView.swift:306-313, 362-365`). P bewirkt unter VLC nichts (AK-20).
  Folge: Nutzer erwarten eine Bestätigung, die nicht kommt; bei MPEG-TS, dem Standardformat, reagiert P scheinbar gar nicht.
- **FB-06 · Der Vollbildzustand des Players ist nicht an sein Fenster gebunden.**
  Fundstelle: `PlayerView.swift:399-404` schaltet `NSApp.keyWindow ?? NSApp.mainWindow`, nicht das Fenster
  der Ansicht. `isFullscreen` (`PlayerView.swift:20, 306-313`) wird nur von eigenen Aktionen gesetzt und
  gleicht sich nie mit dem Fenster ab. Entspricht AS-03.
  Folge: Mit zwei Fenstern kann das falsche ins Vollbild gehen. Fenster A bleibt dann ohne Titel und
  Symbolleiste (AK-23); wie oft das bei echter Bedienung eintritt, ist offen. Vollbild über den grünen Knopf oder
  das Menü verstimmt den Player: Das erste F bewirkt scheinbar nichts, und die Fensterdarstellung passt nicht
  (AK-24). Die Absicht, das Fenster des Players umzuschalten, steht im Kommentar `PlayerView.swift:400`.

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Engine-Wahl nur nach Dateiendung, `.m3u` als HLS | reguläres Kriterium AK-02; Ausweichen als OF-04 | in CLAUDE.md, README und Website als gewollt beschrieben, kein Punkt aus `sicherheit.md`; `.m3u` steht ausdrücklich im Code |
| 2 | VLC-Fehler werden nie angezeigt | ⚠ AK-10 bis AK-12 **und** FB-01 | der Code hat einen Fehlerzweig und eine Fehleransicht, README verspricht den Fallback; Absicht eindeutig. Zugleich `sicherheit.md` 4.5 (keine Zeitgrenze) |
| 3 | Verlassen beendet Engine und Verbindung nicht | ⚠ AK-28, AK-29 **und** FB-02 | `sicherheit.md` 4.2/4.3 (Verbindungslimit, Datenvolumen); der eigene Kommentar in `MultiviewSession` nennt die Lücke |
| 4 | libVLC 3.0.21 für Streams beliebiger Hosts | ⚠ AK-35 **und** FB-03 | `sicherheit.md` 4.4 (unvertraute Inhalte); veröffentlichte Lücken mit Streams als Angriffsweg |
| 5 | README-Hinweis in der Fehleransicht | ⚠ AK-13 **und** FB-04 | die README beschreibt den Hinweis nur ohne VLCKit; der Code zeigt ihn nach Endung — Absicht klar, Umsetzung falsch (DS-06) |
| 6 | Website: HUD für jede Taste | FB-05 | Zielmodus-Regel „Website verspricht, Code tut es nicht" |
| 7 | Vollbild im falschen Fenster, Verstimmung durch grünen Knopf | ⚠ AK-23, AK-24 **und** FB-06 | Kommentar nennt das Fenster des Players als Ziel; nicht sicherheitsrelevant, aber Absicht eindeutig. AS-03 nur über die Aktion ausgelöst, echter Klick offen |
| 8 | iPhone immer Querformat rechts, zurück immer Hochformat | ⚠ AK-25 + OF-03 | Kommentar sagt nur „Querformat anfordern"; ob rechts und die Rückkehr ins Hochformat gewollt sind, ist nicht ableitbar; kein Sicherheitspunkt (AS-04) |
| 9 | Englische Systemtexte in der Fehleransicht | reguläres Kriterium AK-06 + OF-01 | wie B01 OF-06; keine Adresse oder Zugangsdaten im Text (AK-31), daher kein Befund |
| 10 | ↓ hebt Stumm auf | reguläres Kriterium AK-17 + OF-02 | Protokollkommentar `PlaybackEngine.swift:55` beschreibt „hebt Stummschaltung bei Werten > 0 auf" als gewollt; ob das für „leiser" gelten soll, ist nicht ableitbar |
| 11 | Warnton bei unbelegten Tasten | reguläres Kriterium AK-18 | Standardverhalten von macOS; der Code unterdrückt ihn laut Kommentar bewusst nur für belegte Tasten |
| 12 | Zugangsdaten im Pfad jeder Stream-Anfrage | reguläres Kriterium AK-32 | verlangt das Xtream-Protokoll; Klartextspeicherung und HTTP-Zwang sind in B01 behandelt |
| 13 | Adressen mit Zugangsdaten im Log des Test-Hosts | EC-10, kein Befund | betrifft nur `xcodebuild test` auf Entwicklerrechnern mit erfundenen Daten; im normalen App-Lauf belegt sauber (AK-33) |
| 14 | Hintergrundwiedergabe ohne Zeitgrenze, VLC ohne Audio-Sitzung | reguläres Kriterium AK-30 + OF-05 | `Info.plist:62` kommentiert Hintergrund-Audio als gewollt; für VLC nicht ableitbar und ohne Ton nicht prüfbar |
| 15 | Kein Ende-Zustand bei VOD | EC-04, keine offene Frage | VOD ist laut PRD nicht im Scope; bei Live-TV tritt der Fall nicht auf |
| 16 | `file://` und Ziele im lokalen Netz aus Playlists | Teil von FB-03, kein eigener Befund | allein harmlos (lokale Wiedergabe), relevant als Verstärker einer libVLC-Lücke |
| 17 | Fehlende Tests für Zustände, Fehler, Freigabe, Vollbild, Tastatur | kein Fehlbestand, Hinweis in `design.md` | Testabdeckung ist kein beobachtbares Verhalten (wie B07 Nr. 15) |
