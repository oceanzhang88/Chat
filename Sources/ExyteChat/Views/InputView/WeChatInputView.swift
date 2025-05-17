// In Chat/Sources/ExyteChat/Views/InputView/WeChatInputView.swift
import SwiftUI

struct WeChatInputView: View {
    @Bindable var viewModel: InputViewModel
    @EnvironmentObject var globalFocusState: GlobalFocusState
    @EnvironmentObject var keyboardState: KeyboardState

    let localization: ChatLocalization
    let inputFieldId: UUID

    @State private var isVoiceMode: Bool = false
    @FocusState private var isTextFocused: Bool

    @GestureState private var isLongPressSustained: Bool = false
    // No need for @State showRecordingOverlay, viewModel.isRecordingAudioForOverlay handles it

//    private let cancelDragThresholdY: CGFloat = -80

    @Environment(\.chatTheme) private var theme

    private let buttonIconSize: CGFloat = 28
    private let buttonPadding: CGFloat = 5
    private let minInputHeight: CGFloat = 36

    private var holdToTalkTextComputed: String {
        switch viewModel.weChatRecordingPhase {
        case .draggingToCancel:
            return localization.releaseToCancelText
        case .draggingToConvertToText:
            return "Release for Speech-to-Text" // Add to ChatLocalization
        default: // .idle, .recording
            return localization.holdToTalkText
        }
    }
    private var messagePlaceholderText: String { localization.inputPlaceholder }
    private var emojiButtonSystemName: String { "face.smiling" }
    private var addButtonSystemName: String { "plus.circle.fill" }

