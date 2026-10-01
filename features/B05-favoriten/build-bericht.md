# B05 · Favoriten — Build-Bericht

Durchlauf 1 · 2026-09-30 bis 2026-10-01 · Eingang: Fehlerauftrag (`qa-report.md` QA 1, Status `review`). Gebaut am 30.09. auf
dem Branch `sdd/reparaturen` (Stand `main` `47a90c3` plus die damals nicht committeten Reparaturen B02+B03, B06, B07, B08, B04);
am 01.10. vor dem Abschluss angehalten und als Commit `b29408a` („UNVERIFIZIERT“) über PR #10 nach `main` übernommen. Abgeschlossen
am 01.10. auf `main` (`e5d0802`): Gesamtlauf, unabhängiges Review, zwei Nachbesserungen aus dem Review (F-04, Z-1.1 samt Testerweiterung;
nicht committet), dieser Bericht. macOS und iOS teilen den Code; ausgeführt ist macOS, iOS ist gebaut.

Auftrag: BUG-02, BUG-04, BUG-09 beheben; BUG-03 prüfen (was der gemeinsame Logo-Loader aus B04 abdeckt) und die Produktfrage als
offene Frage aufnehmen; BUG-01, BUG-10, BUG-11 (mit B02+B03 behoben) prüfen und vermerken; BUG-05 bis BUG-08 warten auf OF-03,
OF-02, OF-01, OF-04 und werden nicht gebaut. Mitgeführt: die Nacharbeit R-1 und R-2 aus dem B04-Review vom 30.09., dokumentiert in
`features/B04-senderliste/build-bericht.md`, *Nacharbeit nach Review 2026-09-30*.

## Ausgangslauf

Vor jeder Änderung (30.09., 21:54, Debug, `build/dd-test`, `test-without-building`, 8-MB-HFS+-Abbild voll für AK-27) die
QA-Tests der Fehler auf dem unveränderten Arbeitsbaum:

```
Test Case '-[… B05DatenschutzTests testAK25_Angriff5_TabFragtGenauDieLogosDerFavoritenAn]' passed
Test Case '-[… B05DatenschutzTests testAK27_SpeicherfehlerBeimUmschaltenWirdVerschluckt]' passed
Test Case '-[… B05SicherheitTests testAngriff7_NulZeichenWirdBeimSpeichernGekuerzt]' passed
Test Case '-[… B05SicherheitTests testAngriff7_UngewoehnlicheNamenUndTvgIDs]' passed
Test Case '-[… B05SternTests testAK05_VoiceOverKarteEinElementSternNurAlsAktionOhneZustand]' passed
Executed 5 tests, with 0 failures (0 unexpected)
** TEST EXECUTE SUCCEEDED **
```

Darin die fünf erwarteten Fehlschläge, die die Fehler reproduzieren (gekürzt):

```
B05DatenschutzTests.swift:274  Expected failure … testAK27_…: erwartet: Zustand zurückgesetzt oder Meldung (BUG-02)
  AK-27|nach-klick-voll|isFavorite=true|hasChanges=true|db=0|stern=akzent|tab=["Voll Zwei"]|alerts=[]
  AK-27|3s-nach-freigabe|db=0|hasChanges=true · weiterer-stern-mit-platz|dbZwei=1|dbDrei=1   ← unbemerkt nachgeschrieben
  AK-27|entfernen-im-tab-voll|tab=["Voll Zwei"]|isFavorite=false|db=1 · neustart-nach-entfernen|favoriten=["Voll Drei", "Voll Zwei"]
B05DatenschutzTests.swift:141  Expected failure … testAK25_…: Logo-Host erhält genau die Favoriten: ["/logos/sender-11.png", "/logos/sender-17.png", "/logos/sender-3.png"] (BUG-03)
  AK-25|payload|GET /logos/sender-3.png|accept-language: * · user-agent: Mozilla/5.0   ← schon seit B04 neutral
  AK-25|tab-erneut-geoeffnet|anfragen=0
B05SternTests.swift:223  Expected failure … testAK05_…: Karte vor und nach dem Umschalten gleich:
  role=AXButton|label=ZDF, Vollprogramm|value=|…|actions=["Rectangle Split Two By Two", "Favourite"] (BUG-04)
  leerzustand-texte|["MIKA+PLAYER · FAVORITEN", "Favoriten", "Favourite", "Keine Favoriten", …]
B05SicherheitTests.swift:111  Expected failure … testAngriff7_UngewoehnlicheNamenUndTvgIDs: ["Null@QA Eingaben"] (BUG-09, 10 → 9)
B05SicherheitTests.swift:136  Expected failure … testAngriff7_NulZeichen…: ("id:tvg-Null") is not equal to ("id:tvg-Null Byte") (BUG-09)
  Angriff-7|nul|parser name=9 zeichen, tvg=13|im speicher schlüssel="id:tvg-Null\0Byte"|nach neustart name="Null" schlüssel="id:tvg-Null"
```

Warnungen-Basis: `clean build-for-testing` desselben Stands (30.09., 21:53) – 21 Warnungsarten, alle in `Tests/` (veraltete APIs,
Sendable-Hinweise) und `appintentsmetadataprocessor`; keine in `Sources/`. Protokolle dieses Ausgangslaufs:
`~/.claude/projects/-Users-michaelferreira-DEV-macOS-MikaPlusPlayer/e8de96ed-…/b05work/logs/` (`repro-baseline.txt`,
`w-base.txt`).

## 1 · Umgesetzt

