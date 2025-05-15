// Chat/Sources/ExyteChat/Views/Recording/WechatRecordingIndicator.swift
import SwiftUI

struct WechatRecordingIndicator: View {
    @Environment(\.chatTheme) private var theme
    @ObservedObject var inputViewModel: InputViewModel

    var waveformData: [CGFloat] // Passed for .recording and .draggingToCancel

    // Base height for the waveform display, and initial height for ASR display
    private let baseIndicatorHeight: CGFloat = 70

    // State for the actual animated height of the indicator bubble
    @State private var animatedIndicatorHeight: CGFloat
    @State private var hasInitiatedASRHeightAnimation: Bool = false

    // Waveform display properties
    private let barWidth: CGFloat = 2.0
    private let barSpacing: CGFloat = 1.5
    private let maxBarHeight: CGFloat = 45
    private let defaultWaveBarColor: Color = Color(red: 100/255, green: 100/255, blue: 100/255)

    // ASR text display properties (matching IMG_0111.jpg)
    private let asrBubbleGreen = Color(red: 118/255, green: 227/255, blue: 80/255)
    private let minASRTextHeight: CGFloat = 100 // Start at baseIndicatorHeight
    private let maxASRTextHeight: CGFloat = 150
    private let cornerWaveformIconBarWidth: CGFloat = 1.5
    private let cornerWaveformIconBarSpacing: CGFloat = 1.0
    private let cornerWaveformIconMaxBarHeight: CGFloat = 12.0
    private let numberOfSamplesForCornerIndicator: Int = 10 // For the small static-like waveform icon
    @State private var displayCornerWaveformIconData: [CGFloat] = []
    // Timer for the corner waveform icon to give it a subtle "live" feel if desired
    private let cornerWaveformTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()


    private let bubbleCornerRadius: CGFloat = 22 // Consistent corner radius

    // --- Computed properties based on currentPhase ---
    private var currentPhase: WeChatRecordingPhase {
        inputViewModel.weChatRecordingPhase
    }

    private var showASRTextView: Bool {
        currentPhase == .draggingToConvertToText || currentPhase == .processingASR
    }

    private var currentIndicatorColor: Color {
        switch currentPhase {
        case .draggingToCancel:
            return theme.colors.statusError // Red (IMG_0110.jpg)
        default: // .recording
            return asrBubbleGreen // WeChat-like greyish for recording
        }
    }

    private var currentIndicatorShadowColor: Color {
        currentIndicatorColor.opacity(0.3)
    }

    // Tip configuration based on phase
    private var tipSize: CGSize {
        // All relevant phases here have a tip
        return CGSize(width: 15, height: 8)
    }

    private var tipPosition: BubbleWithTipShape.TipPosition {
        .bottom_edge_horizontal_offset // Tip is always on the bottom edge
    }

    // Tip's horizontal position (0.0 left, 0.5 center, 1.0 right of the BUBBLE's width)
    private var tipOffsetPercentage: CGFloat {
        switch currentPhase {
        case .draggingToConvertToText, .processingASR:
            return 0.8 // Towards the right for the wide green bubble (IMG_0111.jpg)
        default: // .recording
            return 0.5 // Centered for the default recording bubble
        }
    }

    init(waveformData: [CGFloat], inputViewModel: InputViewModel) {
        self.waveformData = waveformData
        _inputViewModel = ObservedObject(wrappedValue: inputViewModel)
        _animatedIndicatorHeight = State(initialValue: baseIndicatorHeight)
        // Initialize corner waveform icon data once
        _displayCornerWaveformIconData = State(initialValue: staticWaveformIconData(count: numberOfSamplesForCornerIndicator))
    }

    // For a more static but still "designed" corner waveform icon
   private func staticWaveformIconData(count: Int) -> [CGFloat] {
        var data = [CGFloat]()
        for i in 0..<count {
            let progress = CGFloat(i) / CGFloat(count - 1)
            // Create a simple tapering shape, could be more sophisticated
            let sample = 0.2 + (0.8 * sin(progress * .pi))
            data.append(min(1.0, max(0.1, sample * CGFloat.random(in: 0.7...1.0))))
        }
        return data
    }


