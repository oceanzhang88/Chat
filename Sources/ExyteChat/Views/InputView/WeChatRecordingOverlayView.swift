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
    @ObservedObject var inputViewModel: InputViewModel // Added
    @Environment(\.chatTheme) private var theme // For theme colors

    @State private var isPresented: Bool = true // Assuming this controls visibility
    @State private var displayWaveformData: [CGFloat] = [] // This will be passed to RecordingIndicatorView
    @State private var animationStep: Int = 0
    
    let inputBarHeight: CGFloat // <-- NEW PROPERTY
    var localization: ChatLocalization
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let numberOfSamplesForIndicator: Int = 35 // For the visual indicator
    private let lowVoiceThreshold: CGFloat = 0.1 // If max of recent samples is below this, voice is "low"
    private let samplesToAnalyzeForLowVoice = 15 // Number of recent samples to check for low voice
    
    private let indicatorHeight: CGFloat = 70 // Reduced base height slightly
    private let indicatorTipHeight: CGFloat = 8 // Reduced tip height
    
    // ADJUSTED: Indicator width constants
    private var defaultIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.50 }
    // Make the cancel indicator width smaller as per WeChat's UI
    private var cancelIndicatorWidth: CGFloat { UIScreen.main.bounds.width * 0.1 } // Smaller width when cancelling

    // Adjusted XOffset for better left positioning, similar to WeChat
    private var cancelIndicatorXOffset: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        // (screenWidth / 2) is center.
        // We want it to be roughly centered over the cancel button's area.
        // The cancel button is pushed left by 55 padding + half its own width.
        // Let's try to align the center of the indicator with the center of where the cancel button is.
        let cancelBtnApproxCenterX = (UIScreen.main.bounds.width * 0.25) / 2 + 40 // Approximation
        return -(screenWidth / 2) + cancelBtnApproxCenterX
    }

    private var currentIndicatorWidth: CGFloat {
        inputViewModel.isDraggingInCancelZoneOverlay ? cancelIndicatorWidth : defaultIndicatorWidth
    }

    private var currentXOffset: CGFloat {
        inputViewModel.isDraggingInCancelZoneOverlay ? cancelIndicatorXOffset : 0
    }

    // Helper text: Hide when in cancel zone
    private var helperText: String {
        // UPDATED: Text is gone when in cancel zone
        if inputViewModel.isDraggingInCancelZoneOverlay {
            return "" // No text when cancel is active
        }
        // This was localization.releaseToSendText, matching WeChat, it would be "Release to send" or similar
        // If you want "Slide up to cancel" when NOT in cancel zone but still recording, add that logic here.
        // For now, let's keep it simple based on your feedback.
        return inputViewModel.state == .isRecordingHold || inputViewModel.state == .isRecordingTap ? localization.releaseToSendText : ""
    }


    var body: some View {
        ZStack {
            // Dimmed gradient background
            DimmedGradientBackgroundView()

            VStack {
                // Add an extra Spacer to push the indicator further down
                Spacer()
                Spacer() // This creates more space above the indicator

                // Indicator view that will slide and shrink
                WechatRecordingIndicator(
                    waveformData: displayWaveformData,
                    isDraggingInCancelZone: inputViewModel.isDraggingInCancelZoneOverlay
                )
                .frame(width: currentIndicatorWidth, height: indicatorHeight + indicatorTipHeight) // Use combined height
                .offset(x: currentXOffset)
//                .animation(.interpolatingSpring(stiffness: 200, damping: 22), value: inputViewModel.isDraggingInCancelZoneOverlay)
//                .animation(.interpolatingSpring(stiffness: 200, damping: 22), value: currentIndicatorWidth)


                // Flexible spacer between indicator and bottom controls
                Spacer()

                BottomControlsView(
                    isDraggingInCancelZone: inputViewModel.isDraggingInCancelZoneOverlay, // <-- Pass state
                    helperText: helperText, //Pass the dynamic helper text,
                    localization: localization,
                    onCancel: {
                        // Likely, this should trigger an action in inputViewModel to stop/delete recording
                        inputViewModel.inputViewAction()(.deleteRecord)
                        isPresented = false
                    },
                    onConvertToText: {
                        // This would be a new feature, potentially also an InputViewAction
                        print("Convert to Text tapped - to be implemented")
                    },
                    inputBarHeight: inputBarHeight // <-- PASS IT DOWN
                )
            }
        }
        .ignoresSafeArea(.all)
        .opacity(isPresented ? 1 : 0)
        .onAppear {
                    self.isPresented = inputViewModel.isRecordingAudioForOverlay
                    updateWaveformToDisplay()
        }
        .onReceive(timer) { _ in
            if isPresented {
                updateWaveformToDisplay()
            }
        }
        .onChange(of: inputViewModel.isRecordingAudioForOverlay) { _, newValue in
            // Synchronize isPresented state with the viewModel's overlay state
            self.isPresented = newValue
            if newValue { // If overlay is being shown, ensure waveform is updated
                updateWaveformToDisplay()
            }
        }
        .onChange(of: inputViewModel.attachments.recording?.waveformSamples) { _, _ in
            // React to new samples coming from the InputViewModel (which gets them from Recorder)
            if isPresented && (inputViewModel.state == .isRecordingHold || inputViewModel.state == .isRecordingTap) {
                // Only update waveform if not dragging to cancel
                if !inputViewModel.isDraggingInCancelZoneOverlay {
                    updateWaveformToDisplay()
                }
//                 updateWaveformToDisplay()
            }
        }
        // ADDED: When dragging to cancel starts, capture the current waveform.
        // When it ends (and not cancelled), resume waveform updates.
        .onChange(of: inputViewModel.isDraggingInCancelZoneOverlay) { _, inCancelZone in
            if !inCancelZone {
                // If we are no longer in the cancel zone, resume live waveform updates
                updateWaveformToDisplay(forceUpdate: true)
            }
            // When inCancelZone becomes true, the timer and sample updates
            // will naturally stop updating displayWaveformData due to the condition
            // in onReceive(timer) and onChange(of: ...waveformSamples).
            // The waveform will freeze at its last state.
        }
    }

    private func updateWaveformToDisplay(forceUpdate: Bool = false) {
        // If dragging to cancel, and not forcing an update, do nothing.
        // The waveform should remain static (frozen at its last state before entering cancel zone).
        if inputViewModel.isDraggingInCancelZoneOverlay && !forceUpdate {
            return
        }
        
        if inputViewModel.state == .isRecordingHold || inputViewModel.state == .isRecordingTap {
            let liveSamples = inputViewModel.attachments.recording?.waveformSamples ?? []
            
            if shouldUseRealSamples(liveSamples) {
                // Use real samples, take the most recent ones
                let recentLiveSamples = Array(liveSamples.suffix(numberOfSamplesForIndicator))
                self.displayWaveformData = padOrTruncateSamples(samples: recentLiveSamples, targetCount: numberOfSamplesForIndicator, defaultValue: 0.02)
            } else {
                // Voice is low or no samples yet, use default pulsing animation
                animationStep += 1
                self.displayWaveformData = generateDefaultAnimatedWaveformData(count: numberOfSamplesForIndicator, step: animationStep)
            }
        } else {
            // Not actively recording voice sound for the overlay, keep default animation or clear
            animationStep += 1
            self.displayWaveformData = generateDefaultAnimatedWaveformData(count: numberOfSamplesForIndicator, step: animationStep)
        }
    }
    
    private func shouldUseRealSamples(_ samples: [CGFloat]) -> Bool {
        guard !samples.isEmpty else { return false }
        // Consider the N most recent samples
        let
        recentSamples = samples.suffix(samplesToAnalyzeForLowVoice)
        // If the loudest sound in the recent samples is still below threshold, consider voice low
        if let maxSample = recentSamples.max(), maxSample < lowVoiceThreshold {
            return false // Voice is consistently low
        }
        return true // Voice is loud enough or has some peaks
    }
    
    private func padOrTruncateSamples(samples: [CGFloat], targetCount: Int, defaultValue: CGFloat) -> [CGFloat] {
        if samples.count == targetCount {
            return samples
        } else if samples.count > targetCount {
            return Array(samples.suffix(targetCount))
        } else {
            // Pad at the beginning with default value to make the waveform appear to fill from the right
            let paddingCount = targetCount - samples.count
            return Array(repeating: defaultValue, count: paddingCount) + samples
        }
    }
    
    // Renamed original function to clarify it's the default animation
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

