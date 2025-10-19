//
//  ContentView.swift
//  discreetly-watch Watch App
//
//  Created by Arya Gummadi on 10/19/25.
//

import SwiftUI
import WatchConnectivity
internal import Combine

struct ContentView: View {
    @StateObject private var watchConnectivity = WatchConnectivityManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("Discreetly")
                .font(.headline)
                .foregroundColor(.primary)

            Button(action: {
                triggerSOS()
            }) {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(watchConnectivity.isSystemEnabled ? .white : .gray)

                    Text("SOS")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(watchConnectivity.isSystemEnabled ? .white : .gray)
                }
                .frame(width: 100, height: 100)
                .background(
                    Circle()
                        .fill(watchConnectivity.isSystemEnabled ? Color.red : Color.gray.opacity(0.3))
                )
            }
            .disabled(!watchConnectivity.isSystemEnabled)
            .buttonStyle(PlainButtonStyle())

            Text(watchConnectivity.isSystemEnabled ? "System Active" : "System Inactive")
                .font(.caption)
                .foregroundColor(watchConnectivity.isSystemEnabled ? .green : .gray)
        }
        .padding()
    }

    private func triggerSOS() {
        guard watchConnectivity.isSystemEnabled else { return }

        // Haptic feedback
        WKInterfaceDevice.current().play(.notification)

        // Send trigger message to iOS app
        watchConnectivity.triggerSOS()
    }
}

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isSystemEnabled = false

    override init() {
        super.init()

        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func triggerSOS() {
        guard WCSession.default.isReachable else {
            print("❌ iOS app not reachable")
            return
        }

        let message = ["action": "triggerSOS"]
        WCSession.default.sendMessage(message, replyHandler: { response in
            print("✅ SOS trigger sent successfully: \(response)")
        }) { error in
            print("❌ Failed to send SOS trigger: \(error)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("❌ Watch session activation failed: \(error)")
        } else {
            print("✅ Watch session activated with state: \(activationState.rawValue)")

            // Request initial system state from iOS app
            if activationState == .activated && session.isReachable {
                let message = ["action": "requestSystemState"]
                session.sendMessage(message, replyHandler: { response in
                    DispatchQueue.main.async {
                        if let isEnabled = response["isSystemEnabled"] as? Bool {
                            self.isSystemEnabled = isEnabled
                            print("📱 Got initial system state: \(isEnabled)")
                        }
                    }
                }) { error in
                    print("❌ Failed to request initial system state: \(error)")
                }
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("📱 Received application context: \(applicationContext)")
        DispatchQueue.main.async {
            if let isEnabled = applicationContext["isSystemEnabled"] as? Bool {
                self.isSystemEnabled = isEnabled
                print("📱 Updated system state to: \(isEnabled)")
            } else {
                print("❌ No isSystemEnabled found in application context")
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // Handle any additional messages from iOS app if needed
        print("📱 Received message from iOS: \(message)")
    }
}

#Preview {
    ContentView()
}
