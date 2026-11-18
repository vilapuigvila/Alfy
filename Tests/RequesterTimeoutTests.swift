//
//  RequesterTimeoutTests.swift
//  Alfy
//

import XCTest
@testable import Alfy

final class RequesterTimeoutTests: XCTestCase {
    private let urlString = "https://example.com/data"

    /// Without `timeout(_:)` the URLRequest keeps URLSession's default of 60 seconds.
    func testTimeoutIsUntouchedByDefault() throws {
        let urlRequest = try Requester.buildRequest(Requester.makeRequest(urlString))
        XCTAssertEqual(urlRequest.timeoutInterval, 60)
    }

    func testTimeoutSetsTheURLRequestInterval() throws {
        let urlRequest = try Requester.buildRequest(
            Requester.makeRequest(urlString).timeout(15)
        )
        XCTAssertEqual(urlRequest.timeoutInterval, 15)
    }

    /// The builder is immutable: each modifier returns a copy, and the other settings survive.
    func testTimeoutKeepsTheOtherSettingsAndTheOriginalRequest() throws {
        let base = Requester.makeRequest(urlString).ttl(.seconds(300))
        let withTimeout = base.timeout(15).allowStaleOnError(false)

        XCTAssertNil(base.timeout)
        XCTAssertEqual(withTimeout.timeout, 15)
        XCTAssertEqual(withTimeout.ttl, .seconds(300))
        XCTAssertEqual(withTimeout.allowStaleOnError, false)
    }
}
