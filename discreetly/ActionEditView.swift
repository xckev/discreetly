//
//  ActionEditView.swift
//  discreetly
//
//  Edit view for modifying existing Action configurations
//

import SwiftUI

struct ActionEditView: View {
    let action: ActionConfig
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var baseName: String // Store the base name without contact
    @State private var name: String
    @State private var triggerType: TriggerType
    @State private var voiceTriggerWord: String
    @State private var selectedContacts: Set<UUID>
    @State private var selectedSingleContact: UUID?
    @State private var message: String
    @State private var includeLocation: Bool
    @State private var includeDynamicInfo: Bool
    @State private var isEnabled: Bool
    @State private var showingDeleteAlert = false
    
    // Delay trigger properties
    @State private var delayDuration: Double = 30
    @State private var delayUnit: String = "seconds"
    
    // Health trigger properties
    @State private var respiratoryRateThreshold: Double = 20
    @State private var respiratoryRateOperator: HealthOperator = .lessThan
    @State private var hrvThreshold: Double = 50
    @State private var hrvOperator: HealthOperator = .lessThan

    init(action: ActionConfig) {
        self.action = action
        
        // Extract base name by removing " - ContactName" suffix if present
        let baseName = Self.extractBaseName(from: action.name)
        self._baseName = State(initialValue: baseName)
        self._name = State(initialValue: action.name)
        
        self._triggerType = State(initialValue: action.triggerType)
        self._voiceTriggerWord = State(initialValue: action.voiceTriggerWord ?? "")
        self._selectedContacts = State(initialValue: action.actionType == .textMessage ? Set(action.contacts) : [])
        self._selectedSingleContact = State(initialValue: action.actionType != .textMessage ? action.contacts.first : nil)
        self._message = State(initialValue: action.message ?? "")
        self._includeLocation = State(initialValue: action.includeLocation)
        self._includeDynamicInfo = State(initialValue: action.includeDynamicInfo)
        self._isEnabled = State(initialValue: action.isEnabled)
        
        // Initialize delay trigger properties
        self._delayDuration = State(initialValue: action.delayDuration ?? 30)
        self._delayUnit = State(initialValue: action.delayUnit ?? "seconds")
        
        // Initialize health trigger properties
        self._respiratoryRateThreshold = State(initialValue: action.respiratoryRateThreshold ?? 20)
        self._respiratoryRateOperator = State(initialValue: action.respiratoryRateOperator ?? .lessThan)
        self._hrvThreshold = State(initialValue: action.hrvThreshold ?? 50)
        self._hrvOperator = State(initialValue: action.hrvOperator ?? .lessThan)
    }
    
