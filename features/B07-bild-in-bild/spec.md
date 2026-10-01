# B07 · Bild-in-Bild — Spezifikation

Status: `rekonstruiert` · Stand: 2026-09-15 · Rekonstruktion aus dem Code (sdd-erfassen)

> **Rekonstruiert, nicht geplant.** Beschrieben ist, was der Code auf `main` @ `c01f1cf` **tut**,
> nicht, was er tun sollte. Kriterien mit ⚠ beschreiben fragwürdiges Ist-Verhalten. Sie stehen
> bewusst als Kriterium hier, damit `sdd-qa` sie reproduziert. Wo sie als Fehler eingestuft sind,
> steht ein Verweis auf *Fehlbestand*.
>
> **Wie belegt.** Am 2026-09-15 **ausgeführt** in einer Kopie des Projekts im Scratchpad (eigene
> Bundle-ID `lu.daumedia.b07probe`, In-Memory-Datenbank, Sparkle-Feed abgeschaltet, eigene
> DerivedData). Die Streams waren ein lokal erzeugtes ffmpeg-Testbild über `127.0.0.1:18907`
> (HLS und eine `.ts`-Datei), kein Anbieter, keine Zugangsdaten. Drei Wege:
> 1. **macOS-XCTest** gegen die Engines (Start, Stopp, Start vor Spielbereitschaft, zwei Engines,
>    fehlerhafter Stream).
> 2. **macOS-App** mit einer kleinen Steuerung: Sie legt einen Sender an, öffnet den Player im
>    Tab-Stapel wie in der App und löst Bild-in-Bild **über dieselbe Aktion wie der Knopf** aus,
>    danach „Zurück" und „erneut öffnen" zeitgesteuert.
> 3. **iOS-Simulator** mit derselben Steuerung, App-Wechsel über `simctl launch` der
>    Einstellungen. Die iPhone-Simulatoren (iOS 26.5 und 27.0) melden **keine** PiP-Unterstützung;
>    das iOS-Verhalten ist deshalb auf dem **iPad-Pro-11-Simulator** (iOS 26.5) belegt.
>
> **Nicht bedient:** echte Klicks oder Tipps auf den Knopf, die Taste P, die Knöpfe im PiP-Fenster
> (Schließen, Pause, Zurück zur App), Bildschirmsperre, echte Geräte. Solche Kriterien tragen den
> Vermerk *(gelesen)*. Die iOS-Läufe liefen **stumm** (Stream ohne Tonspur, Player stummgeschaltet);
> Hintergrundwiedergabe ist über den Player-Status belegt, nicht über Hören.
>
> **Evidenz:** `qa-erfassung/sonde-protokoll.txt` (Protokolle aller Läufe), `qa-erfassung/sonde.patch`
> (Sonden-Code gegen `Sources/`), Bildschirmfotos `qa-erfassung/mac-01…04`, `ipad-05…09`,
> `iphone-10`. Die Kopie im Scratchpad ist gelöscht.

## Zweck

Wer einen Sender über die AVKit-Engine schaut, kann das Bild in das schwebende Bild-in-Bild-Fenster
des Systems legen und nebenher andere Fenster oder Apps benutzen. Auf iPhone und iPad wechselt ein
laufender Stream beim App-Wechsel von selbst in dieses Fenster.

## Abhängigkeiten

| Braucht | Status | Warum |
|---|---|---|
| B06 Wiedergabe | bestand | Player-Ansicht, Engine-Wahl nach Endung, Steuerungs-Chrome (Ein-/Ausblenden), Tastatursteuerung. B07 ist ein Knopf, eine Taste und eine Fähigkeit der AVKit-Engine darin |
| B01 Xtream-Codes-Login | rekonstruiert | legt das Standardformat MPEG-TS fest (B01 AK-02). Damit spielen Xtream-Sender standardmäßig über VLC, und dort gibt es kein Bild-in-Bild |

Berührt, ohne Abhängigkeit: B08 (Multiview nutzt dieselben Engines, bewusst ohne Bild-in-Bild),
B09 (Bild-in-Bild ist in keinem ausgelieferten Release), B10 (Website bewirbt Bild-in-Bild, dort
FB-02).

## User Stories

- **US-01** · Als Mac-Nutzer möchte ich einen laufenden Sender in ein schwebendes Fenster legen,
  damit ich weiterschauen kann, während ich in anderen Apps arbeite.
- **US-02** · Als iPhone- oder iPad-Nutzer möchte ich, dass der Sender beim Wechsel in eine andere
  App im kleinen Fenster weiterläuft, ohne dass ich vorher etwas antippen muss.
- **US-03** · Als Tastaturnutzer möchte ich Bild-in-Bild mit einer Taste ein- und ausschalten.

## Nicht im Scope

- Engine-Wahl nach Dateiendung, Play/Pause, Stumm, Lautstärke, Vollbild, HUD, Ein-/Ausblenden der
  Steuerung, Fehleransicht, die übrigen Tasten → **B06**. B07 übernimmt davon nur, *wann* der Knopf
  sichtbar sein kann.
