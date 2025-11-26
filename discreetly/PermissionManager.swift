//
//  PermissionManager.swift
//  discreetly
//
//  Manages all app permissions and requests them automatically on launch
//

import Foundation
import CoreLocation
import CoreMotion
import AVFoundation
import Contacts
import UserNotifications
import Speech
import Combine
import UIKit

struct PermissionStatus {
    var location: String = "Unknown"
    var motion: String = "Unknown"
    var microphone: String = "Unknown"
    var speechRecognition: String = "Unknown"
    var camera: String = "Unknown"
    var contacts: String = "Unknown"
    var notifications: String = "Unknown"

    var allGranted: Bool {
        return location == "Authorized" &&
               motion == "Authorized" &&
               microphone == "Authorized" &&
               speechRecognition == "Authorized" &&
               camera == "Authorized" &&
               contacts == "Authorized" &&
               notifications == "Authorized"
    }

    var criticalGranted: Bool {
        return location == "Authorized" &&
               motion == "Authorized" &&
               microphone == "Authorized" &&
               speechRecognition == "Authorized" &&
               notifications == "Authorized"
    }
}

final class PermissionManager: NSObject, ObservableObject {
    static let shared = PermissionManager()

    @Published var permissionStatus = PermissionStatus()
    @Published var isRequestingPermissions = false
    @Published var hasRequestedPermissions = false

    private let locationManager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()

    override init() {
        super.init()
        setupLocationManager()
    }

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Permission Checking

    func checkAllPermissions() {
        checkLocationPermission()
        checkMotionPermission()
        checkMicrophonePermission()
        checkSpeechRecognitionPermission()
        checkCameraPermission()
        checkContactsPermission()
        checkNotificationPermission()
    }

