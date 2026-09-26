# B04 · Senderliste — Spezifikation

Status: `rekonstruiert` · Stand: 2026-09-16 · Rekonstruktion aus dem Code (sdd-erfassen)

> **Gelesener Code-Stand: `main` @ `c01f1cf`, ohne Reparaturen.** Die parallel laufende Reparatur
> von B01 (ab 2026-09-16) ist hier **nicht** berücksichtigt. `ChannelListView.swift`,
> `ChannelRowView.swift` und `PlayerTheme.swift` waren beim Abschluss unverändert gegenüber
> `c01f1cf`. `Models/Channel.swift` hat die B01-Reparatur inzwischen angefasst (Stream-Adressen von
> Xtream-Sendern künftig ohne Zugangsdaten); davon betroffen sind hier nur die Nebenbemerkungen zu
> Zugangsdaten im Speicher in AK-33, FB-09 und Katalog 6.1. Gegenüber dem Release `v1.1` unterscheidet sich B04 nur in der Kopfzeile
> (`v1.1`: „MIKA+ · N SENDER", `main`: „MIKA+PLAYER · N SENDER").
>
> **Rekonstruiert, nicht geplant.** Beschrieben ist, was der Code **tut**, nicht, was er tun sollte.
> Kriterien mit ⚠ beschreiben fragwürdiges Ist-Verhalten. Sie stehen bewusst als Kriterium hier,
> damit `sdd-qa` sie reproduziert. Wo sie als Fehler eingestuft sind, steht ein Verweis auf
> *Fehlbestand*.
>
> **Wie belegt.** Am 2026-09-16 **ausgeführt** in einer Kopie des Projekts (Scratchpad) unter eigener
> Bundle-ID `lu.daumedia.MikaPlusPlayer.b04probe` und mit eigenen Datenbankdateien; die Datenbank
> des Nutzers blieb unberührt. Eine temporäre XCTest-Sonde im Test-Host der Mac-App hat
> (1) Suche, Sortierung und Gruppen mit exakt dem Predicate der App gegen eine SQLite-Datei
> abgefragt, (2) die echte `ChannelListView` in einem Fenster gerendert, über den
> Accessibility-Baum bedient (Chips gedrückt, ins Suchfeld getippt) und als Fensteraufnahme
> festgehalten, (3) Logos von einem lokalen Mock-Host (`127.0.0.1:18790`, `localhost:18791`) laden
> lassen, der jede Anfrage samt Kopfzeilen protokolliert, (4) die SQL-Ausgabe von Core Data
> (`com.apple.CoreData.SQLDebug`) und `EXPLAIN QUERY PLAN` ausgewertet. Nur macOS; iOS ist
> *(gelesen)*. Kriterien, die nur aus dem Code stammen, tragen den Vermerk *(gelesen)*.
> Alles ohne Ton. Die Kopie und der Mock-Host sind wieder gelöscht.
>
> **Evidenz:** `qa-erfassung/sonde-protokoll.txt` (Ausgaben aller Läufe, SQL, Abfragepläne,
> Mock-Protokoll, Cache-Inhalt), `qa-erfassung/sonde.patch` (Sonden-Code und Änderungen der Kopie),
> Fensteraufnahmen `qa-erfassung/mac-01-logos-chips-alle.png` und
> `qa-erfassung/mac-02-chip-sport-ohne-randleerzeichen.png`. Einschränkung: Einige frühe Läufe
> liefen in einem zu kleinen Testfenster (die Hosting-View hatte die Fenstergröße auf 42 × 48 pt
> gesetzt); daraus stammen nur Aussagen über Anfragen und Zustände, keine über Sichtbarkeit oder
> Zeiten. Alle Zeitangaben und Aufnahmen stammen aus Läufen im 1.100 × 850- bzw. 760 × 980-pt-Fenster.
>
> **Messumgebung für alle Zeitangaben:** Apple M3 Max, macOS 27 (Darwin 27.0.0), **Debug-Build**
> (Test-Host), während parallel Builds eines anderen Features liefen. 17.000 erfundene Sender
> (`DE: Sport 12 HD`, 12 Länderpräfixe × 25 Genres = 300 Gruppen). Die Zahlen sind **Ist-Werte zur
> Orientierung, keine Zielwerte**. Ein Release-Build ist nicht gemessen und dürfte schneller sein.

## Zweck

Nach dem Import sieht der Nutzer alle Sender einer Playlist als Liste mit Logo, Name und Gruppe.
Er findet einen Sender über die Suche nach dem Namen oder grenzt die Liste mit Gruppen-Chips ein
und öffnet ihn zum Abspielen. Die Liste ist für Anbieterlisten mit mehr als 17.000 Sendern gedacht
und fragt dafür direkt die Datenbank ab.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| B03 Playlist-Verwaltung | bestand | Einstieg: Tipp auf eine Playlist-Karte öffnet die Senderliste; Aktualisieren ersetzt die Sender, während die Liste offen sein kann |
| B01 Xtream-Login, B02 M3U-Import | rekonstruiert / bestand | liefern Name, Gruppe (`group-title`, Kategorie) und Logo-Adresse (`tvg-logo`, `stream_icon`) jedes Senders |

Auf B04 bauen auf: B05 (Stern in der Senderkarte), B06 (Tipp auf die Karte öffnet den Player),
B08 (⊞-Button in der Senderkarte, nur macOS).

## User Stories

- **US-01** · Als Nutzer mit einer großen Anbieterliste möchte ich nach einem Sendernamen suchen,
  damit ich ihn ohne Scrollen finde.
- **US-02** · Als Nutzer möchte ich die Liste auf eine Gruppe des Anbieters eingrenzen, damit ich
  z. B. nur Sport- oder Nachrichtensender sehe.
- **US-03** · Als Nutzer möchte ich Senderlogos sehen, damit ich Sender schneller erkenne.
- **US-04** · Als Nutzer möchte ich, dass die Liste auch bei 17.000 Sendern bedienbar bleibt.

## Nicht im Scope

- Favoriten-Stern in der Karte und der Favoriten-Tab → **B05**
- ⊞-Button „Zu Multiview hinzufügen" in der Karte → **B08**
- Player, der sich beim Tipp auf eine Karte öffnet → **B06**
- Playlist-Übersicht, Aktualisieren, Löschen → **B03**. Nur das Verhalten der **offenen**
  Senderliste während eines Aktualisierens gehört hierher (AK-17)
- Wie Name, Gruppe und Logo-Adresse beim Import entstehen → **B01**, **B02**
- EPG, Sendernummern, die Reihenfolge des Anbieters, Bearbeiten oder Umsortieren von Sendern: gibt
  es nicht