- Hintergrundwiedergabe als solche (`UIBackgroundModes audio`) gehört zur Wiedergabe (B06). Sie
  steht hier im Datenschutzteil, weil die Engine die Audio-Session für Bild-in-Bild aktiviert.
- Mehrere Streams gleichzeitig → **B08**. Dort gibt es bewusst kein Bild-in-Bild (AK-12).
- Aussagen der Website zu Bild-in-Bild → **B10** (FB-02); fehlendes Release → **B09**.
- Bild-in-Bild für rohe MPEG-TS-Streams: VLCKit bietet kein System-PiP, der Code sieht es nicht vor
  (AK-09, FB-02).

## Akzeptanzkriterien

Jedes Kriterium ist ohne Codekenntnis prüfbar. Nötig sind ein HLS-Stream (`.m3u8`) und ein roher
MPEG-TS-Stream (`.ts`) auf einem lokalen Server, ein Mac und ein iPad (Gerät oder Simulator). Ein
iPhone-Simulator genügt nicht (AK-08).

### Knopf und Taste

- **AK-01** · Angenommen, ein HLS-Sender spielt, das Gerät unterstützt Bild-in-Bild (Mac, iPad), und
  die Steuerung ist eingeblendet, dann steht oben rechts links neben dem Vollbild-Knopf ein runder
  Knopf mit dem Symbol „Bild-in-Bild öffnen" (`pip.enter`, weiß auf halbtransparentem Schwarz). Auf
  macOS zeigt er beim Überfahren den Tooltip „Bild-in-Bild". VoiceOver liest ihn als **„Minimise
  Video"** vor, auf Englisch. *(iPad ausgeführt über den Bedienungshilfen-Baum; Tooltip gelesen;
  Sprache → OF-03)*
- **AK-02** · Angenommen, der Player lädt noch, zeigt die Fehleransicht oder hat die Steuerung
  ausgeblendet (nach 3,5 s ohne Bedienung), dann ist der Knopf nicht zu sehen. Ein Tipp bzw. Klick
  auf das Bild blendet die Steuerung und damit den Knopf wieder ein. *(gelesen)*
- **AK-03** · Angenommen, der Knopf ist sichtbar, wenn er betätigt wird, dann öffnet sich das
  Bild-in-Bild-Fenster des Systems und spielt weiter:
  - macOS: ein schwebendes Fenster über allen anderen Fenstern (Systemprozess „Bild-in-Bild",
    beobachtet 514 × 270 pt oben rechts auf dem Bildschirm), ohne Titel.
  - iPad: ein schwebendes Fenster über der App mit den Systemknöpfen Schließen, 10 s zurück,
    Pause, 10 s vor, Zurück zur App und einer Zeitleiste (bei einem VOD-Stream; bei einem
    Live-Stream nicht geprüft).
  An der Stelle des Videos zeigt die App eine schwarze Fläche mit einem Bild-in-Bild-Symbol und dem
  englischen Systemtext „This video is playing in picture in picture.". Der Knopf zeigt nun das
  Symbol „Bild-in-Bild schließen" (`pip.exit`). *(ausgeführt macOS und iPad, ausgelöst über dieselbe
  Aktion wie der Knopf, nicht per Klick; Bilder `mac-01`, `mac-02`, `ipad-07`)*
- **AK-04** · Angenommen, Bild-in-Bild ist aktiv und der Player noch geöffnet, wenn der Knopf erneut
  betätigt oder P gedrückt wird, dann schließt sich das schwebende Fenster, das Video erscheint
  wieder im Player, und die Wiedergabe läuft weiter. *(macOS an der Engine ausgeführt: Wiedergabe
  lief nach dem Schließen mit Rate 1,0 weiter; iPad gelesen)*
- **AK-05** · Angenommen, der Player hat den Tastaturfokus (macOS; iPad mit Hardware-Tastatur), wenn
  P gedrückt wird, klein oder groß, dann geschieht dasselbe wie beim Knopf (AK-03, AK-04). Zusätzlich
  blendet sich die Steuerung für 3,5 s ein. Es erscheint kein HUD, und macOS gibt keinen Warnton aus.
  Die Taste wirkt auch, wenn die Steuerung ausgeblendet ist. *(gelesen)*
- **AK-06** · Angenommen, ein HLS-Sender lädt noch, wenn P gedrückt wird, dann geschieht nichts:
  Kein Fenster erscheint, auch nicht, sobald der Stream wenig später spielt, und es gibt keine
  Meldung. *(ausgeführt macOS: 3 s später spielte der Stream, Bild-in-Bild blieb aus → OF-02)*
- **AK-07** · Angenommen, die Wiedergabe ist fehlgeschlagen (z. B. HTTP 404), wenn P gedrückt wird,
  dann geschieht nichts, und die Fehleransicht bleibt. *(ausgeführt macOS)*
- **AK-08** · Angenommen, das Gerät meldet keine Bild-in-Bild-Unterstützung, dann erscheint der
  Knopf nie, P bewirkt außer dem Einblenden der Steuerung nichts, und beim App-Wechsel startet
  nichts. *(ausgeführt auf den iPhone-Simulatoren iOS 26.5 und 27.0, die keine Unterstützung
  melden; Bild `iphone-10`. Ob echte iPhones Unterstützung melden, ist nicht geprüft)*

