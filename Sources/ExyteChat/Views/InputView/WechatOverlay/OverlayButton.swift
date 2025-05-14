//
//  OverlayButton.swift
//  Chat
//
//  Created by Yangming Zhang on 5/14/25.
//


// Chat/Sources/ExyteChat/Views/InputView/Overlay/OverlayButton.swift
import SwiftUI

struct OverlayButton: View {
    var iconSystemName: String? = nil
    var textIcon: String? = nil
    let label: String
    var isHighlighted: Bool = false
    let action: () -> Void
    @Environment(\.chatTheme) private var theme

    static let normalCircleSize: CGFloat = 65
    static let highlightedCircleSize: CGFloat = 70
    static let labelFontSize: CGFloat = 13
    
    private var currentCircleSize: CGFloat { isHighlighted ? OverlayButton.highlightedCircleSize : OverlayButton.normalCircleSize }
    private var iconFontSize: CGFloat { isHighlighted ? 24 : 22 }
    private let staticTextIconFontSize: CGFloat = 24
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: OverlayButton.labelFontSize))
                    .foregroundColor(isHighlighted ? Color.white : Color.gray.opacity(0.8))
                
                ZStack {
                    Circle()
                        .fill(isHighlighted ? Color.white : Color(UIColor.darkGray).opacity(0.8))
                        .frame(width: currentCircleSize, height: currentCircleSize)

                    if let iconName = iconSystemName {
                        Image(systemName: iconName)
                            .font(.system(size: iconFontSize, weight: .medium))
                            .foregroundColor(isHighlighted ? (iconName == "xmark" ? theme.colors.statusError : .black) : Color(UIColor.lightGray))
                    } else if let text = textIcon {
                        Text(text)
                            .font(.system(size: staticTextIconFontSize, weight: .semibold))
                            .foregroundColor(isHighlighted ? .black : Color(UIColor.darkGray))
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .frame(width: OverlayButton.highlightedCircleSize, height: OverlayButton.highlightedCircleSize + OverlayButton.labelFontSize + 8)
    }
}