// Chat/Sources/ExyteChat/Views/InputView/WechatOverlay/ASRResultView.swift
import SwiftUI

struct ASRResultView: View {
    @Bindable var inputViewModel: InputViewModel
    @Environment(\.chatTheme) private var theme
    @EnvironmentObject var keyboardState: KeyboardState // To adjust for keyboard
    var localization: ChatLocalization
    var targetWidth: CGFloat
    
    @State private var showingLanguageSheet = false
    // The @FocusState now directly uses the one from the ViewModel
    // No, ASRResultView should own its FocusState and coordinate with VM if needed,
    // or VM owns it and ASRResultView binds to it.
    // Let's have ASRResultView own it and VM requests it.
    @FocusState private var isTextEditorFocused: Bool
    
    
    private let asrBubbleColor = Color(red: 130/255, green: 230/255, blue: 100/255)
    private let asrTextColor = Color.black.opacity(0.85)
    private let bubbleCornerRadius: CGFloat = 12
    private let minASRBubbleVisibleHeight: CGFloat = 100.0
    private var tipSize: CGSize { CGSize(width: 20, height: 10) }
    private var tipPosition: BubbleWithTipShape.TipPosition { .bottom_edge_horizontal_offset }
    private var tipOffsetPercentage: CGFloat { 0.78 }
    
