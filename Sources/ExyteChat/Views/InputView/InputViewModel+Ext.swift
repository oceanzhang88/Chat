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
    // Function to start monitoring transcriber for live UI updates
    func startTranscriberMonitoring() {
        stopTranscriberMonitoring() // Ensure no previous monitors are running

        guard transcriber.isRecording else {
            DebugLogger.log("startTranscriberMonitoring: Transcriber is not recording. Not starting monitor.")
            return
        }
        DebugLogger.log("startTranscriberMonitoring: Starting to monitor transcriber activity.")

        // Initialize/reset recording attachment for live updates
        self.attachments.recording = Recording(duration: 0, waveformSamples: [])
        self.transcriberRecordingStartTime = Date()

//        // Monitor isRecording state of the transcriber
//        transcriberIsRecordingSubscription = transcriber.$isRecording
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] isRecordingActive in
//                if !isRecordingActive {
//                    self?.stopTranscriberMonitoring()
//                    DebugLogger.log("startTranscriberMonitoring: Transcriber stopped recording (observed via publisher). Finalizing attachment URL.")
//                    if let finalURL = self?.transcriber.lastRecordingURL {
//                        self?.attachments.recording?.url = finalURL
//                         if let finalDuration = self?.transcriber.audioDuration { // If presenter has final duration
//                            self?.attachments.recording?.duration = finalDuration
//                        }
//                        DebugLogger.log("Transcriber auto-stopped or stopped externally. Finalized URL: \(finalURL.path).")
//                        // Update main state if necessary, e.g., if it wasn't part of a send/STT action
//                        if (self?.weChatRecordingPhase == .recording || self?.state == .isRecordingHold || self?.state == .isRecordingTap) && self?.attachments.recording?.url != nil {
//                             self?.state = .hasRecording
//                        }
//                    } else {
//                        DebugLogger.log("Transcriber stopped but no URL. Resetting attachment.")
//                        self?.attachments.recording = nil
//                    }
//                }
//            }
//
//        // Monitor RMS Level from DefaultTranscriberPresenter
//        transcriberRmsLevelSubscription = transcriber.$rmsLevel
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] rms in
//                guard let self = self, self.transcriber.isRecording else { return }
//                // Append or update waveform samples
//                // A more sophisticated waveform might average/downsample or keep a rolling window
//                self.attachments.recording?.waveformSamples.append(CGFloat(rms))
//                if (self.attachments.recording?.waveformSamples.count ?? 0) > 150 { // Example: Keep last 150 samples
//                    self.attachments.recording?.waveformSamples.removeFirst( (self.attachments.recording?.waveformSamples.count ?? 150) - 150)
//                }
//            }
//
//        // Timer for duration
//        transcriberDurationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
//            guard let self = self, self.transcriber.isRecording, let startTime = self.transcriberRecordingStartTime else {
//                self?.stopTranscriberMonitoring() // Stop if transcriber stopped or startTime is nil
//                return
//            }
//            self.attachments.recording?.duration = Date().timeIntervalSince(startTime)
//        }
    }

    // Function to stop monitoring
    func stopTranscriberMonitoring() {
        DebugLogger.log("stopTranscriberMonitoring: Stopping all transcriber monitors.")
        transcriberIsRecordingSubscription?.cancel()
        transcriberIsRecordingSubscription = nil
        transcriberRmsLevelSubscription?.cancel()
        transcriberRmsLevelSubscription = nil
        transcriberDurationTimer?.invalidate()
        transcriberDurationTimer = nil
        transcriberRecordingStartTime = nil
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

// ASR + Audio Recording
extension InputViewModel {
    
    func setRecorderSettings(recorderSettings: RecorderSettings = RecorderSettings()) {
        Task {
            await self.recorder.setRecorderSettings(recorderSettings)
        }
    }

    func recordAudio(type: RecorderType) async {
        if type == .simple {
            if await recorder.isRecording {
                DebugLogger.log("recordAudio() called, but recorder is already recording.")
                return
            }
        } else if type == .transcriber {
            if await transcriber.isRecording {
                DebugLogger.log("recordAudio() called, but recorder is already recording.")
                return
            }
        }

        DebugLogger.log("recordAudio() attempting to start new recording (permission should be granted).")

        await MainActor.run {
            self.attachments.recording = Recording() // Initialize with empty recording
        }
        
        var url: URL? = nil
        
        if type == .simple {
            url = await recorder.startRecording { duration, samples in
                DispatchQueue.main.async { [weak self] in
                    self?.attachments.recording?.duration = duration
                    self?.attachments.recording?.waveformSamples = samples
                }
            }
        } else if type == .transcriber {
            // Get url, keep updating duration and samples
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