    // Computed property to generate the full name
    private var fullName: String {
        if action.actionType == .textMessage {
            // Multi-contact logic for text messages
            if selectedContacts.isEmpty {
                return baseName
            } else if selectedContacts.count == 1,
                      let contactId = selectedContacts.first,
                      let contact = settingsManager.settings.contacts.first(where: { $0.id == contactId }) {
                return "\(baseName) - \(contact.name)"
            } else {
                let contactNames = selectedContacts.compactMap { contactId in
                    settingsManager.settings.contacts.first(where: { $0.id == contactId })?.name
                }.joined(separator: ", ")
                return "\(baseName) - \(contactNames)"
            }
        } else {
            // Single contact logic for other action types
            if let contactId = selectedSingleContact,
               let contact = settingsManager.settings.contacts.first(where: { $0.id == contactId }) {
                return "\(baseName) - \(contact.name)"
            }
            return baseName
        }
    }
    private static func extractBaseName(from fullName: String) -> String {
        // Remove " - ContactName" pattern from the end
        if let dashIndex = fullName.lastIndex(of: "-") {
            let baseNamePart = String(fullName[..<dashIndex]).trimmingCharacters(in: .whitespaces)
            return baseNamePart.isEmpty ? fullName : baseNamePart
        }
        return fullName
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Basic Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Action Name", text: $baseName)
                        
                        if !baseName.isEmpty && ((action.actionType == .textMessage && !selectedContacts.isEmpty) || (action.actionType != .textMessage && selectedSingleContact != nil)) {
                            Text("Full name: \(fullName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trigger Type")
                            .font(.headline)
                        
                        Text("Selected: \(triggerType.rawValue)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    ForEach([TriggerType.actionButton, TriggerType.voiceTriggerWord, TriggerType.waitForMovement, TriggerType.delay, TriggerType.respiratoryRate, TriggerType.heartRateVariability], id: \.self) { trigger in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trigger.rawValue)
                                    .font(.headline)
                            }
                            
                            Spacer()
                            
                            if triggerType == trigger {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                            } else {
                                Circle()
                                    .stroke(.gray, lineWidth: 1)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            triggerType = trigger
                        }
                    }
                    
                    if triggerType == .voiceTriggerWord {
                        TextField("Voice trigger word", text: $voiceTriggerWord)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    // Delay trigger settings
                    if triggerType == .delay {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Duration", value: $delayDuration, format: .number)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 80)
                                
                                Picker("Unit", selection: $delayUnit) {
                                    Text("seconds").tag("seconds")
                                    Text("minutes").tag("minutes")
                                    Text("hours").tag("hours")
                                }
                                .pickerStyle(MenuPickerStyle())
                            }
                            
                            Text("Action will trigger after the specified delay")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Health trigger settings
                    if triggerType == .respiratoryRate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Trigger when respiratory rate is")
                                    .font(.caption)
                                
                                Picker("Operator", selection: $respiratoryRateOperator) {
                                    ForEach(HealthOperator.allCases, id: \.self) { op in
                                        Text(op.rawValue).tag(op)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                
                                TextField("BPM", value: $respiratoryRateThreshold, format: .number)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 60)
                                
                                Text("breaths/min")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if triggerType == .heartRateVariability {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Trigger when HRV is")
                                    .font(.caption)
                                
                                Picker("Operator", selection: $hrvOperator) {
                                    ForEach(HealthOperator.allCases, id: \.self) { op in
                                        Text(op.rawValue).tag(op)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                
                                TextField("ms", value: $hrvThreshold, format: .number)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 60)
                                
                                Text("milliseconds")
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if triggerType == .waitForMovement {
                        Text("Action will trigger when device detects movement")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }

                Section("Message Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Emergency Message")
                            .font(.headline)

                        TextField("Enter custom message...", text: $message, axis: .vertical)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .lineLimit(3...6)

                        Text("Use {location}, {time}, {battery} for dynamic values")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Include Location", isOn: $includeLocation)
                    Toggle("Include Dynamic Info", isOn: $includeDynamicInfo)
                }

                Section("Contacts") {
                    if settingsManager.settings.contacts.isEmpty {
                        Text("No contacts available. Add contacts to assign them to this action.")
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(action.actionType == .textMessage ? "Select contacts for this action" : "Select contact for this action")
                                .font(.headline)
                            
                            if action.actionType == .textMessage {
                                if selectedContacts.isEmpty {
                                    Text("No contacts selected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(selectedContacts.count) contact(s) selected")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            } else {
                                if selectedSingleContact == nil {
                                    Text("No contact selected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if let contactId = selectedSingleContact,
                                          let contact = settingsManager.settings.contacts.first(where: { $0.id == contactId }) {
                                    Text("Selected: \(contact.name)")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        ForEach(settingsManager.settings.contacts) { contact in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name)
                                        .font(.headline)
                                    Text(contact.phoneNumber)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if action.actionType == .textMessage {
                                    // Multi-select for text messages
                                    if selectedContacts.contains(contact.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.title2)
                                    } else {
                                        Circle()
                                            .stroke(.gray, lineWidth: 1)
                                            .frame(width: 20, height: 20)
                                    }
                                } else {
                                    // Single-select for other actions
                                    if selectedSingleContact == contact.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.title2)
                                    } else {
                                        Circle()
                                            .stroke(.gray, lineWidth: 1)
                                            .frame(width: 20, height: 20)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if action.actionType == .textMessage {
                                    // Multi-select logic for text messages
                                    if selectedContacts.contains(contact.id) {
                                        selectedContacts.remove(contact.id)
                                    } else {
                                        selectedContacts.insert(contact.id)
                                    }
                                } else {
                                    // Single-select logic for other actions
                                    if selectedSingleContact == contact.id {
                                        selectedSingleContact = nil
                                    } else {
                                        selectedSingleContact = contact.id
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Action")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Delete") {
                            showingDeleteAlert = true
                        }
                        .foregroundColor(.red)
                        
                        Button("Save") { 
                            saveChanges() 
                        }
                        .disabled(baseName.isEmpty || ((action.actionType == .textMessage && selectedContacts.isEmpty) || (action.actionType != .textMessage && selectedSingleContact == nil)))
                    }
                }
            }
            .alert("Delete Action", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    settingsManager.removeAction(id: action.id)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete '\(action.name)'? This cannot be undone.")
            }
        }
    }

    private func saveChanges() {
        let contacts = if action.actionType == .textMessage {
            Array(selectedContacts)
        } else {
            selectedSingleContact.map { [$0] } ?? []
        }
        
        let updatedAction = ActionConfig(
            id: action.id,
            name: fullName,
            actionType: action.actionType,
            triggerType: triggerType,
            voiceTriggerWord: triggerType == .voiceTriggerWord ? voiceTriggerWord : nil,
            contacts: contacts,
            message: message.isEmpty ? nil : message,
            includeLocation: includeLocation,
            includeDynamicInfo: includeDynamicInfo,
            isEnabled: isEnabled,
            respiratoryRateThreshold: triggerType == .respiratoryRate ? respiratoryRateThreshold : nil,
            respiratoryRateOperator: triggerType == .respiratoryRate ? respiratoryRateOperator : nil,
            hrvThreshold: triggerType == .heartRateVariability ? hrvThreshold : nil,
            hrvOperator: triggerType == .heartRateVariability ? hrvOperator : nil,
            delayDuration: triggerType == .delay ? delayDuration : nil,
            delayUnit: triggerType == .delay ? delayUnit : nil
        )

        print("🔄 Updating action: \(action.name) -> \(fullName)")
        settingsManager.updateAction(updatedAction)
        dismiss()
    }
}

#Preview {
    let sampleAction = ActionConfig(
        name: "Sample Action",
        actionType: .distressCall,
        triggerType: .actionButton,
        contacts: [],
        message: "Emergency help needed!",
        includeLocation: true,
        includeDynamicInfo: true,
        isEnabled: true
    )

    ActionEditView(action: sampleAction)
}
