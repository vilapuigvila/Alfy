//
//  NetworkLogger+Tests.swift
//  Alfy
//
//  Created by albert vila on 30/9/26.
//

import XCTest
import os
@testable import Alfy

final class NetworkLoggerTests: XCTestCase {
    private let namespace = "Alfy_NetworkLogger_Tests"
    private let lines = LogLines()
    private var originalOutput: (@Sendable (OSLogType, String) -> Void)!

    override func setUp() {
        super.setUp()
        originalOutput = NetworkLogger.output
        NetworkLogger.isEnabled = true
        let captured = lines
        NetworkLogger.output = { level, line in captured.append(level, line) }
        Self.removeDiskCache(namespace: namespace)
    }

    override func tearDown() {
        NetworkLogger.output = originalOutput
        NetworkLogger.isEnabled = true
        Self.removeDiskCache(namespace: namespace)
        super.tearDown()
    }

    func testSourceMessages() {
        XCTAssertEqual(NetworkLogger.Source.internet.message, "network")
        XCTAssertEqual(NetworkLogger.Source.cache.message, "cache")
        XCTAssertEqual(NetworkLogger.Source.staleCache.message, "cache (stale)")
    }

    func testInternetThenCacheThenStaleMapToMessages() async throws {
        let url = URL(string: "https://example.com/logger")!
        let online = LogLines.Flag(true)
        let session = makeSession(isOnline: { online.value })
        _ = try await session.data(from: url)
        XCTAssertEqual(lines.all.count, 2)
        XCTAssertEqual(lines.all[0], "[NETWORK] - url: https://example.com/logger - network")
        XCTAssertTrue(lines.all[1].hasPrefix("[NETWORK] - response: status 200 · "))
        XCTAssertTrue(lines.all[1].hasSuffix(" ms"))

        _ = try await session.data(from: url)
        XCTAssertEqual(lines.all[2], "[NETWORK] - url: https://example.com/logger - cache")
        XCTAssertTrue(lines.all[3].hasPrefix("[NETWORK] - cache: age 0s · expires in "))
        XCTAssertEqual(lines.all.count, 4)

        online.value = false
        _ = try await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        XCTAssertEqual(lines.all[4], "[NETWORK] - url: https://example.com/logger - cache (stale)")
        XCTAssertTrue(lines.all[5].hasPrefix("[NETWORK] - cache: age "))
        XCTAssertEqual(lines.all[6], "[NETWORK] - stale served after: offline")
        XCTAssertEqual(lines.all.count, 7)
    }

    func testOfflineWithNothingCachedLogsBlocked() async {
        let session = makeSession(isOnline: { false })
        let url = URL(string: "https://example.com/blocked")!

        do {
            _ = try await session.data(from: url)
            XCTFail("expected noInternetConnection")
        } catch {
            XCTAssertEqual(
                lines.all,
                ["[NETWORK] - blocked: offline", "[NETWORK] - url: https://example.com/blocked"]
            )
        }
    }

    func testResponseThatIsNotStoredLogsReason() async throws {
        let session = makeSession(isOnline: { true }, ttl: 0, behavior: .ignoreServer)

        _ = try await session.data(from: URL(string: "https://example.com/uncached")!)

        XCTAssertEqual(lines.all.count, 3)
        XCTAssertEqual(lines.all[2], "[NETWORK] - not cached: ttl is 0s and no usable cache headers")
    }

    func testStaleAfterNetworkErrorLogsErrorCode() {
        XCTAssertEqual(NetworkLogger.describe(URLError(.notConnectedToInternet)), "URLError -1009")
    }

    func testDisabledSwitchStopsOutput() async throws {
        NetworkLogger.isEnabled = false
        let session = makeSession(isOnline: { true })
        let url = URL(string: "https://example.com/silent")!

        _ = try await session.data(from: url)
        _ = try await session.data(from: url)
        NetworkLogger.logHeaders(["A": "B"], url: nil)

        XCTAssertTrue(lines.all.isEmpty)
    }

    func testHeadersLineUsesNetworkPrefix() {
        NetworkLogger.logHeaders(["A": "B"], url: URL(string: "https://example.com/h"), requestID: "ab12")
        XCTAssertEqual(lines.raw.count, 2)
        XCTAssertTrue(lines.raw[0].hasPrefix("[NETWORK #ab12] - headers: "))
        XCTAssertEqual(lines.raw[1], "[NETWORK #ab12] - url: https://example.com/h")
        XCTAssertEqual(lines.levels, [.debug, .debug])
        NetworkLogger.endRequest("ab12")
    }

    func testLinesWithoutRequestUseBarePrefix() {
        NetworkLogger.logNotCached(reason: "x", url: nil)
        XCTAssertEqual(lines.raw, ["[NETWORK] - not cached: x", "[NETWORK] - url: unknown"])
    }

