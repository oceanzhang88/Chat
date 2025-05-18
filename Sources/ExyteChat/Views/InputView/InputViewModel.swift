// In Chat/Sources/ExyteChat/Views/InputView/InputViewModel.swift
import Foundation
import Combine
import ExyteMediaPicker // Assuming Media is from here
import GiphyUISDK // Assuming GPHMedia is from here
import Speech // <--- ADD THIS LINE

// ADD this enum:
public enum WeChatRecordingPhase: Sendable, Equatable { // Make it Equatable for 
    case idle
    case recording // Standard hold-to-talk recording
    case draggingToCancel
    case draggingToConvertToText
    case processingASR // Speech-to-text is in progress
    case asrCompleteWithText(String) // Store transcribed text here
//    case sttError(String) // Optional: for specific STT error messages
}

public enum RecorderType: Sendable, Equatable {
    case simple
    case transcriber
}

enum RecordingIntent: Sendable, Equatable {
    case sendAudioOnly
    case convertToText
    case none // For other cases like natural end of speech
}

@Observable
@MainActor
final class InputViewModel {
    
    var transcribedText: String = "" // For STT result
    var asrErrorMessage: String? = nil // For STT errors
    var isEditingASRText: Bool = false
    var mediaPickerMode = MediaPickerMode.photos
    var showActivityIndicator = false
    var shouldHideMainInputBar: Bool = false // NEW PROPERTY
    
    var recordingPlayer: RecordingPlayer?
    var transcriber: DefaultTranscriberPresenter = DefaultTranscriberPresenter()
    var didSendMessage: ((DraftMessage) -> Void)?
    var recorder = Recorder()
    var recordPlayerSubscription: AnyCancellable?
    var subscriptions = Set<AnyCancellable>()
    
    var currentRecordingIntent: RecordingIntent = .none
    
    var text = "" {
        didSet  {
            validateDraft()
        }
    }
     var attachments = InputViewAttachments()  {
         didSet  {
             validateDraft()
         }
     }
     var showGiphyPicker = false  {
         didSet  {
             if !showGiphyPicker {
                 attachments.giphyMedia = nil
             }
         }
     }
     var showPicker = false  {
         didSet  {
             if !showPicker {
                 attachments.medias = []
             }
         }
     }
    
