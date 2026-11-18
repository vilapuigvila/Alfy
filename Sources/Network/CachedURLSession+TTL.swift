import Foundation

extension CachedURLSession {
    /// Cache lifetime with an explicit unit. Anything under 5 s is raised to 5 s (asserts in debug).
    public struct TTL: Hashable, Sendable {
        public static let minimum: TimeInterval = 5

        public let seconds: TimeInterval

        public static func seconds(_ value: Double) -> TTL { checked(value) }
        public static func minutes(_ value: Double) -> TTL { checked(value * 60) }
        public static func hours(_ value: Double) -> TTL { checked(value * 3_600) }
        public static func days(_ value: Double) -> TTL { checked(value * 86_400) }

        /// Tests only: no minimum, no assert.
        init(uncheckedSeconds: TimeInterval) {
            self.seconds = uncheckedSeconds
        }

        /// Raises values under `minimum` to `minimum`, without asserting.
        static func clamped(_ seconds: TimeInterval) -> TimeInterval {
            max(seconds, minimum)
        }

        private static func checked(_ seconds: TimeInterval) -> TTL {
            if seconds < minimum {
                assertionFailure("TTL must be at least \(Int(minimum)) seconds")
            }
            return TTL(uncheckedSeconds: clamped(seconds))
        }
    }
}
