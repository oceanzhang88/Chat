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
    var isDraggingInCancelZone: Bool // New state variable

    @Environment(\.chatTheme) private var theme // Access theme for colors

    private let barWidth: CGFloat = 2.0
    private let barSpacing: CGFloat = 1.5
    private let maxBarHeight: CGFloat = 45
    private let cornerRadius: CGFloat = 22
    private let tipHeight: CGFloat = 10
    private let tipWidth: CGFloat = 20

    // ADJUSTED: Dynamic indicator color and shadow based on isDraggingInCancelZone
    private var currentIndicatorColor: Color {
        // If dragging in cancel zone, use the error/red color from the theme
        // Otherwise, use the greenish color.
        isDraggingInCancelZone ? theme.colors.statusError : Color(red: 100/255, green: 220/255, blue: 100/255)
    }
    private var currentIndicatorShadowColor: Color {
        // Shadow color also adapts
        isDraggingInCancelZone ? theme.colors.statusError.opacity(0.7) : currentIndicatorColor.opacity(0.4)
    }
    // UPDATED: Waveform bar color
    private var currentWaveformBarColor: Color {
        // Waveform should be visible in both states.
        // White for red background (cancel), dark for normal red background.
        isDraggingInCancelZone ? Color.white.opacity(0.7) : Color.white.opacity(0.85)
    }

    var body: some View {
        ZStack {
            IndicatorBackgroundShape(cornerRadius: cornerRadius, tipHeight: tipHeight, tipWidth: tipWidth)
                .fill(currentIndicatorColor) // Use dynamic color
                .shadow(color: currentIndicatorShadowColor, radius: 8, x: 0, y: 4) // Use dynamic shadow

            HStack(spacing: barSpacing) {
                let waveCount = isDraggingInCancelZone ? waveformData.count / 2 : waveformData.count
                ForEach(0..<waveCount, id: \.self) { index in
                    Capsule()
                        .fill(currentWaveformBarColor) // Uses dynamic waveform bar color
                        .frame(width: barWidth, height: maxBarHeight * waveformData[index])
                }
            }
            .padding(.bottom, tipHeight * 0.8) // Adjust to ensure waveform is visually centered in the main part
            .padding(.horizontal, 20) // Horizontal padding for waveform within the background
        }
//        .frame(width: UIScreen.main.bounds.width * 0.1, height: 80 + tipHeight)
        .animation(.easeInOut(duration: 0.2), value: isDraggingInCancelZone) // Animate color change
        .animation(.linear(duration: 0.07), value: waveformData) // Keep waveform animation snappy
    }
}

// IndicatorBackgroundShape remains the same
// ... (IndicatorBackgroundShape code as you have it) ...
struct IndicatorBackgroundShape: Shape {
    let cornerRadius: CGFloat
    let tipHeight: CGFloat
    let tipWidth: CGFloat

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
