import XCTest
@testable import MikaPlusPlayer

final class XtreamCodesTests: XCTestCase {

    /// Host ohne Schema -> http:// wird erzwungen, get.php + Query korrekt.
    func testBuildsURLFromBareHost() {
        let creds = XtreamCredentials(host: "example.com", username: "demo", password: "secret")
        let url = creds.playlistURL(output: .hls)
        XCTAssertEqual(
            url?.absoluteString,
            "http://example.com/get.php?username=demo&password=secret&type=m3u_plus&output=hls"
        )
    }

    /// Host mit Schema, Port und Trailing-Slash wird normalisiert.
    func testNormalizesSchemePortAndSlash() {
        let creds = XtreamCredentials(host: "http://example.com:80/", username: "u", password: "p")
        let url = creds.playlistURL(output: .mpegts)
        XCTAssertEqual(
            url?.absoluteString,
            "http://example.com:80/get.php?username=u&password=p&type=m3u_plus&output=mpegts"
        )
    }

    /// Ein ausdrücklich eingegebenes https bleibt erhalten (B01 · BUG-02; vorher: Herabstufen auf http).
    func testKeepsHTTPS() {
        let creds = XtreamCredentials(host: "https://example.com", username: "u", password: "p")
        XCTAssertEqual(creds.playlistURL(output: .hls)?.scheme, "https")
    }

    /// Leerer Host -> nil; Vollständigkeitsprüfung.
    func testIncompleteCredentials() {
        XCTAssertNil(XtreamCredentials(host: "", username: "u", password: "p").playlistURL(output: .hls))
        XCTAssertFalse(XtreamCredentials(host: "h", username: " ", password: "p").isComplete)
        XCTAssertTrue(XtreamCredentials(host: "h", username: "u", password: "p").isComplete)
    }
}
