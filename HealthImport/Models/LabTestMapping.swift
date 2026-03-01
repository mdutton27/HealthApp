import Foundation
import HealthKit

/// Maps lab test names from CSV/XML to HealthKit quantity types where possible.
/// Most lab tests have NO native HealthKit type — only a handful are supported.
struct LabTestMapping {

    struct TestInfo {
        let displayName: String
        let group: String
        let healthKitType: HKQuantityTypeIdentifier?
        let healthKitUnit: HKUnit?
    }

    /// Tests that have a native HealthKit quantity type
    static let healthKitMappings: [String: (HKQuantityTypeIdentifier, HKUnit)] = [
        "Blood Glucose": (.bloodGlucose, HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))),
        "Glucose": (.bloodGlucose, HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))),
    ]

    /// Normalised test group names for consistent display
    static let groupDisplayNames: [String: String] = [
        "Complete Blood Count": "Complete Blood Count",
        "CBC": "Complete Blood Count",
        "Full Blood Count": "Complete Blood Count",
        "Liver Function Tests": "Liver Function",
        "LFT": "Liver Function",
        "Renal Function Tests": "Renal Function",
        "Kidney Function": "Renal Function",
        "Thyroid Function Tests": "Thyroid Function",
        "Iron Studies": "Iron Studies",
        "Crp": "Inflammation",
        "Quantitative Crp": "Inflammation",
        "Testosterone": "Hormones",
        "SHBG": "Hormones",
        "Cortisol": "Hormones",
        "Vitamin B12 And Folate": "Vitamins",
        "B12/Folate": "Vitamins",
        "Calcium/phos/ca.adj": "Bone & Minerals",
        "Haptoglobin": "Haematology",
        "Lactate Dehydrogenase": "Enzymes",
        "Gastric Autoantibodies": "Autoimmune",
        "Coeliac Antibodies": "Autoimmune",
        "Lipids": "Lipid Panel",
        "Cholesterol": "Lipid Panel",
    ]

    /// Group sort order for display
    static let groupSortOrder: [String] = [
        "Complete Blood Count",
        "Liver Function",
        "Renal Function",
        "Thyroid Function",
        "Iron Studies",
        "Lipid Panel",
        "Hormones",
        "Inflammation",
        "Vitamins",
        "Bone & Minerals",
        "Haematology",
        "Enzymes",
        "Autoimmune",
    ]

    /// Group icons for display
    static let groupIcons: [String: String] = [
        "Complete Blood Count": "drop.fill",
        "Liver Function": "liver.fill",
        "Renal Function": "kidney.fill",
        "Thyroid Function": "waveform.path.ecg",
        "Iron Studies": "atom",
        "Lipid Panel": "heart.fill",
        "Hormones": "bolt.fill",
        "Inflammation": "flame.fill",
        "Vitamins": "leaf.fill",
        "Bone & Minerals": "figure.stand",
        "Haematology": "drop.triangle.fill",
        "Enzymes": "bubbles.and.sparkles.fill",
        "Autoimmune": "shield.fill",
    ]

    static func normaliseGroupName(_ rawGroup: String) -> String {
        groupDisplayNames[rawGroup] ?? rawGroup
    }

    static func healthKitType(for testName: String) -> (HKQuantityTypeIdentifier, HKUnit)? {
        healthKitMappings[testName]
    }

    static func icon(for group: String) -> String {
        let normalised = normaliseGroupName(group)
        return groupIcons[normalised] ?? "cross.case.fill"
    }

    static func sortIndex(for group: String) -> Int {
        let normalised = normaliseGroupName(group)
        return groupSortOrder.firstIndex(of: normalised) ?? groupSortOrder.count
    }
}
