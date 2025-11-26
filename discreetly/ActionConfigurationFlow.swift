//
//  ActionConfigurationFlow.swift
//  discreetly
//
//  Action configuration flow: When I → Do
//

import SwiftUI

struct ActionConfigurationFlow: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: ConfigurationStep = .trigger
    @State private var selectedTriggerType: TriggerType = .actionButton
    @State private var triggerWord: String = ""
    @State private var selectedActionType: ActionType = .distressCall
    @State private var selectedContacts: Set<UUID> = []
    @State private var selectedSingleContact: UUID?
    @State private var showingAddContact = false
    @State private var customMessage = ""

    // Health trigger settings
    @State private var respiratoryRateThreshold: Double = 20.0
    @State private var respiratoryRateOperator: HealthOperator = .greaterThan
    @State private var hrvThreshold: Double = 30.0
    @State private var hrvOperator: HealthOperator = .lessThan

    // Delayed trigger settings
    @State private var delayDuration: TimeInterval = 30.0 // Default 30 seconds
    @State private var delayUnit: DelayUnit = .seconds

    enum DelayUnit: String, CaseIterable {
        case seconds = "Seconds"
        case minutes = "Minutes"
        case hours = "Hours"
        
        var multiplier: TimeInterval {
            switch self {
            case .seconds: return 1
            case .minutes: return 60
            case .hours: return 3600
            }
        }
    }

    enum ConfigurationStep: CaseIterable {
        case trigger, action, aiPrompt, contacts, review

        var title: String {
            switch self {
            case .trigger: return "Choose Trigger Type"
            case .action: return "Choose Action"
            case .aiPrompt: return "AI Prompt"
            case .contacts: return "Add Contacts"
            case .review: return "Review & Save"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                // Progress indicator
                ProgressView(value: Double(currentStep.progressValue), total: 4)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .padding()

                // Step content
                switch currentStep {
                case .trigger:
                    triggerStepView
                case .action:
                    actionStepView
                case .aiPrompt:
                    aiPromptStepView
                case .contacts:
                    contactsStepView
                case .review:
                    reviewStepView
                }

                Spacer()

                // Navigation buttons
                HStack {
                    if currentStep != .trigger {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                goToPreviousStep()
                            }
                        }
                        .foregroundColor(.blue)
                    }

                    Spacer()

                    Button(currentStep == .review ? "Create Action" : "Continue") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if currentStep == .review {
                                createAction()
                            } else {
                                goToNextStep()
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(canProceed ? Color.blue : Color.gray)
                    .cornerRadius(8)
                    .disabled(!canProceed)
                }
                .padding()
            }
            .navigationTitle(currentStep.title)
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
            )
        }
    }

    private var triggerStepView: some View {
        let triggers: [(TriggerType, String, String, String)] = [
            (.actionButton, "button.horizontal", "Action Button", "Press the Action Button on your iPhone for instant activation"),
            (.voiceTriggerWord, "mic.fill", "Voice Command", "Say a custom trigger word for hands-free activation"),
            (.waitForMovement, "figure.walk", "Movement Detection", "Activate when movement unusually changes rapidly"),
            (.delay, "clock", "Timed Delay", "Execute actions after a specified waiting period"),
            (.respiratoryRate, "lungs.fill", "Breathing Monitor", "Activate when breathing rate indicates distress or emergency"),
            (.heartRateVariability, "heart.fill", "Heart Rate Monitor", "Activate when heart rate variability indicates stress or emergency")
        ]

        return VStack(alignment: .leading, spacing: 20) {
            Text("Choose how you want to trigger Actions:")
                .font(.headline)
                .padding(.horizontal)

            List(triggers, id: \.0) { trigger in
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.1))
                            .frame(width: 50, height: 50)

                        Image(systemName: trigger.1)
                            .font(.title2)
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(trigger.2)
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text(trigger.3)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if selectedTriggerType == trigger.0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    } else {
                        Circle()
                            .stroke(.gray, lineWidth: 1)
                            .frame(width: 24, height: 24)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTriggerType = trigger.0
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(PlainListStyle())

            if selectedTriggerType == .voiceTriggerWord {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice Trigger Word")
                        .font(.headline)
                    TextField("Enter trigger word", text: $triggerWord)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("Say this word to activate Actions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            if selectedTriggerType == .respiratoryRate {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Respiratory Rate Trigger")
                        .font(.headline)

                    HStack {
                        Text("Trigger when rate is")
                        Picker("Operator", selection: $respiratoryRateOperator) {
                            ForEach(HealthOperator.allCases, id: \.self) { op in
                                Text(op.rawValue).tag(op)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())

                        TextField("Rate", value: $respiratoryRateThreshold, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.decimalPad)
                            .frame(width: 80)

                        Text("BPM")
                    }

                    Text("Normal: 12-20 BPM. Higher rates may indicate stress or distress.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            if selectedTriggerType == .heartRateVariability {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Heart Rate Variability Trigger")
                        .font(.headline)

                    HStack {
                        Text("Trigger when HRV is")
                        Picker("Operator", selection: $hrvOperator) {
                            ForEach(HealthOperator.allCases, id: \.self) { op in
                                Text(op.rawValue).tag(op)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())

                        TextField("HRV", value: $hrvThreshold, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.decimalPad)
                            .frame(width: 80)

                        Text("ms")
                    }

                    Text("Lower HRV may indicate stress or health issues. Normal: 30-60+ ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            if selectedTriggerType == .delay {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Delay Settings")
                        .font(.headline)

                    HStack {
                        Text("Delay duration:")
                        
                        TextField("Duration", value: $delayDuration, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.decimalPad)
                            .frame(width: 80)

                        Picker("Unit", selection: $delayUnit) {
                            ForEach(DelayUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }

                    Text("The Action will be triggered after the specified delay period.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
    }

    private var actionStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Select the Action type:")
                .font(.headline)
                .padding(.horizontal)

            List(ActionType.allCases, id: \.self) { actionType in
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.red.opacity(0.1))
                            .frame(width: 50, height: 50)

                        Image(systemName: iconForActionType(actionType))
                            .font(.title2)
                            .foregroundColor(.red)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(actionType.rawValue)
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text(descriptionForActionType(actionType))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if selectedActionType == actionType {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    } else {
                        Circle()
                            .stroke(.gray, lineWidth: 1)
                            .frame(width: 24, height: 24)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedActionType = actionType
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(PlainListStyle())
        }
    }

    private var aiPromptStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter your AI prompt:")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt Message")
                    .font(.headline)
                    .foregroundColor(.primary)

                TextField("What would you like to ask the AI?", text: $customMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.done)
                    .onSubmit {
                        // Dismiss keyboard when return is pressed
                        hideKeyboard()
                    }

                Text("Example: What's the weather like? Tell me the latest news. Is the stock market open?")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("How it works:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• When you trigger this Action, you'll be prompted to enter a question")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• The AI Assistant will process your question and provide a response")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Perfect for quick information queries during emergencies")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            Spacer()
        }
    }

    private var contactsStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(selectedActionType == .textMessage ? "Choose emergency contacts:" : "Choose emergency contact:")
                .font(.headline)
                .padding(.horizontal)

            if settingsManager.settings.contacts.isEmpty {
                VStack(spacing: 20) {
                    Text("No contacts available")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Add an emergency contact to continue")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Add Contact") {
                        showingAddContact = true
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding()
            } else {
                // Show selection status
                if selectedActionType == .textMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        if selectedContacts.isEmpty {
                            Text("No contacts selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                            Text("\(selectedContacts.count) contact(s) selected")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if selectedSingleContact == nil {
                            Text("No contact selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else if let contactId = selectedSingleContact,
                                  let contact = settingsManager.settings.contacts.first(where: { $0.id == contactId }) {
                            Text("Selected: \(contact.name)")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal)
                        }
                    }
                }
                
                List(settingsManager.settings.contacts, id: \.id) { contact in
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.green.opacity(0.1))
                                .frame(width: 50, height: 50)

                            Image(systemName: contact.isPrimary ? "person.fill.badge.plus" : "person.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(contact.name)
                                    .font(.headline)
                                    .fontWeight(.semibold)

                                if contact.isPrimary {
                                    Text("PRIMARY")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue)
                                        .cornerRadius(4)
                                }
                            }

                            Text(contact.phoneNumber)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if let relationship = contact.relationship {
                                Text(relationship)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Different selection UI based on action type
                        if selectedActionType == .textMessage {
                            // Multi-select for text messages
                            if selectedContacts.contains(contact.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            } else {
                                Circle()
                                    .stroke(.gray, lineWidth: 1)
                                    .frame(width: 24, height: 24)
                            }
                        } else {
                            // Single-select for other actions
                            if selectedSingleContact == contact.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            } else {
                                Circle()
                                    .stroke(.gray, lineWidth: 1)
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedActionType == .textMessage {
                            // Multi-select logic for text messages
                            if selectedContacts.contains(contact.id) {
                                selectedContacts.remove(contact.id)
                            } else {
                                selectedContacts.insert(contact.id)
                            }
                        } else {
                            // Single-select logic for other actions
                            if selectedSingleContact == contact.id {
                                selectedSingleContact = nil // Deselect if already selected
                            } else {
                                selectedSingleContact = contact.id // Select this contact
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(PlainListStyle())

                Button("Add Another Contact") {
                    showingAddContact = true
                }
                .foregroundColor(.blue)
                .padding(.horizontal)
            }

            Spacer()
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactView { contact in
                settingsManager.addContact(contact)
                if selectedActionType == .textMessage {
                    selectedContacts.insert(contact.id)
                } else {
                    selectedSingleContact = contact.id
                }
            }
        }
    }

    private var reviewStepView: some View {
        VStack(spacing: 30) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 16) {
                Text("Action is Ready!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(selectedActionType == .ask ?
                     "Your AI assistant is ready! When triggered, you'll be able to ask questions and get instant AI responses." :
                     "Your action has been configured successfully. The AI agent will help answer questions when your emergency contact calls.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Configuration Summary
            VStack(alignment: .leading, spacing: 16) {
                ReviewRow(title: "Trigger", value: triggerSummary)
                ReviewRow(title: "Action", value: selectedActionType.rawValue)
                if selectedActionType != .ask {
                    if selectedActionType == .textMessage && !selectedContacts.isEmpty {
                        let contactNames = selectedContacts.compactMap { contactId in
                            settingsManager.settings.contacts.first(where: { $0.id == contactId })?.name
                        }.joined(separator: ", ")
                        ReviewRow(title: "Contacts", value: contactNames)
                    } else if selectedActionType != .textMessage && selectedSingleContact != nil {
                        if let contactId = selectedSingleContact,
                           let contact = settingsManager.settings.contacts.first(where: { $0.id == contactId }) {
                            ReviewRow(title: "Contact", value: contact.name)
                        }
                    }
                }
                if !customMessage.isEmpty {
                    ReviewRow(title: selectedActionType == .ask ? "AI Prompt" : "Message", value: customMessage)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
    }

    // MARK: - Computed Properties

    private var canProceed: Bool {
        switch currentStep {
        case .trigger:
            return selectedTriggerType == .actionButton ||
                   (selectedTriggerType == .voiceTriggerWord && !triggerWord.isEmpty) ||
                   (selectedTriggerType == .delay && delayDuration > 0) ||
                   selectedTriggerType == .waitForMovement ||
                   selectedTriggerType == .respiratoryRate ||
                   selectedTriggerType == .heartRateVariability
        case .action:
            return true // ActionType is always selected
        case .aiPrompt:
            return !customMessage.isEmpty
        case .contacts:
            if selectedActionType == .textMessage {
                return !selectedContacts.isEmpty
            } else {
                return selectedSingleContact != nil
            }
        case .review:
            return true
        }
    }

    private var triggerSummary: String {
        switch selectedTriggerType {
        case .actionButton:
            return "Action Button"
        case .voiceTriggerWord:
            return "Voice: \"\(triggerWord)\""
        case .delay:
            let totalSeconds = delayDuration * delayUnit.multiplier
            if totalSeconds < 60 {
                return "Delay: \(Int(totalSeconds)) seconds"
            } else if totalSeconds < 3600 {
                return "Delay: \(Int(totalSeconds / 60)) minutes"
            } else {
                return "Delay: \(Int(totalSeconds / 3600)) hours"
            }
        case .waitForMovement:
            return "Wait for Movement"
        case .respiratoryRate:
            return "Respiratory Rate \(respiratoryRateOperator.rawValue) \(Int(respiratoryRateThreshold)) BPM"
        case .heartRateVariability:
            return "HRV \(hrvOperator.rawValue) \(String(format: "%.1f", hrvThreshold)) ms"
        }
    }

    // MARK: - Helper Methods

    private func goToNextStep() {
        switch currentStep {
        case .trigger:
            currentStep = .action
        case .action:
            if selectedActionType == .ask {
                currentStep = .aiPrompt
            } else {
                currentStep = .contacts
            }
        case .aiPrompt:
            currentStep = .review
        case .contacts:
            currentStep = .review
        case .review:
            break // Already at the end
        }
    }

    private func goToPreviousStep() {
        switch currentStep {
        case .trigger:
            break // Already at the beginning
        case .action:
            currentStep = .trigger
        case .aiPrompt:
            currentStep = .action
        case .contacts:
            currentStep = .action
        case .review:
            if selectedActionType == .ask {
                currentStep = .aiPrompt
            } else {
                currentStep = .contacts
            }
        }
    }

    private func createAction() {
        let message = customMessage.isEmpty ? defaultMessageForActionType(selectedActionType) : customMessage

        if selectedActionType == .ask {
            // Ask AI actions don't need contacts
            let action = ActionConfig(
                name: selectedActionType.rawValue,
                actionType: selectedActionType,
                triggerType: selectedTriggerType,
                voiceTriggerWord: selectedTriggerType == .voiceTriggerWord ? triggerWord : nil,
                contacts: [],
                message: message,
                includeLocation: false,
                includeDynamicInfo: false,
                isEnabled: true,
                respiratoryRateThreshold: selectedTriggerType == .respiratoryRate ? respiratoryRateThreshold : nil,
                respiratoryRateOperator: selectedTriggerType == .respiratoryRate ? respiratoryRateOperator : nil,
                hrvThreshold: selectedTriggerType == .heartRateVariability ? hrvThreshold : nil,
                hrvOperator: selectedTriggerType == .heartRateVariability ? hrvOperator : nil,
                delayDuration: selectedTriggerType == .delay ? (delayDuration * delayUnit.multiplier) : nil,
                delayUnit: selectedTriggerType == .delay ? delayUnit.rawValue : nil
            )

            settingsManager.addAction(action)
            dismiss()
        } else if selectedActionType == .textMessage {
            // Text message actions support multiple contacts
            guard !selectedContacts.isEmpty else { return }

            // Generate action name based on selected contacts
            let contactNames = selectedContacts.compactMap { contactId in
                settingsManager.settings.contacts.first(where: { $0.id == contactId })?.name
            }.joined(separator: ", ")

            let actionName = if selectedContacts.count == 1 {
                "\(selectedActionType.rawValue) - \(contactNames)"
            } else {
                "\(selectedActionType.rawValue) - \(selectedContacts.count) contacts"
            }

            let action = ActionConfig(
                name: actionName,
                actionType: selectedActionType,
                triggerType: selectedTriggerType,
                voiceTriggerWord: selectedTriggerType == .voiceTriggerWord ? triggerWord : nil,
                contacts: Array(selectedContacts),
                message: message,
                includeLocation: true,
                includeDynamicInfo: true,
                isEnabled: true,
                respiratoryRateThreshold: selectedTriggerType == .respiratoryRate ? respiratoryRateThreshold : nil,
                respiratoryRateOperator: selectedTriggerType == .respiratoryRate ? respiratoryRateOperator : nil,
                hrvThreshold: selectedTriggerType == .heartRateVariability ? hrvThreshold : nil,
                hrvOperator: selectedTriggerType == .heartRateVariability ? hrvOperator : nil,
                delayDuration: selectedTriggerType == .delay ? (delayDuration * delayUnit.multiplier) : nil,
                delayUnit: selectedTriggerType == .delay ? delayUnit.rawValue : nil
            )

            settingsManager.addAction(action)
            dismiss()
        } else {
            // Other actions (distressCall, covertCall) use single contact
            guard let contactId = selectedSingleContact,
                  let contact = settingsManager.settings.contacts.first(where: { $0.id == contactId }) else { return }

            let action = ActionConfig(
                name: "\(selectedActionType.rawValue) - \(contact.name)",
                actionType: selectedActionType,
                triggerType: selectedTriggerType,
                voiceTriggerWord: selectedTriggerType == .voiceTriggerWord ? triggerWord : nil,
                contacts: [contactId],
                message: message,
                includeLocation: true,
                includeDynamicInfo: true,
                isEnabled: true,
                respiratoryRateThreshold: selectedTriggerType == .respiratoryRate ? respiratoryRateThreshold : nil,
                respiratoryRateOperator: selectedTriggerType == .respiratoryRate ? respiratoryRateOperator : nil,
                hrvThreshold: selectedTriggerType == .heartRateVariability ? hrvThreshold : nil,
                hrvOperator: selectedTriggerType == .heartRateVariability ? hrvOperator : nil,
                delayDuration: selectedTriggerType == .delay ? (delayDuration * delayUnit.multiplier) : nil,
                delayUnit: selectedTriggerType == .delay ? delayUnit.rawValue : nil
            )

            settingsManager.addAction(action)
            dismiss()
        }
    }

    private func iconForActionType(_ actionType: ActionType) -> String {
        switch actionType {
        case .distressCall:
            return "phone.fill"
        case .textMessage:
            return "message.fill"
        case .ask:
            return "brain.head.profile"
        case .covertCall:
            return "phone.circle"
        }
    }

    private func descriptionForActionType(_ actionType: ActionType) -> String {
        switch actionType {
        case .distressCall:
            return "Emergency call with AI voice agent that communicates your situation, location, and vitals"
        case .textMessage:
            return "Send emergency text messages to multiple contacts with location and health data"
        case .ask:
            return "Get immediate AI assistance and information to pre-set questions"
        case .covertCall:
            return "Open up a line of communication for covert, non-emergency situations"
        }
    }

    private func defaultMessageForActionType(_ actionType: ActionType) -> String {
        switch actionType {
        case .distressCall:
            return "\nLocation: {location}\nTime: {time}\nBattery: {battery}%"
        case .textMessage:
            return "\nLocation: {location}\nTime: {time}\nBattery: {battery}%"
        case .ask:
            return "Asking Claude AI: Should I proceed with actions based on current situation?"
        case .covertCall:
            return "Initiating discrete emergency response. Location: {location} Time: {time}"
        }
    }
}

extension ActionConfigurationFlow.ConfigurationStep {
    var progressValue: Int {
        switch self {
        case .trigger: return 1
        case .action: return 2
        case .aiPrompt: return 3
        case .contacts: return 3
        case .review: return 4
        }
    }
}

struct ReviewRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    ActionConfigurationFlow()
}

// MARK: - Keyboard Helper
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
