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
/// Levels: `.info` for sources and summaries, `.debug` for headers, `.error` for failures (offline, 4xx/5xx, stale after error).
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
        write(.info, source.message)
        write(.info, "url: \(url?.absoluteString ?? "unknown")")
    }

    /// `status 200 · 12.4 KB · 183 ms`; status is `-` for non-HTTP responses. `.error` for 4xx/5xx.
    static func logResponse(status: Int?, bytes: Int, duration: TimeInterval) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let isFailure = (status ?? 0) >= 400
        write(
            isFailure ? .error : .info,
            "response: status \(status.map(String.init) ?? "-") · \(size) · \(Int(duration * 1000)) ms"
        )
    }

    /// `age 42s · expires in 78s`, or `expired 12s ago` for an entry past its expiry.
    static func logCacheEntry(age: TimeInterval, expiresIn: TimeInterval) {
        let expiry = expiresIn >= 0 ? "expires in \(Int(expiresIn))s" : "expired \(Int(-expiresIn))s ago"
        write(.info, "cache: age \(Int(age))s · \(expiry)")
    }

    /// Why a network response was not written to the cache.
    static func logNotCached(reason: String) {
        write(.info, "not cached: \(reason)")
    }

    /// The request was rejected because the device is offline and nothing usable is cached.
    static func logOffline(url: URL?) {
        write(.error, "blocked: offline")
        write(.error, "url: \(url?.absoluteString ?? "unknown")")
    }

    /// Why a stale entry was served: `offline` or the network error text.
    static func logStaleCause(_ cause: String) {
        write(.error, "stale served after: \(cause)")
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
            write(.debug, "url: \(url?.absoluteString ?? "unknown")")
        }
    }

    private static func write(_ level: OSLogType, _ message: String) {
        guard isEnabled else { return }
        let prefix = requestID.map { "[NETWORK #\($0)]" } ?? "[NETWORK]"
        output(level, "\(prefix) - \(message)")
    }
}
