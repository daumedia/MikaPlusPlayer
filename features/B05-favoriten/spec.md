# B05 · Favoriten — Spezifikation

Status: `rekonstruiert` · Stand: `c01f1cf` + Reparatur B01 (2026-09-16) · Rekonstruktion aus dem Code (sdd-erfassen)

> **Gelesener und ausgeführter Code-Stand: `c01f1cf` + Reparatur B01 (2026-09-16),** eingefroren als
> Schnappschuss. Die Dateien des Features — `Views/FavoritesView.swift`, `Views/ChannelRowView.swift`,
> `App/ContentView.swift`, `Channel.favoriteKey` und die Favoriten-Logik in
> `PlaylistImporter.refresh`/`attach` — sind gegenüber `c01f1cf` **unverändert**. Die B01-Reparatur
> wirkt nur am Rand: Die Datenbank liegt unter macOS jetzt in
> `~/Library/Application Support/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store` statt in
> `default.store` (die Übernahme behält die Favoriten), Xtream-Playlists werden in einem
> Hintergrund-Kontext angelegt, Zugangsdaten liegen im Schlüsselbund, und fehlende oder `null`-Namen
> von Xtream-Sendern werden zu einem leeren Namen statt den Import abzubrechen. Zeilenangaben beziehen
> sich auf diesen Stand. Die parallele Reparatur von B09 ist nicht berücksichtigt.
>
> **Rekonstruiert, nicht geplant.** Beschrieben ist, was der Code **tut**, nicht, was er tun sollte.
> Kriterien mit ⚠ beschreiben fragwürdiges Ist-Verhalten. Sie stehen bewusst als Kriterium hier,
> damit `sdd-qa` sie reproduziert. Wo sie als Fehler eingestuft sind, steht ein Verweis auf
> *Fehlbestand*.
>
> **Wie belegt.** Am 2026-09-16 **ausgeführt** in einer Kopie des Schnappschusses (Scratchpad) unter
> eigener Bundle-ID `lu.daumedia.MikaPlusPlayer.b05probe`, mit abgeschaltetem Sparkle-Feed und
> eigenen Datenbankdateien bzw. In-Memory-Containern; Datenbank und Schlüsselbund des Nutzers blieben
> unberührt. Eine temporäre XCTest-Sonde im Test-Host der Mac-App hat
> (1) die echten Ansichten `ChannelListView` und `FavoritesView` in Fenstern gerendert, den Stern per
> synthetischem Mausklick bedient, den Zustand über den Accessibility-Baum, die Pixelfarbe des Sterns
> und die SQLite-Datei gelesen und Fensteraufnahmen gemacht,
> (2) Aktualisieren über den echten `PlaylistImporter.refresh` gegen einen lokalen Mock
> (`127.0.0.1`, M3U und `player_api.php`) mit erfundenen Listen und Zugangsdaten
> (`qa-user` / `qa-pass-b05`) ausgeführt,
> (3) einen Speicherfehler auf einem vollgeschriebenen 8-MB-Datenträgerabbild erzeugt,
> (4) Abfragedauer und Blockaden des Main-Threads bei 17.000 und 34.000 Sendern gemessen, die SQL-Ausgabe
> von Core Data (`com.apple.CoreData.SQLDebug`) und `EXPLAIN QUERY PLAN` ausgewertet,
> (5) das Systemprotokoll mitgeschnitten und die Logo-Anfragen des Tabs am Mock gezählt.
> Nur macOS; iOS ist *(gelesen)*. Kriterien, die nur aus dem Code stammen, tragen den Vermerk
> *(gelesen)*. Alles ohne Ton: Stream-Adressen zeigten auf einen geschlossenen Port. Kopie, Mock und
> Datenträgerabbild sind wieder gelöscht.
>
> **Evidenz:** `qa-erfassung/sonde-protokoll.txt` (Ausgaben aller Läufe, SQL, Abfrageplan,
> Log-Mitschnitt), `qa-erfassung/sonde.patch` (Sonden-Code und Änderungen der Kopie),
> Fensteraufnahmen `qa-erfassung/mac-01` bis `mac-13`.
>
> **Messumgebung für alle Zeitangaben:** Apple M3 Max, macOS 27.0, **Debug-Build** (Test-Host),
> während parallel Builds anderer Features liefen. Die Zahlen sind **Ist-Werte zur Orientierung,
> keine Zielwerte**.

## Zweck

Der Nutzer markiert Sender, die er regelmäßig schaut, mit einem Stern und findet sie in einem
eigenen Tab „Favoriten" wieder — über alle Playlists hinweg, ohne die jeweilige Senderliste zu
öffnen. Beim Aktualisieren einer Playlist sollen die Markierungen erhalten bleiben, obwohl dabei
alle Sender neu angelegt werden.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| B04 Senderliste | rekonstruiert | Der Stern sitzt in der Senderkarte (`ChannelRowView`), die B04 und B05 teilen; der Tab zeigt dieselben Karten |
| B03 Playlist-Verwaltung | bestand | Aktualisieren ersetzt die Sender und führt die Favoriten über (Kern von B05); Löschen entfernt die Favoriten mit |
| B01 Xtream-Login, B02 M3U-Import | building / bestand | liefern Name und `tvg-id` bzw. `epg_channel_id`, aus denen der Wiedererkennungs-Schlüssel entsteht |

Auf B05 bauen auf: B06 (Tipp auf eine Karte im Tab öffnet den Player), B08 (⊞-Button auch in den
Karten des Tabs, nur macOS).

## User Stories

- **US-01** · Als Nutzer möchte ich einen Sender mit einem Klick als Favorit markieren und die
  Markierung ebenso schnell wieder entfernen.
- **US-02** · Als Nutzer mit mehreren Playlists möchte ich meine Favoriten an einer Stelle sehen,
  damit ich nicht in jeder Senderliste suchen muss.
- **US-03** · Als Nutzer möchte ich, dass meine Favoriten ein Aktualisieren der Playlist überstehen,
  auch wenn der Anbieter seine Liste umsortiert.

## Nicht im Scope

- Senderliste, Suche, Gruppen-Chips, Logos und ihr Laden an sich → **B04**. Hier nur, was der
  Favoriten-Tab davon auslöst (AK-25)
- Kontextmenü „Aktualisieren" und „Löschen", deren Rückfrage, Spinner und Fehler-Alert → **B03**.
  Hier nur, was mit den Favoriten dabei passiert
- Player, der sich aus dem Tab öffnet → **B06**; ⊞-Button → **B08**
- Sortieren nach eigener Reihenfolge, Ordner, Umbenennen von Favoriten, Favoriten je Playlist
  filtern, Suche im Tab: gibt es nicht
