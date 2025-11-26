//
//  Models.swift
//  discreetly
//
//  Data models for action-based features
//

import Foundation
import CoreLocation
import UIKit

// MARK: - Contact Model
struct EmergencyContact: Codable, Identifiable {
    let id: UUID
    var name: String
    var phoneNumber: String
    var relationship: String?
    var isPrimary: Bool

    init(id: UUID = UUID(), name: String, phoneNumber: String, relationship: String? = nil, isPrimary: Bool = false) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.relationship = relationship
        self.isPrimary = isPrimary
    }
}

// MARK: - Action Configuration
enum ActionType: String, Codable, CaseIterable {
    case distressCall = "Distress Call"
    case textMessage = "Text Message"
    case ask = "Ask Claude AI"
    case covertCall = "Covert Call"
}

enum TriggerType: String, Codable {
    case actionButton = "Action Button"
    case voiceTriggerWord = "Voice Trigger Word"
    case waitForMovement = "Wait for Movement"
    case delay = "Delay"
    case respiratoryRate = "Respiratory Rate"
    case heartRateVariability = "Heart Rate Variability"
}

enum HealthOperator: String, Codable, CaseIterable {
    case greaterThan = ">"
    case lessThan = "<"
    case greaterThanOrEqual = ">="
    case lessThanOrEqual = "<="
    case equals = "="
}

struct ActionConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var actionType: ActionType
    var triggerType: TriggerType
    var voiceTriggerWord: String?
    var contacts: [UUID] // Contact IDs - mutable so we can add contacts
    var message: String?
    var includeLocation: Bool
    var includeDynamicInfo: Bool // timestamp, battery, etc.
    var isEnabled: Bool

    // Health trigger settings
    var respiratoryRateThreshold: Double? // breaths per minute
    var respiratoryRateOperator: HealthOperator?
    var hrvThreshold: Double? // milliseconds
    var hrvOperator: HealthOperator?
    
    // Delayed trigger settings
    var delayDuration: TimeInterval? // delay in seconds
    var delayUnit: String? // "seconds", "minutes", "hours"

    init(
        id: UUID = UUID(),
        name: String,
        actionType: ActionType,
        triggerType: TriggerType,
        voiceTriggerWord: String? = nil,
        contacts: [UUID] = [],
        message: String? = nil,
        includeLocation: Bool = true,
        includeDynamicInfo: Bool = true,
        isEnabled: Bool = true,
        respiratoryRateThreshold: Double? = nil,
        respiratoryRateOperator: HealthOperator? = nil,
        hrvThreshold: Double? = nil,
        hrvOperator: HealthOperator? = nil,
        delayDuration: TimeInterval? = nil,
        delayUnit: String? = nil
    ) {
        self.id = id
        self.name = name
        self.actionType = actionType
        self.triggerType = triggerType
        self.voiceTriggerWord = voiceTriggerWord
        self.contacts = contacts
        self.message = message
        // For distress calls, always include location and dynamic info
        self.includeLocation = actionType == .distressCall ? true : includeLocation
        self.includeDynamicInfo = actionType == .distressCall ? true : includeDynamicInfo
        self.isEnabled = isEnabled

        // Health trigger settings
        self.respiratoryRateThreshold = respiratoryRateThreshold
        self.respiratoryRateOperator = respiratoryRateOperator
        self.hrvThreshold = hrvThreshold
        self.hrvOperator = hrvOperator
        
        // Delayed trigger settings
        self.delayDuration = delayDuration
        self.delayUnit = delayUnit
    }
}

