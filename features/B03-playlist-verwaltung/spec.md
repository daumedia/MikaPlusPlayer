# B03 · Playlist-Verwaltung — Spezifikation

Status: `rekonstruiert` · Stand: 2026-09-16 · Rekonstruktion aus dem Code (sdd-erfassen)

> **Stand: `c01f1cf` + Reparatur B01 (2026-09-16).** Gelesen und ausgeführt wurde eine eingefrorene
> Kopie des Arbeitsbaums nach Abschluss der B01-Reparatur 1 (ohne `web/`). Gegenüber `c01f1cf` hat
> die B01-Reparatur in B03 geändert: Löschen läuft über `PlaylistImporter.delete` und entfernt bei
> Xtream auch den Schlüsselbund-Eintrag. `refresh` liest die Xtream-Zugangsdaten aus dem
> Schlüsselbund und stellt Altbestand mit Zugangsdaten in der Adresse um. Die Datenbank liegt
> app-eigen unter `Application Support/<Bundle-ID>/MikaPlusPlayer.store`. Xtream-Anfragen laufen
> ohne HTTP-Cache, mit Grenzen und Anmeldebremse. **Nicht geändert** hat sie `attach` und damit das
> Anlegen der Sender beim Aktualisieren (siehe FB-01). Die parallel laufende Reparatur von B09 ist
> nicht berücksichtigt.
>
> **Rekonstruiert, nicht geplant.** Beschrieben ist, was der Code **tut**, nicht, was er tun sollte.
> Kriterien mit ⚠ beschreiben fragwürdiges Ist-Verhalten. Sie stehen bewusst als Kriterium hier,
> damit `sdd-qa` sie reproduziert. Wo sie als Fehler eingestuft sind, steht ein Verweis auf
> *Fehlbestand*.
>
> **Wie belegt.** Am 2026-09-16 **ausgeführt** in einer Kopie im Scratchpad unter eigener Bundle-ID
> `lu.daumedia.MikaPlusPlayer.b03probe`, mit eigenem DerivedData, Sparkle-Feed abgeschaltet. Eine
> temporäre XCTest-Sonde im Test-Host der Mac-App hat:
> 1. Aktualisieren und Löschen über den echten `PlaylistImporter` gegen einen lokalen Mock
>    (`127.0.0.1`, M3U-Datei und `player_api.php`) ausgeführt, auf **Datenbankdateien im
>    Temp-Verzeichnis**, die per SQLite-Abfrage und Bytesuche geprüft wurden;
> 2. den Schlüsselbund nur unter dem Test-Dienst `lu.daumedia.MikaPlusPlayer.xtream.tests.<UUID>`
>    benutzt (je Lauf eigener Dienst, am Ende geleert);
> 3. die echte `PlaylistsView` in einem Fenster gerendert, das Kontextmenü per Rechtsklick-Ereignis
>    geöffnet, Einträge über das `NSMenu` ausgeführt und Fensteraufnahmen gemacht;
> 4. `MultiviewScreen`, `PlayerView` und `ChannelListView` mit einem Sender geöffnet und dessen
>    Playlist gelöscht;
> 5. den Main-Thread mit einem Wachhund gemessen (bis 17.000 Sender).
>
> Alles **ohne Ton**: Stream-Adressen zeigten auf einen Mock-Pfad, der nie antwortet, oder auf einen
> geschlossenen Port. Erfundene Zugangsdaten (`qa-user` / `qa-pass-…`). Die Datenbank und der
> Schlüsselbund-Dienst des Nutzers wurden nicht berührt. Nur macOS; iOS ist *(gelesen)*.
> Kriterien, die nur aus dem Code stammen, tragen den Vermerk *(gelesen)*.
>
> **Evidenz:** `qa-erfassung/sonde-protokoll.txt` (Ausgaben aller Läufe), `qa-erfassung/sonde.patch`
> (Sonden-Code und Änderungen der Kopie), Fensteraufnahmen `qa-erfassung/mac-01` bis `mac-13`. Die
> Kopie ist gelöscht.
>
> **Messumgebung für alle Zeitangaben:** Apple M3 Max, macOS 27 (Darwin 27.0.0), **Debug-Build**
> (Test-Host), Datenbankdatei auf der internen SSD, parallel liefen Builds anderer Features. Die
> Zahlen sind **Ist-Werte zur Orientierung**, keine Zielwerte.

## Zweck

Die Übersicht zeigt alle importierten Playlists. Playlists aus einer M3U-Adresse oder einem
Xtream-Zugang lassen sich neu laden, ohne dass markierte Favoriten verloren gehen. Jede Playlist
lässt sich löschen, samt ihren Sendern, Favoriten und bei Xtream den Zugangsdaten im Schlüsselbund.
Das Löschen ist der einzige Weg in der App, gespeicherte Nutzerdaten zu entfernen.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| B01 Xtream-Login | building (Reparatur 1 fertig, QA 2 steht an) | legt Xtream-Playlists an; liefert `XtreamClient`, Schlüsselbund-Ablage, Anmeldebremse und `StreamURLResolver`, die das Aktualisieren und Löschen benutzen |
| B02 M3U-Import | bestand | legt M3U-Playlists aus Adresse oder Datei an; liefert Parser und Abruf (`fetchText`), die das Aktualisieren wiederverwendet |

Auf B03 bauen auf: B04 (Tipp auf die Karte öffnet die Senderliste; Aktualisieren ersetzt die Sender,
während die Liste offen sein kann, siehe B04 FB-02/FB-03), B05 (Favoriten-Erhalt beim
Aktualisieren), B06 und B08 (halten Sender-Objekte, die Aktualisieren und Löschen entfernen).

## User Stories

- **US-01** · Als Nutzer möchte ich alle meine Playlists auf einen Blick sehen, mit Art und
  Senderanzahl, damit ich die richtige öffne.
- **US-02** · Als Nutzer möchte ich eine Playlist aus dem Netz neu laden, wenn der Anbieter Sender
  ändert, ohne meine Favoriten neu setzen zu müssen.
- **US-03** · Als Nutzer möchte ich eine Playlist löschen, damit ihre Sender, Favoriten und
  Zugangsdaten nicht mehr auf dem Gerät liegen.
- **US-04** · Als Nutzer möchte ich bei einem gescheiterten Aktualisieren erfahren, warum, und meine
  bisherige Senderliste behalten.

## Nicht im Scope

