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
public enum NetworkLogger {
    public static var isEnabled: Bool = true

    /// Where a response came from.
    enum Source {
        case internet
        case cache
        /// Cache served after a network failure or while offline.
        case staleCache

        var message: String {
            switch self {
            case .internet: return "[NETWORK] - data from internet"
            case .cache: return "[NETWORK] - data from cache"
            case .staleCache: return "[NETWORK] - data from cache (stale)"
            }
        }
    }

    private static let logger = Logger(subsystem: "Alfy", category: "Network")

    /// Final destination of each line; replaced in tests to capture output.
    static var output: @Sendable (String) -> Void = { message in
        logger.log("\(message, privacy: .public)")
    }

    static func log(_ source: Source) {
        write(source.message)
    }

    static func logHeaders(_ headers: [String: String]?) {
        write("[NETWORK] - headers: \(String(describing: headers))")
    }

    private static func write(_ message: String) {
        guard isEnabled else { return }
        output(message)
    }
}
