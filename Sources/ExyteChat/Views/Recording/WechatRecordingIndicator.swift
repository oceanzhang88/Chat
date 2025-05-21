// Chat/Sources/ExyteChat/Views/Recording/WechatRecordingIndicator.swift
import SwiftUI

@MainActor
struct WechatRecordingIndicator: View {
    @Environment(\.chatTheme) private var theme
    var inputViewModel: InputViewModel

    // ASR bubble properties
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

    // Constants from ASRBubbleMetrics or local if truly specific
    private let baseWaveformIndicatorHeight: CGFloat = 70 // For non-ASR states
    private let asrBubbleGreen = Color(red: 118 / 255, green: 227 / 255, blue: 80 / 255)
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

//    @State private var currentASRBubbleHeight: CGFloat

    init(inputViewModel: InputViewModel) {
        self.inputViewModel = inputViewModel
        _displayWaveformData = State(initialValue: Array(repeating: visualMinBarRelativeHeight, count: defaultDesiredBarCount))
//        _currentASRBubbleHeight = State(initialValue: minASRBubbleHeight)
    }

    var body: some View {
        ZStack {
            bubbleBackgroundShape
                .frame(height: shouldDisplayASRContentArea ? inputViewModel.currentASRBubbleHeight : baseWaveformIndicatorHeight)
            Group {
                if shouldDisplayASRContentArea {
                    asrContentLayout
                    // Crucially, ensure this content VSTACK is also constrained by the dynamic bubble height
                    // and respects internal padding for the bubble shape itself.
                        .frame(height: inputViewModel.currentASRBubbleHeight)
                    // Clip the content to the bubble shape if it ever tries to overflow due to internal miscalculation.
                        .clipShape(BubbleWithTipShape(cornerRadius: bubbleCornerRadius, tipSize: tipSize, tipPosition: tipPosition, tipOffsetPercentage: tipOffsetPercentage))

                } else {
                    mainWaveformDisplay
                }
            }
        }
        .animation(.easeInOut(duration: 0.1), value: currentIndicatorColor)
        .onAppear {
            updateWaveformDisplayDataLogic()
            if shouldDisplayASRContentArea {
                updateAndAnimateBubbleHeight()
            }
        }
        .onChange(of: currentPhase) {_, newPhase in
            updateWaveformDisplayDataLogic()
            if newPhase == .draggingToConvertToText || newPhase == .processingASR {
                updateAndAnimateBubbleHeight()
            }
        }
        .onChange(of: inputViewModel.transcribedText) { _, newText in
            if shouldDisplayASRContentArea {
                updateAndAnimateBubbleHeight()
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
                updateAndAnimateBubbleHeight()
            }
        }
        .onReceive(waveformTimer) { _ in
            updateWaveformDisplayDataLogic()
        }
        // REMOVED: .onChange(of: displayWaveformData) that populated cornerIconDisplayData
    }
    
