import Foundation
import HealthKit

/// Manages HealthKit authorization and writing lab results that have native HK types.
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var authorizationError: String?

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    /// Types we want to write to HealthKit
    private var writeTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        if let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            types.insert(glucose)
        }
        return types
    }

    /// Types we want to read from HealthKit
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            types.insert(glucose)
        }
        // Note: Clinical lab records (.labResultRecord) require a paid
        // Apple Developer Program membership. Omitted for personal teams.
        return types
    }

    func requestAuthorization() async {
        guard isHealthKitAvailable else {
            await MainActor.run {
                authorizationError = "HealthKit is not available on this device."
            }
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            await MainActor.run {
                isAuthorized = true
                authorizationError = nil
            }
        } catch {
            await MainActor.run {
                authorizationError = error.localizedDescription
                isAuthorized = false
            }
        }
    }

    // MARK: - Writing

    /// Write a lab result to HealthKit if a mapping exists
    func writeToHealthKit(testName: String, value: Double, unit: String, date: Date,
                          refLow: Double?, refHigh: Double?) async -> Bool {
        guard let (typeId, hkUnit) = LabTestMapping.healthKitType(for: testName) else {
            return false
        }

        guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeId) else {
            return false
        }

        let quantity = HKQuantity(unit: hkUnit, doubleValue: value)

        var metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: true,
            HKMetadataKeyWasTakenInLab: true,
        ]
        if let refLow {
            metadata[HKMetadataKeyReferenceRangeLowerLimit] = refLow
        }
        if let refHigh {
            metadata[HKMetadataKeyReferenceRangeUpperLimit] = refHigh
        }

        let sample = HKQuantitySample(
            type: quantityType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: metadata
        )

        do {
            try await healthStore.save(sample)
            return true
        } catch {
            print("HealthKit write error: \(error.localizedDescription)")
            return false
        }
    }

    // Note: Reading clinical records (HKClinicalRecord.labResultRecord)
    // requires a paid Apple Developer Program membership.
    // Can be re-enabled later if you upgrade your account.
}