- Das Import-Sheet, das „+" und „Playlist importieren" öffnen → **B01** (Reiter „Xtream"), **B02**
  (Reiter „URL", „Datei")
- Senderliste, Suche, Gruppen → **B04**. Hier nur, was eine **offene** Senderliste beim Löschen
  zeigt (AK-27)
- Stern und Favoriten-Tab → **B05**. Hier nur der Erhalt der Favoriten beim Aktualisieren
  (AK-09 bis AK-11)
- Player und Multiview → **B06**, **B08**. Hier nur ihr Verhalten, wenn die Playlist des laufenden
  Senders gelöscht oder aktualisiert wird (AK-28, AK-29)
- Gibt es nicht: Umbenennen, Adresse oder Zugangsdaten ändern (B01 OF-05), Format wechseln,
  Umsortieren, automatisches oder zeitgesteuertes Aktualisieren, „Alle aktualisieren",
  Mehrfachauswahl, Wischen zum Löschen, Entf-Taste, Menüleisteneintrag oder Tastenkürzel (AS-05),
  Export
- Randbeobachtung für **B08**, nicht Teil von B03: Wurde die Multiview-Session im Raster-Layout bei
  **sichtbarem** Fenster geleert, stürzte die App mit „Index out of range" in
  `MultiviewScreen.swift:79` ab (Sonde, erster Lauf). In der App leert nur `onDisappear` die Session;
  ob das Schließen des Fensters oder das Entfernen der letzten Kachel im Raster denselben Absturz
  auslöst, ist nicht geprüft.
- Randbeobachtung für **B02**: Der M3U-Import legt Sender über denselben Weg wie das Aktualisieren an
  und wächst ebenso quadratisch (gemessen: 1.000 Sender 1,17 s, 2.000 4,22 s, 4.000 16,53 s, ganz auf
  dem Main-Thread).

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. Für die Netzwerkkriterien genügt ein lokaler
HTTP-Server, der eine M3U-Datei und `player_api.php` ausliefert, Antworten verzögern kann und die
Anfragen protokolliert.

### Übersicht

- **AK-01** · Angenommen, der Tab „Playlists" ist offen, dann steht oben in Akzentfarbe
  „MIKA+PLAYER · PLAYLISTS", darunter groß „Playlists" und rechts ein „+"-Button. Auf macOS heißt das
  Fenster „Playlists"; auf iOS ist die Navigationsleiste ausgeblendet. *(macOS ausgeführt, iOS
  gelesen)*
- **AK-02** · Angenommen, es gibt keine Playlist, dann zeigt die Übersicht ein Filmstreifen-Symbol,
  „Keine Playlists", „Importiere eine M3U/M3U8-Playlist per URL oder Datei, um loszulegen." und den
  Button „Playlist importieren". Dieser Button und „+" öffnen das Import-Sheet. *(Texte ausgeführt,
  `mac-01`; Öffnen gelesen, in B01 ausgeführt; Wortlaut → OF-04)*
- **AK-03** · Angenommen, es gibt Playlists, dann zeigt die Übersicht je Playlist eine Karte, die
  neueste zuerst (nach Anlagezeitpunkt). Jede Karte zeigt links einen Globus bei Playlists aus einer
  Adresse oder einem Xtream-Zugang bzw. ein Dokument bei einer lokalen Datei, daneben den Namen
  einzeilig und darunter das Badge „N Sender", rechts einen Pfeil. *(ausgeführt, `mac-02`: Xtream,
  M3U-Adresse, Datei in umgekehrter Anlagereihenfolge)*
- **AK-04** · Angenommen, die Übersicht zeigt eine Karte, wenn sie angetippt wird, dann öffnet sich
  die Senderliste der Playlist im selben Tab. *(gelesen; B04 AK-01 ausgeführt)*
