//
//  SensorDataDisplayView.swift
//  discreetly
//
//  View for displaying all sensor data when action is triggered
//

import SwiftUI

struct SensorDataDisplayView: View {
    @StateObject private var sensorService = SensorDataService.shared
    @StateObject private var backgroundMonitor = BackgroundSensorMonitor.shared
    @EnvironmentObject private var motionService: MotionDetectionService
    @EnvironmentObject private var permissionManager: PermissionManager
    @State private var sensorDisplayItems: [SensorDisplayItem] = []
    @State private var showingData = false
    @State private var useBackgroundData = true

    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if sensorService.isCollecting {
                        loadingView
                    } else if !sensorDisplayItems.isEmpty {
                        dataView
                    } else {
                        emptyView
                    }
                }
                .padding()
            }
            .navigationTitle("Sensor Data")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Menu {
                            Button(action: {
                                useBackgroundData = true
                                collectSensorData()
                            }) {
                                Label("Use Background Data", systemImage: backgroundMonitor.isDataFresh ? "checkmark.circle.fill" : "clock")
                            }

                            Button(action: {
                                useBackgroundData = false
                                collectSensorData()
                            }) {
                                Label("Force Fresh Collection", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }

                        Button("Refresh") {
                            collectSensorData()
                        }
                        .disabled(sensorService.isCollecting)
                    }
                }
            }
        }
        .onAppear {
            collectSensorData()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()

            Text("Collecting Sensor Data...")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Gathering location, motion, camera, audio, device, and Apple Watch health information")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("No Sensor Data")
                .font(.headline)

            Text("Tap refresh to collect current sensor readings")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Collect Data") {
                collectSensorData()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private var dataView: some View {
        LazyVStack(spacing: 16) {
            // Background Monitor Status
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: backgroundMonitor.isMonitoring ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(backgroundMonitor.isMonitoring ? .green : .orange)
                    Text("Background Monitoring")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(backgroundMonitor.isMonitoring ? "Active" : "Inactive")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(backgroundMonitor.isMonitoring ? .green : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((backgroundMonitor.isMonitoring ? Color.green : Color.orange).opacity(0.2))
                        .cornerRadius(8)
                }

                if backgroundMonitor.isMonitoring {
                    HStack {
                        Text("Data Age:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1fs", backgroundMonitor.dataAge))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(backgroundMonitor.isDataFresh ? .green : .orange)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.green.opacity(0.05))
            .cornerRadius(12)

            // Header with timestamp
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                    Text("Data collected at \(DateFormatter.localizedString(from: sensorService.currentSensorData.timestamp, dateStyle: .none, timeStyle: .medium))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.blue.opacity(0.1))
                .cornerRadius(12)
            }

            // Motion Analytics Section (if motion service is active)
            if motionService.isActive {
                MotionAnalyticsView(analytics: motionService.currentMotionAnalytics)
            }

            // Permissions Status
            PermissionStatusView(permissionStatus: permissionManager.permissionStatus)

            // Sensor data sections
            ForEach(sensorDisplayItems.indices, id: \.self) { index in
                SensorCategoryView(displayItem: sensorDisplayItems[index])
            }
        }
    }

    private func collectSensorData() {
        Task {
            let sensorData: SensorData

            if useBackgroundData && backgroundMonitor.isDataFresh {
                // Use instant background data
                sensorData = backgroundMonitor.getCurrentSensorData()
                print("📱 Using instant background sensor data (age: \(String(format: "%.1f", backgroundMonitor.dataAge))s)")
            } else {
                // Collect fresh data
                sensorData = useBackgroundData
                    ? await sensorService.collectAllSensorData()  // This will use background data if fresh
                    : await sensorService.collectAllSensorDataDirect()  // This forces fresh collection
                print("📱 Collected \(useBackgroundData ? "hybrid" : "fresh") sensor data")
            }

            await MainActor.run {
                self.sensorDisplayItems = sensorService.formatSensorDataForDisplay(sensorData)
                withAnimation(.easeInOut) {
                    self.showingData = true
                }
            }
        }
    }
}

struct SensorCategoryView: View {
    let displayItem: SensorDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack {
                Image(systemName: iconForCategory(displayItem.category))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)

                Text(displayItem.category)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }

            // Data items
            VStack(spacing: 8) {
                ForEach(displayItem.items.indices, id: \.self) { index in
                    let item = displayItem.items[index]
                    HStack {
                        Text(item.0)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(item.1)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)

                    if index < displayItem.items.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.background.secondary)
        .cornerRadius(12)
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Location": return "location"
        case "Motion": return "gyroscope"
        case "Device": return "iphone"
        case "Audio": return "speaker.wave.2"
        case "Camera": return "camera"
        case "Contacts": return "person.2"
        case "Network": return "network"
        case "Watch Heart": return "heart.fill"
        case "Watch Activity": return "figure.run"
        case "Watch Health": return "cross.fill"
        case "Watch Environment": return "waveform.circle"
        case "Watch Mindfulness": return "brain.head.profile"
        case "Watch Status": return "applewatch"
        default: return "sensor"
        }
    }
}

// Preview-friendly wrapper
struct SensorDataDisplayPreview: View {
    @State private var isPresented = true

    var body: some View {
        Button("Show Sensor Data") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            SensorDataDisplayView {
                isPresented = false
            }
        }
    }
}

// MARK: - Motion Analytics View

