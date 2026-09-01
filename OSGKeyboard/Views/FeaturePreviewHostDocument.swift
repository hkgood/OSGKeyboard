// FeaturePreviewHostDocument.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Fills the empty band above the scripted keyboard demos so a full-screen
// App Store preview can be recorded from them. The What's New workflow crops
// to the keyboard chrome and must keep its blank backdrop, so every demo view
// only shows this when `--preview-fullscreen` is passed.
//
// Visual language deliberately matches `NotesHostDemoView` — the same
// Notes / Messages stand-in the extension-based recordings sit on top of.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

enum FeaturePreviewFlags {
    /// Opt into the full-screen host document above the keyboard chrome.
    static var isFullscreen: Bool {
        ProcessInfo.processInfo.arguments.contains("--preview-fullscreen")
    }
}

/// A Notes- or Messages-like document that reacts to the demo timeline.
struct FeaturePreviewHostDocument: View {
    enum Kind {
        case notes
        case messages
    }

    let kind: Kind
    let title: String
    /// Text the keyboard has produced so far. Empty renders the placeholder.
    let text: String
    /// Messages only — the message being replied to.
    var incoming: String?
    /// Draws the send-confirmed state for the AI clip's closing beat.
    var isSent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 4)

            switch kind {
            case .notes:
                notesBody
            case .messages:
                messagesBody
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 56)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notesBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 20))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            } else {
                HStack(alignment: .top, spacing: 0) {
                    Text(text)
                        .font(.system(size: 20))
                        .foregroundStyle(Color(uiColor: .label))
                        .multilineTextAlignment(.leading)
                    caret
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        // Text lands in a stable place instead of jumping as it grows.
        .animation(.easeOut(duration: 0.2), value: text)
    }

    private var messagesBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            if let incoming, !incoming.isEmpty {
                bubble(incoming, outgoing: false)
            }
            if !text.isEmpty {
                bubble(text, outgoing: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if isSent {
                Text("已发送")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .animation(.easeOut(duration: 0.24), value: text)
        .animation(.easeOut(duration: 0.24), value: isSent)
    }

    private func bubble(_ content: String, outgoing: Bool) -> some View {
        HStack {
            if outgoing { Spacer(minLength: 40) }
            Text(content)
                .font(.system(size: 17))
                .foregroundStyle(outgoing ? Color.white : Color(uiColor: .label))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            outgoing
                                ? Color(red: 0.20, green: 0.66, blue: 0.38)
                                : Color(uiColor: .tertiarySystemFill)
                        )
                )
            if !outgoing { Spacer(minLength: 40) }
        }
    }

    private var caret: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: 24)
            .padding(.leading, 1)
    }

    private var placeholder: String {
        switch kind {
        case .notes: return "开始记录…"
        case .messages: return ""
        }
    }
}
#endif
