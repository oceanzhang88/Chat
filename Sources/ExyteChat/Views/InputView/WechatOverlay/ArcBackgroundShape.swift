//
//  ArcBackgroundShape.swift
//  Chat
//
//  Created by Yangming Zhang on 5/14/25.
//


// Chat/Sources/ExyteChat/Views/InputView/Overlay/ArcBackgroundShape.swift
import SwiftUI

struct ArcBackgroundShape: Shape {
    var sagitta: CGFloat // The height of the arc from its chord
    
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