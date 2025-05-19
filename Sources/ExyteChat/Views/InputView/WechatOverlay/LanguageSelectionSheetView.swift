// In LanguageSelectionSheetView.swift

import SwiftUI

struct LanguageSelectionSheetView: View {
    @Environment(\.chatTheme) private var theme
    @Binding var isPresented: Bool
    var inputViewModel: InputViewModel
    @State private var tentativelySelectedLocale: Locale
    
    // WeChat-specific styling constants
    private let sheetCornerRadius: CGFloat = 16 // Typical for bottom sheets
    private let buttonHeight: CGFloat = 44
    private let buttonCornerRadius: CGFloat = 8
    private let buttonHorizontalPadding: CGFloat = 16
    private let buttonSpacing: CGFloat = 10
    private let titlePadding: EdgeInsets = .init(top: 20, leading: 16, bottom: 12, trailing: 16)
    private let listRowInsets: EdgeInsets = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
    
    // Define WeChat-like colors (you can move these to your theme if preferred)
    private var okButtonBackgroundColor: Color { theme.colors.messageMyBG } // Use your theme's primary action color
    private var okButtonTextColor: Color { .white }
    private var cancelButtonBackgroundColor: Color { Color(UIColor.systemGray5) }
    private var cancelButtonTextColor: Color { Color(UIColor.label) } // Adapts to light/dark mode
    private var listTextColor: Color { Color(UIColor.label) }
    private var checkmarkColor: Color { theme.colors.messageMyBG } // Or Color.accentColor
    
    init(isPresented: Binding<Bool>, inputViewModel: InputViewModel) {
        self._isPresented = isPresented
        self.inputViewModel = inputViewModel
        self._tentativelySelectedLocale = State(initialValue: inputViewModel.transcriber.currentLocale)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Select language:") // TODO: Localize
                .font(.system(size: 16, weight: .semibold)) // WeChat often uses slightly smaller, bold titles for such sheets
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(titlePadding)
            
            // Standard Divider
            // Divider() // WeChat often doesn't have a prominent divider here, relying on spacing or list separators
            
            // List of Languages
            List {
                ForEach(inputViewModel.transcriber.availableLocales, id: \.identifier) { locale in
                    Button(action: {
                        self.tentativelySelectedLocale = locale
                    }) {
                        HStack {
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                .font(.system(size: 16))
                                .foregroundColor(listTextColor)
                            Spacer()
                            if self.tentativelySelectedLocale == locale {
                                Image(systemName: "checkmark")
                                    .foregroundColor(checkmarkColor)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(listRowInsets) // Apply consistent padding to the HStack content
                        .contentShape(Rectangle()) // Make the whole row tappable
                    }
                    .listRowInsets(EdgeInsets()) // Remove default List row insets
                    .listRowSeparator(.hidden) // Hide default separators, if desired, or use .visible
                }
            }
            .listStyle(.plain) // Crucial for removing default List styling and getting closer to WeChat's look
            .frame(maxHeight: UIScreen.main.bounds.height * 0.6) // Max height for language list
            
            // Bottom Buttons
            HStack(spacing: buttonSpacing) {
                Button { // Cancel Button
                    isPresented = false
                } label: {
                    Text("Cancel") // TODO: Localize
                        .font(.system(size: 17, weight: .medium))
                        .frame(height: buttonHeight)
                        .frame(maxWidth: .infinity)
                        .background(cancelButtonBackgroundColor)
                        .foregroundColor(cancelButtonTextColor)
                        .cornerRadius(buttonCornerRadius)
                }
                
                Button { // OK Button
                    Task {
                        await inputViewModel.transcriber.changeLanguage(toLocale: tentativelySelectedLocale)
                        inputViewModel.transcriber.currentLocale = tentativelySelectedLocale
                    }
                    isPresented = false
                } label: {
                    Text("OK") // TODO: Localize
                        .font(.system(size: 17, weight: .medium))
                        .frame(height: buttonHeight)
                        .frame(maxWidth: .infinity)
                        .background(okButtonBackgroundColor)
                        .foregroundColor(okButtonTextColor)
                        .cornerRadius(buttonCornerRadius)
                }
            }
            .padding(.horizontal, buttonHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, UIApplication.safeArea.bottom > 0 ? UIApplication.safeArea.bottom : 20) // Ensure padding from bottom edge
        }
        // Use system background for the sheet, which adapts to light/dark mode
        .background(Color(UIColor.systemBackground)) // Changed from systemGray6 for a more standard sheet background
        .clipShape(RoundedCorner(radius: sheetCornerRadius, corners: [.topLeft, .topRight])) // Clip only top corners for bottom sheet
        .edgesIgnoringSafeArea(.bottom) // Allow content to go to the very bottom if needed (buttons will have their own padding)
        // This makes the .medium detent naturally smaller.
//        .frame(maxHeight: UIScreen.main.bounds.height * 0.4, alignment: .bottom)
    }
}

// Helper for rounding specific corners (often used for bottom sheets)
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// Preview (Optional, but helpful)
//struct LanguageSelectionSheetView_Previews: PreviewProvider {
//    @State static var isPresented = true
//    // Create a mock InputViewModel that conforms to ObservableObject for preview
//    class MockInputViewModel: InputViewModel { }
//    @StateObject static var mockVM = MockInputViewModel()
//    
//    static var previews: some View {
//        // Initialize mockVM's transcriber and availableLocales for the preview
//        let _ = { // IIFE to set up mock data
//            let config = TranscriberConfiguration(locale: Locale(identifier: "en-US"))
//            mockVM.transcriber = DefaultTranscriberPresenter(config: config)
//            // Manually set some locales for preview if the default init doesn't provide enough.
//            // This assumes DefaultTranscriberPresenter's availableLocales is settable or pre-populated.
//        }()
//        
//        return ZStack {
//            Color.black.opacity(0.3).edgesIgnoringSafeArea(.all) // Dimmed background for context
//            VStack {
//                Spacer()
//                LanguageSelectionSheetView(isPresented: $isPresented, inputViewModel: .init(wrappedValue: mockVM))
//            }
//        }
//    }
//}
