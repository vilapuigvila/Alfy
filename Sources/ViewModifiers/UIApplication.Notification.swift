//
//  File.swift
//  Alfy
//
//  Created by albert vila on 8/7/25.
//

import Foundation
import SwiftUI
import Combine

public enum AppLifecycleEvent {
    case didEnterBackground
    case willEnterForeground(Date)
}

struct AppLifecycleModifier: ViewModifier {
    let action: (AppLifecycleEvent) -> Void
    private let publisher = Publishers.Merge(
        NotificationCenter.default.publisher(
          for: UIApplication.didEnterBackgroundNotification
        ),
        NotificationCenter.default.publisher(
          for: UIApplication.willEnterForegroundNotification
        )
    )
    
    func body(content: Content) -> some View {
        content
            .onReceive(publisher) { notification in
                switch notification.name {
                case UIApplication.didEnterBackgroundNotification:
                    action(.didEnterBackground)
                case UIApplication.willEnterForegroundNotification:
                    action(.willEnterForeground(.init()))
                default:
                    break
                }
            }
    }
}

public extension View {
    /// Adds handlers for when the app goes to background or comes back to foreground.
    ///
    /// - Parameter action: closure called with `.didEnterBackground` or `.willEnterForeground(Date)`
    func onAppLifecycleEvent(_ action: @escaping (AppLifecycleEvent) -> Void) -> some View {
        modifier(AppLifecycleModifier(action: action))
    }
}
