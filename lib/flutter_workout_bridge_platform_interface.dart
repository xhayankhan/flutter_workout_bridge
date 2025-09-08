import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_workout_bridge_method_channel.dart';

abstract class FlutterWorkoutBridgePlatform extends PlatformInterface {
  /// Constructs a FlutterWorkoutBridgePlatform.
  FlutterWorkoutBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterWorkoutBridgePlatform _instance = MethodChannelFlutterWorkoutBridge();

  /// The default instance of [FlutterWorkoutBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterWorkoutBridge].
  static FlutterWorkoutBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterWorkoutBridgePlatform] when
  /// they register themselves.
  static set instance(FlutterWorkoutBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
