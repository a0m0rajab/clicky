import PhotosUI
import SwiftUI

private enum MobileDesign {
    static let background = Color(red: 0.055, green: 0.063, blue: 0.09)
    static let surface = Color(red: 0.10, green: 0.115, blue: 0.15)
    static let accent = Color(red: 0.40, green: 0.52, blue: 1)
}

struct CompanionView: View {
    @StateObject private var store = CompanionStore()
    @AppStorage("clicky.workerURL") private var workerURL = ""
    @AppStorage("clicky.speakReplies") private var speakReplies = false
    @State private var showsSettings = false
    @State private var selectedPhoto: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.messages.isEmpty {
                    welcome
                } else {
                    conversation
                }
                if let errorMessage = store.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding()
                        .accessibilityLabel("Error: \(errorMessage)")
                }
                composer
            }
            .background(MobileDesign.background)
            .navigationTitle("clicky")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.newConversation()
                        selectedPhoto = nil
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                    .disabled(store.isResponding || store.isLoadingAttachment)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showsSettings) {
                settings
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                store.isLoadingAttachment = true
                defer { store.isLoadingAttachment = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                        throw CompanionError.invalidResponse
                    }
                    try Task.checkCancellation()
                    try store.setAttachment(data)
                } catch {
                    if !Task.isCancelled { store.errorMessage = "Couldn't load that image. Please choose another." }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    store.pause()
                } else if phase == .inactive {
                    // Permission dialogs also make the app inactive. Do not cancel
                    // the first-use permission task before authorization returns.
                    store.stopActiveMedia()
                }
            }
        }
        .tint(MobileDesign.accent)
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("YOUR LITTLE LEARNING COMPANION")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 62, weight: .medium))
                    .foregroundStyle(MobileDesign.accent)
                    .padding(.vertical, 18)
                    .accessibilityHidden(true)
                Text("A little curious?\nLet’s figure it out.")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .tracking(-1.2)
                Text("Ask a question or share a screenshot.\nI’ll help you take the next step.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    suggestion("Explain something simply", icon: "sparkles", prompt: "Explain a difficult idea in simple terms. Ask me what I'd like to learn.")
                    suggestion("Help me with a screenshot", icon: "photo", prompt: "I'd like help understanding a screenshot.")
                    suggestion("Teach me step by step", icon: "stairs", prompt: "Help me learn something new, one step at a time.")
                }
                Text("Only images you choose are shared. No background screen access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 580, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func suggestion(_ title: String, icon: String, prompt: String) -> some View {
        Button { store.draft = prompt } label: {
            HStack {
                Image(systemName: icon).frame(width: 24)
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "arrow.up.left").font(.caption)
            }
            .padding(17)
            .foregroundStyle(.white)
            .background(MobileDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    private var conversation: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(store.messages) { message in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(message.role == "user" ? "YOU" : "CLICKY")
                                .font(.caption2.weight(.bold))
                                .tracking(2)
                                .foregroundStyle(message.role == "user" ? Color.secondary : MobileDesign.accent)
                            if let data = message.imageData, let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel("Attached image")
                            }
                            if message.text.isEmpty {
                                ProgressView().accessibilityLabel("Clicky is thinking")
                            } else {
                                Text(message.text)
                                    .textSelection(.enabled)
                                    .lineSpacing(5)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MobileDesign.surface, in: RoundedRectangle(cornerRadius: 18))
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: 640)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.messages.last?.text) { _, _ in
                scrollProxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 12) {
            if let data = store.attachment, let image = UIImage(data: data) {
                HStack {
                    Image(uiImage: image)
                        .resizable().scaledToFit().frame(height: 60)
                    Text("Image ready to share").font(.caption)
                    Spacer()
                    Button {
                        store.attachment = nil
                        selectedPhoto = nil
                    } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Remove image")
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "plus").frame(width: 32, height: 44)
                }
                .accessibilityLabel("Attach screenshot or photo")
                .disabled(store.isResponding || store.isLoadingAttachment)
                TextField("Ask Clicky anything…", text: $store.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.vertical, 12)
                    .disabled(store.isResponding)
                    .accessibilityLabel("Your question")
                VoiceButton(store: store, voiceInput: store.voiceInput)
                Button {
                    store.send(workerURL: workerURL, speakReplies: speakReplies)
                    if store.attachment == nil { selectedPhoto = nil }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(MobileDesign.accent, in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Send question")
                .disabled(store.isResponding || store.isLoadingAttachment || store.isPreparingVoice ||
                          (store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachment == nil))
            }
            if store.isResponding || store.isLoadingAttachment {
                ProgressView(store.isLoadingAttachment ? "Preparing image…" : "Clicky is responding…")
                    .font(.caption)
            } else {
                Text("A little help. A lot of possibility.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(MobileDesign.surface)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Your Cloudflare Worker") {
                    TextField("https://your-worker.workers.dev", text: $workerURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Worker URL")
                    Text("Use a Worker you own. Messages and selected images are sent there. Provider API keys stay on the Worker, never in this app.")
                        .font(.footnote)
                }
                Section("Voice") {
                    Toggle("Speak replies", isOn: $speakReplies)
                    Text("Spoken replies use your Worker's ElevenLabs configuration. Dictation uses Apple Speech and may send audio to Apple. Tap the microphone to start or stop, review the text, then send.")
                        .font(.footnote)
                }
                Section("Privacy & limits") {
                    Text("Conversations stay in memory and clear when the app closes. The Worker URL and voice preference are saved on this device.")
                    Text("Clicky cannot see other apps, capture your live screen, or move your cursor on iOS. Select a screenshot to give it visual context.")
                    Text("This is a community mobile client for the open-source Clicky repository, not the official HeyClicky app.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsSettings = false }
                }
            }
        }
    }
}

private struct VoiceButton: View {
    @ObservedObject var store: CompanionStore
    @ObservedObject var voiceInput: VoiceInput

    var body: some View {
        Button { store.toggleVoice() } label: {
            Image(systemName: voiceInput.isRecording ? "stop.fill" : "mic")
                .foregroundStyle(voiceInput.isRecording ? .red : MobileDesign.accent)
                .frame(width: 44, height: 44)
                .background(MobileDesign.background, in: Circle())
        }
        .accessibilityLabel(voiceInput.isRecording ? "Stop dictation" : "Start dictation")
        .disabled(store.isResponding || store.isPreparingVoice)
        .hoverEffect(.highlight)
    }
}
