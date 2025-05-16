// In Chat/Sources/ExyteChat/Views/InputView/InputViewModel.swift
import Foundation
import Combine
import ExyteMediaPicker // Assuming Media is from here
import GiphyUISDK // Assuming GPHMedia is from here
import Speech // <--- ADD THIS LINE

// ADD this enum:
public enum WeChatRecordingPhase: Sendable, Equatable { // Make it Equatable for @Published
    case idle
    case recording // Standard hold-to-talk recording
    case draggingToCancel
    case draggingToConvertToText
    case processingASR // Speech-to-text is in progress
    case asrCompleteWithText(String) // Store transcribed text here
//    case sttError(String) // Optional: for specific STT error messages
}

@MainActor
final class InputViewModel: ObservableObject {

    @Published var text = ""
    @Published var attachments = InputViewAttachments()
    @Published var transcribedText: String = "" // For STT result
    @Published var asrErrorMessage: String? = nil // For STT errors
    @Published var isEditingASRText: Bool = false
    @Published var showGiphyPicker = false
    @Published var showPicker = false
    @Published var mediaPickerMode = MediaPickerMode.photos
    @Published var showActivityIndicator = false
    @Published var shouldHideMainInputBar: Bool = false // NEW PROPERTY
    
    // Existing state for general input view status
    @Published var state: InputViewState = .empty {
        didSet {
            if oldValue != state {
                DebugLogger.log("InputViewState changed from \(oldValue) to \(state)")
            }
        }
    }
    // New WeChat-specific phase for detailed gesture interaction
    @Published var weChatRecordingPhase: WeChatRecordingPhase = .idle {
        didSet {
            if oldValue != weChatRecordingPhase {
                DebugLogger.log("WeChatRecordingPhase changed from \(oldValue) to \(weChatRecordingPhase)")
            }
            // This property controls the visibility of WeChatRecordingOverlayView
            let shouldShowOverlay = (
                weChatRecordingPhase != .idle &&
                weChatRecordingPhase != .asrCompleteWithText("") // Check against empty string in case of default value
                // Add other conditions if STT success/error states should also hide the mic input part of overlay
            )

            if isRecordingAudioForOverlay != shouldShowOverlay {
                isRecordingAudioForOverlay = shouldShowOverlay
            }
            
            // Control main ChatView input bar visibility based on overlay's active phases
            let newShouldHideMainInputBar = weChatRecordingPhase == .asrCompleteWithText("")
            if self.shouldHideMainInputBar != newShouldHideMainInputBar {
                self.shouldHideMainInputBar = newShouldHideMainInputBar
                DebugLogger.log("shouldHideMainInputBar changed to \(self.shouldHideMainInputBar)")
            }
        }
    }
    @Published var isRecordingAudioForOverlay: Bool = false {
        didSet {
            if oldValue != isRecordingAudioForOverlay {
                DebugLogger.log("isRecordingAudioForOverlay changed from \(oldValue) to \(isRecordingAudioForOverlay)")
            }
        }
    }
    @Published var isDraggingInCancelZoneOverlay: Bool = false {
        didSet {
            if oldValue != isDraggingInCancelZoneOverlay {
                DebugLogger.log("isDraggingInCancelZoneOverlay changed from \(oldValue) to \(isDraggingInCancelZoneOverlay)")
            }
        }
    }
    // ADD this for "Convert to Text" zone:
    @Published var isDraggingToConvertToTextZoneOverlay: Bool = false {
        didSet {
            if oldValue != isDraggingToConvertToTextZoneOverlay {
                 DebugLogger.log("isDraggingToConvertToTextZoneOverlay changed to \(isDraggingToConvertToTextZoneOverlay)")
            }
        }
    }
    @Published var cancelRectGlobal: CGRect = .zero {
        didSet {
            // Optional: log when it changes if still debugging
            DebugLogger.log("InputViewModel: cancelRectGlobal updated to \(cancelRectGlobal)")
        }
    }
    @Published var convertToTextRectGlobal: CGRect = .zero {
        didSet {
            DebugLogger.log("InputViewModel: convertToTextRectGlobal updated to \(convertToTextRectGlobal)")
        }
    }

    var recordingPlayer: RecordingPlayer?
    var didSendMessage: ((DraftMessage) -> Void)?
    
    private var recorder = Recorder() // Assuming Recorder is an actor
    private var saveEditingClosure: ((String) -> Void)?
    private var recordPlayerSubscription: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()

    func setRecorderSettings(recorderSettings: RecorderSettings = RecorderSettings()) {
        Task {
            await self.recorder.setRecorderSettings(recorderSettings)
        }
    }