// MARK: - Dynamic Message Variables
struct DynamicMessageBuilder {
    static func build(template: String, location: CLLocation?, includeDynamicInfo: Bool) -> String {
        var message = template

        if includeDynamicInfo {
            // Add timestamp
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            message = message.replacingOccurrences(of: "{time}", with: "\(formatter.string(from: Date()))")

            // Add battery level
            UIDevice.current.isBatteryMonitoringEnabled = true
            let batteryLevel = Int(UIDevice.current.batteryLevel * 100)
            message = message.replacingOccurrences(of: "{battery}", with: "\(batteryLevel)")
        }

        // Add location
        if let location = location {
            let lat = String(format: "%.2f", location.coordinate.latitude)
            let lon = String(format: "%.2f", location.coordinate.longitude)

            // Create comprehensive location string with both address and coordinates
            var locationString = "\(lat),\(lon)"
            if let locationName = LocationService.shared.currentLocationName, !locationName.isEmpty {
                locationString = "\(locationName) (\(lat),\(lon))"
            }

            message = message.replacingOccurrences(of: "{location}", with: locationString)
            message = message.replacingOccurrences(of: "{latitude}", with: "\n\(lat)")
            message = message.replacingOccurrences(of: "{longitude}", with: "\n\(lon)")
        }

        return message
    }
}

// MARK: - App Mode
enum AppMode: String, Codable {
    case quick = "Quick Mode"
    case advanced = "Advanced Mode"
}

// MARK: - User Settings
struct UserSettings: Codable {
    var appMode: AppMode
    var contacts: [EmergencyContact]
    var actions: [ActionConfig]
    var enableBackgroundMode: Bool
    var enableHapticFeedback: Bool
    var apiKey: String? // For AI services
    var twilioToken: String?
    var twilioAccountSid: String?
    var twilioAuthToken: String?
    var twilioFromNumber: String?
    var enableUltravoxAI: Bool // User preference to enable/disable Ultravox
    var preferredCallMethod: PreferredCallMethod
    var aiAgentConfig: AIAgentConfig
    var callHistory: [CallRecord]
    var userName: String? // User's name for identification in messages and AI prompts
    var enableNeighborhoodSafetyMonitoring: Bool // Enable automatic neighborhood safety monitoring

    init() {
        self.appMode = .quick
        self.contacts = []
        self.actions = []
        self.enableBackgroundMode = false
        self.enableHapticFeedback = true
        self.apiKey = nil
        self.twilioToken = nil
        self.twilioAccountSid = "AC1adde8ae2e8d4e3891e51613615a6ebe"
        self.twilioAuthToken = "7e5cd223c91d20c285a912e459a0cd37"
        self.twilioFromNumber = "+14257932188"
        self.enableUltravoxAI = true // Default to enabled
        self.preferredCallMethod = .automatic
        self.aiAgentConfig = AIAgentConfig()
        self.callHistory = []
        self.userName = nil
        self.enableNeighborhoodSafetyMonitoring = true // Default to enabled for safety
    }
}

enum PreferredCallMethod: String, Codable, CaseIterable {
    case automatic = "Automatic"
    case ultravoxOnly = "Ultravox AI Only"
    case twilioOnly = "Twilio Only"

    var description: String {
        switch self {
        case .automatic:
            return "Choose best method automatically"
        case .ultravoxOnly:
            return "Always use Ultravox AI"
        case .twilioOnly:
            return "Always use traditional calling"
        }
    }
}

// MARK: - Branched Logic System (Action-based)

/// Condition types for branched logic
enum ConditionType: String, Codable, CaseIterable {
    case timeOfDay = "Time of Day"
    case batteryLevel = "Battery Level"
    case location = "Location Area"
    case userInput = "User Input"
    case callResponse = "Call Response"
    case smsResponse = "SMS Response"
    case emergencyLevel = "Emergency Level"
}

/// Operators for condition evaluation
enum ConditionOperator: String, Codable, CaseIterable {
    case equals = "equals"
    case notEquals = "not equals"
    case greaterThan = "greater than"
    case lessThan = "less than"
    case contains = "contains"
    case between = "between"
    case isWithin = "is within"
}

/// Individual condition for branched logic
struct ActionCondition: Codable, Identifiable {
    let id = UUID()
    var type: ConditionType
    var conditionOperator: ConditionOperator
    var value: String
    var secondValue: String? // For "between" operations

