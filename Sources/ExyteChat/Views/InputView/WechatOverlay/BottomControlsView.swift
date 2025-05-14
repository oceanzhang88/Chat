//
//  BottomControlsView.swift
//  Chat
//
//  Created by Yangming Zhang on 5/14/25.
//

import SwiftUI

struct BottomControlsView: View {
    var currentPhase: WeChatRecordingPhase // Use this
    var localization: ChatLocalization
    var inputViewModel: InputViewModel
    
    var onCancel: () -> Void // For X button during recording/dragging
    var onConvertToText: () -> Void // For En button (direct tap, if any)
    var onSendTranscribedText: () -> Void
    var onSendVoiceAfterASR: () -> Void
    var onCancelASR: () -> Void

    let inputBarHeight: CGFloat
    @Environment(\.chatTheme) private var theme

    private let controlsContentHeight: CGFloat = 130
    private let helperTextMinHeight: CGFloat = 20
    private var arcAreaHeight: CGFloat { inputBarHeight * 1.8 } // Adjusted for better proportion
    private var arcSagitta: CGFloat { arcAreaHeight * 0.33 }
    private var maxButtonContainerWidth: CGFloat { OverlayButton.highlightedCircleSize + 10 }
    private var maxButtonContainerHeight: CGFloat { OverlayButton.highlightedCircleSize + OverlayButton.labelFontSize + 20 }


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
                        .background(GeometryReader { geo in
                            let frameInGlobal = geo.frame(in: .global)
                            Logger.log("BottomControlsView (Cancel Button): GeometryReader frame(in: .global) = \(frameInGlobal)")
                            DispatchQueue.main.async {
                                    if inputViewModel.cancelRectGlobal != frameInGlobal {
                                        inputViewModel.cancelRectGlobal = frameInGlobal
                                    }
                               }
                            return Color.clear
                        })
                        .frame(width: maxButtonContainerWidth, height: maxButtonContainerHeight)

                        Spacer()

                        OverlayButton(
                            textIcon: localization.convertToTextButton, // e.g., "En"
                            label: localization.convertToTextButton,
                            isHighlighted: currentPhase == .draggingToConvertToText,
                            action: onConvertToText // Direct tap action might be less relevant if drag-release is primary
                        )
                        .background(GeometryReader { geo in
                            let frameInGlobal = geo.frame(in: .global)
                            Logger.log("BottomControlsView (To Text Button): GeometryReader frame(in: .global) = \(frameInGlobal)")
                            DispatchQueue.main.async {
                                    if inputViewModel.convertToTextRectGlobal != frameInGlobal {
                                        inputViewModel.convertToTextRectGlobal = frameInGlobal
                                    }
                               }
                            return Color.clear
                        })
                        .frame(width: maxButtonContainerWidth, height: maxButtonContainerHeight)
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
            Color.clear.preference(key: VoiceOverlayBottomAreaHeightPreferenceKey.self, value: arcAreaHeight)
        })
    }

    private func helperTextForPhase() -> String {
        switch currentPhase {
        case .idle: return ""
        case .recording: return localization.releaseToSendText
        case .draggingToCancel: return localization.releaseToCancelText
        case .draggingToConvertToText: return "Release for Speech-to-Text" // Needs localization
        case .processingASR: return "Converting..." // Needs localization
        case .asrCompleteWithText(let text):
//            if inputViewModel.sttErrorMessage != nil { return inputViewModel.sttErrorMessage ?? "Error" }
            return text.isEmpty ? "Couldn't hear clearly. Try again?" : "Tap bubble to edit, or choose an action" // Needs localization
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
        let isCancelOrError = currentPhase == .draggingToCancel

        let topColor = isCancelOrError ? Color(red: 80/255, green: 80/255, blue: 80/255) : Color.white.opacity(0.8)
        let midColor = isCancelOrError ? Color(red: 70/255, green: 70/255, blue: 70/255) : Color.white.opacity(0.75)
        let bottomColor = isCancelOrError ? Color(red: 60/255, green: 60/255, blue: 60/255) : Color.white.opacity(0.7)

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