- Beobachtung am Rand, gehört zu B02/B03: Das Anlegen der Sender über `PlaylistImporter.attach`
  wächst quadratisch (gemessen im Debug-Build: 500 Sender 0,3 s, 1.000 1,1 s, 2.000 4,1 s,
  4.000 16,3 s; hochgerechnet auf 17.000 rund 5 Minuten). Deshalb wurden die Messdaten für B04
  ohne `playlist.channels.append` angelegt; die Datenbankzeilen sind dieselben.

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. Für die Logo-Kriterien genügt ein lokaler
HTTP-Server, der die Anfragen protokolliert, und eine M3U-Datei mit passenden `tvg-logo`-Adressen.

### Aufbau

- **AK-01** · Angenommen, die Playlist-Übersicht zeigt eine Playlist, wenn ihre Karte angetippt
  wird, dann öffnet sich die Senderliste im selben Tab. Oben im Inhalt steht in Akzentfarbe
  „MIKA+PLAYER · N SENDER", darunter groß der Playlistname, darunter die Sender als Karten. Der
  Playlistname ist außerdem Fenstertitel (macOS) bzw. kleiner Titel in der Navigationsleiste
  (iOS). Das Suchfeld „Sender suchen" sitzt in der Fenster-Toolbar (macOS) bzw. in der
  Navigationsleiste (iOS). *(macOS ausgeführt, iOS gelesen)*
