// Chat/Sources/ExyteChat/Views/InputView/WechatOverlay/WeChatRecordingOverlayView.swift
import SwiftUI

// MARK: - Main Overlay View
struct WeChatRecordingOverlayView: View {
    var inputViewModel: InputViewModel
    @Environment(\.chatTheme) private var theme

    @State private var displayWaveformData: [CGFloat] = [] // For passing to indicator
    @State private var animationStep: Int = 0 // For fallback animation

    let inputBarHeight: CGFloat
    var localization: ChatLocalization

//    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let numberOfSamplesForWaveform: Int = 25 // Number of bars for main waveform
    private let lowVoiceThreshold: CGFloat = 0.1
    private let samplesToAnalyzeForLowVoice = 15

    // --- Widths for the indicator based on phase ---
    private var recordingIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.45 } // IMG_0110.jpg reference for relative size
    private var cancelIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.2 } // Smaller for cancel (IMG_0110.jpg)
    private var asrIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.9 }// Wider for ASR text (IMG_0111.jpg)
    
    // Define this constant for use in both live and default cases if they share the same visual minimum
    private let visualMinBarRelativeHeight: CGFloat = 0.12

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

    var body: some View {
        ZStack(alignment: .bottom) {
            DimmedGradientBackgroundView()

            VStack(spacing: 0) {
                Spacer().frame(height: UIScreen.main.bounds.height * 0.4)  // Pushes dynamic content (indicator or ASR bubble) down
//                Spacer()
                
                // Conditional content based on phase
                Group {
                    switch inputViewModel.weChatRecordingPhase {
                    case .idle:
                        EmptyView()
                    case .recording, .draggingToCancel, .draggingToConvertToText, .processingASR:
                        WechatRecordingIndicator(
                            waveformData: displayWaveformData,  // Still needed for non-ASR phases
                            inputViewModel: inputViewModel  // Pass the viewModel
                        )
                        .frame(
                            width: currentRecordingIndicatorWidth
                        )  // Overlay controls width
                        // Height is internally managed and animated by WechatRecordingIndicator
                        .offset(x: currentRecordingIndicatorXOffset)
                        // Animate width and offset changes
                        .animation(
                            .easeInOut(duration: 0.15),
                            value: currentRecordingIndicatorWidth
                        )
                        .animation(
                            .easeInOut(duration: 0.15),
                            value: currentRecordingIndicatorXOffset
                        )
                        
                    case .asrCompleteWithText:  // String argument is handled by ASRResultView
                        // ASRResultView is for the *final static display* after ASR.
                        // The live text during .draggingToConvertToText is now inside WechatRecordingIndicator.
                        ASRResultView(
                            inputViewModel: inputViewModel, localization: localization,
                            targetWidth: asrIndicatorWidth
                        )
                        .transition(.opacity.combined(with: .scale(scale: 1.0)))
                    }
                }
                .padding(.bottom, 20)  // Some space above the bottom controls

                Spacer()

                BottomControlsView(
                    currentPhase: inputViewModel.weChatRecordingPhase,
                    localization: localization,
                    inputViewModel: inputViewModel,
                    inputBarHeight: inputBarHeight,
                    onCancel: { // For X button during recording/dragging to cancel
                        inputViewModel.inputViewAction()(.deleteRecord)
                    },
                    onConvertToText: {
                        DebugLogger.log("BottomControlsView: onConvertToText (direct tap) placeholder.")
                        /* Direct tap on "En" if needed, usually drag-release */
                    }
                )
            }
        }
        .edgesIgnoringSafeArea(.all) // Dimmed background covers all
//        .onReceive(timer) { _ in
//            // Update main waveform data only if the indicator is in a state that shows it
//            if inputViewModel.isRecordingAudioForOverlay &&
//               (inputViewModel.weChatRecordingPhase == .recording || inputViewModel.weChatRecordingPhase == .draggingToCancel) {
//                updateWaveformDisplayData()
//            }
//        }
        .onChange(of: inputViewModel.attachments.recording?.waveformSamples) { _, newSamples in
            if inputViewModel.isRecordingAudioForOverlay &&
               (inputViewModel.weChatRecordingPhase == .recording || inputViewModel.weChatRecordingPhase == .draggingToCancel) {
                updateWaveformDisplayData(samples: newSamples ?? [])
            }
        }
    }

    // Update waveform data for the main centered waveform
    private func updateWaveformDisplayData(samples: [CGFloat]? = nil) {
        let currentSamples = samples ?? inputViewModel.attachments.recording?.waveformSamples ?? []
        if shouldUseRealSamples(currentSamples) {
            // Processing for REAL LIVE SAMPLES
                    var processedLiveSamples: [CGFloat] = []
                    let recentLiveSamplesRaw = Array(currentSamples.suffix(numberOfSamplesForWaveform))

                    for rawSample in recentLiveSamplesRaw {
                        // Add the minimum base height to the raw sample.
                        // Raw sample is typically 0.0-1.0. visualMinBarRelativeHeight is also 0.0-1.0.
                        // The sum should then be clamped to 1.0.
                        let heightWithMin = visualMinBarRelativeHeight + rawSample
                        processedLiveSamples.append(min(max(heightWithMin, visualMinBarRelativeHeight), 1.0))
                    }
                    
                    // Pad or truncate if necessary. Padding should also use the visualMinBarRelativeHeight.
                    self.displayWaveformData = padOrTruncateSamples(samples: processedLiveSamples, targetCount: numberOfSamplesForWaveform, defaultValue: visualMinBarRelativeHeight)

        } else {
            animationStep += 1
            self.displayWaveformData = generateDefaultAnimatedWaveformData(count: numberOfSamplesForWaveform, step: animationStep)
        }
    }

    // Helper methods (shouldUseRealSamples, padOrTruncateSamples, generateDefaultAnimatedWaveformData) remain the same.
    private func shouldUseRealSamples(_ samples: [CGFloat]) -> Bool {
        guard !samples.isEmpty else { return false }
        let recentSamples = samples.suffix(samplesToAnalyzeForLowVoice)
        if let maxSample = recentSamples.max(), maxSample < lowVoiceThreshold { return false }
        return true
    }

    private func padOrTruncateSamples(samples: [CGFloat], targetCount: Int, defaultValue: CGFloat) -> [CGFloat] {
        if samples.count == targetCount {
            return samples
        } else if samples.count > targetCount {
            return Array(samples.suffix(targetCount))
        } else {
            let paddingCount = targetCount - samples.count
            // For "in-place" live view, prepending pads the "older" side of the fixed display.
            return Array(repeating: defaultValue, count: paddingCount) + samples
        }
    }

    private func generateDefaultAnimatedWaveformData(count: Int, step: Int) -> [CGFloat] {
        var currentFrameWaveform: [CGFloat] = Array(repeating: visualMinBarRelativeHeight, count: count)
        let middleIndexFloat = CGFloat(count - 1) / 2.0

        // --- Overall Amplitude Pulsing for the traveling waves ---
        // Peak height of the *additional* wave, on top of minBarRelativeHeight.
        // If peakAmplitude is 0.5 and minBarRelativeHeight is 0.15, total max can be 0.65.
        let peakAmplitude = 0.15 * sin(CGFloat(step) * 0.12) + 0.05 // Adjusted for potentially less total height if min is higher

        // --- Wave Movement: Two peaks moving from center to sides ---
        let pulseCycleDuration: Int = 80 // Slower, smoother wave travel
        let progressInCycle = CGFloat(step % pulseCycleDuration) / CGFloat(max(1, pulseCycleDuration - 1))

        let maxOffset = middleIndexFloat * 0.9 // Let waves move almost to edges
        let waveCenterOffset = progressInCycle * maxOffset

        let peak1Position = middleIndexFloat - waveCenterOffset // Moves left
        let peak2Position = middleIndexFloat + waveCenterOffset // Moves right

        // --- Spread (Width) of each individual wave/hump ---
        let spreadDivisor = CGFloat(count) * 0.08 // Slightly wider individual humps

        for i in 0..<count {
            let barPosition = CGFloat(i)

            let distanceToPeak1 = abs(barPosition - peak1Position)
            let gaussianFactor1 = exp(-pow(distanceToPeak1, 2) / (2 * pow(spreadDivisor, 2)))

            let distanceToPeak2 = abs(barPosition - peak2Position)
            let gaussianFactor2 = exp(-pow(distanceToPeak2, 2) / (2 * pow(spreadDivisor, 2)))
            
            let combinedGaussianFactor = max(gaussianFactor1, gaussianFactor2)
            
            // Calculate the height *added by the wave* to the base minimum
            let waveAddedHeight = combinedGaussianFactor * peakAmplitude
            
            // Final bar height for *this frame's calculation* is the base minimum + wave's contribution
            let barHeightForThisFrame = visualMinBarRelativeHeight + waveAddedHeight
            
            // Assign this frame's calculated height, clamped between the min and 1.0
            currentFrameWaveform[i] = min(max(barHeightForThisFrame, visualMinBarRelativeHeight), 1.0)
        }
        
        return currentFrameWaveform
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
        vm.isRecordingAudioForOverlay = phase != .idle && phase != .asrCompleteWithText("")
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
            sendVoiceButtonText: "send"
            
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
