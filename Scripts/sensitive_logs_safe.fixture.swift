import Foundation

func buildRequest(apiKey: String, payload: Data, provider: String, status: Int) {
    var request = URLRequest(url: URL(string: "https://example.com/v1")!)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = payload
    print("provider=\(provider) status=\(status) responseBytes=\(payload.count)")
}

func traceSafely(transcript: String) {
    FlowTrace.transcript("asr.final", transcript, "source=fixture")
}
