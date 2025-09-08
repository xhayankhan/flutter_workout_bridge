import Flutter
import UIKit
import WorkoutKit
import HealthKit
import Foundation
import SwiftUI

// MARK: - Supporting Types and Enums

enum WorkoutStepType: String {
    case warmup = "warmup"
    case interval = "interval"
    case cooldown = "cooldown"
}

enum WorkoutError: Error {
    case invalidWorkoutData(String)

    var localizedDescription: String {
        switch self {
        case .invalidWorkoutData(let message):
            return "Invalid workout data: \(message)"
        }
    }
}

// MARK: - Main Plugin Class

public class FlutterWorkoutBridgePlugin: NSObject, FlutterPlugin {

    private let healthStore = HKHealthStore()
    private var pendingResult: FlutterResult?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_workout_bridge", binaryMessenger: registrar.messenger())
        let instance = FlutterWorkoutBridgePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Register the workout preview view factory
        if #available(iOS 17.0, *) {
            let factory = WorkoutPreviewViewFactory(messenger: registrar.messenger())
            registrar.register(factory, withId: "workout_preview_button")
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Check iOS version first
        guard #available(iOS 17.0, *) else {
            result(FlutterError(code: "IOS_VERSION_NOT_SUPPORTED", message: "This plugin requires iOS 17.0 or later", details: nil))
            return
        }

        switch call.method {
        case "requestPermissions":
            requestHealthKitPermissions(result: result)
        case "createWorkoutFromJson":
            guard let args = call.arguments as? [String: Any],
                  let jsonData = args["json"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid JSON data", details: nil))
                return
            }
            createWorkoutFromJson(json: jsonData, result: result)
        case "presentWorkout":
            guard let args = call.arguments as? [String: Any],
                  let jsonData = args["json"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid JSON data", details: nil))
                return
            }
            presentWorkoutDirectly(json: jsonData, result: result)
        case "getCompletedWorkouts":
            guard let args = call.arguments as? [String: Any],
                  let daysBack = args["daysBack"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid daysBack parameter", details: nil))
                return
            }
            getCompletedWorkouts(daysBack: daysBack, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - HealthKit Permissions

    private func requestHealthKitPermissions(result: @escaping FlutterResult) {
        guard HKHealthStore.isHealthDataAvailable() else {
            result(FlutterError(code: "HEALTHKIT_NOT_AVAILABLE", message: "HealthKit is not available on this device", details: nil))
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(success)
                }
            }
        }
    }

    // MARK: - Workout Creation

    @available(iOS 17.0, *)
    private func createWorkoutFromJson(json: [String: Any], result: @escaping FlutterResult) {
        do {
            let customWorkout = try parseJsonToWorkout(json: json)
            presentWorkout(customWorkout: customWorkout, result: result)
        } catch {
            result(FlutterError(code: "WORKOUT_CREATION_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    @available(iOS 17.0, *)
    private func parseJsonToWorkout(json: [String: Any]) throws -> CustomWorkout {
        guard let name = json["name"] as? String else {
            throw WorkoutError.invalidWorkoutData("Missing workout name")
        }

        let activityType = parseActivityType(json["activityType"] as? String ?? "running")
        let location = parseLocationType(json["location"] as? String ?? "outdoor")

        var warmupStep: WorkoutStep?
        var intervalBlocks: [IntervalBlock] = []
        var cooldownStep: WorkoutStep?

        // Parse warm-up
        if let warmupData = json["warmup"] as? [String: Any] {
            warmupStep = try parseWorkoutStepAsWorkoutStep(stepData: warmupData, stepType: .warmup)
        }

        // Parse main intervals - group them into blocks
        if let intervalsArray = json["intervals"] as? [[String: Any]] {
            var intervalSteps: [IntervalStep] = []
            for intervalData in intervalsArray {
                let intervalStep = try parseWorkoutStep(stepData: intervalData, stepType: .interval)
                intervalSteps.append(intervalStep)
            }

            // Create a single block with all interval steps
            if !intervalSteps.isEmpty {
                var block = IntervalBlock()
                block.steps = intervalSteps
                block.iterations = 1
                intervalBlocks.append(block)
            }
        }

        // Parse cool-down
        if let cooldownData = json["cooldown"] as? [String: Any] {
            cooldownStep = try parseWorkoutStepAsWorkoutStep(stepData: cooldownData, stepType: .cooldown)
        }

        return createCustomWorkout(
            activity: activityType,
            location: location,
            displayName: name,
            warmup: warmupStep,
            blocks: intervalBlocks,
            cooldown: cooldownStep
        )
    }

    @available(iOS 17.0, *)
    private func parseWorkoutStep(stepData: [String: Any], stepType: WorkoutStepType) throws -> IntervalStep {
        let purpose: IntervalStep.Purpose = stepType == .interval ? .work : .recovery

        if let durationType = stepData["durationType"] as? String {
            switch durationType.lowercased() {
            case "time":
                guard let seconds = stepData["duration"] as? Double else {
                    throw WorkoutError.invalidWorkoutData("Missing time duration")
                }
                let goal = WorkoutGoal.time(seconds, .seconds)
                var step = IntervalStep(purpose)
                step.step.goal = goal
                return step

            case "distance":
                guard let meters = stepData["duration"] as? Double else {
                    throw WorkoutError.invalidWorkoutData("Missing distance duration")
                }
                let goal = WorkoutGoal.distance(meters, .meters)
                var step = IntervalStep(purpose)
                step.step.goal = goal
                return step

            case "calories":
                guard let calories = stepData["duration"] as? Double else {
                    throw WorkoutError.invalidWorkoutData("Missing calorie target")
                }
                let goal = WorkoutGoal.energy(calories, .kilocalories)
                var step = IntervalStep(purpose)
                step.step.goal = goal
                return step

            default:
                let goal = WorkoutGoal.open
                var step = IntervalStep(purpose)
                step.step.goal = goal
                return step
            }
        } else {
            let goal = WorkoutGoal.open
            var step = IntervalStep(purpose)
            step.step.goal = goal
            return step
        }
    }

    @available(iOS 17.0, *)
    private func parseWorkoutStepAsWorkoutStep(stepData: [String: Any], stepType: WorkoutStepType) throws -> WorkoutStep {
        if let durationType = stepData["durationType"] as? String {
            switch durationType.lowercased() {
            case "time":
                guard let seconds = stepData["duration"] as? Double else {
                    throw WorkoutError.invalidWorkoutData("Missing time duration")
                }
                let goal = WorkoutGoal.time(seconds, .seconds)
                return WorkoutStep(goal: goal)

            case "distance":
                guard let meters = stepData["duration"] as? Double else {
                    throw WorkoutError.invalidWorkoutData("Missing distance duration")
                }
                let goal = WorkoutGoal.distance(meters, .meters)
                return WorkoutStep(goal: goal)

            case "calories":
                guard let calories = stepData["duration"] as? Double else {
                    throw WorkoutError.invalidWorkoutData("Missing calorie target")
                }
                let goal = WorkoutGoal.energy(calories, .kilocalories)
                return WorkoutStep(goal: goal)

            default:
                return WorkoutStep(goal: .open)
            }
        } else {
            return WorkoutStep(goal: .open)
        }
    }

    private func parseActivityType(_ activityString: String) -> HKWorkoutActivityType {
        switch activityString.lowercased() {
        case "running":
            return .running
        case "cycling":
            return .cycling
        case "walking":
            return .walking
        case "swimming":
            return .swimming
        case "hiking":
            return .hiking
        case "yoga":
            return .yoga
        case "strength":
            return .functionalStrengthTraining
        case "rowing":
            return .rowing
        case "elliptical":
            return .elliptical
        default:
            return .running
        }
    }

    private func parseLocationType(_ locationString: String) -> HKWorkoutSessionLocationType {
        switch locationString.lowercased() {
        case "indoor":
            return .indoor
        case "outdoor":
            return .outdoor
        default:
            return .outdoor
        }
    }

    // MARK: - Workout Presentation

    @available(iOS 17.0, *)
    private func presentWorkout(customWorkout: CustomWorkout, result: @escaping FlutterResult) {
        // Store the workout for access by the WorkoutPreviewButton
        WorkoutStore.shared.setWorkout(customWorkout)
        result(true)
    }

    @available(iOS 17.0, *)
    private func presentWorkoutDirectly(json: [String: Any], result: @escaping FlutterResult) {
        do {
            let customWorkout = try parseJsonToWorkout(json: json)

            // Store the workout and try to schedule it to Apple Watch
            WorkoutStore.shared.setWorkout(customWorkout)

            // Use the Working approach: Schedule workout instead of preview
            Task {
                await scheduleWorkoutToAppleWatch(customWorkout: customWorkout, result: result)
            }
        } catch {
            result(FlutterError(code: "WORKOUT_CREATION_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }

    @available(iOS 17.0, *)
    private func scheduleWorkoutToAppleWatch(customWorkout: CustomWorkout, result: @escaping FlutterResult) async {
        do {
            // Create WorkoutPlan with a completion goal
            let workoutPlan = WorkoutPlan(.custom(customWorkout))

            // Check authorization status
            let authStatus = await WorkoutScheduler.shared.authorizationState
            print("WorkoutKit Authorization Status: \(authStatus)")

            if authStatus != .authorized {
                print("Requesting WorkoutKit authorization...")
                // Request authorization
                await WorkoutScheduler.shared.requestAuthorization()

                // Check the result
                let newAuthStatus = await WorkoutScheduler.shared.authorizationState
                print("New authorization status: \(newAuthStatus)")

                if newAuthStatus != .authorized {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "AUTHORIZATION_DENIED",
                                          message: "User denied WorkoutKit authorization. Please go to Settings > Privacy & Security > Health > Workouts and enable access.",
                                          details: nil))
                    }
                    return
                }
            }

            // IMPORTANT: Schedule for a near-future time (5 minutes from now)
            // This gives time for sync but is close enough to appear immediately
            let scheduledDate = Date().addingTimeInterval(300) // 5 minutes in future
            let calendar = Calendar.current
            var dateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: scheduledDate
            )
            // Ensure seconds is nil for proper scheduling
            dateComponents.second = nil

            print("Scheduling workout for: \(scheduledDate)")
            print("Workout name: \(customWorkout.displayName)")
            print("Activity type: \(customWorkout.activity)")

            // Schedule the workout
            try await WorkoutScheduler.shared.schedule(workoutPlan, at: dateComponents)

            print("✅ Workout scheduled successfully!")

            // Also try to get scheduled workouts to verify
            let scheduledWorkouts = try? await WorkoutScheduler.shared.scheduledWorkouts
            print("Number of scheduled workouts: \(scheduledWorkouts?.count ?? 0)")

            DispatchQueue.main.async {
                result([
                    "success": true,
                    "message": "Workout scheduled! It will appear in your Apple Watch Workout app within 5 minutes. Make sure your iPhone and Watch are paired and nearby.",
                    "workoutName": customWorkout.displayName,
                    "scheduledDate": ISO8601DateFormatter().string(from: scheduledDate),
                    "instructions": "Open the Workout app on your Apple Watch and scroll to the bottom to find your custom workout."
                ])
            }

        } catch {
            print("❌ Failed to schedule workout: \(error)")
            print("Error details: \(error.localizedDescription)")

            DispatchQueue.main.async {
                result(FlutterError(code: "WORKOUT_SCHEDULE_ERROR",
                                  message: "Failed to schedule workout: \(error.localizedDescription)",
                                  details: "Make sure your Apple Watch is paired and nearby. Try restarting both devices."))
            }
        }
    }

    // MARK: - HealthKit Data Retrieval

    @available(iOS 17.0, *)
    private func getScheduledWorkouts(result: @escaping FlutterResult) {
        Task {
            do {
                let scheduledWorkouts = try await WorkoutScheduler.shared.scheduledWorkouts

                // ScheduledWorkoutPlan is an array of scheduled plans
                // We'll return basic info about count since we can't access specific properties
                let workoutInfo = [
                    "count": scheduledWorkouts.count,
                    "message": "Found \(scheduledWorkouts.count) scheduled workout(s)"
                ]

                DispatchQueue.main.async {
                    result(workoutInfo)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "FETCH_ERROR",
                                      message: "Failed to fetch scheduled workouts: \(error.localizedDescription)",
                                      details: nil))
                }
            }
        }
    }

    @available(iOS 17.0, *)
    private func clearAllScheduledWorkouts(result: @escaping FlutterResult) {
        Task {
            do {
                // Get count of scheduled workouts
                let scheduledWorkouts = try await WorkoutScheduler.shared.scheduledWorkouts

                DispatchQueue.main.async {
                    result([
                        "success": true,
                        "message": "Found \(scheduledWorkouts.count) scheduled workout(s). These will appear on your Apple Watch at their scheduled times.",
                        "count": scheduledWorkouts.count
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "FETCH_ERROR",
                                      message: "Failed to fetch scheduled workouts: \(error.localizedDescription)",
                                      details: nil))
                }
            }
        }
    }

    private func getCompletedWorkouts(daysBack: Int, result: @escaping FlutterResult) {
        let workoutType = HKObjectType.workoutType()

        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -daysBack, to: endDate)!

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] query, samples, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "HEALTHKIT_ERROR", message: error.localizedDescription, details: nil))
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    result([])
                    return
                }

                let workoutData = workouts.map { workout in
                    self?.workoutToJson(workout: workout) ?? [:]
                }

                result(workoutData)
            }
        }

        healthStore.execute(query)
    }

    private func workoutToJson(workout: HKWorkout) -> [String: Any] {
        var json: [String: Any] = [:]

        json["uuid"] = workout.uuid.uuidString
        json["startDate"] = ISO8601DateFormatter().string(from: workout.startDate)
        json["endDate"] = ISO8601DateFormatter().string(from: workout.endDate)
        json["duration"] = workout.duration
        json["workoutActivityType"] = workout.workoutActivityType.rawValue

        if let totalEnergyBurned = workout.totalEnergyBurned {
            json["totalEnergyBurned"] = totalEnergyBurned.doubleValue(for: .kilocalorie())
        }

        if let totalDistance = workout.totalDistance {
            json["totalDistance"] = totalDistance.doubleValue(for: .meter())
        }

        json["sourceName"] = workout.sourceRevision.source.name
        json["device"] = workout.device?.name

        return json
    }
}

