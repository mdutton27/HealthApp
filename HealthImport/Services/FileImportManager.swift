import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Orchestrates file import: detects format, parses, deduplicates, and saves to SwiftData + HealthKit.
@MainActor
final class FileImportManager: ObservableObject {

    @Published var importState: ImportState = .idle
    @Published var lastImportSummary: ImportSummary?

    enum ImportState: Equatable {
        case idle
        case parsing
        case previewing(count: Int)
        case saving
        case complete
        case error(String)
    }

    struct ImportSummary {
        let totalParsed: Int
        let newRecords: Int
        let duplicatesSkipped: Int
        let healthKitWritten: Int
        let groups: [String]
    }

    /// Supported file types for the document picker
    static let supportedTypes: [UTType] = [
        .commaSeparatedText,
        .xml,
        UTType(filenameExtension: "csv") ?? .commaSeparatedText,
        UTType(filenameExtension: "xml") ?? .xml,
    ]

    private var pendingResults: [LabResult] = []

    // MARK: - Import Flow

    /// Parse a file and prepare results for preview
    func parseFile(url: URL) async {
        importState = .parsing
        pendingResults = []

        // Gain access to security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let ext = url.pathExtension.lowercased()
            if ext == "xml" {
                pendingResults = try parseXML(url: url)
            } else {
                pendingResults = try parseCSV(url: url)
            }
            importState = .previewing(count: pendingResults.count)
        } catch {
            importState = .error(error.localizedDescription)
        }
    }

    /// Save parsed results to SwiftData and HealthKit
    func confirmImport(modelContext: ModelContext) async {
        importState = .saving

        var newCount = 0
        var dupCount = 0
        var hkCount = 0
        var groupSet = Set<String>()

        for result in pendingResults {
            // Check for duplicates
            let name = result.testName
            let date = result.observationDate
            let val = result.value
            let predicate = #Predicate<LabResult> { r in
                r.testName == name &&
                r.observationDate == date &&
                r.value == val
            }
            let descriptor = FetchDescriptor<LabResult>(predicate: predicate)
            let existing = (try? modelContext.fetchCount(descriptor)) ?? 0

            if existing > 0 {
                dupCount += 1
                continue
            }

            modelContext.insert(result)
            newCount += 1
            groupSet.insert(LabTestMapping.normaliseGroupName(result.testGroup))

            // Write to HealthKit if mapping exists
            if let numeric = result.numericValue {
                let wrote = await HealthKitManager.shared.writeToHealthKit(
                    testName: result.testName,
                    value: numeric,
                    unit: result.unit,
                    date: result.observationDate,
                    refLow: result.referenceRangeLow.flatMap { Double($0) },
                    refHigh: result.referenceRangeHigh.flatMap { Double($0) }
                )
                if wrote { hkCount += 1 }
            }
        }

        try? modelContext.save()

        lastImportSummary = ImportSummary(
            totalParsed: pendingResults.count,
            newRecords: newCount,
            duplicatesSkipped: dupCount,
            healthKitWritten: hkCount,
            groups: groupSet.sorted()
        )

        pendingResults = []
        importState = .complete
    }

    func reset() {
        importState = .idle
        pendingResults = []
        lastImportSummary = nil
    }

    var previewResults: [LabResult] {
        pendingResults
    }

    // MARK: - Parsers

    private func parseCSV(url: URL) throws -> [LabResult] {
        let rows = try CSVParser.parse(url: url)
        return rows.compactMap { row in
            // Skip rows that look like notes/non-lab-data
            guard !row.testName.isEmpty, !row.value.isEmpty else { return nil }

            return LabResult(
                testName: row.testName,
                testGroup: row.testGroup,
                value: row.value,
                unit: row.unit,
                observationDate: row.observationDate,
                referenceRangeLow: row.refRangeLow,
                referenceRangeHigh: row.refRangeHigh,
                dateReceived: row.dateReceived,
                clinicianComments: row.clinicianComments,
                doctor: row.doctor,
                location: row.location,
                sourceName: "CSV Import"
            )
        }
    }

    private func parseXML(url: URL) throws -> [LabResult] {
        let records = try HealthXMLParser.parse(url: url)
        return records.map { rec in
            LabResult(
                testName: rec.testName,
                testGroup: rec.testGroup,
                value: rec.value,
                unit: rec.unit,
                observationDate: rec.observationDate,
                referenceRangeLow: rec.refRangeLow,
                referenceRangeHigh: rec.refRangeHigh,
                dateReceived: rec.dateReceived,
                clinicianComments: rec.clinicianComments,
                doctor: rec.doctor,
                location: rec.location,
                sourceName: rec.sourceName ?? "XML Import"
            )
        }
    }
}
