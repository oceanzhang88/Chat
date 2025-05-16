//
//  InputViewModel+Ext.swift
//  Chat
//
//  Created by Yangming Zhang on 5/16/25.
//
// In Chat/Sources/ExyteChat/Views/InputView/InputViewModel.swift
import Foundation
import Combine
import ExyteMediaPicker // Assuming Media is from here
import GiphyUISDK // Assuming GPHMedia is from here
import Speech // <--- ADD THIS LINE


// Transcriber
extension InputViewModel {
    
}

// ASR + Audio Recording
extension InputViewModel {
    
    func setRecorderSettings(recorderSettings: RecorderSettings = RecorderSettings()) {
        Task {
            await self.recorder.setRecorderSettings(recorderSettings)
        }
    }

    
    func recordAudio() async {
        if await recorder.isRecording {
            DebugLogger.log("recordAudio() called, but recorder is already recording.")
            return
        }
        DebugLogger.log("recordAudio() attempting to start new recording (permission should be granted).")

        await MainActor.run {
            self.attachments.recording = Recording() // Initialize with empty recording
        }

        let url = await recorder.startRecording { duration, samples in
            DispatchQueue.main.async { [weak self] in
                self?.attachments.recording?.duration = duration
                self?.attachments.recording?.waveformSamples = samples
            }
        }

        await MainActor.run {
            if let recordingUrl = url {
                self.attachments.recording?.url = recordingUrl
                self.weChatRecordingPhase = .recording // Set the WeChat specific phase
                DebugLogger.log("recordAudio() successfully started. URL: \(recordingUrl.absoluteString). Current weChatRecordingPhase: \(self.weChatRecordingPhase).")
            } else {
                DebugLogger.log("recordAudio() failed to start (url is nil). Resetting.")
                self.attachments.recording = nil
                self.state = .empty // Main state
                self.weChatRecordingPhase = .idle // WeChat phase
            }
        }
    }

    // Placeholder for actual STT logic (Phase 3)
    func performSpeechToText() async {
        guard let recording = self.attachments.recording, let audioURL = recording.url else {
            DebugLogger.log("performSpeechToText: No valid recording URL.")
            await MainActor.run {
                self.asrErrorMessage = "No audio to transcribe." // TODO: Localize
                self.weChatRecordingPhase = .asrCompleteWithText("") // Use empty string to signify error for button layout
            }
            return
        }

        DebugLogger.log("Starting STT for: \(audioURL.lastPathComponent)")
        
        // ***** START OF ACTUAL STT IMPLEMENTATION (EXAMPLE WITH SFSpeechRecognizer) *****
        // This is a simplified example. You'll need more robust error handling,
        // permission checks (though `recordAudio` should handle initial mic permission),
        // and potentially UI for STT permission if not covered by mic permission.

        // On-device STT (iOS 10+)
        // Ensure you have added `NSSpeechRecognitionUsageDescription` to your app's Info.plist
        // and requested SFSpeechRecognizer authorization if needed separately, though microphone
        // permission often covers STT for the audio captured.
        
        let recognizer = SFSpeechRecognizer() // Uses user's current locale by default
        guard let speechRecognizer = recognizer, speechRecognizer.isAvailable else {
            DebugLogger.log("STT: SFSpeechRecognizer not available.")
            await MainActor.run {
                self.asrErrorMessage = "Speech recognition is not available right now." // TODO: Localize
                self.weChatRecordingPhase = .asrCompleteWithText("")
            }
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        // request.shouldReportPartialResults = true // If you want live updates (more complex UI handling)

        speechRecognizer.recognitionTask(with: request) { [weak self] (result, error) in
            guard let self = self else { return }
            
            Task { @MainActor in // Ensure UI updates are on the main thread
                if let error = error {
                    DebugLogger.log("STT Error: \(error.localizedDescription)")
                    self.asrErrorMessage = error.localizedDescription // Or a more user-friendly message
                    self.weChatRecordingPhase = .asrCompleteWithText("")
                    return
                }
                
                if let recognitionResult = result {
                    let bestTranscription = recognitionResult.bestTranscription.formattedString
                    DebugLogger.log("STT Success: \(bestTranscription)")
                    self.transcribedText = bestTranscription
                    self.asrErrorMessage = nil
                    self.weChatRecordingPhase = .asrCompleteWithText(bestTranscription)

                    if recognitionResult.isFinal {
                        // You might do final cleanup or logging here
                        DebugLogger.log("STT isFinal: true")
                    }
                } else if error == nil { // No result and no error typically means no speech detected
                     DebugLogger.log("STT: No speech detected or result is empty.")
                     self.transcribedText = "" // Explicitly empty
                     self.asrErrorMessage = nil // No error, just no text
                     self.weChatRecordingPhase = .asrCompleteWithText("") // Show buttons for empty result
                }
            }
        }
        // ***** END OF ACTUAL STT IMPLEMENTATION EXAMPLE *****
        
        // Keep the old mock logic commented out or remove if using real STT
        /*
        // Simulate STT processing
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds delay

        // Simulate success or failure
        let success = Bool.random()
        await MainActor.run {
            if success {
                let mockText = "This is a sample transcription of your voice message honey..."
                self.transcribedText = mockText
                self.asrErrorMessage = nil
                self.weChatRecordingPhase = .asrCompleteWithText(mockText)
                DebugLogger.log("STT Success: \(mockText)")
            } else {
                let mockError = "Speech recognition failed."
                self.asrErrorMessage = mockError
                // Decide if .hasRecording or .idle is better if STT fails but voice note exists
                self.weChatRecordingPhase = .asrCompleteWithText("") // Use empty string to signify error
                DebugLogger.log("STT Failed: \(mockError)")
            }
        }
        */
    }
    
    func startEditingASRText() {
        // Ensure we are in a state where editing makes sense
        guard case .asrCompleteWithText = self.weChatRecordingPhase, self.asrErrorMessage == nil else {
            DebugLogger.log("startEditingASRText: Not in a valid state to edit or ASR had an error.")
            return
        }

        self.text = self.transcribedText // Populate the main input field
        self.isEditingASRText = true
        // self.attachments.recording = nil // Decide: Do we discard voice immediately on edit, or on send of text?
                                        // Let's discard on send of text for now, to allow user to still send voice if they cancel edit.
        self.weChatRecordingPhase = .idle // This will hide the WeChatRecordingOverlayView

        DebugLogger.log("startEditingASRText: Switched to editing. Text: \(self.text)")
        // Notify WeChatInputView to switch to text mode and focus
//        NotificationCenter.default.post(name: .switchToTextInputAndFocus, object: self.inputFieldId)
    }
}

// Subscription
extension InputViewModel {

