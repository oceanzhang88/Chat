//
//  CustomTextEditor.swift
//  Chat
//
//  Created by Yangming Zhang on 5/18/25.
//


import SwiftUI
import UIKit

struct CustomTextEditor: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont = UIFont.systemFont(ofSize: 17, weight: .medium) // Match your SwiftUI font
    var textColor: UIColor = .label // Adapts to light/dark mode

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator // For text changes

        // --- Attempt to disable internal padding ---
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        // --- End attempt ---

        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = .clear // Make background transparent
        textView.isScrollEnabled = true   // Keep scrolling for long text
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false

        // Allow auto-sizing based on content, up to constraints
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != self.text { // Prevent update loops
            uiView.text = self.text
        }
        if uiView.font != self.font {
            uiView.font = self.font
        }
        if uiView.textColor != self.textColor {
            uiView.textColor = self.textColor
        }
        // You might need to re-evaluate layout if text changes significantly
        // uiView.invalidateIntrinsicContentSize() // Consider this if dynamic height is tricky
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: CustomTextEditor

        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // Ensure this doesn't cause rapid updates if text is also bound elsewhere
            // or if updateUIView also sets textView.text
            if self.parent.text != textView.text {
                self.parent.text = textView.text
            }
        }
    }
}