Ein Stern, der sich nicht speichern lässt, springt jetzt auf den gespeicherten Zustand zurück, und im Fenster, in dem geklickt
wurde, erscheint „Favorit nicht gespeichert – Der Stern konnte nicht gespeichert werden und ist zurückgesetzt. Bitte freien
Speicherplatz prüfen und erneut versuchen.“ Im Kontext der Ansicht bleibt nichts Ungespeichertes zurück, das ein späterer
Stern unbemerkt mitschreiben könnte; läuft gerade ein Aktualisieren, zieht es den verworfenen Stern nicht auf die neuen Sender
nach. VoiceOver sagt an, ob ein Sender Favorit ist (Wert „Favorit“ an der Karte), die Stern-Aktion heißt je Zustand „Favorit
hinzufügen“ bzw. „Favorit entfernen“, das Stern-Symbol des leeren Tabs ist ausgeblendet. Beim Anlegen und Aktualisieren – für
alle Importwege, weil alle über `PlaylistStore` speichern – entfallen Steuerzeichen (U+0000–U+001F, U+007F, außer Tabulator und
Zeilenumbrüchen) aus Name, Gruppe und `tvg-id`; ein Sender mit NUL im Namen bleibt damit über jedes Aktualisieren Favorit. Der
Favoriten-Schlüssel und – seit der Nachbesserung F-04 vom 01.10. – auch der Namensvergleich der Favoriten-Übernahme ignorieren
dieselben Zeichen, damit ältere Datenbestände mit solchen Zeichen ihre Sterne am richtigen Sender behalten.

| BUG | Grad | Ergebnis | Wo | Nachweis |
|---|---|---|---|---|
| BUG-01 (= B03 BUG-02, BF-53) | mittel | mit B02+B03 behoben, **geprüft** | `FavoriteCarryOver` (B02+B03) | A `testAK15_EC01_EC03_…M3U`, `testAK15_EC02_…Xtream`, `testAK19_…`, T `testEC01_…` im Gesamtlauf |
| BUG-02 | mittel | **behoben** | `FavoriteEdits.toggle` (wirft, rollt zurück, stellt Festgehaltenes wieder her), `PlaylistStoreError.starNotSaved`, `ChannelRowView` (Meldung) | D `testAK27_SpeicherfehlerBeimUmschaltenSetztZurueckUndMeldet` (volles 8-MB-Abbild), R `testBUG02_…` ×2 |
| BUG-03 | mittel | **nicht behoben** (Kern: Produktfrage, `spec.md` OF-08, Bezug B04 OF-07); geprüft, was B04 abdeckt | — (Loader aus B04) | R `testBUG03_FavoritenTabNutztDenGemeinsamenLogoLoader`; D `testAK25_…` behält `XCTExpectFailure` |
| BUG-04 | mittel | **behoben** (Grenze während des Logo-Ladens: OF-10) | `ChannelRowView` (`accessibilityValue` am Namen, `accessibilityLabel` am Stern), `FavoritesView` (Symbol ausgeblendet) | S `testAK05_VoiceOverKarteEinElementZustandUndAktionJeZustand`, S `testAK01_…`, T `testAK07_…`, T `testAK08_…` |
| BUG-05 | niedrig | **nicht behoben** (wartet auf OF-03) | — | A `testAK11_AK12_AK13_AK14_…` behält `XCTExpectFailure` |
| BUG-06 | niedrig | **nicht behoben** (wartet auf OF-02) | — | T `testAK09_…` behält `XCTExpectFailure` |
| BUG-07 | niedrig | **nicht behoben** (wartet auf OF-01) | — | T `testAK10_…` behält `XCTExpectFailure` |
| BUG-08 | niedrig | **nicht behoben** (wartet auf OF-04) | — | L `testAK20_Angriff8_…` behält `XCTExpectFailure` |
| BUG-09 | niedrig | **behoben** | `Channel.removingControlCharacters`, `Channel.favoriteKey`, `ParsedChannel.withoutControlCharacters`, `PlaylistStore.create`/`replaceChannels`, Namensvergleich in `FavoriteCarryOver.flags` (Nachbesserung F-04) | X `testAngriff7_UngewoehnlicheNamenUndTvgIDs`, X `testAngriff7_NulZeichenWirdBeimAnlegenEntferntSchluesselBleibt`, R `testBUG09_…` ×4 |
| BUG-10 (= BF-59) | niedrig | mit B02+B03 behoben, **geprüft** | `PlaylistStore.compact` (B02+B03) | L `testAK28_…` im Gesamtlauf |
| BUG-11 (BF-90) | mittel | mit B02+B03 behoben, **geprüft** | `PlaylistStore.replaceChannels` (B02+B03) | A `testAK17_Randfall_SpeicherfehlerBeimAktualisieren` mit vollem Abbild im Gesamtlauf |

Kürzel: S `B05SternTests`, T `B05TabTests`, A `B05AktualisierenTests`, L `B05LoeschenTests`, D `B05DatenschutzTests`,
X `B05SicherheitTests`, R `B05ReparaturTests` (neu, 7 Tests).

Tests: Von 9 `XCTExpectFailure`-Blöcken in `Tests/B05` (nach der B02+B03-Reparatur) sind 4 entfernt (BUG-02, BUG-04, BUG-09 ×2);
die Zusicherungen, die das fehlerhafte Verhalten festschrieben, stehen jetzt auf dem behobenen Verhalten. Unverändert bleiben 5:
BUG-03 (Kern, OF-08), BUG-05, BUG-06, BUG-07, BUG-08 – im Gesamtlauf schlugen genau diese fünf erwartet fehl. Umbenannt, weil der
Name den Fehler beschrieb: D `testAK27_SpeicherfehlerBeimUmschaltenWirdVerschluckt` → `…SetztZurueckUndMeldet`, S
`testAK05_VoiceOverKarteEinElementSternNurAlsAktionOhneZustand` → `…ZustandUndAktionJeZustand`, X
`testAngriff7_NulZeichenWirdBeimSpeichernGekuerzt` → `…WirdBeimAnlegenEntferntSchluesselBleibt` (prüft jetzt den echten
Anlegeweg statt eines direkt eingefügten Senders). Neu: `Tests/B05/B05ReparaturTests.swift` (7 Tests: BUG-02 ohne Abbild und im
Zusammenspiel mit dem Festhalten, BUG-03 im Tab, BUG-09 für Xtream, Altbestand, Zeichenumfang und – Nachbesserung F-04 – den
Namensvergleich der Übernahme). `B05Support`: Hilfen `alertTexts`/`confirmAlert`, `close()` schließt einen offenen Alert.

**Nachbesserungen nach dem Review vom 01.10.** (Abschnitt *Unabhängiges Review*), nicht committet:

