// In Chat/Sources/ExyteChat/Views/InputView/InputViewModel.swift
import Foundation
import Combine
import ExyteMediaPicker // Assuming Media is from here
import GiphyUISDK // Assuming GPHMedia is from here

@MainActor
final class InputViewModel: ObservableObject {
    
    @Published var text = ""
    @Published var attachments = InputViewAttachments()
    
    @Published var isRecordingAudioForOverlay: Bool = false {
        didSet {
            // Only print if the value actually changed to avoid redundant logs
            if oldValue != isRecordingAudioForOverlay {
                Logger.log("isRecordingAudioForOverlay changed from \(oldValue) to \(isRecordingAudioForOverlay)")
            }
        }
    }
    @Published var isDraggingInCancelZoneOverlay: Bool = false {
        didSet {
            // Corrected the typo here: isDraggingAudioForOverlay -> isDraggingInCancelZoneForOverlay
            if oldValue != isDraggingInCancelZoneOverlay {
                Logger.log("isDraggingInCancelZoneForOverlay changed from \(oldValue) to \(isDraggingInCancelZoneOverlay)")
            }
        }
    }
    
    @Published var state: InputViewState = .empty {
        didSet {
            if oldValue != state { // Only print if state actually changed
                Logger.log("State changed from \(oldValue) to \(state)")
            }
            let shouldShowOverlay = (state == .isRecordingHold || state == .isRecordingTap)
            if isRecordingAudioForOverlay != shouldShowOverlay {
                isRecordingAudioForOverlay = shouldShowOverlay
                if shouldShowOverlay {
                    Logger.log("Overlay will be shown.")
                } else {
                    Logger.log("Overlay will be hidden.")
                }
            }
        }
    }
    
    @Published var showGiphyPicker = false
    @Published var showPicker = false
    @Published var mediaPickerMode = MediaPickerMode.photos
    
    @Published var showActivityIndicator = false
    