    var body: some View {
        ZStack {
            BubbleWithTipShape(
                cornerRadius: bubbleCornerRadius,
                tipSize: tipSize,
                tipPosition: tipPosition,
                tipOffsetPercentage: tipOffsetPercentage
            )
            .fill(currentIndicatorColor)
            .shadow(color: currentIndicatorShadowColor, radius: 5, x: 0, y: 3)

            Group {
                if showASRTextView {
                    asrTextView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10) // Padding for text content
                } else { // .recording or .draggingToCancel
                    waveformView
                        // Dynamic padding to keep waveform centered and above tip
                        .padding(.horizontal, currentPhase == .draggingToCancel ? 10 : 20)
                        .padding(.bottom, tipSize.height > 0 ? tipSize.height + 5 : 5)
                }
            }
            .opacity(currentPhase == .idle ? 0 : 1)
        }
        .frame(height: animatedIndicatorHeight) // Height is animated
//        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: animatedIndicatorHeight)
        .animation(.easeInOut(duration: 0.2), value: currentIndicatorColor)
        .animation(.linear(duration: 0.07), value: waveformData) // For main waveform bars
        .onAppear {
            animatedIndicatorHeight = baseIndicatorHeight
            // If starting directly in ASR mode (e.g., view re-render), ensure correct height
            if showASRTextView {
                 // Generate once, or periodically if more "liveliness" is needed for the icon
                displayCornerWaveformIconData = staticWaveformIconData(count: numberOfSamplesForCornerIndicator)

                // If ASR view is shown on appear, and text already exists, calculate height
                // This handles cases where the view might be reconstructed while in an ASR phase
                if !inputViewModel.transcribedText.isEmpty {
                    let targetHeight = calculateASRTextHeight(inputViewModel.transcribedText)
                    if targetHeight != animatedIndicatorHeight {
                        animatedIndicatorHeight = targetHeight
                        hasInitiatedASRHeightAnimation = true
                    }
                }
            }
        }
        .onReceive(cornerWaveformTimer) { _ in // Subtle animation for the corner icon
            if showASRTextView && (currentPhase == .draggingToConvertToText || currentPhase == .processingASR) {
                // Slightly randomize to give a hint of activity without being distracting
                 displayCornerWaveformIconData = staticWaveformIconData(count: numberOfSamplesForCornerIndicator).map { $0 * CGFloat.random(in: 0.9...1.1) }
            }
        }
        .onChange(of: currentPhase) { _, newPhase in
            let oldPhase = inputViewModel.weChatRecordingPhase // Get the phase before this onChange might set it
            hasInitiatedASRHeightAnimation = false // Reset for any phase change

            if newPhase == .draggingToConvertToText || newPhase == .processingASR {
                // Transitioning TO ASR view
                animatedIndicatorHeight = baseIndicatorHeight // Crucial: Keep height same initially
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { // Tiny delay
                    // Check if still in the target ASR phase
                    if self.inputViewModel.weChatRecordingPhase == newPhase {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            self.animatedIndicatorHeight = self.calculateASRTextHeight(self.inputViewModel.transcribedText)
                        }
                        self.hasInitiatedASRHeightAnimation = true
                    }
                }
            } else { // Transitioning FROM ASR or between non-ASR views
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    animatedIndicatorHeight = baseIndicatorHeight
                }
            }
        }
        .onChange(of: inputViewModel.transcribedText) { _, newText in
            if showASRTextView {
                if hasInitiatedASRHeightAnimation {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        animatedIndicatorHeight = calculateASRTextHeight(newText)
                    }
                } else if (currentPhase == .draggingToConvertToText || currentPhase == .processingASR) {
                    // Text arrived, but initial height animation sequence might not have fully run
                    // Ensure we set the height correctly if this is the first text update in ASR mode.
                     DispatchQueue.main.async { // Ensure this is after potential phase change effects
                         withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            animatedIndicatorHeight = calculateASRTextHeight(newText)
                        }
                        hasInitiatedASRHeightAnimation = true
                     }
                }
            }
        }
    }

    @ViewBuilder
    private var waveformView: some View {
        HStack(spacing: barSpacing) {
            // Dynamically limit bars based on available width in the indicator
            // The width of the indicator is controlled by WeChatRecordingOverlayView
            // Here, we just fit as many as possible.
            let maxPossibleBars = Int( ( (inputViewModel.weChatRecordingPhase == .draggingToCancel ?
                                            (UIScreen.main.bounds.width * 0.18) // approx cancelIndicatorWidth
                                            : (UIScreen.main.bounds.width * 0.4) // approx defaultIndicatorWidth
                                          ) - (currentPhase == .draggingToCancel ? 20 : 40) // horizontal paddings
                                        ) / (barWidth + barSpacing) )

            let barsToDisplay = waveformData.prefix(max(1, maxPossibleBars))

            ForEach(Array(barsToDisplay.enumerated()), id: \.offset) { index, sample in
                Capsule()
                    .fill(defaultWaveBarColor)
                    .frame(width: barWidth, height: maxBarHeight * sample)
            }
        }
    }

    @ViewBuilder
    private var asrTextView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { scrollViewProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    Text(inputViewModel.transcribedText.isEmpty && inputViewModel.asrErrorMessage == nil ? (currentPhase == .processingASR ? "Processing..." : "Speak now...") : inputViewModel.transcribedText)
                        .foregroundColor(Color.black.opacity(0.85))
                        .font(.system(size: 17, weight: .medium))
                        .padding(.vertical, 2) // Minimal vertical padding for text itself
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("asrTextContentInsideIndicator")
                }
                // ScrollView will be constrained by the parent ZStack's animatedIndicatorHeight
                .onChange(of: inputViewModel.transcribedText) { _,_  in
                    if showASRTextView {
                        withAnimation { scrollViewProxy.scrollTo("asrTextContentInsideIndicator", anchor: .bottom) }
                    }
                }
            }
            // Corner waveform ICON (IMG_0111.jpg style)
            if currentPhase == .draggingToConvertToText || currentPhase == .processingASR {
                HStack(spacing: cornerWaveformIconBarSpacing) {
                    ForEach(0..<displayCornerWaveformIconData.count, id: \.self) { index in
                        Capsule()
                            .fill(Color.black.opacity(0.5)) // Darker, less prominent
                            .frame(width: cornerWaveformIconBarWidth, height: cornerWaveformIconMaxBarHeight * displayCornerWaveformIconData[index])
                    }
                }
                .padding(.trailing, 12) // Positioned as per IMG_0111.jpg
                .padding(.bottom, 8)
            }
        }
    }

    private func calculateASRTextHeight(_ text: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 17, weight: .medium)
        let textToMeasure = text.isEmpty ? (currentPhase == .processingASR ? "Processing..." : "M") : text // Use "M" for min height calculation of placeholder

        // Use a more reliable width based on the expected width of the ASR bubble
        // This width is set in WeChatRecordingOverlayView for .draggingToConvertToText
        let asrBubbleContentWidth = (inputViewModel.convertToTextRectGlobal.minX - inputViewModel.cancelRectGlobal.maxX) * 0.85 - 32 // Subtract ASR text view's own padding

        let constrainedWidth = max(50, asrBubbleContentWidth)

        let textView = UITextView()
        textView.font = font
        textView.text = textToMeasure
        // Calculate size based on the available width for text
        let size = textView.sizeThatFits(CGSize(width: constrainedWidth, height: CGFloat.greatestFiniteMagnitude))

        let calculatedHeight = size.height + 20 // Add internal vertical padding of asrTextView (10*2)
        return max(minASRTextHeight, min(calculatedHeight, maxASRTextHeight))
    }
}
