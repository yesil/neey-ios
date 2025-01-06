import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showingAPIKeyAlert = false
    @State private var apiKeyInput = ""
    @State private var showingScanner = false
    @State private var showingLanguageMenu = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageView(message: message, 
                                          onPromptTap: { prompt in
                                              viewModel.sendMessage(prompt)
                                          },
                                          viewModel: viewModel)
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages) { _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id)
                        }
                    }
                }
                    
                HStack {
                    Spacer()
                    
                    if !viewModel.messages.isEmpty {
                        Button(action: viewModel.clearHistory) {
                            Image(systemName: "trash")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                                .frame(width: 60, height: 60)
                                .background(Circle().stroke(Color.red, lineWidth: 2))
                        }
                        
                        Spacer().frame(width: 20)
                    }
                    
                    if viewModel.hasAPIKey {
                        Button(action: {
                            if viewModel.isRecording {
                                viewModel.cancelRecording()
                            } else {
                                viewModel.startRecording()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.isRecording ? "xmark" : "mic")
                                    .font(.system(size: 24))
                                    .foregroundColor(viewModel.isRecording ? .yellow : .blue)
                                if !viewModel.isRecording {
                                    Text(viewModel.selectedLanguage.flag)
                                        .font(.system(size: 24))
                                }
                            }
                            .frame(width: 90, height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 30)
                                    .stroke(viewModel.isRecording ? Color.yellow : Color.blue, lineWidth: 2)
                            )
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    if !viewModel.isRecording {
                                        showingLanguageMenu = true
                                    }
                                }
                        )
                        .confirmationDialog("Select Language", isPresented: $showingLanguageMenu, titleVisibility: .visible) {
                            ForEach(Language.allCases, id: \.self) { language in
                                Button("\(language.flag) \(language.rawValue)") {
                                    viewModel.setLanguage(language)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .animation(.default, value: viewModel.messages.isEmpty)
                .animation(.default, value: viewModel.hasAPIKey)
            }
            .navigationBarHidden(true)
            .alert("Enter OpenAI API Key", isPresented: $showingAPIKeyAlert) {
                TextField("API Key", text: $apiKeyInput)
                    .textContentType(.password)
                Button("Save") {
                    viewModel.saveAPIKey(apiKeyInput)
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingScanner) {
                QRScannerView(apiKey: $apiKeyInput, isPresented: $showingScanner)
            }
            .onAppear {
                print("View appeared")
                checkAPIKey()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    print("Scene became active")
                    checkAPIKey()
                }
            }
        }
    }
    
    private func checkAPIKey() {
        print("Checking API key")
        if !viewModel.hasAPIKey {
            showingAPIKeyAlert = true
        }
    }
    
    private func toggleRecording() {
        if !viewModel.isRecording {
            viewModel.startRecording()
        }
    }
} 