// MARK: - Sub-components (DimmedGradientBackgroundView, BottomControlsView, ArcBackgroundShape, OverlayButton)
// These remain unchanged in this file as they are specific to the overlay's layout.

// View for the dimmed gradient background
struct DimmedGradientBackgroundView: View {
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

// View for the bottom controls panel
struct BottomControlsView: View {
    var isDraggingInCancelZone: Bool // Receive this state
    var helperText: String // Receive dynamic helper text
    var localization: ChatLocalization
    
    var onCancel: () -> Void
    var onConvertToText: () -> Void
    let inputBarHeight: CGFloat
    @Environment(\.chatTheme) private var theme


    private let controlsContentHeight: CGFloat = 130
    
    // Let arcAreaHeight be somewhat dynamic or a multiple of inputBarHeight
    private var arcAreaHeight: CGFloat { inputBarHeight * 2 } // Example: 1.5 times the input bar height
    private var arcSagitta: CGFloat { arcAreaHeight * 0.33 } // Sagitta as a portion of this dynamic arcAreaHeight

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()

                HStack {
                    // Cancel Button Wrapper - give it a consistent frame
                    ZStack {
                        OverlayButton( // Cancel Button
                            iconSystemName: "xmark",
                            label: localization.cancelButtonText, // Use localization
                            isHighlighted: isDraggingInCancelZone,
                            action: onCancel
                        )
                    }
                    Spacer()
                    ZStack {
                        OverlayButton( // Convert to Text Button
                            textIcon: localization.convertToTextButton,
                            label: localization.convertToTextButton, // Use localization
                            isHighlighted: false, // This button doesn't change with drag state in the example
                            action: onConvertToText
                        )
                    }
                }
                .padding(.horizontal, 55)
                .padding(.bottom, 2)
                .offset(x: 2.5)

