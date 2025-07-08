//
//  File.swift
//  Alfy
//
//  Created by albert vila on 8/7/25.
//

import SwiftUI

private struct OnAppearWithPreviousModifier: ViewModifier {
    @State private var lastDate: Date?

    /// - parameter action: currentDate is `Date()` now; previousDate is the stored timestamp (or nil on first fire)
    let action: (_ previousDate: Date) -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            action(lastDate ?? Date())
            lastDate = Date()
        }
    }
}

extension View {
    /// Calls your closure with (currentDate, previousDate) whenever this view appears.
    public func onAppear(action: @escaping (_ sinceLastShown: Date) -> Void) -> some View {
        modifier(OnAppearWithPreviousModifier(action: action))
    }
}
