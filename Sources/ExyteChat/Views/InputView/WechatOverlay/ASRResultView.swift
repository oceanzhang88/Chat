//
//  ASRResultView.swift
//  Chat
//
//  Created by Yangming Zhang on 5/14/25.
//


// Chat/Sources/ExyteChat/Views/InputView/Overlay/ASRResultView.swift
import SwiftUI

struct ASRResultView: View { // Renamed struct
    @ObservedObject var inputViewModel: InputViewModel
    @Environment(\.chatTheme) private var theme

    var body: some View {
        VStack {
            // Use asrErrorMessage instead of sttErrorMessage
            if let errorMessage = inputViewModel.asrErrorMessage {
                Text("Error: \(errorMessage)") // TODO: Needs localization
                    .font(.footnote)
                    .foregroundColor(theme.colors.statusError)
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
            } else if inputViewModel.transcribedText.isEmpty && inputViewModel.asrErrorMessage == nil {
                Text("Couldn't hear anything clearly.") // TODO: Needs localization
                    .font(.callout)
                    .foregroundColor(Color.white.opacity(0.8))
                    .padding()
            } else {
                VStack(spacing: 0) { // Use a VStack to stack text and tip
                    ScrollView {
                        Text(inputViewModel.transcribedText)
                            .foregroundColor(Color.black) // Or a dark gray for better readability on green
                            .padding(.horizontal, 16) // Adjust padding as needed
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading) // Ensure text bubble takes available width
                    }
                    .frame(maxHeight: 150) // Keep maxHeight for scrollability

                    // Add the tip/tail here, pointing downwards
                    // You'll need a custom Shape for this or an image
                    Image(systemName: "arrowtriangle.down.fill") // Placeholder, replace with actual tip
                        .resizable()
                        .frame(width: 20, height: 10)
                        .foregroundColor(Color(red: 160/255, green: 230/255, blue: 110/255)) // Match bubble color
                        .offset(y: -1) // Adjust to slightly overlap or sit flush
                }
                .background(Color(red: 160/255, green: 230/255, blue: 110/255)) // WeChat-like green
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 3, y: 2)
                .padding(.horizontal) // Padding for the whole green bubble
                .onTapGesture {
                    Logger.log("Overlay: Transcribed text bubble tapped.")
                    if inputViewModel.attachments.recording != nil {
                        inputViewModel.inputViewAction()(.playRecord)
                    }
                }
            }
        }
    }
}
