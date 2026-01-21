import Foundation

public final class RequestThrottleController {
    
    private var lastRequestDate: Date?
    private var extraRequestsRemaining = 0
    private var hasGrantedExtraRequests = false
    public let minimumInterval: TimeInterval
    public let extraRequestsLimit: Int
    
    public init(minimumInterval: TimeInterval, extraRequestsLimit: Int) {
        self.minimumInterval = minimumInterval
        self.extraRequestsLimit = extraRequestsLimit
    }
    
    public func startRequestIfAllowed(at date: Date) -> Bool {
        guard canStartRequest(at: date) else {
            return false
        }
        lastRequestDate = date
        return true
    }
    
    public func registerOutcome(isFailure: Bool) {
        guard isFailure else {
            extraRequestsRemaining = 0
            return
        }
        guard !hasGrantedExtraRequests else {
            return
        }
        extraRequestsRemaining = extraRequestsLimit
        hasGrantedExtraRequests = true
    }

    public func reset() {
        lastRequestDate = nil
        extraRequestsRemaining = 0
        hasGrantedExtraRequests = false
    }
    
    private func canStartRequest(at date: Date) -> Bool {
        if let lastRequestDate, date.timeIntervalSince(lastRequestDate) < minimumInterval {
            guard extraRequestsRemaining > 0 else {
                return false
            }
            extraRequestsRemaining -= 1
            return true
        }
        extraRequestsRemaining = 0
        hasGrantedExtraRequests = false
        return true
    }
}
