//
//  BottomControlsView.swift
//  Chat
//
//  Created by Yangming Zhang on 5/14/25.
//

import SwiftUI

struct BottomControlsView: View {
    @Environment(\.chatTheme) private var theme
    
    var currentPhase: WeChatRecordingPhase // Use this
    var localization: ChatLocalization
    var inputViewModel: InputViewModel
    let inputBarHeight: CGFloat
    
    var onCancel: () -> Void // For X button during recording/dragging
    var onConvertToText: () -> Void // For En button (direct tap, if any)
    var onSendTranscribedText: () -> Void
    var onSendVoiceAfterASR: () -> Void
    var onCancelASR: () -> Void

    private let controlsContentHeight: CGFloat = 130
    private let helperTextMinHeight: CGFloat = 20
    private var arcAreaHeight: CGFloat { inputBarHeight * 1.8 } // Adjusted for better proportion
    private var arcSagitta: CGFloat { arcAreaHeight * 0.33 }
    private var maxButtonContainerWidth: CGFloat { OverlayButton.highlightedCircleSize + 10 }
    private var maxButtonContainerHeight: CGFloat {
        OverlayButton.highlightedCircleSize + OverlayButton.labelFontSize + 20
    }
    private var chatPushUpHeight: CGFloat { controlsContentHeight }


    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                
                HStack {
                    if currentPhase == .asrCompleteWithText("") { // Covers empty transcription and error states for button layout
                        // Buttons for IMG_0112.jpg (STT Complete)
                        OverlayButton(iconSystemName: "arrow.uturn.backward", label: localization.cancelButtonText, action: onCancelASR)
                            .frame(width: maxButtonContainerWidth, height: maxButtonContainerHeight)
                        Spacer()
                        OverlayButton(iconSystemName: "waveform", label: "Send Voice", action: onSendVoiceAfterASR) // Needs localization
                            .frame(width: maxButtonContainerWidth, height: maxButtonContainerHeight)
                        Spacer()
                        OverlayButton(iconSystemName: "checkmark", label: "Send", isHighlighted: true, action: onSendTranscribedText) // Needs localization
                            .frame(width: maxButtonContainerWidth, height: maxButtonContainerHeight)
                    } else {
                        // Buttons for IMG_0110.jpg (Recording/Dragging)
                        OverlayButton(
                            iconSystemName: "xmark",
                            label: localization.cancelButtonText,
                            isHighlighted: currentPhase == .draggingToCancel,
                            action: onCancel
                        )
                        .frame(width: maxButtonContainerWidth, height: maxButtonContainerHeight)
                        .background(GeometryReader { geo in
                            let frameInGlobal = geo.frame(in: .global)
                            if inputViewModel.cancelRectGlobal != frameInGlobal {
                                Logger.log("BottomControlsView (Cancel Button): GeometryReader frame(in: .global) = \(frameInGlobal)")
                                DispatchQueue.main.async {
                                    inputViewModel.cancelRectGlobal = frameInGlobal
                                }
                            }
                            return Color.yellow.preference(key: CancelRectPreferenceKey.self, value: frameInGlobal)
                        })
                        

                        Spacer()

                        OverlayButton(
                            textIcon: localization.convertToTextButton, // e.g., "En"
                            label: localization.convertToTextButton,
                            isHighlighted: currentPhase == .draggingToConvertToText,
                            action: onConvertToText // Direct tap action might be less relevant if drag-release is primary
                        )
                        .frame(width: maxButtonContainerWidth, height: maxButtonContainerHeight)
                        .background(GeometryReader { geo in
                            let frameInGlobal = geo.frame(in: .global)
                            if inputViewModel.convertToTextRectGlobal != frameInGlobal {
                                Logger.log("BottomControlsView (To Text Button): GeometryReader frame(in: .global) = \(frameInGlobal)")
                                DispatchQueue.main.async {
                                    inputViewModel.convertToTextRectGlobal = frameInGlobal
                                }
                            }
                            return Color.yellow.preference(key: ConvertToTextRectPreferenceKey.self, value: frameInGlobal)
                        })
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 2)
                
                Text(helperTextForPhase())
                    .font(.system(size: 13))
                    .frame(minHeight: helperTextMinHeight)
                    .foregroundColor(foregroundColorForHelperText())
                    .padding(.bottom, 10)
            }
            .frame(height: controlsContentHeight)

            ZStack {
                ArcBackgroundShape(sagitta: arcSagitta)
                    .fill(arcBackgroundColor())
                    .shadow(color: Color.black.opacity(0.2), radius: 5, y: -2)

                Image(systemName: "radiowaves.right") // Changed icon
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(Color(white: 0.4).opacity(0.7))
                    .offset(y: arcSagitta - (arcAreaHeight / 2.5) - 5) // Adjusted offset
            }
            .frame(height: arcAreaHeight)
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: VoiceOverlayBottomAreaHeightPreferenceKey.self, value: chatPushUpHeight)
        })
    }

    private func helperTextForPhase() -> String {
        switch currentPhase {
        case .recording: return localization.releaseToSendText
        case .idle, .draggingToCancel, .draggingToConvertToText,
                .processingASR, .asrCompleteWithText: return ""
        }
    }

    private func foregroundColorForHelperText() -> Color {
        switch currentPhase {
        case .draggingToCancel: return theme.colors.statusError
        case .asrCompleteWithText : return theme.colors.statusError
        default: return Color.white.opacity(0.9)
        }
    }

    private func arcBackgroundColor() -> LinearGradient {
        let notInArc = currentPhase == .draggingToCancel || currentPhase == .draggingToConvertToText

        let topColor = notInArc ? Color(red: 80/255, green: 80/255, blue: 80/255) : Color.white.opacity(0.8)
        let midColor = notInArc ? Color(red: 70/255, green: 70/255, blue: 70/255) : Color.white.opacity(0.75)
        let bottomColor = notInArc ? Color(red: 60/255, green: 60/255, blue: 60/255) : Color.white.opacity(0.7)

        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: topColor, location: 0),
                .init(color: midColor, location: 0.5),
                .init(color: bottomColor, location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
