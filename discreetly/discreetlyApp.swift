//
//  discreetlyApp.swift
//  discreetly
//
//  Created by Kevin Xiao on 10/16/25.
//

import SwiftUI
import UserNotifications
import BackgroundTasks
import AVFoundation
import CoreMotion
import HealthKit
import WatchConnectivity

@main
struct discreetlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var permissionManager = PermissionManager.shared
    @StateObject private var motionDetectionService = MotionDetectionService.shared
    @StateObject private var healthKitService = HealthKitService.shared
    @StateObject private var watchConnectivityService = WatchConnectivityService.shared
    @StateObject private var healthTriggerService = HealthTriggerService.shared
    @StateObject private var backgroundSensorMonitor = BackgroundSensorMonitor.shared
    @StateObject private var neighborhoodSafetyService = NeighborhoodSafetyService.shared
    @StateObject private var settingsManager = SettingsManager.shared

    var body: some Scene {
        WindowGroup {
            ActionsMainView()
                .onAppear {
                    startupSequence()
                }
                .environmentObject(permissionManager)
                .environmentObject(motionDetectionService)
                .environmentObject(healthKitService)
                .environmentObject(watchConnectivityService)
                .environmentObject(healthTriggerService)
                .environmentObject(backgroundSensorMonitor)
                .environmentObject(neighborhoodSafetyService)
                .environmentObject(settingsManager)
        }
    }

    private func startupSequence() {
        Task {
            // Check current permissions first
            permissionManager.checkAllPermissions()

            // Setup background audio
            setupBackgroundAudio()

            // Start button monitoring
            startButtonMonitoring()

            // Start background sensor monitoring for instant triggers
            startBackgroundSensorMonitoring()

            // Start neighborhood safety monitoring
            startNeighborhoodSafetyMonitoring()

            // Request permissions if not already requested
            if !permissionManager.hasRequestedPermissions {
                await permissionManager.requestAllPermissions()
            }

            // Request HealthKit permissions
            if healthKitService.healthKitAvailable && healthKitService.authorizationStatus == .notDetermined {
                do {
                    try await healthKitService.requestAuthorization()
                    print("✅ HealthKit authorization requested")
                } catch {
                    print("❌ Failed to request HealthKit authorization: \(error)")
                }
            }

            // Start motion detection with whatever capabilities are available
            await MainActor.run {
                // Always try to start motion detection - it will use available sensors
                motionDetectionService.startMotionDetection()
                print("📱 Motion detection startup attempted")

                // Log Apple Watch connectivity status
                print("⌚ Apple Watch Status: \(watchConnectivityService.watchStatusString)")
            }
        }
    }

    private func setupBackgroundAudio() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
            print("✅ Background audio session configured")
        } catch {
            print("❌ Failed to setup background audio: \(error)")
        }
    }

    private func startButtonMonitoring() {
        ActionMapper.shared.startMonitoring()
        print("🎯 Button monitoring initiated from app launch")
    }

    private func startBackgroundSensorMonitoring() {
        backgroundSensorMonitor.startMonitoring()
        print("📡 Background sensor monitoring initiated from app launch")
    }

    private func startNeighborhoodSafetyMonitoring() {
        // Check if user has enabled neighborhood safety monitoring
        guard settingsManager.settings.enableNeighborhoodSafetyMonitoring else {
            print("⚠️ Neighborhood safety monitoring disabled in user settings")
            return
        }

        // Check if location permissions are available before starting
        if permissionManager.permissionStatus.location == "Authorized" {
            neighborhoodSafetyService.startMonitoring()
            print("🛡️ Neighborhood safety monitoring initiated from app launch")
        } else {
            print("⚠️ Neighborhood safety monitoring deferred - waiting for location permissions")
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

        // Register background tasks
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.discreetly.background.monitoring", using: nil) { task in
            self.handleBackgroundMonitoring(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.discreetly.background.emergency", using: nil) { task in
            self.handleEmergencyBackgroundTask(task: task as! BGProcessingTask)
        }

        print("✅ Background tasks registered")
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleBackgroundTasks()
        print("📱 App entered background - monitoring may be limited")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        print("📱 App entering foreground - full monitoring restored")
    }

    private func scheduleBackgroundTasks() {
        let request = BGAppRefreshTaskRequest(identifier: "com.discreetly.background.monitoring")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background monitoring task scheduled")
        } catch {
            print("❌ Failed to schedule background task: \(error)")
        }
    }

    private func handleBackgroundMonitoring(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Limited background monitoring
        let startTime = Date()

        // Check for emergency conditions in background
        DispatchQueue.global(qos: .utility).async {
            // Simulate emergency monitoring (very limited in background)
            sleep(2)

            let timeElapsed = Date().timeIntervalSince(startTime)
            print("🔄 Background monitoring completed in \(timeElapsed)s")

            task.setTaskCompleted(success: true)

            // Schedule next background task
            self.scheduleBackgroundTasks()
        }
    }

    private func handleEmergencyBackgroundTask(task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Handle emergency processing
        DispatchQueue.global(qos: .userInitiated).async {
            // Emergency background processing
            print("🚨 Emergency background task triggered")

            // Here you could:
            // 1. Send location updates
            // 2. Trigger emergency calls
            // 3. Send status updates

            task.setTaskCompleted(success: true)
        }
    }
}