    @ViewBuilder
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
        // Padding for main waveform display inside its bubble
        .padding(.horizontal, currentPhase == .draggingToCancel ? 10 : 20)
        .padding(.top, ASRBubbleMetrics.indicatorTopChromePadding)
        .padding(.bottom, ASRBubbleMetrics.tipHeightComponent + ASRBubbleMetrics.indicatorBottomChromePadding)
        .frame(height: baseWaveformIndicatorHeight) 
    }

    @ViewBuilder
    private var asrContentLayout: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollViewProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    textAndDotsDisplayView
                    // Apply consistent padding HERE for the text content itself
                        .padding(.horizontal, ASRBubbleMetrics.horizontalPadding)
                        .padding(.vertical, ASRBubbleMetrics.verticalPadding)
                        .id("asrTextContentInsideIndicator")
                }
                .frame(maxHeight: .infinity)
                .onChange(of: inputViewModel.transcribedText) { _, newText in
                    let targetBubbleHeight = WechatRecordingIndicator.calculateDynamicASRBubbleHeight(
                        forText: newText,
                        phase: currentPhase, // Ensure 'currentPhase' is accessible here
                        processingDots: processingDots, // Ensure 'processingDots' is accessible here
                        viewModel: inputViewModel,
                        indicatorWidth: currentIndicatorOverallWidth // Ensure 'currentIndicatorOverallWidth' is accessible
                    )
                    
                    // Only scroll if the bubble's height is capped at the maximum.
                    // This implies the content is overflowing, and the bubble cannot grow further.
                    // A small tolerance is added for floating-point comparisons.
                    if targetBubbleHeight >= ASRBubbleMetrics.maxOverallHeight - 0.1 {
                        // Defer scroll slightly to allow height animation to start/settle.
                        // This schedules the scroll for the next run loop pass.
                        DispatchQueue.main.async {
                            withAnimation { // Keep the scroll itself animated
                                scrollViewProxy.scrollTo("asrTextContentInsideIndicator", anchor: .bottom)
                            }
                        }
                    }
                    // If targetBubbleHeight < maxOverallHeight, the bubble will grow,
                    // and this growth should reveal the new text. No explicit scroll
                    // is forced in this case, as it might conflict with the growth animation.
                }
                .onAppear { // Also scroll to bottom when the view first appears if there's text
                    if !inputViewModel.transcribedText.isEmpty {
                        DispatchQueue.main.async {
                            // No animation needed on initial appear usually, but can be added.
                            scrollViewProxy.scrollTo("asrTextContentInsideIndicator", anchor: .bottom)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                cornerWaveformIcon  // This will now use displayWaveformData
            }
            .padding(.top, ASRBubbleMetrics.indicatorTextToIconSpacing)
            .frame(height: ASRBubbleMetrics.indicatorCornerIconAreaHeight)
            // Horizontal padding for the icon container to inset it from the bubble edge
            .padding(.horizontal, ASRBubbleMetrics.horizontalPadding)
        }
        // Padding for the entire content block (text + icon) inside the bubble shape,
        // accounting for top chrome and making space for bottom chrome + tip.
        .padding(.top, ASRBubbleMetrics.indicatorTopChromePadding)
        .padding(.bottom, ASRBubbleMetrics.tipHeightComponent + ASRBubbleMetrics.indicatorBottomChromePadding)
//        .padding(.horizontal, ASRBubbleMetrics.horizontalPadding) // Apply consistent horizontal padding
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
//        .frame(maxWidth: .infinity, alignment: .trailing)
//        .frame(height: cornerIconAreaHeight)
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

    // Calculate the width for the text content area
    private func getASRBubbleTextContentWidth(for phase: WeChatRecordingPhase, overlayWidth: CGFloat) -> CGFloat {
        return overlayWidth - (ASRBubbleMetrics.horizontalPadding * 2)
    }

    
    static func calculateDynamicASRBubbleHeight(
        forText text: String,
        phase: WeChatRecordingPhase,
        processingDots: String,
        viewModel: InputViewModel, // To access other relevant states if needed
        indicatorWidth: CGFloat // The total width available for the indicator bubble
    ) -> CGFloat {
        
        let textContentWidth = indicatorWidth - (ASRBubbleMetrics.horizontalPadding * 2) // Width available for text
        
        let effectiveText = text.isEmpty && (phase == .draggingToConvertToText || phase == .processingASR) ?
        (processingDots.isEmpty ? " " : processingDots) : // Use dots if text is empty during processing
        (text.isEmpty ? " " : text) // Use a space for measurement if text is truly empty, to get min height
        
        // Calculate the intrinsic height of the text content itself.
        let intrinsicTextHeight = Self.calculateIntrinsicTextHeight(
            for: effectiveText,
            constrainedByWidth: textContentWidth
        )
        
        // The ScrollView that contains the text has its own vertical padding.
        // This padding needs to be added to the intrinsicTextHeight to get the total height
        // required by the scrollable content area.
        // ASRBubbleMetrics.verticalPadding is likely applied on top and bottom of the text within the ScrollView.
        let scrollableContentHeight = intrinsicTextHeight + (ASRBubbleMetrics.verticalPadding * 2)
        
        // Now, calculate the core content height of the bubble, which includes the
        // scrollable text area, spacing, and the corner waveform icon area.
        let coreContentHeight = scrollableContentHeight + ASRBubbleMetrics.indicatorTextToIconSpacing + ASRBubbleMetrics.indicatorCornerIconAreaHeight
        
        // Finally, add the bubble's own chrome (overall padding and tip area height)
        // to get the total calculated height for the bubble.
        let bubbleChromeHeight = ASRBubbleMetrics.indicatorTopChromePadding + ASRBubbleMetrics.tipHeightComponent + ASRBubbleMetrics.indicatorBottomChromePadding
        let calculatedTotalHeight = coreContentHeight + bubbleChromeHeight
        
        // Clamp the calculated height between the defined min and max overall heights for the bubble.
        let newHeight = max(ASRBubbleMetrics.minOverallHeight, min(calculatedTotalHeight, ASRBubbleMetrics.maxOverallHeight))
        
        // For debugging:
        // DebugLogger.log("BubbleHeightCalc: effectiveText='\(effectiveText.prefix(20))', intrinsicTextH=\(intrinsicTextHeight), scrollableContentH=\(scrollableContentHeight), coreContentH=\(coreContentHeight), totalCalcH=\(calculatedTotalHeight), finalH=\(newHeight)")
        
        return newHeight
    }
    
    // Static intrinsic text height calculator (can be shared)
    static func calculateIntrinsicTextHeight(
        for text: String,
        constrainedByWidth width: CGFloat
    ) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 17, weight: .medium)
        let textToMeasure = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : text
        
        let textView = UITextView()
        textView.font = font
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.text = textToMeasure
        let size = textView.sizeThatFits(CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        return ceil(size.height)
    }
    
    
    @MainActor private func updateAndAnimateBubbleHeight() {
        let newHeight = WechatRecordingIndicator.calculateDynamicASRBubbleHeight(
            forText: inputViewModel.transcribedText,
            phase: currentPhase,
            processingDots: processingDots,
            viewModel: inputViewModel,
            indicatorWidth: currentIndicatorOverallWidth // Pass the correct width
        )
        
        if abs(inputViewModel.currentASRBubbleHeight - newHeight) > 1 { // Avoid jitter for tiny changes
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                inputViewModel.currentASRBubbleHeight = newHeight
            }
        } else if inputViewModel.currentASRBubbleHeight != newHeight {
            inputViewModel.currentASRBubbleHeight = newHeight // Update without animation for small adjustments
        }
    }
    
    // Helper to get the current overall width of this indicator
    private var currentIndicatorOverallWidth: CGFloat {
        // This should reflect the width set by WeChatRecordingOverlayView
        // For simplicity, assuming it's mostly asrIndicatorWidth when ASR content is shown
        switch currentPhase {
        case .draggingToCancel: return UIScreen.main.bounds.width * 0.2 // cancelIndicatorWidth
        case .draggingToConvertToText, .processingASR: return UIScreen.main.bounds.width * 0.9 // asrIndicatorWidth
        default: return UIScreen.main.bounds.width * 0.45 // recordingIndicatorWidth
        }
    }
}
