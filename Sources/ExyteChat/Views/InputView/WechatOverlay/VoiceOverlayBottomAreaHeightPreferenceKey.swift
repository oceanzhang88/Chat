//
//  VoiceOverlayBottomAreaHeightPreferenceKey.swift
//  Chat
//
//  Created by Yangming Zhang on 5/12/25.
//


// Chat/Sources/ExyteChat/Views/VoiceOverlayBottomAreaHeightPreferenceKey.swift
import SwiftUI

struct VoiceOverlayBottomAreaHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue()) // Take the maximum height reported
    }
}
struct CancelRectPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct ConvertToTextRectPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
