//
//  BottomControlsView.swift
//  Chat
//
//  Created by Yangming Zhang on 5/14/25.
//

import SwiftUI

struct BottomControlsView: View {
    @Environment(\.chatTheme) private var theme
    @EnvironmentObject var keyboardState: KeyboardState // Make sure this is injected if not already

    var currentPhase: WeChatRecordingPhase
    var localization: ChatLocalization
    var inputViewModel: InputViewModel
    let inputBarHeight: CGFloat
    
    var onCancel: () -> Void // For X button during recording/dragging (uses OverlayButton)
    var onConvertToText: () -> Void // For En button during recording/dragging (uses OverlayButton)
    // Actions for ASR result buttons are now handled directly by WeChatASRActionButton and the checkmark button

    // Constants for specific button styling
    private let weChatCheckmarkCircleSize: CGFloat = 65
    private let weChatCheckmarkIconSize: CGFloat = 25

    // Original constants for dragging phase buttons (if OverlayButton is still used for them)
    private let controlsContentHeight: CGFloat = 130
    private let helperTextMinHeight: CGFloat = 20
    private var arcAreaHeight: CGFloat { inputBarHeight * 1.8 }
    private var arcSagitta: CGFloat { arcAreaHeight * 0.33 }
    private var maxButtonContainerWidthForDrag: CGFloat { OverlayButton.highlightedCircleSize + 10 }
    private var maxButtonContainerHeightForDrag: CGFloat {
        OverlayButton.highlightedCircleSize + OverlayButton.labelFontSize + 20
    }
    private var chatPushUpHeight: CGFloat { controlsContentHeight }
    
    // Dynamically determine the height of the arc based on the current phase
    private var currentArcHeight: CGFloat {
        // Hide arc when ASR result is shown
        if case .asrCompleteWithText = currentPhase {
            return 0
        }
        return arcAreaHeight
    }
    
    // Determine if the arc should be visually present and contribute to layout
    private var showArc: Bool {
        // Hide arc when ASR result is shown AND keyboard is active (editing)
        if case .asrCompleteWithText = currentPhase, keyboardState.isShown, inputViewModel.isEditingASRTextInOverlay {
            return false
        }
        // Also, ensure the arc is not shown if the phase itself implies no arc (original logic)
        if case .asrCompleteWithText = currentPhase { // If it's ASR complete, the arc is generally replaced or hidden
            return true
        }
        return true
    }


    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
//                Spacer()
                
