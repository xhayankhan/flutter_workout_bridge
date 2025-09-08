Pod::Spec.new do |s|
s.name             = 'flutter_workout_bridge'
s.version = '1.0.3'
s.summary          = 'A Flutter plugin for integrating with Apple WorkoutKit and HealthKit.'
s.description      = <<-DESC
        A comprehensive Flutter plugin that provides a bridge to Apple's WorkoutKit and HealthKit frameworks,
allowing you to create custom workouts, schedule them to Apple Watch, and retrieve detailed workout data.
DESC
        s.homepage         = 'https://github.com/xhayankhan/flutter_workout_bridge'
s.license          = { :file => '../LICENSE' }
s.author           = { 'Shayan Khan' => 'shayaniqbal515@gmail.com' }
s.source           = { :path => '.' }

# Include Swift files from Classes directory
s.source_files = 'Classes/**/*'
s.dependency 'Flutter'
s.platform = :ios, '17.0'

# Swift configuration
s.pod_target_xcconfig = {
        'DEFINES_MODULE' => 'YES',
        'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
}
s.swift_version = '5.0'

# Required frameworks - include all necessary ones
s.frameworks = 'UIKit', 'HealthKit', 'WorkoutKit', 'SwiftUI'

# Deployment target
s.ios.deployment_target = '17.0'
end