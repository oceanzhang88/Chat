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

    // Gesture and Recording States
    @GestureState private var isLongPressSustained: Bool = false // True while long press is active
    @State private var showRecordingOverlay: Bool = false
    // @State private var dragLocation: CGPoint = .zero // Not strictly needed for this logic

    private let cancelDragThresholdY: CGFloat = -80

    @Environment(\.chatTheme) private var theme

    // Constants
    private let buttonIconSize: CGFloat = 28
    private let buttonPadding: CGFloat = 5
    private let minInputHeight: CGFloat = 36

    // Computed properties for localized text
    private var holdToTalkTextComputed: String {
        if isLongPressSustained && (viewModel.state == .isRecordingHold || viewModel.state == .isRecordingTap) {
             return viewModel.isDraggingInCancelZoneOverlay ? localization.releaseToCancelText : localization.releaseToSendText
        }
        return localization.holdToTalkText
    }
    private var messagePlaceholderText: String { localization.inputPlaceholder }
    private var emojiButtonSystemName: String { "face.smiling" }
    private var addButtonSystemName: String { "plus.circle.fill" }

    private var performInputAction: (InputViewAction) -> Void {
        viewModel.inputViewAction()
    }

    var body: some View {
        VStack(spacing: 0) { // Main input bar content
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
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFocused = true
                }
            }
        } label: {
            ZStack {
                Image(systemName: "keyboard")
                    .resizable().scaledToFit()
                    .opacity(isVoiceMode ? 1 : 0)
                    .animation(nil, value: isVoiceMode)
                Image(systemName: "mic")
                    .resizable().scaledToFit()
                    .opacity(isVoiceMode ? 0 : 1)
                    .animation(nil, value: isVoiceMode)
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
            .onTapGesture {
                if !isTextFocused { isTextFocused = true }
            }
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
                // value.first is Bool? (LongPressGesture state: true if min duration met and still pressed)
                gestureState = value.first ?? false
            }
            .onChanged { value in // This .onChanged is for the SimultaneousGesture
                guard value.first == true, let dragInfo = value.second else {
                    // If long press ended or no drag info, ensure the view model state is reset if it was true
                    if viewModel.isDraggingInCancelZoneOverlay {
                        viewModel.isDraggingInCancelZoneOverlay = false
                        Logger.log("WeChatInputView.onChanged: Long press ended or no drag, resetting isDraggingInCancelZoneForOverlay to false")
                    }
                    return
                }

                let currentlyInCancelZone = dragInfo.translation.height < cancelDragThresholdY
                if viewModel.isDraggingInCancelZoneOverlay != currentlyInCancelZone {
                    viewModel.isDraggingInCancelZoneOverlay = currentlyInCancelZone
                    // Logger already in InputViewModel's didSet for this property
                }
            }
            .onEnded { value in // This .onEnded is for the SimultaneousGesture
                let longPressWasSustained = value.first ?? false
                let wasInCancelZone = viewModel.isDraggingInCancelZoneOverlay // Check VM's state
                
                if longPressWasSustained {
                    if wasInCancelZone {
                        Logger.log("CombinedGesture.onEnded: Cancel action (dragged to cancel).")
                        performInputAction(.deleteRecord)
                    } else {
                        // User released finger, not in cancel zone, after a sustained long press.
                        // If the state is .isRecordingHold, it means the user intends to send.
                        // The InputViewModel.send() will handle stopping the recorder and final validation.
                        Logger.log("CombinedGesture.onEnded: Release detected (not cancel). Current viewModel.state: \(viewModel.state). Intending to send.")
                        if viewModel.state == .isRecordingHold {
                            performInputAction(.send)
                        } else if viewModel.state == .hasRecording && (viewModel.attachments.recording?.duration ?? 0 > 0.1) {
                            // This case might cover if a tap-locked recording was somehow finalized by a release here,
                            // though less typical for a pure "hold and release" gesture.
                            Logger.log("CombinedGesture.onEnded: State was already .hasRecording with valid duration. Sending.")
                            performInputAction(.send)
                        }
                        else {
                            // If state is not .isRecordingHold (e.g., .empty, .waitingForPermission, or .isRecordingTap without sufficient duration)
                            // then it's an unusual release. Treat as cleanup.
                            Logger.log("CombinedGesture.onEnded: State was not .isRecordingHold or valid .hasRecording. State: \(viewModel.state). Cleaning up.")
                            performInputAction(.deleteRecord)
                        }
                    }
                } else {
                    // Long press was not sustained (e.g., quick tap, or finger lifted before minDuration was met)
                    Logger.log("CombinedGesture.onEnded: Long press not sustained or cancelled early. Current viewModel.state: \(viewModel.state). Cleaning up if was recording.")
                    // If it was in a recording state from this gesture, clean it up.
                    if viewModel.state == .isRecordingHold || viewModel.state == .isRecordingTap {
                        performInputAction(.deleteRecord)
                    }
                }
                // Always reset the dragging cancel zone state in the ViewModel when gesture ends
                if viewModel.isDraggingInCancelZoneOverlay {
                    viewModel.isDraggingInCancelZoneOverlay = false
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
            .gesture(combinedGesture) // Apply the fully constructed combined gesture here
            .onChange(of: isLongPressSustained) { _, isActive in
                // This reacts to the @GestureState changing
                if isActive {
                    // This means the LongPressGesture part of the combinedGesture has met its minimum duration
                    // and the finger is still down.
                    if viewModel.state != .isRecordingHold && viewModel.state != .isRecordingTap {
                        Logger.log("onChange(isLongPressSustained) became true - Starting record hold")
                        performInputAction(.recordAudioHold)
                    }
                } else {
                    // isLongPressSustained became false. This means the gesture ended or was cancelled.
                    // The .onEnded block of `combinedGesture` handles the send/delete logic.
                    Logger.log("onChange(isLongPressSustained) became false. Current viewModel state: \(viewModel.state)")
                }
            }
            .onChange(of: viewModel.state) { _, newState in
                Logger.log("viewModel.state changed to \(newState)")
                if newState == .isRecordingHold || newState == .isRecordingTap {
                    if !isVoiceMode { isVoiceMode = true }
                    if !showRecordingOverlay {
                        Logger.log("Setting showRecordingOverlay = true (viewModel.state: \(newState))")
                        showRecordingOverlay = true
                    }
                } else {
                    if showRecordingOverlay {
                        Logger.log("Setting showRecordingOverlay = false (viewModel.state: \(newState))")
                        showRecordingOverlay = false
                    }
                }
            }
    }

    @ViewBuilder
    private var emojiButton: some View {
        Button {
            isTextFocused = false; keyboardState.resignFirstResponder()
            Logger.log("Emoji button tapped")
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
            performInputAction(.photo)
            Logger.log("Add button tapped")
        } label: {
            ZStack { Image(systemName: addButtonSystemName).resizable().scaledToFit() }
            .frame(width: buttonIconSize + 2, height: buttonIconSize + 2)
            .foregroundStyle(theme.colors.mainText).padding(buttonPadding)
        }
        .frame(height: minInputHeight + (buttonPadding * 2))
    }
}

