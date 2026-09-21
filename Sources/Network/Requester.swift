//
//  File.swift
//  Alfy
//
//  Created by albert vila on 29/5/25.
//

import Foundation

public struct Requester {
    
    private static var cachedSession: CachedURLSession {
        CachedURLSession.shared
    }
    
    public static func configureCache(_ configuration: CachedURLSession.Configuration) {
        CachedURLSession.configure(configuration)
    }
    
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
    
    public static func request(
        _ urlString: String,
        headers: [HeaderParam]? = nil
    ) async throws -> (data: Data, urlResponse: URLResponse) {
        
        let _request = try buildRequest(urlString, headers: headers)
        return try await cachedSession.data(for: _request)
    }
    
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
        
        public func header(_ header: HeaderParam) -> Request {
            var copy = self
            copy.headers.append(header)
            return copy
        }
        
        public func headers(_ headers: [HeaderParam]) -> Request {
            var copy = self
            copy.headers.append(contentsOf: headers)
            return copy
        }
        
        public func cachePolicy(_ policy: URLRequest.CachePolicy) -> Request {
            var copy = self
            copy.cachePolicy = policy
            return copy
        }
        
        public func ttl(_ ttl: TimeInterval) -> Request {
            var copy = self
            copy.ttl = ttl
            return copy
        }

        public func allowStaleOnError(_ allow: Bool) -> Request {
            var copy = self
            copy.allowStaleOnError = allow
            return copy
        }

        public func cacheControlBehavior(_ behavior: CachedURLSession.CacheControlBehavior) -> Request {
            var copy = self
            copy.cacheControlBehavior = behavior
            return copy
        }

        public func forceRefresh() -> Request {
            var copy = self
            copy.cachePolicy = .reloadIgnoringLocalCacheData
            return copy
        }

        public func cacheOnly() -> Request {
            var copy = self
            copy.cachePolicy = .returnCacheDataDontLoad
            return copy
        }

        public func bypassCache() -> Request {
            var copy = self
            copy.isBypassCache = true
            return copy
        }
        
        public func send() async throws -> (data: Data, urlResponse: URLResponse) {
            let _request = try Requester.buildRequest(self)
            return try await Requester.cachedSession.data(for: _request)
        }
        
        public func send<D: Decodable>() async throws -> D {
            let _request = try Requester.buildRequest(self)
            let (data, urlResponse) = try await Requester.cachedSession.data(for: _request)
            return try Requester.decodeResponse(data: data, response: urlResponse)
        }
    }
    
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
    
    private static func buildRequest(_ request: Request) throws -> URLRequest {
        guard NetworkStatusMonitor.shared.hasConnection else {
            throw ErrorReason.noInternetConnection
        }
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
        
        print("Alfy - [NETWORK] - \(String(describing: urlRequest.allHTTPHeaderFields))")
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
        case urlCreationFailed
        case noInternetConnection
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
