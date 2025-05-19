// Chat/Sources/ExyteChat/Views/InputView/WechatOverlay/WeChatRecordingOverlayView.swift
import SwiftUI

// MARK: - Main Overlay View
struct WeChatRecordingOverlayView: View {
    var inputViewModel: InputViewModel
    @Environment(\.chatTheme) private var theme
    @EnvironmentObject var keyboardState: KeyboardState // Keep this
//    @Environment(\.safeAreaInsets) var safeAreaInsets // Get safe area insets
    
    // State to hold the dynamically calculated height from WechatRecordingIndicator
//    @State private var indicatorContentHeight: CGFloat = 70 // Initial default
    
    let inputBarHeight: CGFloat
    var localization: ChatLocalization
    
    // --- Widths for the indicator based on phase ---
    private var recordingIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.45 } // IMG_0110.jpg reference for relative size
    private var cancelIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.2 } // Smaller for cancel (IMG_0110.jpg)
    private var asrIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.9 }// Wider for ASR text (IMG_0111.jpg)
    
    
    // --- X-Offsets for the indicator based on phase ---
    private var recordingIndicatorXOffset: CGFloat { 0 } // Centered
    private var cancelIndicatorXOffset: CGFloat {
        if !inputViewModel.cancelRectGlobal.isEmpty {
            // Center the *cancelIndicator* over the *cancelButton's center*
            return inputViewModel.cancelRectGlobal.midX - (UIScreen.main.bounds.width / 2)
        }
        return -(UIScreen.main.bounds.width * 0.25) // Fallback left
    }
    private var asrIndicatorXOffset: CGFloat {
        // For the wide ASR bubble, we want it to feel like it's expanding towards the "En" button
        // but it might be close to centered if it's very wide.
        // Let's try to align its right edge somewhat relative to the "En" button.
        if !inputViewModel.convertToTextRectGlobal.isEmpty {
            let screenCenter = UIScreen.main.bounds.width / 2
            let targetBubbleRightEdge = inputViewModel.convertToTextRectGlobal.maxX - 10 // Align right edge near "En" button's right
            let bubbleCenterX = targetBubbleRightEdge - (currentRecordingIndicatorWidth / 2)
            return bubbleCenterX - screenCenter
        }
        return 0 // Fallback centered
    }
    
    
    // --- Dynamically select current width and offset ---
    private var currentRecordingIndicatorWidth: CGFloat {
        switch inputViewModel.weChatRecordingPhase {
        case .draggingToCancel: return cancelIndicatorWidth
        case .draggingToConvertToText, .processingASR: return asrIndicatorWidth
        default: return recordingIndicatorWidth // For .recording
        }
    }
    
    private var currentRecordingIndicatorXOffset: CGFloat {
        switch inputViewModel.weChatRecordingPhase {
        case .draggingToCancel: return cancelIndicatorXOffset
            //        case .draggingToConvertToText, .processingASR: return asrIndicatorXOffset
        default: return recordingIndicatorXOffset // For .recording
        }
    }
    
    private var showControlsAboveKeyboard: Bool {
        inputViewModel.isEditingASRTextInOverlay &&
        keyboardState.isShown &&
        (
            {
                if case .asrCompleteWithText = inputViewModel.weChatRecordingPhase { return true }
                return false
            }()
        )
    }
    // Define a small, fixed padding for compactness
    private let compactPadding: CGFloat = 8 // Adjust as needed
    
    var body: some View {
        ZStack(alignment: .bottom) {
            DimmedGradientBackgroundView().onTapGesture {
                // If editing ASR text and user taps background, dismiss keyboard
                DebugLogger.log("WeChatRecordingOverlayView: Background tapped.")
                if inputViewModel.isEditingASRTextInOverlay {
                    inputViewModel.endASREditSession(discardChanges: false)
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                if !showControlsAboveKeyboard { // If keyboard NOT shown with controls, allow more flexible spacing
                    Spacer() // Pushes ASR bubble down
                    Spacer()
                }
                
                // Conditional content based on phase
                Group {
                    switch inputViewModel.weChatRecordingPhase {
                    case .idle:
                        EmptyView()
                    case .recording, .draggingToCancel, .draggingToConvertToText, .processingASR:
                        WechatRecordingIndicator(inputViewModel: inputViewModel)
                        .frame(width: currentRecordingIndicatorWidth) // Use dynamic height
                        .offset(x: currentRecordingIndicatorXOffset)
//                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: indicatorContentHeight) // Animate height changes
                        .animation(.smooth(duration: 0.2), value: currentRecordingIndicatorWidth)
                        .animation(.smooth(duration: 0.2), value: currentRecordingIndicatorXOffset)
                        
                    case .asrCompleteWithText:  // String argument is handled by ASRResultView
                        // ASRResultView is for the *final static display* after ASR.
                        // The live text during .draggingToConvertToText is now inside WechatRecordingIndicator.
                        ASRResultView(
                            inputViewModel: inputViewModel, localization: localization,
                            targetWidth: asrIndicatorWidth
                        )
                        // Use the height stored in the ViewModel, which was last set by the indicator
                        // or re-calculated for the final text.
                        .frame(height: inputViewModel.currentASRBubbleHeight) // <<<< Key Change
                        .transition(.opacity.combined(with: .scale(scale: 1.0)))
                    }
                }
//                .padding(.bottom, 20)  // Some space above the bottom controls
                
                if !showControlsAboveKeyboard { // If keyboard NOT shown with controls, allow more flexible spacing
                    Spacer() // Pushes ASR bubble down
                }
            
                BottomControlsView(
                    currentPhase: inputViewModel.weChatRecordingPhase,
                    localization: localization,
                    inputViewModel: inputViewModel,
                    inputBarHeight: inputBarHeight
                )
                { // For X button during recording/dragging to cancel
                    inputViewModel.inputViewAction()(.deleteRecord)
                }
                onConvertToText: {
                    DebugLogger.log("BottomControlsView: onConvertToText (direct tap) placeholder.")
                    /* Direct tap on "En" if needed, usually drag-release */
                }
                // Adjust padding for keyboard ONLY when editing ASR text in the overlay
                .padding(.bottom, showControlsAboveKeyboard ? keyboardState.keyboardFrame.height * 0.9 : 0)
//                .animation(.easeInOut(duration: 0.25), value: showControlsAboveKeyboard)
//                .animation(.easeInOut(duration: 0.25), value: keyboardState.keyboardFrame.height) // Also animate keyboard height changes

            }
            .padding(.top, UIApplication.safeArea.top + compactPadding)
        }
        .edgesIgnoringSafeArea(.all) // Dimmed background covers all
        .onChange(of: inputViewModel.weChatRecordingPhase) { _, newPhase in
            if case .asrCompleteWithText(let finalText) = newPhase {
                // Recalculate and set the definitive height for ASRResultView based on final content
                let finalHeight = WechatRecordingIndicator.calculateDynamicASRBubbleHeight(
                    forText: inputViewModel.asrErrorMessage != nil ? (inputViewModel.asrErrorMessage ?? "") : finalText,
                    phase: newPhase,
                    processingDots: "",
                    viewModel: inputViewModel,
                    indicatorWidth: asrIndicatorWidth // Width that ASRResultView will use
                )
                if abs(inputViewModel.currentASRBubbleHeight - finalHeight) > 1 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        inputViewModel.currentASRBubbleHeight = finalHeight
                    }
                } else {
                    inputViewModel.currentASRBubbleHeight = finalHeight
                }
            }
        }
    }
}

