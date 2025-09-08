import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Flutter plugin for integrating with Apple WorkoutKit and HealthKit
class FlutterWorkoutBridge {
  static const MethodChannel _channel = MethodChannel('flutter_workout_bridge');

  /// Recursively convert any Map or List coming from a platform channel into
  /// JSON safe Dart structures with String keys.
  static dynamic _deepStringKeyed(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) {
        out[k?.toString() ?? 'null'] = _deepStringKeyed(v);
      });
      return out;
    } else if (value is List) {
      return value.map(_deepStringKeyed).toList();
    } else {
      return value;
    }
  }

  static Map<String, dynamic> _asStringMap(dynamic v) {
    final normalized = _deepStringKeyed(v);
    if (normalized is Map<String, dynamic>) return normalized;
    throw StateError('Expected Map<String, dynamic>, got ${v.runtimeType}');
  }

  static List<Map<String, dynamic>> _asListOfStringMaps(dynamic v) {
    final normalized = _deepStringKeyed(v);
    if (normalized is List) {
      return normalized
          .map<Map<String, dynamic>>((e) => _asStringMap(e))
          .toList();
    }
    throw StateError('Expected List<Map<String, dynamic>>, got ${v.runtimeType}');
  }

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

  /// Check if HealthKit permissions are granted for reading and writing data
  /// Returns a map with read and write permissions status
  static Future<Map<String, dynamic>> checkPermissions() async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final dynamic rawResult =
      await _channel.invokeMethod('checkPermissions');
      return _asStringMap(rawResult);
    } on PlatformException {
      rethrow;
    } catch (e) {
      print('Error in checkPermissions: $e');
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
      final bool result =
      await _channel.invokeMethod('createWorkoutFromJson', {
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
      final dynamic rawResult =
      await _channel.invokeMethod('presentWorkout', {
        'json': json,
      });

      return _asStringMap(rawResult);
    } on PlatformException {
      rethrow;
    } catch (e) {
      print('Error in presentWorkout: $e');
      rethrow;
    }
  }

  /// Get completed workouts from HealthKit with comprehensive data
  /// daysBack Number of days back to fetch workouts from default 90
  /// maxWorkouts Maximum number of workouts to return default 100
  /// Returns a list of detailed workout data
  static Future<List<WorkoutData>> getCompletedWorkouts({
    int daysBack = 90,
    int maxWorkouts = 100,
  }) async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final dynamic rawResult =
      await _channel.invokeMethod('getCompletedWorkouts', {
        'daysBack': daysBack,
      });

      final List<Map<String, dynamic>> items =
      _asListOfStringMaps(rawResult);

      return items.take(maxWorkouts).map(WorkoutData.fromJson).toList();
    } on PlatformException {
      rethrow;
    } catch (e) {
      print('Error in getCompletedWorkouts: $e');
      rethrow;
    }
  }

  /// Get raw completed workouts data for debugging or custom processing
  static Future<List<Map<String, dynamic>>> getCompletedWorkoutsRaw({
    int daysBack = 90,
  }) async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final dynamic rawResult =
      await _channel.invokeMethod('getCompletedWorkouts', {
        'daysBack': daysBack,
      });

      return _asListOfStringMaps(rawResult);
    } on PlatformException {
      rethrow;
    } catch (e) {
      print('Error in getCompletedWorkoutsRaw: $e');
      rethrow;
    }
  }

  /// Get scheduled workouts from WorkoutKit
  static Future<Map<String, dynamic>> getScheduledWorkouts() async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final dynamic rawResult =
      await _channel.invokeMethod('getScheduledWorkouts');
      return _asStringMap(rawResult);
    } on PlatformException {
      rethrow;
    } catch (e) {
      print('Error in getScheduledWorkouts: $e');
      rethrow;
    }
  }

  /// Clear all scheduled workouts
  static Future<Map<String, dynamic>> clearScheduledWorkouts() async {
    if (!Platform.isIOS) {
      throw PlatformException(
        code: 'PLATFORM_NOT_SUPPORTED',
        message: 'This plugin only supports iOS',
      );
    }

    try {
      final dynamic rawResult =
      await _channel.invokeMethod('clearScheduledWorkouts');
      return _asStringMap(rawResult);
    } on PlatformException {
      rethrow;
    } catch (e) {
      print('Error in clearScheduledWorkouts: $e');
      rethrow;
    }
  }
}

/// Comprehensive workout data model
class WorkoutData {
  final String uuid;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final Duration duration;
  final int workoutActivityType;
  final String sourceName;
  final String sourceVersion;
  final String device;

  /// Energy and Distance
  final double? totalEnergyBurned;
  final String? totalEnergyBurnedUnit;
  final double? totalDistance;
  final String? totalDistanceUnit;
  final double? averagePaceMinutesPerKm;
  final double? averageSpeedKmh;

