//
//  AIAgentService.swift
//  discreetly
//
//  Core AI Agent Service functionality
//

import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
class AIAgentService: NSObject, ObservableObject {

    // MARK: - Published Properties
    @Published var isActive: Bool = false
    @Published var currentCall: CallRecord?
    @Published var callHistory: [CallRecord] = []
    @Published var agentConfig: AIAgentConfig
    @Published var isListening: Bool = false
    @Published var currentTranscript: String = ""
    @Published var agentResponse: String = ""

    // MARK: - Private Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let synthesizer = AVSpeechSynthesizer()
    private var conversationHistory: [ConversationMessage] = []
    private var decisionEngine: AIDecisionEngine
    private var hasPermissions = false

    // MARK: - Initialization
    override init() {
        self.agentConfig = AIAgentConfig()
        self.decisionEngine = AIDecisionEngine()
        super.init()

        setupAudioSession()
    }


    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Public Methods

    /// Start the AI agent service
    func startAgent() {
        guard !isActive else { return }

        Task {
            hasPermissions = await requestPermissions()
            if hasPermissions {
                setupSpeechRecognizer()
                isActive = true
                print("AI Agent started with permissions")
            } else {
                print("AI Agent failed to start - permissions denied")
            }
        }
    }

    /// Stop the AI agent service
    func stopAgent() {
        guard isActive else { return }

        stopListening()
        isActive = false
        print("AI Agent stopped")
    }

    /// Handle incoming call
    func handleIncomingCall(from number: String, callerName: String? = nil) {
        guard isActive else { return }

        let callRecord = CallRecord(callerNumber: number, callerName: callerName)
        currentCall = callRecord

        // Decide whether to answer based on configuration
        let shouldAnswer = decisionEngine.shouldAnswerCall(
            from: number,
            config: agentConfig,
            callHistory: callHistory
        )

        if shouldAnswer {
            answerCall(callRecord)
        } else {
            // Let it ring or send to voicemail
            print("AI Agent chose not to answer call from \(number)")
        }
    }

    /// Answer an incoming call with AI
    private func answerCall(_ callRecord: CallRecord) {
        var updatedCall = callRecord
        updatedCall.status = .answered
        currentCall = updatedCall

        // Start listening for speech
        startListening()

        // Generate initial greeting
        let greeting = generateGreeting(for: callRecord)
        speak(greeting)

        // Log AI decision
        let decision = AIDecision(
            decision: "Answered call",
            reasoning: "Call met screening criteria",
            confidence: 0.8
        )
        updatedCall.aiDecisions.append(decision)
        currentCall = updatedCall
    }

    /// Generate contextual greeting
    private func generateGreeting(for callRecord: CallRecord) -> String {
        let personality = agentConfig.profile.personality
        let timeOfDay = getTimeOfDay()

        switch personality {
        case .professional:
            return "Good \(timeOfDay). This is \(agentConfig.profile.name), an AI assistant. How may I help you?"
        case .friendly:
            return "Hi there! This is \(agentConfig.profile.name), an AI assistant. How can I help you today?"
        case .formal:
            return "Good \(timeOfDay). You have reached the AI assistant \(agentConfig.profile.name). How may I be of service?"
        case .casual:
            return "Hey! \(agentConfig.profile.name) here. What's up?"
        case .humorous:
            return "Hello! You've reached \(agentConfig.profile.name), your friendly neighborhood AI. What can I do for you?"
        case .sympathetic:
            return "Hello, this is \(agentConfig.profile.name). I'm here to help you. What's going on?"
        }
    }

    /// Start listening for speech
    func startListening() {
        guard !isListening, hasPermissions else {
            print("Cannot start listening - no permissions or already listening")
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }

        do {
            // Stop any existing recognition
            stopListening()

            // Configure recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true

            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Start audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            // Start recognition
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result = result {
                        self?.currentTranscript = result.bestTranscription.formattedString
                        self?.processUserSpeech(result.bestTranscription.formattedString)
                    }

                    if error != nil {
                        print("Speech recognition error: \(error?.localizedDescription ?? "Unknown")")
                        self?.stopListening()
                    }
                }
            }

