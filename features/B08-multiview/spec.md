# B08 · Multiview — Spezifikation

Status: `rekonstruiert` · Stand: `c01f1cf` + Reparatur B01 (2026-09-16) · Rekonstruktion aus dem Code (sdd-erfassen), erstellt 2026-09-16

> **Rekonstruiert, nicht geplant.** Beschrieben ist, was der Code **tut**, und zwar auf dem Stand `c01f1cf`
> einschließlich der noch nicht committeten Reparatur von B01 (eingefrorene Kopie vom 2026-09-16). Die
> B01-Reparatur hat in B08 genau eine Stelle geändert: `MultiviewSession.add` lädt nicht mehr
> `Channel.streamURL`, sondern fragt den `StreamURLResolver`. Bei Xtream kommen Benutzername und Passwort
> dabei aus dem Schlüsselbund; fehlen sie, entsteht keine Kachel. Die Multiview-Oberfläche
> (`MultiviewScreen`, `MultiviewTile`, ⊞-Button) ist seit `d5c5e58` (2026-06-23) bis auf einen Kommentar
> (`54550b2`) unverändert und steckt so im ausgelieferten Release `v1.1`. Die parallel laufende Reparatur von B09 ist nicht berücksichtigt.
> Kriterien mit ⚠ beschreiben fragwürdiges Ist-Verhalten. Sie stehen bewusst als Kriterium hier, damit
> `sdd-qa` sie reproduziert. Wo sie als Fehler eingestuft sind, steht ein Verweis auf *Fehlbestand*.
>
> **Wie belegt.** Am 2026-09-16 **ausgeführt** in einer Kopie im Scratchpad: eigene Bundle-ID
> `lu.daumedia.MikaPlusPlayer.b08probe`, eigenes DerivedData, Sparkle-Feed abgeschaltet,
> In-Memory-Datenbank, Schlüsselbund nur im Test-Dienst `lu.daumedia.MikaPlusPlayer.xtream.tests.<UUID>`
> (am Ende geleert). Ein lokaler Mock auf `127.0.0.1:18908` spielte `player_api.php`, eine M3U-Datei,
> MPEG-TS im Echtzeittakt und HLS live, dazu 404, harten Abbruch, hängende Verbindungen und ein
> Verbindungslimit je Benutzer. Zwei Wege:
> 1. **XCTest** im Test-Host der Mac-App gegen `MultiviewSession` mit echten Engines (T01–T08): Belegung,
>    Fokus, Stummschaltung am eigentlichen Player (`AVPlayer.isMuted`, VLC `audio.isMuted`), Freigabe der
>    Engines, offene Verbindungen am Mock.
> 2. **Zeitgesteuerter Lauf der App** mit den echten Szenen `WindowGroup` und `Window("Multiview")`
>    (S1–S15). Bedient mit synthetischen Maus- und Tastaturereignissen an die eigenen Fenster: ⊞-Button,
>    Kachelklick, X-Knöpfe, Layout-Picker, roter Fensterknopf, Menü „New Window" und „Window › Multiview".
>    Aufgenommen wurden nur die App-Fenster. Löschen und Aktualisieren liefen über denselben
>    `PlaylistImporter`-Aufruf wie das Kontextmenü.
>
> **Ohne Ton.** Alle Teststreams hatten **keine Tonspur** (`ffmpeg -an`). Nur T04 brauchte eine Tonspur,
> um den VLC-Audiokanal zu prüfen: digitale Stille (`anullsrc`, `volume=0`, gemessen −91 dB) **und**
> Engine-Lautstärke 0. Der Audio-Fokus ist ausschließlich über den Zustand belegt, nie über das Gehör.
> Den macOS-Warnton hat die Sonde abgefangen: `-[NSResponder noResponderFor:]` ruft bei `keyDown:` laut
> Disassembly `NSBeep()`. Die Sonde hat die Methode durch eine Zählung ersetzt; es erklang kein Ton.
>
> **Nicht bedient:** echte Klicks und Tastendrücke eines Menschen, VoiceOver, natives Vollbild über den
> grünen Knopf, Minimieren mit anschließendem ⊞, Wiederherstellung von Fenstern nach Neustart (die Läufe
> nutzten `-ApplePersistenceIgnoreState YES`), echte Anbieter und iOS (dort gibt es Multiview nicht).
> Solche Kriterien tragen den Vermerk *(gelesen)*.
>
> **Evidenz:** `qa-erfassung/sonde-protokoll.txt` (alle Läufe, Absturzauszüge, Mock-Protokoll),
> `qa-erfassung/sonde.patch` (Sonden-Code der Kopie), Fensteraufnahmen `qa-erfassung/mac-01` bis `mac-18`.
> Die Kopie im Scratchpad ist gelöscht.
>
> **Messumgebung für alle Zeitangaben:** Apple M3 Max, macOS 27.0 (26A428), **Debug-Build**, parallel
> liefen Builds anderer Features. Die Zahlen sind **Ist-Werte zur Orientierung**, keine Zielwerte.

## Zweck

Auf dem Mac laufen bis zu vier Sender gleichzeitig in einem eigenen Fenster „Multiview", als ein großer
Stream mit kleinen Kacheln oder als gleich großes Raster. Ton hat immer nur der fokussierte Stream; ein
Klick auf eine Kachel verlegt den Ton dorthin.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| B04 Senderliste | rekonstruiert | trägt den ⊞-Button in jeder Senderkarte (B04 AK-03) |
| B06 Wiedergabe | rekonstruiert | liefert die Engines (AVKit für HLS, VLC für MPEG-TS), ihre Zustände und Fehlermeldungen. B06 AK-05 bis AK-12 gelten in jeder Kachel mit |
| B01 Xtream-Login | building (Reparatur 1 fertig) | `StreamURLResolver` und Schlüsselbund: Xtream-Kacheln bekommen ihre Adresse mit Zugangsdaten erst beim Hinzufügen |

Berührt, ohne Abhängigkeit: B05 (derselbe ⊞-Button im Favoriten-Tab), B03 (Löschen und Aktualisieren
ersetzen Sender, die im Multiview laufen; B03 AK-28, FB-05), B07 (im Multiview gibt es bewusst kein
Bild-in-Bild; B07 AK-12), B10 (Website bewirbt Multiview).

## User Stories

- **US-01** · Als Mac-Nutzer möchte ich mehrere Sender gleichzeitig sehen, z. B. parallele Spiele, damit ich
  nichts verpasse.
- **US-02** · Als Nutzer möchte ich nur einen Stream hören und den Ton mit einem Klick wechseln, damit vier
  Streams nicht durcheinander tönen.
