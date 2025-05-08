// In Sources/ExyteChat/Views/InputView/WeChatInputVew.swift

import SwiftUI

// Keep it public if Step 1 (Attempt 3) worked, otherwise internal might be okay now.
// Let's assume public for now.
struct WeChatInputView: View {

    // ---> ACCEPT VIEW MODELS <---
    @ObservedObject var viewModel: InputViewModel
    @EnvironmentObject var globalFocusState: GlobalFocusState // Use EnvironmentObject

    // Keep internal state for toggling modes
    @State private var isVoiceMode: Bool = false
    @FocusState private var isTextFocused: Bool // Can keep using FocusState

    // Constants remain internal or private
    let buttonSize: CGFloat = 28
    let buttonPadding: CGFloat = 5

    // Environment for theme access
    @Environment(\.chatTheme) private var theme

    // ---> REMOVE OLD INIT <---
    // The view will likely be initialized without parameters now, relying on @ObservedObject / @EnvironmentObject

    // ---> Make body public <---
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // --- 1. Mic/Keyboard Button ---
            Button {
                isVoiceMode.toggle()
                if !isVoiceMode {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFocused = true
                    }
                } else {
                    isTextFocused = false
                    // ---> Use ViewModel Action for Dismissal <---
//                    viewModel.inputViewAction(.requestKeyboardDismiss)
                }
            } label: { /* Button Label - Same as before */
                Image(systemName: isVoiceMode ? "keyboard" : "mic")
                    .resizable().scaledToFit().frame(width: buttonSize, height: buttonSize)
                    .foregroundStyle(theme.colors.mainText).padding(buttonPadding)
            }
            .frame(height: 36 + (buttonPadding * 2))

            // --- 2. TextField or Hold to Talk Button ---
            if isVoiceMode {
                // Hold to Talk Button
                 Button { } label: { Text("Hold to Talk").font(.system(size: 15, weight: .medium)).foregroundStyle(theme.colors.mainText).frame(maxWidth: .infinity).padding(.vertical, 8).background(Color(uiColor: .systemGray5)).clipShape(RoundedRectangle(cornerRadius: 8)).frame(minHeight: 36) }
                // ** Gesture added in later step **
            } else {
                // TextField - Use viewModel.text directly
                TextField("", text: $viewModel.text, axis: .vertical)
                     .placeholder(when: viewModel.text.isEmpty) {
                         // Use viewModel.style here if passed or default to .message
                         Text("Message" ) // TODO: Use localization
                            .foregroundColor(theme.colors.inputPlaceholderText)
                            .padding(.horizontal, 10)
                      }
                     .foregroundStyle(theme.colors.inputText)
                     .focused($isTextFocused) // Keep local focus state
                     .padding(.horizontal, 10).padding(.vertical, 8)
                     .background(Color(uiColor: .systemBackground))
                     .clipShape(RoundedRectangle(cornerRadius: 8)).frame(minHeight: 36)
                     .fixedSize(horizontal: false, vertical: true)
                     .onTapGesture { if !isTextFocused { isTextFocused = true } }
                     // Link local focus to global focus if needed, or rely on external taps setting global focus to nil
//                     .onChange(of: globalFocusState.focus) { newValue in
//                         if newValue != .uuid(viewModel.inputFieldId) { // Check against InputViewModel's ID
//                             isTextFocused = false
//                         }
//                     }
//                     .onChange(of: isTextFocused) { focused in
//                         if focused {
//                             // When local focus state becomes true, update global state
//                             globalFocusState.focus = .uuid(viewModel.inputFieldId)
//                         }
//                     }
            }

            // --- 3. Emoji Button ---
            Button {
                isTextFocused = false
                // ---> Use ViewModel Action for Dismissal <---
//                viewModel.inputViewAction(.requestKeyboardDismiss)
                // TODO: Implement Emoji Picker Action
                print("Emoji button tapped")
            } label: { /* Button Label - Same as before */
                Image(systemName: "face.smiling").resizable().scaledToFit().frame(width: buttonSize, height: buttonSize).foregroundStyle(theme.colors.mainText).padding(buttonPadding)
            }
            .frame(height: 36 + (buttonPadding * 2))

            // --- 4. Add Button ---
            Button {
                isTextFocused = false
                 // ---> Use ViewModel Action for Dismissal <---
//                viewModel.inputViewAction(.requestKeyboardDismiss)
                // ---> Use ViewModel Action for Photo <---
//                viewModel.inputViewAction(.photo)
                print("Add button tapped")
            } label: { /* Button Label - Same as before */
                Image(systemName: "plus.circle.fill").resizable().scaledToFit().frame(width: buttonSize + 2, height: buttonSize + 2).foregroundStyle(theme.colors.mainText).padding(buttonPadding)
            }
            .frame(height: 36 + (buttonPadding * 2))

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 48)
        .background(theme.colors.inputBG)
        // Pass InputViewModel's ID to link focus states
        // Note: This assumes InputViewModel has an 'inputFieldId: UUID' property.
        // If not, it needs to be added or managed differently.
         .onAppear {
             // Ensure local focus matches global on appear if needed
//             if globalFocusState.focus == .uuid(viewModel.inputFieldId) {
//                 isTextFocused = true
//             }
         }
    }
    // Remove helper function if it exists
}
