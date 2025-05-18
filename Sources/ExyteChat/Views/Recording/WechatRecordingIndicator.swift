// Chat/Sources/ExyteChat/Views/Recording/WechatRecordingIndicator.swift
import SwiftUI

struct WechatRecordingIndicator: View {
    @Environment(\.chatTheme) private var theme
    var inputViewModel: InputViewModel

    // Height for non-ASR states (main waveform display)
    private let baseWaveformIndicatorHeight: CGFloat = 70

    // ASR bubble properties
    private let asrBubbleGreen = Color(red: 118/255, green: 227/255, blue: 80/255)
    private let minASRBubbleHeight: CGFloat = 100 // Min height for the entire ASR bubble
    private let maxASRBubbleHeight: CGFloat = 150 // Max height for the entire ASR bubble
    
    // Waveform display properties
    private let barWidth: CGFloat = 2.0
    private let barSpacing: CGFloat = 1.5
    private let maxBarHeightForMainWaveform: CGFloat = 45
    private let visualMinBarRelativeHeight: CGFloat = 0.1
    private let defaultWaveBarColor: Color = Color(red: 100/255, green: 100/255, blue: 100/255)

    // Corner waveform icon properties
    private let cornerWaveformIconBarWidth: CGFloat = 1.5
    private let cornerWaveformIconBarSpacing: CGFloat = 1.0
    private let cornerWaveformIconMaxBarHeight: CGFloat = 22.0
    private let numberOfSamplesForCornerIndicator: Int = 10
    private let cornerIconAreaHeight: CGFloat = 35 // Approximate height needed for the corner icon + its padding

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
    
    @State private var cornerIconDisplayData: [CGFloat] = []
    @State private var displayWaveformData: [CGFloat] = []
    @State private var animationStep: Int = 0
    private let waveformTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let lowVoiceThreshold: CGFloat = 0.1
    private let samplesToAnalyzeForLowVoice = 15
    private let defaultDesiredBarCount: Int = 25

    private var currentDesiredMainWaveformBarCount: Int {
        switch currentPhase {
        case .draggingToCancel:
            return defaultDesiredBarCount / 2
        case .draggingToConvertToText, .processingASR:
            return numberOfSamplesForCornerIndicator
        default:
            return defaultDesiredBarCount
        }
    }
    
    // Actual height of the ASR bubble, considering text and icon
    @State private var currentASRBubbleHeight: CGFloat

    init(inputViewModel: InputViewModel) {
        self.inputViewModel = inputViewModel
        _displayWaveformData = State(initialValue: Array(repeating: visualMinBarRelativeHeight, count: defaultDesiredBarCount))
        _currentASRBubbleHeight = State(initialValue: minASRBubbleHeight) // Start ASR bubble at min height
    }