    private func checkLocationPermission() {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            permissionStatus.location = "Authorized"
        case .denied:
            permissionStatus.location = "Denied"
        case .restricted:
            permissionStatus.location = "Restricted"
        case .notDetermined:
            permissionStatus.location = "Not Determined"
        @unknown default:
            permissionStatus.location = "Unknown"
        }
    }

    private func checkMotionPermission() {
        // Check if basic motion manager is available (always available on iOS devices)
        let motionManager = CMMotionManager()
        let hasBasicMotion = motionManager.isAccelerometerAvailable || motionManager.isGyroAvailable

        if CMMotionActivityManager.isActivityAvailable() {
            let status = CMMotionActivityManager.authorizationStatus()
            switch status {
            case .authorized:
                permissionStatus.motion = "Authorized"
            case .denied:
                permissionStatus.motion = "Denied"
            case .restricted:
                permissionStatus.motion = "Restricted"
            case .notDetermined:
                permissionStatus.motion = "Not Determined"
            @unknown default:
                permissionStatus.motion = "Unknown"
            }
        } else if hasBasicMotion {
            // Motion activity not available but basic sensors are
            permissionStatus.motion = "Limited (Basic Sensors Only)"
        } else {
            // Likely simulator or very old device
            permissionStatus.motion = "Simulator/Limited Device"
        }

        print("🔍 Motion availability check:")
        print("  - CMMotionActivityManager.isActivityAvailable(): \(CMMotionActivityManager.isActivityAvailable())")
        print("  - Basic motion sensors available: \(hasBasicMotion)")
        print("  - Final status: \(permissionStatus.motion)")
    }

    private func checkMicrophonePermission() {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                permissionStatus.microphone = "Authorized"
            case .denied:
                permissionStatus.microphone = "Denied"
            case .undetermined:
                permissionStatus.microphone = "Not Determined"
            @unknown default:
                permissionStatus.microphone = "Unknown"
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                permissionStatus.microphone = "Authorized"
            case .denied:
                permissionStatus.microphone = "Denied"
            case .undetermined:
                permissionStatus.microphone = "Not Determined"
            @unknown default:
                permissionStatus.microphone = "Unknown"
            }
        }
    }

    private func checkSpeechRecognitionPermission() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            permissionStatus.speechRecognition = "Authorized"
        case .denied:
            permissionStatus.speechRecognition = "Denied"
        case .restricted:
            permissionStatus.speechRecognition = "Restricted"
        case .notDetermined:
            permissionStatus.speechRecognition = "Not Determined"
        @unknown default:
            permissionStatus.speechRecognition = "Unknown"
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionStatus.camera = "Authorized"
        case .denied:
            permissionStatus.camera = "Denied"
        case .restricted:
            permissionStatus.camera = "Restricted"
        case .notDetermined:
            permissionStatus.camera = "Not Determined"
        @unknown default:
            permissionStatus.camera = "Unknown"
        }
    }

    private func checkContactsPermission() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            permissionStatus.contacts = "Authorized"
        case .denied:
            permissionStatus.contacts = "Denied"
        case .restricted:
            permissionStatus.contacts = "Restricted"
        case .notDetermined:
            permissionStatus.contacts = "Not Determined"
        case .limited:
            permissionStatus.contacts = "Limited"
        @unknown default:
            permissionStatus.contacts = "Unknown"
        }
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized:
                    self.permissionStatus.notifications = "Authorized"
                case .denied:
                    self.permissionStatus.notifications = "Denied"
                case .notDetermined:
                    self.permissionStatus.notifications = "Not Determined"
                case .provisional:
                    self.permissionStatus.notifications = "Provisional"
                case .ephemeral:
                    self.permissionStatus.notifications = "Ephemeral"
                @unknown default:
                    self.permissionStatus.notifications = "Unknown"
                }
            }
        }
    }

    // MARK: - Permission Requesting

    func requestAllPermissions() async {
        guard !isRequestingPermissions else { return }

        await MainActor.run {
            isRequestingPermissions = true
            hasRequestedPermissions = true
        }

        print("🔐 Requesting all permissions for emergency safety features...")

        // Request permissions in logical order
        await requestNotificationPermission()
        await requestLocationPermission()
        await requestMotionPermission()
        await requestMicrophonePermission()
        await requestSpeechRecognitionPermission()
        await requestCameraPermission()
        await requestContactsPermission()

        await MainActor.run {
            isRequestingPermissions = false
            checkAllPermissions()
        }

        // Log final status
        print("📊 Permission Summary:")
        print("  Location: \(permissionStatus.location)")
        print("  Motion: \(permissionStatus.motion)")
        print("  Microphone: \(permissionStatus.microphone)")
        print("  Speech Recognition: \(permissionStatus.speechRecognition)")
        print("  Camera: \(permissionStatus.camera)")
        print("  Contacts: \(permissionStatus.contacts)")
        print("  Notifications: \(permissionStatus.notifications)")
    }

    private func requestNotificationPermission() async {
        guard permissionStatus.notifications == "Not Determined" else { return }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge, .criticalAlert]
            )
            await MainActor.run {
                permissionStatus.notifications = granted ? "Authorized" : "Denied"
            }
            print("📱 Notifications: \(granted ? "Granted" : "Denied")")
        } catch {
            print("❌ Notification permission error: \(error)")
        }
    }

    private func requestLocationPermission() async {
        guard permissionStatus.location == "Not Determined" else { return }

        return await withCheckedContinuation { continuation in
            locationManager.requestAlwaysAuthorization()

            // Wait for delegate callback
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                continuation.resume()
            }
        }
    }

    private func requestMotionPermission() async {
        guard permissionStatus.motion == "Not Determined" && CMMotionActivityManager.isActivityAvailable() else { return }

        return await withCheckedContinuation { continuation in
            motionActivityManager.startActivityUpdates(to: .main) { [weak self] (activity: CMMotionActivity?) in
                self?.motionActivityManager.stopActivityUpdates()

                DispatchQueue.main.async {
                    if activity != nil {
                        self?.permissionStatus.motion = "Authorized"
                        print("🏃‍♂️ Motion: Granted")
                    } else {
                        self?.permissionStatus.motion = "Denied"
                        print("🏃‍♂️ Motion: Denied")
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func requestMicrophonePermission() async {
        guard permissionStatus.microphone == "Not Determined" else { return }

        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.permissionStatus.microphone = granted ? "Authorized" : "Denied"
                    print("🎤 Microphone: \(granted ? "Granted" : "Denied")")
                    continuation.resume()
                }
            }
        }
    }

    private func requestSpeechRecognitionPermission() async {
        guard permissionStatus.speechRecognition == "Not Determined" else { return }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.permissionStatus.speechRecognition = status == .authorized ? "Authorized" : "Denied"
                    print("🗣️ Speech Recognition: \(status == .authorized ? "Granted" : "Denied")")
                    continuation.resume()
                }
            }
        }
    }

    private func requestCameraPermission() async {
        guard permissionStatus.camera == "Not Determined" else { return }

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            permissionStatus.camera = granted ? "Authorized" : "Denied"
        }
        print("📷 Camera: \(granted ? "Granted" : "Denied")")
    }

    private func requestContactsPermission() async {
        guard permissionStatus.contacts == "Not Determined" else { return }

        do {
            let granted = try await CNContactStore().requestAccess(for: .contacts)
            await MainActor.run {
                permissionStatus.contacts = granted ? "Authorized" : "Denied"
            }
            print("👥 Contacts: \(granted ? "Granted" : "Denied")")
        } catch {
            await MainActor.run {
                permissionStatus.contacts = "Denied"
            }
            print("❌ Contacts permission error: \(error)")
        }
    }

    // MARK: - Convenience Methods

    func showPermissionAlert() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        let alert = UIAlertController(
            title: "Emergency Safety Permissions",
            message: "Discreetly needs access to sensors and services to provide emergency safety features. Please enable permissions in Settings.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        alert.addAction(UIAlertAction(title: "Later", style: .cancel))

        window.rootViewController?.present(alert, animated: true)
    }

    func getPermissionSummary() -> [(String, String)] {
        return [
            ("Location", permissionStatus.location),
            ("Motion & Fitness", permissionStatus.motion),
            ("Microphone", permissionStatus.microphone),
            ("Speech Recognition", permissionStatus.speechRecognition),
            ("Camera", permissionStatus.camera),
            ("Contacts", permissionStatus.contacts),
            ("Notifications", permissionStatus.notifications)
        ]
    }
}

// MARK: - CLLocationManagerDelegate

extension PermissionManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationPermission()
        print("📍 Location permission changed: \(permissionStatus.location)")
    }
}