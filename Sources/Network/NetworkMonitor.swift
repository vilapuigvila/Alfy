//
//  File.swift
//  Alfy
//
//  Created by albert vila on 4/7/25.
//

import Foundation
import Network
import Combine

public final class NetworkStatusMonitor {
    public var statusChanged: AnyPublisher<Bool, Never> {
        networkStatus
            .removeDuplicates()
            .share()
            .eraseToAnyPublisher()
    }
    
    private var _hasConnection: Bool = true
    public var hasConnection: Bool {
        monitorQueue.sync { _hasConnection }
    }
    private let networkStatus = PassthroughSubject<Bool, Never>()
    public private(set) var onWifi = true
    public private(set) var onCellular = true

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "AlfyNetworkStatusMonitor")
    
    public static let shared = NetworkStatusMonitor()
    
    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let connectionStatus = path.status == .satisfied
            self?._hasConnection = connectionStatus
            self?.networkStatus.send(connectionStatus)
            self?.onWifi = path.usesInterfaceType(.wifi)
            self?.onCellular = path.usesInterfaceType(.cellular)
        }
        pathMonitor.start(queue: monitorQueue)
    }
    
    public static func networkStatusChangedSubscription(_ statusUpdatedBlock: @escaping (Bool) -> Void) -> AnyCancellable {
       return shared.statusChanged
           .receive(on: DispatchQueue.main)
           .sink { hasConnection in
               statusUpdatedBlock(hasConnection)
           }
   }
}