                HStack(alignment: .center, spacing: 0) {
                    if case .asrCompleteWithText = currentPhase {
                        WeChatASRActionButton(
                            iconSystemName: "arrow.uturn.backward",
                            label: localization.cancelButtonText,
                            action: {
                                inputViewModel.inputViewAction()(.deleteRecord)
                            }
                        )
                        Spacer()
                        WeChatASRActionButton(
                            iconSystemName: "waveform",
                            label: localization.sendVoiceButtonText,
                            action: {
                                inputViewModel.sendVoiceFromASRResult() // Send will pick up the recording
                            }
                        )
                        Spacer()
                        // Send Text (Checkmark) Button (WeChat Style)
                        Button(action: {
                            inputViewModel.confirmASREditAndSend()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.white) // WeChat green
                                    .frame(width: weChatCheckmarkCircleSize, height: weChatCheckmarkCircleSize)
                                    .shadow(color: Color.black.opacity(0.2), radius: 3.5, y: 1)
                                Image(systemName: "checkmark")
                                    .font(.system(size: weChatCheckmarkIconSize, weight: .medium))
                                    .foregroundColor(Color(red: 76/255, green: 175/255, blue: 80/255))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(width: 80) // Consistent width with other buttons for spacing
                        // Add .disabled modifier
                        .disabled(
                            (inputViewModel.asrErrorMessage != nil) // Disabled if error
                        )
                    } else {
                        // Buttons for IMG_0110.jpg (Recording/Dragging)
                        OverlayButton(
                            iconSystemName: "xmark",
                            label: localization.cancelButtonText,
                            isHighlighted: currentPhase == .draggingToCancel,
                            action: onCancel
                        )
                        .frame(width: maxButtonContainerWidthForDrag, height: maxButtonContainerHeightForDrag)
                        .background(GeometryReader { geo -> Color in
                            let frameInGlobal = geo.frame(in: .global)
                            // Calculate the new frame with increased area
                            let increasedRect = calculateIncreasedDragArea(frameInGlobal: frameInGlobal, type: "xmark")

                            if inputViewModel.cancelRectGlobal != increasedRect {
                                DebugLogger.log("BottomControlsView (Cancel Button): GeometryReader original frame(in: .global) = \(frameInGlobal)")
                                DebugLogger.log("BottomControlsView (Cancel Button): GeometryReader increasedRect = \(increasedRect)")
                                DispatchQueue.main.async {
                                    inputViewModel.cancelRectGlobal = increasedRect
                                }
                            }
                            return Color.yellow
                        })
                        
                        Spacer()

                        OverlayButton(
                            textIcon: localization.convertToTextButton,
                            label: localization.convertToTextButton,
                            isHighlighted: currentPhase == .draggingToConvertToText,
                            action: onConvertToText
                        )
                        .frame(width: maxButtonContainerWidthForDrag, height: maxButtonContainerHeightForDrag)
                        .background(GeometryReader { geo -> Color in
                            let frameInGlobal = geo.frame(in: .global)
                            let increasedRect = calculateIncreasedDragArea(frameInGlobal:frameInGlobal, type: localization.convertToTextButton)

                            if inputViewModel.convertToTextRectGlobal != increasedRect {
                                DebugLogger.log("BottomControlsView (To Text Button): GeometryReader original frame(in: .global) = \(frameInGlobal)")
                                DebugLogger.log("BottomControlsView (To Text Button): GeometryReader increasedRect = \(increasedRect)")
                                DispatchQueue.main.async {
                                    inputViewModel.convertToTextRectGlobal = increasedRect
                                }
                            }
                            return Color.yellow
                        })
                    }
                }
                .padding(.horizontal, currentPhase == .asrCompleteWithText("") ? 20 : 60)
                .padding(.bottom, currentPhase == .asrCompleteWithText("") ? 15 : 2)
                
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
            .frame(height: showArc ? arcAreaHeight : 0)
            .opacity(currentArcHeight > 0 ? 1 : 0)
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: VoiceOverlayBottomAreaHeightPreferenceKey.self, value: showArc ? chatPushUpHeight : 0)
        })
    }
    
    private func calculateIncreasedDragArea(frameInGlobal: CGRect, type: String) -> CGRect {
        // Calculate the new frame with increased area
        let newWidth = UIScreen.main.bounds.width * (type == "xmark" ?  0.55 : 0.5)
        let newHeight = frameInGlobal.height * 1.2
        // It's generally safer to adjust the size and keep the origin the same,
        // or adjust the origin to keep the center the same.
        // Here, we'll keep the origin the same and just expand width/height.
        // If you need to keep the center, the origin calculation would be:
         let newX = frameInGlobal.origin.x - (newWidth - frameInGlobal.width) / 2
         let newY = frameInGlobal.origin.y - (newHeight - frameInGlobal.height) / 2
         return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
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
        let inArcActionZone = currentPhase == .draggingToCancel || currentPhase == .draggingToConvertToText

        let topColor = inArcActionZone ? Color(red: 80/255, green: 80/255, blue: 80/255).opacity(0.85) : Color.white.opacity(0.8)
        let midColor = inArcActionZone ? Color(red: 70/255, green: 70/255, blue: 70/255).opacity(0.8) : Color.white.opacity(0.7)
        let bottomColor = inArcActionZone ? Color(red: 60/255, green: 60/255, blue: 60/255).opacity(0.75) : Color.white.opacity(0.6)

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
