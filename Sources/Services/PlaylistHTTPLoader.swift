import Foundation

/// Gemeinsamer HTTP-Zugriff aller Importwege: `player_api.php` (B01) und M3U-Adressen (B02, B03).
///
/// - Eigene `ephemeral`-Session **ohne** `URLCache` und ohne Zugangsdatenspeicher: Anfragen mit Zugangsdaten und
///   die Antworten landen weder im HTTP-Plattencache noch im gemeinsamen `URLCredentialStorage`
///   (B01 · BUG-03, B02 · BUG-02, B03 · BUG-06). Cookies leben nur im Arbeitsspeicher dieser Session
///   (B02 AK-36) und werden beim Löschen einer Playlist für deren Host entfernt.
/// - Weiterleitungen je Anfrage: `.sameOrigin` (Xtream: nur dasselbe Panel, B01 · BUG-10) oder `.follow`
///   (M3U: wie bisher auch zu anderen Hosts, B02 AK-11; eine Basic-Auth-Antwort geht nie an ein anderes Ziel).
/// - Obergrenze für die Antwortgröße, eine gemeinsame Frist und optional ein Mindestdurchsatz, sobald die Antwort
///   begonnen hat (B01 · BUG-08, B02 · BUG-03).
final class PlaylistHTTPLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = PlaylistHTTPLoader()

    enum LoadError: Error, Equatable {
        case tooLarge
        case deadlineExceeded
        case redirectBlocked
        /// Die Antwort kommt nach der Anlaufzeit langsamer als der Mindestdurchsatz.
        case tooSlow
    }

    enum RedirectPolicy: Sendable {
        /// nur gleiches Schema, gleicher Host, gleicher Port
        case sameOrigin
        /// jede Weiterleitung, die `URLSession` selbst zulässt
        case follow
    }

    /// Mindestdurchsatz ab einer Anlaufzeit nach Beginn der Antwort.
    struct Throughput: Sendable, Equatable {
        var bytesPerSecond: Int
        var grace: TimeInterval
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(_ url: URL?) {
            guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
            self.scheme = scheme
            self.host = host
            self.port = url.port ?? (scheme == "https" ? 443 : 80)
        }
    }

    private final class State {
        /// `nil`, wenn die Adresse keinen Host hat; die Anfrage scheitert dann in `URLSession` selbst.
        let origin: Origin?
        let maxBytes: Int
        let redirects: RedirectPolicy
        let throughput: Throughput?
        var data = Data()
        var failure: LoadError?
        var result: Result<(Data, URLResponse), Error>?
        var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        /// Aufgabe wurde abgebrochen, bevor die Anfrage gestartet war.
        var cancelled = false
        /// `URLSessionTask.resume()` wurde aufgerufen.
        var started = false
        /// Zeitpunkt der ersten Antwort (Kopfzeilen) – Beginn der Durchsatzmessung.
        var responseStarted: Date?

        init(origin: Origin?, maxBytes: Int, redirects: RedirectPolicy, throughput: Throughput?) {
            self.origin = origin
            self.maxBytes = maxBytes
            self.redirects = redirects
            self.throughput = throughput
        }
    }

    private let lock = NSLock()
    private var states: [Int: State] = [:]
    private var session: URLSession!

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Lädt `request` vollständig. Wirft `LoadError`, `URLError` oder `CancellationError`.
    func data(for request: URLRequest, maxBytes: Int, deadline: Date, redirects: RedirectPolicy = .sameOrigin,
              throughput: Throughput? = nil) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard deadline.timeIntervalSinceNow > 0 else { throw LoadError.deadlineExceeded }

        let task = session.dataTask(with: request)
        let state = State(origin: Origin(request.url), maxBytes: maxBytes, redirects: redirects, throughput: throughput)
        lock.withLock { states[task.taskIdentifier] = state }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Start und Abbruch laufen unter derselben Sperre: Ein Abbruch vor dem Start löst die
                // Continuation selbst auf, statt einen nie gestarteten Task abzubrechen.
                let startedTask = lock.withLock { () -> Bool in
                    if state.cancelled {
                        states.removeValue(forKey: task.taskIdentifier)
                        return false
                    }
                    state.continuation = continuation
                    state.started = true
                    task.resume()
                    return true
                }
                guard startedTask else {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let remaining = max(0, deadline.timeIntervalSinceNow)
                DispatchQueue.global().asyncAfter(deadline: .now() + remaining) { [weak self, weak task] in
                    guard let self, let task else { return }
                    self.fail(task, with: .deadlineExceeded)
                }
            }
        } onCancel: {
            let started = lock.withLock { () -> Bool in
                state.cancelled = true
                return state.started
            }
            if started { task.cancel() }
        }
    }

    // MARK: - Cookies (nur im Arbeitsspeicher dieser Session)

    /// Entfernt die Cookies eines Hosts, z. B. beim Löschen einer Playlist.
    func removeCookies(forHost host: String) {
        guard let storage = session.configuration.httpCookieStorage else { return }
        let lower = host.lowercased()
        for cookie in storage.cookies ?? [] {
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if domain == lower || lower.hasSuffix("." + domain) {
                storage.deleteCookie(cookie)
            }
        }
    }

    /// Entfernt Cookies nach Namen (Tests räumen damit nur ihre eigenen Cookies auf).
    func removeCookies(named matches: (String) -> Bool) {
        guard let storage = session.configuration.httpCookieStorage else { return }
        for cookie in storage.cookies ?? [] where matches(cookie.name) { storage.deleteCookie(cookie) }
    }

    /// Cookies dieser Session, nur lesend (Tests).
    var cookies: [HTTPCookie] { session.configuration.httpCookieStorage?.cookies ?? [] }

    /// Entfernt alle Cookies dieser Session („Alle Daten entfernen").
    func removeAllCookies() {
        guard let storage = session.configuration.httpCookieStorage else { return }
        for cookie in storage.cookies ?? [] { storage.deleteCookie(cookie) }
    }

    private func fail(_ task: URLSessionTask, with error: LoadError) {
        let active = lock.withLock { () -> Bool in
            guard let state = states[task.taskIdentifier], state.result == nil else { return false }
            if state.failure == nil { state.failure = error }
            return true
        }
        if active { task.cancel() }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let limit = lock.withLock { () -> Int in
            guard let state = states[dataTask.taskIdentifier] else { return Int.max }
            state.responseStarted = Date()
            return state.maxBytes
        }
        if response.expectedContentLength > Int64(limit) {
            fail(dataTask, with: .tooLarge)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let verdict = lock.withLock { () -> LoadError? in
            guard let state = states[dataTask.taskIdentifier], state.failure == nil else { return nil }
            state.data.append(data)
            if state.data.count > state.maxBytes {
                state.data = Data()
                return .tooLarge
            }
            if let rule = state.throughput, let start = state.responseStarted {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= rule.grace, Double(state.data.count) / elapsed < Double(rule.bytesPerSecond) {
                    state.data = Data()
                    return .tooSlow
                }
            }
            return nil
        }
        if let verdict { fail(dataTask, with: verdict) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let (origin, policy) = lock.withLock { (states[task.taskIdentifier]?.origin, states[task.taskIdentifier]?.redirects) }
        switch policy ?? .sameOrigin {
        case .follow:
            completionHandler(request)
        case .sameOrigin:
            if let origin, let target = Origin(request.url), target == origin {
                completionHandler(request)
            } else {
                fail(task, with: .redirectBlocked)
                completionHandler(nil)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let delivery = lock.withLock { () -> (CheckedContinuation<(Data, URLResponse), Error>, Result<(Data, URLResponse), Error>)? in
            guard let state = states[task.taskIdentifier] else { return nil }
            let result: Result<(Data, URLResponse), Error>
            if let failure = state.failure {
                result = .failure(failure)
            } else if let error {
                result = .failure(error)
            } else if let response = task.response {
                result = .success((state.data, response))
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            state.result = result
            states.removeValue(forKey: task.taskIdentifier)
            guard let continuation = state.continuation else { return nil }
            return (continuation, result)
        }
        if let (continuation, result) = delivery {
            continuation.resume(with: result)
        }
    }
}

/// Früherer Name aus B01; `XtreamClient` und die B01-Tests sprechen den Loader so an.
typealias XtreamHTTPLoader = PlaylistHTTPLoader