- **F-04 · Namensvergleich der Übernahme (BUG-09):** `FavoriteCarryOver.flags` verglich beim Rangschritt „derselbe Name“ den
  bereinigten neuen Namen mit dem unbereinigten gespeicherten. Bei einem Altbestand mit Steuerzeichen im Namen, mehreren Kandidaten
  mit demselben Schlüssel und neuen Stream-Adressen ging der Stern an den ersten Kandidaten des Anbieters statt an den Sender mit
  demselben Namen. Jetzt werden beide Namen ohne Steuerzeichen verglichen. Gegenprobe: Der neue Test schlug ohne die Änderung fehl
  (`[true, false]` statt `[false, true]`), mit ihr ist er grün.
- **Z-1.1 · Akzent-Tasten im inaktiven Fenster (B04 · R-1):** siehe `features/B04-senderliste/build-bericht.md`; die fest gesetzte
  Schrift `playerOnAccent` stand in inaktiven Fenstern im Dunkelmodus Fast-Schwarz auf Dunkelgrau (1,35 : 1). Neu:
  `playerOnAccentLabel()` in `PlayerTheme.swift`.
- **F-05 · VoiceOver während des Logo-Ladens (BUG-04):** nicht gebaut, weil es das B04-Verhalten aller Karten ändert → `spec.md`
  OF-10 (Abschnitt 2).

## 2 · Offene Kriterien und nicht behobene BUGs

- **BUG-03, Kern** — Beim ersten Öffnen des Tabs erfährt jeder Logo-Host weiter die IP-Adresse und über die Auswahl der Logos die
  Favoritenliste. Ob der Tab Logos überhaupt laden soll (Platzhalter, nur schon geladene, Schalter, Zustimmung), verändert
  sichtbar, was der Tab zeigt → `spec.md` OF-08 (Bezug B04 OF-07). Geprüft und belegt ist, was B04 schon abdeckt (siehe
  `qa-report.md` BUG-03). Belegt: `testAK25_…` schlägt weiter erwartungsgemäß fehl (3 Anfragen, genau die Favoriten).
- **BUG-04, während das Logo lädt** — Solange ein Logo lädt (bis 10 s ohne Daten, 15 s insgesamt, bei vielen Logos eines Hosts
  länger), meldet sich die Karte wie in AK-05 und B04 AK-22 beschrieben als Ladeanzeige (`AXBusyIndicator`, Wert „0“). Der Wert
  „Favorit“ fehlt in dieser Zeit; den Zustand verrät nur der Aktionsname. Das erfüllt die Erwartung des Fehlerauftrags
  („Wert, Zustand **oder** unterschiedlich benannte Aktion“), aber nicht die Annahme 5 vollständig → `spec.md` OF-10. Belegt mit
  einer Prüfsonde (01.10., Logo-Host hängt): nach 2 s und 5 s `role=AXBusyIndicator|value=0|aktionen=[…, "Favorit entfernen"]`,
  nach Ablauf der Frist `role=AXButton|value=Favorit`; ohne Logo sofort `AXButton`/„Favorit“. Kein dauerhafter Test (die Sonde ist
  wieder entfernt), weil das Verhalten von der offenen Frage abhängt.
- **BUG-05, BUG-06, BUG-07, BUG-08** — nicht gebaut, warten auf OF-03, OF-02, OF-01, OF-04 (Produktentscheidungen). Belegt:
  ihre `XCTExpectFailure` schlagen weiter erwartungsgemäß fehl.
- **BUG-09, Altbestand mit NUL** — Ein Favorit, dessen Name oder `tvg-id` schon **vor** der Reparatur ein NUL-Zeichen hatte, steht
  in der Datei bereits gekürzt („Null“ statt „NullByte“) und geht beim ersten Aktualisieren danach einmal verloren; vorher ging
  er bei jedem Aktualisieren verloren. **Abgeleitet, nicht eigens ausgeführt:** Die Kürzung beim Speichern ist in QA 1 gemessen
  (BUG-09, `nach neustart name="Null"`), der Schlüssel der bereinigten neuen Liste lautet `id:tvg-NullByte` – die beiden passen
  nicht zusammen. Ohne den abgeschnittenen Teil nicht zu retten → `spec.md` OF-09. Andere Steuerzeichen speichert die Datei
  vollständig; solche Altbestände behalten ihren Stern (belegt: `testBUG09_AltbestandMitSteuerzeichenBehaeltDenStern`, ESC).
- **iOS nur gebaut, nicht bedient.** Meldung (`.alert` in der Karte), VoiceOver-Wert und Aktionsnamen sind unter iOS nicht zur
  Laufzeit geprüft; die Umgebung hat keine Tipp- und VoiceOver-Automatisierung für den Simulator (wie QA 1, AK-06/EC-10). Unter iOS
  ist die Karte ein `NavigationLink` mit eingebettetem Stern-Button; ob VoiceOver dort Wert und Aktionsnamen gleich zusammenfasst
  wie unter macOS, ist ungeprüft (Review F-06).
- **BUG-02 im Standardlauf** — Die Oberflächenprüfung (Meldung, grauer Stern, Tab) läuft nur mit eingehängtem, vollschreibbarem
  Abbild (`TEST_RUNNER_B05_FULL_VOLUME`); ohne die Variable überspringt sich `testAK27_…` selbst, und nur die Testnaht
  (`B05ReparaturTests.testBUG02_…`) läuft. Beide Gesamtläufe dieses Berichts liefen **mit** Abbild (Review F-09).
- **BUG-04, Sprache** — OF-06 (deutsch oder Systemname) ist nicht beantwortet; der Fehlerauftrag verlangte deutsche Namen, gebaut
  ist deutsch, Vermerk unter OF-06. Der ⊞-Button derselben Karte heißt für VoiceOver weiter „Rectangle Split Two By Two“ (B08,
  nicht im Auftrag).