    var recordingPlayer: RecordingPlayer?
    var didSendMessage: ((DraftMessage) -> Void)?
    private var recorder = Recorder()
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
        if isRecordingAudioForOverlay {
            isRecordingAudioForOverlay = false
        }
        if isDraggingInCancelZoneOverlay {
            isDraggingInCancelZoneOverlay = false
        }
    }
    
    // Make sure reset() clears the recording from attachments
    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Logger.log("reset called. Current state before reset: \(self.state)")
            self.showPicker = false
            self.showGiphyPicker = false
            self.text = ""
            self.saveEditingClosure = nil
            self.attachments = InputViewAttachments()
            self.subscribeValidation()
            self.state = .empty
            self.isDraggingInCancelZoneOverlay = false
            Logger.log("State after reset: \(self.state)")
        }
    }
    
    func send() {
        Logger.log("send() called. Current state: \(state)")
        Task {
            // Capture the definitive result from stopRecording
            // This result contains the most accurate duration and samples,
            // especially important if the timer in Recorder didn't update InputViewModel enough times.
            let recordingResult = await recorder.stopRecording()

            // Update self.attachments.recording with the final, accurate data from recordingResult
            // Only proceed if the recording is considered valid (has a URL and some minimal duration)
            if let url = recordingResult.url, recordingResult.duration > 0.1 { // Using 0.1s as a sensible threshold
                
                // Ensure attachments.recording exists before updating.
                // If it was nil (e.g., after a deleteRecord action), create a new Recording instance.
                if self.attachments.recording == nil {
                    self.attachments.recording = Recording(url: url)
                } else {
                    // If it exists, ensure its URL is the one from the finalized recording,
                    // as a safety measure, though it should generally be the same.
                    self.attachments.recording?.url = url
                }
                
                // Populate with the accurate duration and samples from the recordingResult
                self.attachments.recording?.duration = recordingResult.duration
                self.attachments.recording?.waveformSamples = recordingResult.samples
                
                Logger.log("Updated attachments.recording from stopRecording: Duration=\(recordingResult.duration), Samples=\(recordingResult.samples.count), URL: \(url.lastPathComponent)")
            } else {
                // If the recording is too short or otherwise invalid (e.g., no URL from stopRecording),
                // ensure attachments.recording is nil so an empty/0-duration recording isn't sent.
                Logger.log("Recording result not valid or duration too short. Clearing attachments.recording. Duration: \(recordingResult.duration)")
                self.attachments.recording = nil
            }

            await recordingPlayer?.reset() // Reset the audio player state regardless
            sendMessage() // sendMessage will now use the correctly updated (or nilled out) self.attachments.recording
        }
    }
    
    func edit(_ closure: @escaping (String) -> Void) {
        Logger.log("edit() called. Text to edit: \(text)")
        saveEditingClosure = closure
        state = .editing
    }
    
    func inputViewAction() -> (InputViewAction) -> Void {
        { [weak self] in
            Logger.log("inputViewAction() received action: \($0)")
            self?.inputViewActionInternal($0)
        }
    }
    
    private func inputViewActionInternal(_ action: InputViewAction) {
        switch action {
        case .giphy:
            showGiphyPicker = true
        case .photo:
            mediaPickerMode = .photos
            showPicker = true
        case .add:
            mediaPickerMode = .camera
        case .camera:
            mediaPickerMode = .camera
            showPicker = true
        case .send:
            send()
        case .recordAudioLock:
            state = .isRecordingTap
        case .recordAudioTap:
            Task {
                // Check permission BEFORE attempting to change state or record
                let hasPermission = await recorder.isAllowedToRecordAudio
                if hasPermission {
                    state = .isRecordingTap // This will trigger isRecordingAudioForOverlay
                    await recordAudio() // Record audio normally
                } else {
                    // Permission not granted. Trigger request but don't change state to recording.
                    Logger.log("Action .recordAudioTap. Permission not yet granted. Requesting.")
                    state = .waitingForRecordingPermission // Indicate attempt
                    await recorder.requestDirectPermission() // Just request, don't try to record in this flow
                    // After request, revert state. User must tap again.
                    state = .empty
                    Logger.log("Action .recordAudioTap. Permission request made (if dialog shown). State reverted to empty. User must tap/hold again.")
                }
            }
        case .recordAudioHold:
            Task {
                // Check permission BEFORE attempting to change state or record
                let hasPermission = await recorder.isAllowedToRecordAudio
                if hasPermission {
                    state = .isRecordingHold // This will trigger isRecordingAudioForOverlay
                    await recordAudio() // Record audio normally
                } else {
                    // Permission not granted. Trigger request but don't change state to recording.
                    Logger.log("Action .recordAudioHold. Permission not yet granted. Requesting.")
                    state = .waitingForRecordingPermission // Indicate attempt
                    await recorder.requestDirectPermission() // Just request, don't try to record in this flow
                    // After request, revert state. User must tap again.
                    state = .empty
                    Logger.log("Action .recordAudioHold. Permission request made (if dialog shown). State reverted to empty. User must tap/hold again.")
                }
            }
        case .stopRecordAudio:
            Task {
                Logger.log("Action .stopRecordAudio.")
                await recorder.stopRecording()
                if let _ = attachments.recording {
                    state = .hasRecording
                } else {
                    attachments.recording = nil
                    state = .empty
                }
                await recordingPlayer?.reset()
            }
        case .deleteRecord:
            Task {
                Logger.log("Action .deleteRecord.")
                unsubscribeRecordPlayer()
                await recorder.stopRecording()
                attachments.recording = nil
                state = .empty
                if isDraggingInCancelZoneOverlay { // Only reset if it was true
                    isDraggingInCancelZoneOverlay = false
                }
            }
        case .playRecord:
            Logger.log("Action .playRecord.")
            state = .playingRecording
            if let recording = attachments.recording {
                Task {
                    subscribeRecordPlayer()
                    await recordingPlayer?.play(recording)
                }
            }
        case .pauseRecord:
            Logger.log("Action .pauseRecord.")
            state = .pausedRecording
            Task {
                await recordingPlayer?.pause()
            }
        case .saveEdit:
            Logger.log("Action .saveEdit.")
            saveEditingClosure?(text)
            reset()
        case .cancelEdit:
            Logger.log("Action .cancelEdit.")
            reset()
        }
    }
    
    // Simplified recordAudio, assumes permission is already granted when called
    private func recordAudio() async {
        if await recorder.isRecording {
            Logger.log("recordAudio() called, but recorder is already recording.")
            return
        }
        Logger.log("recordAudio() attempting to start new recording (permission should be granted).")

        await MainActor.run {
            self.attachments.recording = Recording()
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
                // State (.isRecordingHold or .isRecordingTap) was already set by the caller
                Logger.log("recordAudio() successfully started. URL: \(recordingUrl.absoluteString). Current state: \(self.state).")
            } else {
                Logger.log("recordAudio() failed to start (url is nil - this shouldn't happen if permission was pre-checked). Resetting.")
                self.attachments.recording = nil
                // If state was .isRecordingHold or .isRecordingTap, revert it as recording failed
                if self.state == .isRecordingHold || self.state == .isRecordingTap || self.state == .waitingForRecordingPermission {
                    self.state = .empty
                }
            }
        }
    }
}

private extension InputViewModel {

    func validateDraft() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard state != .editing else { return } // special case
            if !self.text.isEmpty || !self.attachments.medias.isEmpty {
                self.state = .hasTextOrMedia
            } else if self.text.isEmpty,
                      self.attachments.medias.isEmpty,
                      self.attachments.recording == nil {
                self.state = .empty
            }
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
                        Logger.log("Recording player didPlayTillEnd. Setting state to .hasRecording.")
                        self?.state = .hasRecording
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
            text: self.text,
            medias: attachments.medias,
            giphyMedia: attachments.giphyMedia,
            recording: attachments.recording,
            replyMessage: attachments.replyMessage,
            createdAt: Date()
        )
        didSendMessage?(draft)
        DispatchQueue.main.async { [weak self] in
            self?.showActivityIndicator = false
            self?.reset()
        }
    }
}

