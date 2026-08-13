// FlowTrace.swift
// OSGKeyboard · Shared
//
// One greppable trace channel for the whole voice path:
//
//   capture → downsample → utterance gate → chunker → ASR → polish → keyboard
//
// Every line is `[trace] stage=<area>.<step> key=value …`, so a single
// Console.app filter (subsystem `com.osgkeyboard.ios`, message contains
// `[trace]`) replays one utterance end to end. The `stage=` tag keeps the
// stages sortable, which matters because the pipeline spans two processes
// (main app captures and recognises, keyboard extension inserts).
//
// Transcript payloads are never logged. Both DEBUG and Release retain only
// structural metadata so recognised speech cannot land in console archives.

import Foundation
import os

public enum FlowTrace {

    // MARK: - Stage channels

    /// Mic capture and audio plumbing (engine, converter, gate, drain).
    public static func capture(_ step: String, _ detail: String = "") {
        OSGLog.flow.info("[trace] stage=capture.\(step, privacy: .public) \(detail, privacy: .public)")
    }

    /// Chunking and transcript stitching between capture and the ASR engine.
    public static func pipeline(_ step: String, _ detail: String = "") {
        OSGLog.flow.info("[trace] stage=pipeline.\(step, privacy: .public) \(detail, privacy: .public)")
    }

    /// Recognition engine boundary (local SpeechAnalyzer or cloud provider).
    public static func asr(_ step: String, _ detail: String = "") {
        OSGLog.asr.info("[trace] stage=asr.\(step, privacy: .public) \(detail, privacy: .public)")
    }

    /// LLM polish / translation stage.
    public static func polish(_ step: String, _ detail: String = "") {
        OSGLog.flow.info("[trace] stage=polish.\(step, privacy: .public) \(detail, privacy: .public)")
    }

    /// Keyboard extension side: result delivery and text insertion.
    public static func keyboard(_ step: String, _ detail: String = "") {
        OSGLog.keyboardExt.info("[trace] stage=keyboard.\(step, privacy: .public) \(detail, privacy: .public)")
    }

    /// Paths that used to fail silently (dropped audio, empty transcripts).
    /// Logged at `warning` so they stand out without changing the filter.
    public static func warn(_ step: String, _ detail: String = "") {
        OSGLog.flow.warning("[trace] stage=\(step, privacy: .public) \(detail, privacy: .public) OUTCOME=SUSPECT")
    }

    // MARK: - Transcript payloads

    /// Logs structural metadata for recognised / polished text.
    ///
    /// `step` names the point in the path (`asr.chunk`, `asr.final`,
    /// `polish.input`, `polish.output`, `keyboard.insert`), so a diff between
    /// two adjacent `text.*` lines shows exactly which stage changed the text.
    /// The payload itself is intentionally omitted in every build configuration.
    public static func transcript(_ step: String, _ text: String, _ detail: String = "") {
        let length = text.count
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        OSGLog.asr.info(
            "[trace] stage=text.\(step, privacy: .public) len=\(length, privacy: .public) empty=\(empty, privacy: .public) \(detail, privacy: .public)"
        )
    }

    // MARK: - Formatting helpers

    /// Sample count → seconds at the canonical 16 kHz ASR rate.
    public static func seconds(samples: Int, sampleRate: Int = 16_000) -> String {
        guard sampleRate > 0 else { return "0.00" }
        return String(format: "%.2f", Double(samples) / Double(sampleRate))
    }

    public static func seconds(since start: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(start))
    }

    /// Root-mean-square of a PCM window — distinguishes "user was silent"
    /// from "audio never reached the recogniser" when a transcript is empty.
    public static func rms(_ samples: [Float]) -> String {
        guard !samples.isEmpty else { return "0.0000" }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return String(format: "%.4f", (sum / Float(samples.count)).squareRoot())
    }
}