- **US-03** · Als Nutzer möchte ich zwischen einem großen Hauptbild und einem gleichmäßigen Raster wählen.
- **US-04** · Als Nutzer möchte ich einzelne Streams entfernen oder das Fenster schließen, und dann soll
  auch nichts mehr laufen.

## Nicht im Scope

- Engine-Wahl nach Dateiendung, Lade- und Fehlerverhalten der Engines als solche → **B06** (AK-05 bis
  AK-12, FB-01). Hier nur, wie eine **Kachel** das zeigt.
- Die Senderkarte selbst (Logo, Name, Gruppe, Tipp öffnet den Player) → **B04**; Stern und Favoriten-Tab →
  **B05**. Hier nur der ⊞-Button.
- Löschen und Aktualisieren einer Playlist → **B03**. Hier nur, was laufende Kacheln dabei tun (AK-27,
  AK-28).
- Bild-in-Bild → **B07**. Im Multiview gibt es keinen Knopf, keine Taste und keinen automatischen Start
  (B07 AK-12).
- Aussagen der Website über Multiview → **B10**; der Widerspruch zum Bildwechsel steht hier als FB-02.
- Gibt es nicht: Multiview auf iOS, mehr als vier Streams, Lautstärke, Pause oder „Erneut versuchen" je
  Kachel, Umsortieren, Speichern einer Belegung, Tastenkürzel, eigener Vollbild-Knopf.

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. Nötig sind ein Mac, eine Xtream-Playlist (Standardformat
MPEG-TS) und eine M3U-Playlist mit HLS- und `.ts`-Adressen auf einem lokalen Server, der Verbindungen
protokolliert, 404 liefert, Verbindungen abbricht und ein Verbindungslimit je Benutzer setzen kann.
„Stumm" und „mit Ton" meint den Zustand des Players, nicht das Gehör.

### ⊞-Button und Fenster

- **AK-01** · Angenommen, eine Senderliste oder der Favoriten-Tab ist auf dem Mac offen, dann steht in jeder
  Senderkarte links neben dem Stern ein grauer ⊞-Button mit dem Tooltip „Zu Multiview hinzufügen". Wird er
  angeklickt, dann erscheint der Sender im Fenster „Multiview": Das Fenster öffnet sich bzw. kommt nach
  vorn, und der Stream beginnt zu laden. Die Liste bleibt stehen, ein Player öffnet sich **nicht**.
  *(ausgeführt mit synthetischem Klick in Senderliste und Favoriten-Tab, Bilder `mac-01`, `mac-08`)*
- **AK-02** · Angenommen, das Fenster „Multiview" wird zum ersten Mal geöffnet, dann ist es 1280 × 720 pt
  groß und heißt „Multiview". Eine vom Nutzer geänderte Größe und Lage merkt sich macOS über den Neustart
  hinaus. *(ausgeführt: erster Lauf 1280 × 720, im nächsten Lauf die zuletzt gesetzten 960 × 600)*
- **AK-03** · Angenommen, das Multiview ist leer, wenn der erste Sender hinzugefügt wird, dann ist er
  fokussiert und **hat Ton**. Jeder weitere Sender kommt **stumm** dazu, der Fokus bleibt, wo er ist.
  *(ausgeführt: Engine-Flag und `AVPlayer.isMuted` bzw. VLC `audio.isMuted`, T01, S1)*
- **AK-04** · Angenommen, vier Streams laufen, dann ist der ⊞-Button in **allen** Senderkarten aller
  Hauptfenster abgeblendet (30 % Deckkraft), sein Tooltip lautet „Multiview voll (max. 4)", und ein fünfter
  Sender kommt nicht hinzu; es entsteht keine Verbindung für ihn. *(ausgeführt T01, S1, Bilder `mac-03`,
  `mac-07`)*
- **AK-05** ⚠ · Angenommen, vier Streams laufen, wenn auf den abgeblendeten ⊞-Button geklickt wird, dann
  öffnet sich der **Player** dieses Senders im Hauptfenster, **mit Ton**, und baut eine fünfte Verbindung
  zum Anbieter auf. Im Multiview hat der fokussierte Stream weiter Ton. *(ausgeführt S1: Fenstertitel
  wechselt auf den Sendernamen, fünf offene Verbindungen, Bild `mac-04`; als Fehler eingestuft → FB-03)*
- **AK-06** ⚠ · Angenommen, derselbe Sender wird zweimal hinzugefügt, dann entstehen zwei Kacheln mit
  gleichem Namen, zwei Engines und zwei Verbindungen. Es gibt keinen Hinweis. *(ausgeführt T03, S7; Absicht
  unklar → OF-01)*
- **AK-07** ⚠ · Angenommen, einer Xtream-Playlist fehlen die Zugangsdaten im Schlüsselbund (z. B. nach
  Wiederherstellung auf einem neuen Gerät), wenn ⊞ angeklickt wird, dann kommt kein Stream hinzu, das Fenster
  „Multiview" öffnet sich aber trotzdem und zeigt den Leerzustand bzw. die bisherigen Kacheln. Eine Meldung
  gibt es nicht. *(ausgeführt T05, S13, Bild `mac-14`; Absicht unklar → OF-02, gleich B01 OF-11)*
- **AK-08** · Angenommen, das Multiview ist leer, dann zeigt das Fenster auf schwarzem Grund ein Symbol,
  „Kein Stream im Multiview" und „Füge in der Senderliste mit dem ⊞-Button Sender hinzu, um sie hier
  gleichzeitig zu sehen.". Das Fenster schließt sich nicht von selbst, wenn die letzte Kachel entfernt wird.
  *(ausgeführt S13, Bild `mac-13`)*
