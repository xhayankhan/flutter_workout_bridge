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
        case "checkPermissions":
            checkHealthKitPermissions(result: result)
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
        case "getScheduledWorkouts":
            getScheduledWorkouts(result: result)
        case "clearScheduledWorkouts":
            clearAllScheduledWorkouts(result: result)
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
            HKSeriesType.workoutRoute(),
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
                    return
                }

                let readTypesArray: [HKObjectType] = Array(readTypes)
                let writeTypesArray: [HKSampleType] = Array(writeTypes)

                let allReadAuthorized = readTypesArray.allSatisfy {
                    self.healthStore.authorizationStatus(for: $0) == .sharingAuthorized
                }
                let allWriteAuthorized = writeTypesArray.allSatisfy {
                    self.healthStore.authorizationStatus(for: $0) == .sharingAuthorized
                }

                result(allReadAuthorized && allWriteAuthorized)
            }
        }
    }

    @available(iOS 17.0, *)
    private func checkHealthKitPermissions(result: @escaping FlutterResult) {
        checkActualHealthKitPermissions(result: result)
    }

    private func checkActualHealthKitPermissions(result: @escaping FlutterResult) {
        guard HKHealthStore.isHealthDataAvailable() else {
            result(FlutterError(code: "HEALTHKIT_NOT_AVAILABLE", message: "HealthKit is not available on this device", details: nil))
            return
        }

        let readTypes: [HKObjectType] = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!
        ]

        let writeTypes: [HKSampleType] = [
            HKObjectType.workoutType()
        ]

        var permissionResults: [String: Any] = [:]
        var readPermissions: [String: String] = [:]
        var writePermissions: [String: String] = [:]

        for type in readTypes {
            let authStatus = healthStore.authorizationStatus(for: type)
            let statusString = authorizationStatusToString(authStatus)
            readPermissions[type.identifier] = statusString
        }

        for type in writeTypes {
            let authStatus = healthStore.authorizationStatus(for: type)
            let statusString = authorizationStatusToString(authStatus)
            writePermissions[type.identifier] = statusString
        }

        let allReadAuthorized = readTypes.allSatisfy {
            healthStore.authorizationStatus(for: $0) == .sharingAuthorized
        }
        let allWriteAuthorized = writeTypes.allSatisfy {
            healthStore.authorizationStatus(for: $0) == .sharingAuthorized
        }

        let anyReadDenied = readTypes.contains {
            healthStore.authorizationStatus(for: $0) == .sharingDenied
        }
        let anyWriteDenied = writeTypes.contains {
            healthStore.authorizationStatus(for: $0) == .sharingDenied
        }

        permissionResults["readPermission"] = allReadAuthorized
        permissionResults["writePermission"] = allWriteAuthorized
        permissionResults["readDenied"] = anyReadDenied
        permissionResults["writeDenied"] = anyWriteDenied
        permissionResults["readDetails"] = readPermissions
        permissionResults["writeDetails"] = writePermissions

        if allReadAuthorized && allWriteAuthorized {
            permissionResults["status"] = "All permissions granted"
        } else if anyReadDenied || anyWriteDenied {
            permissionResults["status"] = "Some permissions denied - Go to Settings > Privacy & Security > Health to enable"
        } else {
            permissionResults["status"] = "Permissions not determined - Call requestPermissions first"
        }

        result(permissionResults)
    }

    private func authorizationStatusToString(_ status: HKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .sharingDenied:
            return "denied"
        case .sharingAuthorized:
            return "authorized"
        @unknown default:
            return "unknown"
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

        let customUUID = json["uuid"] as? String ?? UUID().uuidString
        storeCustomWorkoutData(uuid: customUUID, name: name, json: json)

        let activityType = parseActivityType(json["activityType"] as? String ?? "running")
        let location = parseLocationType(json["location"] as? String ?? "outdoor")

        var warmupStep: WorkoutStep?
        var intervalBlocks: [IntervalBlock] = []
        var cooldownStep: WorkoutStep?

        if let warmupData = json["warmup"] as? [String: Any] {
            warmupStep = try parseWorkoutStepAsWorkoutStep(stepData: warmupData, stepType: .warmup)
        }

        if let intervalsArray = json["intervals"] as? [[String: Any]] {
            var intervalSteps: [IntervalStep] = []
            for intervalData in intervalsArray {
                let intervalStep = try parseWorkoutStep(stepData: intervalData, stepType: .interval)
                intervalSteps.append(intervalStep)
            }

            if !intervalSteps.isEmpty {
                var block = IntervalBlock()
                block.steps = intervalSteps
                block.iterations = 1
                intervalBlocks.append(block)
            }
        }

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
        case "running":     return .running
        case "cycling":     return .cycling
        case "walking":     return .walking
        case "swimming":    return .swimming
        case "hiking":      return .hiking
        case "yoga":        return .yoga
        case "strength":    return .functionalStrengthTraining
        case "rowing":      return .rowing
        case "elliptical":  return .elliptical
        case "skiing":              return .downhillSkiing
        case "downhill_skiing":     return .downhillSkiing
        case "cross_country_skiing", "xc_skiing":
                                    return .crossCountrySkiing
        case "surfing":             return .surfingSports
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
        WorkoutStore.shared.setWorkout(customWorkout)
        result(true)
    }

    @available(iOS 17.0, *)
    private func presentWorkoutDirectly(json: [String: Any], result: @escaping FlutterResult) {
        cleanupUserDefaults()

        do {
            let customWorkout = try parseJsonToWorkout(json: json)
            WorkoutStore.shared.setWorkout(customWorkout)
            storeRecentWorkoutInfo(customWorkout: customWorkout)

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
            let workoutPlan = WorkoutPlan(.custom(customWorkout))

            let authStatus = await WorkoutScheduler.shared.authorizationState
            print("WorkoutKit Authorization Status: \(authStatus)")

            if authStatus != .authorized {
                print("Requesting WorkoutKit authorization...")
                await WorkoutScheduler.shared.requestAuthorization()

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

            let scheduledDate = Date().addingTimeInterval(300) // 5 minutes in future
            let calendar = Calendar.current
            var dateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: scheduledDate
            )
            dateComponents.second = nil

            print("Scheduling workout for: \(scheduledDate)")
            print("Workout name: \(customWorkout.displayName)")
            print("Activity type: \(customWorkout.activity)")

            try await WorkoutScheduler.shared.schedule(workoutPlan, at: dateComponents)

            print("✅ Workout scheduled successfully!")

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

    // MARK: - Custom Workout Data Storage

    private func cleanupUserDefaults() {
        let defaults = UserDefaults.standard

        if let existing = defaults.object(forKey: "RecentCustomWorkouts") {
            if !(existing is [[String: Any]]) {
                print("Found corrupted RecentCustomWorkouts data, clearing...")
                defaults.removeObject(forKey: "RecentCustomWorkouts")
            }
        }

        if let existing = defaults.object(forKey: "CustomWorkouts") {
            if !(existing is [String: [String: Any]]) {
                print("Found corrupted CustomWorkouts data, clearing...")
                defaults.removeObject(forKey: "CustomWorkouts")
            }
        }

        defaults.synchronize()
    }

    private func storeCustomWorkoutData(uuid: String, name: String, json: [String: Any]) {
        let defaults = UserDefaults.standard
        var customWorkouts = defaults.dictionary(forKey: "CustomWorkouts") as? [String: [String: Any]] ?? [:]

        customWorkouts[uuid] = [
            "name": name,
            "createdAt": Date().timeIntervalSince1970,
            "originalJson": json
        ]

        defaults.set(customWorkouts, forKey: "CustomWorkouts")
        defaults.synchronize()

        print("Stored custom workout data for UUID: \(uuid), Name: \(name)")
    }

    private func getCustomWorkoutData(uuid: String) -> [String: Any]? {
        let defaults = UserDefaults.standard
        let customWorkouts = defaults.dictionary(forKey: "CustomWorkouts") as? [String: [String: Any]] ?? [:]
        return customWorkouts[uuid]
    }

    @available(iOS 17.0, *)
    private func storeRecentWorkoutInfo(customWorkout: CustomWorkout) {
        let defaults = UserDefaults.standard

        var recentWorkouts: [[String: Any]] = []
        if let existingWorkouts = defaults.object(forKey: "RecentCustomWorkouts") as? [[String: Any]] {
            recentWorkouts = existingWorkouts
        } else {
            print("No existing recent workouts found, starting with empty array")
        }

        let workoutInfo: [String: Any] = [
            "name": customWorkout.displayName,
            "activityType": customWorkout.activity.rawValue,
            "scheduledTime": Date().timeIntervalSince1970
        ]

        recentWorkouts.append(workoutInfo)

        if recentWorkouts.count > 20 {
            recentWorkouts = Array(recentWorkouts.suffix(20))
        }

        defaults.set(recentWorkouts, forKey: "RecentCustomWorkouts")
        defaults.synchronize()

        print("Stored recent workout info: \(customWorkout.displayName)")
    }

    private func findCustomWorkoutName(for workout: HKWorkout) -> String? {
        let defaults = UserDefaults.standard

        var recentWorkouts: [[String: Any]] = []
        if let existingWorkouts = defaults.object(forKey: "RecentCustomWorkouts") as? [[String: Any]] {
            recentWorkouts = existingWorkouts
        } else {
            print("No recent workouts found for matching")
            return nil
        }

        let workoutStartTime = workout.startDate.timeIntervalSince1970

        for recentWorkout in recentWorkouts {
            if let scheduledTime = recentWorkout["scheduledTime"] as? Double,
               let name = recentWorkout["name"] as? String,
               let activityType = recentWorkout["activityType"] as? UInt,
               abs(scheduledTime - workoutStartTime) < 7200, // Within 2 hours
               activityType == workout.workoutActivityType.rawValue {
                print("Found matching custom workout: \(name)")
                return name
            }
        }

        return nil
    }

    // MARK: - HealthKit Data Retrieval

    @available(iOS 17.0, *)
    private func getScheduledWorkouts(result: @escaping FlutterResult) {
        Task {
            do {
                let scheduledWorkouts = try await WorkoutScheduler.shared.scheduledWorkouts

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

    // MARK: - Enhanced Workout Data Retrieval

    private func getCompletedWorkouts(daysBack: Int, result: @escaping FlutterResult) {
        guard HKHealthStore.isHealthDataAvailable() else {
            result(FlutterError(code: "HEALTHKIT_NOT_AVAILABLE", message: "HealthKit is not available on this device", details: nil))
            return
        }

        let workoutType = HKObjectType.workoutType()

        let authStatus = healthStore.authorizationStatus(for: workoutType)
        guard authStatus == .sharingAuthorized else {
            result(FlutterError(code: "PERMISSION_DENIED", message: "Permission denied for workout data. Please enable in Settings > Privacy & Security > Health", details: nil))
            return
        }

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
            if let error = error {
                DispatchQueue.main.async {
                    result(FlutterError(code: "HEALTHKIT_ERROR", message: error.localizedDescription, details: nil))
                }
                return
            }

            guard let workouts = samples as? [HKWorkout] else {
                DispatchQueue.main.async {
                    result([])
                }
                return
            }

            print("Found \(workouts.count) workouts")

            let group = DispatchGroup()
            var workoutDataArray: [[String: Any]] = []
            let workoutQueue = DispatchQueue(label: "workoutProcessing", qos: .userInitiated)

            for (index, workout) in workouts.enumerated() {
                group.enter()

                workoutQueue.async {
                    self?.getDetailedWorkoutData(workout: workout) { workoutData in
                        workoutDataArray.append(workoutData)
                        print("Processed workout \(index + 1)/\(workouts.count): \(workoutData["name"] ?? "Unknown")")
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                let sortedWorkouts = workoutDataArray.sorted { workout1, workout2 in
                    guard let date1Str = workout1["startDate"] as? String,
                          let date2Str = workout2["startDate"] as? String,
                          let date1 = ISO8601DateFormatter().date(from: date1Str),
                          let date2 = ISO8601DateFormatter().date(from: date2Str) else {
                        return false
                    }
                    return date1 > date2
                }

                print("Returning \(sortedWorkouts.count) processed workouts")
                result(sortedWorkouts)
            }
        }

        healthStore.execute(query)
    }

    private func getDetailedWorkoutData(workout: HKWorkout, completion: @escaping ([String: Any]) -> Void) {
        var workoutData = workoutToJson(workout: workout)

        let group = DispatchGroup()

        group.enter()
        getWorkoutRoute(for: workout) { routeData in
            workoutData["route"] = routeData
            group.leave()
        }

        group.enter()
        getWorkoutHeartRateData(for: workout) { heartRateData in
            workoutData["heartRate"] = heartRateData
            group.leave()
        }

        group.enter()
        getWorkoutMetrics(for: workout) { metrics in
            workoutData["metrics"] = metrics
            group.leave()
        }

        group.enter()
        getWorkoutEvents(for: workout) { events in
            workoutData["events"] = events
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            completion(workoutData)
        }
    }

    private func workoutToJson(workout: HKWorkout) -> [String: Any] {
        var json: [String: Any] = [:]

        let workoutUUID = workout.uuid.uuidString
        json["uuid"] = workoutUUID
        json["startDate"] = ISO8601DateFormatter().string(from: workout.startDate)
        json["endDate"] = ISO8601DateFormatter().string(from: workout.endDate)
        json["duration"] = workout.duration
        json["workoutActivityType"] = workout.workoutActivityType.rawValue

        var workoutName = getWorkoutActivityName(workout.workoutActivityType)
        var isCustomWorkout = false

        if let customName = workout.metadata?["CustomWorkoutName"] as? String {
            workoutName = customName
            isCustomWorkout = true
            print("Found custom name in metadata: \(customName)")
        } else if let customData = getCustomWorkoutData(uuid: workoutUUID) {
            if let storedName = customData["name"] as? String {
                workoutName = storedName
                isCustomWorkout = true
                print("Found custom name in UserDefaults: \(storedName)")
            }
        } else if let foundName = findCustomWorkoutName(for: workout) {
            workoutName = foundName
            isCustomWorkout = true
            print("Found custom name by matching: \(foundName)")
        }

        json["name"] = workoutName
        json["isCustomWorkout"] = isCustomWorkout

        if let totalEnergyBurned = workout.totalEnergyBurned {
            json["totalEnergyBurned"] = totalEnergyBurned.doubleValue(for: .kilocalorie())
            json["totalEnergyBurnedUnit"] = "kcal"
        }

        if let totalDistance = workout.totalDistance {
            json["totalDistance"] = totalDistance.doubleValue(for: .meter())
            json["totalDistanceUnit"] = "meters"

            let distanceKm = totalDistance.doubleValue(for: .meter()) / 1000.0
            if distanceKm > 0 && workout.duration > 0 {
                json["averagePaceMinutesPerKm"] = workout.duration / 60.0 / distanceKm
                json["averageSpeedKmh"] = distanceKm / (workout.duration / 3600.0)
            }
        }

        json["sourceName"] = workout.sourceRevision.source.name
        json["sourceVersion"] = workout.sourceRevision.version ?? "Unknown"
        json["device"] = workout.device?.name ?? "Unknown"

        if let weatherCondition = workout.metadata?[HKMetadataKeyWeatherCondition] as? Int {
            json["weatherCondition"] = weatherCondition
        }
        if let weatherTemperature = workout.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity {
            json["weatherTemperature"] = weatherTemperature.doubleValue(for: .degreeCelsius())
        }
        if let weatherHumidity = workout.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity {
            json["weatherHumidity"] = weatherHumidity.doubleValue(for: .percent())
        }

        if let locationType = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool {
            json["isIndoorWorkout"] = locationType
        }

        if let elevationAscended = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity {
            json["elevationAscended"] = elevationAscended.doubleValue(for: .meter())
        }

        return json
    }

    // MARK: - Route Data

    private func getWorkoutRoute(for workout: HKWorkout, completion: @escaping ([String: Any]?) -> Void) {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)

        let routeQuery = HKAnchoredObjectQuery(
            type: routeType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] query, samples, deletedObjects, anchor, error in

            if let error = error {
                print("Error fetching workout route: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let routes = samples as? [HKWorkoutRoute], let firstRoute = routes.first else {
                print("No workout routes found")
                completion(nil)
                return
            }

            print("Found \(routes.count) workout route(s)")
            self?.getLocationDataFromRoute(route: firstRoute, completion: completion)
        }

        healthStore.execute(routeQuery)
    }

    private func getLocationDataFromRoute(route: HKWorkoutRoute, completion: @escaping ([String: Any]?) -> Void) {
        print("DEBUG: Processing route data...")
        print("- Route start: \(route.startDate)")
        print("- Route end: \(route.endDate)")

        var locationPoints: [[String: Any]] = []

        let query = HKWorkoutRouteQuery(route: route) { query, locationsOrNil, done, errorOrNil in

            if let error = errorOrNil {
                print("ERROR: Error reading route locations: \(error.localizedDescription)")
                if done {
                    completion(nil)
                }
                return
            }

            if let locations = locationsOrNil {
                print("DEBUG: Received \(locations.count) location points")

                for location in locations {
                    let point: [String: Any] = [
                        "latitude": location.coordinate.latitude,
                        "longitude": location.coordinate.longitude,
                        "altitude": location.altitude,
                        "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
                        "horizontalAccuracy": location.horizontalAccuracy,
                        "verticalAccuracy": location.verticalAccuracy,
                        "speed": location.speed >= 0 ? location.speed : nil,
                        "course": location.course >= 0 ? location.course : nil
                    ]
                    locationPoints.append(point)
                }
            }

            if done {
                let routeData: [String: Any] = [
                    "points": locationPoints,
                    "totalPoints": locationPoints.count
                ]
                print("SUCCESS: Route processing completed with \(locationPoints.count) points")
                completion(locationPoints.isEmpty ? nil : routeData)
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Heart Rate Data

    private func getWorkoutHeartRateData(for workout: HKWorkout, completion: @escaping ([String: Any]?) -> Void) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(nil)
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let heartRateQuery = HKSampleQuery(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { query, samples, error in

            if let error = error {
                print("Error fetching heart rate data: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let heartRateSamples = samples as? [HKQuantitySample], !heartRateSamples.isEmpty else {
                print("No heart rate samples found for workout")
                completion(nil)
                return
            }

            let heartRateData = heartRateSamples.map { sample in
                return [
                    "value": sample.quantity.doubleValue(for: HKUnit(from: "count/min")),
                    "timestamp": ISO8601DateFormatter().string(from: sample.startDate),
                    "endTimestamp": ISO8601DateFormatter().string(from: sample.endDate)
                ]
            }

            let values = heartRateData.compactMap { $0["value"] as? Double }
            let avgHeartRate = values.reduce(0, +) / Double(values.count)
            let maxHeartRate = values.max() ?? 0
            let minHeartRate = values.min() ?? 0

            let result: [String: Any] = [
                "samples": heartRateData,
                "averageHeartRate": avgHeartRate,
                "maxHeartRate": maxHeartRate,
                "minHeartRate": minHeartRate,
                "sampleCount": heartRateData.count
            ]

            print("Found \(heartRateData.count) heart rate samples")
            completion(result)
        }

        healthStore.execute(heartRateQuery)
    }

    // MARK: - Additional Metrics

    private func getWorkoutMetrics(for workout: HKWorkout, completion: @escaping ([String: Any]) -> Void) {
        var metrics: [String: Any] = [:]
        let group = DispatchGroup()

        let metricsToCollect: [(HKQuantityTypeIdentifier, String, HKUnit)] = [
            (.stepCount, "stepCount", .count()),
            (.distanceWalkingRunning, "walkingRunningDistance", .meter()),
            (.distanceCycling, "cyclingDistance", .meter()),
            (.activeEnergyBurned, "activeEnergyBurned", .kilocalorie()),
            (.basalEnergyBurned, "basalEnergyBurned", .kilocalorie()),
            (.swimmingStrokeCount, "swimmingStrokes", .count()),
            (.distanceSwimming, "swimmingDistance", .meter())
        ]

        for (identifier, key, unit) in metricsToCollect {
            guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { continue }

            group.enter()
            getQuantityData(for: workout, quantityType: quantityType, unit: unit) { data in
                if let data = data {
                    metrics[key] = data
                }
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            completion(metrics)
        }
    }

    private func getQuantityData(for workout: HKWorkout, quantityType: HKQuantityType, unit: HKUnit, completion: @escaping ([String: Any]?) -> Void) {
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        let query = HKSampleQuery(
            sampleType: quantityType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { query, samples, error in

            if let error = error {
                print("Error fetching \(quantityType.identifier): \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                completion(nil)
                return
            }

            let total = quantitySamples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
            let average = total / Double(quantitySamples.count)

            let result: [String: Any] = [
                "total": total,
                "average": average,
                "unit": unit.unitString,
                "sampleCount": quantitySamples.count
            ]

            completion(result)
        }

        healthStore.execute(query)
    }

    // MARK: - Workout Events

    private func getWorkoutEvents(for workout: HKWorkout, completion: @escaping ([[String: Any]]) -> Void) {
        guard let workoutEvents = workout.workoutEvents else {
            completion([])
            return
        }

        let events = workoutEvents.map { event -> [String: Any] in
            var eventData: [String: Any] = [
                "type": workoutEventTypeToString(event.type),
                "timestamp": ISO8601DateFormatter().string(from: event.dateInterval.start)
            ]

            if let metadata = event.metadata {
                eventData["metadata"] = metadata
            }

            return eventData
        }

        completion(events)
    }

    // MARK: - Helper Functions

    private func getWorkoutActivityName(_ activityType: HKWorkoutActivityType) -> String {
        switch activityType {
        case .running:                    return "Running"
        case .cycling:                    return "Cycling"
        case .walking:                    return "Walking"
        case .swimming:                   return "Swimming"
        case .hiking:                     return "Hiking"
        case .yoga:                       return "Yoga"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .rowing:                     return "Rowing"
        case .elliptical:                 return "Elliptical"
        case .stairClimbing:              return "Stair Climbing"
        case .tennis:                     return "Tennis"
        case .basketball:                 return "Basketball"
        case .soccer:                     return "Soccer"
        case .golf:                       return "Golf"
        case .baseball:                   return "Baseball"
        case .americanFootball:           return "American Football"
        case .badminton:                  return "Badminton"
        case .boxing:                     return "Boxing"
        case .climbing:                   return "Climbing"
        case .crossTraining:              return "Cross Training"
        case .downhillSkiing, .crossCountrySkiing:
            return "Skiing"
        case .snowboarding:
            return "Snowboarding"
        case .surfingSports:
            return "Surfing"
        case .waterSports:
            return "Water Sports"
        default:
            return "Other Workout"
        }
    }

    private func workoutEventTypeToString(_ eventType: HKWorkoutEventType) -> String {
        switch eventType {
        case .pause:
            return "pause"
        case .resume:
            return "resume"
        case .lap:
            return "lap"
        case .marker:
            return "marker"
        case .motionPaused:
            return "motionPaused"
        case .motionResumed:
            return "motionResumed"
        case .pauseOrResumeRequest:
            return "pauseOrResumeRequest"
        case .segment:
            return "segment"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - Workout Store

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
            let label = UILabel(frame: view.bounds)
            label.text = "No workout available"
            label.textAlignment = .center
            label.textColor = .systemGray
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(label)
            return
        }

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill
        stackView.distribution = .equalSpacing

        let infoLabel = UILabel()
        infoLabel.text = "📱 \(workout.displayName)"
        infoLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        infoLabel.textColor = .label
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 2

        let mainButton = UIButton(type: .system)
        mainButton.setTitle("⌚ Send to Apple Watch", for: .normal)
        mainButton.backgroundColor = .systemBlue
        mainButton.setTitleColor(.white, for: .normal)
        mainButton.layer.cornerRadius = 12
        mainButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        mainButton.addTarget(self, action: #selector(sendWorkoutToWatch), for: .touchUpInside)
        mainButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        mainButton.layer.shadowColor = UIColor.black.cgColor
        mainButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        mainButton.layer.shadowRadius = 4
        mainButton.layer.shadowOpacity = 0.1

        let statusLabel = UILabel()
        statusLabel.text = "Ready to send"
        statusLabel.font = UIFont.systemFont(ofSize: 12)
        statusLabel.textColor = .systemGray
        statusLabel.textAlignment = .center
        self.statusLabel = statusLabel

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

        if let stackView = self._view.subviews.first as? UIStackView,
           let button = stackView.arrangedSubviews.first(where: { $0 is UIButton }) as? UIButton {
            button.setTitle("📤 Sending...", for: .normal)
            button.backgroundColor = .systemOrange
            button.isEnabled = false
        }

        updateStatus("Preparing workout...", color: .systemOrange)

        Task {
            do {
                let workoutPlan = WorkoutPlan(.custom(workout))

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

                let scheduledDate = Date().addingTimeInterval(30)
                let calendar = Calendar.current
                var dateComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: scheduledDate
                )
                dateComponents.second = nil

                print("Scheduling workout: \(workout.displayName)")
                print("Schedule time: \(scheduledDate)")

                try await WorkoutScheduler.shared.schedule(workoutPlan, at: dateComponents)

                print("✅ Workout scheduled successfully!")

                let scheduledWorkouts = try? await WorkoutScheduler.shared.scheduledWorkouts
                print("Total scheduled workouts: \(scheduledWorkouts?.count ?? 0)")

                updateStatus("✅ Scheduled! Opening on Watch in 30s", color: .systemGreen)

                DispatchQueue.main.async {
                    if let stackView = self._view.subviews.first as? UIStackView,
                       let button = stackView.arrangedSubviews.first(where: { $0 is UIButton }) as? UIButton {
                        button.setTitle("✅ Check Apple Watch!", for: .normal)
                        button.backgroundColor = .systemGreen

                        if let statusLabel = self.statusLabel {
                            statusLabel.numberOfLines = 0
                            statusLabel.text = "✅ Workout scheduled!\n⌚ Open Workout app on watch\n📱 Keep iPhone nearby for sync"
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            self.resetButton()
                            self.updateStatus("Ready to send another", color: .systemGray)
                        }
                    }
                }

            } catch {
                print("❌ Error sending workout: \(error)")
                print("Error details: \(error.localizedDescription)")

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

        details.append("Activity: \(describeActivity(workout.activity))")
        details.append("Location: \(workout.location == .indoor ? "Indoor" : "Outdoor")")

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