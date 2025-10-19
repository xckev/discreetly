//
//  ActionsMainView.swift
//  discreetly
//
//  Main discreetly-style interface
//

import SwiftUI

struct ActionsMainView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @StateObject private var aiAgent = AIAgentService()
    @ObservedObject private var actionMapper = ActionMapper.shared
    @ObservedObject private var neighborhoodSafetyService = NeighborhoodSafetyService.shared
    @ObservedObject private var watchConnectivity = WatchConnectivityService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var isActionsEnabled = false
    @State private var showingConfiguration = false
    @State private var selectedActionForEdit: ActionConfig?
    @State private var showingContacts = false
    @State private var showingSensors = false
    @State private var userName: String = ""
    @State private var showingNameEditor = false
    @State private var editingUserName: String = ""

    var body: some View {
        NavigationView {
            if settingsManager.settings.actions.isEmpty {
                // Welcome/First Time Experience
                welcomeView
            } else {
                // Existing Actions Management View
                existingActionsView
            }
        }
        .sheet(isPresented: $showingConfiguration) {
            ActionConfigurationFlow()
        }
        .sheet(item: $selectedActionForEdit) { action in
            ActionEditView(action: action)
        }
        .sheet(isPresented: $showingContacts) {
            ContactManagementView()
        }
        .sheet(isPresented: $showingSensors) {
            SensorDataDisplayView {
                showingSensors = false
            }
        }
        .sheet(isPresented: $showingNameEditor) {
            NameEditorView(
                currentName: editingUserName,
                onSave: { newName in
                    let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedName.isEmpty {
                        settingsManager.settings.userName = trimmedName
                        userName = trimmedName
                    }
                    showingNameEditor = false
                },
                onCancel: {
                    showingNameEditor = false
                }
            )
        }
        .sheet(isPresented: $actionMapper.showingSensorData) {
            SensorDataDisplayView {
                actionMapper.showingSensorData = false
            }
        }
        .overlay {
            if actionMapper.showingActionExecutionPopup {
                ActionExecutionOverlay(
                    actionName: actionMapper.executingActionName,
                    actionType: actionMapper.executingActionType,
                    isExecuting: actionMapper.isActionExecuting,
                    onDismiss: {
                        actionMapper.dismissActionExecutionPopup()
                    }
                )
            }
        }
        .sheet(isPresented: $actionMapper.showingAskAI) {
            AskAISheet()
        }
        .sheet(isPresented: $actionMapper.showingAIResponse) {
            AIResponseView(
                question: actionMapper.aiQuestion,
                response: actionMapper.aiResponse
            )
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Spacer()

            // Hero Section
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(colorScheme == .dark ? "DarkImage" : "Image")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(width: 60, height: 60)

                    Text("Welcome to Discreetly")
                        .font(.title)
                        .fontWeight(.bold)
                }

                Text("Discreet help at your fingertips")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Features Overview
            VStack(spacing: 12) {
                FeatureRow(
                    icon: "button.horizontal",
                    title: "Multiple Trigger Methods",
                    description: "Action Button, voice commands, health sensors, and more"
                )

                FeatureRow(
                    icon: "location",
                    title: "Smart Emergency Data",
                    description: "Location, health metrics, and contextual information"
                )

                FeatureRow(
                    icon: "brain",
                    title: "AI Voice Agent",
                    description: "Intelligent voice agent that acts on your behalf during emergencies"
                )
            }
            .padding(.horizontal)

            // User Name Input (Required)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Name")
                    .font(.headline)
                TextField("Enter your full name", text: $userName)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                if userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Name is required to personalize messages and calls.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            // Call to Action
            VStack(spacing: 16) {
                Button(action: {
                    let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    // Persist the user's name into settings
                    settingsManager.settings.userName = trimmed
                    showingConfiguration = true
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Create Your First Action")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter your name to continue" : "Emergency setup takes less than 2 minutes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding()
        .navigationTitle("")
        .navigationBarHidden(true)
    }

    private var existingActionsView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 8)

                headerSection
                navigationButtonsSection
                mainControlsSection
                neighborhoodSafetySection

                actionsManagementSection

                Spacer(minLength: 8)
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .onAppear {
            userName = settingsManager.settings.userName ?? ""
            isActionsEnabled = !settingsManager.getEnabledActions().isEmpty
            if isActionsEnabled {
                aiAgent.startAgent()
            } else {
                // Ensure all actions are disabled if system is inactive on appear
                settingsManager.disableAllActions()
            }

            // Send initial system state to watch
            watchConnectivity.updateWatchSystemState(isEnabled: isActionsEnabled)
        }
        .onChange(of: isActionsEnabled) { enabled in
            if enabled {
                aiAgent.startAgent()
            } else {
                aiAgent.stopAgent()
                // Disable all actions when system is turned off
                settingsManager.disableAllActions()
            }

            // Update watch app with new system state
            watchConnectivity.updateWatchSystemState(isEnabled: enabled)
        }
    }
    
    // MARK: - Section Views for existingActionsView
    
    private var neighborhoodSafetySection: some View {
        VStack(spacing: 12) {
            if settingsManager.settings.enableNeighborhoodSafetyMonitoring {
                if let safetyInfo = neighborhoodSafetyService.currentSafetyInfo {
                    // Show current neighborhood and safety status
                    HStack(spacing: 12) {
                        // Safety status icon
                        Group {
                            switch safetyInfo.safetyStatus {
                            case .safe:
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(.green)
                            case .moderatelyUnsafe:
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundColor(.orange)
                            case .unsafe:
                                Image(systemName: "xmark.shield.fill")
                                    .foregroundColor(.red)
                            case .unknown:
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Area")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(safetyInfo.neighborhood)
                                .font(.headline)
                                .fontWeight(.medium)
                            Text(safetyInfo.safetyStatus.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Safety score if available
                        if safetyInfo.safetyScore > 0 {
                            VStack(spacing: 2) {
                                Text("\(safetyInfo.safetyScore)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(scoreColor(for: safetyInfo.safetyScore))
                                Text("/ 10")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                } else if neighborhoodSafetyService.isMonitoring {
                    // Monitoring but no data yet
                    HStack(spacing: 12) {
                        Image(systemName: "location.circle")
                            .foregroundColor(.blue)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Location Monitoring")
                                .font(.headline)
                                .fontWeight(.medium)
                            Text("Detecting neighborhood...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                }
            }
        }
    }

    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 8...10: return .green
        case 5...7: return .orange
        case 1...4: return .red
        default: return .gray
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(colorScheme == .dark ? "DarkImage" : "Image")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: 60, height: 60)

                Text("Discreetly")
                    .font(.title)
                    .fontWeight(.bold)
            }

            userWelcomeMessage
        }
    }
    
    private var userWelcomeMessage: some View {
        Group {
            if let userName = settingsManager.settings.userName, !userName.isEmpty {
                Button(action: {
                    editingUserName = userName
                    showingNameEditor = true
                }) {
                    Text("Welcome, \(userName)!")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    editingUserName = ""
                    showingNameEditor = true
                }) {
                    Text("Welcome, {name}!")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var navigationButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                showingContacts = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                    Text("Contacts")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }

            Button(action: {
                showingSensors = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "sensor.fill")
                        .font(.title3)
                    Text("Sensors")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var mainControlsSection: some View {
        VStack(spacing: 15) {
            HStack {
                Toggle("", isOn: $isActionsEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(1.3)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text(isActionsEnabled ? "Emergency System Active" : "Emergency System Inactive")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(isActionsEnabled ? .green : .secondary)

                Text(isActionsEnabled ?
                     "Actions are ready" :
                     "Tap to activate Actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            testActionButton
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }
    
    @ViewBuilder
    private var testActionButton: some View {
        if isActionsEnabled {
            Button(action: {
                ActionMapper.shared.manualTrigger()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                    Text("Test Action")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.orange)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.top, 8)
        }
    }
    
    private var actionsManagementSection: some View {
        VStack(spacing: 16) {
            if !settingsManager.settings.actions.isEmpty {
                actionsOverviewSection
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var actionsOverviewSection: some View {
        VStack(spacing: 16) {
            actionsHeaderRow
            actionsGrid
            actionsCountFooter
        }
        .padding(.top, 10)
    }
    
    private var actionsHeaderRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Actions")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Only one Action can be active at a time")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: {
                showingConfiguration = true
            }) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }
        }
    }
    
    private var actionsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
            ForEach(Array(settingsManager.settings.actions.prefix(10)), id: \.id) { action in
                ActionRowView(
                    action: action,
                    isActionsEnabled: isActionsEnabled,
                    actionMapper: actionMapper,
                    settingsManager: settingsManager,
                    onEditAction: { selectedActionForEdit = action }
                )
            }
        }
    }
    
    @ViewBuilder
    private var actionsCountFooter: some View {
        if settingsManager.settings.actions.count > 10 {
            Text("+ \(settingsManager.settings.actions.count - 10) more")
                .font(.caption)
                .foregroundColor(.secondary)
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
    
    private func descriptionForAction(_ action: ActionConfig) -> String {
        switch action.triggerType {
        case .actionButton:
            return "Press Action Button"
        case .voiceTriggerWord:
            return "Say '\(action.voiceTriggerWord ?? "help")'"
        case .waitForMovement:
            return "Wait for movement"
        case .delay:
            if let duration = action.delayDuration, let unitString = action.delayUnit {
                if duration < 60 {
                    return "Delay: \(Int(duration)) seconds"
                } else if duration < 3600 {
                    return "Delay: \(Int(duration / 60)) minutes"
                } else {
                    return "Delay: \(Int(duration / 3600)) hours"
                }
            }
            return "Delay"
        case .respiratoryRate:
            return "Respiratory rate trigger"
        case .heartRateVariability:
            return "Heart rate variability trigger"
        }
    }
}

// MARK: - Action Row View
struct ActionRowView: View {
    let action: ActionConfig
    let isActionsEnabled: Bool
    let actionMapper: ActionMapper
    let settingsManager: SettingsManager
    let onEditAction: () -> Void
    
    var body: some View {
        Button(action: onEditAction) {
            HStack(spacing: 16) {
                actionIcon
                actionDetails
                Spacer()
                actionControls
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(backgroundColorForAction)
            .cornerRadius(12)
            .overlay(borderForAction)
        }
        .buttonStyle(.plain)
    }
    
    private var actionIcon: some View {
        Image(systemName: iconForActionType(action.actionType))
            .font(.title2)
            .foregroundColor(action.isEnabled && isActionsEnabled ? .blue : .gray)
    }
    
    private var actionDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(action.name)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(action.isEnabled && isActionsEnabled ? .primary : .secondary)
                .multilineTextAlignment(.leading)
            
            Text(descriptionForAction(action))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
    }
    
    private var actionControls: some View {
        VStack(spacing: 4) {
            Toggle("", isOn: Binding(
                get: { action.isEnabled },
                set: { isEnabled in
                    handleToggleChange(isEnabled)
                }
            ))
            .toggleStyle(.switch)
            .disabled(!isActionsEnabled)
            .onTapGesture {
                // Prevent the button tap when toggle is tapped
            }
            
            actionStatusLabel
        }
    }
    
    @ViewBuilder
    private var actionStatusLabel: some View {
        if action.isEnabled {
            if actionMapper.showingDelayCountdown && actionMapper.pendingDelayedAction?.id == action.id {
                Text("⏱️ \(Int(actionMapper.remainingDelayTime))s")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private var backgroundColorForAction: Color {
        action.isEnabled && isActionsEnabled ? Color.blue.opacity(0.05) : Color(.systemGray6)
    }
    
    private var borderForAction: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(action.isEnabled && isActionsEnabled ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
    }
    
    private func handleToggleChange(_ isEnabled: Bool) {
        // Prevent enabling actions when system is inactive
        if isEnabled && !self.isActionsEnabled {
            return
        }
        
        // If action is being disabled and has a running timer, cancel it
        if !isEnabled && actionMapper.showingDelayCountdown && actionMapper.pendingDelayedAction?.id == action.id {
            print("🚫 Action toggle OFF - canceling delayed timer for: \(action.name)")
            actionMapper.cancelDelayedAction()
        }
        
        // Use the new method that ensures only one action can be active at a time
        settingsManager.enableSingleAction(action.id, enabled: isEnabled)
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
    
    private func descriptionForAction(_ action: ActionConfig) -> String {
        switch action.triggerType {
        case .actionButton:
            return "Press Action Button"
        case .voiceTriggerWord:
            return "Say '\(action.voiceTriggerWord ?? "help")'"
        case .waitForMovement:
            return "Wait for movement"
        case .delay:
            if let duration = action.delayDuration, let unitString = action.delayUnit {
                if duration < 60 {
                    return "Delay: \(Int(duration)) seconds"
                } else if duration < 3600 {
                    return "Delay: \(Int(duration / 60)) minutes"
                } else {
                    return "Delay: \(Int(duration / 3600)) hours"
                }
            }
            return "Delay"
        case .respiratoryRate:
            return "Respiratory rate trigger"
        case .heartRateVariability:
            return "Heart rate variability trigger"
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

// MARK: - Name Editor View
struct NameEditorView: View {
    let currentName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    @State private var editedName: String
    @FocusState private var isTextFieldFocused: Bool
    
    init(currentName: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.currentName = currentName
        self.onSave = onSave
        self.onCancel = onCancel
        self._editedName = State(initialValue: currentName)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("Edit Your Name")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("This name will be used in emergency messages and AI interactions.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Name")
                        .font(.headline)
                    
                    TextField("Enter your full name", text: $editedName)
                        .textContentType(.name)
                        .autocapitalization(.words)
                        .disableAutocorrection(true)
                        .padding(16)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button(action: {
                        onSave(editedName)
                    }) {
                        Text("Save")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                Color.gray : Color.blue
                            )
                            .cornerRadius(12)
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button(action: {
                        onCancel()
                    }) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .padding()
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .onAppear {
            // Auto-focus the text field when the view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
    }
}

#Preview {
    ActionsMainView()
}