    func onStart() {
        DebugLogger.log("onStart called. Current state: \(state)")
        subscribeValidation()
        subscribePicker()
        subscribeGiphyPicker()
    }

    func onStop() {
        DebugLogger.log("onStop called.")
        subscriptions.removeAll()
        if isRecordingAudioForOverlay { isRecordingAudioForOverlay = false }
        if isDraggingInCancelZoneOverlay { isDraggingInCancelZoneOverlay = false }
        if isDraggingToConvertToTextZoneOverlay { isDraggingToConvertToTextZoneOverlay = false }
        if weChatRecordingPhase != .idle { weChatRecordingPhase = .idle } // Ensure reset on stop
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

    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            DebugLogger.log("reset called. Current state before reset: \(self.state)")
            self.isEditingASRText = false // Add this
            self.showPicker = false
            self.showGiphyPicker = false
            self.text = ""
            self.saveEditingClosure = nil
            self.attachments = InputViewAttachments() // This should clear recordings too
            self.transcribedText = ""
            self.asrErrorMessage = nil
            self.weChatRecordingPhase = .idle
            self.isDraggingInCancelZoneOverlay = false
            self.isDraggingToConvertToTextZoneOverlay = false
            self.state = .empty
            self.subscribeValidation() // Re-subscribe if needed, or manage subscriptions more carefully
            DebugLogger.log("States after reset: mainState=\(self.state), weChatPhase=\(self.weChatRecordingPhase)")
        }
    }

    func send() {
        DebugLogger.log("send() called. Current state: \(state)")
        Task {
            // If we were in a recording phase, ensure it's properly stopped.
            if self.weChatRecordingPhase == .recording || self.state == .isRecordingHold || self.state == .isRecordingTap {
                DebugLogger.log("Send called while recording was active, stopping recorder first.")
                let recordingResult = await recorder.stopRecording() // Ensure recorder is stopped
                if let url = recordingResult.url, recordingResult.duration > 0.1 {
                     self.attachments.recording = Recording(duration: recordingResult.duration, waveformSamples: recordingResult.samples, url: url)
                     // self.state = .hasRecording // Main state indicates a recording is ready; sendMessage will handle this
                } else if self.text.isEmpty && self.attachments.medias.isEmpty {
                     // Only clear recording if nothing else to send
                     self.attachments.recording = nil
                }
                DebugLogger.log("Stopped recording via send. Duration: \(self.attachments.recording?.duration ?? 0)")
            }

            // If sending transcribed text, it should be in `self.text` by now.
            // If sending voice after STT, `self.text` might be empty and `self.attachments.recording` should be valid.

            if !self.text.isEmpty || !self.attachments.medias.isEmpty || (self.attachments.recording != nil && (self.attachments.recording?.duration ?? 0) > 0.1) || self.attachments.giphyMedia != nil {
                sendMessage() // This internally calls reset which should set phase to .idle
            } else {
                DebugLogger.log("Send called, but nothing to send. Cleaning up with deleteRecord logic.")
                // Effectively a cancel/cleanup if there's nothing valid to send
                self.inputViewActionInternal(.deleteRecord)
            }
        }
    }

    func edit(_ closure: @escaping (String) -> Void) {
        DebugLogger.log("edit() called. Text to edit: \(text)")
        saveEditingClosure = closure
        state = .editing
        weChatRecordingPhase = .idle // Ensure WeChat specific interactions are reset
    }

    func inputViewAction() -> (InputViewAction) -> Void {
        { [weak self] action in
            DebugLogger.log("inputViewAction() received action: \(action)")
            self?.inputViewActionInternal(action)
        }
    }

    private func inputViewActionInternal(_ action: InputViewAction) {
        switch action {
        case .giphy:
            showGiphyPicker = true
            weChatRecordingPhase = .idle
        case .photo:
            mediaPickerMode = .photos
            showPicker = true
            weChatRecordingPhase = .idle
        case .add:
            mediaPickerMode = .camera // Or your desired action for 'add'
            showPicker = true // Or handle differently
            weChatRecordingPhase = .idle
        case .camera:
            mediaPickerMode = .camera
            showPicker = true
            weChatRecordingPhase = .idle
        case .send:
            if self.isEditingASRText {
                self.attachments.recording = nil // Discard voice if text from ASR edit is sent
                self.isEditingASRText = false // Reset editing state
                DebugLogger.log("Sending edited ASR text, original voice recording discarded.")
            }
            send() // send() will handle recorder stop and state resets

        case .recordAudioHold:
            Task {
                let hasPermission = await recorder.isAllowedToRecordAudio
                if hasPermission {
                    await recordAudio() // This will set weChatRecordingPhase = .recording on success
                    if self.weChatRecordingPhase == .recording {
                        self.state = .isRecordingHold // Sync main state
                    } else { // recordAudio failed
                        self.state = .empty
                        self.weChatRecordingPhase = .idle
                    }
                } else {
                    DebugLogger.log("Action .recordAudioHold. Permission not yet granted. Requesting.")
                    self.state = .waitingForRecordingPermission
                    self.weChatRecordingPhase = .idle
                    let granted = await recorder.requestDirectPermission()
                    self.state = granted ? .empty : .waitingForRecordingPermission // Or a "denied" state
                }
            }
        case .recordAudioTap: // For WeChat style, this might not be used or could be a quick record start/stop
            Task {
                let hasPermission = await recorder.isAllowedToRecordAudio
                if hasPermission {
                    if await recorder.isRecording { // If already recording (e.g. tap-locked), then stop.
                        DebugLogger.log("Action .recordAudioTap: Was recording (tap-locked), now stopping.")
                        await self.inputViewActionInternal(.stopRecordAudio)
                    } else { // Not recording, so start tap-locked recording.
                        DebugLogger.log("Action .recordAudioTap: Starting tap-locked recording.")
                        await recordAudio() // Sets weChatRecordingPhase = .recording
                        if self.weChatRecordingPhase == .recording {
                            self.state = .isRecordingTap // Sync main state for tap-lock
                        } else {
                            self.state = .empty
                            self.weChatRecordingPhase = .idle
                        }
                    }
                } else {
                    DebugLogger.log("Action .recordAudioTap. Permission not yet granted. Requesting.")
                    self.state = .waitingForRecordingPermission
                    self.weChatRecordingPhase = .idle
                    let granted = await recorder.requestDirectPermission()
                    self.state = granted ? .empty : .waitingForRecordingPermission
                }
            }

        case .recordAudioLock: // From UI, when user swipes up during hold
             DebugLogger.log("Action .recordAudioLock. Transitioning state to .isRecordingTap for locked mode.")
             self.state = .isRecordingTap
             self.weChatRecordingPhase = .recording // Or a specific .recordingLocked phase if needed
                                                    // For now, .recording covers visual feedback.

        case .stopRecordAudio: // User explicitly stops a tap-locked recording OR gesture releases on STT zone
            Task {
                DebugLogger.log("Action .stopRecordAudio. Current WeChatPhase: \(self.weChatRecordingPhase)")
                let recordingResult = await recorder.stopRecording()
                if let url = recordingResult.url, recordingResult.duration > 0.1 {
                    self.attachments.recording = Recording(duration: recordingResult.duration, waveformSamples: recordingResult.samples, url: url)
                    self.state = .hasRecording
                    // If this stop was NOT for STT, then the phase should become idle or similar.
                    // If it WAS for STT, the gesture handler should have already set phase to .processingSTT.
                    if self.weChatRecordingPhase != .processingASR && self.weChatRecordingPhase != .asrCompleteWithText("") {
                        self.weChatRecordingPhase = .idle // Or a new phase e.g. .voiceNoteReady
                    }
                } else {
                    self.attachments.recording = nil
                    self.state = .empty
                    self.weChatRecordingPhase = .idle
                }
                await recordingPlayer?.reset()
            }

        case .deleteRecord:
            Task {
                DebugLogger.log("Action .deleteRecord.")
                unsubscribeRecordPlayer()
                _ = await recorder.stopRecording() // Ensure recorder is stopped
                self.attachments.recording = nil
                self.transcribedText = ""
                self.asrErrorMessage = nil
                self.isEditingASRText = false // Also reset editing state here
                self.state = .empty
                self.weChatRecordingPhase = .idle
                self.isDraggingInCancelZoneOverlay = false
                self.isDraggingToConvertToTextZoneOverlay = false
            }
        case .playRecord:
            DebugLogger.log("Action .playRecord.")
            // state = .playingRecording // General state if needed, or rely on player's state
            if let recording = attachments.recording {
                Task {
                    subscribeRecordPlayer()
                    await recordingPlayer?.play(recording)
                }
            }
        case .pauseRecord:
            DebugLogger.log("Action .pauseRecord.")
            // state = .pausedRecording // General state if needed
            Task {
                await recordingPlayer?.pause()
            }
        case .saveEdit:
            DebugLogger.log("Action .saveEdit.")
            saveEditingClosure?(text)
            reset() // Resets all states including weChatRecordingPhase
        case .cancelEdit:
            DebugLogger.log("Action .cancelEdit.")
            reset() // Resets all states
        }
    }

    private func recordAudio() async {
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

}

private extension InputViewModel {

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

private extension InputViewModel {

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