- **AK-05** · Angenommen, eine Playlist wurde aktualisiert, dann zeigt die Übersicht weder den
  Zeitpunkt der letzten Aktualisierung noch Quelle, Host, Benutzername oder Format. Die Karte
  unterscheidet Xtream und M3U-Adresse nicht. *(ausgeführt: Accessibility-Texte der Karten
  „<Name>, N Sender"; → OF-03)*

### Kontextmenü

- **AK-06** · Angenommen, die Übersicht zeigt Playlists, wenn eine Karte mit Rechtsklick (macOS)
  bzw. langem Drücken (iOS) gewählt wird, dann erscheint ein Menü: bei einer Playlist aus Adresse
  oder Xtream-Zugang „Aktualisieren" und „Löschen", bei einer lokalen Datei nur „Löschen". „Löschen"
  ist als destruktiv gekennzeichnet. Andere Wege zu diesen Aktionen gibt es nicht. *(macOS
  ausgeführt: Einträge `["Aktualisieren", "Löschen"]` bzw. `["Löschen"]`; iOS gelesen)*

### Aktualisieren

- **AK-07** · Angenommen, eine Playlist aus einer M3U-Adresse existiert, wenn „Aktualisieren" gewählt
  wird, dann ruft die App die gespeicherte Adresse genau einmal ab und ersetzt **alle** Sender durch
  die neue Liste. Das Badge zeigt die neue Anzahl. Name, Adresse, Anlagezeitpunkt und Position in der
  Übersicht bleiben. Jeder Sender ist danach ein neuer Datensatz; keine Sender-ID bleibt erhalten,
  auch nicht bei unveränderten Sendern. *(ausgeführt: 7 → 9 Sender, 0 von 7 IDs übernommen)*
- **AK-08** · Angenommen, eine Xtream-Playlist existiert, wenn „Aktualisieren" gewählt wird, dann
  schickt die App drei Anfragen an `player_api.php` des gespeicherten Hosts (Anmeldung, Kategorien,
  Live-Streams), mit Benutzername und Passwort aus dem Schlüsselbund. Das Format bleibt das beim
  Import gewählte (MPEG-TS → Adressen auf `.ts`, HLS → `.m3u8`). Die gespeicherten Adressen enthalten
  keine Zugangsdaten, der Schlüsselbund-Eintrag bleibt unverändert, und die Datenbankdatei enthält
  das Passwort nicht. *(ausgeführt: 3 Anfragen mit `qa-user`/`qa-pass-b03`, 5 → 6 Sender, 0
  Vorkommen des Passworts in Store, `-wal`, `-shm`)*
- **AK-09** · Angenommen, Sender sind als Favorit markiert, wenn aktualisiert wird, dann ist nach dem
  Aktualisieren jeder neue Sender Favorit, dessen Schlüssel einem vorherigen Favoriten entspricht.
  Schlüssel ist die tvg-ID bzw. `epg_channel_id`, wenn vorhanden, sonst der Name in Kleinbuchstaben.
  Ein umbenannter Sender mit gleicher tvg-ID bleibt Favorit („Alpha" → „Alpha Neu"), ein umbenannter
  Sender ohne tvg-ID verliert ihn („Gamma" → „Gamma Plus"). Die Reihenfolge des Anbieters spielt
  keine Rolle. *(ausgeführt für M3U und Xtream)*
- **AK-10** ⚠ · Angenommen, mehrere Sender teilen sich einen Schlüssel (gleiche tvg-ID bei „Film HD",
  „Film SD", „Film 4K"; gleicher Name in anderer Schreibweise „Sport HD"/„sport hd"; zweimal „Kanal X"
  mit derselben tvg-ID), und einer davon ist Favorit, wenn aktualisiert wird, dann sind danach
  **alle** diese Sender Favoriten. *(ausgeführt: M3U 4 → 6 Favoriten, „Kanal X" 1 → 2; Xtream 3 → 5
  → FB-02)*
- **AK-11** ⚠ · Angenommen, die Quelle liefert beim Aktualisieren eine gültige, aber viel kürzere
  Liste (z. B. 1 statt 7 Sender), dann ersetzt die App ohne Rückfrage. Favoriten, deren Sender fehlen,
  sind weg und kommen auch nicht zurück, wenn die Quelle beim nächsten Aktualisieren wieder die volle
  Liste liefert. *(ausgeführt: 7 → 1 → 7 Sender, 4 → 0 → 0 Favoriten → OF-02)*
- **AK-12** · Angenommen, ein Aktualisieren läuft, dann steht in der Karte ein Ladeindikator anstelle
  des Pfeils, und die Übersicht bleibt bedienbar, solange die App auf den Anbieter wartet. Ist es
  fertig, verschwindet der Indikator und das Badge zeigt die neue Anzahl. Eine Erfolgsmeldung gibt es
  nicht. *(Indikator und Bedienbarkeit ausgeführt, `mac-03`; neue Anzahl über `channelCount` ausgeführt,
  Badge gelesen; zur Bedienbarkeit bei großen Listen → AK-37)*
- **AK-13** ⚠ · Angenommen, zwei Playlists werden gleichzeitig aktualisiert, dann zeigt nur die
  zuletzt gestartete Karte den Ladeindikator. Ist eine der beiden fertig, verschwindet der Indikator
  ganz, auch wenn die andere noch läuft. *(ausgeführt: M3U gestartet, dann Xtream → Indikator nur bei
  Xtream, `mac-04`; M3U fertig, Xtream läuft noch → kein Indikator, `mac-05` → FB-03)*
- **AK-14** ⚠ · Angenommen, ein Aktualisieren läuft, dann bleibt „Aktualisieren" im Kontextmenü
  wählbar. Jede weitere Wahl startet einen weiteren vollständigen Abruf und ein weiteres Ersetzen.
  Das Ergebnis bleibt richtig: keine doppelten Sender, Favoriten erhalten. *(Menüeintrag ohne Sperre
  gelesen; dreimal über das Menü bei M3U → 3 Abrufe; gleichzeitig gestartet: M3U zweimal → 2 Abrufe,
  7 Sender, Xtream dreimal → 9 Anfragen, 4 Sender → FB-04)*
- **AK-15** · Angenommen, zwei verschiedene Playlists werden gleichzeitig aktualisiert, dann werden
  beide richtig ersetzt, jede mit ihren Favoriten. *(ausgeführt: M3U und Xtream in 1,5 s)*
- **AK-16** · Angenommen, eine Playlist stammt aus einer lokalen Datei, dann gibt es kein
  „Aktualisieren". Eine geänderte Datei wird nicht neu eingelesen; neu einlesen geht nur über einen
  weiteren Import, der eine zweite Playlist anlegt. *(ausgeführt: interner Aufruf ohne Fehler, ohne
  Anfrage, ohne Änderung; Datei geändert → Playlist unverändert → OF-05)*
- **AK-17** · Angenommen, eine Xtream-Playlist hat noch Zugangsdaten in ihrer gespeicherten Adresse
  (Altbestand, dessen Umstellung beim Start gescheitert ist), wenn aktualisiert wird, dann benutzt die
  App diese Zugangsdaten, legt sie danach im Schlüsselbund ab und entfernt sie aus der Adresse und aus
  allen Sendern. Favoriten bleiben. *(ausgeführt über den B01-Test
  `testBUG01_AltbestandBleibtSpielbarUndWirdBeimAktualisierenUmgestellt`)*

### Fehler beim Aktualisieren

Gemeinsam für AK-18 bis AK-21: Die Meldung erscheint als Alert „Fehler" mit Button „OK" über der
Übersicht. Nach „OK" verschwindet er. Die bisherige Senderliste bleibt **vollständig** erhalten:
dieselben Sender mit denselben IDs, dieselben Favoriten, dieselbe Anzahl, derselbe Zeitpunkt der
letzten Aktualisierung; in der Datenbank ändert sich nichts. *(Alert ausgeführt mit „Netzwerkfehler:
HTTP 404", `mac-06`; Erhalt der Liste für jeden Fall unten ausgeführt)*

- **AK-18** · Angenommen, eine M3U-Playlist wird aktualisiert, dann lautet die Meldung:
  - Server antwortet mit HTTP 404 oder 500: „Netzwerkfehler: HTTP 404" bzw. „… HTTP 500"
  - Antwort ist eine HTML-Seite, leer oder nur `#EXTM3U`: „Die Playlist enthält keine gültigen Sender."
  - Host nicht erreichbar: „Netzwerkfehler: Could not connect to the server." (englischer Systemtext,
    B01 OF-06)
  *(ausgeführt)*
- **AK-19** · Angenommen, eine Xtream-Playlist wird aktualisiert, dann lautet die Meldung:
  - leere Senderliste: „Die Playlist enthält keine gültigen Sender."
  - HTTP-Fehler: „Netzwerkfehler: HTTP 500"
  - unerwartete Antwort: „Netzwerkfehler: Unerwartete Serverantwort (The data couldn’t be read because
    it isn’t in the correct format.)"
  - mehr Sender als die Grenze aus B01 (100.000): „Die Senderliste ist zu groß (mehr als 100.000
    Sender)."
  - Host nicht erreichbar: „Netzwerkfehler: Could not connect to the server."
  *(ausgeführt; die Grenze mit 2 statt 100.000)*
- **AK-20** · Angenommen, der Anbieter lehnt die Anmeldung ab, wenn aktualisiert wird, dann lautet die
  Meldung „Anmeldung fehlgeschlagen. Benutzername/Passwort prüfen.". Ab der vierten Ablehnung in Folge
  am selben Panel lautet sie „Zu viele fehlgeschlagene Anmeldungen. Bitte in 30 Sekunden erneut
  versuchen.", und die Anfrage erreicht das Panel nicht. Die Bremse zählt Import und Aktualisieren
  gemeinsam (B01). *(ausgeführt)*
- **AK-21** ⚠ · Angenommen, der Schlüsselbund-Eintrag einer Xtream-Playlist fehlt (z. B. nach der
  Wiederherstellung auf einem neuen Gerät), wenn aktualisiert wird, dann lautet die Meldung „Die
  Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu
  importieren.", und es geht keine Anfrage hinaus. Der empfohlene Weg löscht alle Favoriten dieser
  Playlist. *(ausgeführt → OF-06, B01 OF-09)*

### Löschen

- **AK-22** ⚠ · Angenommen, die Übersicht zeigt eine Playlist, wenn „Löschen" gewählt wird, dann
  verschwindet sie **sofort**, ohne Rückfrage. Es gibt kein Rückgängig: Bearbeiten › Widerrufen (⌘Z)
  stellt sie nicht wieder her. *(ausgeführt: kein Sheet, Datenbank sofort ohne Playlist, `mac-07`;
  Datenbank-Kontext ohne `UndoManager`, `undo:` im Testfenster von keinem Responder behandelt;
  Menüpunkt der App gelesen → OF-01)*
- **AK-23** · Angenommen, eine Playlist wird gelöscht, dann sind danach die Playlist und alle ihre
  Sender aus der Datenbank entfernt, ohne verwaiste Sender-Zeilen, einschließlich ihrer Favoriten
  (sie verschwinden aus dem Favoriten-Tab). Andere Playlists, ihre Sender und Favoriten bleiben
  unverändert. *(ausgeführt per SQLite: 3 Playlists/60 Sender → 1/20; alle 6 Favoriten gehörten zu den
  gelöschten Playlists → 0; Erhalt von Favoriten anderer Playlists gelesen)*
- **AK-24** · Angenommen, eine Xtream-Playlist wird gelöscht, dann ist ihr Schlüsselbund-Eintrag
  entfernt. Einträge anderer Xtream-Playlists bleiben. *(ausgeführt über den Test-Dienst und über das
  Kontextmenü)*
- **AK-25** · Angenommen, eine Playlist aus einer lokalen Datei wird gelöscht, dann bleibt die Datei
  selbst unberührt. *(ausgeführt)*
- **AK-26** · Angenommen, eine Playlist wird aktualisiert, wenn sie währenddessen gelöscht wird, dann
  bleibt sie gelöscht: keine verwaisten Sender, keine Favoriten im Favoriten-Tab, kein wieder
  angelegter Schlüsselbund-Eintrag, kein Absturz. Das Aktualisieren endet danach ohne Meldung.
  *(ausgeführt für M3U und Xtream; Ausnahme Altbestand → AK-35)*
- **AK-27** ⚠ · Angenommen, die Senderliste einer Playlist ist offen (zweites Fenster, geteilter
  Bildschirm), wenn die Playlist gelöscht wird, dann bleibt die Liste stehen: Titel und Kopfzeile
  zeigen weiter Namen und alte Senderzahl („MIKA+PLAYER · 7 SENDER"), die Gruppen-Chips bleiben, und
  die Liste zeigt „Keine Sender – Diese Playlist enthält keine Sender.". *(ausgeführt, `mac-13` →
  FB-05)*
- **AK-28** ⚠ · Angenommen, ein Sender der Playlist läuft im Player oder im Multiview, wenn die
  Playlist gelöscht wird, dann läuft die Wiedergabe weiter: Die Verbindung zum Anbieter bleibt offen
  (bei Xtream mit Zugangsdaten im Pfad), Fenstertitel bzw. Kachel zeigen weiter den Sendernamen. Erst
  Verlassen des Players bzw. Schließen der Kachel oder des Multiview-Fensters beendet sie. „Erneut versuchen" meldet danach bei
  Xtream „Die Zugangsdaten dieser Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen
  und neu importieren."; bei M3U lädt es die alte Adresse erneut. *(ausgeführt: Kachel und Player nach
  dem Löschen unverändert, `mac-09`, `mac-11`, offene Verbindung im Mock-Protokoll; Adressbildung für
  „Erneut versuchen" ausgeführt, Knopf gelesen → FB-05)*
- **AK-29** ⚠ · Angenommen, ein Sender läuft im Player, wenn seine Playlist aktualisiert wird, dann
  läuft die Wiedergabe weiter. „Erneut versuchen" ruft danach bei Xtream die gespeicherte Adresse
  **ohne** Benutzername und Passwort auf (`http://<host>/live/<id>.<endung>`), die der Anbieter
  ablehnt. *(Adressbildung ausgeführt; Ablehnung durch einen echten Anbieter gelesen → FB-05)*

### Datenschutz und Missbrauchsschutz

Fragenkatalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog). Schwerpunkt *Löschen und
Auskunft*: Was bleibt nach dem Löschen wo? Jede Frage hat ein Kriterium, ein „trifft nicht zu,
weil …" oder einen Eintrag im *Fehlbestand*.

