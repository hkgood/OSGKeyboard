import Foundation

/// Remote registry used when fetching on-device model weights.
public enum ModelRegistry: Sendable, Equatable {
    /// Official Hugging Face Hub (`swift-transformers` / `HubApi`).
    case huggingFace(hubEndpoint: String? = nil)
    /// ModelScope.cn — same `owner/model` ids as Hugging Face for aufklarer MLX repos.
    case modelScope(baseURL: String = ModelScopeDownloader.defaultBaseURL, revision: String = "master")
}