- **Nicht aus dem Auftrag, festgestellt:**
  - Der **Playlist-Name** wird nicht bereinigt: Ein eingegebener Name mit NUL-Zeichen wird weiter beim Speichern gekürzt
    (`B02SicherheitTests.testAngriff07_Eingaben` hält das als Ist fest und verweist auf B05 · BUG-09). Betrifft keine Favoriten;
    gehört zu B02 (Namensfeld im Import-Sheet).
  - `docs/datenmodell.md` („`favoriteKey` = `id:<tvgID>` …“), `features/B02-m3u-import/spec.md` EC-06 („NUL, ESC-Sequenzen …
    bleiben im Namen stehen und erreichen die Anzeige in B04“), die rekonstruierten Kriterien AK-05 und AK-27 in
    `features/B05-favoriten/spec.md` sowie „Angriff 7 · Eingaben“ in der Sicherheitsprüfung von `features/B05-favoriten/qa-report.md`
    beschreiben das Ist vor der Reparatur – **nicht geändert, jetzt veraltet**; Nachführen ist Sache von QA-Durchlauf 2.
  - `CLAUDE.md` nennt `PlaylistImporter` weiter als einzigen Ort, der Modelle anlegt; seit B02+B03 legt `PlaylistStore` sie an.

## 3 · Getroffene Annahmen

Alle ohne Rückfrage (Zielmodus), zur Bestätigung durch den Nutzer; die mit Produktfolge stehen als OF-06 (Vermerk), OF-08,
OF-09 und OF-10 in `spec.md`.

1. **Zurückrollen des ganzen Ansichtskontexts (BUG-02):** Scheitert das Speichern eines Sterns, wird der Kontext der Ansicht
   zurückgerollt (`rollback()`), nicht nur der eine Wert zurückgesetzt – so bleibt nichts Ungespeichertes übrig, das ein späteres
   Speichern mitschreibt (in QA 1: der nächste Stern schrieb den verworfenen mit). Verworfen wird damit genau das, was dieses
   Speichern hätte schreiben sollen: Alle anderen Schreibwege der Ansicht (Übernahme nach Import, Abholen nach dem Aktualisieren,
   Löschen, „Alle Daten entfernen“) speichern sofort; `adopt` (Übernahme nach Import) rollt bei einem Fehler nicht selbst zurück,
   schreibt aber nur Werte, die schon in der Datei stehen (Review F-01, widerlegt). Gemessen: danach `hasChanges = false`, Stern
   und Tab zeigen den Stand der Datei.
2. **Meldung (BUG-02):** Titel „Favorit nicht gespeichert“, Text „Der Stern konnte nicht gespeichert werden und ist
   zurückgesetzt. Bitte freien Speicherplatz prüfen und erneut versuchen.“, nur „OK“; gleich für Setzen und Entfernen, im
   Fenster der geklickten Karte (Senderliste oder Tab), kein automatischer neuer Versuch. Wortlaut angelehnt an die Meldungen der
   B02+B03-Reparatur („… Bitte freien Speicherplatz prüfen und erneut versuchen.“).
3. **Festgehaltenes beim Aktualisieren (BUG-02 × R-01):** Ein verworfener Stern stellt das Festgehaltene der Playlist genau auf den
   Stand vor dem Klick zurück (kein Eintrag für den verworfenen Stern; ein früher gespeicherter Stern desselben Senders bleibt, wie
   er war). Ein Stern an einem alten Sender, den das Ersetzen schon gelöscht hat, speichert weiter ohne Fehler (belegt in QA/Review
   R-01b: `speichernDerAnsichtOhneFehler=true`); das Nachziehen aus R-01 bleibt also unverändert.
4. **Testnaht (BUG-02):** `FavoriteEdits.toggle(_:in:save:)` mit austauschbarem Speichern, damit das Zusammenspiel ohne vollen
   Datenträger prüfbar ist; die App benutzt nur `toggle(_:in:)` (echtes `save()`).
5. **VoiceOver (BUG-04):** Wert „Favorit“ nur bei Favoriten (kein „Kein Favorit“ an jeder anderen Karte – die Aktion „Favorit
   hinzufügen“ sagt das schon); Aktionsnamen je Zustand. Der Wert steht am Namen, nicht an der ganzen Karte: Die Karte
   (`NavigationLink`) fasst ihre Teile zusammen und übernahm einen Wert am Stapel je Teil („Favorit, Favorit, Favorit, …“,
   gemessen). Während ein Logo lädt, überdeckt die Ladeanzeige den Wert (OF-10). Das Stern-Symbol des Leerzustands ist Schmuck
   und ausgeblendet (wie in `PlayerView`); die Überschrift „Keine Favoriten“ trägt die Aussage.
6. **Umfang der Bereinigung (BUG-09):** entfernt werden U+0000–U+001F und U+007F außer Tabulator, Zeilenvorschub, vertikalem
   Tabulator, Seitenvorschub und Wagenrücklauf. Leerraum bleibt, weil er sichtbar ist und ein Zeilenumbruch in einer Gruppe laut
   B04 AK-11 eine eigene Gruppe ist. Die Steuerzeichen U+0080–U+009F bleiben, weil sie in der Praxis aus dem Latin-1-Rückfall
   stammen (B02 EC-07/EC-08, dort OF-06) und die Datei sie unverändert speichert; eine erste Fassung, die sie mit entfernte, hätte
   die festgehaltenen Ergebnisse von B02 EC-07 („Ã\u{84}rger TV“) und EC-08 („Preis \u{80} TV“) geändert und ist verworfen.
   Formatzeichen (U+202E) bleiben (B02 EC-06). Gruppe und `tvg-id`, die nur aus solchen Zeichen bestanden, entfallen (`nil`);
   ein Name, der dadurch leer wird, bleibt leer (kein Rückgriff auf die Adresse wie beim leeren M3U-Namen).
7. **Ort der Bereinigung (BUG-09):** im gemeinsamen Anlegeweg (`PlaylistStore.create` und `replaceChannels`, vor der
   Favoriten-Übernahme), nicht im Parser: So gilt sie für M3U per URL, Datei, „Öffnen mit“, Xtream und Aktualisieren an einer
   Stelle, und die Parser-Ergebnisse (B02 EC-06: Parser liefert NUL/ESC) bleiben unverändert.
8. **Schlüssel und Namensvergleich (BUG-09):** `Channel.favoriteKey` ignoriert dieselben Zeichen, ebenso – seit der Nachbesserung
   F-04 – der Rangschritt „derselbe Name“ in `FavoriteCarryOver.flags`. Für neue Daten ändert das nichts (sie enthalten keine
   mehr); für ältere Bestände mit ESC & Co. sorgt es dafür, dass der erste Abgleich nach dem Update die Sterne am richtigen Sender
   findet. Eine `tvg-id` nur aus Steuerzeichen gilt als leer (Schlüssel dann über den Namen). Zwei Kandidaten, die sich nur durch
   Steuerzeichen unterschieden, sind nach der Bereinigung ohnehin gleichnamig.