    // Max height for the scrollable text area within the bubble
    private let maxTextEditorHeight: CGFloat = 160 // Adjust as needed, e.g., 3-4 lines
    private let minTextEditorHeight: CGFloat = 30 // Min height for one line
    
    
    private var errorLocalization: String  {
        if inputViewModel.asrErrorMessage == "100" {
            return localization.unableToRecognizeWordsText
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 5) {
            
            // 1. Ellipsis Button (Language Change) - Placed above the bubble
//            if !inputViewModel.isEditingASRTextInOverlay { // Show options only when not editing
                HStack {
                    Spacer()
                    Button { showingLanguageSheet = true } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(Color.black.opacity(0.8)) // Assuming white is visible on your overlay background
                            .padding(8) // Padding for tap area
                            .background(Color.white.opacity(0.5).clipShape(Circle())) // Optional: subtle background for the button
                    }
//                    .padding(.trailing, 5)
                    .transition(.opacity)
                }
//            }
            // 2. The ASR Bubble (original ZStack or VStack with .background)
            //    No major changes needed inside the bubble structure itself for this request.
            //    We just need to ensure the ZStack that *was* holding the button and bubble
            //    is now just focused on the bubble.
            
            VStack(spacing: 0) { // Bubble content
                ScrollView {
                    textContentArea()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .frame(minHeight: minTextEditorHeight, maxHeight: maxTextEditorHeight)
            }
            .padding(.bottom, tipSize.height > 0 ? tipSize.height : 0)
            .frame(minHeight: minASRBubbleVisibleHeight)
            .frame(width: targetWidth)
            .background(BubbleWithTipShape(cornerRadius: bubbleCornerRadius, tipSize: tipSize, tipPosition: tipPosition, tipOffsetPercentage: tipOffsetPercentage).fill(asrBubbleColor))
            .clipShape(BubbleWithTipShape(cornerRadius: bubbleCornerRadius, tipSize: tipSize, tipPosition: tipPosition, tipOffsetPercentage: tipOffsetPercentage))
            .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
            .onTapGesture {
                if !inputViewModel.isEditingASRTextInOverlay &&
                    inputViewModel.asrErrorMessage == nil, // Check for error
                   case .asrCompleteWithText(let text) = inputViewModel.weChatRecordingPhase
                { // Check if text is not empty
                    inputViewModel.startEditingASRText()
                }
            }
            
            // 3. Helper Text (remains below the bubble)
            if !inputViewModel.isEditingASRTextInOverlay &&
                inputViewModel.asrErrorMessage == nil &&
                inputViewModel.weChatRecordingPhase == .asrCompleteWithText(inputViewModel.transcribedText) && // Ensure phase matches
                !inputViewModel.transcribedText.isEmpty {
                HStack {
                    Spacer()
                    Text(localization.tapToEditText)
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.7))
//                        .transition(.opacity) // Animate its appearance/disappearance
                }
                .padding(.horizontal, 10)
                
            }
        }
        .animation(.easeInOut(duration: 0.2), value: inputViewModel.isEditingASRTextInOverlay)
        .frame(width: targetWidth)
        .sheet(isPresented: $showingLanguageSheet) {
            LanguageSelectionSheetView(isPresented: $showingLanguageSheet, inputViewModel: inputViewModel)
//                .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
                .presentationDetents([.height(UIScreen.main.bounds.height * 0.35)])
        }
        .onChange(of: inputViewModel.isASROverlayEditorFocused) { _, shouldBeFocused in
            // Sync VM's focus request to local @FocusState
            if isTextEditorFocused != shouldBeFocused {
                isTextEditorFocused = shouldBeFocused
                if shouldBeFocused {
                    DebugLogger.log("ASRResultView: TextEditor received focus request from VM.")
                }
            }
        }
        .onChange(of: isTextEditorFocused) { _, isFocusedNow in
            // If editor loses focus and we were in edit mode, tell VM to potentially exit edit mode.
            if !isFocusedNow && inputViewModel.isEditingASRTextInOverlay {
                DebugLogger.log("ASRResultView: TextEditor lost focus. Informing VM.")
                // This might be too aggressive if user temporarily switches app.
                // Consider if this should revert to non-editing display or just update VM's focus flag.
                inputViewModel.endASREditSession(discardChanges: false)
                // To prevent immediately exiting edit mode if keyboard dismissed by system:
                // We might want a small delay or check if keyboard is also gone.
                // For now, if focus is lost, assume edit mode might need to be re-evaluated by VM.
                // If user taps outside, for example.
            }
        }
    }
    
    @ViewBuilder
    private func textContentArea() -> some View {
        if let _ = inputViewModel.asrErrorMessage {
            Text("Error: \(errorLocalization)")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(theme.colors.statusError)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if inputViewModel.isEditingASRTextInOverlay {
            CustomTextEditor(text: $inputViewModel.currentlyEditingASRText)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(asrTextColor)
//                .padding(.leading, -5) // Minor adjustment often needed for TextEditor internal padding
//                .padding(.top, -8)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minTextEditorHeight) // Or calculate based on text
                .focused($isTextEditorFocused)
                .id("asrOverlayTextEditor")
        } else {
            Text(inputViewModel.currentlyEditingASRText.isEmpty ?
                 inputViewModel.transcribedText : inputViewModel.currentlyEditingASRText)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(asrTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // Language Selection Action Sheet
    private var languageActionSheet: ActionSheet {
        var buttons: [ActionSheet.Button] = inputViewModel.transcriber.availableLocales.map { locale in
                .default(Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)) {
                    Task {
                        await inputViewModel.transcriber.changeLanguage(toLocale: locale)
                        // Optionally, you might want to re-transcribe or inform the user
                        // that the language has changed for the *next* recording.
                        // For now, this just changes the presenter's state.
                    }
                }
        }
        buttons.append(.cancel())
        
        return ActionSheet(
            title: Text("Select Language"), // TODO: Localize
            message: Text("Choose the language for speech-to-text."), // TODO: Localize
            buttons: buttons
        )
    }
}

#if DEBUG
@MainActor
struct ASRResultView_Previews_Content: View {
    @State var vm1 = InputViewModel.mocked(text: "Pew pew pew pew la", phase: .asrCompleteWithText("Pew pew pew pew la"))
    @State var vm2 = InputViewModel.mocked(text: "Short", phase: .asrCompleteWithText("Short"))
    @State var vm3 = InputViewModel.mocked(text: "This is a much longer transcribed text that will definitely exceed the initial height and should become scrollable within its designated area, not expanding the bubble indefinitely.", phase: .asrCompleteWithText("This is a much longer transcribed text that will definitely exceed the initial height and should become scrollable within its designated area, not expanding the bubble indefinitely."))
    @State var vm4 = InputViewModel.mocked(text: "", error: "Speech recognition failed.", phase: .asrCompleteWithText(""))
    @State var vm5 = InputViewModel.mocked(text: "", phase: .asrCompleteWithText(""))
    
    
    let localization = ChatLocalization(
        inputPlaceholder: "Type...", signatureText: "Sign...", cancelButtonText: "Cancel", recentToggleText: "Recents",
        waitingForNetwork: "Waiting...", recordingText: "Recording...", replyToText: "Reply to", holdToTalkText: "Hold to Talk",
        releaseToSendText: "Release to Send", releaseToCancelText: "Release to Cancel", convertToTextButton: "En",
        tapToEditText: "Tap the bubble to edit the text", sendVoiceButtonText: "Send Voice", unableToRecognizeWordsText: "unableToRecognizeWordsText"
    )
    let previewTargetWidth = UIScreen.main.bounds.width * 0.9
    
    var body: some View {
        ZStack {
            Color.gray.opacity(0.7).edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                ASRResultView(inputViewModel: vm1, localization: localization, targetWidth: previewTargetWidth)
                ASRResultView(inputViewModel: vm2, localization: localization, targetWidth: previewTargetWidth)
                ASRResultView(inputViewModel: vm3, localization: localization, targetWidth: previewTargetWidth)
                ASRResultView(inputViewModel: vm4, localization: localization, targetWidth: previewTargetWidth)
                ASRResultView(inputViewModel: vm5, localization: localization, targetWidth: previewTargetWidth)
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}

// Add a static func to InputViewModel for easier preview mocking
extension InputViewModel {
    @MainActor static func mocked(text: String = "", error: String? = nil, phase: WeChatRecordingPhase = .idle) -> InputViewModel {
        let vm = InputViewModel()
        vm.transcribedText = text
        vm.asrErrorMessage = error
        vm.weChatRecordingPhase = phase
        // Setup some default available locales for the transcriber in the VM
        let exampleLocales = [Locale(identifier: "en-US"), Locale(identifier: "es-ES"), Locale(identifier: "fr-FR")]
        vm.transcriber = DefaultTranscriberPresenter(config: .init(locale: exampleLocales.first!)) // Initialize with a default
        // You might need to manually set availableLocales if the default initializer doesn't populate it as expected for previews
        // vm.transcriber.availableLocales = exampleLocales // This would require making availableLocales settable or passing via init
        return vm
    }
}

#Preview {
    ASRResultView_Previews_Content()
}

#endif
