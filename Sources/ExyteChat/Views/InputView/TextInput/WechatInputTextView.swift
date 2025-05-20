//
//  ChatSubmitUITextView.swift
//  Chat
//
//  Created by Yangming Zhang on 5/18/25.
//

import SwiftUI
import UIKit
// In ChatSubmitUITextView.swift
struct WechatInputTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var parentFocusBinding: Focusable? // This is typically globalFocusState.focus
    var inputFieldID: UUID
    var onSend: (String) -> Void
    
    var onHeightDidChange: ((CGFloat) -> Void)?
    
    var font: UIFont = UIFont.preferredFont(forTextStyle: .body)
    var cornerRadius: CGFloat = 8
    var backgroundColor: UIColor = UIColor.systemBackground
    var textContainerInset: UIEdgeInsets = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
    
    var defaultHeight: CGFloat {
        font.lineHeight + textContainerInset.top + textContainerInset.bottom
    }
    var maxLines: CGFloat = 10
    var maxHeight: CGFloat {
        (font.lineHeight * maxLines) + textContainerInset.top + textContainerInset.bottom
    }
    
    init(
        text: Binding<String>,
        placeholder: String,
        parentFocusBinding: Binding<Focusable?>,
        inputFieldID: UUID,
        font: UIFont = UIFont.preferredFont(forTextStyle: .body),
        // ... other non-closure params ...
        onSend: @escaping (String) -> Void,
        onHeightDidChange: @escaping (CGFloat) -> Void // Made non-optional and last
    ) {
        _text = text
        self.placeholder = placeholder
        _parentFocusBinding = parentFocusBinding
        self.inputFieldID = inputFieldID
        self.font = font
        // ...
        self.onSend = onSend
        self.onHeightDidChange = onHeightDidChange
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        
        textView.font = font
        textView.backgroundColor = backgroundColor
        textView.layer.cornerRadius = cornerRadius
        textView.textContainerInset = textContainerInset
        
        textView.returnKeyType = .send
        textView.enablesReturnKeyAutomatically = true
        
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        if self.text.isEmpty {
            textView.text = placeholder
            textView.textColor = UIColor.placeholderText
        } else {
            textView.text = self.text
            textView.textColor = UIColor.label
        }
        
        // Initial height calculation via coordinator, dispatched to run after layout pass
        DispatchQueue.main.async {
            context.coordinator.updateHeight(for: textView)
        }
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Sync text
        if uiView.textColor == UIColor.placeholderText && !self.text.isEmpty {
            // If text view has placeholder but binding has text (e.g. programmatic change), update it
            uiView.text = self.text
            uiView.textColor = UIColor.label
        } else if uiView.textColor != UIColor.placeholderText && uiView.text != self.text {
            // If text view has actual text and it differs from binding, update it
            uiView.text = self.text
        }
        // If binding is empty and text view doesn't have placeholder (and not focused), set placeholder
        if self.text.isEmpty && uiView.textColor != UIColor.placeholderText && !uiView.isFirstResponder {
            uiView.text = placeholder
            uiView.textColor = UIColor.placeholderText
        }
        
        // Manage focus directly based on parentFocusBinding
        // updateUIView is already on the main thread.
        if parentFocusBinding == .uuid(inputFieldID) {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
        
        // Update height if necessary
        context.coordinator.updateHeight(for: uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: WechatInputTextView
        
        init(_ parent: WechatInputTextView) {
            self.parent = parent
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.textColor == UIColor.placeholderText {
                textView.text = nil
                textView.textColor = UIColor.label
            }
            // Update parentFocusBinding (globalFocusState.focus)
            // This is the primary way user interaction with UITextView updates the global focus
            DispatchQueue.main.async {
                if self.parent.parentFocusBinding != .uuid(self.parent.inputFieldID) {
                    self.parent.parentFocusBinding = .uuid(self.parent.inputFieldID)
                }
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = UIColor.placeholderText
            }
            // Update parentFocusBinding (globalFocusState.focus)
            DispatchQueue.main.async {
                if self.parent.parentFocusBinding == .uuid(self.parent.inputFieldID) {
                    self.parent.parentFocusBinding = nil
                }
            }
            updateHeight(for: textView)
        }
        
        func textViewDidChange(_ textView: UITextView) {
            // Update bound text property
            // No need for DispatchQueue.main.async here for parent.text update
            // as this delegate method is already on the main thread.
            // However, if parent.text update itself triggers complex SwiftUI view updates,
            // deferring might be considered, but usually not needed for simple binding.
            if textView.textColor != UIColor.placeholderText {
                if self.parent.text != textView.text {
                    self.parent.text = textView.text
                }
            } else if textView.text != self.parent.placeholder { // Started typing over placeholder
                if !textView.text.isEmpty {
                    textView.textColor = UIColor.label
                    if self.parent.text != textView.text {
                        self.parent.text = textView.text
                    }
                }
            }
            self.updateHeight(for: textView)
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                if textView.textColor != UIColor.placeholderText && !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parent.onSend(textView.text)
                } else {
                    parent.onSend("")
                }
                return false
            }
            
            if textView.textColor == UIColor.placeholderText && !text.isEmpty {
                textView.text = ""
                textView.textColor = UIColor.label
            }
            return true
        }
        
        func updateHeight(for textView: UITextView) {
            let fixedWidth = textView.frame.size.width > 0 ?
            (textView.frame.size.width - textView.textContainerInset.left - textView.textContainerInset.right) :
            (UIScreen.main.bounds.width - 100) // Fallback width, adjust as needed
            
            guard fixedWidth > 0 else {
                // Call with default height if width isn't determined yet, or use a last known good height
                parent.onHeightDidChange?(parent.defaultHeight)
                return
            }
            
            let newSize = textView.sizeThatFits(CGSize(width: fixedWidth, height: .greatestFiniteMagnitude))
            let calculatedHeight = newSize.height
            let newHeightToSet = max(parent.defaultHeight, min(calculatedHeight, parent.maxHeight))
            
            parent.onHeightDidChange?(newHeightToSet)
            textView.isScrollEnabled = calculatedHeight >= parent.maxHeight
        }
    }
}

