import XCTest
@testable import Alfy

final class RequestThrottleControllerTests: XCTestCase {
    func testCanStartRequestAllowsFirstRequest() {
        let controller = makeSut()
        let startDate = Date(timeIntervalSince1970: 1_000)
        
        let canStart = controller.startRequestIfAllowed(at: startDate)
        
        XCTAssertTrue(canStart)
    }
    
    func testCanStartRequestBlocksWithinIntervalWithoutExtraRequests() {
        let controller = makeSut()
        let startDate = Date(timeIntervalSince1970: 1_000)
        
        var canStart = controller.startRequestIfAllowed(at: startDate)
        XCTAssertTrue(canStart)
        
        let secondDate = startDate.addingTimeInterval(30)
        canStart = controller.startRequestIfAllowed(at: secondDate)
        XCTAssertFalse(canStart)
    }
    
    func testCanStartRequestAllowsExtraRequestsAfterFailure() {
        let controller = makeSut()
        let startDate = Date(timeIntervalSince1970: 1_000)
        
        var canStart = controller.startRequestIfAllowed(at: startDate)
        XCTAssertTrue(canStart)
        controller.registerOutcome(
            isFailure: true
        )
        
        let secondDate = startDate.addingTimeInterval(10)
        canStart = controller.startRequestIfAllowed(at: secondDate)
        XCTAssertTrue(canStart)
        
        let thirdDate = startDate.addingTimeInterval(20)
        canStart = controller.startRequestIfAllowed(at: thirdDate)
        XCTAssertTrue(canStart)
        
        let fourthDate = startDate.addingTimeInterval(30)
        canStart = controller.startRequestIfAllowed(at: fourthDate)
        XCTAssertFalse(canStart)
    }
    
    func testCanStartRequestGrantsExtraRequestsAgainAfterIntervalReset() {
        let controller = makeSut()
        let startDate = Date(timeIntervalSince1970: 1_000)
        
        var canStart = controller.startRequestIfAllowed(at: startDate)
        XCTAssertTrue(canStart)
        
        controller.registerOutcome(
            isFailure: true
        )
        
        let firstExtraDate = startDate.addingTimeInterval(10)
        canStart = controller.startRequestIfAllowed(at: firstExtraDate)
        
        XCTAssertTrue(canStart)
        
        let secondExtraDate = startDate.addingTimeInterval(20)
        canStart = controller.startRequestIfAllowed(at: secondExtraDate)
        XCTAssertTrue(canStart)
        
        let resetDate = secondExtraDate.addingTimeInterval(61)
        canStart = controller.startRequestIfAllowed(at: resetDate)
        XCTAssertTrue(canStart)
        
        controller.registerOutcome(
            isFailure: true
        )
        
        let newExtraDate = resetDate.addingTimeInterval(10)
        canStart = controller.startRequestIfAllowed(at: newExtraDate)
        XCTAssertTrue(canStart)
    }

    func testResetClearsThrottleState() {
        let controller = makeSut()
        let startDate = Date(timeIntervalSince1970: 1_000)

        var canStart = controller.startRequestIfAllowed(at: startDate)
        XCTAssertTrue(canStart)

        controller.registerOutcome(isFailure: true)

        let blockedDate = startDate.addingTimeInterval(30)
        canStart = controller.startRequestIfAllowed(at: blockedDate)
        XCTAssertTrue(canStart)

        controller.reset()

        let resetDate = startDate.addingTimeInterval(40)
        canStart = controller.startRequestIfAllowed(at: resetDate)
        XCTAssertTrue(canStart)

        let withinIntervalDate = resetDate.addingTimeInterval(10)
        canStart = controller.startRequestIfAllowed(at: withinIntervalDate)
        XCTAssertFalse(canStart)

        controller.registerOutcome(isFailure: true)

        let firstExtraDate = withinIntervalDate.addingTimeInterval(10)
        canStart = controller.startRequestIfAllowed(at: firstExtraDate)
        XCTAssertTrue(canStart)

        let secondExtraDate = firstExtraDate.addingTimeInterval(10)
        canStart = controller.startRequestIfAllowed(at: secondExtraDate)
        XCTAssertTrue(canStart)

        let thirdExtraDate = secondExtraDate.addingTimeInterval(10)
        canStart = controller.startRequestIfAllowed(at: thirdExtraDate)
        XCTAssertFalse(canStart)
    }
    
    private func makeSut() -> RequestThrottleController {
        RequestThrottleController(
            minimumInterval: 60,
            extraRequestsLimit: 2
        )
    }
}
