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
        XCTAssertEqual(NetworkLogger.Source.internet.message, "data from internet")
        XCTAssertEqual(NetworkLogger.Source.cache.message, "data from cache")
        XCTAssertEqual(NetworkLogger.Source.staleCache.message, "data from cache (stale)")
    }

    func testInternetThenCacheThenStaleMapToMessages() async throws {
        let url = URL(string: "https://example.com/logger")!
        let online = LogLines.Flag(true)
        let session = makeSession(isOnline: { online.value })
        let urlLine = "[NETWORK] - url: https://example.com/logger"

        _ = try await session.data(from: url)
        XCTAssertEqual(lines.all.count, 3)
        XCTAssertEqual(Array(lines.all.prefix(2)), ["[NETWORK] - data from internet", urlLine])
        XCTAssertTrue(lines.all[2].hasPrefix("[NETWORK] - response: status 200 · "))
        XCTAssertTrue(lines.all[2].hasSuffix(" ms"))

        _ = try await session.data(from: url)
        XCTAssertEqual(Array(lines.all[3...4]), ["[NETWORK] - data from cache", urlLine])
        XCTAssertTrue(lines.all[5].hasPrefix("[NETWORK] - cache: age 0s · expires in "))
        XCTAssertEqual(lines.all.count, 6)

        online.value = false
        _ = try await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        XCTAssertEqual(Array(lines.all[6...7]), ["[NETWORK] - data from cache (stale)", urlLine])
        XCTAssertTrue(lines.all[8].hasPrefix("[NETWORK] - cache: age "))
        XCTAssertEqual(lines.all[9], "[NETWORK] - stale served after: offline")
        XCTAssertEqual(lines.all.count, 10)
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

        XCTAssertEqual(lines.all.count, 4)
        XCTAssertEqual(lines.all[3], "[NETWORK] - not cached: ttl is 0s and no usable cache headers")
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
    }

    func testLinesWithoutRequestUseBarePrefix() {
        NetworkLogger.logNotCached(reason: "x")
        XCTAssertEqual(lines.raw, ["[NETWORK] - not cached: x"])
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
        XCTAssertEqual(lines.levels, [.info, .info, .info])

        online.value = false
        let blockedURL = URL(string: "https://example.com/levels-blocked")!
        _ = try? await session.data(from: blockedURL)
        XCTAssertEqual(Array(lines.levels.suffix(2)), [.error, .error])
    }

    func testFailureStatusIsLoggedAsError() {
        NetworkLogger.logResponse(status: 404, bytes: 0, duration: 0.01)
        NetworkLogger.logResponse(status: 200, bytes: 0, duration: 0.01)
        XCTAssertEqual(lines.levels, [.error, .info])
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
