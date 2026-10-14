//
//  NetworkLogger.swift
//  Alfy
//
//  Created by albert vila on 30/9/26.
//

import Foundation
import os

/// Logs every request of the network module to the system log (subsystem `Alfy`, category `Network`).
/// Set `isEnabled = false` to silence all of it.
///
/// Every line of one request shares a short id (`[NETWORK #a3f9]`) so concurrent requests can be told apart.
/// Levels: `.default` for sources and summaries (shown and saved without extra settings), `.debug` for headers,
/// `.error` for failures (offline, 4xx/5xx, stale after error). Avoid `.info`: Console hides it and the system does not save it.
public enum NetworkLogger {
    public static var isEnabled: Bool = true

    /// Id stamped on every line written while a request is being handled; nil outside a request.
    @TaskLocal static var requestID: String?

    /// Where a response came from.
    enum Source {
        case internet
        case cache
        /// Cache served after a network failure or while offline.
        case staleCache

        var message: String {
            switch self {
            case .internet: return "data from internet"
            case .cache: return "data from cache"
            case .staleCache: return "data from cache (stale)"
            }
        }
    }

    private static let logger = Logger(subsystem: "Alfy", category: "Network")

    /// Final destination of each line; replaced in tests to capture output.
    static var output: @Sendable (OSLogType, String) -> Void = { level, message in
        logger.log(level: level, "\(message, privacy: .public)")
    }

    /// 4 hex characters, e.g. `a3f9`.
    static func makeRequestID() -> String {
        String(UUID().uuidString.prefix(4)).lowercased()
    }

    /// Writes the source line, then a second line with the URL that performed the request.
    static func log(_ source: Source, url: URL?) {
        write(.default, source.message)
        writeURL(url)
    }

    /// `status 200 · 12.4 KB · 183 ms`; status is `-` for non-HTTP responses. `.error` for 4xx/5xx.
    /// Followed by the URL, at the same level.
    static func logResponse(status: Int?, bytes: Int, duration: TimeInterval, url: URL?) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let isFailure = (status ?? 0) >= 400
        let level: OSLogType = isFailure ? .error : .default
        write(
            level,
            "response: status \(status.map(String.init) ?? "-") · \(size) · \(Int(duration * 1000)) ms"
        )
        writeURL(url, level)
    }

    /// `age 42s · expires in 78s`, or `expired 12s ago` for an entry past its expiry. Followed by the URL.
    static func logCacheEntry(age: TimeInterval, expiresIn: TimeInterval, url: URL?) {
        let expiry = expiresIn >= 0 ? "expires in \(Int(expiresIn))s" : "expired \(Int(-expiresIn))s ago"
        write(.default, "cache: age \(Int(age))s · \(expiry)")
        writeURL(url)
    }

    /// Why a network response was not written to the cache. Followed by the URL.
    static func logNotCached(reason: String, url: URL?) {
        write(.default, "not cached: \(reason)")
        writeURL(url)
    }

    /// The request was rejected because the device is offline and nothing usable is cached.
    static func logOffline(url: URL?) {
        write(.error, "blocked: offline")
        writeURL(url, .error)
    }

    /// Why a stale entry was served: `offline` or the network error text. Followed by the URL.
    static func logStaleCause(_ cause: String, url: URL?) {
        write(.error, "stale served after: \(cause)")
        writeURL(url, .error)
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "URLError \(urlError.errorCode)"
        }
        return String(describing: error)
    }

    /// Writes the headers line (`.debug`), then a second line with the URL being requested.
    /// `requestID` is passed explicitly because this runs before the session starts handling the request.
    static func logHeaders(_ headers: [String: String]?, url: URL?, requestID: String? = nil) {
        $requestID.withValue(requestID ?? Self.requestID) {
            write(.debug, "headers: \(String(describing: headers))")
            writeURL(url, .debug)
        }
    }

    /// Writes the URL line once per request: the first call with a request id wins, later ones are skipped.
    /// Outside a request (no id) it always writes.
    private static func writeURL(_ url: URL?, _ level: OSLogType = .default) {
        guard isEnabled else { return }
        if let id = requestID, !markURLWritten(for: id) { return }
        write(level, "url: \(url?.absoluteString ?? "unknown")")
    }

    private static let urlLock = NSLock()
    /// Request ids whose URL line has already been written. Entries are removed by `endRequest`.
    private static var urlWrittenIDs: Set<String> = []

    /// Returns `true` the first time it is called for `id`.
    private static func markURLWritten(for id: String) -> Bool {
        urlLock.lock()
        defer { urlLock.unlock() }
        return urlWrittenIDs.insert(id).inserted
    }

    /// Called when the session has finished a request, so its id can be forgotten.
    static func endRequest(_ id: String) {
        urlLock.lock()
        defer { urlLock.unlock() }
        urlWrittenIDs.remove(id)
    }

    private static func write(_ level: OSLogType, _ message: String) {
        guard isEnabled else { return }
        let prefix = requestID.map { "[NETWORK #\($0)]" } ?? "[NETWORK]"
        output(level, "\(prefix) - \(message)")
    }
}