            isListening = true
            print("Started listening for speech")
        } catch {
            print("Could not start speech recognition: \(error)")
        }
    }

    /// Stop listening for speech
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    /// Process user speech and generate response
    private func processUserSpeech(_ transcript: String) {
        // Add to conversation history
        conversationHistory.append(ConversationMessage(
            speaker: .caller,
            message: transcript,
            timestamp: Date()
        ))

        // Generate AI response
        Task {
            let response = await generateAIResponse(to: transcript)
            await MainActor.run {
                agentResponse = response
                speak(response)

                // Add AI response to conversation history
                conversationHistory.append(ConversationMessage(
                    speaker: .agent,
                    message: response,
                    timestamp: Date()
                ))

                // Update call record
                if var call = currentCall {
                    call.transcript = conversationHistory.map { "\($0.speaker.rawValue): \($0.message)" }.joined(separator: "\n")
                    currentCall = call
                }
            }
        }
    }

    /// Generate AI response using configured personality and context
    private func generateAIResponse(to userMessage: String) async -> String {
        let systemPrompt = agentConfig.profile.personality.systemPrompt
        let knowledge = agentConfig.profile.knowledge
        let behaviorRules = agentConfig.profile.behaviorRules

        // Simple response generation (would be enhanced with actual AI API)
        if userMessage.lowercased().contains("who are you") {
            return "I'm \(agentConfig.profile.name), an AI assistant handling calls. How can I help you today?"
        } else if userMessage.lowercased().contains("emergency") {
            return "I understand this is urgent. Let me connect you to the appropriate person right away."
        } else if userMessage.lowercased().contains("leave a message") {
            return "Of course! Please go ahead and leave your message. I'll make sure it gets delivered."
        } else if userMessage.lowercased().contains("call back") {
            return "I'll make sure to pass along your callback request. What's the best number to reach you?"
        } else {
            return "I understand. Let me help you with that."
        }
    }

    /// Speak text using configured voice settings
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)

        // Apply voice settings
        utterance.rate = agentConfig.profile.voiceSettings.rate
        utterance.pitchMultiplier = agentConfig.profile.voiceSettings.pitch
        utterance.volume = agentConfig.profile.voiceSettings.volume

        // Select voice based on gender and accent
        let voiceIdentifier = getVoiceIdentifier(
            gender: agentConfig.profile.voiceSettings.gender,
            accent: agentConfig.profile.voiceSettings.accent
        )

        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    /// Get voice identifier based on settings
    private func getVoiceIdentifier(gender: VoiceSettings.VoiceGender, accent: VoiceSettings.VoiceAccent) -> String {
        // Default to English US voices
        switch (gender, accent) {
        case (.female, .american):
            return "com.apple.ttsbundle.Samantha-compact"
        case (.male, .american):
            return "com.apple.ttsbundle.Alex-compact"
        case (.female, .british):
            return "com.apple.ttsbundle.Kate-compact"
        case (.male, .british):
            return "com.apple.ttsbundle.Daniel-compact"
        default:
            return "com.apple.ttsbundle.Samantha-compact"
        }
    }

    /// End current call
    func endCall() {
        if var call = currentCall {
            call.endTime = Date()
            call.status = .ended
            call.duration = call.endTime?.timeIntervalSince(call.startTime)
            callHistory.append(call)
        }

        stopListening()
        conversationHistory.removeAll()
        currentCall = nil
        currentTranscript = ""
        agentResponse = ""
    }

    /// Update agent configuration
    func updateConfig(_ config: AIAgentConfig) {
        agentConfig = config
    }

    // MARK: - Private Helpers

    private func getTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "morning"
        case 12..<17:
            return "afternoon"
        case 17..<21:
            return "evening"
        default:
            return "evening"
        }
    }

    private func requestPermissions() async -> Bool {
        // Request speech recognition permission
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        // Request microphone permission
        let micAuthorized = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let allAuthorized = speechAuthorized && micAuthorized
        print("Permissions - Speech: \(speechAuthorized), Mic: \(micAuthorized), All: \(allAuthorized)")
        return allAuthorized
    }

    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer = speechRecognizer else {
            print("Speech recognizer could not be created")
            return
        }

        guard recognizer.isAvailable else {
            print("Speech recognizer is not available")
            return
        }

        print("Speech recognizer setup completed")
    }
}


// MARK: - Supporting Types

enum Speaker: String, Codable {
    case caller = "Caller"
    case agent = "AI Agent"
}

struct ConversationMessage: Codable {
    let speaker: Speaker
    let message: String
    let timestamp: Date
}

/// AI Decision Engine for call handling logic
class AIDecisionEngine {

    func shouldAnswerCall(from number: String, config: AIAgentConfig, callHistory: [CallRecord]) -> Bool {
        switch config.callHandlingMode {
        case .disabled:
            return false
        case .emergency:
            return isEmergencyNumber(number)
        case .screenAll:
            return true
        case .screenUnknown:
            return !config.whitelistedNumbers.contains(number)
        case .screenWhitelist:
            return !config.whitelistedNumbers.contains(number)
        }
    }

    private func isEmergencyNumber(_ number: String) -> Bool {
        let emergencyNumbers = ["911", "999", "112", "000"]
        return emergencyNumbers.contains(number)
    }

    func analyzeCallPriority(from number: String, callHistory: [CallRecord]) -> Int {
        // Analyze call frequency, time of day, etc.
        let recentCalls = callHistory.filter { $0.callerNumber == number && $0.startTime > Date().addingTimeInterval(-86400) }

        if recentCalls.count > 3 {
            return 5 // High priority - multiple calls
        } else if recentCalls.count > 1 {
            return 3 // Medium priority
        } else {
            return 1 // Low priority
        }
    }

    func shouldTransferCall(transcript: String) -> Bool {
        let transferKeywords = ["emergency", "urgent", "important", "speak to", "transfer"]
        return transferKeywords.contains { transcript.lowercased().contains($0) }
    }
}