    private var performInputAction: (InputViewAction) -> Void {
        viewModel.inputViewAction()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                modeToggleButton
                centerInputArea
                emojiButton
                addButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 48)
            .background(theme.colors.inputBG)
        }
        .onAppear {
            if globalFocusState.focus == .uuid(self.inputFieldId) {
                isTextFocused = true
            }
            // Listen for the notification to switch to text input and focus
            NotificationCenter.default.addObserver(forName: .switchToTextInputAndFocus, object: nil, queue: .main) { notification in
                guard let focusedFieldId = notification.object as? UUID, focusedFieldId == self.inputFieldId else { return }
                
                if self.viewModel.isEditingASRText {
                    self.isVoiceMode = false // Switch to keyboard mode
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { // Brief delay for UI to update
                        self.isTextFocused = true // Focus the text field
                        self.globalFocusState.focus = .uuid(self.inputFieldId) // Ensure global focus state is also set
                    }
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: .switchToTextInputAndFocus, object: nil)
        }
    }

    @ViewBuilder
    private var modeToggleButton: some View {
        Button {
            isVoiceMode.toggle()
            if isVoiceMode {
                isTextFocused = false
                keyboardState.resignFirstResponder()
                viewModel.weChatRecordingPhase = .idle // Ensure reset if switching mode
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFocused = true
                }
            }
        } label: {
            ZStack {
                Image(systemName: "keyboard")
                    .resizable().scaledToFit().opacity(isVoiceMode ? 1 : 0)
                Image(systemName: "mic")
                    .resizable().scaledToFit().opacity(isVoiceMode ? 0 : 1)
            }
            .frame(width: buttonIconSize, height: buttonIconSize)
            .foregroundStyle(theme.colors.mainText)
            .padding(buttonPadding)
        }
        .frame(height: minInputHeight + (buttonPadding * 2))
    }

    @ViewBuilder
    private var centerInputArea: some View {
        if isVoiceMode {
            holdToTalkGestureArea
        } else {
            messageTextField
        }
    }

    @ViewBuilder
    private var messageTextField: some View {
        TextField("", text: $viewModel.text, axis: .vertical)
            .placeholder(when: viewModel.text.isEmpty) {
                Text(messagePlaceholderText)
                    .foregroundColor(theme.colors.inputPlaceholderText)
                    .padding(.horizontal, 10)
             }
            .foregroundStyle(theme.colors.inputText)
            .customFocus($globalFocusState.focus, equals: .uuid(inputFieldId)) // Ensure this uses the passed/managed inputFieldId
            .focused($isTextFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(minHeight: minInputHeight)
            .fixedSize(horizontal: false, vertical: true)
            .onTapGesture { if !isTextFocused { isTextFocused = true } }
            .onChange(of: globalFocusState.focus) { _, newValue in
                if newValue != .uuid(self.inputFieldId) { isTextFocused = false }
            }
            .onChange(of: isTextFocused) { _, focused in
                if focused {
                    globalFocusState.focus = .uuid(self.inputFieldId)
                    viewModel.isEditingASRText = false // If user manually focuses, assume they are done with ASR edit intent
                } else {
                    if globalFocusState.focus == .uuid(self.inputFieldId) && !viewModel.isEditingASRText { // Don't clear global focus if we are programmatically focusing due to ASR edit
                        // globalFocusState.focus = nil // This might be too aggressive if focus shifts to another element controlled by GlobalFocusState
                    }
                }
            }
    }

    @ViewBuilder
    private var holdToTalkGestureArea: some View {
        let longPressMinDuration = 0.25
        let longPressGesture = LongPressGesture(minimumDuration: longPressMinDuration)
        let dragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .global)

        let combinedGesture = longPressGesture.simultaneously(with: dragGesture)
            .updating($isLongPressSustained) { value, gestureState, transaction in
                // Log directly inside .updating() to see if it's even entered
                DebugLogger.log("Gesture.updating: LongPress active=\(value.first ?? false), Drag info exists=\(value.second != nil)")
                gestureState = value.first ?? false
            }
            .onChanged { value in
                DebugLogger.log("Gesture.onChanged: LongPress active=\(value.first ?? false)")
                guard value.first == true, let dragInfo = value.second else {
                    if viewModel.isDraggingInCancelZoneOverlay { viewModel.isDraggingInCancelZoneOverlay = false }
                    if viewModel.isDraggingToConvertToTextZoneOverlay { viewModel.isDraggingToConvertToTextZoneOverlay = false }
                    if viewModel.weChatRecordingPhase == .draggingToCancel || viewModel.weChatRecordingPhase == .draggingToConvertToText {
                         viewModel.weChatRecordingPhase = .recording
                    }
                    return
                }

                let currentDragLocation = dragInfo.location
                let isOverCancel = self.viewModel.cancelRectGlobal.contains(currentDragLocation) &&
                !self.viewModel.cancelRectGlobal.isEmpty
                let isOverConvertToText = self.viewModel.convertToTextRectGlobal.contains(currentDragLocation) && !self.viewModel.convertToTextRectGlobal.isEmpty
                
                viewModel.isDraggingInCancelZoneOverlay = isOverCancel
                viewModel.isDraggingToConvertToTextZoneOverlay = isOverConvertToText

                if isOverCancel {
                    if viewModel.weChatRecordingPhase != .draggingToCancel { viewModel.weChatRecordingPhase = .draggingToCancel }
                } else if isOverConvertToText {
                    if viewModel.weChatRecordingPhase != .draggingToConvertToText { viewModel.weChatRecordingPhase = .draggingToConvertToText }
                } else {
                    if viewModel.weChatRecordingPhase != .recording { viewModel.weChatRecordingPhase = .recording }
                }
            }
            .onEnded { value in
                DebugLogger.log("Gesture.onEnded: LongPress active at end=\(value.first ?? false)")
                let longPressWasSustained = value.first ?? false
                let endedOverCancel = viewModel.isDraggingInCancelZoneOverlay // Capture before reset
                let endedOverConvertToText = viewModel.isDraggingToConvertToTextZoneOverlay // Capture before reset

                // Reset UI drag states immediately
                viewModel.isDraggingInCancelZoneOverlay = false
                viewModel.isDraggingToConvertToTextZoneOverlay = false

                if longPressWasSustained {
                    if endedOverCancel {
                        DebugLogger.log("Gesture Ended on .draggingToCancel. Action: deleteRecord")
                        performInputAction(.deleteRecord)
                    } else if endedOverConvertToText {
                        DebugLogger.log("Gesture Ended on .draggingToConvertToText. Action: stop and prepare for STT")

                        // 1. Stop recording (this gets the audio file URL and duration)
                        performInputAction(.stopRecordAudio) // This sets viewModel.state = .hasRecording if successful
                            
                        // 2. Initiate STT
                        Task { @MainActor in // Ensure UI updates and async calls are managed on MainActor
                            viewModel.weChatRecordingPhase = .processingASR
                            await viewModel.performSpeechToText() // This will eventually set .asrCompleteWithText
                            // Check if stopRecordAudio successfully resulted in a recording
//                            if viewModel.state == .hasRecording, let _ = viewModel.attachments.recording {
//                                viewModel.weChatRecordingPhase = .processingASR // Show "Processing..."
//                                DebugLogger.log("Transitioning to .processingASR for actual STT")
//                                
//                            } else {
//                                DebugLogger.log("No valid recording after stop for STT. Cleaning up.")
//                                // If there was no recording, or stopRecordAudio failed, treat as cancel
//                                performInputAction(.deleteRecord)
//                            }
                        }
                    } else { // Released in the "send voice" zone (center)
                        DebugLogger.log("Gesture Ended on .recording (normal release). Action: send")
                        performInputAction(.send) // This will send the voice memo directly
                    }
                } else { // Long press was not sustained (too short)
                    DebugLogger.log("Gesture Ended: Long press not sustained. Current VM phase: \(viewModel.weChatRecordingPhase)")
                    // If it was a very short tap, it might not even have started recording.
                    // If it did start (e.g., state became .isRecordingHold), then cancel.
                    if viewModel.weChatRecordingPhase == .recording || viewModel.state == .isRecordingHold {
                        performInputAction(.deleteRecord)
                    }
                    // Ensure phase is reset if it wasn't a sustained action leading to send/stt/cancel
                    if viewModel.weChatRecordingPhase != .idle &&
                       viewModel.weChatRecordingPhase != .processingASR && // Already handled above
                       viewModel.weChatRecordingPhase != .asrCompleteWithText("") { // Already handled above
                        viewModel.weChatRecordingPhase = .idle
                    }
                }
            }

        Text(holdToTalkTextComputed)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(theme.colors.mainText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isLongPressSustained ? Color(uiColor: .systemGray3) : Color(uiColor: .systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(minHeight: minInputHeight)
            .gesture(combinedGesture)
            .onChange(of: isLongPressSustained) { _, isActive in
                DebugLogger.log("Long press sustained, isActive: \(isActive).")
                if isActive {
                    if viewModel.weChatRecordingPhase == .recording && viewModel.state != .waitingForRecordingPermission {
                        DebugLogger.log("Long press sustained & active. Triggering .recordAudioHold.")
                        performInputAction(.recordAudioHold)
                    }
                } else {
                    // This means finger lifted OR gesture was cancelled before .onEnded if it didn't meet criteria.
                    // .onEnded handles the primary logic for send/delete/STT.
                    // This block is mostly for cleanup if the gesture is 'cancelled' by the system or very brief.
                    DebugLogger.log("isLongPressSustained became false. VM Phase: \(viewModel.weChatRecordingPhase)")
                    // If the gesture ends and we were in a specific dragging phase, but .onEnded didn't execute
                    // (e.g., system interruption), ensure cleanup.
                    if viewModel.weChatRecordingPhase == .draggingToCancel ||
                       viewModel.weChatRecordingPhase == .draggingToConvertToText {
                        // This scenario is less likely if .onEnded is robust.
                        // Consider if .deleteRecord is appropriate or just resetting UI drag states.
                        // performInputAction(.deleteRecord) // Or just reset UI states
                        DebugLogger.log("isLongPressSustained became false during drag phase. .onEnded should handle.")
                    }
                }
            }
            // No need for .onChange(of: viewModel.state) here to control overlay,
            // viewModel.isRecordingAudioForOverlay (driven by weChatRecordingPhase) does that.
    }

    @ViewBuilder
    private var emojiButton: some View {
        Button {
            isTextFocused = false; keyboardState.resignFirstResponder()
            DebugLogger.log("Emoji button tapped")
            // Potentially toggle a custom emoji keyboard view if you have one
        } label: {
            ZStack { Image(systemName: emojiButtonSystemName).resizable().scaledToFit() }
            .frame(width: buttonIconSize, height: buttonIconSize)
            .foregroundStyle(theme.colors.mainText).padding(buttonPadding)
        }
        .frame(height: minInputHeight + (buttonPadding * 2))
    }

    @ViewBuilder
    private var addButton: some View {
        Button {
            isTextFocused = false; keyboardState.resignFirstResponder()
            performInputAction(.photo) // Or a more generic .addAttachment action
            DebugLogger.log("Add button tapped")
        } label: {
            ZStack { Image(systemName: addButtonSystemName).resizable().scaledToFit() }
            .frame(width: buttonIconSize + 2, height: buttonIconSize + 2)
            .foregroundStyle(theme.colors.mainText).padding(buttonPadding)
        }
        .frame(height: minInputHeight + (buttonPadding * 2))
    }
}