### MPEG-TS über VLC

- **AK-09** · Angenommen, die Adresse des Senders endet auf `.ts`, `.mpegts`, `.mts` oder `.m2ts`
  (das ist bei Xtream-Playlists im Standardformat immer der Fall), dann spielt der Sender über VLC,
  und es gilt:
  - Oben rechts steht nur der Vollbild-Knopf, kein Bild-in-Bild-Knopf.
  - P blendet nur die Steuerung ein, sonst geschieht nichts.
  - Beim App-Wechsel auf dem iPad startet kein Bild-in-Bild.
  - Die App erklärt nirgends, warum Bild-in-Bild fehlt.
  *(ausgeführt iPad: Bedienungshilfen-Baum, Bild `ipad-09`, App-Wechsel; Engine-Wahl zusätzlich
  am Mac ausgeführt; fehlender Hinweis gelesen → FB-02)*

### Automatischer Start (iOS und iPadOS)

- **AK-10** · Angenommen, ein HLS-Sender spielt im Player und Bild-in-Bild wurde in dieser Sitzung
  **nie** von Hand gestartet, wenn der Nutzer in eine andere App wechselt, dann öffnet sich das
  Bild-in-Bild-Fenster von selbst über der anderen App und spielt weiter. Eine Einstellung zum
  Abschalten gibt es nicht. Auf macOS gibt es keinen automatischen Start. *(iPad ausgeführt: Fenster
  etwa 2 s nach dem Wechsel zu den Einstellungen, Bild `ipad-05`; macOS gelesen; Abschaltbarkeit
  → OF-01)*
- **AK-11** · Angenommen, Bild-in-Bild wurde automatisch gestartet, wenn der Nutzer in die App
  zurückkehrt, dann bleibt das schwebende Fenster offen. Der Player zeigt den Platzhalter aus AK-03,
  bis der Nutzer Bild-in-Bild selbst beendet. *(ausgeführt iPad, Bild `ipad-06`)*
- **AK-12** · Angenommen, Streams laufen im Multiview-Fenster (macOS), dann gibt es dort keinen
  Bild-in-Bild-Knopf, keine Taste P und keinen automatischen Start. *(gelesen)*

### Verlassen des Players

- **AK-13** · Angenommen, Bild-in-Bild ist **nicht** aktiv, wenn der Player verlassen wird
  („Zurück" oder Tabwechsel), dann pausiert die Wiedergabe. *(gelesen; gehört zum Verhalten von
  B06, hier nur als Gegenstück zu AK-14 und AK-15)*
- **AK-14** ⚠ · Angenommen, Bild-in-Bild ist auf iPhone oder iPad aktiv, wenn der Nutzer im Player
  „Zurück" wählt, dann verschwindet das schwebende Fenster sofort und die Wiedergabe endet. Es gibt
  keinen Hinweis. Wird der Sender wieder geöffnet, beginnt die Wiedergabe neu im Player.
  *(ausgeführt iPad: Engine und Player sind etwa 10 ms nach dem Verlassen freigegeben, Bild
  `ipad-08`; als Fehler eingestuft → FB-03)*
- **AK-15** ⚠ · Angenommen, Bild-in-Bild ist auf dem Mac aktiv, wenn der Nutzer im Player „Zurück"
  wählt, dann gilt:
  - Das schwebende Fenster spielt weiter; beobachtet über 37 s. Die App zeigt die Liste und hat
    keinen Knopf und keine Taste mehr, um diese Wiedergabe zu steuern.
  - Ein Beenden aus der App heraus bleibt wirkungslos; der Aufruf wurde über die Sonde ausgelöst.
  - Öffnet der Nutzer danach einen Sender, laufen **zwei Streams gleichzeitig**: der neue im Player
    und der alte im schwebenden Fenster.
  - Einige Sekunden später (beobachtet 4,6 s) verschwindet das alte Fenster ohne Hinweis.
  *(ausgeführt in drei Läufen, Bilder `mac-03`, `mac-04`; Wirkung der Knöpfe im PiP-Fenster nicht
  bedient; als Fehler eingestuft → FB-03)*

### Zustand in der App

- **AK-16** ⚠ · Angenommen, Bild-in-Bild ist aktiv und die Wiedergabe wird im schwebenden Fenster
  pausiert, dann zeigt der Player-Knopf unten links weiterhin „Pause", tut also so, als liefe der
  Stream. Der erste Druck auf die Leertaste (bzw. auf den Knopf) setzt nicht fort, erst der zweite.
  *(Pause über den Player ausgelöst, wie es der Pause-Knopf des Fensters tut: der App-Zustand blieb
  „läuft"; Tastenfolge gelesen; als Fehler eingestuft → FB-04)*
- **AK-17** ⚠ · Angenommen, auf dem Mac sind zwei Player in zwei Hauptfenstern offen und der erste
  ist im Bild-in-Bild, wenn im zweiten Bild-in-Bild gestartet wird, dann schließt sich das Fenster
  des ersten, sein Stream **pausiert**, und sein Player zeigt weiter „läuft". *(an zwei Engines
  ausgeführt; zwei Hauptfenster nicht bedient; als Fehler eingestuft → FB-04)*