// MARK: - Workout Store (Singleton for sharing workouts)

@available(iOS 17.0, *)
class WorkoutStore: ObservableObject {
    static let shared = WorkoutStore()
    @Published var currentWorkout: CustomWorkout?

    private init() {}

    func setWorkout(_ workout: CustomWorkout) {
        currentWorkout = workout
    }
}

// MARK: - WorkoutPreviewView Factory

@available(iOS 17.0, *)
class WorkoutPreviewViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return WorkoutPreviewFlutterView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - WorkoutPreviewFlutterView

@available(iOS 17.0, *)
class WorkoutPreviewFlutterView: NSObject, FlutterPlatformView {
    private var _view: UIView
    private var statusLabel: UILabel?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        _view = UIView()
        super.init()
        createNativeView(view: _view, args: args)
    }

    func view() -> UIView {
        return _view
    }

    func createNativeView(view: UIView, args: Any?) {
        guard let workout = WorkoutStore.shared.currentWorkout else {
            // Show a placeholder if no workout is available
            let label = UILabel(frame: view.bounds)
            label.text = "No workout available"
            label.textAlignment = .center
            label.textColor = .systemGray
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(label)
            return
        }

        // Create a vertical stack with the main button and status
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill
        stackView.distribution = .equalSpacing

        // Workout info label
        let infoLabel = UILabel()
        infoLabel.text = "📱 \(workout.displayName)"
        infoLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        infoLabel.textColor = .label
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 2

        // Main "Send to Apple Watch" button
        let mainButton = UIButton(type: .system)
        mainButton.setTitle("⌚ Send to Apple Watch", for: .normal)
        mainButton.backgroundColor = .systemBlue
        mainButton.setTitleColor(.white, for: .normal)
        mainButton.layer.cornerRadius = 12
        mainButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        mainButton.addTarget(self, action: #selector(sendWorkoutToWatch), for: .touchUpInside)
        mainButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        // Add shadow for better appearance
        mainButton.layer.shadowColor = UIColor.black.cgColor
        mainButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        mainButton.layer.shadowRadius = 4
        mainButton.layer.shadowOpacity = 0.1

        // Status label
        let statusLabel = UILabel()
        statusLabel.text = "Ready to send"
        statusLabel.font = UIFont.systemFont(ofSize: 12)
        statusLabel.textColor = .systemGray
        statusLabel.textAlignment = .center
        self.statusLabel = statusLabel

        // Add workout details
        let detailsLabel = UILabel()
        let detailsText = describeWorkout(workout)
        detailsLabel.text = detailsText
        detailsLabel.font = UIFont.systemFont(ofSize: 11)
        detailsLabel.textColor = .systemGray2
        detailsLabel.textAlignment = .center
        detailsLabel.numberOfLines = 0

        stackView.addArrangedSubview(infoLabel)
        stackView.addArrangedSubview(mainButton)
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(detailsLabel)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
    }

    @objc private func sendWorkoutToWatch() {
        guard let workout = WorkoutStore.shared.currentWorkout else {
            updateStatus("❌ No workout available", color: .systemRed)
            return
        }

        // Find the button and update its state
        if let stackView = self._view.subviews.first as? UIStackView,
           let button = stackView.arrangedSubviews.first(where: { $0 is UIButton }) as? UIButton {
            button.setTitle("📤 Sending...", for: .normal)
            button.backgroundColor = .systemOrange
            button.isEnabled = false
        }

        updateStatus("Preparing workout...", color: .systemOrange)

        Task {
            do {
                // Create WorkoutPlan
                let workoutPlan = WorkoutPlan(.custom(workout))

                // Check and request authorization
                updateStatus("Checking permissions...", color: .systemOrange)

                let authStatus = await WorkoutScheduler.shared.authorizationState
                print("Current auth status: \(authStatus)")

                if authStatus != .authorized {
                    updateStatus("Requesting permission...", color: .systemOrange)
                    await WorkoutScheduler.shared.requestAuthorization()

                    let newAuthStatus = await WorkoutScheduler.shared.authorizationState
                    print("New auth status: \(newAuthStatus)")

                    if newAuthStatus != .authorized {
                        updateStatus("❌ Permission denied - Check Settings", color: .systemRed)
                        resetButton()
                        return
                    }
                }

                updateStatus("Scheduling workout...", color: .systemBlue)

                // Schedule for very near future (30 seconds from now)
                let scheduledDate = Date().addingTimeInterval(30)
                let calendar = Calendar.current
                var dateComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: scheduledDate
                )
                // Important: Set seconds to nil for proper scheduling
                dateComponents.second = nil

                print("Scheduling workout: \(workout.displayName)")
                print("Schedule time: \(scheduledDate)")

                // Schedule the workout
                try await WorkoutScheduler.shared.schedule(workoutPlan, at: dateComponents)

                print("✅ Workout scheduled successfully!")

                // Verify it was scheduled
                let scheduledWorkouts = try? await WorkoutScheduler.shared.scheduledWorkouts
                print("Total scheduled workouts: \(scheduledWorkouts?.count ?? 0)")

                // Success!
                updateStatus("✅ Scheduled! Opening on Watch in 30s", color: .systemGreen)

                DispatchQueue.main.async {
                    if let stackView = self._view.subviews.first as? UIStackView,
                       let button = stackView.arrangedSubviews.first(where: { $0 is UIButton }) as? UIButton {
                        button.setTitle("✅ Check Apple Watch!", for: .normal)
                        button.backgroundColor = .systemGreen

                        // Show additional instructions
                        if let statusLabel = self.statusLabel {
                            statusLabel.numberOfLines = 0
                            statusLabel.text = "✅ Workout scheduled!\n⌚ Open Workout app on watch\n📱 Keep iPhone nearby for sync"
                        }

                        // Reset after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            self.resetButton()
                            self.updateStatus("Ready to send another", color: .systemGray)
                        }
                    }
                }

            } catch {
                print("❌ Error sending workout: \(error)")
                print("Error details: \(error.localizedDescription)")

                // Provide more specific error messages
                var errorMessage = "Failed to send"
                if error.localizedDescription.contains("authorization") {
                    errorMessage = "Permission needed - Check Settings > Privacy > Health"
                } else if error.localizedDescription.contains("invalid") {
                    errorMessage = "Invalid workout format"
                } else {
                    errorMessage = "Error: \(error.localizedDescription)"
                }

                updateStatus("❌ \(errorMessage)", color: .systemRed)
                resetButton()
            }
        }
    }

    private func updateStatus(_ text: String, color: UIColor) {
        DispatchQueue.main.async {
            self.statusLabel?.text = text
            self.statusLabel?.textColor = color
        }
    }

    private func resetButton() {
        DispatchQueue.main.async {
            if let stackView = self._view.subviews.first as? UIStackView,
               let button = stackView.arrangedSubviews.first(where: { $0 is UIButton }) as? UIButton {
                button.setTitle("⌚ Send to Apple Watch", for: .normal)
                button.backgroundColor = .systemBlue
                button.isEnabled = true
            }
        }
    }

    private func describeWorkout(_ workout: CustomWorkout) -> String {
        var details: [String] = []

        // Add activity type
        details.append("Activity: \(describeActivity(workout.activity))")

        // Add location
        details.append("Location: \(workout.location == .indoor ? "Indoor" : "Outdoor")")

        // Add step counts
        var stepInfo: [String] = []
        if workout.warmup != nil {
            stepInfo.append("Warmup")
        }
        if !workout.blocks.isEmpty {
            let totalSteps = workout.blocks.reduce(0) { $0 + $1.steps.count }
            stepInfo.append("\(totalSteps) intervals")
        }
        if workout.cooldown != nil {
            stepInfo.append("Cooldown")
        }

        if !stepInfo.isEmpty {
            details.append("Steps: \(stepInfo.joined(separator: " • "))")
        }

        return details.joined(separator: " | ")
    }

    private func describeActivity(_ activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        default: return "Workout"
        }
    }
}

// MARK: - Helper Functions

@available(iOS 17.0, *)
private func createCustomWorkout(
    activity: HKWorkoutActivityType,
    location: HKWorkoutSessionLocationType,
    displayName: String,
    warmup: WorkoutStep? = nil,
    blocks: [IntervalBlock] = [],
    cooldown: WorkoutStep? = nil
) -> CustomWorkout {
    return CustomWorkout(
        activity: activity,
        location: location,
        displayName: displayName,
        warmup: warmup,
        blocks: blocks,
        cooldown: cooldown
    )
}

// MARK: - Workout Step Description Helper

@available(iOS 17.0, *)
private func describeWorkoutStep(_ step: WorkoutStep?) -> String {
    guard let step = step else { return "None" }

    switch step.goal {
    case .time(let value, let unit):
        return "Time: \(Int(value)) \(unit)"
    case .distance(let value, let unit):
        return "Distance: \(Int(value)) \(unit)"
    case .energy(let value, let unit):
        return "Energy: \(Int(value)) \(unit)"
    case .open:
        return "Open goal"
    default:
        return "Custom goal"
    }
}