  /// Weather data
  final int? weatherCondition;
  final double? weatherTemperature;
  final double? weatherHumidity;
  final bool? isIndoorWorkout;
  final double? elevationAscended;

  /// Complex data
  final WorkoutRoute? route;
  final HeartRateData? heartRate;
  final Map<String, WorkoutMetric> metrics;
  final List<WorkoutEvent> events;

  WorkoutData({
    required this.uuid,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.duration,
    required this.workoutActivityType,
    required this.sourceName,
    required this.sourceVersion,
    required this.device,
    this.totalEnergyBurned,
    this.totalEnergyBurnedUnit,
    this.totalDistance,
    this.totalDistanceUnit,
    this.averagePaceMinutesPerKm,
    this.averageSpeedKmh,
    this.weatherCondition,
    this.weatherTemperature,
    this.weatherHumidity,
    this.isIndoorWorkout,
    this.elevationAscended,
    this.route,
    this.heartRate,
    this.metrics = const {},
    this.events = const [],
  });

  factory WorkoutData.fromJson(Map<String, dynamic> json) {
    return WorkoutData(
      uuid: json['uuid'] ?? '',
      name: json['name'] ?? 'Unknown Workout',
      startDate: DateTime.tryParse(json['startDate'] ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['endDate'] ?? '') ?? DateTime.now(),
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      workoutActivityType: (json['workoutActivityType'] as num?)?.toInt() ?? 0,
      sourceName: json['sourceName'] ?? 'Unknown',
      sourceVersion: json['sourceVersion'] ?? 'Unknown',
      device: json['device'] ?? 'Unknown',
      totalEnergyBurned: (json['totalEnergyBurned'] as num?)?.toDouble(),
      totalEnergyBurnedUnit: json['totalEnergyBurnedUnit'],
      totalDistance: (json['totalDistance']??0 as num?)?.toDouble(),
      totalDistanceUnit: json['totalDistanceUnit'],
      averagePaceMinutesPerKm:
      (json['averagePaceMinutesPerKm'] as num?)?.toDouble(),
      averageSpeedKmh: (json['averageSpeedKmh'] as num?)?.toDouble(),
      weatherCondition: (json['weatherCondition'] as num?)?.toInt(),
      weatherTemperature: (json['weatherTemperature'] as num?)?.toDouble(),
      weatherHumidity: (json['weatherHumidity'] as num?)?.toDouble(),
      isIndoorWorkout: json['isIndoorWorkout'] as bool?,
      elevationAscended: (json['elevationAscended'] as num?)?.toDouble(),
      route: json['route'] != null
          ? WorkoutRoute.fromJson(
        Map<String, dynamic>.from(json['route']),
      )
          : WorkoutRoute(points: [RoutePoint(latitude: 0, longitude: 0, altitude: 0, timestamp: DateTime.timestamp(), horizontalAccuracy: 0, verticalAccuracy: 0)], totalPoints: 1),
      heartRate: json['heartRate'] != null
          ? HeartRateData.fromJson(
        Map<String, dynamic>.from(json['heartRate']),
      )
          : HeartRateData(averageHeartRate: 0, maxHeartRate: 0, minHeartRate: 0, sampleCount: 0, samples: [HeartRateSample(value: 0, timestamp: DateTime.timestamp(), endTimestamp: DateTime.timestamp())]),
      metrics: _parseMetrics(json['metrics']),
      events: _parseEvents(json['events']),
    );
  }

  static Map<String, WorkoutMetric> _parseMetrics(dynamic metricsJson) {
    if (metricsJson == null) return {};

    final Map<String, dynamic> metricsMap =
    Map<String, dynamic>.from(metricsJson);
    final Map<String, WorkoutMetric> result = {};

    metricsMap.forEach((key, value) {
      if (value != null) {
        result[key] = WorkoutMetric.fromJson(
          Map<String, dynamic>.from(value),
        );
      }
    });

    return result;
  }

  static List<WorkoutEvent> _parseEvents(dynamic eventsJson) {
    if (eventsJson == null) return [];

    final List<dynamic> eventsList = eventsJson as List<dynamic>;
    return eventsList
        .map((event) => WorkoutEvent.fromJson(
      Map<String, dynamic>.from(event),
    ))
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'duration': duration.inSeconds,
      'workoutActivityType': workoutActivityType,
      'sourceName': sourceName,
      'sourceVersion': sourceVersion,
      'device': device,
      'totalEnergyBurned': totalEnergyBurned,
      'totalEnergyBurnedUnit': totalEnergyBurnedUnit,
      'totalDistance': totalDistance,
      'totalDistanceUnit': totalDistanceUnit,
      'averagePaceMinutesPerKm': averagePaceMinutesPerKm,
      'averageSpeedKmh': averageSpeedKmh,
      'weatherCondition': weatherCondition,
      'weatherTemperature': weatherTemperature,
      'weatherHumidity': weatherHumidity,
      'isIndoorWorkout': isIndoorWorkout,
      'elevationAscended': elevationAscended,
      'route': route?.toJson(),
      'heartRate': heartRate?.toJson(),
      'metrics': Map.fromEntries(
        metrics.entries.map((e) => MapEntry(e.key, e.value.toJson())),
      ),
      'events': events.map((e) => e.toJson()).toList(),
    };
  }
}