                Text(helperText) // Use the dynamic helper text
                    .font(.system(size: 13))
                    .foregroundColor(isDraggingInCancelZone ? theme.colors.statusError : Color.white.opacity(0.9)) // Change text color
                    .padding(.bottom, 10)
//                    .padding(.trailing, 10) // This might need adjustment based on overall layout
            }
            .frame(height: controlsContentHeight)

            // Arc background (remains mostly the same)
            ZStack {
                ArcBackgroundShape(sagitta: arcSagitta)
                    .fill(
                        isDraggingInCancelZone ?
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color:  Color(red: 80/255, green: 80/255, blue: 80/255), location: 0),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ):
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.8), location: 0),
                                .init(color: Color.white.opacity(0.75), location: 0.5),
                                .init(color: Color.white.opacity(0.7), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 5, y: -2) // Softer shadow

                Image(systemName: "radiowaves.right") // This is the icon at the bottom of the input bar
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(Color(white: 0.4).opacity(0.7))
                    .offset(y: arcSagitta - (arcAreaHeight / 2.5)) // Adjust y-offset based on where the arc peak is
            }
            .frame(height: arcAreaHeight)
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: VoiceOverlayBottomAreaHeightPreferenceKey.self,
                        value: geometry.size.height - 0.75 * controlsContentHeight
                    )
            }
        )
    }
}

