// Chat/Sources/ExyteChat/Views/InputView/WechatOverlay/ASRResultView.swift
import SwiftUI

struct ASRResultView: View {
    var inputViewModel: InputViewModel
    @Environment(\.chatTheme) private var theme
    var localization: ChatLocalization
    var targetWidth: CGFloat // NEW: To match the indicator's width for ASR phase

    private let asrBubbleColor = Color(red: 130/255, green: 230/255, blue: 100/255)
    private let asrTextColor = Color.black.opacity(0.85)
    private let bubbleCornerRadius: CGFloat = 12
    // Consistent minimum height, similar to WechatRecordingIndicator's baseIndicatorHeight for ASR.
    private let minASRBubbleVisibleHeight: CGFloat = 100.0 // UPDATED for consistency

    private var tipSize: CGSize { CGSize(width: 20, height: 10) }
    private var tipPosition: BubbleWithTipShape.TipPosition { .bottom_edge_horizontal_offset }
    private var tipOffsetPercentage: CGFloat { 0.65 }

    var body: some View {
        VStack(spacing: 8) { // Root VStack for bubble + helper text
            // Main ASR Bubble container
            VStack(spacing: 0) {
                ScrollView {
                    textContent()
                        .padding(.horizontal, 16) // Padding for text within the ScrollView
                        .padding(.vertical, 12)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: 150)
            }
            .padding(.bottom, tipSize.height > 0 ? tipSize.height : 0) // Space for the tip inside the background
            .frame(minHeight: minASRBubbleVisibleHeight) // Apply min height to the bubble content area
            .frame(width: targetWidth) // Use the targetWidth for the bubble
            .background(
                BubbleWithTipShape(
                    cornerRadius: bubbleCornerRadius,
                    tipSize: tipSize,
                    tipPosition: tipPosition,
                    tipOffsetPercentage: tipOffsetPercentage
                )
                .fill(asrBubbleColor)
            )
            .clipShape(BubbleWithTipShape(
                    cornerRadius: bubbleCornerRadius,
                    tipSize: tipSize,
                    tipPosition: tipPosition,
                    tipOffsetPercentage: tipOffsetPercentage
                )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
            // No horizontal padding here, width is controlled by .frame(width: targetWidth)
            .onTapGesture {
                DebugLogger.log("ASR Bubble tapped. Current text: \(inputViewModel.transcribedText)")
                if inputViewModel.asrErrorMessage == nil && !inputViewModel.transcribedText.isEmpty {
                    inputViewModel.startEditingASRText()
                }
            }

            // Helper Text
            if inputViewModel.asrErrorMessage == nil && !inputViewModel.transcribedText.isEmpty {
                Text(localization.tapToEditText)
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.horizontal, 10) // Add some padding if helper text is too wide
            }
        }
        .fixedSize(horizontal: false, vertical: true) // Root VStack still fits its content vertically
        // The entire ASRResultView (bubble + helper text) will be constrained by this width.
        .frame(width: targetWidth)
    }

    @ViewBuilder
    private func textContent() -> some View {
        Group {
            if let errorMessage = inputViewModel.asrErrorMessage {
                Text("Error: \(errorMessage)")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(theme.colors.statusError)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if inputViewModel.transcribedText.isEmpty && inputViewModel.weChatRecordingPhase == .asrCompleteWithText("") {
                Text("Couldn't hear anything clearly.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(asrTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(inputViewModel.transcribedText)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(asrTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    @MainActor
    func createMockVM(text: String, error: String? = nil) -> InputViewModel {
        let vm = InputViewModel()
        vm.transcribedText = text
        vm.asrErrorMessage = error
        if error != nil || text.isEmpty {
            vm.weChatRecordingPhase = .asrCompleteWithText("")
        } else {
            vm.weChatRecordingPhase = .asrCompleteWithText(text)
        }
        return vm
    }
    
    let localization = ChatLocalization(
        inputPlaceholder: "Type...", signatureText: "Sign...", cancelButtonText: "Cancel", recentToggleText: "Recents",
        waitingForNetwork: "Waiting...", recordingText: "Recording...", replyToText: "Reply to", holdToTalkText: "Hold to Talk",
        releaseToSendText: "Release to Send", releaseToCancelText: "Release to Cancel", convertToTextButton: "En",
        tapToEditText: "Tap the bubble to edit the text", sendVoiceButtonText: "Send Voice"
    )
    
    let previewTargetWidth = UIScreen.main.bounds.width * 0.9
    
    return ZStack {
        Color.gray.opacity(0.7).edgesIgnoringSafeArea(.all)
        VStack(spacing: 20) { // Added spacing to VStack for preview clarity
            ASRResultView(inputViewModel: createMockVM(text: "Pew pew pew pew la"), localization: localization, targetWidth: previewTargetWidth)
            ASRResultView(inputViewModel: createMockVM(text: "Short"), localization: localization, targetWidth: previewTargetWidth)
            ASRResultView(inputViewModel: createMockVM(text: "This is a much longer transcribed text that will definitely exceed the initial height and should become scrollable within its designated area, not expanding the bubble indefinitely."), localization: localization, targetWidth: previewTargetWidth)
            ASRResultView(inputViewModel: createMockVM(text: "", error: "Speech recognition failed."), localization: localization, targetWidth: previewTargetWidth)
        }
        .padding() // Add some padding to the VStack in preview
    }
    .preferredColorScheme(.dark)
}