9. **BUG-03:** kein Code; die Prüfung steht als Test (`testBUG03_…`) und im `qa-report.md`.

## 4 · Systemweite Änderungen

| Datei / Stelle | Feature | Änderung |
|---|---|---|
| `Sources/Services/PlaylistStore.swift` – `PlaylistStore.create`, `replaceChannels` | **B01, B02, B03** | Name, Gruppe und `tvg-id` werden ohne Steuerzeichen gespeichert – für jeden Importweg und beim Aktualisieren (neu: `ParsedChannel.withoutControlCharacters`). Sichtbar nur bei Listen mit solchen Zeichen (z. B. ESC-Farbfolgen, NUL) |
| `Sources/Services/PlaylistStore.swift` – `FavoriteCarryOver.flags` | **B03** | Nachbesserung F-04: Rangschritt „derselbe Name“ vergleicht ohne Steuerzeichen; Reihenfolge der Rangschritte unverändert |
| `Sources/Services/PlaylistStore.swift` – `FavoriteEdits.toggle` | B03 (R-01), B04 | wirft jetzt `PlaylistStoreError.starNotSaved`, rollt bei einem Speicherfehler den Kontext der Ansicht zurück und stellt das Festgehaltene wieder her; neue Überladung `toggle(_:in:save:)`; neuer Fall `PlaylistStoreError.starNotSaved` |
| `Sources/Models/Channel.swift` | B01, B02, **B03** | `favoriteKey(name:tvgID:)` ignoriert Steuerzeichen; neu `removingControlCharacters(_:)`. **Kein** Schemawechsel, `SchemaMigrationPlan` unverändert |
| `Sources/Views/ChannelRowView.swift` | **B04**, B08 | gilt auch für jede Karte der Senderliste: Meldung bei Speicherfehler, VoiceOver-Wert „Favorit“, Stern-Aktion „Favorit hinzufügen/entfernen“ (vorher „Favourite“). Logo (B04) und ⊞ (B08) unverändert; Tests, die Karten über Label/Wert suchen, schneiden den Wert ab (B04 `rows`) bzw. vergleichen nur den Anfang (B08 `card(…)`, `hasPrefix`) |
| `Sources/Views/FavoritesView.swift` | — | Stern-Symbol des Leerzustands für VoiceOver ausgeblendet |
| `Sources/Views/Theme/PlayerTheme.swift` – neu `PlayerOnAccentLabelModifier`/`playerOnAccentLabel()` | **Design-System**, B02, B03, B04, B06 | Nachbesserung zu B04 · R-1 (Z-1.1): Beschriftung hervorgehobener Tasten in `playerOnAccent`, in inaktiven macOS-Fenstern Systemschrift. Eingesetzt an „+“ und „Playlist importieren“ (`PlaylistsView`), „Alle Sender zeigen“ (`ChannelListView`), „Erneut versuchen“ (`PlayerView`). Ausführlich in `features/B04-senderliste/build-bericht.md` |
| `Tests/B03/B03NacharbeitTests.swift` | B03 | `FavoriteEdits.toggle` wirft: `tapStar` mit `XCTAssertNoThrow`, im Test-Haken `do/catch` mit `XCTFail` – strenger als vorher (`try?` im Produktcode verbarg dort jeden Fehler) |
| `Tests/B04/B04Support.swift`, `B04NacharbeitTests.swift`, `B04LeistungTests.swift` | Tests | Nacharbeit R-1/R-2 samt Nachbesserung (siehe B04-Bericht): `forceActive`/`controlState` für Testfenster, Kontrast in drei Fensterzuständen, strikte Leistungsgrenzen |
| `Tests/B05/*` | Tests | siehe Abschnitt 1 |
| `docs/datenmodell.md`, `features/B02-m3u-import/spec.md` (EC-06), `features/B05-favoriten/spec.md` (AK-05, AK-27), `features/B05-favoriten/qa-report.md` (Angriff 7) | Doku | **nicht geändert, jetzt veraltet** (siehe 2) |
| `features/B05-favoriten/spec.md` | Doku | nur *Offene Fragen*: Vermerk unter OF-06, neu OF-08, OF-09, OF-10 |
| `features/B04-senderliste/spec.md` | Doku | nur *Offene Fragen*: neu OF-09 („Erneut versuchen“ im inaktiven Fenster, hell) |
| `features/B05-favoriten/qa-report.md` | Doku | Vermerke unter allen elf BUGs |
| `project.yml`, `Info.plist`, Entitlements, Abhängigkeiten, Schema | alle | **unverändert** |

Nicht angefasst: `features/befunde.md`, `appcast.xml`, `web/`, `CLAUDE.md` (siehe 2), Schlüsselbund, die echte Datenbank.
`features/index.md`: nur die Spalte *Zuletzt* der Zeilen B04 und B05, Status unverändert `building`.

## Unabhängiges Review

**Review 2026-10-01**, zwei Durchgänge. Beide liefen **nur lesend** (keine Builds, keine Tests, kein App-Start), parallel zu den
Gesamtläufen; was sich nur zur Laufzeit klären ließ, habe ich danach mit Prüfsonden selbst ausgeführt. Ergebnisse (JSON) außerhalb
des Repositorys unter `~/.claude/projects/…/e117f1c2-…/b05abschluss/review/`.

**Durchgang 1 – Commit `b29408a` (Reparatur und Nacharbeit R-1/R-2) samt den Berichtsentwürfen.** Sieben Prüfer mit je eigenem
Blickwinkel (BUG-02, BUG-09, BUG-04, R-1/R-2, Testqualität, Auftragstreue und Entwürfe, Regressionen anderer Features), jeder Fund von
zwei Gegenprüfern angegriffen (Code; Wirkung und Grad), danach eine Vollständigkeitsrunde mit drei Zusatzprüfern. 16 Rohfunde → 14
nach Zusammenführen, dazu 7 aus der Zusatzrunde. Ohne Fund geprüft u. a.: jede Änderung lässt sich auf BUG-02/-04/-09 oder R-1/R-2
zurückführen; `spec.md` nur unter *Offene Fragen* geändert; alle Aufrufer von `FavoriteEdits.toggle` (jetzt `throws`) angepasst;
`PlaylistStore.create`/`replaceChannels` ist der einzige Ort, an dem Sender entstehen; die vier entfernten `XCTExpectFailure` sind
durch strikte Zusicherungen ersetzt, 5 bleiben; Tests anderer Features, die die Tasten über ihre Beschriftung finden, passen weiter.

