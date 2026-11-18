import XCTest
@testable import Alfy

final class CachedURLSessionTTLTests: XCTestCase {

    func testUnitsConvertToSeconds() {
        XCTAssertEqual(CachedURLSession.TTL.seconds(30).seconds, 30)
        XCTAssertEqual(CachedURLSession.TTL.minutes(5).seconds, 300)
        XCTAssertEqual(CachedURLSession.TTL.hours(3).seconds, 10_800)
        XCTAssertEqual(CachedURLSession.TTL.days(2).seconds, 172_800)
    }

    func testValuesUnderMinimumAreClampedToFiveSeconds() {
        XCTAssertEqual(CachedURLSession.TTL.clamped(0.05), 5)
        XCTAssertEqual(CachedURLSession.TTL.clamped(0), 5)
        XCTAssertEqual(CachedURLSession.TTL.clamped(4.9), 5)
        XCTAssertEqual(CachedURLSession.TTL.clamped(5), 5)
        XCTAssertEqual(CachedURLSession.TTL.clamped(60), 60)
    }

    func testUncheckedInitKeepsSubMinimumValue() {
        XCTAssertEqual(CachedURLSession.TTL(uncheckedSeconds: 0.05).seconds, 0.05)
    }

    func testRequestStampsTTLInSecondsOnURLRequest() throws {
        let request = try Requester.buildRequest(
            Requester.makeRequest("https://example.com/ttl").ttl(.minutes(5))
        )
        let stamped = URLProtocol.property(forKey: "AlfyCacheTTL", in: request) as? TimeInterval
        XCTAssertEqual(stamped, 300)
    }
}
