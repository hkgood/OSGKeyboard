// AIModeLLMClientFactory.swift
// OSGKeyboard · Shared
//
// AI-keyboard LLM transport: prefer each provider's richest server-side
// web-search path, then silently fall back to plain completion. Dictation
// polish keeps using `LLMClientFactory` and never opts into search.

import Foundation

public enum AIModeLLMClientFactory {
    /// Build an AI-mode client. Thinking is always forced on for this path.
    /// When `allowWebSearch` is false, returns the plain polish-compatible client.
    public static func make(
        providerId: String,
        baseURL: String,
        apiKey: String,
        model: String,
        allowWebSearch: Bool = true,
        session: URLSession = .shared
    ) -> any LLMClient {
        let plain = LLMClientFactory.make(
            providerId: providerId,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            thinkingEnabled: true,
            session: session
        )
        guard allowWebSearch else { return plain }

        guard let searching = makeSearchingClient(
            providerId: providerId,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            session: session
        ) else {
            return plain
        }

        return AIModeSearchFallbackClient(primary: searching, fallback: plain)
    }

    /// Providers with a documented server-side search path. Others stay on plain complete.
    private static func makeSearchingClient(
        providerId: String,
        baseURL: String,
        apiKey: String,
        model: String,
        session: URLSession
    ) -> (any LLMClient)? {
        switch providerId {
        case "deepseek":
            guard AIModeSearchSupport.deepSeekSupportsResponsesSearch(model: model) else {
                return nil
            }
            return ResponsesAPILLMClient(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                providerId: providerId,
                reasoningEffort: "high",
                session: session
            )
        case "openai", "xai":
            return ResponsesAPILLMClient(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                providerId: providerId,
                reasoningEffort: "medium",
                session: session
            )
        case "qwen", "alibabaCoding":
            return SearchAugmentedChatClient(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                providerId: providerId,
                augmentation: .qwenEnableSearch,
                session: session
            )
        case "zhipu":
            return SearchAugmentedChatClient(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                providerId: providerId,
                augmentation: .zhipuWebSearch,
                session: session
            )
        case "anthropic":
            return AnthropicMessagesClient(
                apiKey: apiKey,
                model: model,
                session: session,
                webSearchEnabled: true,
                thinkingEnabled: true
            )
        case "moonshot":
            // Kimi builtin `$web_search` via tools; degrade if the account/model rejects it.
            return SearchAugmentedChatClient(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                providerId: providerId,
                augmentation: .moonshotBuiltinWebSearch,
                session: session
            )
        default:
            return nil
        }
    }
}

enum AIModeSearchSupport {
    static func deepSeekSupportsResponsesSearch(model: String) -> Bool {
        let lower = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "deepseek-v4-flash"
            || lower.hasPrefix("deepseek-v4-flash")
            || lower.contains("v4-flash")
    }
}

/// Try the search-capable client once; on any failure retry plain completion once.
struct AIModeSearchFallbackClient: LLMClient {
    let primary: any LLMClient
    let fallback: any LLMClient

    var requestTimeout: TimeInterval { primary.requestTimeout }

    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        try await complete(
            messages: [.system(systemPrompt), .user(text)],
            timeout: timeout,
            options: .polishDefault
        )
    }

    func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        try await complete(
            messages: [.system(systemPrompt), .user(text)],
            timeout: timeout,
            options: options
        )
    }

    func complete(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        do {
            return try await primary.complete(
                messages: messages,
                timeout: timeout,
                options: options
            )
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw LLMError.cancelled
        } catch let error as LLMError where error == .cancelled {
            throw error
        } catch {
            #if DEBUG
            print("⚠️ [AIMode] search path failed, retrying without search: \(error)")
            #endif
            return try await fallback.complete(
                messages: messages,
                timeout: timeout,
                options: options
            )
        }
    }

    func completeStreaming(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in primary.completeStreaming(
                        messages: messages,
                        timeout: timeout,
                        options: options
                    ) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError where error == .cancelled {
                    continuation.finish(throwing: error)
                } catch {
                    #if DEBUG
                    print("⚠️ [AIMode] search stream failed, retrying without search: \(error)")
                    #endif
                    // Drop any search-path draft before the plain retry.
                    continuation.yield(.restart)
                    do {
                        for try await event in fallback.completeStreaming(
                            messages: messages,
                            timeout: timeout,
                            options: options
                        ) {
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: LLMError.cancelled)
                    } catch let error as LLMError {
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: LLMError.transport(String(describing: error)))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