struct MotionAnalyticsView: View {
    let analytics: MotionAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.green)
                    .frame(width: 24, height: 24)

                Text("Motion Analytics")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Emergency indicators
                if analytics.isFalling || analytics.isShaking {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                }
            }

            // Quick stats
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                MotionStatCard(title: "Activity", value: analytics.motionActivity, icon: "figure.walk")
                MotionStatCard(title: "Speed", value: String(format: "%.1f km/h", analytics.getSpeedKmh()), icon: "speedometer")
                MotionStatCard(title: "G-Force", value: String(format: "%.1f g", analytics.totalAcceleration), icon: "gyroscope")
                MotionStatCard(title: "Distance", value: String(format: "%.0f m", analytics.estimatedDistance), icon: "location")
            }

            // Detailed motion data
            DisclosureGroup("Detailed Motion Data") {
                VStack(spacing: 8) {
                    ForEach(analytics.formattedData.indices, id: \.self) { index in
                        let item = analytics.formattedData[index]
                        HStack {
                            Text(item.0)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(item.1)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 4)

                        if index < analytics.formattedData.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }

            // Motion status indicators
            DisclosureGroup("Motion Status") {
                VStack(spacing: 8) {
                    ForEach(analytics.statusData.indices, id: \.self) { index in
                        let item = analytics.statusData[index]
                        HStack {
                            Text(item.0)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(item.1)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(item.1.contains("⚠️") ? .red : .primary)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 4)

                        if index < analytics.statusData.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }

            // Raw sensor data
            DisclosureGroup("Raw Sensor Data") {
                VStack(spacing: 8) {
                    ForEach(analytics.rawSensorData.indices, id: \.self) { index in
                        let item = analytics.rawSensorData[index]
                        HStack {
                            Text(item.0)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(item.1)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .font(.system(.subheadline, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 4)

                        if index < analytics.rawSensorData.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.green.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(analytics.isFalling || analytics.isShaking ? Color.red : Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

struct MotionStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.green)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.background.secondary)
        .cornerRadius(8)
    }
}

// MARK: - Permission Status View

struct PermissionStatusView: View {
    let permissionStatus: PermissionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)

                Text("Permission Status")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Overall status indicator
                Image(systemName: permissionStatus.criticalGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(permissionStatus.criticalGranted ? .green : .orange)
                    .font(.title2)
            }

            // Permission list
            VStack(spacing: 8) {
                ForEach(getPermissionList().indices, id: \.self) { index in
                    let item = getPermissionList()[index]
                    VStack {
                        HStack {
                            Image(systemName: iconForPermission(item.0))
                                .foregroundColor(colorForStatus(item.1))
                                .frame(width: 20, height: 20)

                            Text(item.0)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(item.1)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(colorForStatus(item.1))
                        }
                        .padding(.horizontal, 4)

                        // Show help text for motion issues
                        if item.0 == "Motion & Fitness" && needsMotionHelp(item.1) {
                            MotionHelpView(status: item.1)
                                .padding(.top, 4)
                        }
                    }

                    if index < getPermissionList().count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(permissionStatus.criticalGranted ? Color.blue.opacity(0.3) : Color.orange, lineWidth: 1)
        )
    }

    private func getPermissionList() -> [(String, String)] {
        return [
            ("Location", permissionStatus.location),
            ("Motion & Fitness", permissionStatus.motion),
            ("Microphone", permissionStatus.microphone),
            ("Camera", permissionStatus.camera),
            ("Contacts", permissionStatus.contacts),
            ("Notifications", permissionStatus.notifications)
        ]
    }

    private func iconForPermission(_ permission: String) -> String {
        switch permission {
        case "Location": return "location"
        case "Motion & Fitness": return "figure.run"
        case "Microphone": return "mic"
        case "Camera": return "camera"
        case "Contacts": return "person.2"
        case "Notifications": return "bell"
        default: return "questionmark"
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status {
        case "Authorized", "Granted": return .green
        case "Authorized (Full)": return .green
        case "Basic Sensors Only", "Basic Sensors Available": return .yellow
        case "Limited (Basic Sensors Only)": return .yellow
        case "Simulator/Limited Device", "Simulator/Not Available": return .orange
        case "Denied": return .red
        case "Restricted": return .orange
        case "Not Determined", "Not Requested": return .gray
        case "Limited", "Provisional": return .yellow
        default: return .gray
        }
    }

    private func needsMotionHelp(_ status: String) -> Bool {
        return status.contains("Simulator") || status.contains("Basic Sensors") || status.contains("Limited") || status == "Denied"
    }
}

// MARK: - Motion Help View

struct MotionHelpView: View {
    let status: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)

            Text(helpText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.blue.opacity(0.1))
        .cornerRadius(8)
    }

    private var helpText: String {
        switch status {
        case let s where s.contains("Simulator"):
            return "Motion & Fitness features are limited in iOS Simulator. Basic motion sensors will work on physical devices."
        case let s where s.contains("Basic Sensors"):
            return "Motion & Fitness permission denied, but basic accelerometer/gyroscope still work for motion detection."
        case let s where s.contains("Limited"):
            return "Limited motion capabilities. Check Privacy & Security → Motion & Fitness in iOS Settings to enable full features."
        case "Denied":
            return "Motion access denied. Go to Settings → Privacy & Security → Motion & Fitness → Discreetly to enable."
        default:
            return "Motion sensors may have limited functionality."
        }
    }
}

#Preview {
    SensorDataDisplayPreview()
}