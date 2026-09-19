// AIReminderExporter.swift
// OSGKeyboard · Main App
//
// Native Reminders export for the built-in "extract todos" skill. Replaces the
// old companion Shortcut: the host requests Reminders access at first use
// (EventKit shows the system prompt) and writes one reminder per parsed title
// into the default list. No Shortcut install required.

import EventKit
import Foundation
import OSGKeyboardShared

enum AIReminderExporter {
    enum Outcome: Equatable {
        /// At least one reminder was written. `created` may be < requested if a
        /// few individual saves failed, but the run still succeeded overall.
        case created(count: Int)
        /// The user has denied or restricted Reminders access. Offer Settings.
        case accessDenied
        /// Access was granted but no reminder could be written (no default list
        /// or every save threw). Distinct from `accessDenied` so the UI can tell
        /// a permission problem from an empty result.
        case failed
    }

    /// Requests access (prompting on first use) and appends `titles` to the
    /// default reminders list. Safe to call from the main actor; EventKit does
    /// its own threading and `commit` is synchronous.
    static func add(titles: [String]) async -> Outcome {
        let cleaned = titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return .failed }

        let store = EKEventStore()
        let granted = await requestAccess(store)
        guard granted else {
            AIAgentShortcutRun.trace("host.reminders accessDenied")
            return .accessDenied
        }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            AIAgentShortcutRun.trace("host.reminders noDefaultList")
            return .failed
        }

        var created = 0
        for title in cleaned {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = title
            do {
                // Batch the writes: stage without committing, then commit once.
                try store.save(reminder, commit: false)
                created += 1
            } catch {
                AIAgentShortcutRun.trace("host.reminders saveFailed \(error.localizedDescription)")
            }
        }
        guard created > 0 else {
            store.reset()
            return .failed
        }
        do {
            try store.commit()
        } catch {
            AIAgentShortcutRun.trace("host.reminders commitFailed \(error.localizedDescription)")
            return .failed
        }
        AIAgentShortcutRun.trace("host.reminders created=\(created) of=\(cleaned.count)")
        return .created(count: created)
    }

    private static func requestAccess(_ store: EKEventStore) async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            AIAgentShortcutRun.trace("host.reminders requestFailed \(error.localizedDescription)")
            return false
        }
    }
}