    func testEveryLineOfOneRequestSharesItsIDAndRequestsDiffer() async throws {
        let session = makeSession(isOnline: { true })

        _ = try await session.data(from: URL(string: "https://example.com/a")!)
        let firstIDs = Set(lines.raw.map(Self.id(of:)))
        XCTAssertEqual(firstIDs.count, 1)

        _ = try await session.data(from: URL(string: "https://example.com/b")!)
        let allIDs = Set(lines.raw.map(Self.id(of:)))
        XCTAssertEqual(allIDs.count, 2)
    }

    func testLevelsMatchSeverity() async throws {
        let online = LogLines.Flag(true)
        let session = makeSession(isOnline: { online.value })
        let url = URL(string: "https://example.com/levels")!

        _ = try await session.data(from: url)
        XCTAssertEqual(lines.levels, [.default, .default])

        online.value = false
        let blockedURL = URL(string: "https://example.com/levels-blocked")!
        _ = try? await session.data(from: blockedURL)
        XCTAssertEqual(Array(lines.levels.suffix(2)), [.error, .error])
    }

    func testURLIsWrittenOncePerRequest() {
        let url = URL(string: "https://example.com/once")
        NetworkLogger.$requestID.withValue("ef56") {
            NetworkLogger.logResponse(status: 500, bytes: 0, duration: 0.01, url: url)
            NetworkLogger.logCacheEntry(age: 1, expiresIn: 1, url: url)
            NetworkLogger.logNotCached(reason: "x", url: url)
            NetworkLogger.logStaleCause("offline", url: url)
        }
        NetworkLogger.endRequest("ef56")

        XCTAssertEqual(lines.all.filter { $0.hasPrefix("[NETWORK] - url: ") }.count, 1)
        XCTAssertEqual(lines.all.count, 5)
    }

    func testRequesterHeadersAndSessionShareOneURLLine() async throws {
        let session = makeSession(isOnline: { true })
        let url = URL(string: "https://example.com/shared")!
        NetworkLogger.logHeaders(nil, url: url, requestID: "cd34")

        let request = NSMutableURLRequest(url: url)
        URLProtocol.setProperty("cd34", forKey: "AlfyRequestID", in: request)
        _ = try await session.data(for: request as URLRequest)

        let urlLines = lines.all.filter { $0.hasPrefix("[NETWORK] - url: ") }
        XCTAssertEqual(urlLines.count, 1)
        XCTAssertTrue(lines.raw.allSatisfy { $0.hasPrefix("[NETWORK #cd34]") })
    }

    func testFailureStatusIsLoggedAsError() {
        let url = URL(string: "https://example.com/status")
        NetworkLogger.logResponse(status: 404, bytes: 0, duration: 0.01, url: url)
        NetworkLogger.logResponse(status: 200, bytes: 0, duration: 0.01, url: url)
        XCTAssertEqual(lines.levels, [.error, .error, .default, .default])
        XCTAssertEqual(lines.all[1], "[NETWORK] - url: https://example.com/status")
        XCTAssertEqual(lines.all[3], "[NETWORK] - url: https://example.com/status")
    }

    private static func id(of line: String) -> String {
        guard let start = line.range(of: "#"), let end = line.range(of: "]") else { return "" }
        return String(line[start.upperBound..<end.lowerBound])
    }

    private func makeSession(
        isOnline: @escaping @Sendable () -> Bool,
        ttl: TimeInterval = 60,
        behavior: CachedURLSession.CacheControlBehavior = .respectServer
    ) -> CachedURLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LoggerStubProtocol.self]
        return CachedURLSession(
            configuration: .init(
                ttl: ttl,
                session: URLSession(configuration: config),
                allowStaleOnError: true,
                cacheNamespace: namespace,
                cacheControlBehavior: behavior,
                isOnline: isOnline
            )
        )
    }

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

private final class LogLines: @unchecked Sendable {
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Bool
        init(_ value: Bool) { stored = value }
        var value: Bool {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    private let lock = NSLock()
    private var storage: [(OSLogType, String)] = []

    func append(_ level: OSLogType, _ line: String) {
        lock.lock()
        storage.append((level, line))
        lock.unlock()
    }

    /// Lines exactly as written, including the `#id`.
    var raw: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage.map(\.1)
    }

    var levels: [OSLogType] {
        lock.lock()
        defer { lock.unlock() }
        return storage.map(\.0)
    }

    /// Lines with the `#id` removed, so tests can compare against fixed text.
    var all: [String] {
        raw.map { $0.replacingOccurrences(of: #" #[0-9a-f]{4}\]"#, with: "]", options: .regularExpression) }
    }
}

private final class LoggerStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "max-age=60"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
