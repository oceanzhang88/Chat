import SwiftUI

// MARK: - Main Overlay View

struct WeChatRecordingOverlayView: View {
    @State private var isPresented: Bool = true
    @State private var waveformData: [CGFloat] = []
    @State private var animationStep: Int = 0 // Controls the phase of the wave animation

    let timer = Timer.publish(every: 0.07, on: .main, in: .common).autoconnect()
    private let numberOfSamples: Int = 35

    var body: some View {
        ZStack {
            // Dimmed gradient background
            DimmedGradientBackgroundView()
                .onTapGesture {
                    // Optional: dismiss on tap
                    // isPresented = false
                }

            VStack {
                // Add an extra Spacer to push the indicator further down
                Spacer()
                Spacer() // This creates more space above the indicator

                RecordingIndicatorView(waveformData: waveformData)
                    .padding(.horizontal, 60) // Keeps indicator from screen edges


                // Flexible spacer between indicator and bottom controls
                Spacer()

                BottomControlsView(
                    onCancel: {
                        print("Cancel tapped")
                        isPresented = false
                    },
                    onConvertToText: {
                        print("Convert to Text tapped")
                        // Handle convert to text action
                    }
                )
            }
        }
        .ignoresSafeArea()
        .opacity(isPresented ? 1 : 0)
        .animation(.easeInOut, value: isPresented)
        .onAppear {
            // Initialize waveform data with the new animation logic
            self.waveformData = generateAnimatedWaveformData(count: numberOfSamples, step: animationStep)
        }
        .onReceive(timer) { _ in
            if isPresented {
                animationStep += 1 // Increment animation step
                self.waveformData = generateAnimatedWaveformData(count: numberOfSamples, step: animationStep)
            }
        }
    }

    // Generates waveform data for a "waving out" animation from middle to sides.
    private func generateAnimatedWaveformData(count: Int, step: Int) -> [CGFloat] {
        var data: [CGFloat] = Array(repeating: 0.05, count: count) // Initialize with a base small height
        let middleIndex = count / 2
        
        // wavePosition determines how far the "peak" of the wave has traveled from the center
        // It cycles from 0 (center) up to middleIndex (edge), then can reset or reflect.
        // For a continuous outward pulse that repeats, we use modulo.
        let wavePosition = CGFloat(step % (middleIndex + 1))

        // Spread factor for the Gaussian pulse (adjust for wider/narrower pulse)
        // A smaller divisor means a wider pulse.
        let spreadDivisor = CGFloat(count) * 0.09 // Example: 35 * 0.09 = 3.15. Adjust as needed.

        for i in 0..<count {
            // Distance of the current bar from the absolute center of the waveform
            let distanceFromAbsoluteCenter = CGFloat(abs(i - middleIndex))
            
            // Calculate the Gaussian factor based on how close this bar's distance from center
            // is to the current wavePosition (which represents the pulse's distance from center).
            // The peak of the Gaussian is where distanceFromAbsoluteCenter is "close" to wavePosition.
            let gaussianFactor = exp(-pow(distanceFromAbsoluteCenter - wavePosition, 2) / (2 * pow(spreadDivisor, 2))) // More standard Gaussian form
            
            // Introduce some randomness to the height of the pulse's peak for a more organic feel
            let randomPeakHeight = CGFloat.random(in: 0.7...1.0)
            
            let barHeight = gaussianFactor * randomPeakHeight
            
            // Ensure data[i] gets the new height if it's greater than the base, clamp values
            data[i] = max(data[i], min(max(barHeight, 0.05), 1.0))
        }
        return data
    }
}

// MARK: - Sub-components

// View for the dimmed gradient background
struct DimmedGradientBackgroundView: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 80/255, green: 80/255, blue: 80/255).opacity(0.7),
                Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.97)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .edgesIgnoringSafeArea(.all)
    }
}

