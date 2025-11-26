//
//  HapticService.swift
//  discreetly
//
//  Service for haptic feedback communication
//  Relays information through phone vibrations (like Morse code)
//

import UIKit

final class HapticService {
    static let shared = HapticService()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    /// Simple success haptic
    func success() {
        notification.notificationOccurred(.success)
    }

    /// Simple error haptic
    func error() {
        notification.notificationOccurred(.error)
    }

    /// Simple warning haptic
    func warning() {
        notification.notificationOccurred(.warning)
    }

    /// Light tap
    func tapLight() {
        impactLight.impactOccurred()
    }

    /// Medium tap
    func tapMedium() {
        impactMedium.impactOccurred()
    }

    /// Heavy tap
    func tapHeavy() {
        impactHeavy.impactOccurred()
    }

    /// Relay a message through vibration patterns
    /// Uses a simple encoding: short vibration = dot, long vibration = dash
    func relayMessage(_ message: String, completion: (() -> Void)? = nil) {
        let pattern = encodeToMorsePattern(message)
        playPattern(pattern, completion: completion)
    }

    /// Relay a yes/no response
    func relayYesNo(isYes: Bool) {
        if isYes {
            // Two quick taps for "yes"
            tapMedium()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.tapMedium()
            }
        } else {
            // One long vibration for "no"
            tapHeavy()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.tapHeavy()
            }
        }
    }

    /// Relay a number (1-9) through vibration count
    func relayNumber(_ number: Int) {
        guard number > 0 && number <= 9 else { return }
        for i in 0..<number {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) {
                self.tapLight()
            }
        }
    }

    /// Three vibrations for call/text feedback
    func threeVibrations() {
        tapMedium()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.tapMedium()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.tapMedium()
        }
    }

    /// Custom pattern player
    private func playPattern(_ pattern: [VibrationUnit], completion: (() -> Void)? = nil) {
        guard !pattern.isEmpty else {
            completion?()
            return
        }

        var currentTime: TimeInterval = 0

        for unit in pattern {
            DispatchQueue.main.asyncAfter(deadline: .now() + currentTime) {
                switch unit {
                case .short:
                    self.tapLight()
                case .long:
                    self.tapHeavy()
                case .pause:
                    break // Just wait
                }
            }

            currentTime += unit.duration
        }

        // Call completion after all vibrations
        if let completion = completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + currentTime) {
                completion()
            }
        }
    }

    /// Simplified Morse code encoding (first 3 letters only for brevity)
    private func encodeToMorsePattern(_ text: String) -> [VibrationUnit] {
        let simplified = String(text.prefix(3)).uppercased()
        var pattern: [VibrationUnit] = []

        for char in simplified {
            let morse = morseCode(for: char)
            pattern.append(contentsOf: morse)
            pattern.append(.pause) // Pause between letters
        }

        return pattern
    }

    /// Simple Morse code mapping
    private func morseCode(for char: Character) -> [VibrationUnit] {
        switch char {
        case "A": return [.short, .long]
        case "B": return [.long, .short, .short, .short]
        case "C": return [.long, .short, .long, .short]
        case "D": return [.long, .short, .short]
        case "E": return [.short]
        case "F": return [.short, .short, .long, .short]
        case "G": return [.long, .long, .short]
        case "H": return [.short, .short, .short, .short]
        case "I": return [.short, .short]
        case "J": return [.short, .long, .long, .long]
        case "K": return [.long, .short, .long]
        case "L": return [.short, .long, .short, .short]
        case "M": return [.long, .long]
        case "N": return [.long, .short]
        case "O": return [.long, .long, .long]
        case "P": return [.short, .long, .long, .short]
        case "Q": return [.long, .long, .short, .long]
        case "R": return [.short, .long, .short]
        case "S": return [.short, .short, .short]
        case "T": return [.long]
        case "U": return [.short, .short, .long]
        case "V": return [.short, .short, .short, .long]
        case "W": return [.short, .long, .long]
        case "X": return [.long, .short, .short, .long]
        case "Y": return [.long, .short, .long, .long]
        case "Z": return [.long, .long, .short, .short]
        case "0": return [.long, .long, .long, .long, .long]
        case "1": return [.short, .long, .long, .long, .long]
        case "2": return [.short, .short, .long, .long, .long]
        case "3": return [.short, .short, .short, .long, .long]
        case "4": return [.short, .short, .short, .short, .long]
        case "5": return [.short, .short, .short, .short, .short]
        case "6": return [.long, .short, .short, .short, .short]
        case "7": return [.long, .long, .short, .short, .short]
        case "8": return [.long, .long, .long, .short, .short]
        case "9": return [.long, .long, .long, .long, .short]
        default: return [.pause]
        }
    }
}

// MARK: - Vibration Unit
enum VibrationUnit {
    case short
    case long
    case pause

    var duration: TimeInterval {
        switch self {
        case .short: return 0.15
        case .long: return 0.4
        case .pause: return 0.2
        }
    }
}
