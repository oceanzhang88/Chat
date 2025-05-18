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
import Speech 


// Transcriber
extension InputViewModel {

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

// ASR + Audio Recording
extension InputViewModel {
    
    func setRecorderSettings(recorderSettings: RecorderSettings = RecorderSettings()) {
        Task {
            await self.recorder.setRecorderSettings(recorderSettings)
        }
    }

    func recordAudio(type: RecorderType) async {
        // Stop any ongoing recording/transcription first to ensure clean state
        if await recorder.isRecording {
            DebugLogger.log("recordAudio: Simple recorder was active, stopping it.")
            _ = await recorder.stopRecording() // Stop simple recorder
        }
        if await transcriber.isRecording {
            DebugLogger.log("recordAudio: Transcriber was active, stopping it.")
            await transcriber.stopRecording() // Stop transcriber
        }
        
        // Reset attachments for the new recording session
        await MainActor.run {
            self.attachments.recording = Recording()
            self.transcribedText = ""
            self.asrErrorMessage = nil
        }

        if type == .simple {
            DebugLogger.log("recordAudio: Starting simple recorder.")
            let url = await recorder.startRecording { duration, samples in
                DispatchQueue.main.async { [weak self] in
                    self?.attachments.recording?.duration = duration
                    self?.attachments.recording?.waveformSamples = samples
                }
            }
            await MainActor.run {
                if let recordingUrl = url {
                    self.attachments.recording?.url = recordingUrl
                    self.state = .isRecordingHold // Or appropriate state
                    self.weChatRecordingPhase = .recording
                    DebugLogger.log("recordAudio (simple) successfully started. URL: \(recordingUrl.absoluteString).")
                } else {
                    DebugLogger.log("recordAudio (simple) failed to start.")
                    self.attachments.recording = nil
                    self.state = .empty
                    self.weChatRecordingPhase = .idle
                }
            }
        } else if type == .transcriber {
            DebugLogger.log("recordAudio: Starting transcriber with progress.")
            await MainActor.run { // Ensure state updates are on main actor before async call
                self.state = .isRecordingHold // Or a specific .isTranscribing state
                self.weChatRecordingPhase = .recording // Or a specific .transcribing phase
            }
            do {
                try await transcriber.startRecordingWithProgress { duration, samples, currentText in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.attachments.recording?.duration = duration
                            let amplifiedSamples = samples.map { $0 * 10.0 }
                            self.attachments.recording?.waveformSamples = amplifiedSamples
                            self.transcribedText = currentText
                        }
                    }
                    completionHandler: { finalText, finalURL in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.transcribedText = finalText
                            self.attachments.recording?.url = finalURL
                            
                            if let url = finalURL, let presenterDuration = await self.transcriber.audioDuration {
                                self.attachments.recording?.duration = presenterDuration
                            } else if finalURL == nil && !finalText.isEmpty { // Transcription succeeded but maybe audio saving failed
                                self.attachments.recording?.duration = Date().timeIntervalSince(self.transcriber.recordingStartTime ?? Date())
                            }


                            if self.attachments.recording?.url != nil && (self.attachments.recording?.duration ?? 0) > 0.1 {
                                self.state = .hasRecording
                            } else if !finalText.isEmpty {
                                 self.state = .hasTextOrMedia // Has text, but recording might be invalid/short
                                 if self.attachments.recording?.url == nil { self.attachments.recording = nil } // Clear invalid recording
                            } else {
                                self.state = .empty
                                self.attachments.recording = nil
                            }
                            
                            if self.currentRecordingIntent == .convertToText {
                                self.weChatRecordingPhase = .asrCompleteWithText(finalText)
                                DebugLogger.log("Transcriber finished with intent .convertToText. Phase: asrCompleteWithText. Text: \(finalText)")
                            } else if self.currentRecordingIntent == .sendAudioOnly {
                                // For sendAudioOnly, the state is already .hasRecording (if audio is valid).
                                // The weChatRecordingPhase will be reset to .idle by the send() -> sendMessage() -> reset() flow.
                                // No specific phase change needed here, as send() will take over.
                                DebugLogger.log("Transcriber finished with intent .sendAudioOnly. State should be .hasRecording.")
                            } else { // .none (e.g., transcriber stopped due to silence)
                                self.weChatRecordingPhase = .asrCompleteWithText(finalText) // Default to showing ASR results
                                DebugLogger.log("Transcriber finished with intent .none. Phase: asrCompleteWithText. Text: \(finalText)")
                            }
                            self.currentRecordingIntent = .none // Reset intent for the next operation
                        }
                    }
                
                // If startRecordingWithProgress returns successfully, DefaultTranscriberPresenter.isRecording is true
                DebugLogger.log("recordAudio (transcriber) successfully initiated.")
            } catch {
                DebugLogger.log("recordAudio (transcriber) failed to start: \(error.localizedDescription)")
                await MainActor.run {
                    self.attachments.recording = nil
                    self.state = .empty
                    self.weChatRecordingPhase = .idle
                    self.asrErrorMessage = error.localizedDescription
                }
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

//    func subscribeValidation() {
//        $attachments.sink { [weak self] _ in self?.validateDraft() }.store(in: &subscriptions)
//        $text.sink { [weak self] _ in self?.validateDraft() }.store(in: &subscriptions)
//    }
//
//    func subscribeGiphyPicker() {
//        $showGiphyPicker.sink { [weak self] value in if !value { self?.attachments.giphyMedia = nil } }.store(in: &subscriptions)
//    }
//
//    func subscribePicker() {
//        $showPicker.sink { [weak self] value in if !value { self?.attachments.medias = [] } }.store(in: &subscriptions)
//    }

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