- Synchronisation zwischen Geräten: gibt es nicht (PRD, *Nicht im Scope*)

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. Für die Kriterien zum Aktualisieren genügt ein lokaler
HTTP-Server, der eine änderbare M3U-Datei (bzw. `player_api.php`) ausliefert.

### Stern

- **AK-01** · Angenommen, eine Senderliste (B04) oder der Favoriten-Tab ist offen, dann trägt jede
  Senderkarte rechts außen einen Stern: umrandet in Grau, solange der Sender kein Favorit ist, gefüllt
  in Akzentfarbe, wenn er Favorit ist. Auf macOS steht links daneben der ⊞-Button (B08). Der Stern hat
  keinen Tooltip. *(macOS ausgeführt: Fensteraufnahmen `mac-01`, `mac-02`, Farbauswertung grau →
  Akzent; iOS gelesen)*
- **AK-02** · Angenommen, ein Sender ist kein Favorit, wenn sein Stern angeklickt wird, dann ist der
  Stern sofort gefüllt, und die Markierung ist ohne weiteren Schritt dauerhaft gespeichert: Sie steht
  im selben Moment in der Datenbankdatei und übersteht einen Neustart. Ein weiterer Klick hebt die
  Markierung ebenso sofort und dauerhaft auf. Ein schneller Doppelklick schaltet zweimal um; der
  Sender ist danach wieder im Ausgangszustand. *(ausgeführt: Wert in der SQLite-Datei direkt nach dem
  Klick 1 bzw. 0)*
- **AK-03** · Angenommen, eine Senderkarte ist sichtbar, wenn genau der Stern angeklickt wird, dann
  öffnet sich **kein** Player, die Liste bleibt stehen. Ein Klick auf die übrige Karte öffnet den
  Player (B06) und lässt den Stern unverändert. *(macOS ausgeführt mit synthetischen Mausklicks; iOS
  gelesen)*
- **AK-04** · Angenommen, der Favoriten-Tab ist offen (unter macOS z. B. in einem zweiten Fenster),
  wenn ein Sender anderswo markiert oder entmarkiert wird, dann erscheint bzw. verschwindet seine
  Karte im Tab sofort, ohne Neuladen. *(ausgeführt)*
- **AK-05** ⚠ · Angenommen, VoiceOver ist aktiv, dann ist jede Senderkarte **ein einziges** Element
  mit dem Etikett „<Name>, <Gruppe>" (ohne Gruppe nur „<Name>"), unter macOS mit dem Hinweis „Zu
  Multiview hinzufügen". Solange das Logo lädt, meldet sich die Karte als Ladeanzeige (vgl. B04
  AK-22). „Drücken" öffnet den Player. Der Stern ist nur über das Aktionen-Menü erreichbar, als
  **„Favourite"** (englisch), in beiden Zuständen gleich benannt; ob der Sender Favorit ist, sagt
  VoiceOver nicht an. Die Aktion schaltet um. Auch das Symbol des Leerzustands heißt „Favourite".
  *(macOS ausgeführt über den Accessibility-Baum: Aktionen „Rectangle Split Two By Two" und
  „Favourite" vor und nach dem Umschalten gleich; Aktion ausgeführt; iOS gelesen → FB-04, OF-06)*

### Favoriten-Tab

- **AK-06** · Angenommen, die App ist offen, dann gibt es neben „Playlists" einen zweiten Tab
  „Favoriten" mit gefülltem Stern-Symbol und eigenem Navigationsstapel. Oben im Inhalt steht in
  Akzentfarbe „MIKA+PLAYER · FAVORITEN", darunter groß „Favoriten". Unter macOS ist „Favoriten" auch
  Fenstertitel; unter iOS ist die Navigationsleiste ausgeblendet. *(Kopfzeile und Fenstertitel
  ausgeführt; Tab-Leiste und iOS gelesen)*
- **AK-07** · Angenommen, kein Sender in keiner Playlist ist Favorit — auch wenn es gar keine
  Playlists gibt —, dann zeigt der Tab einen umrandeten Stern, „Keine Favoriten" und „Markiere Sender
  mit dem Stern, um sie hier zu sammeln.". Einen Button oder Verweis zum Playlists-Tab gibt es nicht.
  *(ausgeführt, `mac-03`)*
- **AK-08** · Angenommen, Sender aus mehreren Playlists sind Favorit, dann zeigt der Tab alle in einer
  einzigen Liste, mit denselben Karten wie die Senderliste: Logo, Name, Gruppe als Badge, ⊞ (macOS),
  Stern. Es gibt keine Überschrift je Playlist, keine Anzahl, keine Suche und keinen Filter. Ein Klick
  auf eine Karte öffnet den Player im Stapel des Tabs; ein Klick auf den Stern entfernt die Karte aus
  dem Tab. *(ausgeführt, `mac-04`, `mac-05`)*
- **AK-09** ⚠ · Angenommen, zwei Playlists enthalten einen Sender mit gleichem Namen und gleicher
  Gruppe, und beide sind Favorit, dann stehen im Tab zwei gleich aussehende Karten. Nichts zeigt, zu
  welcher Playlist eine Karte gehört; unterscheiden könnte nur ein abweichendes Logo. Die beiden
  stehen in der Reihenfolge, in der die Sender angelegt wurden: der Sender der früher importierten
  Playlist oben. Wer oben den Stern entfernt, entmarkiert also den Sender der älteren Playlist.
  *(ausgeführt: `mac-04`, `mac-05`; Reihenfolge aus dem SQL `ORDER BY ZNAME, Z_PK`; dass ein
  Aktualisieren die Sender der aktualisierten Playlist nach unten rückt, ist daraus abgeleitet →
  OF-02)*
- **AK-10** ⚠ · Angenommen, der Tab zeigt Favoriten, dann sind sie nach dem Namen **in Zeichencode-
  Reihenfolge** sortiert, anders als die Senderliste (B04 AK-09): Leerzeichen und `#` am Anfang
  zuerst, dann Ziffern als Text („100% Hits" vor „1LIVE", „Sport 10" vor „Sport 2"), dann **alle**
  großgeschriebenen vor allen kleingeschriebenen Namen („Zebra" vor „ard alpha"), Umlaute und
  Akzente **hinter** „z" („zdf" vor „Ärger TV", „Écran Plus", „Ö3", „Österreich 1"), danach
  Griechisch, Kyrillisch, Ligaturen und Emoji. Gemessene Reihenfolge von 26 Namen: „ Leerzeichen
  vorn", „#Hash TV", „100% Hits", „1LIVE", „ARD", „Oe24 TV", „Sport 10", „Sport 2", „Strasse 2",
  „Straße TV", „Zebra", „ard alpha", „arte", „ecran basic", „film normal", „istanbul 2", „zdf",
  „Ärger TV", „Écran Plus", „Ö3", „Österreich 1", „İstanbul TV", „Ελληνικά", „Первый канал",
  „ﬁlm ligature", „😀 Emoji TV". *(ausgeführt: gerenderte Ansicht und SQL `ORDER BY t0.ZNAME,
  t0.Z_PK` ohne Kollation → OF-01)*

