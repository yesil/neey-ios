import SwiftUI

struct MessageView: View {
    @ObservedObject var message: Message
    var onPromptTap: ((String) -> Void)?
    
    var body: some View {
        VStack(alignment: message.type == MessageType.sent ? .trailing : .leading, spacing: 8) {
            if message.type == MessageType.received {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(message.mainContent.components(separatedBy: "\n"), id: \.self) { line in
                        if !line.contains("NEXT QUESTIONS:") {
                            if line.contains("**Wortschatz:**") || line.contains("**Sätze:**") || line.contains("**Konjugation:**") {
                                Text(line.replacingOccurrences(of: "**", with: ""))
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            } else {
                                Text(line)
                            }
                        }
                    }
                }
                .textSelection(.enabled)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if !message.followUpQuestions.isEmpty {
                    Text("Follow-up Questions:")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 8) {
                        ForEach(message.followUpQuestions, id: \.self) { question in
                            Button(action: {
                                onPromptTap?(question)
                            }) {
                                Text(question)
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
    @Published var followUpQuestions: [String] = []
    
    init(id: UUID = UUID(), text: String, type: MessageType, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.type = type
        self.timestamp = timestamp
        updateContent()
    }
    
    private func updateContent() {
        // Parse follow-up questions if present
        if type == .received && text.contains("NEXT QUESTIONS:") {
            let parts = text.split(separator: "NEXT QUESTIONS:")
            self.mainContent = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            if parts.count > 1 {
                self.followUpQuestions = parts[1]
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.matches(of: #/^\d+\)/#).count > 0 }
                    .map { $0.replacing(#/^\d+\)\s*/#, with: "") }
            } else {
                self.followUpQuestions = []
            }
        } else {
            self.mainContent = text
            self.followUpQuestions = []
        }
    }
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }
    
    enum CodingKeys: String, CodingKey {
        case id, text, type, timestamp, mainContent, followUpQuestions
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        type = try container.decode(MessageType.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        mainContent = try container.decode(String.self, forKey: .mainContent)
        followUpQuestions = try container.decode([String].self, forKey: .followUpQuestions)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(mainContent, forKey: .mainContent)
        try container.encode(followUpQuestions, forKey: .followUpQuestions)
    }
}

enum MessageType: String, Codable, Equatable {
    case sent
    case received
} 
