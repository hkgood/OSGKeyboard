// AIEventExporter.swift
// OSGKeyboard · Main App
//
// Native Calendar export for the built-in "extract events" skill. Replaces the
// old OSGExtractEvents companion Shortcut: the host requests Calendar access at
// first use (EventKit shows the system prompt) and writes one event per parsed
// line into the default calendar. No Shortcut install required.
//
// The keyboard already encodes each event as a canonical
// `start|end|title|location` line (see AIEventExtraction); this decodes those
// back into EKEvents so the parsing stays in one place.

import EventKit
import Foundation
import OSGKeyboardShared

enum AIEventExporter {
    enum Outcome: Equatable {
        /// At least one event was written. `created` may be < requested if a few
        /// individual saves failed, but the run still succeeded overall.
        case created(count: Int)
        /// The user has denied or restricted Calendar access. Offer Settings.
        case accessDenied
        /// Access was granted but no event could be written (no default calendar,
        /// nothing decoded, or every save threw). Distinct from `accessDenied` so
        /// the UI can tell a permission problem from an empty result.
        case failed
    }

    /// Requests access (prompting on first use) and appends the decoded events to
    /// the default calendar. Safe to call from the main actor; EventKit does its
    /// own threading and `commit` is synchronous.
    static func add(lines: [String]) async -> Outcome {
        let events = lines.compactMap { AIEventExtraction.decode($0) }
        guard !events.isEmpty else {
            AIAgentShortcutRun.trace("host.calendar noDecodableLines given=\(lines.count)")
            return .failed
        }

        let store = EKEventStore()
        let granted = await requestAccess(store)
        guard granted else {
            AIAgentShortcutRun.trace("host.calendar accessDenied")
            return .accessDenied
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            AIAgentShortcutRun.trace("host.calendar noDefaultCalendar")
            return .failed
        }

        var created = 0
        for parsed in events {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = parsed.title
            if let location = parsed.location { event.location = location }
            event.isAllDay = parsed.isAllDay
            event.startDate = parsed.start
            // All-day events have no meaningful end time; EventKit wants a same-day
            // end, so reuse the start. Timed events always carry a resolved end.
            event.endDate = parsed.end ?? parsed.start
            do {
                // Batch the writes: stage without committing, then commit once.
                try store.save(event, span: .thisEvent, commit: false)
                created += 1
            } catch {
                AIAgentShortcutRun.trace("host.calendar saveFailed \(error.localizedDescription)")
            }
        }
        guard created > 0 else {
            store.reset()
            return .failed
        }
        do {
            try store.commit()
        } catch {
            AIAgentShortcutRun.trace("host.calendar commitFailed \(error.localizedDescription)")
            return .failed
        }
        AIAgentShortcutRun.trace("host.calendar created=\(created) of=\(events.count)")
        return .created(count: created)
    }

    /// Write-only is deliberate: this exporter only ever creates events and
    /// never reads the user's calendar, so asking for full access would request
    /// more than the feature needs. `defaultCalendarForNewEvents` remains
    /// available under write-only access.
    private static func requestAccess(_ store: EKEventStore) async -> Bool {
        do {
            return try await store.requestWriteOnlyAccessToEvents()
        } catch {
            AIAgentShortcutRun.trace("host.calendar requestFailed \(error.localizedDescription)")
            return false
        }
    }
}