    var body: some View {
        ZStack {
            bubbleBackgroundShape
                .frame(height: shouldDisplayASRContentArea ? currentASRBubbleHeight: baseWaveformIndicatorHeight) // Fixed height
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
            updateWaveformDisplayDataLogic() // For corner icon data primarily
            if shouldDisplayASRContentArea {
                updateASRBubbleHeight(for: inputViewModel.transcribedText, animated: false)
            }
        }
        .onChange(of: currentPhase) { _, newPhase in
            updateWaveformDisplayDataLogic()
            if newPhase == .draggingToConvertToText || newPhase == .processingASR {
                updateASRBubbleHeight(for: inputViewModel.transcribedText, animated: true)
            } else {
                // If switching away from ASR, could reset currentASRBubbleHeight if needed,
                // but mainWaveformWithBackground has a fixed height.
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
            if oldDots != processingDots && shouldDisplayASRContentArea { // Re-calculate height if dots change
                 updateASRBubbleHeight(for: inputViewModel.transcribedText, animated: true)
            }
        }
        .onReceive(waveformTimer) { _ in // Keep updating waveform data source
             updateWaveformDisplayDataLogic()
         }
//        .onChange(of: inputViewModel.attachments.recording?.waveformSamples) { _, _ in
//             updateWaveformDisplayDataLogic()
//        }
        .onChange(of: displayWaveformData) { _, newMainWaveformSource in // Update corner icon based on main data
            let baseSamplesForCorner: [CGFloat]
            if shouldUseRealSamples(inputViewModel.attachments.recording?.waveformSamples ?? []) {
                 let allSamples = inputViewModel.attachments.recording?.waveformSamples ?? []
                 let window = allSamples.suffix(defaultDesiredBarCount * 3)
                 let minSample = window.min() ?? 0
                 let maxSample = max(1.0, window.max() ?? 1.0)
                 if (maxSample - minSample) != 0 {
                    baseSamplesForCorner = window.map { ($0 - minSample) / (maxSample - minSample) }
                 } else {
                    baseSamplesForCorner = window.map { _ in 0.0 }
                 }
            } else {
                baseSamplesForCorner = generateDefaultWaveform(step: animationStep, count: defaultDesiredBarCount)
            }
            self.cornerIconDisplayData = processAndCenterSamples(baseSamplesForCorner, targetCount: numberOfSamplesForCornerIndicator, defaultValue: visualMinBarRelativeHeight)
        }
    }

    // --- Bubble Height Calculation ---
    private func updateASRBubbleHeight(for text: String, animated: Bool) {
        let intrinsicTextHeight = Self.calculateIntrinsicTextHeight(
            for: text,
            phase: currentPhase,
            processingDots: processingDots,
            constrainedByWidth: getASRBubbleContentWidth()
        )
        
        // Total height needed for content: text + padding above icon + icon height
        let contentHeight = intrinsicTextHeight + 6 /*padding above icon*/ + cornerIconAreaHeight
        
        // Bubble's chrome: top padding + (tip height + bottom padding for tip)
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
    
    // --- Views with Background ---
    private var mainWaveformWithBackground: some View {
        mainWaveformDisplay
            .padding(.horizontal, currentPhase == .draggingToCancel ? 10 : 20)
            .padding(.top, 10) // Content padding from bubble edge
            .padding(.bottom, tipSize.height + 10) // Content padding + tip space
//            .background(bubbleBackgroundShape)
            .frame(height: baseWaveformIndicatorHeight) // Fixed height
    }

    private var asrContentWithBackground: some View {
        asrContentLayout // This now fits its content
            .padding(.horizontal, 16) // Bubble's horizontal padding
            .padding(.top, 10)          // Bubble's top padding
            .padding(.bottom, tipSize.height + 10) // Bubble's bottom padding (for tip)
//            .background(bubbleBackgroundShape)
            .frame(height: currentASRBubbleHeight) // Dynamic height for the whole bubble
    }
    
    private var bubbleBackgroundShape: some View {
        BubbleWithTipShape(
            cornerRadius: bubbleCornerRadius,
            tipSize: tipSize,
            tipPosition: tipPosition,
            tipOffsetPercentage: tipOffsetPercentage
        )
        .fill(currentIndicatorColor)
        .shadow(color: currentIndicatorColor.opacity(0.3), radius: 5, x: 0, y: 3)
    }

    // --- Display Components ---
    @ViewBuilder
    private var mainWaveformDisplay: some View {
        HStack(spacing: barSpacing) {
            ForEach(Array(displayWaveformData.enumerated()), id: \.offset) { _, sample in
                let barHeightValue = (maxBarHeightForMainWaveform * visualMinBarRelativeHeight) + (sample * maxBarHeightForMainWaveform * (1.0 - visualMinBarRelativeHeight))
                Capsule()
                    .fill(defaultWaveBarColor)
                    .frame(width: barWidth, height: barHeightValue )
                    .animation(.spring(response: 0.1, dampingFraction: 0.7), value: sample)
            }
        }
        .frame(maxHeight: maxBarHeightForMainWaveform) // Ensure main waveform area respects its max height
        .animation(.easeInOut(duration: 0.15), value: displayWaveformData)
        .clipped()
    }
    
    // Layout for ASR Text and Corner Waveform Icon
    @ViewBuilder
    private var asrContentLayout: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollViewProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    textAndDotsDisplayView
                        .padding(.vertical, 2) // Minimal padding around the text block itself
                        .id("asrTextContentInsideIndicator") // For ScrollViewReader
                }
                .frame(maxHeight: maxASRBubbleHeight)
                // The ScrollView should take up available space, but not more than needed for maxASRBubbleHeight
                // Its max height is implicitly controlled by the parent's frame (`asrContentWithBackground`)
                // and the space taken by `cornerWaveformIcon`.
                // ScrollView will be constrained by the parent ZStack's animatedIndicatorHeight
                .onChange(of: inputViewModel.transcribedText) { _,_  in
//                    if showASRTextView {
                    withAnimation { scrollViewProxy.scrollTo("asrTextContentInsideIndicator", anchor: .bottom) }
//                    }
                }
            }
            