// Custom Shape for the Recording Indicator Background with a Tip
struct IndicatorBackgroundShape: Shape {
    let cornerRadius: CGFloat
    let tipHeight: CGFloat
    let tipWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mainRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tipHeight)

        path.move(to: CGPoint(x: mainRect.minX + cornerRadius, y: mainRect.minY))
        path.addLine(to: CGPoint(x: mainRect.maxX - cornerRadius, y: mainRect.minY))
        path.addArc(center: CGPoint(x: mainRect.maxX - cornerRadius, y: mainRect.minY + cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        path.addLine(to: CGPoint(x: mainRect.maxX, y: mainRect.maxY - cornerRadius))
        path.addArc(center: CGPoint(x: mainRect.maxX - cornerRadius, y: mainRect.maxY - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: mainRect.midX + tipWidth / 2, y: mainRect.maxY))
        path.addLine(to: CGPoint(x: mainRect.midX, y: mainRect.maxY + tipHeight))
        path.addLine(to: CGPoint(x: mainRect.midX - tipWidth / 2, y: mainRect.maxY))
        path.addLine(to: CGPoint(x: mainRect.minX + cornerRadius, y: mainRect.maxY))
        path.addArc(center: CGPoint(x: mainRect.minX + cornerRadius, y: mainRect.maxY - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: mainRect.minX, y: mainRect.minY + cornerRadius))
        path.addArc(center: CGPoint(x: mainRect.minX + cornerRadius, y: mainRect.minY + cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        path.closeSubpath()
        return path
    }
}


// View for the central recording indicator
struct RecordingIndicatorView: View {
    let waveformData: [CGFloat]
    private let barWidth: CGFloat = 2.0
    private let barSpacing: CGFloat = 1.5
    private let maxBarHeight: CGFloat = 45
    private let cornerRadius: CGFloat = 22
    private let tipHeight: CGFloat = 10
    private let tipWidth: CGFloat = 20
    private let indicatorColor = Color(red: 100/255, green: 220/255, blue: 100/255)


    var body: some View {
        ZStack {
            IndicatorBackgroundShape(cornerRadius: cornerRadius, tipHeight: tipHeight, tipWidth: tipWidth)
                .fill(indicatorColor)
                .shadow(color: indicatorColor.opacity(0.4), radius: 8, x: 0, y: 4)

            HStack(spacing: barSpacing) {
                ForEach(0..<waveformData.count, id: \.self) { index in
                    Capsule()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: barWidth, height: maxBarHeight * waveformData[index])
                }
            }
            .padding(.bottom, tipHeight * 0.8)
            .padding(.horizontal, 20)
        }
        .frame(width: UIScreen.main.bounds.width * 0.50,
               height: 80 + tipHeight)
        .animation(.linear(duration: 0.07), value: waveformData)
    }
}

// View for the bottom controls panel
struct BottomControlsView: View {
    var onCancel: () -> Void
    var onConvertToText: () -> Void

    private let controlsContentHeight: CGFloat = 130
    private let arcAreaHeight: CGFloat = 120
    private let arcSagitta: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()

                HStack {
                    OverlayButton(
                        iconSystemName: "xmark",
                        label: "Cancel",
                        action: onCancel
                    )
                    Spacer()
                    OverlayButton(
                        textIcon: "En",
                        label: "Convert to Text",
                        action: onConvertToText
                    )
                }
                .padding(.horizontal, 50)
                .padding(.bottom, 2)

                Text("Release to send")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.9))
                    .padding(.bottom, 10)
            }
            .frame(height: controlsContentHeight)

            ZStack {
                ArcBackgroundShape(sagitta: arcSagitta)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.7), location: 0),
                                .init(color: Color.white.opacity(0.6), location: 0.5),
                                .init(color: Color.white.opacity(0.5), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.white.opacity(0.15), radius: 10, y: -3)

                Image(systemName: "radiowaves.right")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(Color(white: 0.4).opacity(0.7))
                    .offset(y: arcSagitta - (arcAreaHeight / 3))
            }
            .frame(height: arcAreaHeight)
        }
        .padding(.bottom, (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom ?? 0 > 0 ? 10 : 0)
    }
}

// Custom Shape for the Arc Background of the bottom controls
struct ArcBackgroundShape: Shape {
    var sagitta: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arcPeakY = rect.minY
        let arcEdgeY = rect.minY + sagitta
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: arcEdgeY))
        let controlPointY = 2 * arcPeakY - arcEdgeY
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: arcEdgeY),
            control: CGPoint(x: rect.midX, y: controlPointY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// Reusable Button Component for the overlay
struct OverlayButton: View {
    var iconSystemName: String? = nil
    var textIcon: String? = nil
    let label: String
    let action: () -> Void

    private let buttonCircleSize: CGFloat = 65
    private let iconFontSize: CGFloat = 28
    private let textIconFontSize: CGFloat = 24
    private let labelFontSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: labelFontSize))
                    .foregroundColor(Color.gray.opacity(0.8))

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: buttonCircleSize, height: buttonCircleSize)

                    if let iconName = iconSystemName {
                        Image(systemName: iconName)
                            .font(.system(size: iconFontSize, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    } else if let text = textIcon {
                        Text(text)
                            .font(.system(size: textIconFontSize, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct WeChatRecordingOverlayView_Previews: PreviewProvider {
    static var previews: some View {
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
            WeChatRecordingOverlayView()
        }
        .preferredColorScheme(.dark)
    }
}

