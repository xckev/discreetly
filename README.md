# Discreetly

A comprehensive iOS safety app designed to provide discreet emergency assistance and safety monitoring for iOS and Apple Watch.

## Features

### Emergency Response System
- **Distress Calls**: Automated emergency calling with configurable contacts
- **Text Messaging**: SMS alerts to emergency contacts with location data
- **Covert Calling**: Discrete emergency calls that appear as normal phone calls
- **AI-Powered Assistance**: Integration with Claude AI for emergency guidance and Ultravox for voice interaction

### Trigger Methods
- **Action Button**: Manual activation via hardware button
- **Voice Trigger Words**: Hands-free activation using speech recognition
- **Motion Detection**: Automatic triggering based on device movement patterns
- **Health Monitoring**: Apple Watch integration with heart rate and respiratory monitoring
- **Delay Triggers**: Timed activation with cancellation options

### Safety Monitoring
- **Neighborhood Safety**: Location-based safety monitoring and alerts
- **Background Sensor Monitoring**: Continuous monitoring of device sensors
- **Apple Watch Integration**: Companion app with health-based emergency detection
- **Location Services**: Real-time location tracking and sharing

### Contact Management
- **Emergency Contacts**: Manage multiple emergency contacts with relationship tracking
- **Primary Contact System**: Designate primary emergency contacts
- **Native iOS Integration**: Seamless integration with iOS Contacts app

## Technical Implementation

### Core Services
- **PermissionManager**: Handles all app permissions (location, health, notifications, microphone)
- **MotionDetectionService**: Processes accelerometer and gyroscope data for movement detection
- **HealthKitService**: Integrates with Apple HealthKit for health data monitoring
- **LocationService**: Manages GPS tracking and location-based features
- **TwilioService**: Handles emergency calling functionality
- **TextbeltClient**: Manages SMS messaging capabilities

### AI Integration
- **ClaudeService**: Claude AI integration for emergency assistance
- **UltravoxService**: Voice AI service for hands-free interaction
- **AIAgentService**: Orchestrates AI-powered emergency response

### Apple Watch Support
- **WatchConnectivityService**: Bidirectional communication with Apple Watch
- **Health Triggers**: Watch-based health monitoring for emergency detection
- **Standalone Watch App**: Independent emergency functionality on Apple Watch

### Background Processing
- **BackgroundSensorMonitor**: Continuous sensor data collection
- **Emergency Action Processing**: Background task handling for emergency scenarios
- **Notification System**: Local and push notification management

## Privacy & Security

- All personal data stored locally on device
- Health data processed through Apple's secure HealthKit framework
- Location data only shared during emergency situations
- Voice processing handled securely through integrated AI services

## Requirements

- iOS 15.0+
- Apple Watch (optional but recommended)
- Location Services permission
- Microphone permission for voice features
- HealthKit permission for health monitoring
- Background App Refresh enabled

## Getting Started

1. Install the app on your iOS device
2. Complete the initial setup and permission requests
3. Configure your emergency contacts
4. Set up your preferred trigger methods
5. Test the system to ensure proper functionality

## Emergency Actions

The app supports configurable emergency actions that can be triggered through multiple methods:

- **Distress Call**: Places an emergency call to designated contacts
- **Text Message**: Sends location and emergency information via SMS
- **Ask Claude AI**: Provides AI-powered emergency guidance
- **Covert Call**: Initiates discrete emergency communication

Each action can be customized with specific triggers, delays, and contact preferences to match individual safety needs.