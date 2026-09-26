// b09_ed25519.swift — EdDSA-Gegenprobe für den Release-Ablauf (B09 · BUG-11).
//
// Prüft Sparkle-Signaturen allein mit dem ÖFFENTLICHEN Schlüssel aus Info.plist (CryptoKit,
// ohne Keychain, ohne Privatschlüssel). Signiert nichts.
//
//   xcrun swift scripts/b09_ed25519.swift archiv <SUPublicEDKey> <Datei> <sparkle:edSignature>
//   xcrun swift scripts/b09_ed25519.swift feed   <SUPublicEDKey> <appcast.xml>
//
// Exit 0 = Signatur gültig · 1 = ungültig · 2 = Eingabe fehlt/unlesbar (z. B. Feed ohne Signaturblock)
//
// Feed-Format wie Sparkle 2.9.3 (SPUExtractSignedFeed.m, common_cli/Signing.swift): Der Inhalt vor dem
// letzten "<!-- sparkle-signatures:\n" ist signiert; der Block nennt edSignature und length.
import CryptoKit
import Foundation

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count >= 4 else {
    fail(2, "Aufruf: b09_ed25519.swift archiv <pubkey> <datei> <signatur> | feed <pubkey> <appcast.xml>")
}
guard let publicKeyData = Data(base64Encoded: args[2]), publicKeyData.count == 32,
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
    fail(2, "SUPublicEDKey ist kein gültiger Ed25519-Schlüssel")
}
guard let data = FileManager.default.contents(atPath: args[3]) else {
    fail(2, "Datei nicht lesbar: \(args[3])")
}

switch args[1] {
case "archiv":
    guard args.count >= 5, let signature = Data(base64Encoded: args[4]) else {
        fail(2, "Signatur fehlt oder ist kein Base64")
    }
    guard publicKey.isValidSignature(signature, for: data) else {
        fail(1, "UNGÜLTIG: Signatur passt nicht zu \(args[3]) und SUPublicEDKey")
    }
    print("gültig: \((args[3] as NSString).lastPathComponent) (\(data.count) Byte)")

case "feed":
    let prefix = Data("<!-- sparkle-signatures:\n".utf8)
    guard let prefixRange = data.range(of: prefix, options: .backwards) else {
        fail(2, "Feed trägt keinen Signaturblock")
    }
    let content = data.subdata(in: data.startIndex..<prefixRange.lowerBound)
    guard let suffixRange = data.range(of: Data("-->".utf8), in: prefixRange.upperBound..<data.endIndex),
          let block = String(data: data.subdata(in: prefixRange.upperBound..<suffixRange.lowerBound), encoding: .utf8) else {
        fail(2, "Signaturblock unvollständig")
    }
    var signatureBase64: String?
    var length: Int?
    for line in block.split(separator: "\n") {
        if line.hasPrefix("edSignature:") {
            signatureBase64 = line.dropFirst("edSignature:".count).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("length:") {
            length = Int(line.dropFirst("length:".count).trimmingCharacters(in: .whitespaces))
        }
    }
    guard let signatureBase64, let signature = Data(base64Encoded: signatureBase64) else {
        fail(2, "Signaturblock ohne edSignature")
    }
    guard length == content.count else {
        fail(1, "UNGÜLTIG: length \(length.map(String.init) ?? "-") ≠ \(content.count) Byte Feed-Inhalt (nach dem Signieren verändert?)")
    }
    guard publicKey.isValidSignature(signature, for: content) else {
        fail(1, "UNGÜLTIG: Feed-Signatur passt nicht zu SUPublicEDKey (nach dem Signieren verändert?)")
    }
    print("gültig: Feed-Signatur (\(content.count) Byte)")

default:
    fail(2, "Unbekannter Modus \(args[1])")
}