- **AK-30** · Angenommen, ein Aktualisieren scheitert aus einem Grund aus AK-18 bis AK-21, dann
  enthält die Meldung weder Benutzername noch Passwort noch die Adresse. *(ausgeführt für alle 16
  Fehlerfälle)*
- **AK-31** · Angenommen, aktualisiert oder gelöscht wird, dann schreibt die App keine Nutzdaten ins
  Systemprotokoll. *(gelesen: kein `print`, `Logger`, `os_log`, `NSLog` in `Sources/`. Beim
  gleichzeitigen Aktualisieren und Löschen protokolliert SwiftData selbst Zeilen „PersistentIdentifier
  … was remapped to a temporary identifier during save … This is a fatal logic error in
  DefaultStore" mit Objekt-IDs, ohne Namen oder Adressen; ausgeführt. Mitschnitt mit `log stream`
  nicht ausgeführt)*
- **AK-32** · Angenommen, eine Xtream-Playlist wird aktualisiert, dann gehen Benutzername und Passwort
  nur an den gespeicherten Host der Playlist und landen weder in der Datenbank noch im
  HTTP-Plattencache. *(ausgeführt: nur Mock-Anfragen an den eigenen Host, 0 Vorkommen im Store, 0
  `player_api`-Einträge in `Cache.db`)*
- **AK-33** ⚠ · Angenommen, eine M3U-Playlist wurde importiert oder aktualisiert, wenn sie gelöscht
  wird, dann bleiben im HTTP-Plattencache der App (macOS `~/Library/Caches/<Bundle-ID>/Cache.db`, iOS
  `Library/Caches`) ihre Adresse samt Query (z. B. `?token=…`) und die vollständige Antwort mit allen
  Sendernamen und Stream-Adressen stehen. *(ausgeführt: je 1 Eintrag für Adresse und Antwortkörper vor
  und nach dem Löschen → FB-06)*
- **AK-34** ⚠ · Angenommen, eine Playlist wurde gelöscht, wenn die Datenbankdatei nach einem Neustart
  als Bytefolge durchsucht wird, dann können Namen und Stream-Adressen gelöschter Sender noch darin
  stehen. *(ausgeführt: gelöschte M3U-Playlist mit 20 Sendern → nach Schließen und erneutem Öffnen 26
  Vorkommen der Sendernamen und 26 der Stream-Adressen in `…store`, 3 freie Seiten, `PRAGMA
  secure_delete` = 2 (FAST); die im selben Lauf gelöschte Xtream-Playlist hinterließ 0 Vorkommen;
  Name der Playlist und Token der Adresse: 0 → FB-07)*
- **AK-35** ⚠ · Angenommen, eine Xtream-Playlist aus dem Altbestand (AK-17) wird aktualisiert, wenn sie
  währenddessen gelöscht wird, dann legt das Aktualisieren den Schlüsselbund-Eintrag **nach** dem
  Löschen neu an. Er bleibt ohne Playlist bestehen, und die App bietet keinen Weg, ihn zu entfernen.
  *(ausgeführt → FB-08)*
