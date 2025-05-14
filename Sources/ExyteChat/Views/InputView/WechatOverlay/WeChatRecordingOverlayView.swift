//
//  WeChatRecordingOverlayView.swift
//  Chat
//
//  Created by Yangming Zhang on 5/13/25.
//


// Chat/Sources/ExyteChat/Views/InputView/WeChatRecordingOverlayView.swift
import SwiftUI

// MARK: - Main Overlay View
struct WeChatRecordingOverlayView: View {
    @ObservedObject var inputViewModel: InputViewModel
    @Environment(\.chatTheme) private var theme

    // @State private var isPresented: Bool = true // Controlled by inputViewModel.isRecordingAudioForOverlay
    @State private var displayWaveformData: [CGFloat] = []
    @State private var animationStep: Int = 0

    let inputBarHeight: CGFloat
    var localization: ChatLocalization

    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let numberOfSamplesForIndicator: Int = 35
    private let lowVoiceThreshold: CGFloat = 0.1
    private let samplesToAnalyzeForLowVoice = 15

    private let indicatorHeight: CGFloat = 70
    private let indicatorTipHeight: CGFloat = 8

    private var defaultIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.4 }
    private var cancelIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.15 } // Slightly wider for icon
    private var sttIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.45 }    // Similar for STT icon


    // Adjusted XOffsets for better positioning
    private var cancelIndicatorXOffset: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        // Target center of the cancel button area (approx -screenW/4 + button_width/2)
        // This needs to align with where BottomControlsView places its cancel button.
        // Let's assume BottomControlsView uses padding of 60 on each side for its HStack.
        // Cancel button itself is ~70 wide. So its center is at 60 + 35 = 95 from left.
        // Overlay indicator's center is at screenWidth/2 + Xoffset.
        // So, screenWidth/2 + Xoffset = 95  => Xoffset = 95 - screenWidth/2
        return 95 - (screenWidth / 2) // Positive X for left, Negative for right
    }

    private var convertToTextIndicatorXOffset: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        // ConvertToText button is on the right. Approx center: screenWidth - 95
        // screenWidth/2 + Xoffset = screenWidth - 95 => Xoffset = screenWidth/2 - 95
        return (screenWidth / 2) - 95
    }


    private var currentIndicatorWidth: CGFloat {
        switch inputViewModel.weChatRecordingPhase {
        case .draggingToCancel: return cancelIndicatorWidth
        case .draggingToConvertToText: return UIScreen.main.bounds.width // Make it full width
        default: return defaultIndicatorWidth
        }
    }

    private var currentXOffset: CGFloat {
        switch inputViewModel.weChatRecordingPhase {
        case .draggingToCancel: return cancelIndicatorXOffset
        case .draggingToConvertToText: return 0 // Center it when full width
        default: return 0
        }
    }

    var body: some View {
        // Only show the overlay if isRecordingAudioForOverlay is true
        // AND the phase is one of the active recording/dragging phases.
        // STT processing and STT complete will have their own UI within this ZStack.
        if inputViewModel.isRecordingAudioForOverlay &&
            (inputViewModel.weChatRecordingPhase == .recording ||
             inputViewModel.weChatRecordingPhase == .draggingToCancel ||
             inputViewModel.weChatRecordingPhase == .draggingToConvertToText ||
             inputViewModel.weChatRecordingPhase == .processingASR ||
             inputViewModel.weChatRecordingPhase == .asrCompleteWithText("")) { // Include STT complete phase

            ZStack {
                DimmedGradientBackgroundView()

                VStack {
                    Spacer() // Pushes content down

                    // Conditional content based on phase
                    switch inputViewModel.weChatRecordingPhase {
                    case .idle:
                        EmptyView() // Should not be visible if isRecordingAudioForOverlay is false
                    case .recording, .draggingToCancel, .draggingToConvertToText:
                        WechatRecordingIndicator(
                            waveformData: displayWaveformData,
                            currentPhase: inputViewModel.weChatRecordingPhase // Pass the full phase
                        )
                        .frame(width: currentIndicatorWidth, height: indicatorHeight + indicatorTipHeight)
                        .offset(x: currentXOffset)
                        .animation(.linear(duration: 0.1), value: currentIndicatorWidth)
                        .animation(.linear(duration: 0.1), value: currentXOffset)
                    case .processingASR:
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                                .padding(.bottom, 5)
                            Text("Converting...") // Needs localization
                                .font(.footnote)
                                .foregroundColor(Color.white.opacity(0.8))
                        }
                    case .asrCompleteWithText(let transcribedText):
                        ASRResultView(inputViewModel: inputViewModel)
                    }
                    Spacer()

                    BottomControlsView(
                        currentPhase: inputViewModel.weChatRecordingPhase,
                        localization: localization,
                        inputViewModel: inputViewModel,
                        onCancel: { // This is for the X button when recording/dragging
                            inputViewModel.inputViewAction()(.deleteRecord)
                        },
                        onConvertToText: { /* Likely not used directly if drag-release triggers */ },
                        onSendTranscribedText: {
                            // If transcribedText is empty and there was no STT error, maybe send original voice? Or disallow.
                            if !inputViewModel.transcribedText.isEmpty {
                                inputViewModel.text = inputViewModel.transcribedText
                                // Decide: Send only text? Or text + original voice?
                                // If only text, ensure recording is cleared from attachments:
                                // inputViewModel.attachments.recording = nil
                            } else if inputViewModel.attachments.recording != nil {
                                // STT failed or empty, but voice note exists, send voice.
                                inputViewModel.text = "" // Clear any potentially empty transcribed text
                            }
                            inputViewModel.inputViewAction()(.send)
                            // ViewModel's send/reset should set phase to .idle
                        },
                        onSendVoiceAfterASR: {
                            inputViewModel.text = "" // Clear transcribed text
                            // Ensure recording is in attachments (should be from STT process)
                            inputViewModel.inputViewAction()(.send)
                        },
                        onCancelASR: { // For the "Cancel" button on the STT complete screen
                            inputViewModel.inputViewAction()(.deleteRecord) // Discards voice and text
                        },
                        inputBarHeight: inputBarHeight
                    )
                }
            }
            .ignoresSafeArea(.all)
            .onAppear {
                updateWaveformToDisplay()
            }
            .onReceive(timer) { _ in
                if inputViewModel.isRecordingAudioForOverlay &&
                   (inputViewModel.weChatRecordingPhase == .recording ||
                    inputViewModel.weChatRecordingPhase == .draggingToCancel ||
                    inputViewModel.weChatRecordingPhase == .draggingToConvertToText) {
                    updateWaveformToDisplay()
                }
            }
            .onChange(of: inputViewModel.attachments.recording?.waveformSamples) { _, _ in
                if inputViewModel.isRecordingAudioForOverlay &&
                   (inputViewModel.weChatRecordingPhase == .recording ||
                    inputViewModel.weChatRecordingPhase == .draggingToCancel ||
                    inputViewModel.weChatRecordingPhase == .draggingToConvertToText) {
                    if !inputViewModel.isDraggingInCancelZoneOverlay && !inputViewModel.isDraggingToConvertToTextZoneOverlay {
                         updateWaveformToDisplay()
                    }
                }
            }
            .onChange(of: inputViewModel.isDraggingInCancelZoneOverlay) { _, inCancelZone in
                if !inCancelZone && inputViewModel.weChatRecordingPhase == .draggingToCancel {
                    // If no longer in cancel zone (but drag didn't end), revert to normal recording UI
                    // This might be handled by the gesture's .onChanged setting phase to .recording
                } else {
                    updateWaveformToDisplay(forceUpdate: true) // Update indicator style even if frozen
                }
            }
            .onChange(of: inputViewModel.isDraggingToConvertToTextZoneOverlay) { _, inSTTZone in
                 if !inSTTZone && inputViewModel.weChatRecordingPhase == .draggingToConvertToText {
                    // Revert to normal recording UI if drag moves out
                } else {
                    updateWaveformToDisplay(forceUpdate: true)
                }
            }
//            .onPreferenceChange(CancelRectPreferenceKey.self) { newValue in
//                // Log what's coming in
//                Logger.log("ChatView.onPreferenceChange(CancelRect). NewRect=\(newValue)")
//
//            }
//            .onPreferenceChange(ConvertToTextRectPreferenceKey.self) { value in
//    //            self.convertToTextRectGlobal = value
//                Logger.log("ChatView updated ConvertToTextRectGlobal: \(value)")
//            }
        } else {
            EmptyView()
        }
    }

    private func updateWaveformToDisplay(forceUpdate: Bool = false) {
        if (inputViewModel.weChatRecordingPhase == .draggingToCancel || inputViewModel.weChatRecordingPhase == .draggingToConvertToText) && !forceUpdate {
            // Waveform should be static (frozen) when dragging to special zones, unless forced
            return
        }

        if inputViewModel.state == .isRecordingHold || inputViewModel.state == .isRecordingTap || inputViewModel.weChatRecordingPhase == .recording {
            let liveSamples = inputViewModel.attachments.recording?.waveformSamples ?? []
            if shouldUseRealSamples(liveSamples) {
                let recentLiveSamples = Array(liveSamples.suffix(numberOfSamplesForIndicator))
                self.displayWaveformData = padOrTruncateSamples(samples: recentLiveSamples, targetCount: numberOfSamplesForIndicator, defaultValue: 0.02)
            } else {
                animationStep += 1
                self.displayWaveformData = generateDefaultAnimatedWaveformData(count: numberOfSamplesForIndicator, step: animationStep)
            }
        } else {
            animationStep += 1
            self.displayWaveformData = generateDefaultAnimatedWaveformData(count: numberOfSamplesForIndicator, step: animationStep)
        }
    }

    private func shouldUseRealSamples(_ samples: [CGFloat]) -> Bool {
        guard !samples.isEmpty else { return false }
        let recentSamples = samples.suffix(samplesToAnalyzeForLowVoice)
        if let maxSample = recentSamples.max(), maxSample < lowVoiceThreshold {
            return false
        }
        return true
    }

    private func padOrTruncateSamples(samples: [CGFloat], targetCount: Int, defaultValue: CGFloat) -> [CGFloat] {
        if samples.count == targetCount { return samples }
        else if samples.count > targetCount { return Array(samples.suffix(targetCount)) }
        else {
            let paddingCount = targetCount - samples.count
            return Array(repeating: defaultValue, count: paddingCount) + samples
        }
    }

    private func generateDefaultAnimatedWaveformData(count: Int, step: Int) -> [CGFloat] {
        var data: [CGFloat] = Array(repeating: 0.05, count: count)
        let middleIndex = count / 2
        let wavePosition = CGFloat(step % (middleIndex + 1))
        let spreadDivisor = CGFloat(count) * 0.09
        for i in 0..<count {
            let distanceFromAbsoluteCenter = CGFloat(abs(i - middleIndex))
            let gaussianFactor = exp(-pow(distanceFromAbsoluteCenter - wavePosition, 2) / (2 * pow(spreadDivisor, 2)))
            let randomPeakHeight = CGFloat.random(in: 0.2...0.5)
            let barHeight = gaussianFactor * randomPeakHeight
            data[i] = max(data[i], min(max(barHeight, 0.05), 1.0))
        }
        return data
    }
}

// MARK: - Sub-components
struct DimmedGradientBackgroundView: View { /* ... as before ... */
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 80/255, green: 80/255, blue: 80/255).opacity(0.7),
                Color(red: 30/255, green: 30/255, blue: 30/255).opacity(1)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .edgesIgnoringSafeArea(.all)
    }
}

// MARK: - Preview (Optional, but good for the overlay itself)
struct WeChatRecordingOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        // Simulate a background like a chat view for context
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                Text("Your Chat Messages Would Be Here")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                Image(systemName: "message.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
            }
            // Then present the overlay
            //            WeChatRecordingOverlayView(inputViewModel: InputViewModel(),inputBarHeight: 48, )
        }
        .preferredColorScheme(.dark) // Often these overlays are designed for dark mode
    }
}
