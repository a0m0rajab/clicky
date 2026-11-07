import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    var text: String
    var imageData: Data?
}

enum CompanionError: LocalizedError {
    case invalidURL
    case server(Int)
    case invalidResponse
    case incompleteResponse
    case speechUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Add your deployed Worker's HTTPS URL in Settings first."
        case .server(let status): return "Your Worker returned HTTP \(status). Check its configuration and provider credits."
        case .invalidResponse: return "The Worker returned an unexpected response."
        case .incompleteResponse: return "The response was interrupted. Please try again."
        case .speechUnavailable: return "Speech recognition is unavailable. You can still type your question."
        case .permissionDenied: return "Enable microphone and speech recognition access in iOS Settings, or type instead."
        }
    }
}

struct ProxyClient {
    let workerURL: String

    func endpoint(_ path: String) throws -> URL {
        guard let components = URLComponents(string: workerURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let baseURL = components.url else {
            throw CompanionError.invalidURL
        }
        return baseURL.appendingPathComponent(path)
    }

    @MainActor
    func reply(messages: [ChatMessage], onText: (String) -> Void) async throws {
        var request = URLRequest(url: try endpoint("chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestMessages: [[String: Any]] = messages.map { message in
            var content: [[String: Any]] = []
            if let imageData = message.imageData {
                content.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": imageData.base64EncodedString()
                    ]
                ])
            }
            content.append(["type": "text", "text": message.text])
            return ["role": message.role, "content": content]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4-6",
            "max_tokens": 2048,
            "stream": true,
            "system": """
            You are Clicky, a friendly, concise mobile learning companion.
            Help the user understand what they are working on, one clear step at a time.
            You can only see images they explicitly attach, not their live screen.
            Never claim to control their phone or see other apps. When discussing
            an attached image, describe locations in plain language rather than
            emitting desktop POINT tags. Ask a focused question when context is missing.
            """,
            "messages": requestMessages
        ])
        let (responseBytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response)
        var receivedMessageStop = false
        for try await line in responseBytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard let payloadData = payload.data(using: .utf8),
                  let event = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                throw CompanionError.invalidResponse
            }
            switch event["type"] as? String {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String {
                    onText(text)
                }
            case "error":
                throw CompanionError.invalidResponse
            case "message_stop":
                receivedMessageStop = true
            default:
                break
            }
        }
        guard receivedMessageStop else { throw CompanionError.incompleteResponse }
    }

    func speechAudio(for text: String) async throws -> Data {
        var request = URLRequest(url: try endpoint("tts"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": "eleven_flash_v2_5"
        ])
        let (audioData, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        guard response.mimeType?.hasPrefix("audio/") == true else {
            throw CompanionError.invalidResponse
        }
        return audioData
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw CompanionError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw CompanionError.server(response.statusCode) }
    }
}