- **AK-18** · Angenommen, das System lehnt den Start von Bild-in-Bild ab, dann erscheint keine
  Meldung, und der Knopf zeigt weiter „Bild-in-Bild öffnen". *(gelesen; Ablehnung ließ sich nicht
  auslösen → OF-02)*

### Datenschutz und Missbrauchsschutz

Fragenkatalog `~/.claude/sdd/sicherheit.md`, Stufe B (voller Katalog). Jede Frage hat ein
Kriterium, ein „trifft nicht zu, weil …" oder einen Eintrag im *Fehlbestand*.

- **AK-19** · Angenommen, Bild-in-Bild ist aktiv, dann zeigen das schwebende Fenster und der
  Platzhalter im Player nur das Bild, ohne Sendernamen, ohne Stream-Adresse und damit ohne die darin
  enthaltenen Zugangsdaten (B01 AK-24). *(ausgeführt macOS und iPad, Bilder `mac-02`, `ipad-05`,
  `ipad-07`; keine Metadaten gesetzt: gelesen)*
- **AK-20** · Angenommen, Bild-in-Bild ist aktiv, dann liegt das Fenster über allen anderen Apps und
  erscheint in Bildschirmfotos des Systems. Mit dem automatischen Start (AK-10) geschieht das auf
  iPhone und iPad ohne Zutun, sobald der Nutzer die App wechselt, also auch beim Wechsel in eine App,
  die gerade den Bildschirm teilt oder aufnimmt. *(Bildschirmfotos ausgeführt: `screencapture` am
  Mac, Simulator-Bildschirmfoto über den Einstellungen; Bildschirmfreigabe und -aufnahme nicht
  ausgeführt → OF-01)*
- **AK-21** · Angenommen, ein HLS-Sender spielt auf iPhone oder iPad, wenn die App in den Hintergrund
  geht, dann läuft die Wiedergabe weiter, mit Bild-in-Bild sichtbar, ohne Bild-in-Bild unsichtbar.
  Die Verbindung zum Anbieter bleibt bestehen. Es gibt keine Zeitgrenze und kein automatisches
  Anhalten. *(ausgeführt, stumm: iPhone-Simulator ohne PiP, Player-Rate 1,0 während 7 s im
  Hintergrund; iPad mit PiP. Ton nicht gehört; echtes Gerät nicht geprüft)*
- **AK-22** · Angenommen, das iPhone oder iPad wird gesperrt, während ein Sender spielt, dann setzt
  die App selbst keine „Jetzt läuft"-Angaben: Einen Sendernamen auf dem Sperrbildschirm liefert die
  App nicht. Ob und wie das System das Bild-in-Bild-Fenster oder Steuerelemente bei gesperrtem
  Bildschirm zeigt, ist **nicht geprüft**. Dasselbe gilt für den gesperrten Mac. *(gelesen: kein
  `MediaPlayer`/`MPNowPlayingInfoCenter` im Code; Sperre im Simulator nicht auslösbar)*