- **AK-02** · Angenommen, eine Suche oder ein Gruppen-Chip ist aktiv, dann zeigt die Kopfzeile
  weiter die **Gesamtzahl** der Sender der Playlist, nicht die Zahl der Treffer. *(ausgeführt:
  „8 SENDER" bei gewähltem Chip mit einem Treffer und bei einer Suche ohne Treffer)*
- **AK-03** · Angenommen, die Liste ist offen, dann zeigt jede Karte links ein 48 × 48 pt großes,
  abgerundetes Logofeld, daneben den Sendernamen einzeilig und darunter die Gruppe als graues
  Badge. Rechts sitzen der ⊞-Button (nur macOS, B08) und der Stern (B05). Hat der Sender keine
  Gruppe oder eine leere, fehlt das Badge. Das Badge zeigt den gespeicherten Gruppennamen
  unverändert, also auch mit Leerzeichen am Rand. *(ausgeführt, Fensteraufnahme)*
- **AK-04** · Angenommen, die Liste ist offen, wenn eine Karte außerhalb von Stern und ⊞ angetippt
  wird, dann öffnet sich der Player des Senders (B06) im selben Navigationsstapel. *(gelesen)*
- **AK-05** · Angenommen, die Playlist hat 17.000 Sender, wenn die Liste geöffnet wird, dann
  werden nur die Karten im sichtbaren Bereich und knapp darüber hinaus aufgebaut, und nur für
  diese werden Logos angefragt. Weitere Karten und Logos folgen beim Scrollen. *(ausgeführt)*

### Suche

- **AK-06** · Angenommen, die Liste ist offen, wenn in „Sender suchen" getippt wird, dann wird die
  Liste mit jedem Zeichen neu gefiltert, ohne Bestätigung und ohne Verzögerung. Gesucht wird nur
  im **Sendernamen** und nur in der geöffneten Playlist. Gruppe und tvg-ID werden nicht
  durchsucht. *(ausgeführt: Name, Playlist-Grenze, Neufilterung je Zeichen; Gruppe und tvg-ID
  gelesen → OF-04)*
- **AK-07** · Angenommen, eine Playlist enthält „ARD", „ard alpha", „BR München HD", „MÜNCHEN TV",
  „Straße TV", „Strasse 2", „Écran Plus", „İstanbul TV", „ﬁlm ligature" und „Ελληνικά", dann gilt
  für die Suche:
  (a) Groß- und Kleinschreibung spielt keine Rolle („ard", „ARD", „Ard" finden dasselbe).
  (b) Akzente und Umlaute spielen keine Rolle: „munchen" und „MUNCHEN" finden beide München-Sender,
  „ecran" findet „Écran Plus", „istanbul" findet „İstanbul TV".
  (c) „ß" und „ss" sind gleich: „strasse" und „straße" finden „Straße TV" und „Strasse 2".
  (d) Ligaturen und Vollbreite werden aufgelöst: „fi" findet „ﬁlm ligature", „ＡＲＤ" findet „ARD"
  und umgekehrt.
  (e) Nicht ersetzt werden Umschreibungen und eigene Buchstaben: „muenchen" findet München nicht,
  „oe" nicht „Œuvre", „lodz" nicht „Łódź TV", „o" nicht „Ølstrup".
  (f) Griechisch und Kyrillisch werden ohne Groß- und Kleinschreibung gefunden („ΕΛΛ" → „Ελληνικά").
  *(ausgeführt, 41 Namen, 46 Suchbegriffe)*
- **AK-08** · Angenommen, die Liste ist offen, dann wird der Suchtext wörtlich genommen:
  (a) Leerzeichen am Rand werden **nicht** entfernt: „ ard" findet nichts, „ard " nur Namen, in
  denen auf „ard" ein Leerzeichen folgt, ein einzelnes Leerzeichen findet jeden Namen mit
  Leerzeichen.
  (b) `%`, `_`, `*`, `?`, `\`, `'` und `"` sind keine Platzhalter und finden nur Namen, die das
  Zeichen enthalten.
  (c) Doppelte Leerzeichen zählen: „sport 2" findet „Sport  2" (zwei Leerzeichen) nicht.
  (d) Eine Eingabe von 10.000 Zeichen liefert eine leere Trefferliste ohne Fehler.
  *(ausgeführt)*
- **AK-09** ⚠ · Angenommen, die Liste ist offen, dann sind die Sender immer nach Namen sortiert, mit
  und ohne Suche oder Gruppe. Die Reihenfolge des Anbieters spielt keine Rolle. Die Sortierung
  folgt der Systemsprache: Groß- und Kleinschreibung gleich, Umlaute und Akzente beim
  Grundbuchstaben („Ärger TV" bei A), Namen mit Leerzeichen, `#` oder Emoji am Anfang zuerst,
  Ziffern vor Buchstaben, Griechisch, Kyrillisch und Arabisch am Ende. Zahlen werden **nicht** als
  Zahlen sortiert: „100% Hits" steht vor „1LIVE", „Sport 10" vor „Sport 2".
  *(ausgeführt; Zahlenreihenfolge → OF-01)*

### Gruppen-Filter

- **AK-10** · Angenommen, die Sender einer Playlist tragen mindestens **zwei** verschiedene
  Gruppennamen, wenn die Liste geöffnet wird, dann erscheint oben eine waagerecht scrollbare
  Chip-Leiste auf Leistenmaterial: zuerst „Alle", dann ein Chip je Gruppe. Bei nur einer Gruppe
  erscheint keine Leiste, auch wenn es daneben Sender ohne Gruppe gibt. Eine Playlist ohne Gruppen
  hat keine Leiste. *(ausgeführt, Fensteraufnahme)*
- **AK-11** · Angenommen, die Chip-Leiste ist sichtbar, dann gilt für die Chips:
  (a) Jeder Gruppenname erscheint einmal; Leerzeichen und Tabulatoren am Rand sind entfernt, ein
  Zeilenumbruch am Ende bleibt (eigener Chip „News⏎" neben „News").
  (b) Leere Gruppen, Gruppen nur aus Leerzeichen und Sender ohne Gruppe erzeugen keinen Chip.
  (c) Groß- und Kleinschreibung trennt: „Sport", „sport" und „SPORT" sind drei Chips.
  *(ausgeführt: 18 Gruppenwerte → 13 Chips)*
- **AK-12** ⚠ · Angenommen, die Chip-Leiste ist sichtbar, dann stehen die Gruppen-Chips nach
  Zeichencode sortiert, nicht nach Sprache: Ziffern als Text („10 Musik" vor „2 Musik"), alle
  großgeschriebenen vor allen kleingeschriebenen Namen („Zebra" vor „kids"), Umlaute ganz am Ende
  („Ärger", „Österreich", „Ünter" nach „sport"). Das weicht von der Sortierung der Sender ab
  (AK-09). *(ausgeführt → OF-02)*
- **AK-13** · Angenommen, keine Gruppe ist gewählt, dann ist „Alle" in Akzentfarbe gefüllt mit
  weißer Schrift, alle anderen Chips grau. Wird ein Gruppen-Chip angetippt, ist er in Akzentfarbe
  gefüllt, „Alle" wird grau, und die Liste zeigt nur Sender dieser Gruppe. Erneutes Tippen auf
  denselben Chip oder Tippen auf „Alle" hebt die Auswahl auf. Es ist immer höchstens ein Chip
  gewählt. Suche und Gruppe wirken zusammen. *(ausgeführt: Chips per Accessibility gedrückt,
  Fensteraufnahme; Aufheben und Kombination über die Abfrage belegt; Kontrast → FB-11)*
- **AK-14** ⚠ · Angenommen, Sender tragen dieselbe Gruppe mit und ohne Leerzeichen am Rand
  („Sport", „ Sport", „Sport "), wenn der Chip „Sport" angetippt wird, dann erscheinen **nur** die
  Sender mit exakt „Sport". Die übrigen sind unter keinem Chip zu finden, nur über „Alle" oder die
  Suche. *(ausgeführt: 2 von 6 Sendern in der Abfrage; in der Fensteraufnahme fehlt „S2" mit
  „ Sport" → FB-01)*
- **AK-15** ⚠ · Angenommen, eine Gruppe kommt nur mit Leerzeichen oder Tabulator am Rand vor
  (z. B. „⇥Tab"), wenn ihr Chip „Tab" angetippt wird, dann zeigt die Liste **keinen** Sender, und
  es erscheint „Keine Sender – Diese Playlist enthält keine Sender.". *(Abfrage ausgeführt: 0
  Treffer; Anzeige gelesen, sie folgt aus AK-19 → FB-01, FB-03)*
- **AK-16** · Angenommen, eine Gruppe oder ein Suchtext ist gewählt, wenn die Liste verlassen und
  wieder geöffnet wird, dann ist beides zurückgesetzt, und die Chips werden neu aus der Datenbank
  berechnet. *(Neuberechnung ausgeführt; Zurücksetzen gelesen)*
- **AK-17** ⚠ · Angenommen, die Liste ist offen und ein Chip gewählt, wenn die Playlist in einem
  anderen Fenster aktualisiert wird und dabei Gruppen wegfallen oder hinzukommen, dann zeigen
  Liste und Kopfzeile sofort den neuen Bestand. Die Chip-Leiste bleibt aber **alt**: Weggefallene
  Gruppen bleiben als Chip stehen, neue fehlen. War eine weggefallene Gruppe gewählt, erscheint
  „Keine Sender – Diese Playlist enthält keine Sender.", obwohl die Playlist Sender hat. Erst
  Verlassen und erneutes Öffnen zeigt die neuen Chips. Die App stürzt dabei nicht ab.
  *(ausgeführt: Kino → Doku ersetzt, 5 → 3 Sender; Chips blieben „Alle, Kino, News, Sport" → FB-02)*

### Leerzustände

- **AK-18** · Angenommen, eine Playlist hat keine Sender, wenn ihre Liste geöffnet wird, dann steht
  dort ein durchgestrichenes TV-Symbol, „Keine Sender" und „Diese Playlist enthält keine Sender.",
  ohne Chip-Leiste. *(ausgeführt; über den Import entsteht eine solche Playlist nicht, B01/B02
  lehnen leere Listen ab)*
- **AK-19** ⚠ · Angenommen, ein Gruppen-Chip ist gewählt, das Suchfeld leer und kein Sender passt,
  dann erscheint derselbe Leerzustand wie bei einer leeren Playlist: „Diese Playlist enthält keine
  Sender.". *(ausgeführt über AK-17; Bedingung gelesen → FB-03)*
- **AK-20** ⚠ · Angenommen, ein Suchtext ist eingegeben und kein Sender passt, dann erscheint die
  Systemansicht mit Lupe und **englischem** Text: „No Results for “<Suchtext>”" und „Check the
  spelling or try a new search.". Die übrige Oberfläche ist deutsch. *(ausgeführt → OF-03)*

### Logos

- **AK-21** · Angenommen, ein Sender hat eine Logo-Adresse, wenn seine Karte in den sichtbaren
  Bereich kommt, dann lädt die App das Bild von genau dieser Adresse. Bis zur Antwort dreht im
  Logofeld ein Ladeindikator. Kommt ein Bild, wird es eingepasst angezeigt. Antwortet der Host mit
  einem HTTP-Fehler (z. B. 404) oder mit etwas, das kein Bild ist (HTML, JSON, HTML mit
  `Content-Type: image/png`), erscheint das graue TV-Symbol als Platzhalter.
  *(ausgeführt: PNG, 404 und HTML in der Fensteraufnahme; JSON und HTML-als-PNG über die Zahl der
  verbliebenen Ladeindikatoren)*
- **AK-22** ⚠ · Angenommen, ein Sender hat **keine** Logo-Adresse, oder der Logo-Host ist nicht
  erreichbar (Port geschlossen, Name nicht auflösbar, `https://` ohne Gegenstelle), oder er leitet
  endlos weiter, dann dreht der Ladeindikator **dauerhaft**. Der Platzhalter erscheint nie.
  *(ausgeführt: Fensteraufnahme nach 9 s, Einzelzeilen nach 6 s → FB-04)*
- **AK-23** · Angenommen, ein Logo-Host antwortet langsam, dann dreht der Ladeindikator, bis die
  Antwort da ist. Kommen 60 s lang keine Daten, bricht die Anfrage ab, und der Ladeindikator
  bleibt stehen (wie AK-22). Wird die Karte aus dem sichtbaren Bereich gescrollt oder die Liste
  verlassen, schließt die App die laufende Logo-Anfrage sofort. *(ausgeführt: bei 2.000 Sendern
  mit 8 s verzögerten Logos wurden beim Scrollen zur Mitte die 6 Anfragen der ersten Karten, beim
  Scrollen ans Ende die 7 Anfragen der Mitte und beim Verlassen die letzten 2 innerhalb von
  0,1 s abgebrochen; 60 s-Abbruch im Protokoll des Mock-Hosts)*
- **AK-24** ⚠ · Angenommen, eine Logo-Adresse liefert ein Bild von 12.000 × 12.000 px (446 KB) und
  eine andere eine Datei von 27 MB, wenn beide Karten sichtbar werden, dann lädt die App beide
  vollständig. Der Speicherbedarf der App steigt von 37 MB auf **640 MB** und bleibt dort, solange
  die Liste offen ist; nach dem Verlassen fällt er auf 62 MB. Es gibt keine Grenze für Dateigröße
  oder Bildabmessung. *(ausgeführt → FB-05)*
- **AK-25** ⚠ · Angenommen, eine Logo-Adresse beginnt mit `http://`, dann lädt die App sie
  unverschlüsselt. Antwortet der Host mit einer Weiterleitung, folgt die App ihr ohne Rückfrage,
  auch auf einen anderen Host und Port. Eine Weiterleitungsschleife verfolgt sie mit 21 Anfragen
  innerhalb von 40 ms, dann gibt sie auf (AK-22). *(ausgeführt → FB-06)*

### Datenschutz und Missbrauchsschutz

Fragenkatalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog). Jede Frage hat ein
Kriterium, ein „trifft nicht zu, weil …" oder einen Eintrag im *Fehlbestand*.

- **AK-26** ⚠ · Angenommen, die Liste zeigt Karten mit Logos, dann erhält **jeder** Host, der in
  einer Logo-Adresse steht, ohne Rückfrage und ohne Abschaltmöglichkeit: die IP-Adresse des
  Nutzers, den User-Agent `Mika+Player/<Build> CFNetwork/<Version> Darwin/<Version>` (App-Name,
  Build-Nummer, Betriebssystemversion), `Accept-Language` mit der Systemsprache (z. B.
  `de-DE,de;q=0.9`) sowie `Accept: */*` und `Accept-Encoding: gzip, deflate`. Cookies und Referer
  werden nicht gesendet. Das gilt auch für das Ziel einer Weiterleitung. *(ausgeführt → FB-06)*
- **AK-27** ⚠ · Angenommen, der Nutzer sucht oder wählt eine Gruppe, dann fragt die App Logos nur
  für die dann sichtbaren Treffer an. Ein Logo-Host, der mehrere Sender bedient, erfährt so, welche
  Sender der Nutzer sich gerade ansieht bzw. wonach er gefiltert hat. *(abgeleitet aus AK-05 und
  AK-21, beide ausgeführt; nicht gesondert mit Suche ausgeführt → FB-06)*
- **AK-28** ⚠ · Angenommen, Logos wurden angezeigt, dann liegen Logo-Adresse, Antwortkopfzeilen und
  Antwortinhalt im Plattencache der App (macOS: `~/Library/Caches/<Bundle-ID>/Cache.db`, iOS:
  `Library/Caches` im App-Container), und zwar **auch** Antworten mit `Cache-Control: no-store`,
  Antworten ohne Cache-Kopfzeilen, 404-Seiten, HTML und JSON. Logos mit `max-age` fragt die App beim
  nächsten Öffnen der Liste nicht erneut an; alle anderen fragt sie erneut an und speichert sie
  trotzdem. Die Grenze ist der Standard von `URLCache` (512 KB Arbeitsspeicher, 20 MB Platte). Das
  Löschen der Playlist entfernt diese Einträge nicht. *(ausgeführt: neun Einträge in `Cache.db`
  nach einem Durchlauf, Kopfzeilen des `no-store`-Eintrags gelesen, erneute Anfragen im Protokoll;
  Nicht-Entfernen gelesen → FB-07)*
- **AK-29** · Angenommen, ein Suchtext wird eingegeben, dann verlässt er das Gerät nicht, wird
  nicht gespeichert und erscheint nicht im Systemprotokoll. *(ausgeführt: `log stream --level
  debug` auf einen eindeutigen Suchtext, kein Treffer; Speichern und Senden gelesen: kein
  Netzwerkaufruf außer den Logos, kein `UserDefaults`, kein `print`/`Logger`)*
- **AK-30** · Angenommen, die Liste ist offen, dann zeigt sie weder Stream-Adressen noch
  Zugangsdaten. *(ausgeführt, Fensteraufnahme; gelesen)*

### Leistung

Gemessene **Ist-Werte, keine Zielwerte.** Messumgebung siehe Kopf (Debug-Build, M3 Max, Last
durch parallele Builds). Die QA misst am selben Aufbau nach; Abweichungen um den Faktor 2 sind
bei dieser Umgebung nicht ungewöhnlich.

- **AK-31** · Angenommen, eine Suche, eine Gruppe oder beides ist aktiv, dann laufen Filter und
  Sortierung in der Datenbank, nicht im Speicher: Die App schickt eine SQL-Abfrage
  `… WHERE ZPLAYLISTID = ? [AND NSCoreDataStringSearch(ZNAME, ?, 417, 1)] [AND ZGROUP = ?]
  ORDER BY ZNAME COLLATE NSCollateLocaleSensitive`. *(ausgeführt, SQL-Ausgabe von Core Data)*
- **AK-32** ⚠ · Angenommen, die Datenbank enthält 17.000 oder 34.000 Sender, dann nutzt diese
  Abfrage **keinen Index**: `EXPLAIN QUERY PLAN` meldet `SCAN` über alle Sender aller Playlists und
  `USE TEMP B-TREE FOR ORDER BY`. Der einzige vorhandene Index (`ZCHANNEL_ZPLAYLIST_INDEX` auf der
  Beziehung `ZPLAYLIST`) bleibt ungenutzt, weil über die Kopie `ZPLAYLISTID` gefiltert wird; mit
  `ZPLAYLIST = ?` meldet SQLite `SEARCH … USING INDEX`. Messbar ist der Unterschied bei 17.000
  gegenüber 34.000 Sendern kaum (+0,5 ms). *(ausgeführt → FB-08)*
- **AK-33** ⚠ · Angenommen, die Liste einer Playlist mit 17.000 Sendern wird geöffnet, dann lädt die
  App zur Berechnung der Chips **alle 17.000 Sender mit allen Spalten** (einschließlich
  Stream-Adresse und Logo-Adresse) und bildet die Gruppenliste im Speicher. Das dauert rund
  205 ms auf dem Main-Thread und geschieht bei jedem Öffnen der Liste. *(ausgeführt: SQL ohne
  Spaltenbeschränkung, Messung → FB-09)*
- **AK-34** ⚠ · Angenommen, die Playlist hat 17.000 Sender, dann lädt die Liste bei jeder Änderung
  von Suchtext oder Gruppe **alle** Treffer als Objekte (ohne Filter: 17.000) auf dem Main-Thread,
  und die Oberfläche steht dabei. Es gibt keine Verzögerung zwischen Tastendrücken und keine
  Obergrenze der Treffer. Gemessen:

  | Vorgang (17.000 Sender) | Main-Thread blockiert, längster Einzelblock |
  |---|---|
  | Liste öffnen (zwei Durchläufe) | 626 ms / 817 ms |
  | Liste verlassen | 100–111 ms |
  | erstes Zeichen „F" tippen | 143 ms |
  | aus leerem Suchfeld „a" tippen (7.359 Treffer) | 153 ms |
  | weitere Zeichen bis „Fußball 12" (je 0,8 s Abstand) | 43–100 ms je Zeichen |
  | 8 Zeichen im Abstand von 100 ms („Doku 5 H") | 341 ms, Eingabe dauerte 1,95 s statt 0,8 s |
  | Suchfeld leeren (zurück auf 17.000) | 278–378 ms |
  | Chip „DE \| Sport" wählen (58 Treffer) | 129 ms |
  | Chip wieder abwählen (zurück auf 17.000) | 386 ms |
  | Speicherbedarf der App mit offener Liste | 119–152 MB |

  *(ausgeführt im 1.100 × 850-pt-Fenster; das Tippen über einen Nachbau, der wie `ChannelListView`
  bei jeder Änderung eine neue `ChannelResultsList` mit neuer Abfrage erzeugt → FB-10)*

  Reine Abfragedauer mit Anlegen der Objekte, ohne Oberfläche (je 1 kalter und 4 warme Läufe):

  | Abfrage | Treffer | 17.000 Sender gesamt | 34.000 Sender gesamt (2 Playlists) |
  |---|---|---|---|
  | ohne Suche, ohne Gruppe | 17.000 | 268 ms kalt, 252–258 ms warm | 259 ms, 254–256 ms |
  | Suche „a" | 7.359 | 110 ms | 111–113 ms |
  | Suche „Sport" | 686 | 14–15 ms | 15–16 ms |
  | Suche „fußball" | 679 | 15 ms | 15–16 ms |
  | Suche „Anime 97 4K" | 2 | 5 ms | 6 ms |
  | Suche ohne Treffer | 0 | 5 ms | 6 ms |
  | Suche mit 10.000 Zeichen | 0 | 10 ms | 11 ms |
  | Gruppe „DE \| Sport" | 58 | 2 ms | 2 ms |
  | Gruppe + Suche „HD" | 34 | 6 ms | 6 ms |
  | Chips berechnen (`loadGroups`) | 300 Gruppen | 214 ms kalt, 201–205 ms warm | 203–208 ms |

  Davon reine SQL-Ausführung laut Core Data bei 17.000 Zeilen: 0,12–0,21 s; bei 7.359 Zeilen
  0,08–0,09 s. Der Rest ist das Anlegen der Objekte.

#### Katalog, Frage für Frage

| # | Katalogfrage | Antwort für B04 |
|---|---|---|
| 1.1 | Welche personenbezogenen Daten? | Gegenüber Logo-Hosts: IP-Adresse, Betriebssystemversion, App-Build, Systemsprache (AK-26) und welche Sender der Nutzer gerade sieht (AK-27). Lokal: der Suchtext (flüchtig, AK-29). Namen, Gruppen und Logo-Adressen stammen vom Anbieter, nicht vom Nutzer |
| 1.2 | Besondere Kategorien? | Nicht gespeichert. Aber: Aus den angefragten Logos kann ein Logo-Host auf Interessen schließen, z. B. religiöse oder politische Sender nach einer Suche (AK-27 → FB-06). Die Favoriten selbst gehören zu B05 |
| 1.3 | Wo gespeichert, wie lange? | B04 schreibt nichts in die Datenbank. Logos und Logo-Antworten liegen im Plattencache, bis das System ihn räumt oder die 20-MB-Grenze greift (AK-28 → FB-07). Suchtext, Gruppenauswahl und Chip-Liste nur im Arbeitsspeicher, bis die Liste verlassen wird (AK-16) |
| 1.4 | Landen sie in Logs? | Suchtext nein (AK-29). Logo-Adressen stehen im Plattencache (AK-28). Die SQL-Ausgabe mit Suchtext entsteht nur mit dem Entwickler-Schalter `com.apple.CoreData.SQLDebug`, nicht im Normalbetrieb |
| 2.1 | Welche externen Dienste? | Jeder Host, der in einer Logo-Adresse steht, und jedes Ziel einer Weiterleitung (AK-21, AK-25, AK-26). Kein KI-Dienst, keine Analyse, kein Fehler-Tracking |
| 2.2 | Was wird übertragen, was vorher entfernt? | IP, Kopfzeilen, Abrufzeitpunkt und damit die sichtbaren Sender; entfernt wird nichts, abschalten lässt es sich nicht → FB-06 |
| 2.3 | Standort des Dienstes, AV-Vertrag? | Trifft nicht zu, weil die Logo-Hosts weder vom Nutzer noch von daumedia gewählt werden, sondern in der Playlist des Anbieters stehen; daumedia verarbeitet dabei nichts. Die Website nennt Logo-Server als Empfänger (`web/app/privacy/page.tsx:52-54`) |
| 2.4 | Training mit dem Payload? | Trifft nicht zu, weil kein KI-Dienst beteiligt ist |
| 3.1 | Wer darf sehen, ändern, löschen? | Der lokale Nutzer sieht alle Sender aller Playlists; B04 ändert nichts (Stern: B05). Unter macOS kann jeder Prozess des Benutzers `default.store` und `Cache.db` lesen, weil die Sandbox aus ist (siehe B01 FB-09) |
| 3.2 | Erzwungen in DB oder Anwendung? | Nirgends; Einzelnutzer-App ohne Konten. Die Abfrage grenzt nur fachlich auf die geöffnete Playlist ein (AK-06) |
| 3.3 | Fremde ID? | Trifft nicht zu, weil es keinen Server und keine per ID abrufbaren Ressourcen gibt |
| 3.4 | Rollen? | Trifft nicht zu, weil die App keine Konten und keine Rollen hat |
| 4.1 | Rate Limit Anmeldung | Trifft nicht zu, weil B04 keine Anmeldung hat |
| 4.2 | Rate Limit für Kostenpflichtiges | Trifft nicht zu, weil B04 keinen kostenpflichtigen Dienst ruft. Logo-Anfragen sind nur durch die Sichtbarkeit begrenzt (AK-05) und werden beim Wegscrollen abgebrochen (AK-23) |
| 4.3 | Kosten je Aufruf | Trifft nicht zu, siehe 4.2. Kosten entstehen als Rechenzeit: jede Eingabe blockiert die Oberfläche (AK-34 → FB-10) |
| 4.4 | Unvertraute Eingaben: Größe, Typ, Inhalt | Logos: keine Grenze für Größe, Abmessung oder Dauer (AK-24 → FB-05); der Inhalt wird vom System-Decoder geprüft, Nicht-Bilder werden zum Platzhalter (AK-21). Suchtext: keine Längengrenze, 10.000 Zeichen unkritisch (AK-08). Gruppennamen: ungefiltert übernommen (AK-11, AK-14) |
| 4.5 | Wo greift das Limit? | Nur `URLCache`-Standard (20 MB Platte) und der 60-s-Leerlauf-Timeout von `URLSession` (AK-23, AK-28) |
| 5.1 | Konto selbst löschen? | Trifft nicht zu, weil die App kein Konto hat |
| 5.2 | Was wird dabei gelöscht? | B04 speichert selbst nichts. Beim Löschen einer Playlist (B03) bleibt der Logo-Cache stehen → FB-07 |
| 5.3 | Was bleibt, und warum? | Logo-Cache-Einträge samt Adressen, ohne Begründung → FB-07 |
| 5.4 | E-Mail-Adresse wieder frei? | Trifft nicht zu, weil die App keine Registrierung hat |
| 5.5 | Datenexport? | Trifft nicht zu, weil daumedia keine Daten erhält |
| 6.1 | Welche Schlüssel braucht das Feature? | Keine. Die Chip-Berechnung lädt allerdings die Stream-Adressen mit Xtream-Zugangsdaten mit in den Speicher (AK-33); ausgegeben werden sie nicht (AK-30) |
| 6.2 | Welche dürfen zum Client? | Trifft nicht zu, weil es keinen Server gibt |
| 6.3 | Steht Echtes im Repository? | Trifft für B04 nicht zu, weil die Dateien keine Adressen, Schlüssel oder Zugangsdaten enthalten; die Git-Historie ist in B01 AK-30 geprüft |
| 6.4 | Vorlagen `.env.example` / `Secrets.example.xcconfig` | Trifft nicht zu, weil B04 keine Build-Geheimnisse braucht |

## Edge Cases

Ist-Verhalten. „(ausgeführt)" heißt mit der Sonde belegt, „(gelesen)" heißt aus dem Code abgeleitet.

- **EC-01** · Gruppe nur aus Leerzeichen → kein Chip (AK-11), aber die Karte zeigt ein Badge mit
  unsichtbarem Text, weil nur auf leere Zeichenkette geprüft wird. *(gelesen)*
- **EC-02** · Gruppe mit Zeilenumbruch am Ende („News⏎") → eigener Chip neben „News"; dieser Chip
  findet genau diese Sender. Chip und Badge sind einzeilig begrenzt. *(Chip und Treffer ausgeführt,
  Darstellung gelesen)*
- **EC-03** · Mehrere Sender mit gleichem Namen → alle erscheinen; ihre Reihenfolge untereinander
  ist nicht festgelegt, weil nur nach Namen sortiert wird. *(SQL ausgeführt)*
- **EC-04** · Gewählter Chip und Suche ohne Treffer → die englische Suchansicht (AK-20), nicht
  „Keine Sender", weil das Suchfeld nicht leer ist. *(gelesen)*
- **EC-05** · Logo-Adresse mit `file://` (z. B. ein Icon unter `/System/Library`) → die App lädt die
  lokale Datei ohne Netzwerk; der Ladeindikator verschwindet. Ob das Bild angezeigt wird, ist nicht
  angesehen. *(ausgeführt → OF-06)*
- **EC-06** · Logo-Host schickt Daten tröpfchenweise (1 Byte je 10 s) → die 60-s-Leerlaufgrenze greift
  nicht; die Anfrage bliebe offen, solange die Karte sichtbar ist. Im Test wurde sie beim Scrollen
  abgebrochen, das Dauerverhalten ist nicht abgewartet. *(teilweise ausgeführt, gelesen → FB-05)*
- **EC-07** · Karte wird weggescrollt, während das Logo lädt, und wieder hergescrollt → ob die App
  neu anfragt oder der Ladeindikator stehen bleibt, ist nicht eindeutig belegt: In einem Lauf kam
  keine neue Anfrage, in einem anderen fragte die App zwei Karten erneut an. *(ausgeführt, nicht
  eindeutig — die QA prüft das per Fensteraufnahme)*
- **EC-08** · Zwei Hauptfenster (macOS) zeigen dieselbe Playlist → Suche und Chip-Auswahl sind je
  Fenster unabhängig; ein Aktualisieren im einen Fenster lässt die Chips im anderen veralten
  (AK-17). *(Aktualisieren ausgeführt, Unabhängigkeit gelesen)*
- **EC-09** · Die Playlist wird in einem anderen Fenster **gelöscht**, während ihre Liste offen ist →
  nicht ausgeführt. Die Liste hält das `Playlist`-Objekt (Kopfzeile, Titel); Prüfpunkt für B03 und
  die QA (vgl. DM-10). *(gelesen)*
- **EC-10** · Sehr langer Sendername → einzeilig, abgeschnitten. *(gelesen)*
- **EC-11** · iOS → Suchfeld in der Navigationsleiste, Chip-Leiste unter der Navigationsleiste,
  sonst wie macOS; ⊞-Button fehlt. Nicht ausgeführt, weil es keine iOS-Tests gibt. *(gelesen)*
- **EC-12** · Schnelles Tippen bei 17.000 Sendern → Eingaben stauen sich; 8 Zeichen im Abstand von
  100 ms brauchten 1,95 s, der längste Block dauerte 341 ms (AK-34). *(ausgeführt)*

## Offene Fragen

Alle vom 2026-09-16. Entscheidung durch den Nutzer (Michael Ferreira), vor der Reparaturrunde
nach der QA von B04.

- **OF-01** · Sollen Zahlen in Sendernamen als Zahlen sortiert werden („Sport 2" vor „Sport 10")
  (AK-09)? Heute gilt die Textreihenfolge.
- **OF-02** · Sollen die Gruppen-Chips wie die Sender sprachgerecht sortiert und Groß-/Klein-Varianten
  („Sport", „sport") zusammengefasst werden (AK-11, AK-12)?
- **OF-03** · Soll der Leerzustand der Suche englisch bleiben (AK-20)? Die übrige Oberfläche ist
  deutsch; B01 OF-06 fragt dasselbe für Fehlermeldungen.
- **OF-04** · Soll die Suche auch Gruppe oder tvg-ID durchsuchen (AK-06)?
- **OF-05** · Soll die Kopfzeile bei aktiver Suche oder Gruppe die Trefferzahl zeigen statt der
  Gesamtzahl (AK-02)?
- **OF-06** · Sollen Logo-Adressen mit `file://` (und anderen Nicht-HTTP-Schemata) geladen werden
  (EC-05)? Eine fremde Playlist kann so lokale Bilddateien anzeigen lassen; ein Abfluss nach
  außen entsteht dabei nicht.

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus dem Code belegt. Kein Kriterium: `sdd-qa` prüft
nichts davon als bestanden, sondern nimmt es als Suchliste. Zeilenangaben beziehen sich auf
`Sources/` @ `c01f1cf`.

- **FB-01 · Gruppen-Chip gekürzt, Filter vergleicht ungekürzt.**
  Fundstelle: `Views/ChannelListView.swift:77` entfernt Leerzeichen und Tabulatoren beim Bilden der
  Chips, `:95` vergleicht `ch.group == g` mit dem gespeicherten, ungekürzten Wert.
  Folge: Sender mit „ Sport" oder „Sport " fehlen unter dem Chip „Sport". Eine Gruppe, die nur mit
  Randzeichen vorkommt, ergibt einen Chip ohne Treffer, der „Diese Playlist enthält keine Sender."
  behauptet. Solche Gruppennamen liefern Anbieter häufig. (AK-14, AK-15)
- **FB-02 · Chip-Leiste wird nach einem Aktualisieren nicht neu berechnet.**
  Fundstelle: `Views/ChannelListView.swift:43`, `.task(id: playlist.id)`. Die ID der Playlist bleibt
  beim Aktualisieren gleich (B03 ersetzt nur die Sender), also läuft `loadGroups()` nicht erneut.
  Die Liste selbst aktualisiert sich über `@Query`.
  Folge: Weggefallene Gruppen bleiben als Chip, neue fehlen, und ein gewählter weggefallener Chip
  meldet eine leere Playlist. Erreichbar mit zwei Fenstern (macOS) oder geteiltem Bildschirm (iPad).
  (AK-17)
- **FB-03 · Ein Leerzustand für zwei verschiedene Lagen.**
  Fundstelle: `Views/ChannelListView.swift:101-104` zeigt „Keine Sender – Diese Playlist enthält keine
  Sender.", sobald die Trefferliste leer und das Suchfeld leer ist — auch wenn nur der gewählte Chip
  nichts findet.
  Folge: Die App sagt etwas Falsches über die Playlist; der Nutzer hält sie für leer. (AK-15, AK-17,
  AK-19)
- **FB-04 · Ladeindikator dreht dauerhaft statt Platzhalter.**
  Fundstelle: `Views/ChannelRowView.swift:36-46`. Der Code sieht für `.failure` den Platzhalter vor,
  für `.empty` den Ladeindikator. Ohne Logo-Adresse bleibt `AsyncImage` in `.empty`; bei
  Verbindungsfehlern, Timeout und Weiterleitungsschleife blieb es im Test ebenfalls beim
  Ladeindikator.
  Folge: Bei Anbietern mit vielen Sendern ohne Logo oder mit totem Logo-Server dreht in jeder Karte
  ein Ladeindikator, ohne je zu enden. Die Absicht (Platzhalter bei Fehler) ist im Code erkennbar,
  deshalb als Fehler eingestuft. (AK-22)
- **FB-05 · Keine Grenzen für Logo-Antworten.**
  Fundstelle: `Views/ChannelRowView.swift:36`, `AsyncImage(url:)` ohne eigene Session, ohne
  Größen-, Abmessungs- oder Gesamtzeitgrenze.
  Folge: Eine Playlist aus fremder Quelle kann mit einem einzigen Logo mehrere hundert MB
  Arbeitsspeicher belegen (gemessen: 640 MB für ein 12.000 × 12.000-px-Bild und eine 27-MB-Datei),
  auf iOS droht die Beendigung der App durch das System. Ein tröpfelnder Host hält Verbindungen
  unbegrenzt offen (EC-06). `sicherheit.md` 4.4: fehlende Größenlimits bei unvertrauten Eingaben.
  (AK-24)
- **FB-06 · Logos laden bei beliebigen Dritten, ohne Wahl, auch unverschlüsselt und über
  Weiterleitungen.**
  Fundstelle: `Views/ChannelRowView.swift:36` lädt jede Logo-Adresse, sobald die Karte sichtbar
  wird; `Resources/Info.plist:39-40` (`NSAllowsArbitraryLoads`) erlaubt HTTP; es gibt keine
  Einstellung, Logos abzuschalten oder nur über den Anbieter-Host zu laden.
  Folge: Jeder Host in einer Playlist erfährt IP, Systemversion, App-Build, Sprache und welche Sender
  der Nutzer sich gerade ansieht oder wonach er filtert. Über HTTP sieht das auch jeder im Netz
  mit. Die Website nennt Logo-Server als Empfänger (`web/app/privacy/page.tsx:52-54`), schreibt aber
  zwei Zeilen darüber, jede Logo-Anfrage gehe an „the host you entered" (`:47-49`) — das stimmt
  nicht. (AK-25, AK-26, AK-27)
- **FB-07 · Logo-Antworten im Plattencache, auch wenn sie nicht gespeichert werden sollen, und
  über das Löschen hinaus.**
  Fundstelle: `AsyncImage` nutzt den gemeinsamen `URLCache` der App; kein Code der App leert ihn
  oder schließt Logos aus.
  Folge: `Cache.db` enthält die Logo-Adressen der angesehenen Sender (Hinweis auf Anbieter und
  Interessen), auch Antworten mit `Cache-Control: no-store`, und behält sie nach dem Löschen der
  Playlist. Unter macOS ohne Sandbox für jeden Prozess des Benutzers lesbar. (AK-28)
- **FB-08 · Kein Index; der Filter umgeht den einzigen vorhandenen.**
  Fundstelle: `Models/Channel.swift:19-22` begründet `playlistID` mit „schnelle, robuste
  `#Predicate`-Filter"; `Views/ChannelListView.swift:73, 93` filtern darüber. SQLite hat auf
  `ZPLAYLISTID`, `ZNAME` und `ZGROUP` keinen Index, nur auf der Beziehung `ZPLAYLIST`. `#Index`
  gibt es erst ab iOS 18 / macOS 15. Entspricht DM-05.
  Folge: Jede Abfrage liest alle Sender **aller** Playlists und sortiert in einem temporären
  B-Baum. Bei 34.000 Sendern gemessen noch unauffällig (+0,5 ms); die Kosten wachsen mit jeder
  weiteren großen Playlist. Die Begründung im Kommentar trifft in dieser Form nicht zu. (AK-32)
- **FB-09 · Chip-Berechnung lädt alle Sender vollständig in den Speicher.**
  Fundstelle: `Views/ChannelListView.swift:70-80`. `propertiesToFetch = [\.group]` wirkt nicht; das
  SQL liest alle Spalten. Deduplizieren und Sortieren im Speicher, auf dem Main-Thread. Entspricht
  DM-07.
  Folge: rund 205 ms Stillstand bei jedem Öffnen einer Liste mit 17.000 Sendern, dazu alle
  Stream-Adressen (bei Xtream mit Zugangsdaten) im Arbeitsspeicher. Widerspricht der FAQ „searching
  and filtering happen in the database rather than in memory" (`web/content/faq.ts:35`). (AK-33)
- **FB-10 · Die Werbeaussage „responds immediately" ist bei 17.000 Sendern nicht eingelöst.**
  Fundstelle: `Views/ChannelListView.swift:23-27, 42, 88-97` — jede Änderung von Suchtext oder Chip
  baut sofort eine neue `@Query` ohne Entprellung, ohne Obergrenze und ohne Hintergrundausführung.
  Die Website verspricht „Type a name, tap a group chip, and the list responds immediately"
  (`web/content/features.ts:12-13`) und „the list narrows as fast as you can type"
  (`web/app/page.tsx:108-110`); README (`:260-261`) und Code-Kommentar (`ChannelListView.swift:5-6`)
  sagen „flüssig".
  Folge (Debug-Build, siehe AK-34): Öffnen blockiert 0,6–0,8 s, Leeren der Suche und Abwählen eines
  Chips 0,3–0,4 s, schnelles Tippen staut sich (341 ms Block, 1,95 s für 8 Zeichen). Einzelne
  Zeichen liegen mit 43–143 ms an der Wahrnehmungsgrenze. Ein Release-Build ist nicht gemessen;
  die QA soll dort nachmessen, bevor die Aussage bewertet wird. (AK-34)
- **FB-11 · Gewählter Chip nur über Farbe erkennbar, mit zu wenig Kontrast.**
  Fundstelle: `Views/ChannelListView.swift:137-157`. Weiß auf Akzentfarbe hat 3,76 : 1 (hell) bzw.
  2,77 : 1 (dunkel) bei 15-pt-Text (DS-01); es gibt kein Auswahl-Merkmal für VoiceOver, im
  Accessibility-Baum erscheinen die Chips nur als Buttons mit Titel.
  Folge: Die Auswahl ist für sehbehinderte Nutzer und mit Screenreader nicht erkennbar. Die
  Website hat das Problem für sich gelöst (`--accent-ink`), die App nicht. (AK-13)

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den
Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Logos von beliebigen Hosts, ohne Abschaltmöglichkeit, auch über HTTP und Weiterleitungen | ⚠ AK-25, AK-26, AK-27 **und** FB-06 | Die Website beschreibt Logo-Server als Empfänger, das Laden ist also gewollt; die Weitergabe von IP, Systemdaten und Sehverhalten an Dritte ohne Wahl ist aber eine Schwäche nach `sicherheit.md` 2, und die Website widerspricht sich selbst |
| 2 | Keine Größengrenze für Logos | ⚠ AK-24 + FB-05 | Zielmodus: fehlende Größenlimits bei unvertrauten Eingaben sind eine Schwäche |
| 3 | Logo-Cache inkl. `no-store`, bleibt nach Löschen | ⚠ AK-28 + FB-07 | beim Ausführen gefunden; Kopie außerhalb der Datenbank, die das Löschen übersteht (wie B01 FB-03) |
| 4 | Chip gekürzt, Filter ungekürzt | ⚠ AK-14, AK-15 + FB-01 | nicht sicherheitsrelevant, aber die Absicht (Chip zeigt seine Sender) ist eindeutig; eine offene Frage wäre Zurechtrücken durch Unterlassen |
| 5 | Chips veralten nach Aktualisieren | ⚠ AK-17 + FB-02 | Absicht eindeutig: der Kommentar zu `loadGroups` will die Gruppen „einmalig" laden, nicht veraltete zeigen |
| 6 | „Diese Playlist enthält keine Sender." bei leerem Filterergebnis | ⚠ AK-19 + FB-03 | die Aussage ist sachlich falsch |
| 7 | Dauerhafter Ladeindikator | ⚠ AK-22 + FB-04 | der Code sieht für Fehler ausdrücklich den Platzhalter vor |
| 8 | Kein Index, Filter über unindizierte Kopie | ⚠ AK-32 + FB-08 | Code-Kommentar und CLAUDE.md begründen die Kopie mit Geschwindigkeit; gemessen ist sie ohne Index, der Effekt bei 17.000 Sendern aber klein — ehrlich so benannt |
| 9 | `loadGroups` lädt alle Spalten in den Speicher | ⚠ AK-33 + FB-09 | FAQ verspricht „not in memory"; `propertiesToFetch` zeigt die Absicht, nur die Gruppe zu laden |
| 10 | „responds immediately" gegen die Messung | ⚠ AK-34 + FB-10 | Website verspricht mehr, als im Debug-Build gemessen; Einschränkung Debug-Build ausdrücklich vermerkt, Nachmessung im Release der QA übertragen |
| 11 | Kontrast und Auswahl-Merkmal der Chips | FB-11 | DS-01 ist bekannt; die Website zeigt, dass Lesbarkeit gewollt ist |
| 12 | Englischer Leerzustand der Suche | ⚠ AK-20 + OF-03 | nicht sicherheitsrelevant, Absicht nicht ableitbar; gleiche Lage wie B01 OF-06 |
| 13 | Zahlen nicht numerisch sortiert | ⚠ AK-09 + OF-01 | nicht sicherheitsrelevant, Absicht nicht ableitbar |
| 14 | Chip-Reihenfolge nach Zeichencode, Groß-/Klein-Varianten getrennt | ⚠ AK-12 + OF-02 | nicht sicherheitsrelevant, Absicht nicht ableitbar |
| 15 | Suche nur im Namen | AK-06 + OF-04 | die Website spricht von „Search by name" (`web/content/setup-steps.ts:17`); ob Gruppe/tvg-ID dazugehören sollen, ist offen |
| 16 | Kopfzeile zeigt Gesamtzahl | AK-02 + OF-05 | Absicht nicht ableitbar |
| 17 | `file://`-Logos | EC-05 + OF-06 | kein Abfluss nach außen, Absicht nicht ableitbar |
| 18 | Filter und Sortierung in der Datenbank | reguläres Kriterium AK-31 | CLAUDE.md, README und Website beschreiben das als gewollt, und es trifft zu |
| 19 | Lazy-Laden und Abbruch beim Wegscrollen | reguläre Kriterien AK-05, AK-23 | Verhalten von `LazyVStack`/`AsyncImage`, begrenzt die Anfragen; kein Sicherheitspunkt |
| 20 | Suchtext nicht protokolliert | reguläres Kriterium AK-29 | im PRD als Ist-Stand beschrieben und ausgeführt belegt |
| 21 | Quadratisches Anlegen der Sender | kein Kriterium hier, Randnotiz unter *Nicht im Scope* | gehört zu B02/B03 (`attach`), beim Aufbau der Messdaten gefunden |
