import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Flutter plugin for integrating with Apple WorkoutKit and HealthKit
class FlutterWorkoutBridge {
  static const MethodChannel _channel = MethodChannel('flutter_workout_bridge');

  /// Request necessary HealthKit permissions
  /// Returns true if permissions were granted
  static Future<bool> requestPermissions() async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final bool result = await _channel.invokeMethod('requestPermissions');
      return result;
    } on PlatformException {
      rethrow;
    }
  }

  /// Create and present a workout from JSON data
  /// The workout will open in Apple's native Workout app
  static Future<bool> createWorkoutFromJson(Map<String, dynamic> json) async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final bool result = await _channel.invokeMethod('createWorkoutFromJson', {
        'json': json,
      });
      return result;
    } on PlatformException {
      rethrow;
    }
  }

  /// Create and immediately present a workout preview from JSON data
  /// This will show the native WorkoutPreviewController
  static Future<Map<String, dynamic>> presentWorkout(
      Map<String, dynamic> json) async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final dynamic result = await _channel.invokeMethod('presentWorkout', {
        'json': json,
      });

      // Handle both bool and Map return types
      if (result is bool) {
        return {'success': result, 'message': 'Workout created successfully'};
      } else if (result is Map) {
        return Map<String, dynamic>.from(result);
      } else {
        return {'success': false, 'message': 'Unknown response type'};
      }
    } on PlatformException {
      rethrow;
    }
  }

  /// Get completed workouts from HealthKit
  /// [daysBack] - Number of days back to fetch workouts from
  /// Returns a list of workout data maps
  static Future<List<Map<String, dynamic>>> getCompletedWorkouts({
    int daysBack = 7,
  }) async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final List<dynamic> result =
          await _channel.invokeMethod('getCompletedWorkouts', {
        'daysBack': daysBack,
      });

      return result
          .map((dynamic workout) => Map<String, dynamic>.from(workout))
          .toList();
    } on PlatformException {
      rethrow;
    }
  }
}

/// Native WorkoutPreviewButton widget that shows Apple's workout preview
class WorkoutPreviewButton extends StatelessWidget {
  final double height;
  final Map<String, dynamic>? args;

  const WorkoutPreviewButton({
    super.key,
    this.height = 60.0,
    this.args,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) {
      return Container(
        height: height,
        child: const Center(
          child: Text('WorkoutPreviewButton is only available on iOS'),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: const UiKitView(
        viewType: 'workout_preview_button',
        creationParamsCodec: StandardMessageCodec(),
      ),
    );
  }
}

/// Helper class to build workout JSON structures
class WorkoutBuilder {
  final Map<String, dynamic> _workout = {};

  WorkoutBuilder(
    String name, {
    String activityType = 'running',
    String location = 'outdoor',
  }) {
    _workout['name'] = name;
    _workout['activityType'] = activityType;
    _workout['location'] = location;
  }

  /// Add a warmup step
  WorkoutBuilder addWarmup({
    String? name,
    String durationType = 'time',
    double? duration,
  }) {
    _workout['warmup'] = {
      'name': name ?? 'Warm Up',
      'durationType': durationType,
      if (duration != null) 'duration': duration,
    };
    return this;
  }

  /// Add an interval step
  WorkoutBuilder addInterval({
    required String name,
    String durationType = 'time',
    double? duration,
  }) {
    _workout['intervals'] ??= <Map<String, dynamic>>[];
    (_workout['intervals'] as List).add({
      'name': name,
      'durationType': durationType,
      if (duration != null) 'duration': duration,
    });
    return this;
  }

  /// Add a cooldown step
  WorkoutBuilder addCooldown({
    String? name,
    String durationType = 'time',
    double? duration,
  }) {
    _workout['cooldown'] = {
      'name': name ?? 'Cool Down',
      'durationType': durationType,
      if (duration != null) 'duration': duration,
    };
    return this;
  }

  /// Build and return the workout JSON
  Map<String, dynamic> build() => Map<String, dynamic>.from(_workout);
}

/// Workout activity types supported by HealthKit
class WorkoutActivityType {
  static const String running = 'running';
  static const String cycling = 'cycling';
  static const String walking = 'walking';
  static const String swimming = 'swimming';
  static const String hiking = 'hiking';
  static const String yoga = 'yoga';
  static const String strength = 'strength';
}

/// Workout location types
class WorkoutLocationType {
  static const String indoor = 'indoor';
  static const String outdoor = 'outdoor';
}

/// Duration types for workout steps
class DurationType {
  static const String time = 'time'; // Duration in seconds
  static const String distance = 'distance'; // Distance in meters
  static const String calories = 'calories'; // Calories to burn
  static const String open = 'open'; // Open-ended (no specific target)
}

/// Example workout models for common workout types
class WorkoutTemplates {
  /// Create a basic interval running workout
  static Map<String, dynamic> intervalRun({
    required String name,
    int warmupMinutes = 5,
    int intervalMinutes = 1,
    int restMinutes = 1,
    int intervals = 8,
    int cooldownMinutes = 5,
  }) {
    final builder =
        WorkoutBuilder(name, activityType: WorkoutActivityType.running)
            .addWarmup(
      durationType: DurationType.time,
      duration: warmupMinutes * 60.0,
    );

    // Add intervals
    for (int i = 0; i < intervals; i++) {
      builder.addInterval(
        name: 'Sprint ${i + 1}',
        durationType: DurationType.time,
        duration: intervalMinutes * 60.0,
      );

      if (i < intervals - 1) {
        // Don't add rest after the last interval
        builder.addInterval(
          name: 'Rest ${i + 1}',
          durationType: DurationType.time,
          duration: restMinutes * 60.0,
        );
      }
    }

    builder.addCooldown(
      durationType: DurationType.time,
      duration: cooldownMinutes * 60.0,
    );

    return builder.build();
  }

  /// Create a distance-based cycling workout
  static Map<String, dynamic> cyclingWorkout({
    required String name,
    double warmupDistance = 1000, // meters
    double mainDistance = 10000, // meters
    double cooldownDistance = 1000, // meters
  }) {
    return WorkoutBuilder(name, activityType: WorkoutActivityType.cycling)
        .addWarmup(
          durationType: DurationType.distance,
          duration: warmupDistance,
        )
        .addInterval(
          name: 'Main Ride',
          durationType: DurationType.distance,
          duration: mainDistance,
        )
        .addCooldown(
          durationType: DurationType.distance,
          duration: cooldownDistance,
        )
        .build();
  }

  /// Create a time-based yoga session
  static Map<String, dynamic> yogaSession({
    required String name,
    int durationMinutes = 30,
  }) {
    return WorkoutBuilder(name,
            activityType: WorkoutActivityType.yoga,
            location: WorkoutLocationType.indoor)
        .addInterval(
          name: 'Yoga Flow',
          durationType: DurationType.time,
          duration: durationMinutes * 60.0,
        )
        .build();
  }

  /// Create a calorie-burning strength workout
  static Map<String, dynamic> strengthWorkout({
    required String name,
    double calorieGoal = 300,
  }) {
    return WorkoutBuilder(name,
            activityType: WorkoutActivityType.strength,
            location: WorkoutLocationType.indoor)
        .addWarmup(
          durationType: DurationType.time,
          duration: 300, // 5 minutes
        )
        .addInterval(
          name: 'Strength Training',
          durationType: DurationType.calories,
          duration: calorieGoal,
        )
        .addCooldown(
          durationType: DurationType.time,
          duration: 300, // 5 minutes
        )
        .build();
  }
}
