//
//  CachedURLSession+Tests.swift
//  Alfy
//
//  Created by Codex on 2026/01/21.
//

import XCTest
@testable import Alfy

final class CachedURLSessionTests: XCTestCase {
    private let cacheNamespace = "Alfy_CachedURLSession_Tests"

    override func setUp() {
        super.setUp()
        Self.resetURLProtocol()
        Self.removeDiskCache(namespace: cacheNamespace)
    }

    override func tearDown() {
        Self.resetURLProtocol()
        Self.removeDiskCache(namespace: cacheNamespace)
        super.tearDown()
    }

    /// Caches a successful GET response and serves it from cache on the next request.
    /// Verifies `X-Cache` transitions from MISS to HIT with only one network call.
    func testCachesGETResponsesAndServesHit() async throws {
        let url = URL(string: "https://example.com/data")!
        let data1 = Data("one".utf8)

        let calls = Locked<Int>(0)
        TestURLProtocol.requestHandler = { request in
            calls.withLock { $0 += 1 }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Cache-Control": "max-age=60", "Content-Type": "text/plain"]
                )!,
                data1
            )
        }

        let cached = Self.makeCachedSession(ttl: 60, allowStaleOnError: true, cacheControlBehavior: .respectServer)

        let (firstData, firstResponse) = try await cached.data(from: url)
        XCTAssertEqual(firstData, data1)
        XCTAssertEqual((firstResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "MISS")

        let (secondData, secondResponse) = try await cached.data(from: url)
        XCTAssertEqual(secondData, data1)
        XCTAssertEqual((secondResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "HIT")
        XCTAssertEqual(calls.withLock { $0 }, 1)
    }

    /// Uses `URLRequest` initializer with `.useProtocolCachePolicy` and `timeoutInterval: 60`.
    /// First request is network (MISS), second is cached (HIT).
    func testUseProtocolCachePolicyWithTimeoutCachesSecondRequest() async throws {
        let url = URL(string: "https://example.com/use-protocol")!
        let data = Data("stored".utf8)

        let calls = Locked<Int>(0)
        TestURLProtocol.requestHandler = { request in
            calls.withLock { $0 += 1 }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Cache-Control": "max-age=60"]
                )!,
                data
            )
        }

        let cached = Self.makeCachedSession(ttl: 120, allowStaleOnError: true, cacheControlBehavior: .respectServer)

        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)

        let (d1, r1) = try await cached.data(for: request)
        XCTAssertEqual(d1, data)
        XCTAssertEqual((r1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "MISS")

        let (d2, r2) = try await cached.data(for: request)
        XCTAssertEqual(d2, data)
        XCTAssertEqual((r2 as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "HIT")
        XCTAssertEqual(calls.withLock { $0 }, 1)
    }

    /// Ensures a `ttl: 2` cache entry expires and triggers a refetch.
    /// Sequence: MISS → HIT → (sleep > 2s) → MISS.
    func testUseProtocolCachePolicyWithTTLExpiresAndRefetches() async throws {
        let url = URL(string: "https://example.com/ttl-expiry")!
        let calls = Locked<Int>(0)

        TestURLProtocol.requestHandler = { request in
            let count = calls.withLock { current in
                current += 1
                return current
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [:]
                )!,
                Data("v\(count)".utf8)
            )
        }

        let cached = Self.makeCachedSession(ttl: 2, allowStaleOnError: true, cacheControlBehavior: .respectServer)
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)

        let (d1, r1) = try await cached.data(for: request)
        XCTAssertEqual(d1, Data("v1".utf8))
        XCTAssertEqual((r1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "MISS")

        let (d2, r2) = try await cached.data(for: request)
        XCTAssertEqual(d2, Data("v1".utf8))
        XCTAssertEqual((r2 as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "HIT")

        try await Task.sleep(nanoseconds: 2_250_000_000)

        let (d3, r3) = try await cached.data(for: request)
        XCTAssertEqual(d3, Data("v2".utf8))
        XCTAssertEqual((r3 as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "MISS")
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    /// With `.returnCacheDataDontLoad` and no cached entry, throws `.resourceUnavailable`.
    func testReturnCacheDataDontLoadThrowsWhenMissing() async throws {
        let url = URL(string: "https://example.com/miss")!
        let cached = Self.makeCachedSession(ttl: 60, allowStaleOnError: true, cacheControlBehavior: .respectServer)

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataDontLoad

        do {
            _ = try await cached.data(for: request)
            XCTFail("Expected URLError.resourceUnavailable")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .resourceUnavailable)
        }
    }

    /// With `.returnCacheDataDontLoad` and a cached entry, returns cached data (HIT).
    func testReturnCacheDataDontLoadReturnsCachedWhenPresent() async throws {
        let url = URL(string: "https://example.com/have")!
        let data = Data("cached".utf8)

        TestURLProtocol.requestHandler = { request in
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Cache-Control": "max-age=60"]
                )!,
                data
            )
        }

        let cached = Self.makeCachedSession(ttl: 60, allowStaleOnError: true, cacheControlBehavior: .respectServer)
        _ = try await cached.data(from: url)

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataDontLoad
        let (hitData, hitResponse) = try await cached.data(for: request)
        XCTAssertEqual(hitData, data)
        XCTAssertEqual((hitResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "HIT")
    }

    /// With `.reloadIgnoringLocalCacheData`, bypasses cache and refills it with latest response.
    func testReloadIgnoringLocalCacheDataBypassesCache() async throws {
        let url = URL(string: "https://example.com/reload")!
        let calls = Locked<Int>(0)

        TestURLProtocol.requestHandler = { request in
            let count = calls.withLock { current in
                current += 1
                return current
            }
            let data = Data("v\(count)".utf8)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Cache-Control": "max-age=60"]
                )!,
                data
            )
        }

        let cached = Self.makeCachedSession(ttl: 60, allowStaleOnError: true, cacheControlBehavior: .respectServer)

        let (d1, _) = try await cached.data(from: url)
        XCTAssertEqual(d1, Data("v1".utf8))

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (d2, r2) = try await cached.data(for: request)
        XCTAssertEqual(d2, Data("v2".utf8))
        XCTAssertEqual((r2 as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "MISS")

        let (d3, r3) = try await cached.data(from: url)
        XCTAssertEqual(d3, Data("v2".utf8))
        XCTAssertEqual((r3 as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "HIT")
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    /// When respecting server headers, `Cache-Control: no-store` disables caching.
    func testRespectsNoStoreByDefault() async throws {
        let url = URL(string: "https://example.com/nostore")!
        let calls = Locked<Int>(0)

        TestURLProtocol.requestHandler = { request in
            calls.withLock { $0 += 1 }
            let data = Data("uncached".utf8)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Cache-Control": "no-store, max-age=60"]
                )!,
                data
            )
        }

        let cached = Self.makeCachedSession(ttl: 60, allowStaleOnError: true, cacheControlBehavior: .respectServer)
        _ = try await cached.data(from: url)
        _ = try await cached.data(from: url)
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    /// When ignoring server cache control, `no-store` responses can still be cached.
    func testIgnoreServerCacheControlCachesNoStore() async throws {
        let url = URL(string: "https://example.com/nostore-ignored")!
        let calls = Locked<Int>(0)
        let data = Data("cached-anyway".utf8)

        TestURLProtocol.requestHandler = { request in
            calls.withLock { $0 += 1 }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Cache-Control": "no-store"]
                )!,
                data
            )
        }

        let cached = Self.makeCachedSession(ttl: 60, allowStaleOnError: true, cacheControlBehavior: .ignoreServer)
        _ = try await cached.data(from: url)
        let (hitData, hitResponse) = try await cached.data(from: url)
        XCTAssertEqual(hitData, data)
        XCTAssertEqual((hitResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "HIT")
        XCTAssertEqual(calls.withLock { $0 }, 1)
    }

    /// If the network fails and `allowStaleOnError` is true, returns a stale cached entry.
    func testAllowStaleOnErrorReturnsStaleWhenFetchFails() async throws {
        let url = URL(string: "https://example.com/stale")!
        let calls = Locked<Int>(0)
        let data = Data("fresh-then-stale".utf8)

        TestURLProtocol.requestHandler = { request in
            let count = calls.withLock { current in
                current += 1
                return current
            }
            if count == 1 {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Cache-Control": "max-age=0"]
                    )!,
                    data
                )
            }
            throw URLError(.notConnectedToInternet)
        }

        let cached = Self.makeCachedSession(ttl: 0.05, allowStaleOnError: true, cacheControlBehavior: .respectServer)
        _ = try await cached.data(from: url)
        try await Task.sleep(nanoseconds: 150_000_000)

        let (staleData, staleResponse) = try await cached.data(from: url)
        XCTAssertEqual(staleData, data)
        XCTAssertEqual((staleResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Cache"), "STALE")
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    /// If the network fails and `allowStaleOnError` is false, propagates the network error.
    func testDisallowsStaleOnErrorWhenConfigured() async throws {
        let url = URL(string: "https://example.com/no-stale")!
        let calls = Locked<Int>(0)

        TestURLProtocol.requestHandler = { request in
            let count = calls.withLock { current in
                current += 1
                return current
            }
            if count == 1 {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Cache-Control": "max-age=0"]
                    )!,
                    Data("will-expire".utf8)
                )
            }
            throw URLError(.timedOut)
        }

        let cached = Self.makeCachedSession(ttl: 0.05, allowStaleOnError: false, cacheControlBehavior: .respectServer)
        _ = try await cached.data(from: url)
        try await Task.sleep(nanoseconds: 150_000_000)

        do {
            _ = try await cached.data(from: url)
            XCTFail("Expected timedOut error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }
    }

    /// Only GET requests are cached; POST requests always hit the underlying session.
    func testDoesNotCacheNonGETRequests() async throws {
        let url = URL(string: "https://example.com/post")!
        let calls = Locked<Int>(0)

        TestURLProtocol.requestHandler = { request in
            calls.withLock { $0 += 1 }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!,
                Data("ok".utf8)
            )
        }

        let cached = Self.makeCachedSession(ttl: 60, allowStaleOnError: true, cacheControlBehavior: .respectServer)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        _ = try await cached.data(for: request)
        _ = try await cached.data(for: request)
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    /// Concurrent identical GETs share a single inflight request and both await the same result.
    func testDeduplicatesInflightRequestsForSameURL() async throws {
        let url = URL(string: "https://example.com/inflight")!
        let calls = Locked<Int>(0)
        let data = Data("slow".utf8)

        TestURLProtocol.requestHandler = { request in
            calls.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 0.15)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Cache-Control": "max-age=60"]
                )!,
                data
            )
        }

        let cached = Self.makeCachedSession(ttl: 60, allowStaleOnError: true, cacheControlBehavior: .respectServer)

        async let a = cached.data(from: url)
        async let b = cached.data(from: url)
        let (r1, r2) = try await (a, b)

        XCTAssertEqual(r1.0, data)
        XCTAssertEqual(r2.0, data)
        XCTAssertEqual(calls.withLock { $0 }, 1)
    }

    // MARK: - Helpers

    /// Builds a `CachedURLSession` that uses `TestURLProtocol` for deterministic responses.
    /// Uses `CachedURLSession.shared`, so tests should clean up disk cache between runs.
    private static func makeCachedSession(
        ttl: TimeInterval,
        allowStaleOnError: Bool,
        cacheControlBehavior: CachedURLSession.CacheControlBehavior
    ) -> CachedURLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: config)
        CachedURLSession.configure(
            ttl: ttl,
            session: session,
            allowStaleOnError: allowStaleOnError,
            maxMemoryEntries: 64,
            cacheControlBehavior: cacheControlBehavior
        )
        return CachedURLSession.shared
    }

    /// Clears the shared `TestURLProtocol` handler to avoid test cross-talk.
    private static func resetURLProtocol() {
        TestURLProtocol.requestHandler = nil
    }

    /// Deletes the on-disk cache directory used by `CachedURLSession`.
    private static func removeDiskCache(namespace: String) {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(namespace, isDirectory: true)
        if let dir {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

/// `URLProtocol` stub that returns responses from a per-test handler closure.
private final class TestURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Minimal thread-safe box for counters shared across concurrent tasks.
private final class Locked<T> {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
