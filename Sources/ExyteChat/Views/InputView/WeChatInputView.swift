// In Chat/Sources/ExyteChat/Views/InputView/WeChatInputView.swift
import SwiftUI

struct WeChatInputView: View {
    @Bindable var viewModel: InputViewModel
    @EnvironmentObject var globalFocusState: GlobalFocusState
    @EnvironmentObject var keyboardState: KeyboardState
    @Environment(\.chatTheme) private var theme
    @Environment(\.colorScheme) var colorScheme // To potentially adjust textViewBackgroundColor

    // Local FocusState for the embedded WeChatTextInputView
    @FocusState private var isTextInputViewFocused: Bool
    @GestureState private var isLongPressSustained: Bool = false
   
    // Configuration
    @State private var isVoiceMode: Bool = false
    @State var textViewHeight: CGFloat
    @State private var wasActuallyLongHeld: Bool = true
    
    let localization: ChatLocalization
    let inputFieldId: UUID
    
    private let buttonPadding: CGFloat = 4 // Reduced from 5
    private let mainHStackSpacing: CGFloat = 6 // Reduced from 8
    private let overallHorizontalPadding: CGFloat = 6 // Reduced from 8
    
    private let buttonIconSize: CGFloat = 28
    private let minInputHeight: CGFloat = 36
    
    let verticalPadding: CGFloat = 10
    var maxLines: CGFloat = 10
    var maxHeight: CGFloat {
        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        return lineHeight * maxLines + verticalPadding
    }
    
    private var holdToTalkTextComputed: String {
        switch viewModel.weChatRecordingPhase {
        case .draggingToCancel:
            return localization.releaseToCancelText
        case .draggingToConvertToText:
            return "Release for Speech-to-Text"  // Add to ChatLocalization
        default:  // .idle, .recording
            return localization.holdToTalkText
        }
    }
    private var messagePlaceholderText: String { localization.inputPlaceholder }
    private var emojiButtonSystemName: String { "face.smiling" }
    private var addButtonSystemName: String { "plus.circle.fill" }
    
