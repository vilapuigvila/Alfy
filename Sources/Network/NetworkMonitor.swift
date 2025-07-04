//
//  File.swift
//  Alfy
//
//  Created by albert vila on 4/7/25.
//

import Foundation
import Network
import Combine

/// A singleton that watches the current network path.
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "AlfyNetworkMonitorQueue")

    /// Latest known status
    private(set) var isConnected: Bool = false

    /// A Combine publisher if you want reactive updates:
    /// let publisher: AnyPublisher<Bool, Never>
    private let subject = PassthroughSubject<Bool, Never>()
    var publisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status == .satisfied
            self?.isConnected = status
            self?.subject.send(status)
        }
        monitor.start(queue: queue)
    }
}