    func evaluate(context: ActionContext) -> Bool {
        switch type {
        case .timeOfDay:
            return evaluateTimeCondition(context: context)
        case .batteryLevel:
            return evaluateBatteryCondition(context: context)
        case .location:
            return evaluateLocationCondition(context: context)
        case .userInput:
            return evaluateUserInputCondition(context: context)
        case .callResponse:
            return evaluateCallResponseCondition(context: context)
        case .smsResponse:
            return evaluateSMSResponseCondition(context: context)
        case .emergencyLevel:
            return evaluateEmergencyLevelCondition(context: context)
        }
    }

    private func evaluateTimeCondition(context: ActionContext) -> Bool {
        let currentHour = Calendar.current.component(.hour, from: Date())

        if let hour = Int(value) {
            switch conditionOperator {
            case .equals:
                return currentHour == hour
            case .greaterThan:
                return currentHour > hour
            case .lessThan:
                return currentHour < hour
            case .between:
                if let secondHour = Int(secondValue ?? "0") {
                    return currentHour >= hour && currentHour <= secondHour
                }
                return false
            default:
                return false
            }
        }
        return false
    }

    private func evaluateBatteryCondition(context: ActionContext) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = Int(UIDevice.current.batteryLevel * 100)

        if let targetLevel = Int(value) {
            switch conditionOperator {
            case .equals:
                return batteryLevel == targetLevel
            case .greaterThan:
                return batteryLevel > targetLevel
            case .lessThan:
                return batteryLevel < targetLevel
            case .between:
                if let secondLevel = Int(secondValue ?? "0") {
                    return batteryLevel >= targetLevel && batteryLevel <= secondLevel
                }
                return false
            default:
                return false
            }
        }
        return false
    }

    private func evaluateLocationCondition(context: ActionContext) -> Bool {
        // Location-based conditions (could be enhanced with geofencing)
        return true // Placeholder
    }

    private func evaluateUserInputCondition(context: ActionContext) -> Bool {
        guard let userInput = context.userInput else { return false }

        switch conditionOperator {
        case .equals:
            return userInput.lowercased() == value.lowercased()
        case .contains:
            return userInput.lowercased().contains(value.lowercased())
        default:
            return false
        }
    }

    private func evaluateCallResponseCondition(context: ActionContext) -> Bool {
        guard let callStatus = context.callStatus else { return false }

        switch conditionOperator {
        case .equals:
            return callStatus == value
        default:
            return false
        }
    }

    private func evaluateSMSResponseCondition(context: ActionContext) -> Bool {
        guard let smsResponse = context.smsResponse else { return false }

        switch conditionOperator {
        case .contains:
            return smsResponse.lowercased().contains(value.lowercased())
        case .equals:
            return smsResponse.lowercased() == value.lowercased()
        default:
            return false
        }
    }

    private func evaluateEmergencyLevelCondition(context: ActionContext) -> Bool {
        let currentLevel = context.emergencyLevel

        if let targetLevel = Int(value) {
            switch conditionOperator {
            case .equals:
                return currentLevel == targetLevel
            case .greaterThan:
                return currentLevel > targetLevel
            case .lessThan:
                return currentLevel < targetLevel
            default:
                return false
            }
        }
        return false
    }
}

/// Branch in conditional logic
struct ActionBranch: Codable, Identifiable {
    let id = UUID()
    var name: String
    var conditions: [ActionCondition]
    var logicOperator: LogicOperator // AND/OR for multiple conditions
    var actionId: UUID? // Action to execute if conditions are met
    var nextBranches: [ActionBranch]? // Nested branches

    func shouldExecute(context: ActionContext) -> Bool {
        guard !conditions.isEmpty else { return true }

        let results = conditions.map { $0.evaluate(context: context) }

        switch logicOperator {
        case .and:
            return results.allSatisfy { $0 }
        case .or:
            return results.contains(true)
        }
    }
}

enum LogicOperator: String, Codable, CaseIterable {
    case and = "AND"
    case or = "OR"
}

