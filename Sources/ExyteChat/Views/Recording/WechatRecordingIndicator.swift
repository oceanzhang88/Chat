// Chat/Sources/ExyteChat/Views/Recording/WechatRecordingIndicator.swift
import SwiftUI

struct WechatRecordingIndicator: View {
    @Environment(\.chatTheme) private var theme
    var inputViewModel: InputViewModel

    // Height for non-ASR states (main waveform display)
    private let baseWaveformIndicatorHeight: CGFloat = 70

    // ASR bubble properties
    private let asrBubbleGreen = Color(red: 118 / 255, green: 227 / 255, blue: 80 / 255)
    private let minASRBubbleHeight: CGFloat = 100  // Min height for the entire ASR bubble
    private let maxASRBubbleHeight: CGFloat = 160  // Max height for the entire ASR bubble

    // Waveform display properties
    private let barWidth: CGFloat = 2.0
    private let barSpacing: CGFloat = 1.5
    private let maxBarHeightForMainWaveform: CGFloat = 45
    private let visualMinBarRelativeHeight: CGFloat = 0.1
    private let defaultWaveBarColor: Color = Color(red: 100 / 255, green: 100 / 255, blue: 100 / 255)

    // Corner waveform icon properties
    private let cornerWaveformIconBarWidth: CGFloat = 1.5
    private let cornerWaveformIconBarSpacing: CGFloat = 1.5
    private let cornerWaveformIconMaxBarHeight: CGFloat = 22.0
    // numberOfSamplesForCornerIndicator is already used by currentDesiredMainWaveformBarCount in relevant phases
    // private let numberOfSamplesForCornerIndicator: Int = 10 // This constant remains, used in currentDesiredMainWaveformBarCount
    private let cornerIconAreaHeight: CGFloat = 35  // Approximate height needed for the corner icon + its padding

    @State private var processingDots: String = ""
    private let dotAnimationTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var dotCount: Int = 0

    private let bubbleCornerRadius: CGFloat = 22

    private var currentPhase: WeChatRecordingPhase {
        inputViewModel.weChatRecordingPhase
    }

    // Determines if the ASR content area (text + corner icon) should be shown
    private var shouldDisplayASRContentArea: Bool {
        currentPhase == .draggingToConvertToText || currentPhase == .processingASR
    }

    private var currentIndicatorColor: Color {
        switch currentPhase {
        case .draggingToCancel:
            return theme.colors.statusError
        default:
            return asrBubbleGreen
        }
    }

    private var tipSize: CGSize {
        return CGSize(width: 15, height: 8)
    }

    private var tipPosition: BubbleWithTipShape.TipPosition {
        .bottom_edge_horizontal_offset
    }

    private var tipOffsetPercentage: CGFloat {
        switch currentPhase {
        case .draggingToConvertToText, .processingASR:
            return 0.8
        default:
            return 0.5
        }
    }

    @State private var displayWaveformData: [CGFloat] = []
    @State private var animationStep: Int = 0
    private let waveformTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let lowVoiceThreshold: CGFloat = 0.1
    private let samplesToAnalyzeForLowVoice = 15
    private let defaultDesiredBarCount: Int = 25
    private let numberOfSamplesForCornerIndicator: Int = 10  // Keep for clarity, used by currentDesiredMainWaveformBarCount

    private var currentDesiredMainWaveformBarCount: Int {
        switch currentPhase {
        case .draggingToCancel:
            return defaultDesiredBarCount / 2
        case .draggingToConvertToText, .processingASR:
            return numberOfSamplesForCornerIndicator  // This ensures displayWaveformData has 10 bars for corner icon use
        default:
            return defaultDesiredBarCount
        }
    }

    @State private var currentASRBubbleHeight: CGFloat

    init(inputViewModel: InputViewModel) {
        self.inputViewModel = inputViewModel
        _displayWaveformData = State(initialValue: Array(repeating: visualMinBarRelativeHeight, count: defaultDesiredBarCount))
        _currentASRBubbleHeight = State(initialValue: minASRBubbleHeight)
    }