- **AK-09** · Angenommen, die App läuft, dann steht im Menü „Window" ein Eintrag „Multiview" (ohne
  Tastenkürzel). Er öffnet das Fenster auch ohne Streams, dann mit Leerzustand. Ein zweites
  Multiview-Fenster gibt es nie. *(ausgeführt S13: Menü „Minimize, Zoom, Multiview, Bring All to Front,
  Playlists")*

### Layout

- **AK-10** · Angenommen, das Layout ist „Fokus", dann füllt der fokussierte Stream das ganze Fenster bis
  unter die Titelleiste und hat einen 2 pt breiten Rahmen in Akzentfarbe. Die übrigen Streams stehen als
  240 × 135 pt große, abgerundete Kacheln mit Schatten übereinander oben rechts, 16 pt vom Rand, 8 pt
  Abstand, in der Reihenfolge des Hinzufügens. Jede Kachel zeigt oben links ein Etikett mit Lautsprecher und
  Sendernamen (fokussiert: `speaker.wave.2.fill`, akzentgetönt; sonst `speaker.slash.fill`, grau) und oben
  rechts einen runden X-Knopf mit dem Tooltip „Stream entfernen". *(ausgeführt, Bild `mac-05`)*
- **AK-11** · Angenommen, das Layout ist „Raster", dann sind alle Kacheln gleich groß, 4 pt Abstand: eine
  Kachel füllt das Fenster, zwei stehen nebeneinander, drei und vier im 2 × 2-Raster (bei drei bleibt unten
  rechts ein leeres Feld). Der fokussierte Stream hat den Akzentrahmen. *(ausgeführt für 1 und 4 Streams,
  Bilder `mac-06`, `mac-12`; 2 und 3 Streams gelesen)*
- **AK-12** · Angenommen, das Fenster ist offen, dann sitzt mittig in der Titelleiste ein segmentierter
  Umschalter „Fokus | Raster". Er ist deaktiviert, solange weniger als zwei Streams laufen, und aktiv ab
  zwei. Das gewählte Layout bleibt beim Schließen und erneuten Öffnen des Fensters erhalten, solange die App
  läuft; nach einem Neustart gilt „Fokus". *(ausgeführt: Zustand des Umschalters bei 0, 1, 2, 3, 4 Streams,
  Umschalten per Klick, Bild `mac-02`; Erhalt über das Schließen gelesen, Neustart gelesen)*
- **AK-13** ⚠ · Angenommen, im Raster wird auf einen Stream reduziert, dann bleibt das Raster eingestellt
  und der Umschalter deaktiviert: Zurück zu „Fokus" geht erst wieder ab zwei Streams. Das Schließen des
  Fensters in diesem Zustand bringt die App zum Absturz (AK-23). *(ausgeführt S14, Bild `mac-12`; als
  Fehler eingestuft → FB-01)*

### Fokus und Ton

- **AK-14** · Angenommen, mindestens zwei Streams laufen, wenn auf eine **nicht** fokussierte Kachel geklickt
  wird (Fokus: kleine Kachel; Raster: jede andere Kachel), dann wird sie fokussiert: Nur sie hat Ton, alle
  anderen sind stumm, Etikett und Rahmen wandern mit, und im Fokus-Layout tauscht sie mit dem großen Stream.
  Ein Klick auf den fokussierten Stream bewirkt nichts. *(Fokus-Layout per Klick ausgeführt S10; Raster
  gelesen; Tonzustand ausgeführt T02, T04)*
- **AK-15** ⚠ · Angenommen, im Fokus-Layout läuft der neu fokussierte Stream über VLC (Adresse auf `.ts`, also
  jede Xtream-Playlist im Standardformat), wenn der Fokus per Klick wechselt, dann ist die große Fläche
  **schwarz**. Der Stream mit Ton ist nirgends zu sehen; das bleibt so (beobachtet 15 s und nach Ändern der
  Fenstergröße), bis das Layout einmal auf „Raster" und zurück gestellt wird. Über AVKit (HLS) erscheint das
  Bild korrekt. *(ausgeführt S4, S10, S11 mit Schwarzanteil 100 % gegenüber 0 % bei HLS in S12; Bilder
  `mac-09`, `mac-10`; als Fehler eingestuft → FB-02)*
- **AK-16** ⚠ · Angenommen, im Fokus-Layout laufen mindestens zwei Streams, wenn der Nutzer auf das X des
  großen Streams klickt, dann liegt dieses X unter der ersten kleinen Kachel: Der Klick fokussiert die kleine
  Kachel, statt den großen Stream zu entfernen. Weitere Klicks an dieselbe Stelle schalten den Fokus hin und
  her. Den fokussierten Stream entfernt man erst, wenn er allein ist, oder im Raster. *(ausgeführt S4, sechs
  Klicks, Fokus 0 ↔ 1; Bild `mac-11`; als Fehler eingestuft → FB-04)*
- **AK-17** · Angenommen, Streams werden entfernt, dann gilt für den Ton, gemessen am Engine-Flag und am
  eigentlichen Player:
  - Entfernen **vor** dem fokussierten Stream: Der Fokus bleibt beim selben Stream.
  - Entfernen **des** fokussierten Streams: Der Stream, der an seine Stelle rückt, bekommt den Ton; war es der
    letzte in der Reihe, der davor.
  - Entfernen **nach** dem fokussierten Stream: nichts ändert sich.
  - Es hat immer genau ein Stream Ton, solange einer läuft; nach dem Leeren hat der nächste hinzugefügte Ton.
  *(ausgeführt T02, T04)*
- **AK-18** · Angenommen, im Multiview und im Player eines Hauptfensters läuft je ein Stream, dann haben
  beide Ton. Der Ton-Fokus gilt nur innerhalb des Multiview-Fensters. *(ausgeführt S1 über den Zustand:
  Multiview-Fokus und Player nicht stumm; Streams ohne Tonspur → OF-05)*

### Entfernen, Schließen, Lebensdauer

- **AK-19** · Angenommen, eine Kachel wird über ihr X entfernt, dann verschwindet sie, ihre Engine wird
  freigegeben und ihre Verbindung endet: MPEG-TS-Verbindungen waren nach 2 s geschlossen, HLS-Abrufe endeten
  innerhalb von 5 s. Das gilt auch für eine Kachel, die noch lädt. *(ausgeführt T07, S2, S13)*
- **AK-20** · Angenommen, das Fenster steht im Layout „Fokus", wenn es über den roten Knopf geschlossen wird,
  dann ist das Multiview danach leer: Alle Engines sind sofort freigegeben, alle Verbindungen nach spätestens
  3 s geschlossen, der ⊞-Button ist in allen Hauptfenstern wieder aktiv. Der nächste ⊞-Klick öffnet das
  Fenster mit diesem einen Stream. *(ausgeführt S1)*