| Fund | Urteil | Inhalt | Umgang |
|---|---|---|---|
| **Z-1.1** | bestätigt (hoch/mittel) | R-1: fest gesetztes `playerOnAccent` in inaktiven Fenstern | **zur Laufzeit bestätigt** (dunkel 1,35 : 1) → **nachgebessert** (`playerOnAccentLabel()`), Test misst jetzt drei Fensterzustände; Rest „Erneut versuchen“ hell inaktiv → B04 OF-09 |
| **F-04** | bestätigt (mittel) | Namensvergleich der Übernahme mit unbereinigtem Altnamen | **nachgebessert**, neuer Test, Gegenprobe rot |
| **F-05** | bestätigt (mittel) | VoiceOver-Wert „Favorit“ während des Logo-Ladens ungeprüft | **zur Laufzeit bestätigt** (`AXBusyIndicator`, Wert „0“) → B05 OF-10, Abschnitt 2 |
| **F-09** | bestätigt (mittel/gering) | BUG-02-Oberflächentest nur mit Abbild | beide Gesamtläufe mit Abbild; in Abschnitt 2 und im `qa-report.md` vermerkt |
| F-13 | bestätigt (gering) | Entwurf verortete „Angriff 7“ in `spec.md` | korrigiert (steht in `qa-report.md`) |
| Z-3.3 | bestätigt (mittel) | Entwurf behauptete Nicht-Zugesichertes zum weitergeleiteten Logo | Vermerk unterscheidet jetzt „zugesichert“ und „laut Protokoll“ |
| F-06 | strittig | BUG-04 unter iOS nicht laufzeitgeprüft | so in Abschnitt 2 (iOS nur gebaut) |
| F-08, F-10 | strittig | Entwürfe nannten „≤ 100 ms strikt“, gebaut sind 120 ms | Berichte nennen 120 ms mit Begründung (B04-Nachtrag, Annahme 3) |
| F-14 | strittig (Hinweis) | 120 ms mit wenig Abstand zu beobachteten Werten | Gesamtläufe 01.10.: 77 bzw. 80 ms; bleibt im Blick |
| Z-2.1 | strittig | Stern könnte nach `rollback()` optisch nicht zurückspringen | **zur Laufzeit widerlegt**: `stern=grau` nach dem gescheiterten Setzen, `stern=akzent` nach dem gescheiterten Entfernen (macOS 27; macOS 14/iOS 17 nicht ausgeführt) |
| Z-2.2 | strittig | grauer Stern nicht durch einen Lauf belegt | jetzt belegt (beide Gesamtläufe) |
| Z-3.1, Z-3.2 | strittig | Entwurfsvermerke ohne Laufreferenz | Vermerke nennen die Gesamtläufe vom 01.10. |
| Z-3.4 | strittig | NUL-Altbestand nur abgeleitet | als „abgeleitet, nicht eigens ausgeführt“ gekennzeichnet |
| F-01, F-02, F-03, F-07, F-11, F-12 | widerlegt | `adopt` ohne Rollback (schreibt nur Werte, die schon in der Datei stehen); Karte fällt im Tab kurz aus der Liste (synchroner Pfad, belegt: Meldung erscheint im Tab); `rollback()` an ersetztem Sender; 120 ms ohne OF; Öffnen-Grenze; Zuverlässigkeit von `rollback()` | keine Änderung |

**Durchgang 2 – die Nachbesserungen (Diff gegen `b29408a`).** Drei Prüfer (Modifier, F-04, Tests und offene Fragen), je Fund zwei
Gegenprüfer. Ohne Fund: iOS-Zweig des Modifiers kompiliert und ist richtig gepaart; nur die vier Tasten haben eine
`.borderedProminent`-Akzentfläche (der Chip zeichnet seine Fläche selbst und wird nicht grau); F-04 spiegelt genau die
Normalisierung von `favoriteKey`; `spec.md`-Änderungen nur unter *Offene Fragen*. Funde:

| Fund | Urteil | Umgang |
|---|---|---|
| `.active` (Hauptfenster, nicht key) wird wie `.key` behandelt | strittig (hoch/gering) | Sonde vom 01.10.: in `.active` zeichnet macOS die Akzentfläche, `playerOnAccent` erreicht dort 5,86 / 7,94 : 1; als dritter Zustand in `testR1_…` aufgenommen (24 Messungen) |
| iOS: gedimmte Tint-Farbe bei offenem Sheet/Alert | strittig | nicht gemessen, im B04-Nachtrag unter *Offen* |
| Namensvergleich der Übernahme unterscheidet Groß-/Kleinschreibung, der Schlüssel nicht | bestätigt (Hinweis) | vorbestehend, nicht Teil des Auftrags; keine Änderung |
| Messwerte der OF-09/OF-10 durch Lesen nicht nachprüfbar | bestätigt (Hinweis) | Messprotokolle unter *Verifikation* |

## Verifikation

Stand **2026-10-01**, `main` `e5d0802` (= Commit `b29408a` der Reparatur) plus die Nachbesserungen dieses Abschlusses (nicht
committet). Debug, `build/dd-test`, `test-without-building`. Streams auf den geschlossenen Port 9 bzw. lokale Mocks, keine Tonspur;
Logo-Hosts nur auf 127.0.0.1. Gesamtläufe mit Aktivierungshelfer (wie im B04-Build: `TEST_RUNNER_B06_ACTIVATE_REQ`,
`TEST_RUNNER_B08_AKTIVIEREN`, `TEST_RUNNER_B07_BRIDGE`; der Helfer holt den Test-Host per Bedienungshilfen nach vorn und lehnt alle
anderen Bridge-Befehle ab), `TEST_RUNNER_B05_FULL_VOLUME` (frisches 8-MB-HFS+-Abbild, vor jedem Lauf angelegt, danach ausgehängt und
gelöscht), Nachweise von B04/B08 in einen Ordner außerhalb des Repositorys (`TEST_RUNNER_B04_QA_DIR`, `TEST_RUNNER_B08_QA_EVIDENCE`),
`caffeinate -d -i -u`. Protokolle aller Läufe: `~/.claude/projects/…/e117f1c2-…/b05abschluss/logs/`.

