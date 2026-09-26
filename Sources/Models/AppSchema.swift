import Foundation
import SwiftData

/// Versioniertes Schema der Datenbank (B09 · BUG-13).
///
/// **Version 1** ist das Schema, das v1.0 und v1.1 ausgeliefert haben; die B01-Reparatur hat daran
/// nichts geändert (nur Kommentare an `Playlist`/`Channel`). SwiftData erkennt eine Datenbank aus v1.1
/// über die Entitäts-Hashes als Version 1 und öffnet sie ohne Umbau
/// (`B09PersistenzTests.testBUG13_DatenbankAusV11OeffnetUnveraendert`, Vorlage mit dem v1.1-Quelltext erzeugt).
///
/// **Bei jeder Modelländerung** (neues Feld, Umbenennung, neue Entität):
/// 1. Die heutigen Klassen als eingefrorene Kopie in `MikaPlusPlayerSchemaV1` verschieben
///    (`extension MikaPlusPlayerSchemaV1 { @Model final class Playlist { … } }`) und `models` darauf zeigen lassen.
/// 2. `MikaPlusPlayerSchemaV2` mit den geänderten Klassen anlegen, `AppSchema.current` darauf setzen.
/// 3. In `MikaPlusPlayerMigrationPlan` an `schemas` anhängen und eine `MigrationStage` (`.lightweight` oder
///    `.custom`) von V1 nach V2 ergänzen; die Vorlage `Tests/B09/Fixtures/v1.1-schema.store` muss weiter öffnen.
///
/// Fehlt die Stufe, öffnet die neue App die alte Datei nicht. `AppPersistence.openStore` legt sie dann
/// unverändert beiseite, statt abzustürzen – die Daten sind für den Nutzer aber zunächst weg.
enum MikaPlusPlayerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Playlist.self, Channel.self] }
}

/// Migrationsplan: alle ausgelieferten Schema-Versionen in Reihenfolge, je Übergang eine Stufe.
enum MikaPlusPlayerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MikaPlusPlayerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum AppSchema {
    /// Die Schema-Version, mit der diese App-Version ihre Datenbank öffnet.
    static var current: any VersionedSchema.Type { MikaPlusPlayerSchemaV1.self }

    static var schema: Schema { Schema(versionedSchema: current) }
}
