// NotesHostDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Minimal Notes / Messages-like host for What's New recording. Only presents a
// text field — the **real** keyboard extension paints over it (Approach A).
// Launch with `--whats-new-host` (+ optional `--whats-new-scenario=` / `--whats-new-lang=`).

#if DEBUG
import SwiftUI
import UIKit
import OSGKeyboardShared

struct NotesHostDemoView: View {
    let scenario: WhatsNewDemoScenario
    let seedText: String
    let language: WhatsNewDemoScenario.Language

    private var title: String {
        switch (scenario, language) {
        case (.ai, .en): return "Messages"
        case (.ai, .zh): return "信息"
        case (.edit, .en), (.clipboard, .en): return "Notes"
        case (.edit, .zh), (.clipboard, .zh): return "备忘录"
        }
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.horizontal, 4)

                if scenario == .ai {
                    ChatHostTextView(text: seedText)
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                } else {
                    NotesHostTextView(text: seedText)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 56)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.light)
        .environment(
            \.locale,
            language == .en ? Locale(identifier: "en") : Locale(identifier: "zh-Hans")
        )
        .task {
            // Refresh TTL while armed; stop once the extension consumes / plays.
            WhatsNewDemoScenario.arm(scenario, seedText: seedText, language: language)
            for _ in 0..<25 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if WhatsNewDemoScenario.isPlaying() { break }
                guard WhatsNewDemoScenario.peek() != nil else { break }
                WhatsNewDemoScenario.arm(scenario, seedText: seedText, language: language)
            }
        }
    }
}

/// UITextView wrapper that becomes first responder so the system presents
/// the real custom keyboard extension.
private struct NotesHostTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 20)
        view.textColor = .label
        view.text = text
        view.isEditable = true
        view.isScrollEnabled = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .default
        view.delegate = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text, !context.coordinator.userEdited {
            uiView.text = text
        }
        if !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var userEdited = false

        func textViewDidChange(_ textView: UITextView) {
            userEdited = true
        }
    }
}

/// Messaging-style composer: Return key is **Send** so AI insert → send is valid.
private struct ChatHostTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 17)
        view.textColor = .label
        view.text = text
        view.isEditable = true
        view.isScrollEnabled = true
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .send
        view.enablesReturnKeyAutomatically = true
        view.delegate = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text, !context.coordinator.userEdited {
            uiView.text = text
        }
        if !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var userEdited = false

        func textViewDidChange(_ textView: UITextView) {
            userEdited = true
        }
    }
}
#endif