// DimmedGradientBackgroundView remains the same
struct DimmedGradientBackgroundView: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 80/255, green: 80/255, blue: 80/255).opacity(0.7),
                Color(red: 20/255, green: 20/255, blue: 20/255).opacity(1)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .edgesIgnoringSafeArea(.all)
    }
}

// Preview (Optional, but good for the overlay itself)
struct WeChatRecordingOverlayView_Previews: PreviewProvider {
    static func createMockVM(phase: WeChatRecordingPhase) -> InputViewModel {
        let vm = InputViewModel()
        vm.weChatRecordingPhase = phase
        vm.isRecordingAudioOverlay = phase != .idle && phase != .asrCompleteWithText("")
        if case .draggingToConvertToText = phase {
            vm.transcribedText = "Testing real-time display..."
        }
        if case .asrCompleteWithText(let text) = phase {
            vm.transcribedText = text.isEmpty ? "DA DA do do, honey" : text
        } else if phase == .asrCompleteWithText("") { // Simulate empty ASR result
            vm.transcribedText = ""
        }
        vm.cancelRectGlobal = CGRect(x: 50, y: UIScreen.main.bounds.height - 100, width: 70, height: 70)
        vm.convertToTextRectGlobal = CGRect(x: UIScreen.main.bounds.width - 120, y: UIScreen.main.bounds.height - 100, width: 70, height: 70)
        return vm
    }
    
    static var previews: some View {
        let localization = ChatLocalization(
            inputPlaceholder: "Type a message...",
            signatureText: "Signature",
            cancelButtonText: "Cancel",
            recentToggleText: "Recents",
            waitingForNetwork: "Waiting...",
            recordingText: "Recording...",
            replyToText: "Reply to",
            holdToTalkText: "Hold to Talk",
            releaseToSendText: "Release to send",
            releaseToCancelText: "Release to cancel",
            convertToTextButton: "En",
            tapToEditText: "tapToEditText",
            sendVoiceButtonText: "send",
            unableToRecognizeWordsText: "Unable to recognize words"
            
        )
        
        Group {
            WeChatRecordingOverlayView(inputViewModel: createMockVM(phase: .recording), inputBarHeight: 50, localization: localization)
                .previewDisplayName("Recording Phase")
            
            WeChatRecordingOverlayView(inputViewModel: createMockVM(phase: .draggingToCancel), inputBarHeight: 50, localization: localization)
                .previewDisplayName("Dragging to Cancel")
            
            WeChatRecordingOverlayView(inputViewModel: createMockVM(phase: .draggingToConvertToText), inputBarHeight: 50, localization: localization)
                .previewDisplayName("Dragging to ConvertToText")
            
            WeChatRecordingOverlayView(inputViewModel: createMockVM(phase: .processingASR), inputBarHeight: 50, localization: localization)
                .previewDisplayName("Processing ASR")
            
            WeChatRecordingOverlayView(inputViewModel: createMockVM(phase: .asrCompleteWithText("This is the final text.")), inputBarHeight: 50, localization: localization) // Pass localization
                .previewDisplayName("ASR Complete")
            
            WeChatRecordingOverlayView(inputViewModel: createMockVM(phase: .asrCompleteWithText("")), inputBarHeight: 50, localization: localization) // Pass localization
                .previewDisplayName("ASR Complete (Empty)")
        }
        .preferredColorScheme(.light) // Often these overlays are designed for dark mode
    }
}