    var body: some View {
        ZStack {
            bubbleBackgroundShape
                .frame(height: shouldDisplayASRContentArea ? currentASRBubbleHeight : baseWaveformIndicatorHeight)
            Group {
                if shouldDisplayASRContentArea {
                    asrContentWithBackground
                } else {
                    mainWaveformWithBackground
                }
            }
        }
        .animation(.easeInOut(duration: 0.1), value: currentIndicatorColor)
        .onAppear {
            updateWaveformDisplayDataLogic()
            if shouldDisplayASRContentArea {
                updateASRBubbleHeight(for: inputViewModel.transcribedText, animated: false)
            }
        }
        .onChange(of: currentPhase) {
            _,
            newPhase in
            updateWaveformDisplayDataLogic()
            if newPhase == .draggingToConvertToText || newPhase == .processingASR {
                updateASRBubbleHeight(for: inputViewModel.transcribedText, animated: true)
            }
        }
        .onChange(of: inputViewModel.transcribedText) { _, newText in
            if shouldDisplayASRContentArea {
                updateASRBubbleHeight(for: newText, animated: true)
            }
        }
        .onReceive(dotAnimationTimer) { _ in
            let oldDots = processingDots
            if currentPhase == .draggingToConvertToText || currentPhase == .processingASR {
                dotCount = (dotCount + 1) % 3
                processingDots = String(repeating: ".", count: dotCount + 1)
            } else {
                dotCount = 0
                processingDots = ""
            }
            if oldDots != processingDots && shouldDisplayASRContentArea {
                updateASRBubbleHeight(for: inputViewModel.transcribedText, animated: true)
            }
        }
        .onReceive(waveformTimer) { _ in
            updateWaveformDisplayDataLogic()
        }
        // REMOVED: .onChange(of: displayWaveformData) that populated cornerIconDisplayData
    }

    private func updateASRBubbleHeight(for text: String, animated: Bool) {
        let intrinsicTextHeight = Self.calculateIntrinsicTextHeight(
            for: text,
            phase: currentPhase,
            processingDots: processingDots,
            constrainedByWidth: getASRBubbleContentWidth()
        )

        let contentHeight = intrinsicTextHeight + 6 + cornerIconAreaHeight
        let bubbleChromeHeight = 10 + (tipSize.height + 10)
        let calculatedTotalHeight = contentHeight + bubbleChromeHeight
        let newHeight = max(minASRBubbleHeight, min(calculatedTotalHeight, maxASRBubbleHeight))

        if animated {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                currentASRBubbleHeight = newHeight
            }
        } else {
            currentASRBubbleHeight = newHeight
        }
    }

    private var mainWaveformWithBackground: some View {
        mainWaveformDisplay
            .padding(.horizontal, currentPhase == .draggingToCancel ? 10 : 20)
            .padding(.top, 10)
            .padding(.bottom, tipSize.height + 10)
            .frame(height: baseWaveformIndicatorHeight)
    }

    private var asrContentWithBackground: some View {
        asrContentLayout
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, tipSize.height + 10)
            .frame(height: currentASRBubbleHeight)
    }

    private var bubbleBackgroundShape: some View {
        BubbleWithTipShape(
            cornerRadius: bubbleCornerRadius, tipSize: tipSize,
            tipPosition: tipPosition, tipOffsetPercentage: tipOffsetPercentage
        )
        .fill(currentIndicatorColor)
        .shadow(color: currentIndicatorColor.opacity(0.3), radius: 5, x: 0, y: 3)
    }

    @ViewBuilder
    private var mainWaveformDisplay: some View {
        HStack(spacing: barSpacing) {
            ForEach(Array(displayWaveformData.enumerated()), id: \.offset) { _, sample in
                let barHeightValue =
                    (maxBarHeightForMainWaveform * visualMinBarRelativeHeight)
                    + (sample * maxBarHeightForMainWaveform * (1.0 - visualMinBarRelativeHeight))
                Capsule()
                    .fill(defaultWaveBarColor)
                    .frame(width: barWidth, height: barHeightValue)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: sample)
            }
        }
        .frame(maxHeight: maxBarHeightForMainWaveform)