/// Context for action execution and condition evaluation
struct ActionContext {
    var location: CLLocation?
    var batteryLevel: Int?
    var currentTime: Date
    var userInput: String?
    var callStatus: String?
    var smsResponse: String?
    var emergencyLevel: Int // 1-5 scale
    var previousActions: [String] // History of executed actions

    init() {
        self.currentTime = Date()
        self.emergencyLevel = 1
        self.previousActions = []

        // Auto-populate battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.batteryLevel = Int(UIDevice.current.batteryLevel * 100)
    }
}

/// Enhanced action configuration with branched logic
struct BranchedActionConfig: Codable, Identifiable {
    let id = UUID()
    var name: String
    var description: String?
    var rootAction: ActionConfig
    var branches: [ActionBranch]
    var timeoutSeconds: Int? // Timeout for user input
    var maxRetries: Int
    var isEnabled: Bool

    init(
        name: String,
        description: String? = nil,
        rootAction: ActionConfig,
        branches: [ActionBranch] = [],
        timeoutSeconds: Int? = nil,
        maxRetries: Int = 3,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.description = description
        self.rootAction = rootAction
        self.branches = branches
        self.timeoutSeconds = timeoutSeconds
        self.maxRetries = maxRetries
        self.isEnabled = isEnabled
    }
}

/// Emergency escalation levels (Action-based feature)
enum EmergencyLevel: Int, Codable, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    case extreme = 5

    var description: String {
        switch self {
        case .low: return "Low Priority"
        case .medium: return "Medium Priority"
        case .high: return "High Priority"
        case .critical: return "Critical Emergency"
        case .extreme: return "Extreme Emergency"
        }
    }

    var escalationDelay: TimeInterval {
        switch self {
        case .low: return 300 // 5 minutes
        case .medium: return 180 // 3 minutes
        case .high: return 60 // 1 minute
        case .critical: return 30 // 30 seconds
        case .extreme: return 0 // Immediate
        }
    }
}

// MARK: - AI Agent System (Emergency Response Features)

/// AI Agent personality and behavior configuration
struct AIAgentProfile: Codable, Identifiable, Equatable {
    let id = UUID()
    var name: String
    var personality: AIPersonality
    var voiceSettings: VoiceSettings
    var behaviorRules: [BehaviorRule]
    var knowledge: [KnowledgeEntry]
    var isActive: Bool

    init(name: String = "Assistant", personality: AIPersonality = .professional) {
        self.name = name
        self.personality = personality
        self.voiceSettings = VoiceSettings()
        self.behaviorRules = []
        self.knowledge = []
        self.isActive = true
    }
}

enum AIPersonality: String, Codable, CaseIterable {
    case professional = "Professional"
    case friendly = "Friendly"
    case formal = "Formal"
    case casual = "Casual"
    case humorous = "Humorous"
    case sympathetic = "Sympathetic"

    var systemPrompt: String {
        switch self {
        case .professional:
            return "You are a professional, efficient AI assistant. Be clear, concise, and helpful."
        case .friendly:
            return "You are a warm, friendly AI assistant. Be approachable and conversational."
        case .formal:
            return "You are a formal, courteous AI assistant. Use proper etiquette and respectful language."
        case .casual:
            return "You are a relaxed, casual AI assistant. Be natural and easy-going."
        case .humorous:
            return "You are a witty, lighthearted AI assistant. Add appropriate humor when suitable."
        case .sympathetic:
            return "You are an empathetic, understanding AI assistant. Be caring and supportive."
        }
    }
}

struct VoiceSettings: Codable, Equatable {
    var pitch: Float = 1.0
    var rate: Float = 0.5
    var volume: Float = 1.0
    var accent: VoiceAccent = .american
    var gender: VoiceGender = .neutral

    enum VoiceAccent: String, Codable, CaseIterable {
        case american = "American"
        case british = "British"
        case australian = "Australian"
        case canadian = "Canadian"
    }

    enum VoiceGender: String, Codable, CaseIterable {
        case male = "Male"
        case female = "Female"
        case neutral = "Neutral"
    }
}

