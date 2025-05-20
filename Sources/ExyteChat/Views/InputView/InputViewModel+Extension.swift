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
    
    // Add this new method
    @MainActor
    func processLanguageChangeConfirmation() async {
        // The language in self.transcriber (DefaultTranscriberPresenter) has already been updated
        // by its own changeLanguage(toLocale:) method, which also re-initialized the Transcriber actor.
        // That method also handles calling reTranscribeAudio if appropriate (i.e., if not live recording and lastRecordingURL exists).
        
        // Here, we primarily need to update the InputViewModel's state based on the presenter's new state.
        
        DebugLogger.log("InputViewModel: Processing language change confirmation.")
        
        // Update UI to reflect potential re-transcription start (if presenter initiated it)
        // or to clear old results if re-transcription won't happen.
        
        // Show "processing" if the presenter is now re-transcribing.
        // This requires adding an `isReTranscribing` state to DefaultTranscriberPresenter or inferring.
        // For now, we'll directly update based on the presenter's `transcribedText` and `error` after it attempts re-transcription.
        
        if let currentError = self.transcriber.error {
            self.asrErrorMessage = currentError.localizedDescription
            self.transcribedText = "" // Clear previous text
            // Update phase to show the error or an empty state.
            // If asrErrorMessage is set, ASRResultView shows it.
            self.weChatRecordingPhase = .asrCompleteWithText("") // Keep showing the bubble for the error
            DebugLogger.log("InputViewModel: Re-transcription resulted in error: \(currentError.localizedDescription)")
        } else {
            let newText = self.transcriber.transcribedText // Get potentially new text from presenter
            self.transcribedText = newText
            self.currentlyEditingASRText = newText // Sync editing buffer
            self.asrErrorMessage = nil // Clear any previous error message
            
            if self.attachments.recording?.url != nil { // If there was an audio to re-transcribe
                // If newText is empty after re-transcription, it might mean no speech or unmatchable.
                if newText.isEmpty {
                    self.asrErrorMessage = "100" // "Unable to recognize words"
                    self.weChatRecordingPhase = .asrCompleteWithText("")
                    DebugLogger.log("InputViewModel: Re-transcription resulted in empty text.")
                } else {
                    self.weChatRecordingPhase = .asrCompleteWithText(newText)
                    DebugLogger.log("InputViewModel: Re-transcription successful. New text: \(newText)")
                }
            } else {
                // No audio was re-transcribed (e.g., language changed before any recording).
                // Just ensure UI is clean for the new language.
                self.weChatRecordingPhase = .idle // Or .asrCompleteWithText("") if bubble should stay for some reason
                DebugLogger.log("InputViewModel: Language changed, no audio processed. UI reset.")
            }
        }
        
        // The bubble height will be recalculated by WeChatRecordingOverlayView's .onChange(of: weChatRecordingPhase)
        // or .onChange(of: transcribedText) in WechatRecordingIndicator.
    }
    
    @MainActor
    func startEditingASRText() {
        guard case .asrCompleteWithText(let textToShow) = self.weChatRecordingPhase, self.asrErrorMessage == nil else {
            DebugLogger.log("startEditingASRTextInOverlay: Not in .asrCompleteWithText phase or ASR had an error.")
            return
        }
        self.text = textToShow // Populate the main input field
        if self.editingASRTextCount == 0 {
            self.currentlyEditingASRText = textToShow // Initialize editing text
        }
        self.isEditingASRTextInOverlay = true      // Set the flag
        self.editingASRTextCount += 1              
        DebugLogger.log("startEditingASRTextInOverlay: Edit mode enabled. Initial text: \"\(textToShow)\". Requesting focus for overlay editor.")
        self.isASROverlayEditorFocused = true       // Request focus
    }
    
    @MainActor
    func confirmASRTextAndSend() {
        // Use the text from currentlyEditingASRText if available
        if self.currentlyEditingASRText.isEmpty {
            text = transcribedText
        } else {
            text = currentlyEditingASRText
            transcribedText = currentlyEditingASRText
        }
        self.attachments.recording = nil // Discard original voice
        
        DebugLogger.log("confirmASREditAndSend: Text set to \"\(self.text)\". Original voice discarded. Preparing to send.")
        
        // Reset states and send
        self.isEditingASRTextInOverlay = false
        self.editingASRTextCount = 0
        self.isASROverlayEditorFocused = false
        self.weChatRecordingPhase = .idle // This will hide the overlay
        send() // Calls didSendMessage and then reset()
    }
    
    // This action is called from BottomControlsView when "Cancel" is tapped
    // or from WeChatRecordingOverlayView when tapping the background during edit.
    @MainActor
    func endASREditSession(discardChanges: Bool = false) {
        DebugLogger.log("endASROverlayEditSession called. Discard changes: \(discardChanges)")
        isASROverlayEditorFocused = false // This should trigger the TextEditor to lose focus
        isEditingASRTextInOverlay = false // Explicitly exit editing mode
        
        if discardChanges {
            // If discarding, revert currentlyEditingASRText to the original transcribed text
            // This is if the user "cancels" the edit but not the whole ASR result.
            // Your current "Cancel" button calls .deleteRecord which is more destructive.
            // This function is more for when focus is lost.
            if case .asrCompleteWithText(let originalText) = self.weChatRecordingPhase {
                currentlyEditingASRText = originalText
            }
        } else {
            // If not discarding (e.g. focus lost but might re-focus),
            // currentlyEditingASRText retains its value for now.
            // The send action will use currentlyEditingASRText if isEditingASRTextInOverlay was true.
        }
    }
    
    // If user taps "Send Voice" button in BottomControlsView while editing ASR (or just viewing ASR)
    @MainActor
    func sendVoiceFromASRResult() {
        DebugLogger.log("sendVoiceFromASROverlay: Sending original voice.")
        // Text is ignored, only the recording is sent.
        self.text = "" // Clear any potentially edited text if we're sending voice.
        self.isEditingASRTextInOverlay = false
        self.isASROverlayEditorFocused = false
        // The self.attachments.recording should still hold the original recording
        self.weChatRecordingPhase = .idle
        send() // send() will pick up self.attachments.recording
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
        if  transcriber.isRecording {
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
                            
                            if let url = finalURL, let presenterDuration = self.transcriber.audioDuration {
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
                                if let error = self.transcriber.error { // Check for transcriber error first
                                    self.asrErrorMessage = error.localizedDescription // Or a user-friendly message
                                    self.transcribedText = ""
                                    self.weChatRecordingPhase = .asrCompleteWithText("")
                                    DebugLogger.log("Transcriber finished with intent .convertToText but with an error. Phase: asrCompleteWithText(\"\"). Error: \(error.localizedDescription)")
                                } else if finalText.isEmpty {
                                    self.asrErrorMessage = "100" // Example, make this localizable
                                    self.transcribedText = ""
                                    self.weChatRecordingPhase = .asrCompleteWithText("")
                                    DebugLogger.log("Transcriber finished with intent .convertToText but no text recognized. Phase: asrCompleteWithText(\"\").")
                                } else {
                                    self.transcribedText = finalText
                                    self.asrErrorMessage = nil
                                    self.weChatRecordingPhase = .asrCompleteWithText(finalText)
                                    DebugLogger.log("Transcriber finished with intent .convertToText. Phase: asrCompleteWithText. Text: \(finalText)")
                                }
                            } else if self.currentRecordingIntent == .sendAudioOnly {
                                // For sendAudioOnly, the state is already .hasRecording (if audio is valid).
                                // The weChatRecordingPhase will be reset to .idle by the send() -> sendMessage() -> reset() flow.
                                // No specific phase change needed here, as send() will take over.
                                DebugLogger.log("Transcriber finished with intent .sendAudioOnly. State should be .hasRecording.")
                            } else { // .none (e.g., transcriber stopped due to silence)
                                if finalText.isEmpty {
                                    self.asrErrorMessage = "100" // Or a generic "No speech detected"
                                    self.transcribedText = ""
                                    self.weChatRecordingPhase = .asrCompleteWithText("")
                                } else {
                                    self.transcribedText = finalText
                                    self.asrErrorMessage = nil
                                    self.weChatRecordingPhase = .asrCompleteWithText(finalText)
                                }
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
