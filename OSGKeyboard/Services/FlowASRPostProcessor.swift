// FlowASRPostProcessor.swift
// OSGKeyboard · Main App
//
// Applies deterministic on-device transcript corrections before Flow branches
// into dictation polish or AI question handling.

import OSGKeyboardShared

enum FlowASRPostProcessor {
    struct Output: Equatable {
        let text: String
        let textForPolish: String
    }

    static func process(
        text: String,
        textForPolish: String,
        engineMode: String,
        dictionary: PersonalDictionary
    ) -> Output {
        guard engineMode == "local" else {
            return Output(text: text, textForPolish: textForPolish)
        }

        let correctionPairs = dictionary.localCorrectionPairs()
        return Output(
            text: LocalASRTranscriptCorrector.apply(text, pairs: correctionPairs),
            textForPolish: LocalASRTranscriptCorrector.apply(
                textForPolish,
                pairs: correctionPairs
            )
        )
    }
}
