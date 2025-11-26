//
//  TriggerWordDetector.swift
//  discreetly
//
//  Service for detecting voice trigger words using Speech Recognition
//

import Foundation
import Speech
import AVFoundation
import Combine
import UIKit

final class TriggerWordDetector: NSObject, ObservableObject {
    static let shared = TriggerWordDetector()

    @Published var isListening = false
    @Published var lastDetectedWord: String?
    @Published var lastDetectionTime: Date?

    private var audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var audioSession = AVAudioSession.sharedInstance()
    private var inputNode: AVAudioInputNode?
    private var hasTapInstalled = false

    private var activeActions: [ActionConfig] = []
    private var cancellables = Set<AnyCancellable>()

    // Restart loop prevention
    private var restartCount = 0
    private var lastRestartTime: Date?
    private let maxRestartAttempts = 5
    private let restartCooldownPeriod: TimeInterval = 10.0 // 10 seconds

    var onTriggerWordDetected: ((String, ActionConfig) -> Void)?

    override init() {
        super.init()
        setupAudioSession()
    }

    deinit {
        stopListening()
    }

    // MARK: - Setup

    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Public Methods

    func startListening(for actions: [ActionConfig]) {
        print("🎤 [SPEECH DEBUG] startListening called with \(actions.count) actions")

        guard !isListening else {
            print("🎤 [SPEECH DEBUG] Already listening for trigger words - skipping")
            return
        }

        guard !actions.isEmpty else {
            print("❌ [SPEECH DEBUG] No voice trigger actions provided")
            return
        }

        // Check permissions
        print("🎤 [SPEECH DEBUG] Checking permissions...")
        guard checkPermissions() else {
            print("❌ [SPEECH DEBUG] Speech recognition or microphone permissions not granted")
            logPermissionStatus()
            return
        }
        print("✅ [SPEECH DEBUG] Permissions are granted")

        activeActions = actions.filter { $0.triggerType == .voiceTriggerWord && $0.isEnabled }
        print("🎤 [SPEECH DEBUG] Filtered to \(activeActions.count) voice trigger actions:")
        for (index, action) in activeActions.enumerated() {
            print("  \(index + 1). '\(action.voiceTriggerWord ?? "nil")' -> \(action.name)")
        }

        guard !activeActions.isEmpty else {
            print("❌ [SPEECH DEBUG] No enabled voice trigger actions found")
            return
        }

        let triggerWords = activeActions.compactMap { $0.voiceTriggerWord }.joined(separator: ", ")
        print("🎤 [SPEECH DEBUG] Starting voice detection for trigger words: [\(triggerWords)]")

        do {
            try startSpeechRecognition()
            isListening = true
            // Reset restart counter on successful start
            restartCount = 0
            lastRestartTime = nil
            print("✅ [SPEECH DEBUG] Voice trigger detection started successfully (restart counter reset)")
        } catch {
            print("❌ [SPEECH DEBUG] Failed to start speech recognition: \(error)")
            print("❌ [SPEECH DEBUG] Error details: \(error.localizedDescription)")
        }
    }

    func stopListening() {
        print("🛑 [SPEECH DEBUG] stopListening called, isListening: \(isListening)")
        guard isListening else {
            print("🛑 [SPEECH DEBUG] Not currently listening - skipping stop")
            return
        }

        print("🛑 [SPEECH DEBUG] Stopping voice trigger detection...")

        // Clean up current recognition
        cleanupCurrentRecognition()

        // Update state
        isListening = false
        activeActions = []

        // Reset restart tracking
        restartCount = 0
        lastRestartTime = nil

        print("✅ [SPEECH DEBUG] Voice trigger detection stopped completely (restart counter reset)")
    }

    // MARK: - Private Methods