**1 · Projekt erzeugen** — `xcodegen generate` → exit 0 (vor jedem Bau).

**2 · Warnungen** — `xcodebuild clean build-for-testing … -derivedDataPath build/dd-test` auf dem Commit-Stand (18:31) und nach den
Nachbesserungen (19:41; danach nur noch die Testerweiterung `.active`, 22:13 inkrementell): `** CLEAN SUCCEEDED **`,
`** TEST BUILD SUCCEEDED **`, **0 Warnungen in `Sources/`**; die Warnungsliste (21 Arten, alle in `Tests/` und
`appintentsmetadataprocessor`) ist **zeichengleich** zur Basis vor der Reparatur (`w-base.txt` vom 30.09.). Keine neue Warnung.

**3 · macOS-Gesamtlauf (Endstand)** — Lauf 2 (19:43–20:13, Last 2,6–5) blieb um 20:13:40 in
`B06EngineZustandTests.testAK09_AK32_AK35_VLCSpieltAlleEndungen` stehen: Der Hauptthread wartete in
`libvlc_media_player_stop_async` → `__psynch_mutexwait` (Stapel gesichert, `haenger-gesamt-2.sample.txt`), 0 % CPU – der bekannte
libVLC-Hänger beim Abbau (BF-101, B06 BUG-03 wartet auf OF-06), den die B06-Tests nicht über die Senderliste erreichen. Bis dahin 42
Suiten ohne Fehlschlag (alle von B01 bis B05 und `B06Deadlock`). Um 22:13 beendet; danach die 28 fehlenden Suiten und
`B04NacharbeitTests` in der Endfassung (24 Messungen) als Restlauf (22:14–22:40, Last 28 → 5, mit Wachhund gegen Hänger):

```
xcodebuild test-without-building -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer-macOS -destination 'platform=macOS' \
  -derivedDataPath build/dd-test -collect-test-diagnostics never [-only-testing: … 29 Suiten im Restlauf]
Lauf 2 bis zum Hänger   42 Suiten   333 Tests,  7 übersprungen, 0 Fehlschläge   (B04NacharbeitTests dort in der Fassung mit 16 Messungen, grün)
Restlauf                29 Suiten   186 Tests, 12 übersprungen, 0 Fehlschläge   ** TEST EXECUTE SUCCEEDED **
zusammen                71 Suiten   519 Tests, 19 übersprungen, 0 Fehlschläge
```

Dieselben 71 Suiten wie in Lauf 1, ein Test mehr (`B05ReparaturTests` 7 statt 6, Nachbesserung F-04). Die 19 Übersprungenen
überspringen sich selbst mit einem Umgebungsgrund (Laufzeit > 3 min, Private-Data-Logging, SQLDebug/iOS-Store nur auf Anforderung,
B06 langsam/Deadlock/Erkundung, B08 Hänger/Tasten/Absturz/Neustart, fünf B07-Systemfenster-Tests ohne Bridge, B02 ohne eigenes
Abbild, B03 EC-03 nicht provozierbar). Erwartete Fehlschläge in `Tests/B05` genau die fünf wartenden: BUG-03 (`testAK25_…`), BUG-05
(`testAK11_AK12_AK13_AK14_…`), BUG-06 (`testAK09_…`), BUG-07 (`testAK10_…`), BUG-08 (`testAK20_…`); in `Tests/B04` die bekannten
(BUG-08 ×2, BUG-09, BUG-11, OF-07, nicht strikt „< 50 ms je Zeichen“) und neu OF-09 („Erneut versuchen“ hell inaktiv, 2,63 : 1).
Die B05-Belege von Lauf 1 und Lauf 2 sind zeilengleich (bis auf die Reihenfolge in einem Wörterbuch).

**4 · Frühere Läufe und Prüfungen dieses Abschlusses**

| Lauf | Stand | Ergebnis | Einordnung |
|---|---|---|---|
| Gesamtlauf 1 (18:33–19:26, Last 11 → 4) | Commit `b29408a` | 71 Suiten, 518 Tests, 19 übersprungen, **1 rot**: B06 `testAK01_AK14_…` („SYSTEMBEEP-UNTERDRUECKT NSWindow keyDown:“) | Das erste Tastenereignis kam vor dem Vordergrundholen an (Helfer meldete `b06.req … ok` in derselben Sekunde) – Aktivierung des Test-Hosts, wie im B04-Build Lauf 5. Wiederholt (19:28–19:33, `-test-iterations 2`): `B06PlayerViewTests` 33 Tests, 1 übersprungen, **0 rot**. Alle B04- und B05-Suiten grün, B04 R-2: Öffnen 71/66 ms, je Zeichen höchstens 77 ms |
| Prüfsonde R-1 (19:35) | Commit-Stand | Kontrast in allen Fensterzuständen (Tabelle im B04-Nachtrag) | bestätigt Review Z-1.1 (dunkel inaktiv 2,17 bzw. 1,35 : 1) |
| Prüfsonde F-05 (19:37) | Commit-Stand | Karte während des Logo-Ladens `AXBusyIndicator`, Wert „0“; nach der Frist `AXButton`/„Favorit“ | bestätigt Review F-05 → OF-10 |
| Gegenprobe (19:40) | Nachbesserungen zurückgenommen | `testR1_…` rot (dunkel inaktiv 1,35/1,92, hell inaktiv „Erneut versuchen“ 2,92 : 1), `testBUG09_Namensvergleich…` rot (`[true, false]`) | beide neuen Prüfungen erkennen den Fehler |
| Nachher (19:41, 19:43) | Nachbesserungen | `testBUG09_Namensvergleich…` und alle `B05ReparaturTests` grün; `testR1_…` 15 von 16 ≥ 4,5 : 1, der 16. Fall (2,63 : 1, Systemdarstellung) → OF-09 und erwarteter Fehlschlag, danach grün | — |
| Gesamtlauf 2, Restlauf | Endstand | siehe 3 | — |

