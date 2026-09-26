import Foundation

/// HTTP-Zugriff auf `player_api.php` (B01).
///
/// - Eigene `ephemeral`-Session **ohne** `URLCache`: Anfragen mit Zugangsdaten und die Antworten
///   des Panels landen nicht im HTTP-Plattencache (BUG-03).
/// - Weiterleitungen nur innerhalb desselben Panels (Schema, Host, Port); alles andere wird
///   abgebrochen, bevor die Zugangsdaten das Ziel erreichen (BUG-10).
/// - Obergrenze für die Antwortgröße und eine gemeinsame Frist für alle Anfragen eines Imports (BUG-08).
final class XtreamHTTPLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = XtreamHTTPLoader()

    enum LoadError: Error, Equatable {
        case tooLarge
        case deadlineExceeded
        case redirectBlocked
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
        var data = Data()
        var failure: LoadError?
        var result: Result<(Data, URLResponse), Error>?
        var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        /// Aufgabe wurde abgebrochen, bevor die Anfrage gestartet war.
        var cancelled = false
        /// `URLSessionTask.resume()` wurde aufgerufen.
        var started = false

        init(origin: Origin?, maxBytes: Int) {
            self.origin = origin
            self.maxBytes = maxBytes
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
    func data(for request: URLRequest, maxBytes: Int, deadline: Date) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard deadline.timeIntervalSinceNow > 0 else { throw LoadError.deadlineExceeded }

        let task = session.dataTask(with: request)
        let state = State(origin: Origin(request.url), maxBytes: maxBytes)
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
        let limit = lock.withLock { states[dataTask.taskIdentifier]?.maxBytes } ?? Int.max
        if response.expectedContentLength > Int64(limit) {
            fail(dataTask, with: .tooLarge)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let exceeded = lock.withLock { () -> Bool in
            guard let state = states[dataTask.taskIdentifier], state.failure == nil else { return false }
            state.data.append(data)
            if state.data.count > state.maxBytes {
                state.data = Data()
                return true
            }
            return false
        }
        if exceeded { fail(dataTask, with: .tooLarge) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let origin = lock.withLock { states[task.taskIdentifier]?.origin }
        if let origin, let target = Origin(request.url), target == origin {
            completionHandler(request)
        } else {
            fail(task, with: .redirectBlocked)
            completionHandler(nil)
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
