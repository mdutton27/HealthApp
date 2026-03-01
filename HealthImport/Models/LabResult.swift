import Foundation
import SwiftData

@Model
final class LabResult {
    var id: UUID
    var testName: String
    var testGroup: String
    var value: String
    var numericValue: Double?
    var unit: String
    var referenceRangeLow: String?
    var referenceRangeHigh: String?
    var observationDate: Date
    var dateReceived: String?
    var clinicianComments: String?
    var doctor: String?
    var location: String?
    var importDate: Date
    var sourceName: String?

    var status: ResultStatus {
        guard let numeric = numericValue else { return .unknown }
        if let lowStr = referenceRangeLow, let low = Double(lowStr), numeric < low {
            return .low
        }
        if let highStr = referenceRangeHigh, let high = Double(highStr), numeric > high {
            return .high
        }
        if referenceRangeLow != nil || referenceRangeHigh != nil {
            return .normal
        }
        return .unknown
    }

    init(
        testName: String,
        testGroup: String,
        value: String,
        unit: String,
        observationDate: Date,
        referenceRangeLow: String? = nil,
        referenceRangeHigh: String? = nil,
        dateReceived: String? = nil,
        clinicianComments: String? = nil,
        doctor: String? = nil,
        location: String? = nil,
        sourceName: String? = nil
    ) {
        self.id = UUID()
        self.testName = testName
        self.testGroup = testGroup
        self.value = value
        self.numericValue = Double(value)
        self.unit = unit
        self.observationDate = observationDate
        self.referenceRangeLow = referenceRangeLow
        self.referenceRangeHigh = referenceRangeHigh
        self.dateReceived = dateReceived
        self.clinicianComments = clinicianComments
        self.doctor = doctor
        self.location = location
        self.importDate = Date()
        self.sourceName = sourceName
    }
}

enum ResultStatus: String, Codable {
    case normal
    case low
    case high
    case unknown
}
