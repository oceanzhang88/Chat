//
//  WechatRecordingIndicator.swift
//  Chat
//
//  Created by Yangming Zhang on 5/13/25.
//


// Chat/Sources/ExyteChat/Views/Recording/WechatRecordingIndicator.swift
import SwiftUI

struct WechatRecordingIndicator: View {
    let waveformData: [CGFloat]
    var currentPhase: WeChatRecordingPhase // Use the new phase
    
    @Environment(\.chatTheme) private var theme

    private let barWidth: CGFloat = 2.0
    private let barSpacing: CGFloat = 1.5
    private let maxBarHeight: CGFloat = 45
    private let cornerRadius: CGFloat = 22
    private let tipHeight: CGFloat = 10
    private let tipWidth: CGFloat = 20
    private let defaultWaveBarColor: Color = Color(red: 80/255, green: 80/255, blue: 80/255) // Default dark gray for waves

    private var currentIndicatorColor: Color {
        switch currentPhase {
        case .draggingToCancel:
            return theme.colors.statusError // Red
        case .draggingToConvertToText:
            return theme.colors.messageMyBG.opacity(0.9) // Your app's accent color, slightly transparent
        default: // .recording, .idle (though not visible in .idle)
            return Color(red: 100/255, green: 220/255, blue: 100/255) // Greenish
        }
    }
    
    private var tipAlignment: IndicatorBackgroundShape.TipAlignment {
        switch currentPhase {
            case .draggingToCancel:
                return .left // Or adjust if your cancel button is elsewhere
            case .draggingToConvertToText:
                return .right
            default:
                return .center
        }
    }

    private var currentIndicatorShadowColor: Color {
        currentIndicatorColor.opacity(0.4)
    }

    private var currentWaveformBarColor: Color {
        switch currentPhase {
        case .draggingToCancel, .draggingToConvertToText:
            return Color.white.opacity(0.75) // White waves on special backgrounds
        default:
            return defaultWaveBarColor.opacity(0.85) // Darker waves on greenish background
        }
    }

    // Determine number of bars based on phase for shrinking effect
    private var numberOfWaveformBars: Int {
        switch currentPhase {
        case .draggingToCancel, .draggingToConvertToText:
            return waveformData.count / 2 // Or a fixed small number like 10
        default:
            return waveformData.count
        }
    }

    var body: some View {
        ZStack {
            
            IndicatorBackgroundShape(cornerRadius: cornerRadius, tipHeight: tipHeight, tipWidth: tipWidth, tipAlignment: tipAlignment)
                .fill(currentIndicatorColor)
                .shadow(color: currentIndicatorShadowColor, radius: 8, x: 0, y: 4)

            HStack(spacing: barSpacing) {
                // Ensure we don't try to access out of bounds if waveformData is short
                let barsToShow = min(numberOfWaveformBars, waveformData.count)
                ForEach(0..<barsToShow, id: \.self) { index in
                    Capsule()
                        .fill(currentWaveformBarColor)
                        .frame(width: barWidth, height: maxBarHeight * waveformData[index])
                }
            }
            .padding(.bottom, tipHeight * 0.8)
            .padding(.horizontal, currentPhase == .draggingToCancel || currentPhase == .draggingToConvertToText ? 10 : 20) // Less padding when shrunk
            .animation(.easeInOut(duration: 0.1), value: currentWaveformBarColor) // Quick color change for bars
        }
        // Animations for color and shadow are handled by the parent view's animation on currentIndicatorWidth/Offset
        .animation(.linear(duration: 0.07), value: waveformData) // Keep waveform data updates snappy
    }
}

struct IndicatorBackgroundShape: Shape { /* ... as before ... */
    var cornerRadius: CGFloat
    var tipHeight: CGFloat
    var tipWidth: CGFloat
    var tipAlignment: TipAlignment

    enum TipAlignment {
        case center, left, right
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Adjust mainRect to account for the tipHeight, assuming tip is at the bottom
        let mainRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tipHeight)

        // Top-left corner
        path.move(to: CGPoint(x: mainRect.minX + cornerRadius, y: mainRect.minY))
        // Top edge
        path.addLine(to: CGPoint(x: mainRect.maxX - cornerRadius, y: mainRect.minY))
        // Top-right corner (arc)
        path.addArc(center: CGPoint(x: mainRect.maxX - cornerRadius, y: mainRect.minY + cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        // Right edge
        path.addLine(to: CGPoint(x: mainRect.maxX, y: mainRect.maxY - cornerRadius))
        // Bottom-right corner (arc)
        path.addArc(center: CGPoint(x: mainRect.maxX - cornerRadius, y: mainRect.maxY - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        
        // --- Modified Tip Drawing Logic ---
        let tipBaseY = mainRect.maxY
        let tipApexY = mainRect.maxY + tipHeight
        var tipCenterX: CGFloat

        switch tipAlignment {
        case .center:
            tipCenterX = mainRect.midX
        case .left:
            // Position tip towards the left button (approx 1/4 from left edge)
            tipCenterX = mainRect.minX + (mainRect.width / 4)
        case .right:
            // Position tip towards the right button (approx 3/4 from left edge, or 1/4 from right edge)
            tipCenterX = mainRect.maxX - (mainRect.width / 4)
        }
        
        // Bottom edge with tip
        path.addLine(to: CGPoint(x: mainRect.midX + tipWidth / 2, y: mainRect.maxY)) // Line to right side of tip base
        path.addLine(to: CGPoint(x: mainRect.midX, y: mainRect.maxY + tipHeight)) // Line to tip point
        path.addLine(to: CGPoint(x: mainRect.midX - tipWidth / 2, y: mainRect.maxY)) // Line to left side of tip base
        
        // Continue bottom edge
        path.addLine(to: CGPoint(x: mainRect.minX + cornerRadius, y: mainRect.maxY))
        // Bottom-left corner (arc)
        path.addArc(center: CGPoint(x: mainRect.minX + cornerRadius, y: mainRect.maxY - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        // Left edge
        path.addLine(to: CGPoint(x: mainRect.minX, y: mainRect.minY + cornerRadius))
        // Top-left corner (arc)
        path.addArc(center: CGPoint(x: mainRect.minX + cornerRadius, y: mainRect.minY + cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        path.closeSubpath()
        return path
    }
}
