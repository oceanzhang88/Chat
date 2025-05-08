//
//  InputBarStyle.swift
//  Chat
//
//  Created by Yangming Zhang on 5/8/25.
//


import Foundation

/// Defines the visual style and interaction model for the input bar presented by ChatView.
public enum InputBarStyle: Sendable {
    /// Default style with distinct buttons for attachments, camera, mic, etc.
    /// Recording is typically initiated via tap-and-hold or tap-to-lock on the microphone icon.
    case `default`

    /// WeChat-style layout with a mic/keyboard toggle button on the left,
    /// a central area that switches between text input and a "Hold to Talk" button,
    /// and Emoji/Add buttons on the right.
    /// Recording is initiated via long-press on the "Hold to Talk" button.
    case weChat
}
