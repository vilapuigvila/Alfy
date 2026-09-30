//
//  NetworkLogger+Tests.swift
//  Alfy
//
//  Created by albert vila on 30/9/26.
//

import XCTest
@testable import Alfy

final class NetworkLoggerTests: XCTestCase {
    private let namespace = "Alfy_NetworkLogger_Tests"
    private let lines = LogLines()
    private var originalOutput: (@Sendable (String) -> Void)!

    override func setUp() {
        super.setUp()
        originalOutput = NetworkLogger.output
        NetworkLogger.isEnabled = true
        let captured = lines
        NetworkLogger.output = { captured.append($0) }
        Self.removeDiskCache(namespace: namespace)
    }

    override func tearDown() {
        NetworkLogger.output = originalOutput
        NetworkLogger.isEnabled = true
        Self.removeDiskCache(namespace: namespace)
        super.tearDown()
    }

    func testSourceMessages() {
        XCTAssertEqual(NetworkLogger.Source.internet.message, "[NETWORK] - data from internet")
        XCTAssertEqual(NetworkLogger.Source.cache.message, "[NETWORK] - data from cache")
        XCTAssertEqual(NetworkLogger.Source.staleCache.message, "[NETWORK] - data from cache (stale)")
    }

    func testInternetThenCacheThenStaleMapToMessages() async throws {
        let url = URL(string: "https://example.com/logger")!
        let online = LogLines.Flag(true)
        let session = makeSession(isOnline: { online.value })

        _ = try await session.data(from: url)
        XCTAssertEqual(lines.all, ["[NETWORK] - data from internet"])

        _ = try await session.data(from: url)
        XCTAssertEqual(lines.all.last, "[NETWORK] - data from cache")

        online.value = false
        _ = try await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        XCTAssertEqual(lines.all.last, "[NETWORK] - data from cache (stale)")
        XCTAssertEqual(lines.all.count, 3)
    }

    func testDisabledSwitchStopsOutput() async throws {
        NetworkLogger.isEnabled = false
        let session = makeSession(isOnline: { true })
        let url = URL(string: "https://example.com/silent")!

        _ = try await session.data(from: url)
        _ = try await session.data(from: url)
        NetworkLogger.logHeaders(["A": "B"])

        XCTAssertTrue(lines.all.isEmpty)
    }

    func testHeadersLineUsesNetworkPrefix() {
        NetworkLogger.logHeaders(["A": "B"])
        XCTAssertEqual(lines.all.count, 1)
        XCTAssertTrue(lines.all[0].hasPrefix("[NETWORK] - headers: "))
    }

    private func makeSession(isOnline: @escaping @Sendable () -> Bool) -> CachedURLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LoggerStubProtocol.self]
        return CachedURLSession(
            configuration: .init(
                ttl: 60,
                session: URLSession(configuration: config),
                allowStaleOnError: true,
                cacheNamespace: namespace,
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
    private var storage: [String] = []

    func append(_ line: String) {
        lock.lock()
        storage.append(line)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
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