    private func checkPermissions() -> Bool {
        print("🔍 [SPEECH DEBUG] Checking permissions...")

        // Check speech recognition permission
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        print("🔍 [SPEECH DEBUG] Speech recognition status: \(speechStatus)")
        guard speechStatus == .authorized else {
            print("❌ [SPEECH DEBUG] Speech recognition not authorized: \(speechStatus)")
            return false
        }

        // Check microphone permission
        let audioStatus = audioSession.recordPermission
        print("🔍 [SPEECH DEBUG] Microphone permission status: \(audioStatus)")
        guard audioStatus == .granted else {
            print("❌ [SPEECH DEBUG] Microphone permission not granted: \(audioStatus)")
            return false
        }

        print("✅ [SPEECH DEBUG] All permissions are granted")
        return true
    }

    private func logPermissionStatus() {
        print("📊 [SPEECH DEBUG] Current permission status:")
        print("  Speech Recognition: \(SFSpeechRecognizer.authorizationStatus())")
        print("  Microphone: \(audioSession.recordPermission)")
        print("  Speech Recognizer Available: \(speechRecognizer?.isAvailable ?? false)")
        print("  Current Locale: \(speechRecognizer?.locale.identifier ?? "unknown")")
    }

    private func startSpeechRecognition() throws {
        print("🔧 [SPEECH DEBUG] Starting speech recognition setup...")

        // Make sure we clean up any existing setup first
        print("🔧 [SPEECH DEBUG] Cleaning up any existing recognition...")
        cleanupCurrentRecognition()

        // Create recognition request
        print("🔧 [SPEECH DEBUG] Creating speech recognition request...")
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("❌ [SPEECH DEBUG] Failed to create recognition request")
            throw TriggerWordError.recognitionRequestFailed
        }
        print("✅ [SPEECH DEBUG] Recognition request created")

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true // For privacy
        print("🔧 [SPEECH DEBUG] Recognition request configured - partial results: true, on-device: true")

