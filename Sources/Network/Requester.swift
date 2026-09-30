//
//  File.swift
//  Alfy
//
//  Created by albert vila on 29/5/25.
//

import Foundation

/// Static GET-only API; every call goes through `CachedURLSession.shared`.
/// When offline, serves the cache (fresh, or stale if `allowStaleOnError`) and throws
/// `ErrorReason.noInternetConnection` only when nothing usable is cached.
public struct Requester {
    
    private static var cachedSession: CachedURLSession {
        CachedURLSession.shared
    }
    
    /// Call once at app startup, before any request. Replaces the shared session and drops its in-memory cache.
    public static func configureCache(_ configuration: CachedURLSession.Configuration) {
        CachedURLSession.configure(configuration)
    }
    
    /// Same as the `Configuration` overload. `ttl` is in **seconds**; `maxMemoryEntries` is a count of responses.
    /// `cacheNamespace` is the folder name under `Caches/`.
    public static func configureCache(
        ttl: TimeInterval = 180,
        session: URLSession = .shared,
        allowStaleOnError: Bool = true,
        maxMemoryEntries: Int = 64,
        cacheNamespace: String = "Alfy_CachedURLSession",
        cacheControlBehavior: CachedURLSession.CacheControlBehavior = .respectServer
    ) {
        CachedURLSession.configure(
            ttl: ttl,
            session: session,
            allowStaleOnError: allowStaleOnError,
            maxMemoryEntries: maxMemoryEntries,
            cacheNamespace: cacheNamespace,
            cacheControlBehavior: cacheControlBehavior
        )
    }
    
    /// Cached GET returning raw data. Uses the shared cache defaults; for per-request options use `makeRequest`.
    public static func request(
        _ urlString: String,
        headers: [HeaderParam]? = nil
    ) async throws -> (data: Data, urlResponse: URLResponse) {
        
        let _request = try buildRequest(urlString, headers: headers)
        return try await cachedSession.data(for: _request)
    }
    
    /// Cached GET decoded as JSON into `D`. Throws `ErrorReason.generic(statusCode:)` for non-2xx.
    public static func request<D: Decodable>(
        _ urlString: String,
        headers: [HeaderParam]? = nil
    ) async throws -> D {
        
        let _request = try buildRequest(urlString, headers: headers)
        let (data, urlResponse) = try await cachedSession.data(for: _request)
        
        return try decodeResponse(data: data, response: urlResponse)
    }
}

extension Requester {
    /// Immutable builder: each modifier returns a modified copy; call `send()` to execute.
    /// Fields left nil fall back to the `CachedURLSession` configuration.
    public struct Request {
        public let urlString: String
        public var headers: [HeaderParam]
        public var cachePolicy: URLRequest.CachePolicy?
        public var ttl: TimeInterval?
        public var allowStaleOnError: Bool?
        public var cacheControlBehavior: CachedURLSession.CacheControlBehavior?
        public var isBypassCache: Bool?
        
        public init(_ urlString: String) {
            self.urlString = urlString
            self.headers = []
            self.cachePolicy = nil
            self.ttl = nil
            self.allowStaleOnError = nil
            self.cacheControlBehavior = nil
            self.isBypassCache = nil
        }
        
        /// Appends one header. `Content-Type: application/json` is always added after yours.
        public func header(_ header: HeaderParam) -> Request {
            var copy = self
            copy.headers.append(header)
            return copy
        }
        
        /// Appends several headers to the ones already set; does not replace them.
        public func headers(_ headers: [HeaderParam]) -> Request {
            var copy = self
            copy.headers.append(contentsOf: headers)
            return copy
        }
        
        /// Only `.returnCacheDataDontLoad` and the two `reload...` policies change behavior; any other value acts as default.
        /// Prefer `forceRefresh()` / `cacheOnly()`.
        public func cachePolicy(_ policy: URLRequest.CachePolicy) -> Request {
            var copy = self
            copy.cachePolicy = policy
            return copy
        }
        
        /// Cache lifetime in **seconds** (e.g. `300` = 5 min), not milliseconds.
        /// Used when the server sends no cache headers (or `.ignoreServer`), and caps the age of an existing entry.
        public func ttl(_ ttl: TimeInterval) -> Request {
            var copy = self
            copy.ttl = ttl
            return copy
        }

        /// `true`: if the network call fails and an expired cached entry exists, return it (`X-Cache: STALE`).
        /// `false`: rethrow the network error.
        public func allowStaleOnError(_ allow: Bool) -> Request {
            var copy = self
            copy.allowStaleOnError = allow
            return copy
        }

        /// `.respectServer`: expiry from the `Cache-Control` / `Expires` headers. `.ignoreServer`: always use the TTL.
        public func cacheControlBehavior(_ behavior: CachedURLSession.CacheControlBehavior) -> Request {
            var copy = self
            copy.cacheControlBehavior = behavior
            return copy
        }

        /// Skips the cache read but still stores the fresh response.
        public func forceRefresh() -> Request {
            var copy = self
            copy.cachePolicy = .reloadIgnoringLocalCacheData
            return copy
        }

        /// Never hits the network: returns a fresh cached entry or throws `URLError(.resourceUnavailable)`.
        public func cacheOnly() -> Request {
            var copy = self
            copy.cachePolicy = .returnCacheDataDontLoad
            return copy
        }