//        .animation(.easeInOut(duration: 0.15), value: displayWaveformData)
        .clipped()
    }

    @ViewBuilder
    private var asrContentLayout: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollViewProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    textAndDotsDisplayView
                        .padding(.vertical, 2)
                        .id("asrTextContentInsideIndicator")
                }
                .frame(maxHeight: maxASRBubbleHeight)
                .onChange(of: inputViewModel.transcribedText) { _, _ in
                    withAnimation {
                        scrollViewProxy.scrollTo("asrTextContentInsideIndicator", anchor: .bottom)
                    }
                }
            }

            cornerWaveformIcon  // This will now use displayWaveformData
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var textAndDotsDisplayView: some View {
        Group {
            if let errorMessage = inputViewModel.asrErrorMessage {
                Text(errorMessage).foregroundColor(theme.colors.statusError)
            } else {
                let textToShow = inputViewModel.transcribedText
                let dots = (currentPhase == .processingASR || currentPhase == .draggingToConvertToText) ? processingDots : ""

                if !textToShow.isEmpty {
                    Text(textToShow).foregroundColor(Color.black) + Text(dots).foregroundColor(Color(UIColor.darkGray))
                } else if !dots.isEmpty {
                    Text(dots).foregroundColor(Color(UIColor.darkGray))
                } else {
                    Text(" ").opacity(0)
                }
            }
        }
        .font(.system(size: 17, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cornerWaveformIcon: some View {
        // Now uses displayWaveformData.
        // When this icon is visible, displayWaveformData will have 10 bars due to currentDesiredMainWaveformBarCount.
        HStack(spacing: cornerWaveformIconBarSpacing) {
            ForEach(Array(displayWaveformData.enumerated()), id: \.offset) { _, sample in
                let barHeightValue =
                    (cornerWaveformIconMaxBarHeight * visualMinBarRelativeHeight * 2)
                    + (sample * cornerWaveformIconMaxBarHeight * (1.0 - visualMinBarRelativeHeight))

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: cornerWaveformIconBarWidth, height: barHeightValue)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: sample)
                //                    .transition(.scale(scale: 0.5, anchor: .center) .combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: cornerIconAreaHeight)
//        .animation(.easeInOut(duration: 0.15), value: displayWaveformData.count)  // displayWaveformData.count will be 10 here
    }

    private func shouldUseRealSamples(_ samples: [CGFloat]) -> Bool {
        guard !samples.isEmpty else { return false }
        let recentSamples = samples.suffix(samplesToAnalyzeForLowVoice)
        guard recentSamples.count >= min(5, samplesToAnalyzeForLowVoice) else {
            return true
        }
        if let maxSample = recentSamples.max(), maxSample < lowVoiceThreshold {
            return false
        }
        return true
    }

    private func generateDefaultWaveform(step: Int, count: Int) -> [CGFloat] {
        var currentFrameWaveform: [CGFloat] = Array(repeating: 0.0, count: count)
        guard count > 0 else { return [] }
        let middleIndexFloat = CGFloat(count - 1) / 2.0
        let peakAmplitude = 0.15 * sin(CGFloat(step) * 0.12) + 0.1
        let pulseCycleDuration: Int = 80
        let progressInCycle = CGFloat(step % pulseCycleDuration) / CGFloat(max(1, pulseCycleDuration - 1))
        let maxOffset = middleIndexFloat
        let waveCenterOffset = progressInCycle * maxOffset
        let peak1Position = middleIndexFloat - waveCenterOffset
        let peak2Position = middleIndexFloat + waveCenterOffset
        let spreadDivisor = CGFloat(count) * 0.08
        for i in 0..<count {
            let barPosition = CGFloat(i)
            let d1 = abs(barPosition - peak1Position)
            let g1 = exp(-pow(d1, 2) / (2 * pow(max(1, spreadDivisor), 2)))
            let d2 = abs(barPosition - peak2Position)
            let g2 = exp(-pow(d2, 2) / (2 * pow(max(1, spreadDivisor), 2)))
            currentFrameWaveform[i] = min(max(max(g1, g2) * peakAmplitude, 0.0), 1.0)
        }
        return currentFrameWaveform
    }
    
    // --- MODIFIED: generateAnimatedWaveformPattern to not use 'step' for pattern ---
    private func generateAnimatedWaveformPattern(count: Int, strengthMultiplier: CGFloat = 1.0) -> [CGFloat] {
        var waveform: [CGFloat] = Array(repeating: 0.0, count: count)
        guard count > 0 else { return [] }
        
        for i in 0..<count {
            // Generate a random base height for each bar
            let randomBaseHeight = CGFloat.random(in: 0.0...1.0)
            
            // Modulate by the overall strength
            var modulatedHeight = randomBaseHeight * strengthMultiplier
            
            // Ensure it's within 0-1 after strength modulation
            modulatedHeight = max(0.0, min(modulatedHeight, 1.0))
            
            // Apply the visualMinBarRelativeHeight mapping
            let finalHeight = visualMinBarRelativeHeight + modulatedHeight * (1.0 - visualMinBarRelativeHeight)
            
            waveform[i] = max(visualMinBarRelativeHeight, min(finalHeight, 1.0))
        }
        return waveform
    }
    // --- END MODIFICATION ---
    
    private func updateWaveformDisplayDataLogic() {
        let currentInputSamples = inputViewModel.attachments.recording?.waveformSamples ?? []
        let targetBarCount = self.currentDesiredMainWaveformBarCount
        let processedSourceData: [CGFloat]
        if shouldUseRealSamples(currentInputSamples) {
            let strengthWindow = currentInputSamples.suffix(targetBarCount * 2)
            let maxStrengthInWindow = strengthWindow.max() ?? 0.0
            let strengthMultiplier = max(visualMinBarRelativeHeight, min(maxStrengthInWindow, 0.5))
            
            // Generate waveform based on random jitter modulated by strength
            processedSourceData = generateAnimatedWaveformPattern(count: targetBarCount, strengthMultiplier: strengthMultiplier)
        } else {
            animationStep += 1
            processedSourceData = generateDefaultWaveform(step: animationStep, count: targetBarCount)
        }
        if self.displayWaveformData != processedSourceData {
            self.displayWaveformData = processedSourceData
        }
    }

    private func processAndCenterSamples(
        _ samples: [CGFloat], targetCount: Int, defaultValue: CGFloat
    ) -> [CGFloat] {
        guard targetCount > 0 else { return [] }
        let currentCount = samples.count
        if currentCount == targetCount {
            return samples
        } else if currentCount > targetCount {
            let overflow = currentCount - targetCount
            let L = overflow / 2
            let R = overflow - L
            return Array(samples[L..<(currentCount - R)])
        } else {
            let needed = targetCount - currentCount
            let L = needed / 2
            let R = needed - L
            return Array(repeating: defaultValue, count: L) + samples + Array(repeating: defaultValue, count: R)
        }
    }

    private func getASRBubbleContentWidth() -> CGFloat {
        let bubbleHorizontalPadding = 16 * 2
        let asrOverlayWidth = UIScreen.main.bounds.width * 0.9
        return asrOverlayWidth - CGFloat(bubbleHorizontalPadding)
    }

    static func calculateIntrinsicTextHeight(
        for text: String, phase: WeChatRecordingPhase, processingDots: String,
        constrainedByWidth width: CGFloat
    ) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 17, weight: .medium)
        var textToMeasure = text
        if phase == .processingASR || phase == .draggingToConvertToText {
            if textToMeasure.isEmpty {
                textToMeasure = processingDots.isEmpty ? " " : processingDots
            } else {
                textToMeasure += processingDots
            }
        }
        if textToMeasure
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            textToMeasure = " "
        }

        let textView = UITextView()
        textView.font = font
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.text = textToMeasure
        let size = textView.sizeThatFits(
            CGSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude)
        )
        let calculatedHeight = ceil(size.height)
        return max(20, calculatedHeight)
    }
}
