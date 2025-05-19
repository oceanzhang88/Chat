//
//  ASRBubbleMetrics.swift
//  Chat
//
//  Created by Yangming Zhang on 5/18/25.
//


// Chat/Sources/ExyteChat/Views/InputView/WechatOverlay/ASRBubbleMetrics.swift
import SwiftUI

struct ASRBubbleMetrics {
    // Overall Bubble Constraints
    static let minOverallHeight: CGFloat = 100.0
    static let maxOverallHeight: CGFloat = 180.0
    
    // Internal Content Area Common Paddings
    static let horizontalPadding: CGFloat = 16.0
    static let verticalPadding: CGFloat = 12.0
    static var totalInternalVerticalPadding: CGFloat { verticalPadding * 2 }
    
    // Tip
    static let tipSize: CGSize = CGSize(width: 20, height: 10)
    static var tipHeightComponent: CGFloat { tipSize.height > 0 ? tipSize.height : 0 }
    
    // --- WechatRecordingIndicator specific metrics ---
    static let indicatorCornerIconAreaHeight: CGFloat = 30.0
    static let indicatorTextToIconSpacing: CGFloat = 4.0
    static let indicatorTopChromePadding: CGFloat = 8.0
    static let indicatorBottomChromePadding: CGFloat = 8.0
    // Calculated:
    static var indicatorTotalChromeHeight: CGFloat { indicatorTopChromePadding + tipHeightComponent + indicatorBottomChromePadding }
    
    
    // --- ASRResultView specific metrics ---
    static let resultViewMinTextEditorHeight: CGFloat = 30.0 // Minimum height for the text input/display field
    static let resultViewEllipsisButtonApproxHeight: CGFloat = 35.0
    static let resultViewInternalVStackSpacing: CGFloat = 5.0
}