            cornerWaveformIcon
                .padding(.top, 6) // Space between text area and icon
        }
    }
    
    @ViewBuilder
    private var textAndDotsDisplayView: some View {
        Group {
            if let errorMessage = inputViewModel.asrErrorMessage {
                Text(errorMessage).foregroundColor(theme.colors.statusError)
            } else {
                let textToShow = inputViewModel.transcribedText
                // Show dots if processing, either alone or appended
                let dots = (currentPhase == .processingASR || currentPhase == .draggingToConvertToText) ? processingDots : ""

                if !textToShow.isEmpty {
                    Text(textToShow + dots).foregroundColor(Color.black)
                } else if !dots.isEmpty { // Only dots if text is empty AND processing/dragging
                    Text(dots).foregroundColor(Color(UIColor.darkGray))
                } else {
                    Text(" ").opacity(0) // Placeholder for height calculation if totally empty
                }
            }
        }
        .font(.system(size: 17, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading) // Text aligns left
    }
    
    @ViewBuilder
    private var cornerWaveformIcon: some View {
        HStack(spacing: cornerWaveformIconBarSpacing) {
            ForEach(Array(cornerIconDisplayData.enumerated()), id: \.offset) { _, sample in
                // Calculate height based on sample and max height
                let sampleBasedHeight = (cornerWaveformIconMaxBarHeight * visualMinBarRelativeHeight) + (sample * cornerWaveformIconMaxBarHeight * (1.0 - visualMinBarRelativeHeight))
                // Ensure the bar is at least cornerWaveformIconMinAbsoluteBarHeight pixels high, but not exceeding cornerWaveformIconMaxBarHeight
                let renderedHeight = max(5, min(sampleBasedHeight, cornerWaveformIconMaxBarHeight))

                Capsule()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: cornerWaveformIconBarWidth, height: renderedHeight) // Use the new renderedHeight
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: sample) // Animates based on sample changes
                    .transition(.scale(scale: 0.5, anchor: .center).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing) // Icon to the right
        .frame(height: cornerIconAreaHeight) // Fixed height for the icon area
        .animation(.easeInOut(duration: 0.15), value: cornerIconDisplayData.count)
    }

    // --- Waveform Data Logic ---
    private func shouldUseRealSamples(_ samples: [CGFloat]) -> Bool {
        guard !samples.isEmpty else { return false }
        let recentSamples = samples.suffix(samplesToAnalyzeForLowVoice)
        guard recentSamples.count >= min(5, samplesToAnalyzeForLowVoice) else { return true }
        if let maxSample = recentSamples.max(), maxSample < lowVoiceThreshold { return false }
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
            let d1 = abs(barPosition - peak1Position); let g1 = exp(-pow(d1,2)/(2*pow(max(1,spreadDivisor),2)))
            let d2 = abs(barPosition - peak2Position); let g2 = exp(-pow(d2,2)/(2*pow(max(1,spreadDivisor),2)))
            currentFrameWaveform[i] = min(max(max(g1,g2)*peakAmplitude,0.0),1.0)
        }
        return currentFrameWaveform
    }

    private func updateWaveformDisplayDataLogic() {
        let currentInputSamples = inputViewModel.attachments.recording?.waveformSamples ?? []
        let targetBarCount = self.currentDesiredMainWaveformBarCount
        let processedSourceData: [CGFloat]
        if shouldUseRealSamples(currentInputSamples) {
            let window = currentInputSamples.suffix(targetBarCount * 3)
            let minSample = window.min() ?? 0; let maxSample = max(1.0, window.max() ?? 1.0)
            let normWindow: [CGFloat] = (maxSample-minSample)>0.001 ? window.map{($0-minSample)/(maxSample-minSample)} : window.map{_ in 0.0}
            processedSourceData = processAndCenterSamples(normWindow, targetCount: targetBarCount, defaultValue: 0.0)
        } else {
            animationStep += 1
            processedSourceData = generateDefaultWaveform(step: animationStep, count: targetBarCount)
        }
        if self.displayWaveformData != processedSourceData { self.displayWaveformData = processedSourceData }
    }

    private func processAndCenterSamples(_ samples: [CGFloat], targetCount: Int, defaultValue: CGFloat) -> [CGFloat] {
        guard targetCount > 0 else { return [] }
        let currentCount = samples.count
        if currentCount == targetCount { return samples }
        else if currentCount > targetCount {
            let overflow = currentCount-targetCount; let L = overflow/2; let R = overflow-L
            return Array(samples[L..<(currentCount-R)])
        } else {
            let needed = targetCount-currentCount; let L = needed/2; let R = needed-L
            return Array(repeating:defaultValue,count:L)+samples+Array(repeating:defaultValue,count:R)
        }
    }
    
    // --- Helpers ---
    private func getASRBubbleContentWidth() -> CGFloat {
        let bubbleHorizontalPadding = 16 * 2 // From asrContentWithBackground
        let asrOverlayWidth = UIScreen.main.bounds.width * 0.9 // From WeChatRecordingOverlayView
        return asrOverlayWidth - CGFloat(bubbleHorizontalPadding)
    }
    
    static func calculateIntrinsicTextHeight(for text: String, phase: WeChatRecordingPhase, processingDots: String, constrainedByWidth width: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 17, weight: .medium)
        var textToMeasure = text
        if phase == .processingASR || phase == .draggingToConvertToText {
            if textToMeasure.isEmpty { textToMeasure = processingDots.isEmpty ? " " : processingDots }
            else { textToMeasure += processingDots }
        }
        if textToMeasure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { textToMeasure = " " }

        let textView = UITextView()
        textView.font = font; textView.textContainerInset = .zero; textView.textContainer.lineFragmentPadding = 0
        textView.text = textToMeasure
        let size = textView.sizeThatFits(CGSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude))
        let calculatedHeight = ceil(size.height)
        return max(20, calculatedHeight) // Ensure min one line height (approx 20 for system font 17)
    }
}

