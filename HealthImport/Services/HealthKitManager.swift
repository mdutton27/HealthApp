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

    /// Types we want to read from HealthKit (quantity types only — safe for all accounts)
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            types.insert(glucose)
        }
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
            // First: authorize standard quantity types (always safe)
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            await MainActor.run {
                isAuthorized = true
                authorizationError = nil
            }

            // Then: try clinical records separately so it doesn't crash the app
            await requestClinicalAuthorization()
        } catch {
            await MainActor.run {
                authorizationError = error.localizedDescription
                isAuthorized = false
            }
        }
    }

    /// Attempt clinical records authorization separately — this will silently fail
    /// on simulators or if the entitlement isn't fully provisioned yet.
    private func requestClinicalAuthorization() async {
        guard let labType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) else {
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [labType])
        } catch {
            // Clinical records not available (simulator, missing entitlement, etc.)
            // This is fine — the app works without it.
            print("Clinical records auth not available: \(error.localizedDescription)")
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

    // MARK: - Reading Clinical Records

    func fetchClinicalLabResults() async -> [HKClinicalRecord] {
        guard let labType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: labType,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let records = (samples as? [HKClinicalRecord]) ?? []
                continuation.resume(returning: records)
            }
            healthStore.execute(query)
        }
    }
}
