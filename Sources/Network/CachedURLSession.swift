//
//  File.swift
//  Alfy
//
//  Created by albert vila on 21/1/26.
//

import Foundation
import CryptoKit

public actor CachedURLSession {
    
    private static let defaultCacheNamespace = "Alfy_CachedURLSession"

    private enum SharedStorage {
        static let lock = NSLock()
        static var instance = CachedURLSession(configuration: .init())
    }

    /// Global singleton instance. Call `configure(...)` once at app startup to customize it.
    public static var shared: CachedURLSession {
        SharedStorage.lock.lock()
        let instance = SharedStorage.instance
        SharedStorage.lock.unlock()
        return instance
    }

    public struct Configuration {
        let cacheNamespace: String = "Alfy_CachedURLSession"
        
        public var ttl: TimeInterval
        public var session: URLSession
        public var allowStaleOnError: Bool
        public var maxMemoryEntries: Int
        public var cacheControlBehavior: CacheControlBehavior

        public init(
            ttl: TimeInterval = 120,
            session: URLSession = .shared,
            allowStaleOnError: Bool = true,
            maxMemoryEntries: Int = 64,
//            cacheNamespace: String = CachedURLSession.defaultCacheNamespace,
            cacheControlBehavior: CacheControlBehavior = .respectServer
        ) {
            self.ttl = ttl
            self.session = session
            self.allowStaleOnError = allowStaleOnError
            self.maxMemoryEntries = maxMemoryEntries
//            self.cacheNamespace = cacheNamespace
            self.cacheControlBehavior = cacheControlBehavior
        }
    }

    /// Replaces the global singleton instance.
    public static func configure(_ configuration: Configuration) {
        SharedStorage.lock.lock()
        SharedStorage.instance = CachedURLSession(configuration: configuration)
        SharedStorage.lock.unlock()
    }

    public static func configure(
        ttl: TimeInterval = 120,
        session: URLSession = .shared,
        allowStaleOnError: Bool = true,
        maxMemoryEntries: Int = 64,
//        cacheNamespace: String = CachedURLSession.defaultCacheNamespace,
        cacheControlBehavior: CacheControlBehavior = .respectServer
    ) {
        configure(
            Configuration(
                ttl: ttl,
                session: session,
                allowStaleOnError: allowStaleOnError,
                maxMemoryEntries: maxMemoryEntries,
//                cacheNamespace: cacheNamespace,
                cacheControlBehavior: cacheControlBehavior
            )
        )
    }
    
    public enum CacheControlBehavior {
        case respectServer
        case ignoreServer
    }

    private struct CacheEntry: Codable {
        let storedAt: Date
        let expiresAt: Date
        let data: Data
        let statusCode: Int
        let headers: [String: String]
        let mimeType: String?
        let textEncodingName: String?
    }

    private let defaultTTL: TimeInterval
    private let session: URLSession
    private let allowStaleOnError: Bool
    private let maxMemoryEntries: Int
    private let cacheDirectoryURL: URL
    private let cacheControlBehavior: CacheControlBehavior

    private var memoryCache: [String: CacheEntry] = [:]
    private var inflight: [String: Task<(Data, URLResponse), Error>] = [:]

    private init(configuration: Configuration) {
        self.defaultTTL = configuration.ttl
        self.session = configuration.session
        self.allowStaleOnError = configuration.allowStaleOnError
        self.maxMemoryEntries = configuration.maxMemoryEntries
        self.cacheControlBehavior = configuration.cacheControlBehavior
        self.cacheDirectoryURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(configuration.cacheNamespace, isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(configuration.cacheNamespace, isDirectory: true)

        try? FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url))
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let cacheKey = cacheKey(for: request) else {
            return try await session.data(for: request)
        }

        switch request.cachePolicy {
        case .returnCacheDataDontLoad:
            if let entry = loadEntry(forKey: cacheKey), isFresh(entry) {
                return cachedResult(from: entry, url: request.url, cacheState: "HIT")
            }
            throw URLError(.resourceUnavailable)
        case .reloadIgnoringLocalCacheData, .reloadIgnoringLocalAndRemoteCacheData:
            break
        default:
            if let entry = loadEntry(forKey: cacheKey), isFresh(entry) {
                return cachedResult(from: entry, url: request.url, cacheState: "HIT")
            }
        }

        if let existing = inflight[cacheKey] {
            return try await existing.value
        }

        let task = Task<(Data, URLResponse), Error> {
            try await self.fetchAndCache(request: request, cacheKey: cacheKey)
        }
        inflight[cacheKey] = task
        defer { inflight[cacheKey] = nil }
        return try await task.value
    }
    
