import Foundation
import Speech
import AVFAudio

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isProcessing = false
    @Published var selectedLanguage: Language = .english {
        didSet {
            // Save language preference when it changes
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "selected_language")
        }
    }
    @Published var isRecording = false
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var currentTranscription: String = ""
    private var isCancelled = false
    private var streamingMessage: Message?
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.0  // Changed from 0.5 to 1.0 second
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    private var mainSystemPrompt: String {
        """
        You are a helpful German teacher.
        Respond with language learning material in german in a concise, clear, and structured format with translations in \(selectedLanguage.rawValue).
        -
        Below are the only sections you must include in your response:
        1. **Wortschatz:** Provide 5 examples with definite articles in relation to the user's message. Do not number items.
        e.g: - Der Hund - the dog
        2. **Sätze:** Provide 5 examples in relation to the user's message with translations. Do not number items.
        e.g: - Der Hund ist süß. - The dog is cute.
        3. **Konjugation:** Include the most important conjugations in Präsens, Perfekt, and Präteritum for the most significant verb related to the topic, inlined.
        -
        End your response with three suitable follow-up prompts (not in question form) in \(selectedLanguage.rawValue), formatted like this:
        NEXT PROMPTS:
        1) ...
        2) ...
        3) ...
        """
    }
    
    var hasAPIKey: Bool {
        (try? KeychainService.shared.load(service: "com.neey.app", account: "openai_api_key")) != nil
    }
    
    init() {
        // Load saved language preference
        if let savedLanguage = UserDefaults.standard.string(forKey: "selected_language"),
           let language = Language(rawValue: savedLanguage) {
            selectedLanguage = language
        }
        
        loadMessages()
        updateSpeechRecognizer()
        requestSpeechAuthorization()
    }
    
    func setLanguage(_ language: Language) {
        selectedLanguage = language
        updateSpeechRecognizer()
    }
    
    private func updateSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: selectedLanguage.locale)
    }
    
    func saveAPIKey(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        try? KeychainService.shared.save(data, service: "com.neey.app", account: "openai_api_key")
    }
    
    func clearHistory() {
        if audioEngine.isRunning {
            stopRecording()
        }
        
        isCancelled = true
        isProcessing = false
        
        messages = []
        UserDefaults.standard.removeObject(forKey: "chat_messages")
    }
    
    private func loadMessages() {
        if let data = UserDefaults.standard.data(forKey: "chat_messages"),
           let decodedMessages = try? JSONDecoder().decode([Message].self, from: data) {
            messages = decodedMessages
        }
    }
    
    private func saveMessages() {
        if let encoded = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(encoded, forKey: "chat_messages")
        }
    }
    
    func sendMessage(_ text: String) {
        let message = Message(text: text, type: .sent)
        messages.append(message)
        saveMessages()
        
        streamingMessage = Message(text: "", type: .received)
        messages.append(streamingMessage!)
        
        Task {
            await sendToOpenAI(text)
        }
    }
    
    private func sendToOpenAI(_ text: String) async {
        if isCancelled {
            isCancelled = false
            print("❌ Request was cancelled before starting.")
            return
        }
        
        guard let apiKeyData = try? KeychainService.shared.load(service: "com.neey.app", account: "openai_api_key"),
              let apiKey = String(data: apiKeyData, encoding: .utf8) else { 
            print("❌ No API key found.")
            return 
        }
        
        print("🚀 Starting OpenAI request...")
        isProcessing = true
        defer { isProcessing = false }
        
        if isCancelled {
            isCancelled = false
            print("❌ Request was cancelled after starting.")
            return
        }
        
        let apiMessages = messages.dropLast().map { ["role": $0.type == .sent ? "user" : "assistant", "content": $0.text] }
        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [["role": "system", "content": mainSystemPrompt]] + apiMessages,
            "temperature": 0.9,
            "stream": true
        ]
        
        print("📝 Request payload prepared.")
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { 
            print("❌ Invalid URL.")
            return 
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            if isCancelled {
                isCancelled = false
                print("❌ Request was cancelled before streaming.")
                return
            }
            
            print("📡 Starting stream...")
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            
            var fullContent = ""
            for try await line in bytes.lines {
                if isCancelled {
                    isCancelled = false
                    print("❌ Stream was cancelled.")
                    return
                }
                
                print("📥 Received line: \(line)")
                
                guard line.hasPrefix("data: ") else { 
                    print("⚠️ Skipping non-data line.")
                    continue 
                }
                
                let jsonString = String(line.dropFirst(6))
                guard jsonString != "[DONE]" else {
                    print("✅ Stream completed.")
                    break
                }
                
                print("🔄 Processing chunk: \(jsonString)")
                
                guard let data = jsonString.data(using: .utf8),
                      let response = try? JSONDecoder().decode(StreamResponse.self, from: data),
                      let content = response.choices.first?.delta.content else {
                    print("⚠️ Could not decode chunk.")
                    continue
                }
                
                print("📝 Content chunk: \(content)")
                fullContent += content
                
                await MainActor.run {
                    print("🔄 Updating UI with content length: \(fullContent.count)")
                    if let index = messages.firstIndex(where: { $0.id == streamingMessage?.id }) {
                        messages[index].text = fullContent
                        messages[index].mainContent = fullContent
                    } else {
                        print("⚠️ Could not find streaming message.")
                    }
                }
            }
            
            print("💾 Saving final message...")
            await MainActor.run {
                saveMessages()
                streamingMessage = nil
            }
            print("✅ Message saved.")
            
        } catch {
            print("❌ Error in OpenAI stream: \(error)")
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == streamingMessage?.id }) {
                    messages.remove(at: index)
                }
                streamingMessage = nil
            }
        }
    }
    
    func startRecording() {
        // First ensure any existing recording is properly cleaned up
        cleanupRecording()
        
        isRecording = true
        isCancelled = false
        currentTranscription = ""
        streamingMessage = nil
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to configure audio session:", error)
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        let inputNode = audioEngine.inputNode
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.currentTranscription = result.bestTranscription.formattedString
                
                self.silenceTimer?.invalidate()
                self.silenceTimer = Timer.scheduledTimer(withTimeInterval: self.silenceThreshold, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    if self.isRecording {
                        Task { @MainActor in
                            self.stopRecording()
                        }
                    }
                }
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
    }
    
    private func cleanupRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            if audioEngine.inputNode.numberOfInputs > 0 {
                audioEngine.inputNode.removeTap(onBus: 0)
            }
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    func stopRecording() {
        // First cleanup the recording session
        cleanupRecording()
        isRecording = false
        
        if !currentTranscription.isEmpty {
            sendMessage(currentTranscription)
        }
        
        currentTranscription = ""
    }
    
    private func handleTranscription(_ text: String) {
        currentTranscription = text
    }
    
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
    
    func cancelRecording() {
        cleanupRecording()
        isRecording = false
        currentTranscription = ""
    }
    
    func speakText(_ text: String) {
        // Stop any ongoing speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // Create utterance with the correct language
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE") // German voice
        utterance.rate = 0.4  // Even slower rate for clearer pronunciation
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session:", error)
        }
        
        speechSynthesizer.speak(utterance)
    }
}

enum Language: String, CaseIterable {
    case english = "English"
    case turkish = "Turkish"
    case french = "French"
    case romanian = "Romanian"
    case italian = "Italian"
    case spanish = "Spanish"
    case polish = "Polish"
    case arabic = "العربية"
    
    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en-US")
        case .turkish: return Locale(identifier: "tr-TR")
        case .french: return Locale(identifier: "fr-FR")
        case .romanian: return Locale(identifier: "ro-RO")
        case .italian: return Locale(identifier: "it-IT")
        case .spanish: return Locale(identifier: "es-ES")
        case .polish: return Locale(identifier: "pl-PL")
        case .arabic: return Locale(identifier: "ar-SA")
        }
    }
    
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .turkish: return "🇹🇷"
        case .french: return "🇫🇷"
        case .romanian: return "🇷🇴"
        case .italian: return "🇮🇹"
        case .spanish: return "🇪🇸"
        case .polish: return "🇵🇱"
        case .arabic: return "🇸🇦"
        }
    }
}

struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let content: String
        }
    }
}

struct StreamResponse: Codable {
    let choices: [StreamChoice]
}

struct StreamChoice: Codable {
    let delta: DeltaContent
}

struct DeltaContent: Codable {
    let content: String?
} 