- **AK-36** ⚠ · Angenommen, der Nutzer will alle gespeicherten Daten loswerden, dann gibt es dafür in
  der App keinen Weg außer jede Playlist einzeln zu löschen. Wird die App gelöscht, bleiben unter
  macOS Datenbank (`~/Library/Application Support/<Bundle-ID>/`), HTTP-Cache, Einstellungen und
  Schlüsselbund-Einträge liegen; unter iOS bleiben Schlüsselbund-Einträge über die Deinstallation
  hinaus bestehen. *(gelesen, Systemverhalten; nicht ausgeführt → FB-09)*

### Leistung

Gemessene **Ist-Werte, keine Zielwerte**; Messumgebung siehe Kopf. Die QA misst am selben Aufbau
nach.

- **AK-37** ⚠ · Angenommen, eine Playlist mit N Sendern wird aktualisiert, dann blockiert die App
  nach dem Abruf den Main-Thread für die gesamte Dauer des Ersetzens; die Oberfläche reagiert in dieser
  Zeit nicht. Die Dauer wächst **quadratisch** mit N:

  | Sender | M3U: Aktualisieren | Xtream: Import (zum Vergleich) | Xtream: Aktualisieren | längste Main-Thread-Blockade (M3U / Xtream) |
  |---|---|---|---|---|
  | 1.000 | 1,17 s | 0,18 s | 1,19 s | 1,15 s / 1,14 s |
  | 2.000 | 4,42 s | 0,25 s | 4,35 s | 4,39 s / 4,29 s |
  | 4.000 | 16,52 s | 0,43 s | 16,66 s | 16,50 s / 16,60 s |
  | 17.000 | nicht gemessen | 2,39 s | **292,43 s** | — / **292,31 s** |

  Der Speicherbedarf stieg bei 17.000 Sendern von 53 auf 86 MB; alle 17 Favoriten blieben erhalten.
  *(ausgeführt → FB-01)*
- **AK-38** ⚠ · Angenommen, eine Playlist mit N Sendern wird gelöscht, dann blockiert die App den
  Main-Thread, bis alle Sender entfernt sind:

  | Sender | Löschen nach einem Aktualisieren (M3U / Xtream) | Löschen ohne vorheriges Aktualisieren (Xtream) |
  |---|---|---|
  | 1.000 | 0,55 s / 0,52 s | — |
  | 2.000 | 0,69 s / 1,61 s | — |
  | 4.000 | 5,20 s / 4,06 s | 8,00 s |
  | 17.000 | — / **59,87 s** | **69,81 s** |

  Die Blockade entspricht jeweils der gesamten Dauer. In beiden Spalten waren die Sender vorher im
  Speicher geladen (die Sonde hatte Favoriten gesetzt). *(ausgeführt → FB-01)*

#### Katalog, Frage für Frage

| # | Katalogfrage | Antwort für B03 |
|---|---|---|
| 1.1 | Welche personenbezogenen Daten? | Xtream: Benutzername und Passwort (im Schlüsselbund, beim Aktualisieren gelesen und gesendet), Host des Anbieters, IP gegenüber dem Anbieter. M3U: Adresse mit etwaigen Token. Favoriten (Sehgewohnheiten). Senderlisten selbst stammen vom Anbieter |
| 1.2 | Besondere Kategorien? | Nicht gespeichert. Favoriten können Rückschlüsse erlauben (religiöse, politische Sender); B03 vervielfacht sie beim Aktualisieren (AK-10) und löscht sie mit der Playlist (AK-23). Bewertung gehört zu B05 |
| 1.3 | Wo gespeichert, wie lange? | Datenbank `Application Support/<Bundle-ID>/MikaPlusPlayer.store` bis zum Löschen (AK-23), danach Reste in freien Seiten (AK-34 → FB-07). Schlüsselbund bis zum Löschen (AK-24), verwaist in AK-35 (FB-08). `Cache.db` für M3U-Abrufe unbefristet bis zur Räumung durch das System (AK-33 → FB-06). Nach dem Löschen der App: FB-09. Eine Löschfrist gibt es nicht |
| 1.4 | Landen sie in Logs? | Nein, AK-30, AK-31. Im HTTP-Cache ja, bei M3U (FB-06) |
| 2.1 | Welche externen Dienste? | Beim Aktualisieren: der Host der M3U-Adresse bzw. das Xtream-Panel der Playlist (AK-07, AK-08). Löschen spricht keinen Dienst an. Keine KI, keine Analyse, kein Fehler-Tracking |
| 2.2 | Was wird übertragen, was vorher entfernt? | Xtream: Benutzername und Passwort als Query-Parameter, über `http://` oder `https://` wie beim Import gewählt (B01); M3U: die gespeicherte Adresse unverändert, mit Weiterleitungen und ohne Grenzen des Standard-`URLSession` (gelesen, B02). Entfernt wird nichts |
| 2.3 | Standort des Dienstes, AV-Vertrag? | Trifft nicht zu, weil der Nutzer den Anbieter selbst gewählt hat und die App direkt mit ihm spricht; daumedia empfängt nichts |
| 2.4 | Training mit dem Payload? | Trifft nicht zu, weil kein KI-Dienst beteiligt ist |
| 3.1 | Wer darf sehen, ändern, löschen? | Der lokale Nutzer: alle Playlists sehen, aktualisieren, löschen (AK-06). Unter macOS können andere Prozesse desselben Benutzers Datenbank und Cache lesen (Sandbox aus, B01); den Schlüsselbund-Eintrag schützt dessen Zugriffsliste (B01) |
| 3.2 | Erzwungen in DB oder Anwendung? | Nirgends in der App; Einzelnutzer ohne Konten. iOS: App-Sandbox des Systems |
| 3.3 | Fremde ID? | Trifft nicht zu, weil es keinen Server und keine per ID abrufbaren Ressourcen gibt |
| 3.4 | Rollen? | Trifft nicht zu, weil die App keine Konten und Rollen hat |
| 4.1 | Rate Limit auf die Anmeldung | Die B01-Bremse greift auch beim Aktualisieren (AK-20). Mehrfaches Auslösen ohne Fehler ist ungebremst (AK-14 → FB-04) |
| 4.2 | Rate Limit für Kostenpflichtiges | Trifft nicht zu, weil kein kostenpflichtiger Dienst des Betreibers gerufen wird. Anbieter mit Verbindungs- oder Abruflimits trifft FB-04 |
| 4.3 | Kosten je Aufruf | Rechenzeit: Ersetzen quadratisch auf dem Main-Thread, 17.000 Sender ≈ 5 min (AK-37), Löschen 60–70 s (AK-38) → FB-01 |
| 4.4 | Unvertraute Eingaben: Größe, Typ, Inhalt | Xtream: Grenzen aus B01 (64 MB, 100.000 Sender, 180 s) gelten auch beim Aktualisieren (AK-19). M3U: keine Größen- oder Gesamtzeitgrenze beim Abruf (gelesen; Befund gehört zu B02, wirkt hier gleich). Eine plötzlich kleinere Liste wird ohne Rückfrage übernommen (AK-11 → OF-02) |
| 4.5 | Wo greift das Limit? | In der App (`XtreamClient.Limits`, `XtreamLoginThrottle`), nur für Xtream |
| 5.1 | Konto selbst löschen? | Trifft als Konto nicht zu, weil die App keine Konten hat. Das Gegenstück „alle Daten entfernen" fehlt (AK-36 → FB-09) |
| 5.2 | Was genau wird gelöscht? | Playlist, alle Sender, deren Favoriten (AK-23); bei Xtream der Schlüsselbund-Eintrag (AK-24). **Nicht** gelöscht: M3U-Einträge im HTTP-Cache (FB-06), Logo-Cache (B04 FB-07), Reste in freien Datenbankseiten (FB-07), verwaiste Schlüsselbund-Einträge (FB-08), Kopien in Backups (Datenbank bewusst nicht ausgeschlossen, B01 Annahme 7), laufende Wiedergaben (FB-05) |
| 5.3 | Was bleibt, und warum? | Die Liste unter 5.2, ohne Begründung im Code. Einzig begründet: Datenbank im Backup, damit Playlists wiederherstellbar sind (B01) |
| 5.4 | E-Mail-Adresse wieder frei? | Trifft nicht zu, weil die App keine Registrierung hat |
| 5.5 | Datenexport? | Trifft nicht zu, weil daumedia keine Daten erhält, die es herausgeben könnte. In der App sieht der Nutzer zu einer Playlist nur Name und Senderzahl (AK-05) |
| 6.1 | Welche Schlüssel braucht das Feature? | Keine App-Schlüssel. Das Xtream-Passwort des Nutzers liegt im Schlüsselbund (B01) und wird beim Aktualisieren gelesen |
| 6.2 | Welche dürfen zum Client? | Trifft nicht zu, weil es keinen Server gibt |
| 6.3 | Steht Echtes im Repository? | Trifft für B03 nicht zu, weil `PlaylistsView.swift` und die B03-Teile von `PlaylistImporter.swift` keine Adressen oder Zugangsdaten enthalten; Git-Historie in B01 AK-30 geprüft |
| 6.4 | Vorlagen `.env.example` / `Secrets.example.xcconfig` | Trifft nicht zu, weil B03 keine Build-Geheimnisse braucht |