Die beiden Prüfsonden standen vorübergehend als `Tests/B04/B04ZProbeR1InaktivTests.swift` im Projekt und sind entfernt (Kopie außerhalb
des Repositorys, `sonde-B04ZProbeR1InaktivTests.swift`).

**5 · Belege je BUG im Endstand** (Lauf 2, gekürzt; Lauf 1 gleich):

```
AK-27|nach-klick-voll|isFavorite=false|hasChanges=false|db=0|stern=grau|tab=[]|alert=["alert", "Favorit nicht gespeichert", "Der Stern konnte nicht gespeichert werden und ist zurückgesetzt. Bitte freien Speicherplatz prüfen und erneut versuchen.", "OK"]|alertTab=[]
AK-27|expliziter-save|ok · neustart-voll|favoriten=[] · 3s-nach-freigabe|db=0|hasChanges=false
AK-27|weiterer-stern-mit-platz|dbZwei=0|dbDrei=1|hasChanges=false|alert=[]
AK-27|entfernen-im-tab-voll|tab=["Voll Drei"]|isFavorite=true|db=1|stern=akzent|hasChanges=false|alert=["alert", "Favorit nicht gespeichert", …]
AK-27|neustart-nach-entfernen|favoriten=["Voll Drei"]
BUILD|BUG-02|nachgestellt|a=false|b=true|hasChanges=false|dbA=0|dbB=1 · festgehalten=["Kanal B=true"]
AK-01|liste|role=AXButton|label=ZDF, Vollprogramm|value=Favorit|…|actions=["Rectangle Split Two By Two", "Favorit entfernen"]
AK-05|vorher|role=AXButton|label=ZDF, Vollprogramm|value=|…|actions=["Rectangle Split Two By Two", "Favorit hinzufügen"]|kinder=0
AK-05|nach-aktion-favorit-hinzufuegen|…|value=Favorit|…|actions=["Rectangle Split Two By Two", "Favorit entfernen"]|isFavorite=true
AK-05|leerzustand-texte|["MIKA+PLAYER · FAVORITEN", "Favoriten", "Keine Favoriten", "Markiere Sender mit dem Stern, um sie hier zu sammeln."]
Angriff-7|nul|parser name=9 zeichen, tvg=13|gespeichert name="NullByte" tvg=Optional("tvg-NullByte") gruppe=Optional("Gruppe")|im speicher schlüssel="id:tvg-NullByte"|nach neustart name="NullByte" schlüssel="id:tvg-NullByte"
Angriff-7|favoriten vor/nach unverändertem aktualisieren=10/10|gleich=true|ZCHANNEL=10
BUILD|BUG-09|xtream|favoriten vorher=[…NullSender, Esc[31mRot, Tab\tSender] · nachher=[gleich]
BUILD|BUG-09|altbestand|dateiVorher="Alt\u{1B}[1mSender"|favoritenNachher=["Alt[1mSender@QA BUG-09 Alt"]
BUILD|BUG-03|erstesOeffnen|pfade=["/logos/a.png", "/logos/weiter.png"]|fremderHost=0|… user-agent: Mozilla/5.0 …|plattencache=false|arbeitsspeicher=true
BUILD|BUG-03|erneutesOeffnen|pfade=["/logos/weiter.png"]|fremderHost=0
AK-15|m3u|vorher=3 → nach-aktualisieren-unveraendert=3 · nutzer-entfernt-dubletten=3 → 3 · nur-ZDF-SD-markiert → ["ZDF SD"] · xtream 2 → 2
AK-17-randfall|meldung=Die Playlist konnte nicht gespeichert werden. …|tab danach=["ZDF HD, Deutschland"]|dieselben objekte=true|hasChanges=false
AK-28|nach-neustart|store 0, -wal 0, -shm 0|freelist_count=0
```

**6 · iOS** — `xcodebuild clean build -project MikaPlusPlayer.xcodeproj -scheme MikaPlusPlayer -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd-ios`
auf dem Commit-Stand (18:32) und nach den Nachbesserungen (19:43): je `** CLEAN SUCCEEDED **`, `** BUILD SUCCEEDED **`, einzige
Warnung wie bisher `appintentsmetadataprocessor … Metadata extraction skipped, no AppIntents.framework dependency found`. Nicht
bedient (keine Tipp- und VoiceOver-Automatisierung im Simulator).

**Aufräumen und Vorkommnisse**

- **Beendet:** Aktivierungshelfer, `caffeinate`, Wachhund, der hängende Test-Host von Lauf 2 (nach Sicherung des Stapels). Danach lief
  keine Instanz von `MikaPlusPlayer` und kein `xcodebuild`; die `xcodebuildmcp`- und fremden `caffeinate -i -t 300`-Prozesse gehören
  anderen Sitzungen und sind unberührt. Die App wurde nie regulär gestartet; Datenbank und Cache des Nutzers weder gelesen noch
  beschrieben; kein Simulator angelegt oder gestartet; alles ohne Ton.
- **Gelöscht:** jedes 8-MB-Abbild nach seinem Lauf (ausgehängt und gelöscht, `hdiutil info` ohne Eintrag); die Prüfsonde im Projekt.
  `build/dd-test` und `build/dd-ios` bleiben (erlaubt).
- **Nachweise:** Nach jedem Lauf wurden versionierte Dateien unter `features/*/qa/` zurückgenommen (bis zu 61 je Lauf, Nachweise der
  QA anderer Features); neue unversionierte Dateien dort entstanden nicht. Neu und gewollt: `features/B04-senderliste/qa/BUILD-R1-*`
  (Kontrastmessung und 18 Aufnahmen der Endfassung, Nacharbeit R-1).
- **Bildschirm:** Weil `caffeinate` nach zwei Stunden endete, schaltete sich der Bildschirm von 21:57 bis 21:58 ab – während Lauf 2
  schon hing, kein Test lief in dieser Zeit.
- **Commit:** keiner. Die Nachbesserungen, dieser Bericht, die Vermerke in `qa-report.md` und die offenen Fragen liegen im Arbeitsbaum.
