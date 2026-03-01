import Foundation

/// Parses Apple Health–style XML exports containing lab results.
/// Handles the format exported by ManageMyHealth and similar apps.
final class HealthXMLParser: NSObject, XMLParserDelegate {

    struct ParsedRecord {
        let testName: String
        let testGroup: String
        let value: String
        let unit: String
        let observationDate: Date
        let refRangeLow: String?
        let refRangeHigh: String?
        let clinicianComments: String?
        let doctor: String?
        let location: String?
        let dateReceived: String?
        let sourceName: String?
    }

    enum XMLError: LocalizedError {
        case parseFailed(String)
        case noRecords

        var errorDescription: String? {
            switch self {
            case .parseFailed(let msg): return "XML parsing failed: \(msg)"
            case .noRecords: return "No lab result records found in XML."
            }
        }
    }

    private var records: [ParsedRecord] = []
    private var currentMetadata: [String: String] = [:]
    private var currentAttributes: [String: String] = [:]
    private var inRecord = false
    private var parseError: Error?

    /// Parse XML data from a URL
    static func parse(url: URL) throws -> [ParsedRecord] {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    /// Parse XML data
    static func parse(data: Data) throws -> [ParsedRecord] {
        let handler = HealthXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()

        if let error = handler.parseError ?? parser.parserError {
            throw XMLError.parseFailed(error.localizedDescription)
        }

        if handler.records.isEmpty {
            throw XMLError.noRecords
        }

        return handler.records
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        if elementName == "Record" {
            inRecord = true
            currentAttributes = attributes
            currentMetadata = [:]
        } else if elementName == "MetadataEntry", inRecord {
            if let key = attributes["key"], let value = attributes["value"] {
                currentMetadata[key] = value
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard elementName == "Record", inRecord else { return }
        inRecord = false

        let testName = currentMetadata["HKMetadataKeyLabTestName"] ?? ""
        guard !testName.isEmpty else { return }

        let value = currentAttributes["value"] ?? ""
        guard !value.isEmpty else { return }

        let unit = currentMetadata["HKMetadataKeyUnit"]
            ?? currentAttributes["unit"]
            ?? ""

        let observationDate = Self.parseISO8601(currentAttributes["startDate"]) ?? Date()

        let record = ParsedRecord(
            testName: testName,
            testGroup: currentMetadata["HKMetadataKeyLabTestGroup"] ?? "Other",
            value: value,
            unit: unit,
            observationDate: observationDate,
            refRangeLow: nonEmpty(currentMetadata["HKMetadataKeyReferenceRangeLow"]),
            refRangeHigh: nonEmpty(currentMetadata["HKMetadataKeyReferenceRangeHigh"]),
            clinicianComments: nonEmpty(currentMetadata["HKMetadataKeyClinicianComments"]),
            doctor: nonEmpty(currentMetadata["HKMetadataKeyDoctor"]),
            location: nonEmpty(currentMetadata["HKMetadataKeyLocation"]),
            dateReceived: nonEmpty(currentMetadata["HKMetadataKeyDateReceived"]),
            sourceName: currentAttributes["sourceName"]
        )
        records.append(record)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    // MARK: - Helpers

    private static func parseISO8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        // Try basic format like "2025-09-03T08:00:00"
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: string)
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