## Edge Cases

Ist-Verhalten. „(ausgeführt)" heißt mit der Sonde belegt, „(gelesen)" heißt aus dem Code abgeleitet.

- **EC-01** · Xtream-Playlist mit unbekanntem Formatwert (`"ts"`, `"m3u8"`, leer, fehlend) → das
  Aktualisieren baut HLS-Adressen (`.m3u8`). Der Code-Kommentar nennt `"m3u8"/"ts"` als Werte (DM-11);
  geschrieben werden nur `"hls"`/`"mpegts"`. *(ausgeführt)*
- **EC-02** · Anbieter liefert unveränderte Liste → trotzdem werden alle Sender gelöscht und neu
  angelegt, mit voller Dauer aus AK-37. *(ausgeführt)*
- **EC-03** · Speichern scheitert nach dem Ersetzen (z. B. Datenträger voll) → Alert mit der
  Fehlermeldung; die gelöschten und neuen Sender bleiben aber ungespeichert im Kontext der Ansicht und
  können beim nächsten automatischen Speichern doch geschrieben werden. *(gelesen, nicht provoziert)*
- **EC-04** · Zwei Aktualisierungen scheitern kurz nacheinander → es gibt nur eine Fehlermeldung; die
  spätere ersetzt die frühere. *(gelesen)*
- **EC-05** · Aktualisieren, während die Senderliste derselben Playlist offen ist → Liste und
  Kopfzeile aktualisieren sich, die Gruppen-Chips nicht (B04 AK-17, FB-02). *(in B04 ausgeführt)*
- **EC-06** · Xtream-Antwort mit einzelnen defekten Einträgen → diese werden beim Aktualisieren still
  übersprungen (B01 BUG-06); ein Favorit auf einem solchen Sender geht verloren. *(gelesen)*
- **EC-07** · Löschen während eines Aktualisierens → „Löschen" ist im Menü wählbar; das Aktualisieren
  meldet danach keinen Fehler (AK-26). *(ausgeführt)*
- **EC-08** · macOS nach einem App-Update (ad-hoc signiert, B01 OF-08) → Aktualisieren und Löschen
  einer Xtream-Playlist können eine Abfrage des Anmeldepassworts auslösen. Wird sie abgelehnt, meldet
  Aktualisieren „Der Schlüsselbund hat den Zugriff auf die Zugangsdaten verweigert (Code …)."; Löschen
  entfernt die Playlist trotzdem und verschweigt, dass der Eintrag bleibt (FB-08). *(gelesen, nicht
  nachgestellt)*
- **EC-09** · Mehrere Hauptfenster (macOS) → jedes hat eigenen Ladeindikator-Zustand; ein
  Aktualisieren in Fenster A zeigt in Fenster B keinen Indikator, dessen Übersicht zeigt die neue
  Anzahl aber sofort. *(gelesen)*
- **EC-10** · Sehr langer Playlist-Name → einzeilig, abgeschnitten. *(gelesen)*
- **EC-11** · iOS → Kontextmenü über langes Drücken mit Vorschau der Karte; Einträge wie macOS.
  *(gelesen)*
- **EC-12** · Lokale Datei wurde verschoben oder gelöscht → ohne Wirkung auf die Playlist, weil nur der
  Inhalt beim Import übernommen wurde. *(gelesen; AK-25 ausgeführt)*

## Offene Fragen

Alle vom 2026-09-16. Entscheidung durch den Nutzer (Michael Ferreira), vor der Reparaturrunde nach der
QA von B03.

- **OF-01** · Soll „Löschen" nachfragen oder rückgängig zu machen sein (AK-22)? Bei Xtream sind danach
  auch die Zugangsdaten weg, bei allen Playlists die Favoriten.
- **OF-02** · Soll das Aktualisieren warnen oder abbrechen, wenn die neue Liste deutlich kleiner ist,
  und sollen Favoriten fehlender Sender aufbewahrt werden, bis sie wiederkommen (AK-11)?
- **OF-03** · Sollen Zeitpunkt der letzten Aktualisierung, Quelle (Xtream/M3U, Host) oder Format in der
  Karte stehen (AK-05)? `lastRefreshed` wird gespeichert, aber nirgends gezeigt.
- **OF-04** · Soll der Leerzustand den Xtream-Zugang nennen (AK-02)? Das Sheet öffnet mit Reiter
  „Xtream", der Text spricht nur von M3U/M3U8.
- **OF-05** · Soll eine Datei-Playlist neu eingelesen werden können (AK-16)?
- **OF-06** · Soll die Meldung „Zugangsdaten fehlen" einen Weg anbieten, sie neu einzugeben, statt
  Löschen zu empfehlen (AK-21)? Hängt an B01 OF-05 und OF-09.

Aus der Reparatur vom 2026-09-26 (`build-bericht.md`), ebenfalls zur Entscheidung durch den Nutzer:

- **OF-07** · „Alle Daten entfernen": Ort (macOS im App-Menü nach „Einstellungen", iOS im Menü „…" der
  Playlist-Übersicht), Umfang (auch Einstellungen der App einschließlich Sparkle und beiseitegelegte
  Datenbanken) und Rückfrage (eine Warnung, kein Rückgängig) sind angenommen. Passt das, und was sagt die
  Datenschutzseite dazu (B10)?
- **OF-08** · Sollen Schlüsselbund-Einträge ohne Playlist, die vor dieser Reparatur entstanden sind (AK-35,
  B01 BF-44/BF-46), beim Start entfernt werden? Heute verschwinden sie nur über „Alle Daten entfernen", weil
  ein Eintrag zu einer beiseitegelegten Datenbank (B09) gehören kann.
- **OF-09** · Laufende Wiedergabe beim **Aktualisieren**: Player und Multiview-Kacheln spielen die alte Adresse
  weiter (B08 BUG-05, Teil Aktualisieren); nur „Erneut versuchen" nimmt den neuen Stand. Sollen laufende
  Streams nach dem Aktualisieren auf den wiedererkannten Sender umschalten oder enden, wenn er fehlt?
- **OF-10** · Beim Aktualisieren bleiben Namen und Adressen der ersetzten Sender bis zum nächsten Löschen bzw.
  „Alle Daten entfernen" in freien Seiten der Datenbankdatei (Verdichten nur nach dem Löschen, weil es bei
  großen Listen Sekunden kostet). Reicht das (vgl. B05 BUG-10)?

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus dem Code belegt. Kein Kriterium: `sdd-qa` prüft
nichts davon als bestanden, sondern nimmt es als Suchliste. Zeilenangaben beziehen sich auf
`Sources/` im Stand `c01f1cf` + Reparatur B01.

- **FB-01 · Aktualisieren und Löschen großer Playlists blockieren die Oberfläche minutenlang.**
  Fundstelle: `Services/PlaylistImporter.swift:253-264` (`refresh` läuft auf dem Main-Actor, lädt alle
  Sender, löscht sie einzeln), `:284-305` (`attach` legt jeden Sender mit
  `Channel(playlist:)` an und hängt ihn zusätzlich mit `playlist.channels.append` an — der Weg, den
  B01 BUG-12 für den Import als quadratisch ersetzt hat), `:270-278` (`delete` kaskadiert auf dem
  Main-Actor).
  Folge: 17.000 Sender aktualisieren = 292 s eingefrorene App, löschen = 60–70 s (AK-37, AK-38). Unter
  iOS droht die Beendigung durch das System, wenn die App dabei in den Hintergrund geht. Das PRD
  verspricht „bleibt auch bei Anbieterlisten mit mehr als 17.000 Sendern bedienbar", die Website
  „Seventeen thousand channels, still usable" (`web/app/page.tsx:105`). Mehrfaches Tippen (FB-04)
  vervielfacht die Dauer.
- **FB-02 · Ein Favorit wird beim Aktualisieren zu mehreren.**
  Fundstelle: `Models/Channel.swift:49-52` (`favoriteKey` nicht eindeutig: tvg-ID oder Name in
  Kleinbuchstaben), `Services/PlaylistImporter.swift:253, 299` (Menge von Schlüsseln, jeder passende
  neue Sender wird Favorit). Entspricht DM-06; fachlich Überschneidung mit B05.
  Folge: HD/SD/4K-Varianten und Namensdubletten füllen den Favoriten-Tab mit Sendern, die der Nutzer
  nie markiert hat; jedes Aktualisieren kann weitere hinzufügen (AK-10). Die Website verspricht
  „Refreshing a remote playlist matches favourites by their tvg-id" (`web/content/features.ts:18`),
  nicht ihre Vermehrung.
- **FB-03 · Ladeindikator nur für eine Playlist.**
  Fundstelle: `Views/PlaylistsView.swift:11` (ein einziges `refreshingID`), `:110-111` (gesetzt beim
  Start, beim Ende jedes Aktualisierens auf `nil`).
  Folge: Bei zwei laufenden Aktualisierungen zeigt eine Karte nichts an, und nach dem Ende der ersten
  sieht es aus, als wäre alles fertig (AK-13). Der Nutzer startet deshalb erneut (FB-04). Die App-Shell
  beschreibt „Spinner in der betroffenen Karte" (`docs/app-shell.md`).
- **FB-04 · Keine Sperre gegen mehrfaches Aktualisieren derselben Playlist.**
  Fundstelle: `Views/PlaylistsView.swift:39-46` (Menüeintrag nie deaktiviert),
  `Services/PlaylistImporter.swift:220` (keine Prüfung auf ein laufendes Aktualisieren).
  Folge: Jede Wahl erzeugt einen vollständigen Abruf beim Anbieter (Xtream: drei Anfragen mit
  Zugangsdaten) und ein weiteres Ersetzen auf dem Main-Thread (AK-14). Anbieter mit Abruflimits
  können das als Missbrauch werten. B01 hat dasselbe beim Import als Fehler eingestuft (BUG-09,
  Doppelklick).
