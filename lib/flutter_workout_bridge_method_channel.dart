import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_workout_bridge_platform_interface.dart';

/// An implementation of [FlutterWorkoutBridgePlatform] that uses method channels.
class MethodChannelFlutterWorkoutBridge extends FlutterWorkoutBridgePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_workout_bridge');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