// Custom Shape for the Arc Background of the bottom controls
struct ArcBackgroundShape: Shape {
    var sagitta: CGFloat // The height of the arc from its chord

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // The Y coordinate of the arc's peak (highest point)
        let arcPeakY = rect.minY
        // The Y coordinate where the arc meets the straight vertical sides
        let arcEdgeY = rect.minY + sagitta

        // Start from bottom-left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Line up to the start of the arc on the left
        path.addLine(to: CGPoint(x: rect.minX, y: arcEdgeY))

        // Calculate the control point for the quadratic Bézier curve.
        // For a symmetric arc where the peak is at rect.midX, arcPeakY,
        // and edges are at (rect.minX, arcEdgeY) and (rect.maxX, arcEdgeY),
        // the control point's Y is 2*arcPeakY - arcEdgeY.
        let controlPointY = 2 * arcPeakY - arcEdgeY
        
        // Add the quadratic Bézier curve for the arc
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: arcEdgeY),
            control: CGPoint(x: rect.midX, y: controlPointY)
        )

        // Line down to the bottom-right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Close the path to form a filled shape
        path.closeSubpath()
        
        return path
    }
}


// Modify OverlayButton to optionally highlight
struct OverlayButton: View {
    var iconSystemName: String? = nil
    var textIcon: String? = nil
    let label: String
    var isHighlighted: Bool = false // New property for highlighting
    let action: () -> Void
    @Environment(\.chatTheme) private var theme // Access theme

    // Define base sizes
    private let normalCircleSize: CGFloat = 65
    private let highlightedCircleSize: CGFloat = 70 // For cancel button when highlighted

    private let normalIconFontSize: CGFloat = 26
    private let highlightedIconFontSize: CGFloat = 32 // For cancel icon when highlighted

    private let staticTextIconFontSize: CGFloat = 24 // For "En" button
    private let labelFontSize: CGFloat = 13
    
    // ADJUSTED: Define sizes for normal and enlarged states
    // Determine current sizes based on state
    private var currentCircleSize: CGFloat {
        isHighlighted ? highlightedCircleSize : normalCircleSize
    }
    private var currentIconSize: CGFloat {
        isHighlighted ? highlightedIconFontSize : normalIconFontSize
    }
    

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: labelFontSize))
                    .foregroundColor(isHighlighted ? Color.white : Color.gray.opacity(0.8)) // Change label color when highlighted

                ZStack {
                    Circle()
                        // UPDATED: Cancel button style
                        .fill(
                            iconSystemName == "xmark" ?
                                (isHighlighted ? Color.white : Color.gray) // Reddish transparent OR White
                                : Color.white.opacity(0.12) // "To Text" button is always light gray
                        )
                        .frame(width: currentCircleSize, height: currentCircleSize)
                        .scaleEffect(isHighlighted ? (highlightedCircleSize / normalCircleSize) : 1.0)
                        // Optional: Add border for highlighted cancel button
//                        .overlay(
//                            iconSystemName == "xmark" && isHighlighted ?
//                            Circle().stroke(theme.colors.statusError.opacity(0.3), lineWidth: 1.5)
//                            : nil
//                        )


                    if let iconName = iconSystemName {
                        Image(systemName: iconName)
                            .font(.system(size: currentIconSize, weight: .medium))
                            // UPDATED: Cancel icon style
                            .foregroundColor(
                                isHighlighted ? Color.black : Color(UIColor.darkGray) // Red icon OR Dark Gray icon
                            )
                    } else if let text = textIcon { // For "En" button
                        Text(text)
                            .font(.system(size: staticTextIconFontSize, weight: .semibold))
                            .foregroundColor(Color(UIColor.darkGray)) // "En" text is dark gray
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
//        .frame(width: highlightedCircleSize, height: highlightedCircleSize + labelFontSize + 8) // Ensure frame accommodates largest size
//        .animation(.easeInOut, value: isHighlighted) // Animate highlight changes
//        .animation(.easeInOut, value: currentCircleSize) // Animate explicit size changes (if any beyond scale)

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
