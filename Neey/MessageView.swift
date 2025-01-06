import SwiftUI

struct SpeakableText: View {
    let text: String
    let viewModel: ChatViewModel
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(text)
            Button(action: {
                viewModel.speakText(text)
            }) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .padding(4)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                    )
            }
        }
    }
}

struct TextView: View {
    let sentence: String
    let translation: String
    let viewModel: ChatViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SpeakableText(text: sentence, viewModel: viewModel)
            Text(translation)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

struct MessageView: View {
    @ObservedObject var message: Message
    var onPromptTap: ((String) -> Void)?
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {           
            VStack(alignment: message.type == MessageType.sent ? .trailing : .leading, spacing: 8) {
                if message.type == MessageType.received {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(message.mainContent.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty && !trimmedLine.contains("NEXT PROMPTS:") && !trimmedLine.hasPrefix("1)") && !trimmedLine.hasPrefix("2)") && !trimmedLine.hasPrefix("3)") {
                                if trimmedLine.contains("**Wortschatz:**") || trimmedLine.contains("**Sätze:**") || trimmedLine.contains("**Konjugation") {
                                    Text(trimmedLine.replacingOccurrences(of: "**", with: ""))
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                } else if trimmedLine.hasPrefix("- ") {
                                    let contentLine = String(trimmedLine.dropFirst(2))  // Remove "- " prefix
                                    if let separatorRange = contentLine.range(of: " - ") {
                                        let sentence = String(contentLine[..<separatorRange.lowerBound])
                                        let translation = String(contentLine[separatorRange.upperBound...])
                                        Group {
                                            if message.mainContent.contains("**Sätze:**") || message.mainContent.contains("**Wortschatz:**") {
                                                TextView(
                                                    sentence: sentence.trimmingCharacters(in: .whitespaces),
                                                    translation: translation.trimmingCharacters(in: .whitespaces),
                                                    viewModel: viewModel
                                                )
                                            } else {
                                                Text(contentLine)
                                            }
                                        }
                                    } else {
                                        Text(contentLine)
                                    }
                                } else {
                                    Text(trimmedLine)
                                }
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !message.followUpPrompts.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(message.followUpPrompts, id: \.self) { prompt in
                                Button(action: {
                                    onPromptTap?(prompt)
                                }) {
                                    Text(prompt)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.blue, lineWidth: 1)
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(16)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.type == MessageType.sent ? .trailing : .leading)
        }
        .padding(.horizontal)
    }
}

class Message: ObservableObject, Identifiable, Codable, Equatable {
    let id: UUID
    @Published var text: String {
        didSet {
            updateContent()
        }
    }
    let type: MessageType
    let timestamp: Date
    @Published var mainContent: String = ""
    @Published var followUpPrompts: [String] = []
    
    init(id: UUID = UUID(), text: String, type: MessageType, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.type = type
        self.timestamp = timestamp
        updateContent()
    }
    
    private func updateContent() {
        // Parse follow-up prompts if present
        if type == .received && text.contains("NEXT PROMPTS:") {
            let parts = text.split(separator: "NEXT PROMPTS:")
            self.mainContent = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if parts.count > 1 {
                self.followUpPrompts = parts[1]
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.matches(of: #/^\d+\)/#).count > 0 }
                    .map { $0.replacing(#/^\d+\)\s*/#, with: "") }
            } else {
                self.followUpPrompts = []
            }
        } else {
            self.mainContent = text
            self.followUpPrompts = []
        }
    }
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }
    
    enum CodingKeys: String, CodingKey {
        case id, text, type, timestamp, mainContent, followUpPrompts
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        type = try container.decode(MessageType.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        mainContent = try container.decode(String.self, forKey: .mainContent)
        followUpPrompts = try container.decode([String].self, forKey: .followUpPrompts)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(mainContent, forKey: .mainContent)
        try container.encode(followUpPrompts, forKey: .followUpPrompts)
    }
}

enum MessageType: String, Codable, Equatable {
    case sent
    case received
} 