- **AK-21** · Angenommen, mehrere Hauptfenster sind offen (Menü „New Window"), dann teilen sie sich ein
  Multiview: Was im einen Fenster hinzugefügt wird, macht den ⊞-Button im anderen abgeblendet, und das
  Schließen des Multiview-Fensters leert es für alle. *(ausgeführt S1, Bild `mac-07`)*
- **AK-22** · Angenommen, das Multiview-Fenster wird minimiert oder alle Hauptfenster werden geschlossen,
  dann laufen die Streams mit ihren Verbindungen weiter. *(ausgeführt S1)*
- **AK-23** ⚠ · Angenommen, das Layout ist „Raster", dann **stürzt die App ab** („Fatal error: Index out of
  range", `MultiviewScreen.swift:79`), sobald die Zahl der Rasterzeilen sinkt:
  - beim Schließen des Fensters, mit einem wie mit vier Streams;
  - beim Entfernen einer Kachel per X von 3 auf 2 und von 1 auf 0 Streams.
  Kein Absturz beim Entfernen von 4 auf 3 und von 2 auf 1, beim Beenden der App mit offenem Raster und in
  jedem Fall im Fokus-Layout. Mit dem Absturz enden alle Fenster und ein laufender Player.
  *(ausgeführt S1 Lauf 3, S2, S3, S9, S14 mit Absturzberichten; Beenden S15; als Fehler eingestuft → FB-01)*
- **AK-24** · Angenommen, die App wird neu gestartet, dann ist das Multiview leer; es wird nichts über
  Belegung, Fokus oder Layout gespeichert. *(gelesen)*

### Fehler je Kachel

- **AK-25** · Angenommen, ein Stream über AVKit scheitert beim Laden (z. B. HTTP 404, Port geschlossen),
  dann zeigt seine Kachel über dem schwarzen Bild „Wiedergabe fehlgeschlagen" mit einem englischen
  Systemtext, z. B. „The requested URL was not found on this server." oder „Could not connect to the
  server.". Einen Knopf zum erneuten Versuch gibt es nicht. Die anderen Kacheln laufen weiter.
  *(ausgeführt T06, S8, Bild `mac-15`; Sprache → B01 OF-06)*
- **AK-26** ⚠ · Angenommen, ein Stream über VLC scheitert, dann zeigt die Kachel **keinen** Fehler:
  - HTTP 404 oder Port geschlossen: endlos die Ladeanzeige.
  - Verbindung bricht während der Wiedergabe ab: das letzte Bild bleibt stehen.
  - Server antwortet nie: Schwarz ohne Ladeanzeige (Zustand „spielt").
  Ein HLS-Stream über AVKit, dessen Segmente nach dem Start mit 404 enden, bleibt ebenso ohne Meldung.
  *(ausgeführt T06, S8, Bild `mac-15`; Ursache in den Engines → B06 FB-01)*

### Laufende Kacheln beim Löschen und Aktualisieren der Playlist

- **AK-27** ⚠ · Angenommen, Sender einer Playlist laufen im Multiview (Fokus oder Raster), wenn die Playlist
  gelöscht wird, dann stürzt nichts ab, und die Kacheln laufen mit Namen weiter. Die Verbindungen zum
  Anbieter bleiben offen, bei Xtream mit Benutzername und Passwort im Pfad, obwohl der Schlüsselbund-Eintrag
  schon entfernt ist. Erst X oder Schließen beendet sie. *(ausgeführt S5, S6, Bild `mac-17`; als Fehler
  eingestuft → FB-05)*
- **AK-28** ⚠ · Angenommen, Sender einer Playlist laufen im Multiview, wenn die Playlist aktualisiert wird und
  der Anbieter neue `stream_id`s liefert, dann spielen die Kacheln weiter die **alte** Adresse. In der
  Senderliste zeigt ⊞ wieder „Zu Multiview hinzufügen"; ein Klick fügt denselben Sender als weitere Kachel mit
  neuer Adresse und weiterer Verbindung hinzu. Der Sender steht dann zweimal im Multiview. *(ausgeführt S7,
  Bild `mac-18`; als Fehler eingestuft → FB-05)*

### Tastatur

- **AK-29** · Angenommen, das Multiview-Fenster ist aktiv, dann hat es keine Tastatursteuerung: Leertaste, M,
  F, P, ↑, ↓, Esc, 1 und Tab bewirken nichts, und macOS spielt bei jeder dieser Tasten den Warnton. Es gibt
  kein Tastenkürzel, das Multiview öffnet. *(ausgeführt S1: jeder `keyDown` erreichte das Ende der
  Responder-Kette; Warnton abgefangen, nicht gehört; Wunsch nach Tasten → OF-04)*

### Datenschutz und Missbrauchsschutz

Fragenkatalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog). Jede Frage hat ein Kriterium, ein
„trifft nicht zu, weil …" oder einen Eintrag im *Fehlbestand*.

- **AK-30** ⚠ · Angenommen, N Kacheln laufen, dann hält die App N gleichzeitige Verbindungen zum Anbieter, bei
  Xtream jede mit Benutzername und Passwort im Pfad (`/live/<benutzer>/<passwort>/<id>.ts`); ein Player im
  Hauptfenster kommt als weitere hinzu. Die App prüft kein Verbindungslimit des Abos und weist nirgends
  darauf hin. *(ausgeführt T05: 1, 2, 3, 4 offene Verbindungen nach 1 bis 4 Kacheln; S1: fünf mit Player;
  als Fehler eingestuft → FB-06)*
- **AK-31** ⚠ · Angenommen, das Abo erlaubt nur eine Verbindung und der Anbieter weist weitere mit HTTP 403
  ab, wenn vier Xtream-Sender (MPEG-TS) hinzugefügt werden, dann spielt die erste Kachel, die drei anderen
  zeigen endlos die Ladeanzeige ohne Meldung. VLC fragt je Kachel viermal innerhalb von rund 20 ms an und gibt
  dann auf. *(ausgeführt T05, S8, Bild `mac-16`; als Fehler eingestuft → FB-06)*
- **AK-32** · Angenommen, eine Kachel läuft oder scheitert, dann zeigt sie nur den Sendernamen und gegebenenfalls
  eine Fehlermeldung, weder die Adresse noch Benutzername oder Passwort. *(ausgeführt für die Meldungen aus
  AK-25 und AK-26 mit M3U-Adressen; Xtream-Adressen ergeben dieselben Engine-Texte ohne Adresse, gelesen)*
- **AK-33** · Angenommen, Kacheln laufen, scheitern oder werden entfernt, dann schreibt die App dazu nichts
  ins Protokoll. *(ausgeführt: In der Standardfehlerausgabe aller App-Läufe standen weder Passwort noch
  Mock-Adresse; `log show` der letzten Stunde fand das Passwort nicht, private Daten sind dort jedoch
  standardmäßig geschwärzt; kein `print`, `Logger`, `os_log`, `NSLog` in `Sources/`. Vorbehalt aus B01:
  CFNetwork kann Fehleradressen bei aktivem Private-Data-Logging selbst protokollieren)*
- **AK-34** · Angenommen, das Multiview wurde benutzt, dann liegt davon nichts in der Datenbank, im
  Schlüsselbund oder in eigenen Einstellungen der App. Nur Größe und Lage des Fensters merkt sich macOS
  (AK-02). *(gelesen; Fenstergröße ausgeführt)*

#### Katalog, Frage für Frage

| # | Katalogfrage | Antwort für B08 |
|---|---|---|
| 1.1 | Welche personenbezogenen Daten? | Keine neuen. Gegenüber dem Anbieter: IP-Adresse und bis zu vier gleichzeitig abgerufene Sender, bei Xtream Benutzername und Passwort in jeder Verbindung (AK-30). Auf dem Bildschirm: welche Sender der Nutzer gleichzeitig schaut, in Bildschirmfotos und bei geteiltem Bildschirm sichtbar |
| 1.2 | Besondere Kategorien? | Trifft nicht zu, weil B08 nichts speichert oder überträgt, was nicht schon B01 bis B06 berühren. Gleichzeitig geschaute Sender können Rückschlüsse zulassen (Religion, Herkunft, Politik); sie verlassen das Gerät nur als Abruf beim Anbieter |
| 1.3 | Wo gespeichert, wie lange? | Nirgends dauerhaft (AK-24, AK-34). Belegung und Engines leben im Arbeitsspeicher bis X, Schließen des Fensters oder Ende der App. Nach dem Löschen einer Playlist leben ihre Kacheln samt Zugangsdaten in der Adresse weiter → FB-05 |
| 1.4 | Landen sie in Logs? | App-seitig nein (AK-33, mit Vorbehalt) |
| 2.1 | Welche externen Dienste? | Nur die Stream-Hosts der Sender: bei Xtream der Anbieter, bei M3U beliebige Hosts. Je Kachel eine eigene Verbindung (AK-30). Kein KI-Dienst, keine Analyse, kein Fehler-Tracking |
| 2.2 | Was wird übertragen, was vorher entfernt? | Die abspielbare Adresse. Bei Xtream verlangt das Protokoll Benutzername und Passwort im Pfad; entfernt wird nichts. Das HTTP für Adressen ohne `https` gehört zu B01 |
| 2.3 | Standort des Dienstes, AV-Vertrag? | Trifft nicht zu, weil der Nutzer den Anbieter selbst wählt und daumedia nichts empfängt |
| 2.4 | Training mit dem Payload? | Trifft nicht zu, weil kein KI-Dienst beteiligt ist |
| 3.1 | Wer darf sehen, ändern, löschen? | Der lokale Nutzer; alle Hauptfenster teilen ein Multiview (AK-21). Sehen kann jeder mit Blick auf den Bildschirm |
| 3.2 | Erzwungen in DB oder Anwendung? | Trifft nicht zu, weil B08 keine Daten mit Zugriffsregeln hat |
| 3.3 | Fremde ID? | Trifft nicht zu, weil es keine per ID abrufbaren Ressourcen und keinen Server der App gibt |
| 3.4 | Rollen? | Trifft nicht zu, weil die App keine Konten und keine Rollen hat |
| 4.1 | Rate Limit auf Anmeldung u. ä. | Trifft nicht zu, weil B08 keine Anmeldung hat. Verbindungsversuche je Kachel begrenzt nur VLC selbst (vier Versuche, AK-31) |
| 4.2 | Rate Limit für Kostenpflichtiges | Für den Betreiber trifft das nicht zu. Beim Anbieter zählen gleichzeitige Verbindungen: bis zu vier Kacheln plus Player plus Kacheln aus AK-05, AK-06, AK-28, ohne Prüfung und ohne Hinweis → **FB-06**; zusätzliche Verbindungen durch FB-03 und FB-05 |
| 4.3 | Kosten je Aufruf | Für den Nutzer Datenvolumen: vier Streams gleichzeitig, auch minimiert und ohne Hauptfenster weiter (AK-22). Keine Zeitgrenze |
| 4.4 | Uploads: Größe, Typ, Inhalt | Trifft nicht zu, weil B08 keine Dateien annimmt. Unvertraute Medien parsen die Engines → B06 FB-03, im Multiview bis zu viermal gleichzeitig |
| 4.5 | Wo greift das Limit? | Nur in der App: höchstens vier Kacheln (AK-04). Ein Anbieterlimit wird nicht berücksichtigt → FB-06 |
| 5.1 | Konto selbst löschen? | Trifft nicht zu, weil B08 kein Konto und keine Daten hat |
| 5.2 | Was wird dabei gelöscht? | Beim Löschen einer Playlist (B03) bleiben ihre laufenden Kacheln samt Verbindung mit Zugangsdaten bestehen → **FB-05** |
| 5.3 | Was bleibt, und warum? | Nichts dauerhaft; die weiterlaufenden Kacheln aus FB-05 bis X, Schließen oder App-Ende, ohne Begründung |
| 5.4 | E-Mail-Adresse wieder frei? | Trifft nicht zu, weil die App keine Registrierung hat |
| 5.5 | Datenexport? | Trifft nicht zu, weil B08 keine Daten erzeugt |
| 6.1 | Welche Schlüssel braucht das Feature? | Keine eigenen. Xtream-Zugangsdaten liest `StreamURLResolver` aus dem Schlüsselbund (B01) |
| 6.2 | Welche dürfen zum Client? | Trifft nicht zu, weil es keinen Server gibt |
| 6.3 | Steht Echtes im Repository? | Nein. Die Multiview-Commits `d5c5e58` und `54550b2` enthalten keine Adressen oder Zugangsdaten; die Sonde benutzte nur `qa-user`/`qa-pass-b08` |
| 6.4 | Vorlagen `.env.example` / `Secrets.example.xcconfig` | Trifft nicht zu, weil B08 keine Build-Geheimnisse braucht |

## Edge Cases

Ist-Verhalten. „(ausgeführt)" heißt mit der Sonde belegt, „(gelesen)" heißt aus dem Code abgeleitet.

- **EC-01** · AVKit- und VLC-Kacheln gemischt → laufen nebeneinander, der Ton-Fokus wirkt auf beide gleich.
  *(ausgeführt T01, T02)*
- **EC-02** · Fokussierter Stream ohne Tonspur → Er ist „mit Ton" fokussiert, alle anderen bleiben stumm; zu
  hören ist nichts. *(ausgeführt T04)*
- **EC-03** · VLC-Kachel vor Wiedergabebeginn stumm geschaltet → Der VLC-Audiokanal übernimmt den Wert sofort,
  nicht erst beim Start, wie der Code-Kommentar annimmt. *(ausgeführt T04)*
- **EC-04** · Eine pausierte, aber nicht freigegebene Engine hält ihre Verbindung: VLC lässt die Verbindung
  offen und liest nicht weiter, AVKit ruft bei HLS die Playlist weiter ab. Im Multiview tritt das nicht auf,
  weil Entfernen und Schließen die Engines freigeben; `pause()` allein würde die Verbindung nicht beenden.
  *(ausgeführt T08, T07)*
- **EC-05** · Kachel, deren Server nie antwortet, wird entfernt → Engine frei, Verbindung zu. *(ausgeführt T07)*
- **EC-06** · Tooltip und Zustand des ⊞-Buttons aktualisieren sich in allen offenen Hauptfenstern ohne Neuladen,
  auch im Favoriten-Tab. *(ausgeführt S1)*
- **EC-07** · ⊞ bei minimiertem Multiview-Fenster → nicht geprüft; der Button ruft dieselbe Öffnen-Aktion.
  *(gelesen)*
- **EC-08** · Natives Vollbild über den grünen Fensterknopf → vorhanden, weil es ein eigenes Fenster ist;
  Verhalten der Kacheln darin nicht geprüft. *(gelesen)*
- **EC-09** · Neustart mit zuvor offenem Multiview-Fenster → Ob macOS das leere Fenster wiederherstellt, ist nicht
  geprüft. *(nicht ausgeführt)*
- **EC-10** · Kleines Fenster im Fokus-Layout mit drei kleinen Kacheln → Die Kacheln sind fest 240 × 135 pt;
  ob sie bei geringer Fensterhöhe überlaufen, ist nicht geprüft. *(gelesen)*
- **EC-11** · Langer Sendername → Etikett einzeilig, abgeschnitten. *(gelesen)*
- **EC-12** · HLS-Kacheln legen je einen nie benutzten Bild-in-Bild-Controller an (B07 EC-11). *(gelesen)*
- **EC-13** · Last von vier gleichzeitig dekodierten Streams → nicht gemessen. *(nicht ausgeführt)*
- **EC-14** · Nach dem Löschen einer Playlist wird im Multiview der Fokus gewechselt oder eine Kachel entfernt →
  kein Absturz; die Sender-Objekte der Kacheln haben keinen Kontext mehr, ihr Name ist weiter lesbar.
  *(ausgeführt S5, S6)*
- **EC-15** · Beenden der App (⌘Q) mit offenem Multiview im Raster → kein Absturz. *(ausgeführt S15)*

## Offene Fragen

Alle vom 2026-09-16. Entscheidung durch den Nutzer (Michael Ferreira), vor der Reparaturrunde nach der QA
von B08.

- **OF-01** · Soll derselbe Sender mehrfach ins Multiview dürfen (AK-06, AK-28)? Heute entstehen doppelte
  Kacheln und doppelte Verbindungen ohne Hinweis.
- **OF-02** · Soll ⊞ bei fehlenden Xtream-Zugangsdaten eine Meldung zeigen, statt ein leeres Fenster zu öffnen
  (AK-07)? Deckungsgleich mit B01 OF-11.
- **OF-03** · Soll die App das Verbindungslimit des Abos kennen (`user_info.max_connections` liefert das Panel
  bei der Anmeldung mit) und vor bzw. beim Überschreiten warnen? Die fehlende Rückmeldung selbst ist FB-06.
  *Stand 2026-09-28 (Build B08, BUG-06):* Die Rückmeldung ist gebaut – eine abgelehnte Kachel zeigt die Meldung der
  Engine und, solange ein anderer Stream desselben Anbieters (Host und Port) läuft, zusätzlich „Möglicherweise erlaubt
  dein Abo nicht so viele Streams gleichzeitig.". `max_connections` wird **nicht** ausgewertet, die Zahl der Kacheln
  nicht begrenzt und vorab nicht gewarnt; das bleibt die Entscheidung dieser Frage. Ob der Hinweis auch erscheinen
  soll, wenn der Player im Hauptfenster die Verbindung belegt (die Kachel sieht ihn nicht), gehört mit dazu.
- **OF-04** · Soll das Multiview Tasten haben (z. B. 1–4 für den Fokus, Leertaste, M), oder zumindest keinen
  Warnton erzeugen (AK-29)? Die Tastenliste der Website nennt kein Fenster und lässt offen, ob sie hier gilt.
- **OF-05** · Soll der Ton-Fokus auch den Player im Hauptfenster einschließen (AK-18, AK-05)? Die Website
  verspricht „Only the focused stream plays sound, so four matches at once do not turn into noise".
- **OF-06** · Soll eine gescheiterte Kachel „Erneut versuchen" anbieten wie der Player (AK-25, AK-26)?
- **OF-07** · Soll das gewählte Layout (und ggf. die Belegung) einen Neustart überdauern (AK-24)?

Aus der Reparatur (Build B08, 2026-09-28) — ohne Rückfrage entschieden, zur Bestätigung durch den Nutzer:

- **OF-08** · Lage der kleinen Kacheln im Fokus-Layout (BUG-04): Sie beginnen jetzt **46 pt** unter dem oberen
  Inhaltsrand (8 pt Innenabstand + 30 pt X-Knopf + 8 pt) statt 16 pt, damit das X des großen Streams frei liegt;
  rechts bleiben 16 pt, dazwischen 8 pt. AK-10 nennt noch „16 pt vom Rand". Bestätigen oder eine andere Lösung wählen
  (z. B. X des großen Streams links oder unten).
- **OF-09** · Umschalter „Fokus | Raster" mit weniger als zwei Streams (BUG-01): Ist „Raster" gewählt, bleibt er aktiv
  (Weg zurück zu „Fokus"); ist „Fokus" gewählt, bleibt er wie bisher gesperrt. AK-12 nennt noch „deaktiviert, solange
  weniger als zwei Streams laufen". Alternative: beim Unterschreiten von zwei Streams automatisch auf „Fokus" – dann
  ginge die Wahl „Raster" beim Entfernen verloren.
- **OF-10** · Mindestgröße des Fensters (BUG-10): Inhalt mindestens **640 × 483 pt** (mit Titelleiste 640 × 535 pt) –
  so passen drei kleine Kacheln samt Abständen unter die Leiste des großen Streams. Bestätigen.
- **OF-11** · Frist für hängende AVKit-Kacheln (BUG-07, HLS-Teil): Eine Kachel, deren Wiedergabezeit **30 s** lang
  nicht weiterläuft (z. B. Live-HLS, dessen Segmente mit 404 enden – AVKit gibt dann nie auf), zeigt „Die Verbindung
  zum Sender wurde unterbrochen." und lädt nicht mehr nach. 30 s wie die Hängerfrist der VLC-Engine (B06 OF-08).
  Gilt **nur für Kacheln**; der Player (B06) behält das Verhalten von AVKit (Standbild ohne Ende). Soll der Player
  dieselbe Frist bekommen, und passt die Länge?
- **OF-12** · Abgeblendeter ⊞ (BUG-03): Der Knopf ist bei vollem Multiview nur noch abgeblendet (30 % Deckkraft) und
  wirkungslos, nicht mehr „deaktiviert" – sonst fiele der Klick an die Karte. Bedienungshilfen melden ihn damit nicht
  mehr als deaktiviert; der Tooltip „Multiview voll (max. 4)" bleibt. Reicht das, oder soll der Zustand zusätzlich
  angesagt werden?
- **OF-13** · Ladeanzeige der Kachel (B06 OF-12): Kacheln zeigen weiter den grauen System-Ladekreis, der Player seit
  B06 BUG-09 einen weißen. Nicht Teil des Fehlerauftrags, nicht geändert.
- **OF-14** · Laufende Kacheln beim **Aktualisieren** der Playlist (AK-28, BUG-05 Teil Aktualisieren): Sie spielen die
  alte Adresse weiter, derselbe Sender lässt sich mit neuer Adresse ein zweites Mal hinzufügen. Ob laufende Streams
  umschalten, enden oder bleiben, entscheidet B03 OF-09 (dort für Player und Multiview gemeinsam); die Dublette hängt
  zusätzlich an OF-01. Das Löschen der Playlist beendet die Kacheln seit der B03-Reparatur (AK-27).

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus dem Code belegt. Kein Kriterium: `sdd-qa` prüft nichts
davon als bestanden, sondern nimmt es als Suchliste.

- **FB-01 · Absturz im Raster-Layout beim Schließen des Fensters und beim Entfernen von Kacheln.**
  Fundstelle: `Views/MultiviewScreen.swift:69-93`. `gridLayout` rechnet `count`, `columns` und `rows` einmal
  aus und baut `ForEach(0..<rows, id: \.self)` mit innerem `ForEach(0..<columns)`. Die inneren Closures lesen
  `session.slots[index]` (`:79`) live, prüfen aber gegen den alten `count`. Sinkt die Zeilenzahl, wertet
  SwiftUI eine veraltete Zeile noch einmal aus und greift hinter das Ende des Arrays. Auslöser sind
  `session.clear()` aus `onDisappear` (`:26`, Schließen des Fensters) und `session.remove` über das X
  (`MultiviewTile.swift:62-70`). Der Absturzbericht zeigt `Array.subscript.getter` ← `MultiviewScreen.gridLayout`
  (`:79`) ← `ForEachChild.updateValue()` ← `NSHostingView.updateConstraints()`. Die Grenzprüfung ist auch im
  Release-Build aktiv (gelesen); der Code ist seit `d5c5e58` unverändert und damit in `v1.1`.
  Folge: Wer das Raster benutzt, verliert die App beim Schließen des Multiview-Fensters, und zwar immer. Beim
  Abbauen einzelner Kacheln trifft es jeden zweiten Schritt. Mit nur einem Stream kann der Nutzer das Raster
  nicht mehr verlassen, weil der Umschalter gesperrt ist (AK-13). Ein laufender Player im Hauptfenster endet
  mit. Die B03-Rückerfassung hatte den Absturz über `session.clear()` bei sichtbarem Fenster gefunden; die
  echten Nutzerwege sind hier nachgestellt (AK-23).
- **FB-02 · Ein VLC-Stream wird nach dem Fokuswechsel unsichtbar; die Website verspricht, dass das große Bild
  mitwandert.**
  Fundstelle: `Views/MultiviewScreen.swift:39-46`. Die große Kachel hat keine Identität je Stream (kein
  `.id(slot.id)`), SwiftUI behält deshalb ihre Plattform-Ansicht. `Services/VLCPlaybackEngine.swift:121-129`:
  `VLCPlayerSurface.makeNSView` gibt die **eine** Zeichenfläche der Engine zurück, `updateNSView` ist leer.
  Beim Fokuswechsel wandert die Zeichenfläche des alten Streams in seine neue kleine Kachel, die des neuen
  Streams wird aus ihrer kleinen Kachel gelöst und nie in die große eingesetzt (Mechanismus gelesen, Ergebnis
  ausgeführt). Zum Vergleich hängt `PlayerLayerView.updateNSView` (`Services/PlayerLayerView.swift:63-65`) bei
  AVKit den Layer bei jeder Aktualisierung neu ein; dort tritt der Fehler nicht auf. Versprochen wird es in
  `web/content/changelog-overrides.ts:11` („Clicking a tile moves both the sound and the large picture") und
  `web/app/page.tsx:44-45`.
  Folge: Für Xtream-Playlists im Standardformat MPEG-TS, also die Hauptzielgruppe, zeigt das Fokus-Layout
  nach dem ersten Klick auf eine Kachel ein schwarzes Hauptbild, während genau dieser Stream Ton hat
  (AK-15). Abhilfe findet der Nutzer nur durch Zufall (Raster und zurück).
- **FB-03 · Ein Klick auf den abgeblendeten ⊞-Button öffnet den Player.**
  Fundstelle: `Views/ChannelRowView.swift:73-85` (`.disabled(!multiview.canAddMore)`). Die Karte ist als Ganzes
  ein `NavigationLink` (`Views/ChannelListView.swift:111-113`, `Views/FavoritesView.swift:24-26`); ein
  deaktivierter Button nimmt den Klick nicht an, er geht an die Karte weiter.
  Folge: Gerade wenn das Multiview voll ist, startet ein fünfter Stream mit eigenem Ton und eigener Verbindung
  zum Anbieter (AK-05). Bei einem Abo mit Verbindungslimit scheitert er oder verdrängt einen anderen. Die Absicht
  („voll" heißt: nichts passiert) ist eindeutig.
- **FB-04 · Das X des großen Streams ist im Fokus-Layout nicht erreichbar.**
  Fundstelle: `Views/MultiviewScreen.swift:41-46` (große Kachel mit X oben rechts, `MultiviewTile.swift:53-75`,
  8 pt Innenabstand) und `:47-64` (kleine Kacheln als Overlay oben rechts, 16 pt Abstand, 240 × 135 pt). Die
  erste kleine Kachel liegt über dem X und fängt den Klick mit ihrer Fokus-Geste ab.
  Folge: Der fokussierte Stream lässt sich nicht direkt entfernen; der Klick verlegt stattdessen Ton und Fokus
  (AK-16). Für VoiceOver ist das X weiter als Element vorhanden (gelesen), für die Maus nicht.
- **FB-05 · Kacheln überleben das Löschen und Aktualisieren ihrer Playlist, samt Verbindung mit Zugangsdaten.**
  Fundstelle: `Services/MultiviewSession.swift:37-41` (`Slot` hält `Channel` und die bereits geladene Engine),
  `:54-67` (Adresse einmalig beim Hinzufügen gebildet). `Services/PlaylistImporter.swift:220-278` (`refresh`,
  `delete`) benachrichtigt die Session nicht. Entspricht DM-10 und B03 FB-05.
  Folge: Nach dem Löschen einer Xtream-Playlist sendet die App weiter Benutzername und Passwort an den Anbieter,
  obwohl der Nutzer die Playlist und ihren Schlüsselbund-Eintrag entfernt hat (AK-27, `sicherheit.md` 5.2).
  Nach dem Aktualisieren laufen veraltete Adressen weiter, und derselbe Sender lässt sich ein zweites Mal
  hinzufügen (AK-28).
- **FB-06 · Parallele Verbindungen ohne Rücksicht auf das Anbieterlimit, und Kacheln über dem Limit scheitern
  ohne Meldung.**
  Fundstelle: `Services/MultiviewSession.swift:54-67` (jede Kachel eine eigene Engine und Verbindung, einzige
  Grenze `maxSlots = 4`, `:34`). `Services/XtreamClient.swift:165-171` dekodiert aus `user_info` nur `auth`,
  nicht `max_connections`. VLC-Fehler erreichen die Kachel nie (`VLCPlaybackEngine.swift:84-96`,
  `MultiviewTile.swift:35-39`; Ursache B06 FB-01). Website und FAQ erwähnen kein Verbindungslimit
  (`web/app/page.tsx:150-158`, `web/content/faq.ts`).
  Folge: Viele IPTV-Abos erlauben eine Verbindung. Dann spielt eine Kachel, drei laden endlos, und der Nutzer
  erfährt nicht, warum (AK-31). Anbieter können gleichzeitige Verbindungen desselben Kontos als Weitergabe
  werten und das Konto sperren; das trifft den Nutzer, nicht die App (`sicherheit.md` 4.2). Ob die App das
  Limit kennen soll, ist OF-03; die fehlende Rückmeldung ist ein Fehler.

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Absturz im Raster (Schließen, Entfernen) | ⚠ AK-13, AK-23 **und** FB-01 | kein denkbarer gewollter Zustand; Hinweis der B03-Rückerfassung über die echten Nutzerwege nachgestellt, mit Absturzberichten |
| 2 | Schwarzes Hauptbild nach Fokuswechsel bei VLC | ⚠ AK-15 **und** FB-02 | Website verspricht, dass das große Bild mitwandert (Zielmodus-Regel „verspricht, tut es nicht"); betrifft das Standardformat |
| 3 | Klick auf abgeblendeten ⊞ öffnet den Player | ⚠ AK-05 **und** FB-03 | Absicht eindeutig (voll = nichts passiert); Folge berührt Verbindungslimit und Ton (`sicherheit.md` 4.2) |
| 4 | X des großen Streams verdeckt | ⚠ AK-16 **und** FB-04 | Absicht eindeutig (X entfernt), nicht sicherheitsrelevant; eine offene Frage wäre Zurechtrücken durch Unterlassen |
| 5 | Kacheln laufen nach Löschen/Aktualisieren weiter | ⚠ AK-27, AK-28 **und** FB-05 | `sicherheit.md` 5.2: nach dem Löschen gehen Zugangsdaten weiter an den Anbieter; deckungsgleich mit DM-10 und B03 FB-05 |
| 6 | N Kacheln = N Verbindungen, Limit 1 scheitert still | ⚠ AK-30, AK-31 **und** FB-06; ob die App das Limit kennen soll → OF-03 | `sicherheit.md` 4.2 (Kosten/Missbrauch beim Anbieter); Folge beschrieben, nicht bewertet. Die Stille ist ein Fehler, die Limitlogik eine Produktfrage |
| 7 | Höchstens vier Streams | reguläres Kriterium AK-04 | Code-Kommentar, Tooltip, Website und Release-Notes beschreiben es als gewollt |
| 8 | Ton nur beim fokussierten Stream | reguläre Kriterien AK-03, AK-14, AK-17 | Code-Kommentar und Website beschreiben es als gewollt; am Player-Zustand belegt |
| 9 | Player im Hauptfenster hat zusätzlich Ton | reguläres Kriterium AK-18 + OF-05 | der Code begrenzt den Ton-Fokus erkennbar auf das Fenster; die Website-Aussage ist so lesbar, dass sie nur das Multiview meint, daher kein Fehlbestand |
| 10 | Derselbe Sender zweimal | ⚠ AK-06 + OF-01 | nicht sicherheitsrelevant, Absicht nicht ableitbar; die doppelte Verbindung ist in FB-06 mitbenannt |
| 11 | ⊞ ohne Zugangsdaten öffnet leeres Fenster | ⚠ AK-07 + OF-02 | in B01 bereits als offene Frage OF-11 geführt; nicht sicherheitsrelevant |
| 12 | VLC-Fehler in Kacheln unsichtbar | ⚠ AK-26, Verweis auf B06 FB-01, kein eigener Fehlbestand | Ursache liegt in der Engine und ist dort als Fehler eingestuft; hier nur die Kachel-Ausprägung, damit die QA sie mitprüft |
| 13 | Kein „Erneut versuchen" in Kacheln | reguläres Kriterium AK-25 + OF-06 | nicht sicherheitsrelevant, Absicht nicht ableitbar |
| 14 | Keine Tasten, Warnton bei jeder Taste | reguläres Kriterium AK-29 + OF-04 | Standardverhalten von macOS, wie in B06 Decision Log 11; die Website-Tastenliste nennt kein Fenster |
| 15 | Streams laufen minimiert und ohne Hauptfenster weiter | reguläres Kriterium AK-22 | gewöhnliches Fensterverhalten, kein Punkt aus `sicherheit.md` über 4.3 hinaus (dort benannt) |
| 16 | Layout nach Neustart „Fokus", nichts gespeichert | reguläres Kriterium AK-24 + OF-07 | `MultiviewSession` ist laut Kommentar und Datenmodell bewusst flüchtig |
| 17 | Multiview auch über „Window › Multiview" erreichbar | reguläres Kriterium AK-09 | beobachtetes Standardverhalten einer SwiftUI-`Window`-Szene. **Widerspricht `docs/app-shell.md` AS-05** („Multiview nur über den ⊞-Button erreichbar") — Korrektur des App-Shell-Dokuments durch den Orchestrator vorgeschlagen |
| 18 | Englische Menü- und Systemtexte | kein eigener Punkt, Verweis auf B01 OF-06 | gleiche Ursache (Bundle nur `en` lokalisiert) |
