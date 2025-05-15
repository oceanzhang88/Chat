import SwiftUI

struct BubbleWithTipShape: Shape {
    let cornerRadius: CGFloat
    let tipSize: CGSize // width is base, height is how far it extends
    let tipPosition: TipPosition
    let tipOffsetPercentage: CGFloat // 0.0 (leading/top) to 1.0 (trailing/bottom) from the edge's start. 0.5 is center.

    enum TipPosition {
        case trailing_edge_vertical_center
        case bottom_edge_horizontal_offset
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Determine the main body rectangle of the bubble, excluding the tip area.
        var bodyRect = rect
        var tipApex = CGPoint.zero
        var tipBaseStart = CGPoint.zero
        var tipBaseEnd = CGPoint.zero

        switch tipPosition {
        case .trailing_edge_vertical_center:
            // Tip is on the right edge, so bodyRect's width is reduced.
            bodyRect.size.width -= tipSize.width
            // Tip points to the right.
            let tipCenterY = bodyRect.midY
            tipBaseStart = CGPoint(x: bodyRect.maxX, y: tipCenterY - tipSize.height / 2)
            tipApex = CGPoint(x: rect.maxX, y: tipCenterY) // rect.maxX includes tip width
            tipBaseEnd = CGPoint(x: bodyRect.maxX, y: tipCenterY + tipSize.height / 2)

        case .bottom_edge_horizontal_offset:
            // Tip is on the bottom edge, so bodyRect's height is reduced.
            bodyRect.size.height -= tipSize.height
            // Tip points downwards.
            let tipBaseCenterX = bodyRect.minX + (bodyRect.width * tipOffsetPercentage)
            tipBaseStart = CGPoint(x: tipBaseCenterX - tipSize.width / 2, y: bodyRect.maxY)
            tipApex = CGPoint(x: tipBaseCenterX, y: rect.maxY) // rect.maxY includes tip height
            tipBaseEnd = CGPoint(x: tipBaseCenterX + tipSize.width / 2, y: bodyRect.maxY)
        }

        // Start drawing the rounded rectangle for the main body
        path.move(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))

        // Top edge
        path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY))
        // Top-right arc
        path.addArc(center: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY + cornerRadius),
                    radius: cornerRadius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)

        // Right edge OR start of right-side tip
        if tipPosition == .trailing_edge_vertical_center {
            path.addLine(to: tipBaseStart)
            path.addLine(to: tipApex)
            path.addLine(to: tipBaseEnd)
        }
        path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - cornerRadius))
        // Bottom-right arc
        path.addArc(center: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)

        // Bottom edge OR start of bottom-side tip
        if tipPosition == .bottom_edge_horizontal_offset {
            path.addLine(to: tipBaseEnd) // Line from corner to the right base of the tip
            path.addLine(to: tipApex)     // Line to the tip's apex
            path.addLine(to: tipBaseStart) // Line to the left base of the tip
        }
        path.addLine(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY))
        // Bottom-left arc
        path.addArc(center: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY - cornerRadius),
                    radius: cornerRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)

        // Left edge
        path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
        // Top-left arc
        path.addArc(center: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY + cornerRadius),
                    radius: cornerRadius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        path.closeSubpath()
        return path
    }
}
