import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_workout_bridge/flutter_workout_bridge.dart';

void main() {
  runApp(const WorkoutBridgeExampleApp());
}

class WorkoutBridgeExampleApp extends StatelessWidget {
  const WorkoutBridgeExampleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkoutBridge Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const WorkoutBridgeHomePage(),
    );
  }
}

class WorkoutBridgeHomePage extends StatefulWidget {
  const WorkoutBridgeHomePage({Key? key}) : super(key: key);

  @override
  State<WorkoutBridgeHomePage> createState() => _WorkoutBridgeHomePageState();
}

class _WorkoutBridgeHomePageState extends State<WorkoutBridgeHomePage> {
  bool _permissionsGranted = false;
  bool _isLoading = false;
  String _statusMessage = 'Ready to start';
  List<WorkoutData> _completedWorkouts = [];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking permissions...';
    });

    try {
      final workouts = await FlutterWorkoutBridge.checkPermissions();
      print('PERMISSIONS $workouts');

      // ( workouts['readDetails']['HKWorkoutTypeIdentifier']=='denied'|| workouts['writeDetails']['HKWorkoutTypeIdentifier']=='denied')||( workouts['readDetails']['HKWorkoutTypeIdentifier']=='notDetermined'|| workouts['writeDetails']['HKWorkoutTypeIdentifier']=='notDetermined')
      // Check specific permission keys like your controller does
      final readWorkoutPermission = workouts['readDetails']?['HKWorkoutTypeIdentifier'];
      final writeWorkoutPermission = workouts['writeDetails']?['HKWorkoutTypeIdentifier'];

      // Use same logic as your controller
      if ((readWorkoutPermission == 'denied' || writeWorkoutPermission == 'denied') ||
          (readWorkoutPermission == 'notDetermined' || writeWorkoutPermission == 'notDetermined')) {

        setState(() {
          _permissionsGranted = false;
          log('PERMISSION ${_permissionsGranted}');
          _statusMessage = 'Permissions needed - some are denied or not determined';
        });

        if (readWorkoutPermission == 'denied' || writeWorkoutPermission == 'denied') {
          _showPermissionDialog();
        }
      } else {
        setState(() {
          _permissionsGranted = true;
          log('PERMISSION GRANTED ${_permissionsGranted}');
          _statusMessage = 'Permissions already granted';
        });

        // Load workouts if permissions are good
        await _loadCompletedWorkouts();
      }

    } catch (e) {
      print('ERROR while checking permissions: $e');
      setState(() {
        _permissionsGranted = false;
        _statusMessage = 'Permissions needed - Tap "Request Permissions"';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Request permissions using controller approach
  Future<void> _requestPermissions() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Requesting permissions...';
    });

    try {
      // Request HealthKit permissions through the bridge
      final granted = await FlutterWorkoutBridge.requestPermissions();

      if (granted) {
        setState(() {
          _statusMessage = 'Permissions granted successfully!';
        });


      } else {
        setState(() {
          _permissionsGranted = false;
          _statusMessage = 'Permissions denied. Some features may not work.';
        });
        _showPermissionDialog();
      }

    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = 'Permission error: ${e.message}';
      });
      print('Permission error: $e');
    } catch (e) {
      setState(() {
        _statusMessage = 'Unexpected error: $e';
      });
      print('Unexpected error in requestPermissions: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Enhanced permission dialog matching controller style
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
            'Your Apple Watch requires permissions to work with this app. '
                'Please accept all required permissions to continue with Apple Watch.\n\n'
                'Go to  Settings > Apps > Health > Data Access & Devices > '
                'WorkoutBridge Example > Turn On All'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Load completed workouts after permissions are granted
              await _loadCompletedWorkouts();

              // Recheck permissions to update UI properly
              await _checkPermissions();
              // _requestPermissions();
            },
            child: const Text('Request Permissions'),
          ),
        ],
      ),
    );
  }

  /// Load completed workouts from HealthKit
  Future<void> _loadCompletedWorkouts() async {
    if (!_permissionsGranted) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Loading completed workouts...';
    });

    try {
      final workouts = await FlutterWorkoutBridge.getCompletedWorkouts(daysBack: 30);

      setState(() {
        _completedWorkouts = workouts;
        _statusMessage = 'Loaded ${workouts.length} workout(s) from last 30 days';
      });
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = 'Error loading workouts: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error loading workouts: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Create and send a sample workout to Apple Watch
  Future<void> _createSampleWorkout() async {
    log('PERMISSION WHILE CREATING WORKOUT ${_permissionsGranted}');
    if (_permissionsGranted==false) {
      _showPermissionDialog();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating workout...';
    });

    try {
      // Create a sample interval running workout
      final workout = WorkoutTemplates.intervalRun(
        name: "Example Interval Run",
        warmupMinutes: 5,
        intervalMinutes: 2,
        restMinutes: 1,
        intervals: 6,
        cooldownMinutes: 5,
      );

      // Add unique identifier
      workout['uuid'] = '${DateTime.now().microsecondsSinceEpoch}';

      final result = await FlutterWorkoutBridge.presentWorkout(workout);

      setState(() {
        _statusMessage = result['success'] == true
            ? 'Workout scheduled! Check your Apple Watch Workout app.'
            : 'Failed to schedule workout: ${result['message'] ?? 'Unknown error'}';
      });

      if (result['success'] == true) {
        _showWorkoutScheduledDialog(result);
      }
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = 'Error creating workout: ${e.message}';
      });
      _showErrorDialog('Workout Error', e.message ?? 'Failed to create workout');
    } catch (e) {
      setState(() {
        _statusMessage = 'Error creating workout: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Create a custom cycling workout
  Future<void> _createCyclingWorkout() async {
    if (!_permissionsGranted) {
      _showPermissionDialog();
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating cycling workout...';
    });

    try {
      final workout = WorkoutTemplates.cyclingWorkout(
        name: "Morning Cycling Session",
        warmupDistance: 1000, // 1km warmup
        mainDistance: 15000,  // 15km main ride
        cooldownDistance: 1000, // 1km cooldown
      );

      workout['uuid'] = '${DateTime.now().microsecondsSinceEpoch}';

      final result = await FlutterWorkoutBridge.presentWorkout(workout);

      setState(() {
        _statusMessage = result['success'] == true
            ? 'Cycling workout scheduled!'
            : 'Failed to schedule cycling workout';
      });

      if (result['success'] == true) {
        _showWorkoutScheduledDialog(result);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error creating cycling workout: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  /// Show error dialog
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show workout scheduled success dialog
  void _showWorkoutScheduledDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout Scheduled!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Workout: ${result['workoutName'] ?? 'Custom Workout'}'),
            const SizedBox(height: 8),
            const Text('Instructions:'),
            const SizedBox(height: 4),
            const Text(
              '1. Open Workout app on Apple Watch\n'
                  '2. Scroll to bottom to find your workout\n'
                  '3. Tap to start when ready',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Scheduled: ${DateTime.now().add(const Duration(minutes: 5))}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WorkoutBridge Example'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _permissionsGranted ? Icons.check_circle : Icons.warning,
                          color: _permissionsGranted ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Status',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_statusMessage),
                    if (_isLoading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Permission Actions
            if (!_permissionsGranted) ...[
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _requestPermissions,
                icon: const Icon(Icons.security),
                label: const Text('Request Permissions'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
            ],

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _checkPermissions,
              icon: const Icon(Icons.refresh),
              label: const Text('Check Permissions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 16),

            // Workout Actions
            if (_permissionsGranted) ...[
              const Text(
                'Create Workouts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              ElevatedButton.icon(
                onPressed: _isLoading ? null : _createSampleWorkout,
                icon: const Icon(Icons.directions_run),
                label: const Text('Create Interval Run'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),

              const SizedBox(height: 8),

              ElevatedButton.icon(
                onPressed: _isLoading ? null : _createCyclingWorkout,
                icon: const Icon(Icons.directions_bike),
                label: const Text('Create Cycling Workout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),

              const SizedBox(height: 16),

              // Data Actions
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadCompletedWorkouts,
                icon: const Icon(Icons.history),
                label: const Text('Load Recent Workouts'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Workouts List
            if (_completedWorkouts.isNotEmpty) ...[
              const Text(
                'Recent Workouts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: ListView.builder(
                  itemCount: _completedWorkouts.length,
                  itemBuilder: (context, index) {
                    final workout = _completedWorkouts[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getWorkoutColor(workout.workoutActivityType ?? 0),
                          child: Icon(
                            _getWorkoutIcon(workout.totalDistance?.toInt() ?? 0),
                            color: Colors.white,
                          ),
                        ),
                        title: Text(workout.name ?? 'Unknown Workout'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${((workout.duration.inMinutes ?? 0) / 60).toInt()} min • ${((workout.totalDistance ?? 0) / 1000).toStringAsFixed(1)} km',
                            ),
                            Text(
                              workout.startDate.toString() ?? '',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: workout.totalEnergyBurned!= null
                            ? Text('${(workout.totalEnergyBurned as double).toInt()} kcal')
                            : null,
                        onTap: () => _showWorkoutDetails(workout),
                      ),
                    );
                  },
                ),
              ),
            ] else if (_permissionsGranted && !_isLoading) ...[
              const Center(
                child: Text(
                  'No workouts found.\nTry creating a workout first!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getWorkoutColor(int activityType) {
    // Map HKWorkoutActivityType values to colors
    switch (activityType) {
      case 37: return Colors.red; // Running
      case 13: return Colors.green; // Cycling
      case 52: return Colors.blue; // Walking
      case 46: return Colors.teal; // Swimming
      default: return Colors.grey;
    }
  }

  IconData _getWorkoutIcon(int activityType) {
    switch (activityType) {
      case 37: return Icons.directions_run;
      case 13: return Icons.directions_bike;
      case 52: return Icons.directions_walk;
      case 46: return Icons.pool;
      default: return Icons.fitness_center;
    }
  }

  void _showWorkoutDetails(WorkoutData workout) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(workout.name ?? 'Workout Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Duration', '${((workout.duration.inMinutes ?? 0)).toInt()} minutes'),
              if (workout.totalDistance!= null)
                _buildDetailRow('Distance', '${((workout.totalDistance as double) / 1000).toStringAsFixed(2)} km'),
              if (workout.totalEnergyBurned != null)
                _buildDetailRow('Calories', '${(workout.totalEnergyBurned as double).toInt()} kcal'),
              _buildDetailRow('Source', workout.sourceName ?? 'Unknown'),
              _buildDetailRow('Device', workout.device ?? 'Unknown'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}