    func validateDraft() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.state != .editing, self.weChatRecordingPhase == .idle else { return } // Don't change state if editing or in WeChat gesture

            if !self.text.isEmpty || !self.attachments.medias.isEmpty || self.attachments.giphyMedia != nil {
                if self.state != .hasTextOrMedia { self.state = .hasTextOrMedia }
            } else if self.attachments.recording == nil { // Only go to empty if no recording either
                if self.state != .empty { self.state = .empty }
            }
            // If self.attachments.recording exists, state should be .hasRecording (set by stopRecordAudio)
        }
    }

    func subscribeValidation() {
        $attachments.sink { [weak self] _ in self?.validateDraft() }.store(in: &subscriptions)
        $text.sink { [weak self] _ in self?.validateDraft() }.store(in: &subscriptions)
    }

    func subscribeGiphyPicker() {
        $showGiphyPicker.sink { [weak self] value in if !value { self?.attachments.giphyMedia = nil } }.store(in: &subscriptions)
    }

    func subscribePicker() {
        $showPicker.sink { [weak self] value in if !value { self?.attachments.medias = [] } }.store(in: &subscriptions)
    }

    func subscribeRecordPlayer() {
        Task { @MainActor in
            if let recordingPlayer {
                recordPlayerSubscription = recordingPlayer.didPlayTillEnd
                    .sink { [weak self] in
                        guard let self = self else { return }
                        DebugLogger.log("Recording player didPlayTillEnd.")
                        // If it was playing as part of STT complete screen, revert to STT complete, not .hasRecording
                        if case .asrCompleteWithText(let text) = self.weChatRecordingPhase {
                            DebugLogger.log("Player finished, was in sttComplete. Staying in sttComplete.")
                            // Optionally, reset player UI within sttComplete (e.g., show play button again)
                        } else if self.state != .hasRecording { // Only if not already in hasRecording (e.g. if STT flow sets it differently)
                            self.state = .hasRecording
                        }
                        // For standard input view, this would set its internal state correctly.
                        // For WeChat overlay, the overlay's state should also reflect that playback stopped.
                        // This might require a more specific phase if the overlay is still visible.
                    }
            }
        }
    }

    func unsubscribeRecordPlayer() {
        recordPlayerSubscription?.cancel()
        recordPlayerSubscription = nil
    }
}

// Send message
extension InputViewModel {

    func sendMessage() {
        showActivityIndicator = true
        let draft = DraftMessage(
//            id: attachments.recording?.url?.lastPathComponent ?? UUID().uuidString, // Use recording name or new ID
            text: self.text,
            medias: attachments.medias,
            giphyMedia: attachments.giphyMedia,
            recording: attachments.recording, // This will be the final recording data
            replyMessage: attachments.replyMessage,
            createdAt: Date()
        )
        DebugLogger.log("sendMessage: Preparing to send DraftMessage. Text: '\(draft.text)', Recording duration: \(draft.recording?.duration ?? -1)")
        didSendMessage?(draft)

        DispatchQueue.main.async { [weak self] in
            self?.showActivityIndicator = false
            self?.reset() // Crucial: This resets all states including weChatRecordingPhase
        }
    }
}