/// Workout route data GPS polypoints
class WorkoutRoute {
  final List<RoutePoint> points;
  final int totalPoints;

  WorkoutRoute({
    required this.points,
    required this.totalPoints,
  });

  factory WorkoutRoute.fromJson(Map<String, dynamic> json) {
    final List<dynamic> pointsList = json['points'] ?? [];
    return WorkoutRoute(
      points: pointsList
          .map((point) =>
          RoutePoint.fromJson(Map<String, dynamic>.from(point)))
          .toList(),
      totalPoints: (json['totalPoints'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'points': points.map((p) => p.toJson()).toList(),
      'totalPoints': totalPoints,
    };
  }
}

/// Individual GPS point in a workout route
class RoutePoint {
  final double latitude;
  final double longitude;
  final double altitude;
  final DateTime timestamp;
  final double horizontalAccuracy;
  final double verticalAccuracy;
  final double? speed;
  final double? course;

  RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.timestamp,
    required this.horizontalAccuracy,
    required this.verticalAccuracy,
    this.speed,
    this.course,
  });

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: (json['altitude'] as num).toDouble(),
      timestamp:
      DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      horizontalAccuracy:
      (json['horizontalAccuracy'] as num).toDouble(),
      verticalAccuracy: (json['verticalAccuracy'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      course: (json['course'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'timestamp': timestamp.toIso8601String(),
      'horizontalAccuracy': horizontalAccuracy,
      'verticalAccuracy': verticalAccuracy,
      'speed': speed,
      'course': course,
    };
  }
}

/// Heart rate data for a workout
class HeartRateData {
  final double averageHeartRate;
  final double maxHeartRate;
  final double minHeartRate;
  final int sampleCount;
  final List<HeartRateSample> samples;

  HeartRateData({
    required this.averageHeartRate,
    required this.maxHeartRate,
    required this.minHeartRate,
    required this.sampleCount,
    required this.samples,
  });

  factory HeartRateData.fromJson(Map<String, dynamic> json) {
    final List<dynamic> samplesList = json['samples'] ?? [];
    return HeartRateData(
      averageHeartRate: (json['averageHeartRate'] as num?)?.toDouble() ?? 0.0,
      maxHeartRate: (json['maxHeartRate'] as num?)?.toDouble() ?? 0.0,
      minHeartRate: (json['minHeartRate'] as num?)?.toDouble() ?? 0.0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      samples: samplesList
          .map((sample) => HeartRateSample.fromJson(
        Map<String, dynamic>.from(sample),
      ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'averageHeartRate': averageHeartRate,
      'maxHeartRate': maxHeartRate,
      'minHeartRate': minHeartRate,
      'sampleCount': sampleCount,
      'samples': samples.map((s) => s.toJson()).toList(),
    };
  }
}

/// Individual heart rate sample
class HeartRateSample {
  final double value;
  final DateTime timestamp;
  final DateTime endTimestamp;

  HeartRateSample({
    required this.value,
    required this.timestamp,
    required this.endTimestamp,
  });

  factory HeartRateSample.fromJson(Map<String, dynamic> json) {
    return HeartRateSample(
      value: (json['value'] as num).toDouble(),
      timestamp:
      DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      endTimestamp:
      DateTime.tryParse(json['endTimestamp'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'endTimestamp': endTimestamp.toIso8601String(),
    };
  }
}

/// Workout metric data steps distance energy etc
class WorkoutMetric {
  final double total;
  final double average;
  final String unit;
  final int sampleCount;

  WorkoutMetric({
    required this.total,
    required this.average,
    required this.unit,
    required this.sampleCount,
  });

  factory WorkoutMetric.fromJson(Map<String, dynamic> json) {
    return WorkoutMetric(
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      average: (json['average'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] ?? '',
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'average': average,
      'unit': unit,
      'sampleCount': sampleCount,
    };
  }
}

/// Workout event lap pause resume etc
class WorkoutEvent {
  final String type;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  WorkoutEvent({
    required this.type,
    required this.timestamp,
    this.metadata,
  });

  factory WorkoutEvent.fromJson(Map<String, dynamic> json) {
    return WorkoutEvent(
      type: json['type'] ?? 'unknown',
      timestamp:
      DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}

/// Utility class for filtering and analyzing workout data
class WorkoutAnalyzer {
  /// Filter workouts by activity type
  static List<WorkoutData> filterByActivityType(
      List<WorkoutData> workouts,
      List<int> activityTypes,
      ) {
    return workouts
        .where((workout) => activityTypes.contains(workout.workoutActivityType))
        .toList();
  }

  /// Filter workouts by date range
  static List<WorkoutData> filterByDateRange(
      List<WorkoutData> workouts,
      DateTime startDate,
      DateTime endDate,
      ) {
    return workouts
        .where((workout) =>
    workout.startDate.isAfter(startDate) &&
        workout.startDate.isBefore(endDate))
        .toList();
  }

  /// Get workouts with GPS data
  static List<WorkoutData> getWorkoutsWithGPS(
      List<WorkoutData> workouts) {
    return workouts
        .where((workout) =>
    workout.route != null && workout.route!.points.isNotEmpty)
        .toList();
  }

  /// Calculate total distance for a set of workouts
  static double getTotalDistance(List<WorkoutData> workouts) {
    return workouts.fold(
        0.0, (sum, workout) => sum + (workout.totalDistance ?? 0.0));
  }

  /// Calculate total calories burned for a set of workouts
  static double getTotalCalories(List<WorkoutData> workouts) {
    return workouts.fold(
        0.0, (sum, workout) => sum + (workout.totalEnergyBurned ?? 0.0));
  }

  /// Calculate total workout time
  static Duration getTotalDuration(List<WorkoutData> workouts) {
    return workouts.fold(Duration.zero, (sum, workout) => sum + workout.duration);
  }

  /// Get average pace for running workouts minutes per km
  static double? getAveragePace(List<WorkoutData> workouts) {
    final runningWorkouts =
    workouts.where((w) => w.averagePaceMinutesPerKm != null).toList();
    if (runningWorkouts.isEmpty) return null;

    final totalPace = runningWorkouts.fold(
        0.0, (sum, w) => sum + w.averagePaceMinutesPerKm!);
    return totalPace / runningWorkouts.length;
  }

  /// Get average heart rate across workouts
  static double? getAverageHeartRate(List<WorkoutData> workouts) {
    final workoutsWithHR =
    workouts.where((w) => w.heartRate != null).toList();
    if (workoutsWithHR.isEmpty) return null;

    final totalHR = workoutsWithHR.fold(
        0.0, (sum, w) => sum + w.heartRate!.averageHeartRate);
    return totalHR / workoutsWithHR.length;
  }
}

/// Keep existing classes for backward compatibility
class WorkoutPreviewButton extends StatelessWidget {
  final double height;
  final Map<String, dynamic>? args;

  const WorkoutPreviewButton({
    Key? key,
    this.height = 60.0,
    this.args,
  }) : super(key: key);

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

/// Keep existing helper classes
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

  Map<String, dynamic> build() => Map<String, dynamic>.from(_workout);
}

class WorkoutActivityType {
  static const String running = 'running';
  static const String cycling = 'cycling';
  static const String walking = 'walking';
  static const String swimming = 'swimming';
  static const String hiking = 'hiking';
  static const String yoga = 'yoga';
  static const String strength = 'strength';
}

class WorkoutLocationType {
  static const String indoor = 'indoor';
  static const String outdoor = 'outdoor';
}

class DurationType {
  static const String time = 'time';
  static const String distance = 'distance';
  static const String calories = 'calories';
  static const String open = 'open';
}

class WorkoutTemplates {
  static Map<String, dynamic> intervalRun({
    required String name,
    int warmupMinutes = 5,
    int intervalMinutes = 1,
    int restMinutes = 1,
    int intervals = 8,
    int cooldownMinutes = 5,
  }) {
    final builder = WorkoutBuilder(name,
        activityType: WorkoutActivityType.running)
      ..addWarmup(
        durationType: DurationType.time,
        duration: warmupMinutes * 60.0,
      );

    for (int i = 0; i < intervals; i++) {
      builder.addInterval(
        name: 'Sprint ${i + 1}',
        durationType: DurationType.time,
        duration: intervalMinutes * 60.0,
      );

      if (i < intervals - 1) {
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

  static Map<String, dynamic> cyclingWorkout({
    required String name,
    double warmupDistance = 1000,
    double mainDistance = 10000,
    double cooldownDistance = 1000,
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

  static Map<String, dynamic> strengthWorkout({
    required String name,
    double calorieGoal = 300,
  }) {
    return WorkoutBuilder(name,
        activityType: WorkoutActivityType.strength,
        location: WorkoutLocationType.indoor)
        .addWarmup(
      durationType: DurationType.time,
      duration: 300,
    )
        .addInterval(
      name: 'Strength Training',
      durationType: DurationType.calories,
      duration: calorieGoal,
    )
        .addCooldown(
      durationType: DurationType.time,
      duration: 300,
    )
        .build();
  }
}