### Erhalt beim Aktualisieren

Aktualisieren (B03) löscht alle Sender der Playlist und legt sie neu an. Welche neuen Sender Favorit
werden, entscheidet ein Wiedererkennungs-Schlüssel je Sender.

- **AK-11** · Angenommen, eine Playlist wird erfolgreich aktualisiert, dann gilt als Schlüssel eines
  Senders seine `tvg-id` (M3U) bzw. `epg_channel_id` (Xtream), sofern sie nicht leer ist — exakt,
  mit Groß- und Kleinschreibung. Ohne sie gilt der Name in Kleinbuchstaben. Nach dem Aktualisieren ist
  **jeder** neue Sender Favorit, dessen Schlüssel vorher bei mindestens einem Favoriten **derselben**
  Playlist vorkam; alle anderen sind es nicht. *(ausgeführt mit M3U und Xtream)*
- **AK-12** · Angenommen, der Anbieter liefert dieselben Sender in anderer Reihenfolge, mit neuen
  Stream-Adressen bzw. neuen `stream_id`s, dann sind danach dieselben Sender Favorit wie vorher
  (abgesehen von AK-15). Ein umbenannter Sender mit gleicher `tvg-id` bleibt Favorit („Beta" →
  „Beta HD"). *(ausgeführt)*
- **AK-13** · Angenommen, ein Favorit hat keine `tvg-id`, dann bleibt er über den Namen erhalten, wenn
  sich nur Groß- und Kleinschreibung ändert („Sport1" → „SPORT1", „München TV" → „MÜNCHEN TV") oder
  derselbe Name in anderer Unicode-Form ankommt („Café" zusammengesetzt bzw. mit kombinierendem
  Akzent). Er geht verloren, wenn der Name anders geschrieben wird: umbenannt („DE: Sky Sport 1" →
  „DE | Sky Sport 1"), „ß" statt „SS" („Straße TV" → „STRASSE TV"), „İ" statt „I" („İstanbul TV" →
  „ISTANBUL TV"), anderes Leerzeichen im Namen („Kanal  Zwei" → „Kanal Zwei"). Leerzeichen am Rand
  spielen bei M3U keine Rolle, weil der Import sie entfernt (B02); bei Xtream zählen sie mit.
  *(ausgeführt; Leerzeichen am Rand gelesen)*
- **AK-14** ⚠ · Angenommen, ein Favorit ist in der neuen Liste nicht mehr als derselbe Schlüssel
  enthalten, weil seine `tvg-id` die Schreibweise ändert („ard.de" → „ARD.de", „kika.de" →
  „KiKA.de"), eine `tvg-id` neu hinzukommt oder wegfällt, oder weil der Sender fehlt, dann ist die
  Markierung weg, ohne Hinweis. Kommt der Sender bei einer späteren Aktualisierung zurück, ist er kein
  Favorit mehr. Passt kein einziger Sender, sind alle Favoriten der Playlist weg, und das
  Aktualisieren gilt trotzdem als Erfolg. *(ausgeführt → OF-03)*
- **AK-15** ⚠ · Angenommen, mehrere Sender einer Playlist haben denselben Schlüssel — dieselbe
  `tvg-id` (z. B. „ZDF HD", „ZDF SD", „ZDF FHD"), denselben Namen ohne `tvg-id` auch in anderer
  Schreibweise („News", „News", „NEWS"), eine `tvg-id` nur aus Leerzeichen, oder bei Xtream Sender
  ohne Namen und ohne `epg_channel_id` —, und nur einer davon ist Favorit, dann sind nach dem
  nächsten Aktualisieren **alle** Favorit, auch wenn sich an der Liste nichts geändert hat. Entfernt
  der Nutzer die zusätzlichen Sterne, setzt das nächste Aktualisieren sie wieder. Markiert er statt
  „ZDF HD" nur „ZDF SD", sind danach wieder alle drei markiert. *(ausgeführt: 14 Favoriten → 19 beim
  ersten Aktualisieren einer unveränderten Liste; nach Entfernen der Dubletten 7 → wieder 12; Xtream
  4 → 5 bei zwei verlorenen und drei hinzugekommenen; im Tab sichtbar `mac-10` → `mac-11` → FB-01)*
- **AK-16** · Angenommen, zwei Playlists enthalten Sender mit derselben `tvg-id`, dann ändert das
  Aktualisieren der einen Playlist nur deren Favoriten: Der Sender der anderen Playlist behält seinen
  Stern bzw. bekommt keinen. *(ausgeführt in beide Richtungen)*
- **AK-17** · Angenommen, das Aktualisieren scheitert (HTTP-Fehler, leere Liste, fehlende
  Xtream-Zugangsdaten), dann bleiben alle Sender und alle Favoriten der Playlist unverändert, und B03
  zeigt die Meldung. *(ausgeführt: „Netzwerkfehler: HTTP 500" und „Die Playlist enthält keine gültigen
  Sender.", dieselben Senderobjekte danach; fehlende Zugangsdaten gelesen, in B01 getestet)*
- **AK-18** · Angenommen, eine Playlist stammt aus einer lokalen Datei, dann lässt sie sich nicht
  aktualisieren (B03), und ihre Favoriten bleiben, bis der Nutzer sie ändert oder die Playlist löscht.
  *(ausgeführt: Aktualisieren ist wirkungslos)*
- **AK-19** · Angenommen, der Favoriten-Tab ist offen oder ein aus dem Tab geöffneter Player läuft,
  wenn die Playlist aktualisiert wird, dann zeigt der Tab ohne Neuladen den neuen Stand (einschließlich
  AK-15), und der Player bleibt offen; die App stürzt nicht ab. *(ausgeführt; was der Player dabei
  sonst tut, gehört zu B03/B06, vgl. DM-10)*

### Löschen

- **AK-20** ⚠ · Angenommen, eine Playlist mit Favoriten wird gelöscht (B03), dann verschwinden ihre
  Favoriten sofort aus dem Tab, ohne Hinweis darauf, dass Favoriten betroffen sind; Favoriten anderer
  Playlists bleiben. Wird dieselbe Quelle erneut importiert, sind ihre Sender keine Favoriten mehr.
  *(ausgeführt: `mac-06` → `mac-07`, kein Alert; Rückfrage und Rückgängig → B03 bzw. DM-08 → OF-04)*
- **AK-21** · Angenommen, der Nutzer will seine Favoriten loswerden, dann geht das nur Stern für Stern
  oder mit der ganzen Playlist. Einen Befehl „Alle Favoriten entfernen", einen Export oder eine
  Sicherung der Favoriten gibt es nicht. *(gelesen → OF-05)*

### Datenschutz und Missbrauchsschutz

Fragenkatalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog). Favoriten sind ein
**Nutzungsprofil**: Sie zeigen, was jemand regelmäßig schaut. Jede Frage hat ein Kriterium, ein
„trifft nicht zu, weil …" oder einen Eintrag im *Fehlbestand*.

- **AK-22** · Angenommen, ein Sender ist Favorit, dann ist das als Merkmal dieses Senders in der
  App-Datenbank gespeichert, sonst nirgends (keine Einstellungen, kein iCloud, kein Server). Unter
  macOS ist das `~/Library/Application Support/lu.daumedia.MikaPlusPlayer/MikaPlusPlayer.store` samt
  `-wal` und `-shm`, Dateirechte `rw-r--r--` in einem Ordner `rwxr-xr-x` unterhalb von `~/Library`
  (`rwx------`); unter iOS der App-Container. *(Pfadbildung und Rechte ausgeführt über die Funktionen
  der App in einem Probeordner; iOS gelesen)*
- **AK-23** · Angenommen, der Nutzer sichert sein Gerät (Time Machine, iCloud- oder Geräte-Backup),
  dann enthält die Sicherung die Datenbank und damit die Favoriten; die Datei ist nicht vom Backup
  ausgeschlossen. *(ausgeführt: `isExcludedFromBackup = false`; die Begründung steht im Code, siehe
  Decision Log)*
- **AK-24** · Angenommen, unter macOS läuft ein anderes Programm desselben Benutzers, dann kann es die
  Datenbank und damit die Favoriten lesen; andere Benutzer des Macs können es nicht. *(ausgeführt: ein
  separater `sqlite3`-Prozess las die Probedatenbank; Sandbox aus laut `MikaPlusPlayer.entitlements`)*
- **AK-25** ⚠ · Angenommen, Favoriten haben Logo-Adressen, wenn der Favoriten-Tab geöffnet wird, dann
  fragt die App **genau die Logos der sichtbaren Favoriten** an und keine anderen. Jeder Logo-Host
  erhält dabei die IP-Adresse, den User-Agent `Mika+Player/<Build> CFNetwork/<Version>
  Darwin/<Version>` und die Systemsprache (`Accept-Language: de-DE,de;q=0.9`), keine Cookies und
  keinen Referer. Ein Host, der die Logos mehrerer Sender ausliefert, kann daraus die Favoritenliste
  des Nutzers ablesen, erneut bei jedem Öffnen des Tabs, soweit die Logos nicht im Cache liegen (B04
  AK-28). *(ausgeführt: 3 Favoriten unter 20 Sendern mit Logos auf dem Mock → genau 3 Anfragen, genau
  diese Logos, `mac-13` → FB-03)*
- **AK-26** · Angenommen, ein Stern wird mehrfach umgeschaltet und der Tab ist offen, dann erscheinen
  Sendername, Playlistname und `tvg-id` nicht im Systemprotokoll. *(ausgeführt: `log stream --level
  debug` auf den App-Prozess, 6.830 Zeilen, kein Treffer; kein `print`/`Logger` im Code)*
- **AK-27** ⚠ · Angenommen, die Datenbank lässt sich nicht schreiben (z. B. Datenträger voll), wenn
  ein Stern angeklickt wird, dann zeigt der Stern trotzdem den neuen Zustand, und der Tab nimmt die
  Karte auf bzw. entfernt sie — gespeichert ist nichts, und es erscheint **keine Meldung**. Nach einem
  Neustart ist der alte Zustand zurück. Die ausstehende Änderung wird erst mit dem nächsten
  erfolgreichen Speichern mitgeschrieben, z. B. beim nächsten Stern, wenn wieder Platz ist; das
  automatische Speichern hat sie innerhalb von 3 s nach dem Freigeben nicht nachgeholt. Der Fehler
  steht nur im Systemprotokoll („SwiftData.DefaultStore save failed … NSSQLiteErrorDomain=13").
  *(ausgeführt auf einem vollen 8-MB-Datenträgerabbild, `mac-08`, `mac-09` → FB-02)*
- **AK-28** · Angenommen, eine Playlist mit Favoriten wurde gelöscht, dann sind ihre Sender aus der
  Datenbank entfernt. Solange die App läuft, stehen Namen gelöschter Sender noch im Write-Ahead-Log
  (`-wal`); nach dem Beenden ist in keiner Datenbankdatei mehr etwas davon zu finden. *(ausgeführt:
  2 Vorkommen des Markers im `-wal` nach dem Löschen, 0 nach Prozessende; `secure_delete = FAST`)*

### Leistung

Gemessene **Ist-Werte, keine Zielwerte.** Messumgebung siehe Kopf.

- **AK-29** · Angenommen, die Datenbank enthält 17.000 Sender mit 50 Favoriten bzw. 34.000 Sender mit
  100 Favoriten, dann gilt für den Tab: Die Abfrage läuft in der Datenbank
  (`WHERE ZISFAVORITE = ? ORDER BY ZNAME, Z_PK`), **ohne Index** (`EXPLAIN QUERY PLAN`: `SCAN`, `USE
  TEMP B-TREE FOR ORDER BY`), und ist trotzdem schnell:

  | Vorgang | 17.000 / 50 | 34.000 / 100 |
  |---|---|---|
  | Favoriten laden, kalt / warm | 1,9 ms / 1,0 ms | 3,4 ms / 2,0–2,2 ms |
  | Favoriten zählen | 0,4 ms | 0,9 ms |
  | Tab öffnen, längste Blockade des Main-Threads | 70 ms | — |
  | Stern im Tab entfernen: Klick / längste Blockade danach | 9 ms / 26 ms | — |
  | Stern in der offenen Senderliste (17.000): Klick / längste Blockade, mit offenem Tab | 64–86 ms / 292–309 ms | — |
  | dasselbe ohne offenen Tab | 90–94 ms / 226–318 ms | — |

  Der offene Tab verlängert das Umschalten in der Senderliste nicht messbar; die Blockade stammt von
  der Senderliste selbst (B04 AK-34). *(ausgeführt)*
- **AK-30** · Angenommen, eine Playlist mit 17.000 Sendern wird aktualisiert, dann lädt die App zum
  Merken der Favoriten alle ihre Sender als Objekte: 1.079 ms beim ersten Mal auf dem Main-Thread
  (1.135 ms bei 34.000 Sendern in der Datenbank), 10–11 ms, wenn sie schon geladen sind. Das kommt zur
  Dauer des Aktualisierens hinzu (B03, DM-07). *(ausgeführt, nur dieser Schritt)*

#### Katalog, Frage für Frage

| # | Katalogfrage | Antwort für B05 |
|---|---|---|
| 1.1 | Welche personenbezogenen Daten? | Die Favoritenliste als Nutzungsprofil: welche Sender jemand regelmäßig schaut, zusammen mit der Playlist, also dem Anbieter. Gegenüber Logo-Hosts zusätzlich IP-Adresse, Systemversion, App-Build und Sprache, verknüpft mit genau diesen Sendern (AK-25) |
| 1.2 | Besondere Kategorien? | Möglich: Religiöse, politische oder muttersprachliche Sender und Erwachsenenkanäle unter den Favoriten lassen auf Religion, politische Meinung, Herkunft oder Sexualleben schließen. Das PRD begründet Stufe B statt C damit, dass Favoriten das Gerät nie verlassen (`docs/prd.md:92-93`). Für die Datenbank trifft das zu (abgesehen von Backups des Nutzers, AK-23); über die Logo-Anfragen des Tabs verlassen Rückschlüsse das Gerät doch → **FB-03** |
| 1.3 | Wo gespeichert, wie lange? | App-Datenbank (AK-22), unbefristet: bis der Nutzer den Stern entfernt, die Playlist löscht (AK-20) oder die App samt Daten entfernt. Im `-wal` bis zum Checkpoint (AK-28), in Backups nach deren Regeln (AK-23). Eine Löschfrist gibt es nicht und braucht es für eine vom Nutzer selbst gesetzte Markierung nicht |
| 1.4 | Landen sie in Logs? | Nein (AK-26). Ein Speicherfehler protokolliert nur den Dateipfad, keine Sender (AK-27) |
| 2.1 | Welche externen Dienste? | Keine, die B05 selbst anspricht. Indirekt die Logo-Hosts aus der Playlist, die der Tab beim Öffnen anfragt (AK-25). Kein Sync, kein Analyse- oder Fehlerdienst |
| 2.2 | Was wird übertragen, was vorher entfernt? | An Logo-Hosts: IP, Kopfzeilen und, durch die Auswahl der Anfragen, die Favoriten. Entfernt wird nichts, abschalten lässt es sich nicht → **FB-03** |
| 2.3 | Standort des Dienstes, AV-Vertrag? | Trifft nicht zu, weil weder der Nutzer noch daumedia die Logo-Hosts auswählt — sie stehen in der Playlist des Anbieters —, und daumedia dabei nichts verarbeitet. iCloud-Backups laufen im Vertragsverhältnis zwischen Nutzer und Apple |
| 2.4 | Training mit dem Payload? | Trifft nicht zu, weil kein KI-Dienst beteiligt ist |
| 3.1 | Wer darf sehen, ändern, löschen? | Der lokale Nutzer alles, über Stern und Playlist. Unter macOS lesen außerdem alle Programme desselben Benutzers mit (AK-24); andere Benutzer nicht. iOS: nur die App |
| 3.2 | Erzwungen in DB oder Anwendung? | Nur durch das Betriebssystem: Dateirechte und `~/Library` unter macOS, App-Sandbox unter iOS. Die Mac-App läuft bewusst ohne Sandbox (CLAUDE.md) |
| 3.3 | Fremde ID? | Trifft nicht zu, weil es keinen Server und keine per ID abrufbaren Ressourcen gibt |
| 3.4 | Rollen? | Trifft nicht zu, weil die App keine Konten und keine Rollen hat |
| 4.1 | Rate Limit Anmeldung | Trifft nicht zu, weil B05 keine Anmeldung hat |
| 4.2 | Rate Limit für Kostenpflichtiges | Trifft nicht zu, weil B05 keinen kostenpflichtigen Dienst ruft |
| 4.3 | Kosten je Aufruf | Trifft nicht zu. Rechenzeit: AK-29, AK-30 |
| 4.4 | Unvertraute Eingaben: Größe, Typ, Inhalt | Name und `tvg-id` stammen vom Anbieter und bestimmen den Schlüssel. Eine Liste mit wiederholten `tvg-id`s oder Namen vervielfacht die Favoriten des Nutzers (AK-15 → **FB-01**). Längen begrenzt nur B01 für Xtream (512 Zeichen) |
| 4.5 | Wo greift das Limit? | Nirgends; für B05 ist keines nötig |
| 5.1 | Konto selbst löschen? | Trifft nicht zu, weil die App kein Konto hat |
| 5.2 | Was wird dabei gelöscht? | Stern entfernen: nur die Markierung (AK-02). Playlist löschen: alle Sender samt Favoriten (AK-20). App entfernen: unter iOS der Container; unter macOS bleibt die Datenbank in `~/Library/Application Support` liegen, wenn nur das Programm gelöscht wird (gelesen; die Website sagt anderes → BF-20 aus B10) |
| 5.3 | Was bleibt, und warum? | Backups (AK-23, bewusst), der `-wal` bis zum Checkpoint (AK-28), Logo-Adressen und -Bilder der Favoriten im HTTP-Cache (B04 FB-07) |
| 5.4 | E-Mail-Adresse wieder frei? | Trifft nicht zu, weil die App keine Registrierung hat |
| 5.5 | Datenexport? | Trifft als Auskunftsrecht nicht zu, weil daumedia keine Daten erhält. Einen Export für den Nutzer selbst gibt es nicht (AK-21 → OF-05) |
| 6.1 | Welche Schlüssel braucht das Feature? | Keine |
| 6.2 | Welche dürfen zum Client? | Trifft nicht zu, weil es keinen Server gibt |
| 6.3 | Steht Echtes im Repository? | Trifft für B05 nicht zu, weil die Dateien keine Adressen, Schlüssel oder Zugangsdaten enthalten; die Git-Historie ist in B01 AK-30 geprüft |
| 6.4 | Vorlagen `.env.example` / `Secrets.example.xcconfig` | Trifft nicht zu, weil B05 keine Build-Geheimnisse braucht |

## Edge Cases

Ist-Verhalten. „(ausgeführt)" heißt mit der Sonde belegt, „(gelesen)" heißt aus dem Code abgeleitet.

- **EC-01** · Zwei gleichnamige Sender **in derselben** Playlist ohne `tvg-id`, einer markiert → im
  Tab eine Karte; nach dem nächsten Aktualisieren zwei gleich aussehende Karten (AK-15). *(ausgeführt)*
- **EC-02** · Xtream-Sender ohne Namen (`name` leer, fehlend oder `null`) → Karte ohne Namen. Alle
  namenlosen Sender ohne `epg_channel_id` teilen sich den Schlüssel „leerer Name"; wer einen markiert,
  hat nach dem Aktualisieren alle markiert. Seit der B01-Reparatur betrifft das auch fehlende und
  `null`-Namen, die vorher den Import scheitern ließen. *(ausgeführt)*
- **EC-03** · `tvg-id=" "` (nur Leerzeichen) bei mehreren Sendern → gilt als vorhandene `tvg-id`, alle
  teilen einen Schlüssel (AK-15). *(ausgeführt)*
- **EC-04** · Stern angeklickt, während dieselbe Playlist gerade aktualisiert wird → Solange die App auf
  die Antwort des Anbieters wartet, wird der Klick gespeichert und beim Merken der Favoriten
  berücksichtigt. Merken, Löschen und Neuanlegen laufen danach ohne Unterbrechung am Stück; ein Klick
  kann nicht dazwischenfallen. *(gelesen, nicht ausgeführt)*
- **EC-05** · Nach Wiederherstellung auf einem neuen Gerät fehlen die Xtream-Zugangsdaten (B01 OF-09):
  Die Favoriten sind da, Abspielen und Aktualisieren melden aber „Die Zugangsdaten dieser
  Xtream-Playlist fehlen auf diesem Gerät. Bitte die Playlist löschen und neu importieren." Wer der
  Meldung folgt, verliert die Favoriten dieser Playlist (AK-20). *(gelesen)*
- **EC-06** · Erster Start nach dem Update mit alter `default.store` bzw. mit Zugangsdaten in den
  Adressen → Übernahme und Umstellung behalten die Favoriten. *(gelesen; B01-Tests
  `testBUG01_MigrationVorhandenerDatenbankOhneDatenverlust`, `testBUG01_MigrationMit17000Sendern`)*
- **EC-07** · Zwei Hauptfenster (macOS), Stern im einen, Tab im anderen → Tab folgt sofort (AK-04).
  *(ausgeführt mit zwei Fenstern auf denselben Container)*
- **EC-08** · Stern im Favoriten-Tab entfernt, während derselbe Sender in einer Senderliste sichtbar
  ist → die Senderliste zeigt den grauen Stern ohne Neuladen. *(gelesen: beide Karten beobachten
  dasselbe Objekt)*
- **EC-09** · Sehr viele Favoriten (mehrere Tausend) → nicht gemessen. Der Tab lädt alle Favoriten als
  Objekte; bei 17.000 Treffern kostet das in der Senderliste rund 250 ms (B04 AK-34). *(nicht
  ausgeführt)*
- **EC-10** · iOS: Tipp auf den Stern innerhalb der als Link wirkenden Karte → nicht ausgeführt, weil es
  keine iOS-Tests gibt; der Aufbau ist derselbe wie unter macOS. *(gelesen)*
- **EC-11** · Import derselben Quelle als zweite Playlist (B01 AK-09) → die neuen Sender sind keine
  Favoriten; Favoriten der ersten Playlist bleiben unberührt (AK-16). *(abgeleitet aus AK-16, AK-20)*

## Offene Fragen

Alle vom 2026-09-16. Entscheidung durch den Nutzer (Michael Ferreira), vor der Reparaturrunde
nach der QA von B05.

- **OF-01** · Soll der Tab wie die Senderliste sprachgerecht sortieren (Umlaute beim Grundbuchstaben,
  Groß- und Kleinschreibung gleich, ggf. Zahlen als Zahlen, vgl. B04 OF-01) statt nach Zeichencode
  (AK-10)?
- **OF-02** · Soll der Tab zeigen, aus welcher Playlist ein Favorit stammt, oder nach Playlist gruppieren
  (AK-09)?
- **OF-03** · Soll ein Favorit, der beim Aktualisieren nicht wiedererkannt wird, mit Hinweis entfallen
  oder gemerkt werden, bis der Sender zurückkommt (AK-14)? Und soll der Namensvergleich großzügiger
  sein (ß/SS, İ/I, mehrfache Leerzeichen, `tvg-id` ohne Groß-/Kleinunterschied) (AK-13)?
- **OF-04** · Soll das Löschen einer Playlist sagen, wie viele Favoriten dabei verloren gehen, oder
  sollen Favoriten einen erneuten Import derselben Quelle überstehen (AK-20)? Die Rückfrage vor dem
  Löschen an sich gehört zu B03 (DM-08).
- **OF-05** · Braucht es „Alle Favoriten entfernen" und eine Möglichkeit, Favoriten zu sichern oder auf
  ein anderes Gerät mitzunehmen (AK-21)?
- **OF-06** · Soll die VoiceOver-Beschriftung des Sterns deutsch sein („Favorit") statt des englischen
  Systemnamens „Favourite" (AK-05)? Gleiche Lage wie B07 OF-03 und B04 OF-03.
  *Stand 2026-09-30 (sdd-build, Reparatur BUG-04, nicht beantwortet):* Der Fehlerauftrag verlangte
  deutsche Aktionsnamen; gebaut ist „Favorit hinzufügen" bzw. „Favorit entfernen" je Zustand, dazu der
  Wert „Favorit" an der Karte, und das Stern-Symbol des Leerzustands ist für VoiceOver ausgeblendet
  (Begründung: App-Oberfläche nur Deutsch laut PRD; wie `PlayerView`, das Symbole aus demselben Grund
  ausblendet). Der ⊞-Button daneben heißt weiter „Rectangle Split Two By Two" (B08). Zur Bestätigung
  durch den Nutzer.
- **OF-07** · Die Website sagt „Star a channel anywhere" (`web/content/features.ts:18`). Einen Stern gibt
  es in der Senderliste und im Tab, nicht im Player und nicht im Multiview. Soll er dort auch hin, oder
  ist „anywhere" so gemeint?

Ergänzt beim Bau der Reparatur (sdd-build, 2026-09-30). Nicht gebaut, weil Produktentscheidung:

- **OF-08** · Soll der Favoriten-Tab Senderlogos überhaupt laden – oder nur schon geladene aus dem
  Arbeitsspeicher zeigen, abschaltbar bzw. erst nach Zustimmung (BUG-03, AK-25; gleiche Frage für die
  Senderliste: B04 OF-07)? Seit der B04-Reparatur lädt der Tab über denselben `ChannelLogoLoader` wie die
  Senderliste: neutrale Kopfzeilen (`User-Agent: Mozilla/5.0`, `Accept-Language: *`), keine Weiterleitung
  auf fremde Hosts, kein Plattencache, erneutes Öffnen ohne erneute Anfrage (belegt:
  `B05ReparaturTests.testBUG03_…`). Beim ersten Öffnen erfährt jeder Logo-Host aber weiter die IP-Adresse
  und – weil der Tab genau die Favoriten zeigt – die Favoritenliste. Ganz vermeiden ließe sich das nur
  ohne Anfrage (Platzhalter bzw. nur Logos, die die Senderliste in dieser Sitzung schon geladen hat) oder
  mit einem Schalter, den es mangels Einstellungen noch nicht gibt; beides verändert sichtbar, was der Tab
  zeigt. Die FAQ „Nowhere" und die PRD-Begründung der Stufe B stimmen bis dahin nicht (BF-20, B10).
- **OF-09** · Sollen Steuerzeichen in Senderdaten weiter gefasst entfernt werden (BUG-09)? Gebaut ist:
  Beim Anlegen und Aktualisieren (M3U und Xtream) entfallen U+0000–U+001F und U+007F in Name, Gruppe und
  `tvg-id`, außer Tabulator und Zeilenumbrüchen (sichtbar; ein Zeilenumbruch in einer Gruppe ist laut B04
  AK-11 eine eigene Gruppe). Nicht entfernt werden die Steuerzeichen U+0080–U+009F (entstehen beim
  Latin-1-Rückfall aus Umlauten, B02 EC-07/EC-08, B02 OF-06) und Formatzeichen wie U+202E (B02 EC-06). Ein
  Favorit, der **vor** der Reparatur einen Namen oder eine `tvg-id` mit NUL-Zeichen hatte, ist in der
  Datei schon gekürzt gespeichert und geht beim ersten Aktualisieren danach einmal verloren (vorher ging
  er bei jedem Aktualisieren verloren); andere Steuerzeichen in Altbeständen erkennt der Schlüssel wieder.

Ergänzt beim Abschluss der Reparatur (sdd-build, 2026-10-01). Nicht gebaut, weil es das in B04 festgelegte
Verhalten aller Karten ändert:

- **OF-10** · Soll die Senderkarte für VoiceOver auch dann „Favorit“ ansagen, solange ihr Logo noch lädt
  (BUG-04, AK-05)? Während des Ladens – bis 10 s ohne Daten, 15 s insgesamt, bei vielen Logos eines Hosts
  länger (B04 Review R-3) – meldet sich die Karte wie in AK-05 und B04 AK-22 beschrieben als Ladeanzeige
  (`AXBusyIndicator`, Wert „0“); der Wert „Favorit“ fehlt dann, den Zustand verrät nur der Aktionsname
  („Favorit entfernen“ statt „Favorit hinzufügen“). Belegt mit einer Prüfsonde am 01.10. (Logo-Host hängt:
  nach 2 s und 5 s `AXBusyIndicator`/„0“, nach Ablauf der Frist `AXButton`/„Favorit“). Abhilfe wäre, den
  Ladeindikator für VoiceOver auszublenden – für alle Karten der Senderliste und des Tabs.

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus dem Code belegt. Kein Kriterium: `sdd-qa` prüft
nichts davon als bestanden, sondern nimmt es als Suchliste. Zeilenangaben beziehen sich auf
`Sources/` im Stand `c01f1cf` + Reparatur B01.

- **FB-01 · Aktualisieren vervielfacht Favoriten und macht Entfernen rückgängig.**
  Fundstelle: `Models/Channel.swift:49-52` bildet einen Schlüssel, der nicht eindeutig ist (`tvg-id`
  ohne Prüfung auf Leerzeichen, sonst Name in Kleinbuchstaben, auch leer).
  `Services/PlaylistImporter.swift:253` merkt nur die **Menge** der Schlüssel, nicht, welcher Sender
  markiert war; `:299` markiert jeden neuen Sender mit passendem Schlüssel. Dazu
  `Services/M3UParser.swift:113` (`tvg-id` aus Leerzeichen bleibt stehen) und
  `Services/XtreamClient.swift:106, 112` (leere Namen). Entspricht DM-06.
  Folge: Bei Xtream-Anbietern tragen HD-, FHD-, SD- und 4K-Varianten üblicherweise dieselbe
  `epg_channel_id`. Wer eine Variante markiert, hat nach dem nächsten Aktualisieren alle markiert, und
  jeder entfernte Stern kommt beim nächsten Aktualisieren zurück. Die Auswahl des Nutzers bleibt also
  nicht erhalten, sie wird verändert — entgegen dem Code-Kommentar („Schlüssel, über den **ein** Channel
  beim Refresh wiedererkannt wird", `Channel.swift:47-48`) und der Website („does not wipe your
  selection", `web/content/features.ts:18`). (AK-15)
- **FB-02 · Speicherfehler beim Umschalten werden verschluckt.**
  Fundstelle: `Views/ChannelRowView.swift:61-62`: `channel.isFavorite.toggle()` und danach
  `try? modelContext.save()`; kein Zurücksetzen, keine Meldung.
  Folge: Stern und Tab zeigen einen Zustand, der nicht gespeichert ist und nach dem Neustart
  verschwindet — bei vollem Datenträger, schreibgeschützter oder gesperrter Datenbank. Der Nutzer
  erfährt es nicht; die Änderung wird erst mit dem nächsten erfolgreichen Speichern nachgeholt, das der
  Nutzer nicht erkennt. `docs/datenmodell.md` beschreibt `isFavorite` als „sofort gespeichert"; die
  Absicht ist eindeutig. (AK-27)
- **FB-03 · Der Favoriten-Tab verrät die Favoritenliste an Logo-Hosts.**
  Fundstelle: `Views/FavoritesView.swift:8-12, 22-28` zeigt genau die Favoriten als Karten;
  `Views/ChannelRowView.swift:36` lädt deren Logos, sobald die Karten sichtbar sind, über HTTP erlaubt
  durch `Resources/Info.plist:39-40`. Es gibt keine Einstellung, Logos im Tab nicht zu laden.
  Folge: Jeder Host, der mehrere Logos einer Playlist ausliefert — oft der Anbieter selbst oder ein
  gemeinsamer Logo-Dienst —, erhält bei jedem Öffnen des Tabs eine Anfrageserie, die aus genau den
  Favoriten besteht, verknüpft mit IP-Adresse, Systemversion und Sprache. Favoriten können besondere
  Kategorien berühren (Katalog 1.2). Das widerspricht der Begründung der Datenschutzstufe im PRD
  („verlassen das Gerät aber nie", `docs/prd.md:92-93`) und der FAQ „Where does my data go? Nowhere."
  (`web/content/faq.ts:40`, als BF-20 für B10 erfasst). Allgemeiner Befund zum Logo-Laden: B04 FB-06.
  (AK-25)
- **FB-04 · Favoriten-Zustand für VoiceOver nicht wahrnehmbar.**
  Fundstelle: `Views/ChannelRowView.swift:59-69` setzt für den Stern weder Beschriftung noch Wert noch
  Zustand; die Karte ist als Link ein einziges Accessibility-Element
  (`Views/FavoritesView.swift:24-27`, `Views/ChannelListView.swift:111-114`), der Stern nur als Aktion
  „Favourite" erreichbar, in beiden Zuständen gleich.
  Folge: Mit VoiceOver lässt sich in der Senderliste nicht erkennen, welche Sender Favorit sind, und
  nach dem Auslösen der Aktion nicht, was sie bewirkt hat. Gleiche Lage wie B04 FB-11 (Auswahl der
  Chips nicht wahrnehmbar). (AK-05)

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den
Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Aktualisieren macht aus einem Favoriten mehrere | ⚠ AK-15 **und** FB-01 | nicht sicherheitsrelevant, aber die Absicht ist eindeutig: Kommentar „ein Channel wird wiedererkannt", Website „does not wipe your selection". Eine offene Frage wäre Zurechtrücken durch Unterlassen (wie B01 Nr. 4, B04 Nr. 4) |
| 2 | `try? modelContext.save()` beim Stern | ⚠ AK-27 + FB-02 | beim Ausführen belegt; `docs/datenmodell.md` beschreibt „sofort gespeichert", der Code will speichern und verschweigt das Scheitern |
| 3 | Tab lädt genau die Logos der Favoriten | ⚠ AK-25 + FB-03 | Schwäche nach `sicherheit.md` 1.2 und 2 (Weitergabe eines Profils an Dritte ohne Wahl); widerspricht PRD-Begründung der Stufe B und der FAQ |
| 4 | Stern für VoiceOver ohne Zustand, englisch benannt | ⚠ AK-05 + FB-04 (Zustand) und OF-06 (Sprache) | Zustand: wie B04 FB-11 behandelt; Sprache: Absicht nicht ableitbar, wie B07 OF-03 |
| 5 | Sortierung im Tab nach Zeichencode | ⚠ AK-10 + OF-01 | nicht sicherheitsrelevant, Absicht nicht ableitbar; `sort: \Channel.name` erzeugt ohne Kollation eine binäre Sortierung, ob das bewusst war, ist nicht erkennbar |
| 6 | Gleichnamige Favoriten nicht unterscheidbar | ⚠ AK-09 + OF-02 | nicht sicherheitsrelevant, Absicht nicht ableitbar |
| 7 | Favorit geht bei Wegfall, `tvg-id`-Wechsel oder Umbenennung ohne Hinweis verloren | ⚠ AK-14 + OF-03 | README nennt den Schlüssel „`tvg-id`/Name", der Verlust folgt daraus; ob er stumm bleiben soll, ist offen |
| 8 | Namens-Rückfall, Kleinschreibung, exakte `tvg-id` | reguläre Kriterien AK-11, AK-13 | README („über `tvg-id`/Name"), CLAUDE.md und Code-Kommentar beschreiben es so. Die Website nennt nur die `tvg-id` — unvollständig, nicht falsch; kein Fehlbestand, Hinweis für B10 |
| 9 | Löschen der Playlist nimmt Favoriten ohne Hinweis mit | ⚠ AK-20 + OF-04 | im PRD als Ist beschrieben; ob ein Hinweis nötig ist, ist offen. Fehlende Rückfrage gehört zu B03 (DM-08) |
| 10 | Kein Index auf `isFavorite` | reguläres Kriterium AK-29, **kein** Fehlbestand | gemessen 1–3 ms bei 17.000 bzw. 34.000 Sendern; niemand verspricht hier mehr. DM-05 bleibt als Datenmodell-Befund stehen |
| 11 | Datenbank nicht vom Backup ausgeschlossen | reguläres Kriterium AK-23 | bewusste, im Code begründete Entscheidung der B01-Reparatur (`AppPersistence.swift:16-17`: ohne Zugangsdaten würde ein Ausschluss nur Playlists beim Wiederherstellen nehmen); Favoriten gehören dem Nutzer, das Backup auch |
| 12 | Unter macOS für alle Programme des Benutzers lesbar | reguläres Kriterium AK-24 | Sandbox-Entscheidung ist in CLAUDE.md und `MikaPlusPlayer.entitlements` als gewollt beschrieben; B01 FB-09 betraf Zugangsdaten, die inzwischen im Schlüsselbund liegen |
| 13 | Kein Export, kein „Alle entfernen" | AK-21 + OF-05, Katalog 5.5 „trifft nicht zu" | Auskunftsrecht greift nicht (keine Verarbeitung durch daumedia); Nutzen für den Nutzer ist eine Produktfrage |
| 14 | Namen gelöschter Sender im `-wal` bis zum Checkpoint | reguläres Kriterium AK-28 | nach dem Beenden nachweislich nichts mehr in der Datei; übliches SQLite-Verhalten, kein Versprechen verletzt |
| 15 | Merken der Favoriten lädt alle Sender (1,1 s) | reguläres Kriterium AK-30 mit Verweis auf DM-07 | Befund gehört zum Aktualisieren (B03); hier nur als Messwert |
| 16 | Keine Protokollierung | reguläres Kriterium AK-26 | im PRD als Ist-Stand beschrieben und ausgeführt belegt |
| 17 | „Star a channel anywhere" | OF-07 | „anywhere" ist als „in jeder Senderliste" lesbar und trifft so zu; ob Player/Multiview gemeint sind, ist nicht ableitbar |
| 18 | Speicherfehler-Nachweis per vollem Datenträgerabbild | Methode | schreibgeschützte Dateiflags wirken auf offene Verbindungen nicht (Vorversuch); ein volles Volume ist der realistische und reproduzierbare Fall |
