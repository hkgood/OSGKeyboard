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
    var appearStressCount: Int = 0

    private var title: String {
        switch (scenario, language) {
        case (.ai, .en): return "Messages"
        case (.ai, .zh): return "信息"
        case (.edit, .en), (.clipboard, .en), (.clipboardSkills, .en): return "Notes"
        case (.edit, .zh), (.clipboard, .zh), (.clipboardSkills, .zh): return "备忘录"
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
                    NotesHostTextView(text: seedText, appearStressCount: appearStressCount)
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
            guard appearStressCount == 0 else { return }
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
    var appearStressCount: Int = 0

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
        view.accessibilityIdentifier = "notes.host.textView"
        context.coordinator.appearStressCount = appearStressCount
        context.coordinator.textView = view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if context.coordinator.appearStressCount > 0 {
                context.coordinator.startAppearStressIfNeeded()
            } else {
                view.becomeFirstResponder()
            }
        }
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text, !context.coordinator.userEdited {
            uiView.text = text
        }
        // Stress owns first-responder; don't fight resignFirstResponder.
        guard appearStressCount == 0 else { return }
        if !uiView.isFirstResponder {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var userEdited = false
        var appearStressCount = 0
        weak var textView: UITextView?
        private var started = false
        private var waitingForShow = false
        private var waitingForHide = false
        private var showWaiter: CheckedContinuation<Bool, Never>?
        private var hideWaiter: CheckedContinuation<Bool, Never>?
        /// Invalidates leftover timeout tasks from a finished wait.
        private var waitGeneration = 0

        func textViewDidChange(_ textView: UITextView) {
            userEdited = true
        }

        func startAppearStressIfNeeded() {
            guard appearStressCount > 0, !started else { return }
            started = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidShow),
                name: UIResponder.keyboardDidShowNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidHide),
                name: UIResponder.keyboardDidHideNotification,
                object: nil
            )
            Task { @MainActor [weak self] in
                await self?.runAppearStress()
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func keyboardDidShow(_ notification: Notification) {
            finishWait(show: true, success: true)
        }

        @objc private func keyboardDidHide(_ notification: Notification) {
            finishWait(show: false, success: true)
        }

        private func finishWait(show: Bool, success: Bool) {
            if show {
                guard waitingForShow, let pending = showWaiter else { return }
                waitingForShow = false
                showWaiter = nil
                waitGeneration += 1
                pending.resume(returning: success)
            } else {
                guard waitingForHide, let pending = hideWaiter else { return }
                waitingForHide = false
                hideWaiter = nil
                waitGeneration += 1
                pending.resume(returning: success)
            }
        }

        @MainActor
        private func runAppearStress() async {
            let total = appearStressCount
            OSGDiag.log("keyboard.stress begin count=\(total)", category: "boot")
            guard let textView else {
                OSGDiag.log("keyboard.stress FAIL textView gone", category: "boot")
                return
            }
            guard await becomeAndWaitForShow(textView, timeoutNanoseconds: 8_000_000_000) else {
                OSGDiag.log("keyboard.stress FAIL first-show timeout", category: "boot")
                return
            }
            OSGDiag.log("keyboard.stress first-show ok", category: "boot")
            var passed = 0
            for cycle in 1...total {
                guard await resignAndWaitForHide(textView, timeoutNanoseconds: 5_000_000_000) else {
                    OSGDiag.log("keyboard.stress FAIL cycle=\(cycle) hide timeout", category: "boot")
                    break
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard await becomeAndWaitForShow(textView, timeoutNanoseconds: 8_000_000_000) else {
                    OSGDiag.log("keyboard.stress FAIL cycle=\(cycle) show timeout", category: "boot")
                    break
                }
                passed += 1
                OSGDiag.log("keyboard.stress cycle=\(passed)/\(total) ok", category: "boot")
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            OSGDiag.log("keyboard.stress done passed=\(passed)/\(total)", category: "boot")
            try? await Task.sleep(nanoseconds: 250_000_000)
            exit(passed == total ? 0 : 1)
        }

        @MainActor
        private func becomeAndWaitForShow(_ textView: UITextView, timeoutNanoseconds: UInt64) async -> Bool {
            await waitForKeyboard(show: true, timeoutNanoseconds: timeoutNanoseconds) {
                textView.becomeFirstResponder()
            }
        }

        @MainActor
        private func resignAndWaitForHide(_ textView: UITextView, timeoutNanoseconds: UInt64) async -> Bool {
            await waitForKeyboard(show: false, timeoutNanoseconds: timeoutNanoseconds) {
                textView.resignFirstResponder()
            }
        }

        @MainActor
        private func waitForKeyboard(
            show: Bool,
            timeoutNanoseconds: UInt64,
            trigger: () -> Void
        ) async -> Bool {
            await withCheckedContinuation { continuation in
                waitGeneration += 1
                let generation = waitGeneration
                if show {
                    waitingForShow = true
                    showWaiter = continuation
                } else {
                    waitingForHide = true
                    hideWaiter = continuation
                }
                trigger()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    guard let self, generation == waitGeneration else { return }
                    self.finishWait(show: show, success: false)
                }
            }
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
