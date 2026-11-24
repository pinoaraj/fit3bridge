import Foundation
import HealthKit
import Combine

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    @Published var isAuthorized = false
    @Published var authorizationError: String?

    private let healthStore = HKHealthStore()
    private let typesToWrite: Set<HKSampleType> = [
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
    ]
    private let typesToRead: Set<HKObjectType> = [
        HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
    ]

    private init() {
        checkAuthorizationStatus()
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            await MainActor.run { self.authorizationError = "HealthKit no disponible en este dispositivo" }
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            await MainActor.run { self.checkAuthorizationStatus() }
        } catch {
            await MainActor.run { self.authorizationError = error.localizedDescription }
        }
    }

    private func checkAuthorizationStatus() {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let status = healthStore.authorizationStatus(for: stepType)
        isAuthorized = status == .sharingAuthorized
    }

    func syncTodayData(steps: Int, distanceMeters: Double) async -> Bool {
        guard isAuthorized else {
            await MainActor.run { self.authorizationError = "No autorizado para escribir en HealthKit" }
            return false
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let stepQuantity = HKQuantity(unit: .count(), doubleValue: Double(steps))
        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distanceMeters)

        let stepSample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            quantity: stepQuantity,
            start: startOfDay,
            end: now
        )

        let distanceSample = HKQuantitySample(
            type: HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            quantity: distanceQuantity,
            start: startOfDay,
            end: now
        )

        do {
            try await healthStore.save(stepSample)
            try await healthStore.save(distanceSample)
            return true
        } catch {
            await MainActor.run { self.authorizationError = "Error guardando en HealthKit: \(error.localizedDescription)" }
            return false
        }
    }

    func readTodaySteps() async -> Int {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let value = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(value))
            }
            healthStore.execute(query)
        }
    }

    func readTodayDistance() async -> Double {
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: distanceType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let value = result?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
}