    // Existing state for general input view status
     var state: InputViewState = .empty {
        didSet {
            if oldValue != state {
                DebugLogger.log("InputViewState changed from \(oldValue) to \(state)")
            }
        }
    }
    // New WeChat-specific phase for detailed gesture interaction
     var weChatRecordingPhase: WeChatRecordingPhase = .idle {
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
     var isRecordingAudioForOverlay: Bool = false {
        didSet {
            if oldValue != isRecordingAudioForOverlay {
                DebugLogger.log("isRecordingAudioForOverlay changed from \(oldValue) to \(isRecordingAudioForOverlay)")
            }
        }
    }
     var isDraggingInCancelZoneOverlay: Bool = false {
        didSet {
            if oldValue != isDraggingInCancelZoneOverlay {
                DebugLogger.log("isDraggingInCancelZoneOverlay changed from \(oldValue) to \(isDraggingInCancelZoneOverlay)")
            }
        }
    }
    // ADD this for "Convert to Text" zone:
     var isDraggingToConvertToTextZoneOverlay: Bool = false {
        didSet {
            if oldValue != isDraggingToConvertToTextZoneOverlay {
                 DebugLogger.log("isDraggingToConvertToTextZoneOverlay changed to \(isDraggingToConvertToTextZoneOverlay)")
            }
        }
    }
     var cancelRectGlobal: CGRect = .zero {
        didSet {
            // Optional: log when it changes if still debugging
            DebugLogger.log("InputViewModel: cancelRectGlobal updated to \(cancelRectGlobal)")
        }
    }
     var convertToTextRectGlobal: CGRect = .zero {
        didSet {
            DebugLogger.log("InputViewModel: convertToTextRectGlobal updated to \(convertToTextRectGlobal)")
        }
    }

    private var saveEditingClosure: ((String) -> Void)?
    // For monitoring transcriber activity
    var transcriberIsRecordingSubscription: AnyCancellable?
    var transcriberRmsLevelSubscription: AnyCancellable?
    var transcriberDurationTimer: Timer?
    var transcriberRecordingStartTime: Date?

    func onStart() {
        DebugLogger.log("onStart called. Current state: \(state)")
//        subscribeValidation()
//        subscribePicker()
//        subscribeGiphyPicker()
    }

    func onStop() {
        DebugLogger.log("onStop called.")
        subscriptions.removeAll()
        if isRecordingAudioForOverlay { isRecordingAudioForOverlay = false }
        if isDraggingInCancelZoneOverlay { isDraggingInCancelZoneOverlay = false }
        if isDraggingToConvertToTextZoneOverlay { isDraggingToConvertToTextZoneOverlay = false }
        if weChatRecordingPhase != .idle { weChatRecordingPhase = .idle } // Ensure reset on stop
    }

    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            DebugLogger.log("reset called. Current state before reset: \(self.state)")

            self.isEditingASRText = false
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
//            self.subscribeValidation()
            DebugLogger.log("States after reset: mainState=\(self.state), weChatPhase=\(self.weChatRecordingPhase)")
        }
    }

    func send() {
        DebugLogger.log("send() called. State: \(state), WeChatPhase: \(weChatRecordingPhase)")
        Task {
            if self.state == .isRecordingHold && self.weChatRecordingPhase == .recording { // Transcriber was active from a "Hold to Talk"
                DebugLogger.log("Send: Transcriber (Hold) was active. Setting intent to .sendAudioOnly and stopping transcriber.")
                self.currentRecordingIntent = .sendAudioOnly // Set the intent
                await self.transcriber.stopRecording() // Stop the transcriber
                // The transcriber's completion handler (modified in step 2) will run.
                // It will populate self.attachments.recording and set self.state = .hasRecording.
                // It will *not* set weChatRecordingPhase to .asrCompleteWithText due to the .sendAudioOnly intent.
            } else if self.state == .isRecordingTap && self.weChatRecordingPhase == .recording { // Simple recorder from tap-lock
                DebugLogger.log("Send: Simple Recorder (Tap) was active. Stopping simple recorder.")
                let simpleRecResult = await recorder.stopRecording()
                if let url = simpleRecResult.url, simpleRecResult.duration > 0.1 {
                    self.attachments.recording = Recording(duration: simpleRecResult.duration, waveformSamples: simpleRecResult.samples, url: url)
                    self.state = .hasRecording // Ensure state reflects this before sendMessage
                } else {
                    self.attachments.recording = nil // Clear if invalid
                }
            }
            // else: No active recording to stop, or state is already .hasRecording / .hasTextOrMedia from a previous operation.

            // Check if there's anything valid to send
            if !self.text.isEmpty || !self.attachments.medias.isEmpty || (self.attachments.recording != nil && (self.attachments.recording?.duration ?? 0) > 0.1) || self.attachments.giphyMedia != nil {
                sendMessage() // This internally calls reset(), which will set weChatRecordingPhase to .idle
            } else {
                DebugLogger.log("Send: Nothing valid to send after processing active recording. Cleaning up.")
                self.inputViewActionInternal(.deleteRecord) // This also calls reset()
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
                    await recordAudio(type: .transcriber) // This will set weChatRecordingPhase = .recording on success
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
                        await recordAudio(type: .simple) // Sets weChatRecordingPhase = .recording
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
                DebugLogger.log("Action .deleteRecord initiated.")
                await MainActor.run { // Ensure UI-related properties are set on main actor
                    unsubscribeRecordPlayer()
                }

                // Stop the simple recorder if it was active
                if await recorder.isRecording {
                    DebugLogger.log(".deleteRecord: Simple recorder is active, stopping it.")
                    _ = await recorder.stopRecording()
                }

                // ***** THIS IS THE CRUCIAL ADDITION/MODIFICATION *****
                // Stop the DefaultTranscriberPresenter (and its internal Transcriber) if it was active
                // 'self.transcriber' is the instance of DefaultTranscriberPresenter in InputViewModel
                if await self.transcriber.isRecording {
                    DebugLogger.log(".deleteRecord: Transcriber (DefaultTranscriberPresenter) is active, stopping it.")
                    await self.transcriber.stopRecording() // This calls the presenter's stop method
                }
                // ***** END OF CRUCIAL ADDITION/MODIFICATION *****

                // Reset all relevant states on the main actor
                await MainActor.run {
                    self.attachments.recording = nil
                    self.transcribedText = ""
                    self.asrErrorMessage = nil
                    self.isEditingASRText = false
                    self.state = .empty // General state
                    self.weChatRecordingPhase = .idle // WeChat specific phase
                    self.isDraggingInCancelZoneOverlay = false // UI state for drag zone
                    self.isDraggingToConvertToTextZoneOverlay = false // UI state for drag zone
                    self.currentRecordingIntent = .none // Reset recording intent
                    DebugLogger.log(".deleteRecord: Cleanup complete. All states reset.")
                }
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
}