- **AK-23** · Angenommen, Bild-in-Bild wird gestartet, beendet oder schlägt fehl, dann schreibt die
  App dazu nichts ins Systemprotokoll, weder Sender noch Adresse. *(gelesen: kein `print`, `Logger`,
  `os_log`, `NSLog` in `Sources/`; am Produktivbuild nicht ausgeführt. In der Sonde protokollierte
  das System selbst Netzverbindungen nur mit gehashtem Host und „url hash")*
- **AK-24** · Angenommen, Bild-in-Bild wurde benutzt, dann ist nichts davon gespeichert: kein
  Eintrag in der Datenbank, in den Einstellungen oder in Dateien. Nach einem Neustart ist
  Bild-in-Bild aus. *(gelesen)*

#### Katalog, Frage für Frage

| # | Katalogfrage | Antwort für B07 |
|---|---|---|
| 1.1 | Welche personenbezogenen Daten? | Keine neuen. Sichtbar wird, **was** der Nutzer schaut: im schwebenden Fenster über anderen Apps, in Bildschirmfotos und bei geteiltem Bildschirm (AK-20). Adresse und Zugangsdaten erscheinen nicht (AK-19). Gegenüber dem Anbieter bleibt die IP-Adresse im Hintergrund in Verbindung (AK-21) |
| 1.2 | Besondere Kategorien? | Trifft nicht zu, weil B07 nichts speichert oder überträgt. Ein sichtbar laufender Sender kann Rückschlüsse zulassen (Religion, Herkunft, Politik); das betrifft die Sichtbarkeit, → OF-01 |
| 1.3 | Wo gespeichert, wie lange? | Nirgends (AK-24). Das System hält den Zustand nur, solange das Fenster offen ist |
| 1.4 | Landen sie in Logs? | App-seitig nein (AK-23, nachzuweisen am Build) |
| 2.1 | Welche externen Dienste? | Keine neuen. Bild-in-Bild ist eine lokale Systemfunktion. Der Stream kommt weiter vom Anbieter (B06). Auf dem Mac bleibt nach „Zurück" eine Verbindung offen, beim erneuten Öffnen entsteht eine zweite (AK-15) → FB-03 |
| 2.2 | Was wird übertragen, was vorher entfernt? | Trifft nicht zu, weil B07 nichts an Dritte überträgt |
| 2.3 | Standort des Dienstes, AV-Vertrag? | Trifft nicht zu, weil kein Dienst von daumedia oder Dritten beteiligt ist |
| 2.4 | Training mit dem Payload? | Trifft nicht zu, weil kein KI-Dienst beteiligt ist |
| 3.1 | Wer darf sehen, ändern, löschen? | Sehen kann jeder, der auf den Bildschirm oder eine Bildschirmfreigabe schaut (AK-20). Bei gesperrtem Bildschirm nicht geprüft (AK-22). Steuern kann nur der lokale Nutzer, auf dem Mac nach „Zurück" nur noch über das Systemfenster (AK-15) |
| 3.2 | Erzwungen in DB oder Anwendung? | Trifft nicht zu, weil es keine Daten mit Zugriffsregeln gibt. Die Sichtbarkeit steuert das Betriebssystem |
| 3.3 | Fremde ID? | Trifft nicht zu, weil B07 keine per ID abrufbaren Ressourcen hat |
| 3.4 | Rollen? | Trifft nicht zu, weil die App keine Konten und keine Rollen hat |
| 4.1 | Rate Limit auf Anmeldung u. ä. | Trifft nicht zu, weil B07 keine Anmeldung und keinen Endpunkt hat |
| 4.2 | Rate Limit für Kostenpflichtiges | Trifft für Dienste des Betreibers nicht zu. Beim Anbieter zählen gleichzeitige Verbindungen: Die zweite parallele Verbindung aus AK-15 kann das Limit des Abos erreichen (viele Anbieter erlauben eine) → FB-03 |
| 4.3 | Kosten je Aufruf | Keine für den Betreiber. Für den Nutzer Datenvolumen: Wiedergabe läuft im Hintergrund ohne Zeitgrenze weiter (AK-21) und auf dem Mac nach „Zurück" unsichtbar gesteuert weiter (AK-15) |
| 4.4 | Uploads: Größe, Typ, Inhalt | Trifft nicht zu, weil B07 keine Eingaben oder Dateien annimmt. Unvertraute Medien verarbeitet AVKit bzw. VLC in B06 |
| 4.5 | Wo greift das Limit? | Nirgends; siehe 4.2, 4.3 |
| 5.1 | Konto selbst löschen? | Trifft nicht zu, weil B07 kein Konto und keine Daten hat |
| 5.2 | Was wird dabei gelöscht? | Trifft nicht zu, siehe 5.1 und AK-24 |
| 5.3 | Was bleibt, und warum? | Trifft nicht zu, siehe AK-24 |
| 5.4 | E-Mail-Adresse wieder frei? | Trifft nicht zu, weil die App keine Registrierung hat |
| 5.5 | Datenexport? | Trifft nicht zu, weil B07 keine Daten erzeugt |
| 6.1 | Welche Schlüssel braucht das Feature? | Keine. Bild-in-Bild braucht weder auf iOS noch auf macOS ein Entitlement; iOS nutzt nur `UIBackgroundModes audio` (`Info.plist:62-66`) |
| 6.2 | Welche dürfen zum Client? | Trifft nicht zu, weil es keine Schlüssel und keinen Server gibt |
| 6.3 | Steht Echtes im Repository? | Trifft nicht zu, weil B07 keine Geheimnisse berührt; der PiP-Commit `54550b2` enthält keine Adressen oder Zugangsdaten |
| 6.4 | Vorlagen `.env.example` / `Secrets.example.xcconfig` | Trifft nicht zu, weil B07 keine Build-Geheimnisse braucht |

## Edge Cases

Ist-Verhalten. „(ausgeführt)" heißt mit der Sonde belegt, „(gelesen)" heißt aus dem Code abgeleitet.

- **EC-01** · Senderadresse ohne Dateiendung (`…/live/u/p/101`) → Wahl der AVKit-Engine, der Knopf
  kann erscheinen. Ist der Stream in Wahrheit rohes MPEG-TS, schlägt die Wiedergabe fehl, und der
  Knopf erscheint nicht. *(Engine-Wahl ausgeführt, Wiedergabe gelesen)*
- **EC-02** · Adresse auf `.m3u` → AVKit-Engine, Bild-in-Bild wie bei `.m3u8`. *(Engine-Wahl ausgeführt)*
- **EC-03** · Tabwechsel (Playlists ↔ Favoriten) bei aktivem Bild-in-Bild → Der Player verschwindet
  ohne Pause. Der Stapel des Tabs bleibt erhalten, also vermutlich auch Engine und schwebendes
  Fenster; bei der Rückkehr wird `play()` aufgerufen. *(gelesen, nicht bedient)*
- **EC-04** · Stream bricht während Bild-in-Bild ab → Der Player geht in die Fehleransicht, der Knopf
  verschwindet (AK-02). Das schwebende Fenster bleibt offen; P beendet es weiterhin. *(gelesen)*
- **EC-05** · „Erneut versuchen" bei aktivem Bild-in-Bild → Derselbe Player lädt den Stream neu; das
  Fenster bleibt an denselben Player gebunden. *(gelesen)*
- **EC-06** · App-Wechsel, während der Stream pausiert ist oder noch lädt → Das System startet
  Bild-in-Bild nur bei laufender Wiedergabe; die App tut darüber hinaus nichts. *(gelesen,
  Systemverhalten nicht geprüft)*
- **EC-07** · Schließen-Knopf im schwebenden Fenster → Das System beendet Bild-in-Bild, die App
  merkt es (Knopf wieder „öffnen"). Ob das System dabei pausiert, ist nicht geprüft; wenn ja, gilt
  AK-16. *(gelesen, nicht bedient)*
- **EC-08** · „Zurück zur App" im schwebenden Fenster bei noch geöffnetem Player → Das System holt
  das Bild in den Player zurück; die App hat dafür keinen eigenen Wiederherstellungsschritt. Nach
  „Zurück" (AK-14, AK-15) gibt es keinen Player, in den das Bild zurück kann. *(gelesen, nicht
  bedient → FB-03)*
- **EC-09** · Bild-in-Bild im Vollbild des Players → Der Platzhalter füllt die Vollbildfläche; am
  Vollbild ändert sich nichts. *(gelesen)*
- **EC-10** · Zwei Player auf dem Mac, beide im Bild-in-Bild gewünscht → Es gibt immer nur ein
  schwebendes Fenster; der zuletzt gestartete gewinnt (AK-17). *(an zwei Engines ausgeführt)*
- **EC-11** · Multiview-Kacheln mit HLS-Streams → Jede Kachel legt intern einen
  Bild-in-Bild-Controller an, der nie benutzt wird. Sichtbar ist davon nichts. *(gelesen)*
- **EC-12** · iPhone im Hochformat, Bild-in-Bild automatisch gestartet → Verhalten auf echten
  iPhones nicht geprüft (AK-08). *(nicht ausgeführt)*

## Offene Fragen

Alle vom 2026-09-15. Entscheidung durch den Nutzer (Michael Ferreira), vor der Reparaturrunde nach
der QA von B07.

- **OF-01** · Soll der automatische Start beim App-Wechsel (AK-10) abschaltbar sein oder erst nach
  einmaligem Einverständnis greifen? Heute legt jeder App-Wechsel den laufenden Sender sichtbar über
  andere Apps, auch über eine laufende Bildschirmfreigabe (AK-20). Die Website bewirbt den
  automatischen Start als Funktion.
- **OF-02** · Soll ein nicht möglicher oder abgelehnter Start (AK-06, AK-18) eine Rückmeldung geben
  oder sich den Wunsch merken, bis der Stream spielt?
- **OF-03** · VoiceOver-Beschriftung „Minimise Video" (AK-01) und Platzhaltertext „This video is
  playing in picture in picture." (AK-03) sind englisch, die App sonst deutsch. Eigene deutsche
  Beschriftung gewünscht? (analog B01 OF-06)
- **OF-04** · Welches Verhalten ist beim Verlassen des Players mit aktivem Bild-in-Bild gewollt:
  weiterlaufen mit echter Steuerbarkeit (wie heute halb auf dem Mac) oder sauber beenden (wie heute
  abrupt auf iOS)? Die Reparatur von FB-03 braucht diese Entscheidung.

Aus der Reparatur BUG-01 bis BUG-05 (sdd-build, 2026-09-27), ohne Rückfrage offen gelassen:

- **OF-05** · „Zurück zur App" im schwebenden Fenster, nachdem der Player verlassen wurde: Die Reparatur
  beendet die Wiedergabe (Fenster zu, Verbindung zu), statt den Player wieder zu öffnen. Wiederherstellen
  hieße, den Sender programmatisch in den richtigen Tab-Stapel zu legen; die Navigation hat dafür keine
  gebundenen Pfade (`ContentView`, `ChannelListView`, `FavoritesView`). Gewünscht? Hängt an OF-04.
- **OF-06** · Hinweis „Bild-in-Bild gibt es nur mit HLS" im Player: Er erscheint nur auf die Taste P. Wer
  am iPad ohne Tastatur einen MPEG-TS-Sender schaut, sieht ihn nie; einen Knopf gibt es bei VLC nach AK-09
  nicht. Soll ein (abgeschwächter) Knopf mit dieser Erklärung erscheinen?
- **OF-07** · Verwaiste Bild-in-Bild-Wiedergabe und Multiview (macOS): Nur ein startender oder fortgesetzter
  Einzel-Player beendet sie. Eine neue Multiview-Kachel lässt sie weiterlaufen – dann laufen Kachel(n) und
  schwebendes Fenster parallel. Soll auch Multiview sie beenden?
- **OF-08** · Playlist löschen, während ihr Sender nach „Zurück" im schwebenden Fenster läuft: Die
  übernommene Wiedergabe kennt ihre Playlist nicht und läuft weiter, bis Bild-in-Bild endet (gelesen:
  `PlaylistEvents.willDelete` beobachten nur `PlayerView`, `ChannelListView` und `MultiviewSession`; Bezug
  B03 BUG-05, BF-56). Soll das Löschen sie beenden?
- **OF-09** · Tabwechsel mit aktivem Bild-in-Bild (EC-03), dann im anderen Tab einen Sender öffnen: Der erste
  Player liegt weiter in seinem Stapel und gilt nicht als verlassen; sein schwebendes Fenster läuft neben dem neuen
  Sender weiter (gelesen: `stopAll()` beendet nur übernommene Wiedergaben). Soll auch das enden?

## Fehlbestand

Nicht vorhanden oder als Fehler eingestuft, aus dem Code belegt. Kein Kriterium: `sdd-qa` prüft
nichts davon als bestanden, sondern nimmt es als Suchliste.

- **FB-01 · Bild-in-Bild ist in keinem ausgelieferten Release, die Website bewirbt es.**
  Fundstelle: eingeführt mit `54550b2` am 2026-07-15. Das einzige Release `v1.1` stammt vom
  2026-06-23 und enthält den Commit nicht (`git merge-base --is-ancestor 54550b2 v1.1` → nein).
  `git show v1.1:Sources/Views/PlayerView.swift` hat keinen Fall `"p"`. `appcast.xml` führt nur 1.1,
  `MARKETING_VERSION` steht weiter auf 1.1. Beworben wird es trotzdem: `web/content/features.ts:31-33`
  („Picture in Picture … On iPhone and iPad it starts on its own"), `:38` und
  `web/app/support/page.tsx:18` („P · Picture in Picture"). iOS wird gar nicht verteilt.
  README und CLAUDE.md erwähnen Bild-in-Bild nicht.
  Folge: Wer die App nach der Website lädt, findet weder Knopf noch Taste. Die iOS-Zusage ist für
  niemanden erreichbar. Deckungsgleich mit B10 FB-02.
- **FB-02 · Für das Standardformat der Xtream-Anmeldung nicht verfügbar, ohne Hinweis.**
  Fundstelle: `PlaybackEngine.swift:85-94` (No-Op-Standard für alle Engines außer AVKit),
  `PlaybackEngineFactory` `PlaybackEngine.swift:101-104` (`.ts` → VLC), Standardformat MPEG-TS in
  `ImportPlaylistView.swift:31`. Der Knopf wird nur ausgeblendet (`PlayerView.swift:114`); P ist still
  wirkungslos (`PlayerView.swift:312-313`).
  Folge: Für die Hauptzielgruppe (Xtream-Abos, B01) fehlt die Funktion im Normalfall. Die Website
  nennt keine Einschränkung, und die App erklärt das Fehlen nicht (AK-09). Die Beschränkung selbst
  ist im Commit als bewusst beschrieben („PiP nur für AVKit-Streams … nicht für rohe .ts"); Befund
  ist die Zusage ohne Einschränkung.
- **FB-03 · Die Lebensdauer von Bild-in-Bild hängt an der Player-Ansicht; Verlassen des Players
  führt je Plattform zu Abbruch oder zu verwaister Wiedergabe.**
  Fundstelle: Die Engine lebt nur als `@State` in `PlayerView.swift:17`. Die Schutzabfrage in
  `onDisappear` (`PlayerView.swift:83-87`) verhindert nur die Pause, nicht das Freigeben der Ansicht.
  Der Delegate hält die Engine schwach (`AVKitPlaybackEngine.swift:154`). Es gibt keinen
  `restoreUserInterfaceForPictureInPictureStop`-Delegate (`AVKitPlaybackEngine.swift:153-172`) und
  keinen Ort außerhalb der Ansicht, der eine laufende PiP-Wiedergabe kennt. Der Code-Kommentar sagt:
  „Bei aktivem PiP NICHT pausieren – sonst würgt der Ansichtswechsel … die schwebende Wiedergabe ab";
  der Commit spricht vom „onDisappear-Guard, damit PiP nicht abgewürgt wird".
  Folge:
  - iOS und iPadOS: „Zurück" beendet Bild-in-Bild sofort und ohne Rückmeldung (AK-14), entgegen
    der Absicht des Kommentars.
  - macOS: Nach „Zurück" spielt ein Stream weiter, den die App nicht mehr steuern kann (AK-15).
  - Öffnet der Nutzer dann einen Sender, bestehen zwei Verbindungen zum Anbieter. Das kann das
    Verbindungslimit des Abos reißen oder den neuen Stream scheitern lassen. Einige Sekunden später
    verschwindet das alte Fenster kommentarlos.
  - Das Verhalten ist zwischen den Plattformen gegensätzlich. Welches gewollt ist → OF-04.
- **FB-04 · Der Wiedergabezustand der App folgt dem Player nicht, sobald das System eingreift.**
  Fundstelle: `isPaused` wird nur in `play()`/`pause()` der App gesetzt
  (`AVKitPlaybackEngine.swift:13, 45-47`). Rate und `timeControlStatus` des `AVPlayer` werden nicht
  beobachtet. Mit Bild-in-Bild kommen zwei Stellen hinzu, die den Player ohne die App anhalten:
  der Pause-Knopf des schwebenden Fensters und der Start eines zweiten Bild-in-Bild.
  Folge: Der Player zeigt „läuft", obwohl er steht, und der erste Tastendruck zum Fortsetzen
  verpufft (AK-16, AK-17). Funktionsfehler, keine Sicherheitslücke; die Absicht (Knopf zeigt den
  Zustand) ist eindeutig.

## Decision Log

Alle Einträge: **ohne Rückfrage entschieden (Zielmodus 2026-09-15) — zur Bestätigung durch den
Nutzer.**

| # | Frage | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Bild-in-Bild nur für AVKit, nicht für `.ts` | reguläres Kriterium AK-09 **und** FB-02 | Beschränkung im Commit und im Protokollkommentar als gewollt beschrieben; die Website verspricht sie aber ohne Einschränkung → Zielmodus-Regel „Website verspricht, Code tut es nicht" |
| 2 | In keinem Release, Website bewirbt es | FB-01 | Zielmodus-Regel „Website verspricht, Code tut es nicht"; mit B10 FB-02 abgeglichen, selbst nachgeprüft |
| 3 | Automatischer Start beim App-Wechsel ohne vorherige Nutzeraktion | reguläres Kriterium AK-10, Abschaltbarkeit als OF-01 | im Code-Kommentar und auf der Website als gewollt beschrieben; kein Punkt aus `sicherheit.md` verletzt. Die Sichtbarkeit bei Bildschirmfreigabe ist eine Abwägung, die der Nutzer treffen muss |
| 4 | iOS: „Zurück" beendet Bild-in-Bild abrupt | ⚠ AK-14 + FB-03, als Fehler eingestuft | Kommentar und Commit sagen ausdrücklich, dass ein Ansichtswechsel die schwebende Wiedergabe nicht abwürgen soll; der Code hält das nicht ein |
| 5 | macOS: verwaiste, nicht steuerbare Wiedergabe nach „Zurück", zweite Verbindung beim erneuten Öffnen | ⚠ AK-15 + FB-03, als Fehler eingestuft | keine Steuerbarkeit mehr aus der App; doppelte Verbindungen treffen das Anbieterlimit (`sicherheit.md` Abschnitt 4, Kosten/Missbrauch) |
| 6 | Zielverhalten beim Verlassen | OF-04 | beide Varianten sind vertretbar, die Absicht zwischen „weiterlaufen" und „beenden" ist aus dem Code nicht eindeutig ableitbar |
| 7 | App-Zustand nach Pause im PiP-Fenster bzw. nach zweitem PiP-Start | ⚠ AK-16, AK-17 + FB-04, als Fehler eingestuft | nicht sicherheitsrelevant, aber die Absicht (Knopf spiegelt den Zustand) ist eindeutig; eine offene Frage wäre Zurechtrücken durch Unterlassen |
| 8 | Start während des Ladens tut nichts, auch später nicht | reguläres Kriterium AK-06, Rückmeldung als OF-02 | Protokollkommentar beschreibt es als gewollt („No-Op, wenn … nicht spielbereit"); ob der Nutzer eine Rückmeldung bekommen soll, ist nicht ableitbar |
| 9 | `failedToStart` ohne Meldung | reguläres Kriterium AK-18 (gelesen), OF-02 | nicht auslösbar, nicht sicherheitsrelevant, Absicht nicht ableitbar |
| 10 | Englische VoiceOver-Beschriftung und Platzhaltertext | AK-01/AK-03 + OF-03 | nicht sicherheitsrelevant; Systemtext, weil das Bundle nur `en` lokalisiert, Absicht nicht ableitbar |
| 11 | Hintergrundwiedergabe ohne Zeitgrenze | reguläres Kriterium AK-21 | `Info.plist:62` kommentiert „Audio-Wiedergabe im Hintergrund / bei gesperrtem Bildschirm (iOS)" als gewollt; kein Punkt aus `sicherheit.md` |
| 12 | Sperrbildschirm | AK-22 als „nicht geprüft" markiert, kein Fehlbestand | im Simulator nicht auslösbar; die App liefert nachweislich keine Metadaten, das Systemverhalten bleibt für die QA am Gerät |
| 13 | Kein Bild-in-Bild im Multiview | reguläres Kriterium AK-12 | Kommentar `PlaybackEngine.swift:77-79` beschreibt es als bewusst |
| 14 | iPhone-Simulator meldet keine Unterstützung | AK-08 als Kriterium für „Gerät ohne Unterstützung"; iOS-Nachweis am iPad-Simulator | Plattformgrenze des Simulators, kein Verhalten der App; echtes iPhone bleibt für die QA (EC-12) |
| 15 | Fehlende Tests für das eigentliche Bild-in-Bild-Verhalten | kein Fehlbestand, Hinweis in `design.md` | Testabdeckung ist kein beobachtbares Verhalten; die zwei vorhandenen Tests prüfen nur den Ruhezustand |