/*
    public func get(_ url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        Task {
            do {
                let (data, response) = try await self.data(from: url)
                completion(data, response, nil)
            } catch {
                completion(nil, nil, error)
            }
        }
    }
 */

    private func cacheKey(for request: URLRequest) -> String? {
        guard let url = request.url else { return nil }
        let method = (request.httpMethod ?? "GET").uppercased()
        guard method == "GET" else { return nil }
        return sha256("\(method) \(url.absoluteString)")
    }

    private func fetchAndCache(request: URLRequest, cacheKey: String) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            if let entry = makeCacheEntry(request: request, data: data, response: response) {
                store(entry, forKey: cacheKey)
            }
            return (data, withCacheHeader(response, cacheState: "MISS"))
        } catch {
            if allowStaleOnError, let stale = loadEntry(forKey: cacheKey) {
                return cachedResult(from: stale, url: request.url, cacheState: "STALE")
            }
            throw error
        }
    }

    private func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func isFresh(_ entry: CacheEntry) -> Bool {
        Date() < entry.expiresAt
    }

    private func cachedResult(from entry: CacheEntry, url: URL?, cacheState: String) -> (Data, URLResponse) {
        let responseURL = url ?? URL(string: "about:blank")!
        var headers = entry.headers
        headers["X-Cache"] = cacheState
        headers["Age"] = String(Int(Date().timeIntervalSince(entry.storedAt)))

        if headers["Cache-Control"] == nil {
            let maxAge = max(0, Int(entry.expiresAt.timeIntervalSince(entry.storedAt)))
            headers["Cache-Control"] = "public, max-age=\(maxAge)"
        }

        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: entry.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) ?? URLResponse(
            url: responseURL,
            mimeType: entry.mimeType,
            expectedContentLength: entry.data.count,
            textEncodingName: entry.textEncodingName
        )

        return (entry.data, response)
    }

    private func withCacheHeader(_ response: URLResponse, cacheState: String) -> URLResponse {
        guard let http = response as? HTTPURLResponse else { return response }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String {
                headers[key] = String(describing: value)
            }
        }
        headers["X-Cache"] = cacheState
        return HTTPURLResponse(
            url: http.url ?? URL(string: "about:blank")!,
            statusCode: http.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) ?? response
    }

    private func makeCacheEntry(request: URLRequest, data: Data, response: URLResponse) -> CacheEntry? {
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200...299).contains(http.statusCode) else { return nil }

        let storedAt = Date()
        guard let expiresAt = expirationDate(for: http, storedAt: storedAt, fallbackTTL: defaultTTL) else {
            return nil
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String {
                headers[key] = String(describing: value)
            }
        }

        return CacheEntry(
            storedAt: storedAt,
            expiresAt: expiresAt,
            data: data,
            statusCode: http.statusCode,
            headers: headers,
            mimeType: http.mimeType,
            textEncodingName: http.textEncodingName
        )
    }

    private func expirationDate(for response: HTTPURLResponse, storedAt: Date, fallbackTTL: TimeInterval) -> Date? {
        let cacheControl = headerValue(named: "Cache-Control", in: response)
        if cacheControlBehavior == .respectServer,
           let cacheControl,
           cacheControlLowercasedContainsNoStoreOrNoCache(cacheControl)
        {
            return nil
        }

        if let cacheControl, let maxAge = cacheControlMaxAgeSeconds(cacheControl), maxAge > 0 {
            return storedAt.addingTimeInterval(TimeInterval(maxAge))
        }

        if let expires = headerValue(named: "Expires", in: response),
           let date = httpDate(expires),
           date > storedAt {
            return date
        }

        guard fallbackTTL > 0 else { return nil }
        return storedAt.addingTimeInterval(fallbackTTL)
    }

    private func headerValue(named name: String, in response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String else { continue }
            if key.caseInsensitiveCompare(name) == .orderedSame {
                return String(describing: value)
            }
        }
        return nil
    }

    private func cacheControlLowercasedContainsNoStoreOrNoCache(_ value: String) -> Bool {
        let directives = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return directives.contains("no-store") || directives.contains("no-cache")
    }

    private func cacheControlMaxAgeSeconds(_ value: String) -> Int? {
        let directives = value.split(separator: ",")
        for directive in directives {
            let trimmed = directive.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard trimmed.hasPrefix("max-age=") else { continue }
            let secondsString = trimmed.replacingOccurrences(of: "max-age=", with: "")
            return Int(secondsString)
        }
        return nil
    }

    private func httpDate(_ string: String) -> Date? {
        let formatters: [DateFormatter] = {
            let formats = [
                "EEE',' dd MMM yyyy HH':'mm':'ss zzz",  // RFC1123
                "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",   // RFC850
                "EEE MMM d HH':'mm':'ss yyyy"           // ANSI C asctime()
            ]
            return formats.map { format in
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(secondsFromGMT: 0)
                df.dateFormat = format
                return df
            }
        }()

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    private func loadEntry(forKey key: String) -> CacheEntry? {
        if let entry = memoryCache[key] {
            return entry
        }

        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = PropertyListDecoder()
        guard let entry = try? decoder.decode(CacheEntry.self, from: data) else { return nil }
        memoryCache[key] = entry
        trimMemoryIfNeeded()
        return entry
    }

    private func store(_ entry: CacheEntry, forKey key: String) {
        memoryCache[key] = entry
        trimMemoryIfNeeded()

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: fileURL(forKey: key), options: [.atomic])
    }

    private func fileURL(forKey key: String) -> URL {
        cacheDirectoryURL
            .appendingPathComponent(key)
            .appendingPathExtension("plist")
    }

    private func trimMemoryIfNeeded() {
        guard memoryCache.count > maxMemoryEntries else { return }
        let orderedKeys = memoryCache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .map(\.key)
        let keysToRemove = orderedKeys.prefix(memoryCache.count - maxMemoryEntries)
        for key in keysToRemove {
            memoryCache[key] = nil
        }
    }
}