    var font: UIFont = UIFont.preferredFont(forTextStyle: .body)
    // Text view's own internal padding (affects text layout width)
    private let textViewInternalInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10) // Standard WeChat-like padding
    // Background and corner radius for the text view itself
    private var textViewBackgroundColor: Color {
        // In dark mode, WeChat uses a slightly lighter gray than the input bar.
        // In light mode, it's often white or very light gray.
        colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemBackground)
    }
    private let textViewCornerRadius: CGFloat = 8
    
    private var performInputAction: (InputViewAction) -> Void {
        viewModel.inputViewAction()
    }
    
    init(
        viewModel: InputViewModel,
        localization: ChatLocalization,
        inputFieldId: UUID
    ) {
        self.viewModel = viewModel
        self.localization = localization
        self.inputFieldId = inputFieldId
        self._textViewHeight = State(initialValue: Self.calculateInitialHeight(
            text: viewModel.text,
            font: font,
            defaultHeight: minInputHeight,
            verticalPadding: textViewInternalInsets.top + textViewInternalInsets.bottom
        ))
    }
    
    private static func calculateInitialHeight(text: String, font: UIFont, defaultHeight: CGFloat, verticalPadding: CGFloat) -> CGFloat {
        if text.isEmpty {
            return defaultHeight
        }
        let tempTextView = UITextView()
        tempTextView.font = font
        tempTextView.text = text
        // Rough estimation, will be refined by WechatInputTextView's own calculation
        let fixedWidth = UIScreen.main.bounds.width - 100 // Approximate
        let size = tempTextView.sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
        return max(defaultHeight, ceil(size.height) + verticalPadding)
    }

    var body: some View {
        VStack(spacing: 0) {
            //            GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 8) {
                modeToggleButton
                centerInputArea
                    .layoutPriority(1)
                emojiButton
                addButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            //                .frame(minHeight: UIFont.preferredFont(forTextStyle: .body).lineHeight + 16)
            .background(theme.colors.inputBG)
        }
//        .frame(height: textViewHeight)
        .animation(.easeInOut(duration: 0.2), value: textViewHeight)
        .onAppear {
            // Sync local focus state with global focus state on appear
            self.isTextInputViewFocused = (globalFocusState.focus == .uuid(self.inputFieldId))
            recalculateAndUpdateHeight(text: viewModel.text, geometryProxyWidth: UIScreen.main.bounds.width - 16)

            // Listen for the notification to switch to text input and focus
            NotificationCenter.default.addObserver(forName: .switchToTextInputAndFocus, object: nil, queue: .main) { notification in
                DispatchQueue.main.async {
                    guard let focusedFieldId = notification.object as? UUID, focusedFieldId == self.inputFieldId else { return }

                    if self.viewModel.isEditingASRTextInOverlay {
                        self.isVoiceMode = false  // Switch to keyboard mode
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {  // Brief delay for UI to update
                            self.isTextInputViewFocused = true  // Directly set local focus
                            self.globalFocusState.focus = .uuid(self.inputFieldId)  // Ensure global focus state is also set
                            DebugLogger.log("WeChatInputView: Switched to text mode and focused text field due to ASR edit.")
                        }
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
        // Use if/else to switch between two distinct Button views
        if isVoiceMode {
            Button {
                isVoiceMode = false  // Toggle the mode
                isTextInputViewFocused = true  // Request focus for the text input
            } label: {
                Image(systemName: "keyboard")
                    .resizable().scaledToFit()
                    .frame(width: buttonIconSize, height: buttonIconSize)
                    .foregroundStyle(theme.colors.mainText)
                    .padding(buttonPadding)
            }
            .transition(.identity)  // Explicitly no transition for appearance/disappearance
            .frame(height: minInputHeight + (buttonPadding * 2))
        } else {
            Button {
                isVoiceMode = true  // Toggle the mode
                //                isTextFocused = false
                isTextInputViewFocused = false  // Remove focus from text field
                keyboardState.resignFirstResponder()
                viewModel.weChatRecordingPhase = .idle
            } label: {
                Image(systemName: "mic")
                    .resizable().scaledToFit()
                    .frame(width: buttonIconSize, height: buttonIconSize)
                    .foregroundStyle(theme.colors.mainText)
                    .padding(buttonPadding)
            }
            .transition(.identity)  // Explicitly no transition for appearance/disappearance
            .frame(height: minInputHeight + (buttonPadding * 2))
        }
    }

    @ViewBuilder
    private var centerInputArea: some View {
        if isVoiceMode {
            holdToTalkGestureArea
        } else {
            // Replace the old TextField with WeChatTextInputView
            WechatInputTextView(
                text: $viewModel.text,  // Bind to the ViewModel's text
                placeholder: messagePlaceholderText,  // Use the localized placeholder
                parentFocusBinding: $globalFocusState.focus,
                inputFieldID: inputFieldId,
                font: UIFont.preferredFont(forTextStyle: .body)
            ) { messageText in
                // This closure is called when the "Send" return key is pressed
                if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    performInputAction(.send)  // Trigger the send action in the ViewModel
                    
                }
            } onHeightDidChange: { newHeight in
                // Update the textViewHeight state, which will trigger animation
                if self.textViewHeight != newHeight {
                    DispatchQueue.main.async {
                        withAnimation(.linear(duration: 0.2)) {
                            self.textViewHeight = newHeight
                        }
                    }
                }
            }
            .frame(height: textViewHeight)
            .offset(y: -4)
        }
    }

    @ViewBuilder
    private var holdToTalkGestureArea: some View {
        let longPressMinDuration = 0.25
        let longPressGesture = LongPressGesture(minimumDuration: longPressMinDuration)
        let dragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .global)
        
//        let combinedGesture = longPressGesture.simultaneously(with: dragGesture)
//            .onChanged { g2 in
//                DebugLogger.log("Gesture.onChanged: LongPress active=\(g2.first), Drag info exists=\(g2.second?.location)")
//            }
//            .updating($isLongPressSustained) { g2, gestureState, transaction in
//                DebugLogger.log("Gesture.updating: LongPress active=\(g2.first) Drag info exists=\(g2.second?.location)")
//                gestureState = g2.first ?? false
//            }
//            .onEnded { g2 in
//                DebugLogger.log("Gesture.onEnded: LongPress active=\(g2.first), Drag info exists=\(g2.second?.location)")
//            }
        let combinedGesture = longPressGesture.simultaneously(with: dragGesture)
            .updating($isLongPressSustained) { value, gestureState, transaction in
                // Log directly inside .updating() to see if it's even entered
                DebugLogger.log("Gesture.updating: LongPress active=\(value.first ?? false), Drag info exists=\(value.second != nil)")
                gestureState = value.first ?? false
            }
            .onChanged { value in
                DebugLogger.log("Gesture.onChanged: LongPress active=\(value.first ?? false)")
                guard value.first == true, let dragInfo = value.second else {
                    if viewModel.isDraggingInCancelOverlay { viewModel.isDraggingInCancelOverlay = false }
                    if viewModel.isDraggingToTextOverlay { viewModel.isDraggingToTextOverlay = false }
                    if viewModel.weChatRecordingPhase == .draggingToCancel || viewModel.weChatRecordingPhase == .draggingToConvertToText {
                        viewModel.weChatRecordingPhase = .recording
                    }
                    return
                }

                let currentDragLocation = dragInfo.location
                let isOverCancel = self.viewModel.cancelRectGlobal.contains(currentDragLocation) && !self.viewModel.cancelRectGlobal.isEmpty
                let isOverConvertToText = self.viewModel.convertToTextRectGlobal.contains(currentDragLocation) && !self.viewModel.convertToTextRectGlobal.isEmpty

                viewModel.isDraggingInCancelOverlay = isOverCancel
                viewModel.isDraggingToTextOverlay = isOverConvertToText

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

                let endedOverCancel = viewModel.isDraggingInCancelOverlay  // Capture before reset
                let endedOverConvertToText = viewModel.isDraggingToTextOverlay  // Capture before reset

                // Reset UI drag states immediately
                viewModel.isDraggingInCancelOverlay = false
                viewModel.isDraggingToTextOverlay = false

                if longPressWasSustained {
                    if endedOverCancel {
                        DebugLogger.log("Gesture Ended on .draggingToCancel. Action: deleteRecord")
                        performInputAction(.deleteRecord)
                    } else if endedOverConvertToText {
                        DebugLogger.log("Gesture Ended on .draggingToConvertToText. Setting intent to .convertToText and stopping transcriber.")
                        viewModel.currentRecordingIntent = .convertToText  // Set the intent

                        Task { @MainActor in  // Ensure operations on viewModel are on MainActor

                            // Evaluate the await expression first and store its result
                            let isTranscriberCurrentlyRecording = viewModel.transcriber.isRecording
                            if viewModel.state == .isRecordingHold && isTranscriberCurrentlyRecording {  // Check if transcriber was indeed active
                                await viewModel.transcriber.stopRecording()
                                // The transcriber's completion handler (modified in step 2) will use the .convertToText intent
                                // and set weChatRecordingPhase = .asrCompleteWithText, showing the ASR results UI.
                            } else {
                                // Fallback or error: transcriber wasn't active as expected, or was not in .isRecordingHold state.
                                DebugLogger.log("ConvertToText: Transcriber was not active or not in the expected state. Performing cleanup.")
                                performInputAction(.deleteRecord)  // Perform cleanup by deleting any partial recording
                            }
                        }
                    } else {  // Released in the "send voice" zone (center)
                        DebugLogger.log("Gesture Ended on .recording (normal release). Action: send")
                        performInputAction(.send)  // This will send the voice memo directly
                    }
                } else {  // Long press was not sustained (too short)
                    DebugLogger.log("Gesture Ended: Long press not sustained. Current VM phase: \(viewModel.weChatRecordingPhase)")
                    // If it was a very short tap, it might not even have started recording.
                    // If it did start (e.g., state became .isRecordingHold), then cancel.
                    if viewModel.weChatRecordingPhase == .recording || viewModel.state == .isRecordingHold {
                        performInputAction(.deleteRecord)
                    }
                    // Ensure phase is reset if it wasn't a sustained action leading to send/stt/cancel
                    if viewModel.weChatRecordingPhase != .idle && viewModel.weChatRecordingPhase != .processingASR  // Already handled above
                        && viewModel.weChatRecordingPhase != .asrCompleteWithText("")
                    {  // Already handled above
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
//            .onTapGesture {
//                DebugLogger.log("View.onTapGesture: Text was tapped (this might not fire if LongPressGesture consumes the touch first, depending on interaction)")
//            }
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
                    if viewModel.weChatRecordingPhase == .draggingToCancel || viewModel.weChatRecordingPhase == .draggingToConvertToText {
                        // This scenario is less likely if .onEnded is robust.
                        // Consider if .deleteRecord is appropriate or just resetting UI drag states.
                        // performInputAction(.deleteRecord) // Or just reset UI states
                        DebugLogger.log("isLongPressSustained became false during drag phase. .onEnded should handle.")
                    }
                }
            }
//         No need for .onChange(of: viewModel.state) here to control overlay,
//         viewModel.isRecordingAudioForOverlay (driven by weChatRecordingPhase) does that.
    }

    @ViewBuilder
    private var emojiButton: some View {
        Button {
            isTextInputViewFocused = false  // Remove focus from text field
            keyboardState.resignFirstResponder()
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
            isTextInputViewFocused = false  // Remove focus from text field
            keyboardState.resignFirstResponder()
            performInputAction(.photo)  // Or a more generic .addAttachment action
            DebugLogger.log("Add button tapped")
        } label: {
            ZStack { Image(systemName: addButtonSystemName).resizable().scaledToFit() }
                .frame(width: buttonIconSize + 2, height: buttonIconSize + 2)
                .foregroundStyle(theme.colors.mainText).padding(buttonPadding)
        }
        .frame(height: minInputHeight + (buttonPadding * 2))
    }

    // --- Combined Calculation and Update Function ---
    private func recalculateAndUpdateHeight(text: String, geometryProxyWidth: CGFloat) {
        // Estimate available width for the CustomTextView more accurately
        let totalBarWidth = geometryProxyWidth
        let buttonWidth: CGFloat = 30  // Slightly larger estimate for tappable area/visual size
        let spacing: CGFloat = 12
        let textHorizontalPadding: CGFloat = 8 * 2  // Internal TextView padding (L+R)

        // Subtract widths of 3 buttons, 3 spacing gaps, and text internal padding
        let estimatedTextViewWidth = totalBarWidth - (3 * buttonWidth) - (3 * spacing) - textHorizontalPadding
        let availableWidth = max(10, estimatedTextViewWidth)  // Ensure width is positive

        // Calculate and update the height state variable
//        withAnimation(.linear(duration: 1)) {
            textViewHeight = calculateHeight(for: text, width: availableWidth)
//        }

    }

    // Calculate required height for text within a given width (Keep this function)
    private func calculateHeight(for text: String, width: CGFloat) -> CGFloat {
        if text.isEmpty {
            return minInputHeight
        }

        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )

        let calculatedSize = attributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let calculatedHeight = ceil(calculatedSize.height) + verticalPadding

        return max(minInputHeight, min(calculatedHeight, maxHeight))
    }
    
    //    @ViewBuilder
    //    private var messageTextField: some View {
    //        TextField("", text: $viewModel.text, axis: .vertical)
    //            .placeholder(when: viewModel.text.isEmpty) {
    //                Text(messagePlaceholderText)
    //                    .foregroundColor(theme.colors.inputPlaceholderText)
    //                    .padding(.horizontal, 10)
    //             }
    //            .foregroundStyle(theme.colors.inputText)
    //            .customFocus($globalFocusState.focus, equals: .uuid(inputFieldId)) // Ensure this uses the passed/managed inputFieldId
    //            .focused($isTextFocused)
    //            .padding(.horizontal, 10)
    //            .padding(.vertical, 8)
    //            .background(Color(uiColor: .systemBackground))
    //            .clipShape(RoundedRectangle(cornerRadius: 8))
    //            .frame(minHeight: minInputHeight)
    //            .fixedSize(horizontal: false, vertical: true)
    //            .onTapGesture { if !isTextFocused { isTextFocused = true } }
    //            .onChange(of: globalFocusState.focus) { _, newValue in
    //                if newValue != .uuid(self.inputFieldId) { isTextFocused = false }
    //            }
    //            .onChange(of: isTextFocused) { _, focused in
    //                if focused {
    //                    globalFocusState.focus = .uuid(self.inputFieldId)
    //                    //viewModel.isEditingASRText = false // If user manually focuses, assume they are done with ASR edit intent
    //                } else {
    //                    if globalFocusState.focus == .uuid(self.inputFieldId) && !viewModel.isEditingASRTextInOverlay { // Don't clear global focus if we are programmatically focusing due to ASR edit
    //                        // globalFocusState.focus = nil // This might be too aggressive if focus shifts to another element controlled by GlobalFocusState
    //                    }
    //                }
    //            }
    //    }
}