// Optional Helper for Dynamic Height Calculation (makes it fit content)
//extension UITextView {
//    override open var intrinsicContentSize: CGSize {
//        // Ensure font is not nil - though it usually isn't on a UITextView
//        guard let font = self.font else {
//            // Minimal fallback if font is somehow nil
//            return CGSize(width: UIView.noIntrinsicMetric, height: 30)
//        }
//        
//        if text.isEmpty {
//            // --- ADJUST EMPTY HEIGHT CALCULATION ---
//            // Use font.lineHeight directly (it's not optional here)
//            let emptyHeight =
//            font.lineHeight + textContainerInset.top
//            + textContainerInset.bottom
//            return CGSize(width: UIView.noIntrinsicMetric, height: emptyHeight)
//            // ----------------------------------------
//        } else {
//            // Calculation for non-empty text
//            let fixedWidth =
//            frame.size.width - textContainerInset.left
//            - textContainerInset.right
//            // Ensure fixedWidth is positive
//            guard fixedWidth > 0 else {
//                let fallbackHeight =
//                font.lineHeight + textContainerInset.top
//                + textContainerInset.bottom
//                return CGSize(
//                    width: UIView.noIntrinsicMetric,
//                    height: fallbackHeight
//                )
//            }
//            
//            let size = sizeThatFits(
//                CGSize(width: fixedWidth, height: .greatestFiniteMagnitude)
//            )
//            // Ensure minimum height is at least one line plus padding
//            // Use font.lineHeight directly
//            let desiredHeight = max(
//                size.height,
//                font.lineHeight + textContainerInset.top
//                + textContainerInset.bottom
//            )
//            
//            return CGSize(
//                width: UIView.noIntrinsicMetric,
//                height: desiredHeight
//            )
//        }
//    }
//}
//
