// In Chat/Sources/ExyteChat/Views/InputView/WeChatInputView.swift
import SwiftUI

struct WeChatInputView: View {
    @ObservedObject var viewModel: InputViewModel
    @EnvironmentObject var globalFocusState: GlobalFocusState
    @EnvironmentObject var keyboardState: KeyboardState

    let localization: ChatLocalization
    let inputFieldId: UUID

    @State private var isVoiceMode: Bool = false
    @FocusState private var isTextFocused: Bool

    @GestureState private var isLongPressSustained: Bool = false
    // No need for @State showRecordingOverlay, viewModel.isRecordingAudioForOverlay handles it

    private let cancelDragThresholdY: CGFloat = -80

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
                if focused { globalFocusState.focus = .uuid(self.inputFieldId) }
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
                Logger.log("Gesture.updating: LongPress active=\(value.first ?? false), Drag info exists=\(value.second != nil)")
                gestureState = value.first ?? false
            }
            .onChanged { value in
                Logger.log("Gesture.onChanged: LongPress active=\(value.first ?? false)")
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
                Logger.log("Gesture.onEnded: LongPress active at end=\(value.first ?? false)")
                let longPressWasSustained = value.first ?? false
                let endedPhase = viewModel.weChatRecordingPhase // Capture before it's reset

                if longPressWasSustained {
                    switch endedPhase {
                    case .draggingToCancel:
                        Logger.log("Gesture Ended on .draggingToCancel. Action: deleteRecord")
                        performInputAction(.deleteRecord)
                    case .draggingToConvertToText:
                        Logger.log("Gesture Ended on .draggingToConvertToText. Action: stop and prepare for STT")
                        performInputAction(.stopRecordAudio) // This gets the recording ready
                        Task { @MainActor in
                            if viewModel.state == .hasRecording, let _ = viewModel.attachments.recording {
                                viewModel.weChatRecordingPhase = .processingASR
                                Logger.log("Transitioning to .processingSTT for actual STT")
                                await viewModel.performSpeechToText() // Actual STT call
                            } else {
                                Logger.log("No valid recording after stop for STT. Cleaning up.")
                                performInputAction(.deleteRecord)
                            }
                        }
                    case .recording:
                        Logger.log("Gesture Ended on .recording (normal release). Action: send")
                        performInputAction(.send)
                    default:
                        Logger.log("Gesture Ended on unexpected phase \(endedPhase) while sustained. Cleaning up.")
                        performInputAction(.deleteRecord)
                    }
                } else {
                    Logger.log("Gesture Ended: Long press not sustained. Current VM phase: \(viewModel.weChatRecordingPhase)")
                    if viewModel.weChatRecordingPhase == .recording || viewModel.state == .isRecordingHold {
                        performInputAction(.deleteRecord)
                    }
                }

                // Reset UI drag states. The core phase (.idle, .processingSTT, .sttComplete)
                // will be set by the actions themselves.
                viewModel.isDraggingInCancelZoneOverlay = false
                viewModel.isDraggingToConvertToTextZoneOverlay = false

                // If not moving into an STT processing or complete state, ensure phase is idle.
                if endedPhase != .processingASR && endedPhase != .asrCompleteWithText("") && viewModel.weChatRecordingPhase != .processingASR && viewModel.weChatRecordingPhase != .asrCompleteWithText("") {
                     // Check viewModel.weChatRecordingPhase again because actions might have already set it to .idle
                    if viewModel.weChatRecordingPhase != .idle {
                        // viewModel.weChatRecordingPhase = .idle // Let actions handle final idle state
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
                Logger.log("Long press sustained, isActive: \(isActive).")
                if isActive {
                    if viewModel.weChatRecordingPhase == .recording && viewModel.state != .waitingForRecordingPermission {
                        Logger.log("Long press sustained & active. Triggering .recordAudioHold.")
                        performInputAction(.recordAudioHold)
                    }
                } else {
                    // This means finger lifted OR gesture was cancelled before .onEnded if it didn't meet criteria.
                    // .onEnded handles the primary logic for send/delete/STT.
                    // This block is mostly for cleanup if the gesture is 'cancelled' by the system or very brief.
                    Logger.log("isLongPressSustained became false. VM Phase: \(viewModel.weChatRecordingPhase)")
                    // If the gesture ends and we were in a specific dragging phase, but .onEnded didn't execute
                    // (e.g., system interruption), ensure cleanup.
                    if viewModel.weChatRecordingPhase == .draggingToCancel ||
                       viewModel.weChatRecordingPhase == .draggingToConvertToText {
                        // This scenario is less likely if .onEnded is robust.
                        // Consider if .deleteRecord is appropriate or just resetting UI drag states.
                        // performInputAction(.deleteRecord) // Or just reset UI states
                        Logger.log("isLongPressSustained became false during drag phase. .onEnded should handle.")
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
            Logger.log("Emoji button tapped")
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
            Logger.log("Add button tapped")
        } label: {
            ZStack { Image(systemName: addButtonSystemName).resizable().scaledToFit() }
            .frame(width: buttonIconSize + 2, height: buttonIconSize + 2)
            .foregroundStyle(theme.colors.mainText).padding(buttonPadding)
        }
        .frame(height: minInputHeight + (buttonPadding * 2))
    }
}

