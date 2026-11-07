import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class CompanionStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var attachment: Data?
    @Published var errorMessage: String?
    @Published private(set) var isResponding = false
    @Published private(set) var isPreparingVoice = false
    @Published var isLoadingAttachment = false
    let voiceInput = VoiceInput()
    private var responseTask: Task<Void, Never>?
    private var voiceTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    func send(workerURL: String, speakReplies: Bool) {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isResponding, !isLoadingAttachment, !isPreparingVoice,
              !question.isEmpty || attachment != nil else { return }
        let client = ProxyClient(workerURL: workerURL)
        do {
            _ = try client.endpoint("chat")
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        stopVoice()
        audioPlayer?.stop()
        messages.append(ChatMessage(role: "user", text: question.isEmpty ? "Help me understand this image." : question, imageData: attachment))
        draft = ""
        attachment = nil
        errorMessage = nil
        isResponding = true
        // Keep the entire current session together. A new session clears it explicitly.
        let conversation = messages
        let assistantMessage = ChatMessage(role: "assistant", text: "")
        let assistantMessageID = assistantMessage.id
        messages.append(assistantMessage)
        responseTask = Task {
            defer { isResponding = false }
            do {
                try await client.reply(messages: conversation) { [weak self] text in
                    guard let self, let index = self.messages.firstIndex(where: { $0.id == assistantMessageID }) else { return }
                    self.messages[index].text += text
                }
                guard let answer = messages.last?.text, !answer.isEmpty else {
                    throw CompanionError.invalidResponse
                }
                if speakReplies {
                    let audioData = try await client.speechAudio(for: answer)
                    try Task.checkCancellation()
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                    try AVAudioSession.sharedInstance().setActive(true)
                    audioPlayer = try AVAudioPlayer(data: audioData)
                    audioPlayer?.play()
                }
            } catch {
                // Never leave an empty assistant message in the next API request.
                // Restore input when no text arrived, including cancellation on background.
                if let index = messages.firstIndex(where: { $0.id == assistantMessageID }),
                   messages[index].text.isEmpty {
                    messages.remove(at: index)
                    if let lastQuestion = messages.popLast() {
                        draft = lastQuestion.text
                        attachment = lastQuestion.imageData
                    }
                }
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    func toggleVoice() {
        if voiceInput.isRecording || isPreparingVoice {
            stopVoice()
            return
        }
        guard !isResponding else { return }
        audioPlayer?.stop()
        errorMessage = nil
        isPreparingVoice = true
        voiceTask = Task {
            defer { isPreparingVoice = false }
            do {
                let previousDraft = draft
                try await voiceInput.start { [weak self] transcript in
                    self?.draft = previousDraft.isEmpty ? transcript : previousDraft + " " + transcript
                } onFailure: { [weak self] error in
                    self?.errorMessage = error.localizedDescription
                }
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }

    func stopVoice() {
        voiceTask?.cancel()
        voiceInput.stop()
    }

    func pause() {
        stopVoice()
        audioPlayer?.stop()
        responseTask?.cancel()
    }

    func stopActiveMedia() {
        voiceInput.stop()
        audioPlayer?.stop()
        responseTask?.cancel()
    }

    func newConversation() {
        guard !isResponding else { return }
        stopVoice()
        audioPlayer?.stop()
        messages = []
        draft = ""
        attachment = nil
        errorMessage = nil
    }

    func setAttachment(_ data: Data) throws {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw CompanionError.invalidResponse
        }
        let scale = min(1, 1568 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resizedImage = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.75) else {
            throw CompanionError.invalidResponse
        }
        attachment = jpegData
    }
}
