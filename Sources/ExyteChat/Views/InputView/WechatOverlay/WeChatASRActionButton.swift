// Chat/Sources/ExyteChat/Views/InputView/WechatOverlay/WeChatASRActionButton.swift
import SwiftUI

struct WeChatASRActionButton: View {
    let iconSystemName: String
    let label: String
    let action: () -> Void

    // Styling constants to match WeChat UI for these specific buttons
    // These are smaller than the drag-target buttons
    private let iconSize: CGFloat = 22 // Smaller icon
    private let labelFontSize: CGFloat = 11 // Smaller label
    private let buttonWidth: CGFloat = 60 // Adjusted width for a more compact layout

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) { // Reduced spacing
                Image(systemName: iconSystemName)
                    .font(.system(size: iconSize, weight: .regular)) // Regular weight might be closer
                    .foregroundColor(Color.white.opacity(0.75)) // Subdued icon color

                Text(label)
                    .font(.system(size: labelFontSize))
                    .foregroundColor(Color.white.opacity(0.65)) // Subdued label color
            }
            .frame(width: buttonWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
        HStack(spacing: 15) { // Adjusted spacing for preview
            WeChatASRActionButton(iconSystemName: "arrow.uturn.backward", label: "Cancel") {
                print("Cancel tapped")
            }
            WeChatASRActionButton(iconSystemName: "waveform", label: "Send Voice") {
                print("Send Voice tapped")
            }
        }
    }
}

