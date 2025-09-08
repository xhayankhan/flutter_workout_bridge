# Flutter WorkoutBridge

A comprehensive Flutter plugin for integrating with Apple WorkoutKit and HealthKit, enabling you to create custom workouts, schedule them to Apple Watch, and retrieve detailed workout data.

## Features

- ✅ Create custom structured workouts with intervals, warmup, and cooldown
- ⌚ Schedule workouts directly to Apple Watch via WorkoutKit
- 📊 Retrieve comprehensive workout data from HealthKit
- 🗺️ Access GPS route data and heart rate information
- 🔐 Handle HealthKit permissions seamlessly
- 📱 Native iOS integration with SwiftUI preview components

## Requirements

- iOS 17.0+
- Xcode 15+
- Flutter 3.0+
- Physical iPhone and Apple Watch for testing

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  flutter_workout_bridge: ^1.0.0
```

## Setup

### iOS Permissions

Add these permissions to your `ios/Runner/Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>This app needs access to read your workout data.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>This app needs access to save workout data.</string>
```

### HealthKit Entitlement

Enable HealthKit in your iOS project:
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select your project target
3. Go to "Signing & Capabilities"
4. Add "HealthKit" capability

## Quick Start

```dart
import 'package:flutter_workout_bridge/flutter_workout_bridge.dart';

// Request permissions
bool hasPermissions = await FlutterWorkoutBridge.requestPermissions();

// Create a workout
Map<String, dynamic> workout = WorkoutTemplates.intervalRun(
  name: "Morning Intervals",
  warmupMinutes: 5,
  intervalMinutes: 2,
  restMinutes: 1,
  intervals: 8,
  cooldownMinutes: 5,
);

// Schedule to Apple Watch
Map<String, dynamic> result = await FlutterWorkoutBridge.presentWorkout(workout);

// Get completed workouts
List<Map<String, dynamic>> workouts = await FlutterWorkoutBridge.getCompletedWorkouts(daysBack: 30);
```

## API Reference

### Core Methods

#### `requestPermissions()`
Request HealthKit permissions from the user.

#### `presentWorkout(Map<String, dynamic> workout)`
Schedule a workout to Apple Watch and show it in the Workout app.

#### `getCompletedWorkouts({int daysBack = 7})`
Retrieve workout data from HealthKit.

### Workout Templates

Pre-built workout templates for common activities:

```dart
// Interval running workout
WorkoutTemplates.intervalRun(name: "Sprint Intervals");

// Cycling workout
WorkoutTemplates.cyclingWorkout(name: "Morning Ride");

// Yoga session
WorkoutTemplates.yogaSession(name: "Evening Flow");

// Strength training
WorkoutTemplates.strengthWorkout(name: "Upper Body");
```

### Custom Workout Builder

```dart
final workout = WorkoutBuilder("Custom Run")
    .addWarmup(durationType: DurationType.time, duration: 300)
    .addInterval(name: "Main Set", durationType: DurationType.distance, duration: 5000)
    .addCooldown(durationType: DurationType.time, duration: 300)
    .build();
```

## Platform Support

| Feature | iOS | Android |
|---------|-----|---------|
| Workout Creation | ✅ | ❌ |
| Apple Watch Integration | ✅ | ❌ |
| HealthKit Data | ✅ | ❌ |

*Note: This plugin is iOS-only due to its integration with Apple's WorkoutKit and HealthKit frameworks.*

## Example App

See the `/example` folder for a complete implementation showing:
- Permission handling
- Workout creation and scheduling
- Data visualization
- Error handling

## Troubleshooting

### Common Issues

**Workout not appearing on Apple Watch:**
- Ensure iPhone and Watch are paired and nearby
- Check that both devices have sufficient battery
- Verify WorkoutKit permissions are granted

**HealthKit permission denied:**
- Guide users to Settings > Privacy & Security > Health
- Explain why permissions are needed
- Handle graceful fallbacks

**Build errors:**
- Ensure minimum iOS 17.0 deployment target
- Verify HealthKit capability is enabled
- Check that all required frameworks are linked

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our GitHub repository.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

---

## Author

<div align="center">
  <img src="https://github.com/xhayankhan.png" alt="Shayan Khan" width="100" height="100" style="border-radius: 50%;">
  <h3>Shayan Khan</h3>


[![GitHub](https://img.shields.io/badge/GitHub-xhayankhan-black?style=flat&logo=github)](https://github.com/xhayankhan)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-shayan--flutter--dev-blue?style=flat&logo=linkedin)](https://www.linkedin.com/in/shayan-flutter-dev/)

  <p><em>Building bridges between Flutter and native iOS capabilities</em></p>
</div>