        // Get audio input node
        print("🔧 [SPEECH DEBUG] Getting audio input node...")
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            print("❌ [SPEECH DEBUG] Audio input node not available")
            throw TriggerWordError.audioInputNotAvailable
        }
        print("✅ [SPEECH DEBUG] Audio input node obtained")

        // Start recognition task
        print("🔧 [SPEECH DEBUG] Starting recognition task...")
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error)
        }

        guard recognitionTask != nil else {
            print("❌ [SPEECH DEBUG] Failed to create recognition task")
            throw TriggerWordError.speechRecognizerUnavailable
        }
        print("✅ [SPEECH DEBUG] Recognition task created")

        // Configure audio format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("🔧 [SPEECH DEBUG] Audio format: \(recordingFormat)")

        // Only install tap if we don't already have one
        if !hasTapInstalled {
            print("🔧 [SPEECH DEBUG] Installing audio tap...")
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
                recognitionRequest.append(buffer)
            }
            hasTapInstalled = true
            print("✅ [SPEECH DEBUG] Audio tap installed")
        } else {
            print("⚠️ [SPEECH DEBUG] Audio tap already installed, skipping")
        }

        // Start audio engine
        print("🔧 [SPEECH DEBUG] Preparing and starting audio engine...")
        audioEngine.prepare()

        if !audioEngine.isRunning {
            try audioEngine.start()
            print("✅ [SPEECH DEBUG] Audio engine started successfully")
        } else {
            print("⚠️ [SPEECH DEBUG] Audio engine already running")
        }

        print("🎤 [SPEECH DEBUG] Speech recognition is now active and listening...")
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        print("📝 [SPEECH DEBUG] handleRecognitionResult called")

        // Check if we still have active trigger words
        if activeActions.isEmpty || activeActions.filter({ $0.triggerType == .voiceTriggerWord && $0.isEnabled }).isEmpty {
            print("❌ [SPEECH DEBUG] No active voice trigger words - stopping speech recognition")
            DispatchQueue.main.async { [weak self] in
                self?.stopListening()
            }
            return
        }

        if let error = error {
            print("❌ [SPEECH DEBUG] Speech recognition error: \(error)")
            print("❌ [SPEECH DEBUG] Error type: \(type(of: error))")
            print("❌ [SPEECH DEBUG] Error description: \(error.localizedDescription)")

            // Check if we should restart recognition after error
            if shouldAttemptRestart() {
                print("🔄 [SPEECH DEBUG] Scheduling recognition restart in 1 second...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    if self?.isListening == true {
                        print("🔄 [SPEECH DEBUG] Restarting recognition after error...")
                        self?.restartRecognition()
                    } else {
                        print("🔄 [SPEECH DEBUG] Not restarting - no longer listening")
                    }
                }
            } else {
                print("❌ [SPEECH DEBUG] Too many restart attempts, stopping speech recognition")
                DispatchQueue.main.async { [weak self] in
                    self?.stopListening()
                }
            }
            return
        }

        guard let result = result else {
            print("⚠️ [SPEECH DEBUG] No result and no error - this is unusual")
            return
        }

        let transcription = result.bestTranscription.formattedString.lowercased()
        let confidence = result.bestTranscription.segments.last?.confidence ?? 0.0

        print("🎯 [SPEECH DEBUG] Recognition result:")
        print("  Transcription: '\(transcription)'")
        print("  Confidence: \(confidence)")
        print("  Is Final: \(result.isFinal)")
        print("  Alternative count: \(result.transcriptions.count)")

        // Check for trigger words in the transcription
        checkForTriggerWords(in: transcription)

        // If the result is final and we're still listening, restart recognition
        if result.isFinal && isListening {
            if shouldAttemptRestart() {
                print("🔄 [SPEECH DEBUG] Final result received, scheduling restart in 0.5 seconds...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    if self?.isListening == true {
                        print("🔄 [SPEECH DEBUG] Restarting recognition after final result...")
                        self?.restartRecognition()
                    } else {
                        print("🔄 [SPEECH DEBUG] Not restarting - no longer listening")
                    }
                }
            } else {
                print("❌ [SPEECH DEBUG] Too many restart attempts, stopping speech recognition")
                DispatchQueue.main.async { [weak self] in
                    self?.stopListening()
                }
            }
        }
    }

    private func checkForTriggerWords(in transcription: String) {
        print("🔍 [SPEECH DEBUG] Checking for trigger words in: '\(transcription)'")
        print("🔍 [SPEECH DEBUG] Active trigger words: [\(activeActions.compactMap { $0.voiceTriggerWord }.joined(separator: ", "))]")

        for (index, action) in activeActions.enumerated() {
            guard let triggerWord = action.voiceTriggerWord?.lowercased() else {
                print("⚠️ [SPEECH DEBUG] Action \(index) has no trigger word")
                continue
            }

            print("🔍 [SPEECH DEBUG] Checking trigger word '\(triggerWord)' against transcription...")

            // Check if the trigger word is in the transcription
            if transcription.contains(triggerWord) {
                print("🎯 [SPEECH DEBUG] MATCH FOUND! Trigger word '\(triggerWord)' detected in transcription")
                handleTriggerWordDetected(word: triggerWord, action: action)
                break // Only trigger one action at a time
            } else {
                print("🔍 [SPEECH DEBUG] No match for '\(triggerWord)'")
            }
        }
        print("🔍 [SPEECH DEBUG] Trigger word check complete")
    }

    private func handleTriggerWordDetected(word: String, action: ActionConfig) {
        print("🚨 [SPEECH DEBUG] handleTriggerWordDetected called with word: '\(word)', action: '\(action.name)'")

        // Prevent multiple detections of the same word within a short time
        if let lastTime = lastDetectionTime {
            let timeSinceLastDetection = Date().timeIntervalSince(lastTime)
            print("🚨 [SPEECH DEBUG] Time since last detection: \(timeSinceLastDetection) seconds")
            if timeSinceLastDetection < 3.0 {
                print("🔄 [SPEECH DEBUG] Ignoring duplicate trigger word detection (cooldown: 3s)")
                return
            }
        } else {
            print("🚨 [SPEECH DEBUG] This is the first trigger word detection")
        }

        print("🎯 [SPEECH DEBUG] TRIGGER WORD DETECTED: '\(word)' -> Action: \(action.name)")

        lastDetectedWord = word
        lastDetectionTime = Date()

        // Provide haptic feedback
        print("📳 [SPEECH DEBUG] Providing haptic feedback...")
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }

        // Execute the trigger callback
        print("🎬 [SPEECH DEBUG] Executing trigger callback...")
        onTriggerWordDetected?(word, action)
        print("✅ [SPEECH DEBUG] Trigger word handling complete")
    }

    private func shouldAttemptRestart() -> Bool {
        // First check if we have any active trigger words - don't restart if none
        if activeActions.isEmpty {
            print("❌ [SPEECH DEBUG] No active trigger words - not attempting restart")
            return false
        }

        let enabledVoiceActions = activeActions.filter { $0.triggerType == .voiceTriggerWord && $0.isEnabled }
        if enabledVoiceActions.isEmpty {
            print("❌ [SPEECH DEBUG] No enabled voice trigger actions - not attempting restart")
            return false
        }

        let now = Date()

        // Check if we're within the cooldown period
        if let lastRestart = lastRestartTime {
            let timeSinceLastRestart = now.timeIntervalSince(lastRestart)
            if timeSinceLastRestart < restartCooldownPeriod {
                print("🔄 [SPEECH DEBUG] Restart attempt \(restartCount + 1)/\(maxRestartAttempts)")
                if restartCount >= maxRestartAttempts {
                    print("❌ [SPEECH DEBUG] Max restart attempts (\(maxRestartAttempts)) reached within cooldown period")
                    return false
                }
            } else {
                // Reset counter if enough time has passed
                print("🔄 [SPEECH DEBUG] Cooldown period expired, resetting restart counter")
                restartCount = 0
            }
        }

        // Check if we haven't exceeded max attempts
        return restartCount < maxRestartAttempts
    }

    private func restartRecognition() {
        print("🔄 [SPEECH DEBUG] restartRecognition called, isListening: \(isListening)")
        guard isListening else {
            print("🔄 [SPEECH DEBUG] Not listening - skipping restart")
            return
        }

        // Update restart tracking
        restartCount += 1
        lastRestartTime = Date()
        print("🔄 [SPEECH DEBUG] Restarting speech recognition... (attempt \(restartCount)/\(maxRestartAttempts))")

        // Clean up current recognition completely
        cleanupCurrentRecognition()

        // Start new recognition after a brief delay
        print("🔄 [SPEECH DEBUG] Scheduling restart in 0.1 seconds...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            print("🔄 [SPEECH DEBUG] Attempting to restart speech recognition...")
            do {
                try self?.startSpeechRecognition()
                print("✅ [SPEECH DEBUG] Speech recognition restarted successfully")
            } catch {
                print("❌ [SPEECH DEBUG] Failed to restart speech recognition: \(error)")
                print("❌ [SPEECH DEBUG] Error details: \(error.localizedDescription)")

                // Check if we should try again
                if let strongSelf = self, strongSelf.shouldAttemptRestart() {
                    print("🔄 [SPEECH DEBUG] Will try restart again after error...")
                } else {
                    print("❌ [SPEECH DEBUG] Max restart attempts reached, stopping listening")
                    self?.isListening = false
                }
            }
        }
    }

    private func cleanupCurrentRecognition() {
        print("🧹 [SPEECH DEBUG] Cleaning up current recognition...")

        // Stop audio engine first
        if audioEngine.isRunning {
            print("🧹 [SPEECH DEBUG] Stopping audio engine...")
            audioEngine.stop()
        }

        // Remove audio tap safely
        if let inputNode = inputNode, hasTapInstalled {
            print("🧹 [SPEECH DEBUG] Removing audio tap...")
            inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }

        // End recognition request
        if let recognitionRequest = recognitionRequest {
            print("🧹 [SPEECH DEBUG] Ending recognition request...")
            recognitionRequest.endAudio()
        }

        // Cancel recognition task
        if let recognitionTask = recognitionTask {
            print("🧹 [SPEECH DEBUG] Cancelling recognition task...")
            recognitionTask.cancel()
        }

        // Clear references
        recognitionRequest = nil
        recognitionTask = nil
        inputNode = nil

        print("🧹 [SPEECH DEBUG] Cleanup complete")
    }

    // MARK: - Permission Requests

    func requestPermissions() async -> Bool {
        print("🔐 [SPEECH DEBUG] requestPermissions called")

        // Request speech recognition permission
        print("🔐 [SPEECH DEBUG] Requesting speech recognition permission...")
        let speechPermission = await requestSpeechPermission()
        print("🔐 [SPEECH DEBUG] Speech recognition permission result: \(speechPermission)")

        // Request microphone permission
        print("🔐 [SPEECH DEBUG] Requesting microphone permission...")
        let microphonePermission = await requestMicrophonePermission()
        print("🔐 [SPEECH DEBUG] Microphone permission result: \(microphonePermission)")

        let allGranted = speechPermission && microphonePermission
        print("🔐 [SPEECH DEBUG] All permissions granted: \(allGranted)")

        return allGranted
    }

    private func requestSpeechPermission() async -> Bool {
        print("🗣️ [SPEECH DEBUG] Requesting speech recognition authorization...")
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    let granted = status == .authorized
                    print("🗣️ [SPEECH DEBUG] Speech recognition authorization status: \(status)")
                    print("🗣️ [SPEECH DEBUG] Speech recognition permission: \(granted ? "Granted" : "Denied")")
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        print("🎤 [SPEECH DEBUG] Requesting microphone record permission...")
        return await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    print("🎤 [SPEECH DEBUG] Microphone permission: \(granted ? "Granted" : "Denied")")
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

// MARK: - Error Types

enum TriggerWordError: Error {
    case recognitionRequestFailed
    case audioInputNotAvailable
    case permissionDenied
    case speechRecognizerUnavailable

    var localizedDescription: String {
        switch self {
        case .recognitionRequestFailed:
            return "Failed to create speech recognition request"
        case .audioInputNotAvailable:
            return "Audio input not available"
        case .permissionDenied:
            return "Speech recognition or microphone permission denied"
        case .speechRecognizerUnavailable:
            return "Speech recognizer not available for current locale"
        }
    }
}

// MARK: - Configuration Helper

extension TriggerWordDetector {

    /// Get recommended trigger words for emergency situations
    static func getRecommendedTriggerWords() -> [String] {
        return [
            "help",
            "emergency",
            "panic",
            "distress",
            "danger",
            "assist",
            "alert",
            "rescue"
        ]
    }

    /// Validate a trigger word
    static func isValidTriggerWord(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count >= 2 && trimmed.count <= 20
    }

    /// Get explanation for voice trigger setup
    static var setupExplanation: String {
        return """
        Voice triggers allow hands-free activation of actions.

        • Speak clearly and loudly
        • Choose distinctive words
        • Avoid common words to prevent false triggers
        • Works best in quiet environments
        • Keep your device nearby

        Privacy: All speech processing happens on-device.
        """
    }

    /// Debug method to log current state
    func logCurrentState() {
        print("📊 [SPEECH DEBUG] === CURRENT STATE ===")
        print("📊 [SPEECH DEBUG] Is Listening: \(isListening)")
        print("📊 [SPEECH DEBUG] Active Actions Count: \(activeActions.count)")
        print("📊 [SPEECH DEBUG] Last Detected Word: \(lastDetectedWord ?? "none")")
        print("📊 [SPEECH DEBUG] Last Detection Time: \(lastDetectionTime?.description ?? "none")")
        print("📊 [SPEECH DEBUG] Audio Engine Running: \(audioEngine.isRunning)")
        print("📊 [SPEECH DEBUG] Recognition Task State: \(recognitionTask?.state.rawValue ?? -1)")
        print("📊 [SPEECH DEBUG] Speech Recognizer Available: \(speechRecognizer?.isAvailable ?? false)")
        print("📊 [SPEECH DEBUG] Restart Count: \(restartCount)/\(maxRestartAttempts)")
        print("📊 [SPEECH DEBUG] Last Restart Time: \(lastRestartTime?.description ?? "none")")
        logPermissionStatus()
        print("📊 [SPEECH DEBUG] Active Trigger Words:")
        for (index, action) in activeActions.enumerated() {
            print("📊 [SPEECH DEBUG]   \(index + 1). '\(action.voiceTriggerWord ?? "nil")' -> \(action.name)")
        }
        print("📊 [SPEECH DEBUG] ==================")
    }
}
