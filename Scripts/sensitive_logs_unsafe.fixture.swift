func leakCredential(apiKey: String) {
    print("credential=\(apiKey)")
}

func leakResponse(bodyText: String) {
    OSGLog.flow.error("response=\(bodyText, privacy: .public)")
}

func leakPrompt(text: String) {
    debug("prompt=\(text)")
}

func leakResult(result: FlowResult) {
    FlowTrace.warn("failed", "message=\(result.text ?? "nil")")
}

func leakError(error: FlowTranscriptionError) {
    debug("failure=\(error.message)")
}

enum FlowTrace {
    static func transcript(_ step: String, _ text: String) {
        print("stage=\(step) text=\(text)")
    }
}
