import AVFoundation
import Combine
import Speech

@MainActor
final class VoiceInput: ObservableObject {
    @Published private(set) var isRecording = false
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var inputTapInstalled = false
    private var recordingSessionID = UUID()

    func start(onTranscript: @escaping (String) -> Void, onFailure: @escaping (Error) -> Void) async throws {
        let speechPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphonePermission = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard speechPermission == .authorized, microphonePermission else {
            throw CompanionError.permissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            throw CompanionError.speechUnavailable
        }
        stop()
        let sessionID = UUID()
        recordingSessionID = sessionID
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            stop()
            throw CompanionError.speechUnavailable
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        inputTapInstalled = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.recordingSessionID == sessionID else { return }
                if let result {
                    onTranscript(result.bestTranscription.formattedString)
                    if result.isFinal { self.stop() }
                }
                if let error, self.isRecording {
                    self.stop()
                    onFailure(error)
                }
            }
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        recordingSessionID = UUID()
        audioEngine.stop()
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