- **FB-05 · Sender-Objekte überleben Löschen und Aktualisieren in Player, Multiview und Senderliste.**
  Fundstelle: `Services/MultiviewSession.swift:37-41` (`Slot` hält `Channel`), `Views/PlayerView.swift:13,
  239-257` (`channel` fest, „Erneut versuchen" bildet die Adresse aus dem alten Objekt),
  `Services/StreamURLResolver.swift:25` (ohne `playlist` gibt der Resolver die gespeicherte Adresse
  ohne Zugangsdaten zurück), `Views/ChannelListView.swift:18-21, 35` (hält die `Playlist`).
  B03 benachrichtigt keine dieser Stellen. Entspricht DM-10.
  Folge: Nach dem Löschen läuft die Wiedergabe mit Zugangsdaten weiter, obwohl der Nutzer die Playlist
  entfernt hat (AK-28); die offene Senderliste behauptet eine leere Playlist (AK-27); nach einem
  Aktualisieren scheitert „Erneut versuchen" bei Xtream an fehlenden Zugangsdaten (AK-29), mit einer
  Meldung, die das Löschen empfiehlt.
- **FB-06 · M3U-Abrufe landen im HTTP-Plattencache und überstehen das Löschen.**
  Fundstelle: `Services/PlaylistImporter.swift:307-321` (`fetchText` über `URLSession.shared`;
  `cachePolicy = .reloadIgnoringLocalCacheData` verhindert nur das Lesen). `delete` (`:270-278`) räumt
  keinen Cache. B01 BUG-03 hat nur Xtream auf eine Sitzung ohne Cache umgestellt;
  `AppPersistence.purgeLegacyHTTPCacheOnce` leert einmalig beim ersten Start.
  Folge: Adresse samt Token und die vollständige Senderliste bleiben nach dem Löschen in `Cache.db`
  (AK-33); unter macOS für jeden Prozess des Benutzers lesbar. Anbieter-M3U-Links tragen häufig
  Benutzername und Passwort in der Adresse. Betrifft ebenso den Import (B02).
- **FB-07 · Gelöschte Sender bleiben als Bytes in der Datenbankdatei.**
  Fundstelle: `Services/PlaylistImporter.swift:270-278` (Löschen ohne anschließendes Verdichten);
  SQLite läuft mit `secure_delete` = FAST, das freigegebene Seiten nicht zuverlässig überschreibt.
  `AppPersistence.compactStore` (`AppPersistence.swift:204-214`) verdichtet nur nach der
  Zugangsdaten-Umstellung.
  Folge: Namen und Stream-Adressen gelöschter Playlists lassen sich aus der Datei zurückgewinnen,
  auch nach Neustart (AK-34). Bei M3U-Playlists enthalten Stream-Adressen oft Zugangsdaten des
  Anbieters. Geringe Tragweite, weil Zugriff auf die Datei nötig ist; aber „Löschen" hält nicht, was
  der Nutzer erwartet.
- **FB-08 · Verwaiste Schlüsselbund-Einträge; Fehler beim Entfernen werden verschwiegen.**
  Fundstelle: `Services/PlaylistImporter.swift:242-245` (Altbestand: Eintrag wird nach dem Netzabruf
  geschrieben, ohne zu prüfen, ob die Playlist noch existiert), `:273-277` (erst Datenbank, dann
  Schlüsselbund), `Views/PlaylistsView.swift:106` (`try?` verwirft jeden Fehler). Keine Bereinigung
  beim Start.
  Folge: Das Passwort bleibt im Schlüsselbund, ohne dass eine Playlist darauf verweist (AK-35,
  EC-08). Der Nutzer sieht das nicht und kann es in der App nicht entfernen, nur in der
  Schlüsselbundverwaltung bzw. gar nicht (iOS).
- **FB-09 · Kein Weg, alle Daten zu entfernen; App löschen entfernt nicht alles, entgegen der Website.**
  Fundstelle: keine Funktion dafür in `Sources/`; Speicherorte aus `AppPersistence.swift:61-65`,
  `XtreamCredentialStore.swift:26-30`, `URLCache.shared`. Die Website sagt „deleting the app removes
  all of it" (`web/app/privacy/page.tsx:38-39`, Arbeitsbaum 2026-09-16; vgl. BF-20 für B10).
  Folge: Unter macOS bleiben nach dem Löschen der App Datenbank, Cache, Einstellungen und
  Schlüsselbund-Einträge mit Passwörtern zurück; unter iOS die Schlüsselbund-Einträge. Seit der
  B01-Reparatur liegt das Passwort genau dort, wo das Löschen der App es am wenigsten erreicht
  (AK-36).

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den
Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Aktualisieren/Löschen blockieren minutenlang | ⚠ AK-37, AK-38 + FB-01 | PRD und Website versprechen Bedienbarkeit bei 17.000 Sendern; B01 hat denselben Pfad beim Import als hoch eingestuft |
| 2 | Favoriten vervielfachen sich | ⚠ AK-10 + FB-02 | Absicht eindeutig (ein Stern soll ein Stern bleiben); Website beschreibt Wiedererkennung, nicht Vermehrung. Kein Sicherheitspunkt, aber eine offene Frage wäre Zurechtrücken durch Unterlassen |
| 3 | Ein Ladeindikator für alle | ⚠ AK-13 + FB-03 | App-Shell beschreibt den Spinner „in der betroffenen Karte"; Absicht eindeutig |
| 4 | Mehrfaches Aktualisieren ungesperrt | ⚠ AK-14 + FB-04 | `sicherheit.md` 4 (wiederholte Anfragen mit Zugangsdaten an Dritte); gleiche Lage wie B01 BUG-09 |
| 5 | Gehaltene Sender nach Löschen/Aktualisieren | ⚠ AK-27 bis AK-29 + FB-05 | `sicherheit.md` 5.2: Nach dem Löschen läuft eine Verbindung mit Zugangsdaten weiter; DM-10 war als Prüfpunkt benannt |
| 6 | M3U-Abrufe im Plattencache nach Löschen | ⚠ AK-33 + FB-06 | `sicherheit.md` 5.2/5.3: Kopie außerhalb der Datenbank, die das Löschen übersteht; wie B01 FB-03 und B04 FB-07 |
| 7 | Bytes gelöschter Sender in freien Seiten | ⚠ AK-34 + FB-07 | `sicherheit.md` 5.2; beim Ausführen gefunden. Geringe Tragweite ausdrücklich vermerkt |
| 8 | Verwaiste Schlüsselbund-Einträge, verschwiegene Fehler | ⚠ AK-35 + FB-08 | `sicherheit.md` 5.2 und 6: Passwort bleibt ohne Bezug und ohne Löschweg |
| 9 | App löschen entfernt nicht alles | ⚠ AK-36 + FB-09 | Website verspricht es; `sicherheit.md` 5.1/5.2 |
| 10 | Löschen ohne Rückfrage und Rückgängig | ⚠ AK-22 + OF-01 | kein Sicherheitspunkt, nirgends als gewollt beschrieben, Absicht nicht ableitbar (manche Apps löschen bewusst sofort); DM-08 war Prüfpunkt |
| 11 | Kürzere Liste ersetzt ohne Rückfrage, Favoriten gehen verloren | ⚠ AK-11 + OF-02 | kein Sicherheitspunkt; Website verspricht nur Robustheit gegen Umsortieren, und die hält |
| 12 | Meldung „Zugangsdaten fehlen" empfiehlt Löschen | ⚠ AK-21 + OF-06 | Absicht aus B01 (Annahme 16, OF-09) bekannt, Folge für Favoriten offen |
| 13 | Letzte Aktualisierung nicht angezeigt | AK-05 + OF-03 | kein Sicherheitspunkt, Absicht nicht ableitbar |
| 14 | Leerzustand nennt nur M3U | AK-02 + OF-04 | Text stammt aus der Zeit vor Xtream; ob gewollt, nicht ableitbar |
| 15 | Datei-Playlist nicht aktualisierbar | reguläres AK-16 + OF-05 | Code-Kommentar `PlaylistImporter.swift:208` („Lokale Datei: sourceURL bleibt nil -> nicht refreshbar") und PRD („Aktualisieren (nur Remote-Playlists)") beschreiben es als gewollt; nur der Wunsch nach Neueinlesen ist offen |
| 16 | Favoriten-Erhalt über tvg-ID bzw. Name | reguläres AK-09 | README, CLAUDE.md und Website beschreiben es als gewollt |
| 17 | Alte Liste bleibt bei Fehlern erhalten | reguläre AK-18 bis AK-20 | Verhalten schützt die Daten des Nutzers; kein Widerspruch zu Dokumentation |
| 18 | Löschen während Aktualisieren ohne Meldung | reguläres AK-26 | Ergebnis ist das, was der Nutzer mit dem Löschen wollte; SwiftData-Protokollzeilen enthalten keine Nutzdaten (AK-31) |
| 19 | Absturz im Multiview-Raster beim Leeren | nur Randnotiz unter *Nicht im Scope* | gehört zu B08; in der Sonde nur über einen Weg ausgelöst, den die App selbst so nicht geht |