        /// Skips the cache entirely: no read, no write.
        public func bypassCache() -> Request {
            var copy = self
            copy.isBypassCache = true
            return copy
        }
        
        /// Executes the GET and returns raw data. Does not check the HTTP status code.
        /// Check the `X-Cache` response header (`HIT`/`MISS`/`STALE`) to see where it came from.
        public func send() async throws -> (data: Data, urlResponse: URLResponse) {
            let _request = try Requester.buildRequest(self)
            return try await Requester.cachedSession.data(for: _request)
        }
        
        /// Executes the GET and decodes the JSON body into `D`.
        /// Throws `ErrorReason.generic(statusCode:)` for non-2xx; decoding failures trigger `assertionFailure` in debug.
        public func send<D: Decodable>() async throws -> D {
            let _request = try Requester.buildRequest(self)
            let (data, urlResponse) = try await Requester.cachedSession.data(for: _request)
            return try Requester.decodeResponse(data: data, response: urlResponse)
        }
    }
    
    /// Starts a `Request` builder; chain modifiers, then call `.send()`.
    public static func makeRequest(_ urlString: String) -> Request {
        Request(urlString)
    }
    
    public static func request(_ request: Request) async throws -> (data: Data, urlResponse: URLResponse) {
        try await request.send()
    }
    
    public static func request<D: Decodable>(_ request: Request) async throws -> D {
        try await request.send()
    }
    
    private static func buildRequest(_ urlString: String, headers: [HeaderParam]?) throws -> URLRequest {
        var request = Request(urlString)
        if let headers {
            request = request.headers(headers)
        }
        return try buildRequest(request)
    }
    
    /// Builds the GET `URLRequest` and stamps cache overrides as `URLProtocol` properties.
    /// `CachedURLSession` reads them back by the same key strings.
    private static func buildRequest(_ request: Request) throws -> URLRequest {
        guard let url = URL(string: request.urlString) else {
            assertionFailure()
            throw ErrorReason.urlCreationFailed
        }
        let urlRequest = NSMutableURLRequest(url: url)
        urlRequest.httpMethod = "GET"
        if let cachePolicy = request.cachePolicy {
            urlRequest.cachePolicy = cachePolicy
        }

        computedHeaders(request.headers).forEach {
            urlRequest.setValue($0.value, forHTTPHeaderField: $0.headerField)
        }
        
        if let ttl = request.ttl {
            URLProtocol.setProperty(
                ttl,
                forKey: "AlfyCacheTTL",
                in: urlRequest
            )
        }
        if let allowStaleOnError = request.allowStaleOnError {
            URLProtocol.setProperty(
                allowStaleOnError,
                forKey: "AlfyAllowStaleOnError",
                in: urlRequest
            )
        }
        if let cacheControlBehavior = request.cacheControlBehavior {
            let rawValue: String = cacheControlBehavior == .ignoreServer ? "ignoreServer" : "respectServer"
            URLProtocol.setProperty(
                rawValue,
                forKey: "AlfyCacheControlBehavior",
                in: urlRequest
            )
        }
        if let isBypassCache = request.isBypassCache {
            URLProtocol.setProperty(
                isBypassCache,
                forKey: "AlfyBypassCache",
                in: urlRequest
            )
        }
        
        NetworkLogger.logHeaders(urlRequest.allHTTPHeaderFields)
        return urlRequest as URLRequest
    }
    
    private static func computedHeaders(_ headers: [HeaderParam]) -> [HeaderParam] {
        let mandatoryHeaders: [HeaderParam] = [
            .contentType(value: .none)
        ]
        return headers + mandatoryHeaders
    }
}

extension Requester {
    
    public enum ErrorReason: Error {
        case dataCorrupted
        /// The string passed is not a valid URL.
        case urlCreationFailed
        /// `NetworkStatusMonitor` reports offline and the cache has nothing to serve; thrown without touching the network.
        case noInternetConnection
        /// Non-2xx HTTP status (only thrown by the decoding overloads).
        case generic(statusCode: Int)
    }
    
    public enum HeaderParam: Hashable {
        case custom(headerField: String, value: String)
        case acceptLanguage(value: String)
        case contentType(value: String? = nil)
        
        var headerField: String {
            switch self {
            case .acceptLanguage:
                return "Accept-Language"
            case .contentType:
                return "Content-Type"
            case .custom(let key, _):
                return key
            }
        }
        
        var value: String {
            switch self {
            case .acceptLanguage(let value):
                return value
            case .contentType(let value):
                return value ?? "application/json"
            case .custom(_, let value):
                return value
            }
        }
    }
}

extension Requester {
    private static func decodeResponse<D: Decodable>(data: Data, response: URLResponse) throws -> D {
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if !(200..<300).contains(statusCode) && statusCode != 204 {
                assert(statusCode != 204)
                throw ErrorReason.generic(statusCode: statusCode)
            }
        }
        
        do {
            return try JSONDecoder().decode(D.self, from: data)
        } catch {
            if case DecodingError.keyNotFound(_, let context) = error {
                assertionFailure(context.debugDescription)
            } else {
                assertionFailure(
                    "\(error.localizedDescription)\n\(String(data: data, encoding: .utf8) ?? "no data")"
                )
            }
            throw error
        }
    }
}
