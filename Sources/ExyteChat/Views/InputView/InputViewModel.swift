// In Chat/Sources/ExyteChat/Views/InputView/InputViewModel.swift
import Foundation
import Combine
import ExyteMediaPicker // Assuming Media is from here
import GiphyUISDK // Assuming GPHMedia is from here

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

    // Existing state for general input view status
    @Published var state: InputViewState = .empty {
        didSet {
            if oldValue != state {
                Logger.log("InputViewState changed from \(oldValue) to \(state)")
            }
        }
    }

    // New WeChat-specific phase for detailed gesture interaction
    @Published var weChatRecordingPhase: WeChatRecordingPhase = .idle {
        didSet {
            if oldValue != weChatRecordingPhase {
                Logger.log("WeChatRecordingPhase changed from \(oldValue) to \(weChatRecordingPhase)")
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
        }
    }

    @Published var transcribedText: String = "" // For STT result
    @Published var asrErrorMessage: String? = nil // For STT errors

    @Published var isRecordingAudioForOverlay: Bool = false {
        didSet {
            if oldValue != isRecordingAudioForOverlay {
                Logger.log("isRecordingAudioForOverlay changed from \(oldValue) to \(isRecordingAudioForOverlay)")
            }
        }
    }
    @Published var isDraggingInCancelZoneOverlay: Bool = false {
        didSet {
            if oldValue != isDraggingInCancelZoneOverlay {
                Logger.log("isDraggingInCancelZoneOverlay changed from \(oldValue) to \(isDraggingInCancelZoneOverlay)")
            }
        }
    }
    // ADD this for "Convert to Text" zone:
    @Published var isDraggingToConvertToTextZoneOverlay: Bool = false {
        didSet {
            if oldValue != isDraggingToConvertToTextZoneOverlay {
                 Logger.log("isDraggingToConvertToTextZoneOverlay changed to \(isDraggingToConvertToTextZoneOverlay)")
            }
        }
    }
    @Published var cancelRectGlobal: CGRect = .zero {
        didSet {
            // Optional: log when it changes if still debugging
            Logger.log("InputViewModel: cancelRectGlobal updated to \(cancelRectGlobal)")
        }
    }
    @Published var convertToTextRectGlobal: CGRect = .zero {
        didSet {
            Logger.log("InputViewModel: convertToTextRectGlobal updated to \(convertToTextRectGlobal)")
        }
    }


    @Published var showGiphyPicker = false
    @Published var showPicker = false
    @Published var mediaPickerMode = MediaPickerMode.photos
    @Published var showActivityIndicator = false

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
        Logger.log("onStart called. Current state: \(state)")
        subscribeValidation()
        subscribePicker()
        subscribeGiphyPicker()
    }

    func onStop() {
        Logger.log("onStop called.")
        subscriptions.removeAll()
        if isRecordingAudioForOverlay { isRecordingAudioForOverlay = false }
        if isDraggingInCancelZoneOverlay { isDraggingInCancelZoneOverlay = false }
        if isDraggingToConvertToTextZoneOverlay { isDraggingToConvertToTextZoneOverlay = false }
        if weChatRecordingPhase != .idle { weChatRecordingPhase = .idle } // Ensure reset on stop
    }

    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Logger.log("reset called. Current state before reset: \(self.state)")
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
            Logger.log("States after reset: mainState=\(self.state), weChatPhase=\(self.weChatRecordingPhase)")
        }
    }

    func send() {
        Logger.log("send() called. Current state: \(state)")
        Task {
            // If we were in a recording phase, ensure it's properly stopped.
            if self.weChatRecordingPhase == .recording || self.state == .isRecordingHold || self.state == .isRecordingTap {
                Logger.log("Send called while recording was active, stopping recorder first.")
                let recordingResult = await recorder.stopRecording() // Ensure recorder is stopped
                if let url = recordingResult.url, recordingResult.duration > 0.1 {
                     self.attachments.recording = Recording(duration: recordingResult.duration, waveformSamples: recordingResult.samples, url: url)
                     // self.state = .hasRecording // Main state indicates a recording is ready; sendMessage will handle this
                } else if self.text.isEmpty && self.attachments.medias.isEmpty {
                     // Only clear recording if nothing else to send
                     self.attachments.recording = nil
                }
                Logger.log("Stopped recording via send. Duration: \(self.attachments.recording?.duration ?? 0)")
            }

            // If sending transcribed text, it should be in `self.text` by now.
            // If sending voice after STT, `self.text` might be empty and `self.attachments.recording` should be valid.

            if !self.text.isEmpty || !self.attachments.medias.isEmpty || (self.attachments.recording != nil && (self.attachments.recording?.duration ?? 0) > 0.1) || self.attachments.giphyMedia != nil {
                sendMessage() // This internally calls reset which should set phase to .idle
            } else {
                Logger.log("Send called, but nothing to send. Cleaning up with deleteRecord logic.")
                // Effectively a cancel/cleanup if there's nothing valid to send
                self.inputViewActionInternal(.deleteRecord)
            }
        }
    }

    func edit(_ closure: @escaping (String) -> Void) {
        Logger.log("edit() called. Text to edit: \(text)")
        saveEditingClosure = closure
        state = .editing
        weChatRecordingPhase = .idle // Ensure WeChat specific interactions are reset
    }

    func inputViewAction() -> (InputViewAction) -> Void {
        { [weak self] action in
            Logger.log("inputViewAction() received action: \(action)")
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
                    Logger.log("Action .recordAudioHold. Permission not yet granted. Requesting.")
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
                        Logger.log("Action .recordAudioTap: Was recording (tap-locked), now stopping.")
                        await self.inputViewActionInternal(.stopRecordAudio)
                    } else { // Not recording, so start tap-locked recording.
                        Logger.log("Action .recordAudioTap: Starting tap-locked recording.")
                        await recordAudio() // Sets weChatRecordingPhase = .recording
                        if self.weChatRecordingPhase == .recording {
                            self.state = .isRecordingTap // Sync main state for tap-lock
                        } else {
                            self.state = .empty
                            self.weChatRecordingPhase = .idle
                        }
                    }
                } else {
                    Logger.log("Action .recordAudioTap. Permission not yet granted. Requesting.")
                    self.state = .waitingForRecordingPermission
                    self.weChatRecordingPhase = .idle
                    let granted = await recorder.requestDirectPermission()
                    self.state = granted ? .empty : .waitingForRecordingPermission
                }
            }

        case .recordAudioLock: // From UI, when user swipes up during hold
             Logger.log("Action .recordAudioLock. Transitioning state to .isRecordingTap for locked mode.")
             self.state = .isRecordingTap
             self.weChatRecordingPhase = .recording // Or a specific .recordingLocked phase if needed
                                                    // For now, .recording covers visual feedback.

        case .stopRecordAudio: // User explicitly stops a tap-locked recording OR gesture releases on STT zone
            Task {
                Logger.log("Action .stopRecordAudio. Current WeChatPhase: \(self.weChatRecordingPhase)")
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
                Logger.log("Action .deleteRecord.")
                unsubscribeRecordPlayer()
                _ = await recorder.stopRecording() // Ensure recorder is stopped
                self.attachments.recording = nil
                self.transcribedText = ""
                self.asrErrorMessage = nil
                self.state = .empty
                self.weChatRecordingPhase = .idle
                self.isDraggingInCancelZoneOverlay = false
                self.isDraggingToConvertToTextZoneOverlay = false
            }
        case .playRecord:
            Logger.log("Action .playRecord.")
            // state = .playingRecording // General state if needed, or rely on player's state
            if let recording = attachments.recording {
                Task {
                    subscribeRecordPlayer()
                    await recordingPlayer?.play(recording)
                }
            }
        case .pauseRecord:
            Logger.log("Action .pauseRecord.")
            // state = .pausedRecording // General state if needed
            Task {
                await recordingPlayer?.pause()
            }
        case .saveEdit:
            Logger.log("Action .saveEdit.")
            saveEditingClosure?(text)
            reset() // Resets all states including weChatRecordingPhase
        case .cancelEdit:
            Logger.log("Action .cancelEdit.")
            reset() // Resets all states
        }
    }

    private func recordAudio() async {
        if await recorder.isRecording {
            Logger.log("recordAudio() called, but recorder is already recording.")
            return
        }
        Logger.log("recordAudio() attempting to start new recording (permission should be granted).")

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
                Logger.log("recordAudio() successfully started. URL: \(recordingUrl.absoluteString). Current weChatRecordingPhase: \(self.weChatRecordingPhase).")
            } else {
                Logger.log("recordAudio() failed to start (url is nil). Resetting.")
                self.attachments.recording = nil
                self.state = .empty // Main state
                self.weChatRecordingPhase = .idle // WeChat phase
            }
        }
    }

    // Placeholder for actual STT logic (Phase 3)
    func performSpeechToText() async {
        guard let recording = self.attachments.recording, let audioURL = recording.url else {
            Logger.log("performSpeechToText: No valid recording URL.")
            await MainActor.run {
                self.asrErrorMessage = "No audio to transcribe."
                self.weChatRecordingPhase = .idle // Or an STT error phase
            }
            return
        }

        Logger.log("Starting STT for: \(audioURL.lastPathComponent)")
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
                Logger.log("STT Success: \(mockText)")
            } else {
                let mockError = "Speech recognition failed."
                self.asrErrorMessage = mockError
                // Decide if .hasRecording or .idle is better if STT fails but voice note exists
                self.weChatRecordingPhase = .idle // Or specific STT error phase
                Logger.log("STT Failed: \(mockError)")
            }
        }
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
                        Logger.log("Recording player didPlayTillEnd.")
                        // If it was playing as part of STT complete screen, revert to STT complete, not .hasRecording
                        if case .asrCompleteWithText(let text) = self.weChatRecordingPhase {
                            Logger.log("Player finished, was in sttComplete. Staying in sttComplete.")
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
        Logger.log("sendMessage: Preparing to send DraftMessage. Text: '\(draft.text)', Recording duration: \(draft.recording?.duration ?? -1)")
        didSendMessage?(draft)

        DispatchQueue.main.async { [weak self] in
            self?.showActivityIndicator = false
            self?.reset() // Crucial: This resets all states including weChatRecordingPhase
        }
    }
}