/// Rules governing AI behavior in different situations
struct BehaviorRule: Codable, Identifiable, Equatable {
    let id = UUID()
    var name: String
    var condition: String // Natural language condition
    var action: String // What the AI should do
    var priority: Int // Higher numbers = higher priority
    var isEnabled: Bool = true
}

/// Knowledge entries for the AI agent
struct KnowledgeEntry: Codable, Identifiable, Equatable {
    let id = UUID()
    var topic: String
    var information: String
    var category: KnowledgeCategory
    var isPublic: Bool // Can share with others

    enum KnowledgeCategory: String, Codable, CaseIterable {
        case personal = "Personal Info"
        case work = "Work Related"
        case family = "Family"
        case preferences = "Preferences"
        case schedule = "Schedule"
        case contacts = "Contacts"
        case general = "General Knowledge"
    }
}

/// Call handling modes for the AI agent
enum CallHandlingMode: String, Codable, CaseIterable {
    case screenAll = "Screen All Calls"
    case screenUnknown = "Screen Unknown Numbers"
    case screenWhitelist = "Screen Non-Whitelist"
    case emergency = "Emergency Only"
    case disabled = "Disabled"

    var description: String {
        switch self {
        case .screenAll: return "AI answers all incoming calls"
        case .screenUnknown: return "AI answers calls from unknown numbers"
        case .screenWhitelist: return "AI answers calls not in whitelist"
        case .emergency: return "AI only handles emergency calls"
        case .disabled: return "AI call handling disabled"
        }
    }
}

/// Call status and management
enum CallStatus: String, Codable {
    case incoming = "incoming"
    case answered = "answered"
    case screening = "screening"
    case transferred = "transferred"
    case ended = "ended"
    case recorded = "recorded"
    case transcribed = "transcribed"
}

/// Call record for tracking AI-handled calls
struct CallRecord: Codable, Identifiable {
    let id = UUID()
    var callerNumber: String
    var callerName: String?
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval?
    var status: CallStatus
    var transcript: String?
    var summary: String?
    var recordingURL: URL?
    var aiDecisions: [AIDecision]
    var userNotified: Bool = false

    init(callerNumber: String, callerName: String? = nil) {
        self.callerNumber = callerNumber
        self.callerName = callerName
        self.startTime = Date()
        self.status = .incoming
        self.aiDecisions = []
    }
}

/// AI decision tracking
struct AIDecision: Codable, Identifiable {
    let id = UUID()
    var timestamp: Date
    var decision: String
    var reasoning: String
    var confidence: Float // 0.0 - 1.0

    init(decision: String, reasoning: String, confidence: Float = 1.0) {
        self.timestamp = Date()
        self.decision = decision
        self.reasoning = reasoning
        self.confidence = confidence
    }
}

/// Conversation flow for AI agent
struct ConversationFlow: Codable, Identifiable, Equatable {
    let id = UUID()
    var name: String
    var steps: [ConversationStep]
    var triggerPhrases: [String]
    var isEnabled: Bool = true
}

struct ConversationStep: Codable, Identifiable, Equatable {
    let id = UUID()
    var prompt: String
    var expectedResponses: [String]
    var nextStepId: UUID?
    var actions: [String] // Actions to take after this step
}

/// AI agent configuration combining all settings
struct AIAgentConfig: Codable, Equatable {
    var profile: AIAgentProfile
    var callHandlingMode: CallHandlingMode
    var whitelistedNumbers: [String]
    var blockedNumbers: [String]
    var conversationFlows: [ConversationFlow]
    var autoTranscribe: Bool = true
    var autoSummarize: Bool = true
    var notifyUser: Bool = true
    var maxCallDuration: TimeInterval = 300 // 5 minutes
    var saveRecordings: Bool = false

    init() {
        self.profile = AIAgentProfile()
        self.callHandlingMode = .screenUnknown
        self.whitelistedNumbers = []
        self.blockedNumbers = []
        self.conversationFlows = []
    }
}

