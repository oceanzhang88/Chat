//
//  ChatLocalization.swift
//  Chat
//
//  Created by Aman Kumar on 18/12/24.
//

import Foundation

public struct ChatLocalization: Hashable {
    public var inputPlaceholder: String
    public var signatureText: String
    public var cancelButtonText: String
    public var recentToggleText: String
    public var waitingForNetwork: String
    public var recordingText: String
    public var replyToText: String
    public var holdToTalkText:  String
    public var releaseToSendText: String // Added this line
    public var releaseToCancelText: String // <<<< ADDED THIS LINE
    public var convertToTextButton: String
    public var tapToEditText: String // New
    public var sendVoiceButtonText: String // New
    
    public init(
        inputPlaceholder: String,
        signatureText: String,
        cancelButtonText: String,
        recentToggleText: String,
        waitingForNetwork: String,
        recordingText: String,
        replyToText: String,
        holdToTalkText: String,
        releaseToSendText: String,
        releaseToCancelText: String, // <<<< ADDED THIS PARAMETER,
        convertToTextButton: String, // Add as parameter
        tapToEditText: String, // New
        sendVoiceButtonText: String // New
    ) {
        self.inputPlaceholder = inputPlaceholder
        self.signatureText = signatureText
        self.cancelButtonText = cancelButtonText
        self.recentToggleText = recentToggleText
        self.waitingForNetwork = waitingForNetwork
        self.recordingText = recordingText
        self.replyToText = replyToText
        self.holdToTalkText = holdToTalkText
        self.releaseToSendText = releaseToSendText // Initialize the new property
        self.releaseToCancelText = releaseToCancelText // <<<< INITIALIZE NEW PROPERTY
        self.convertToTextButton = convertToTextButton
        self.tapToEditText = tapToEditText // Initialize
        self.sendVoiceButtonText = sendVoiceButtonText // Initialize
    }
}
