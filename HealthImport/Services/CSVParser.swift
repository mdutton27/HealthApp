import Foundation

/// Parses CSV lab result files.
/// Expected columns: Observation Date, Date Received, Test Group, Test Name,
///                    Value, Unit, Ref Range Low, Ref Range High,
///                    Clinician Comments, Doctor, Location
struct CSVParser {

    struct ParsedRow {
        let observationDate: Date
        let dateReceived: String
        let testGroup: String
        let testName: String
        let value: String
        let unit: String
        let refRangeLow: String?
        let refRangeHigh: String?
        let clinicianComments: String?
        let doctor: String?
        let location: String?
    }

    enum CSVError: LocalizedError {
        case noData
        case noHeader
        case missingColumns(expected: [String], found: [String])
        case noValidRows

        var errorDescription: String? {
            switch self {
            case .noData: return "File contains no data."
            case .noHeader: return "Could not find CSV header row."
            case .missingColumns(let expected, let found):
                let missing = expected.filter { !found.contains($0) }
                return "Missing columns: \(missing.joined(separator: ", "))"
            case .noValidRows: return "No valid data rows found in file."
            }
        }
    }

    // Required columns (case-insensitive matching)
    private static let requiredColumns = ["test group", "test name", "value", "unit"]

    /// Parse CSV data from a URL
    static func parse(url: URL) throws -> [ParsedRow] {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CSVError.noData
        }
        return try parse(content: content)
    }

    /// Parse CSV content string
    static func parse(content: String) throws -> [ParsedRow] {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !lines.isEmpty else { throw CSVError.noData }
        guard lines.count > 1 else { throw CSVError.noHeader }

        // Parse header
        let headerLine = lines[0]
        let headers = parseCSVLine(headerLine).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        // Validate required columns exist
        let missingRequired = Self.requiredColumns.filter { req in
            !headers.contains(where: { $0.contains(req) })
        }
        if !missingRequired.isEmpty {
            throw CSVError.missingColumns(expected: Self.requiredColumns, found: headers)
        }

        // Build column index map
        let colIndex = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })

        // Parse data rows
        var rows: [ParsedRow] = []
        for i in 1..<lines.count {
            let fields = parseCSVLine(lines[i])
            guard fields.count >= 4 else { continue }

            let testName = field(fields, colIndex, matching: "test name")
            let testGroup = field(fields, colIndex, matching: "test group")
            let value = field(fields, colIndex, matching: "value")
            let unit = field(fields, colIndex, matching: "unit")

            guard !testName.isEmpty, !value.isEmpty else { continue }

            let obsDateStr = field(fields, colIndex, matching: "observation date")
            let observationDate = Self.parseDate(obsDateStr) ?? Date()

            let row = ParsedRow(
                observationDate: observationDate,
                dateReceived: field(fields, colIndex, matching: "date received"),
                testGroup: testGroup.isEmpty ? "Other" : testGroup,
                testName: testName,
                value: value,
                unit: unit,
                refRangeLow: nonEmpty(field(fields, colIndex, matching: "ref range low")),
                refRangeHigh: nonEmpty(field(fields, colIndex, matching: "ref range high")),
                clinicianComments: nonEmpty(field(fields, colIndex, matching: "clinician comments")),
                doctor: nonEmpty(field(fields, colIndex, matching: "doctor")),
                location: nonEmpty(field(fields, colIndex, matching: "location"))
            )
            rows.append(row)
        }

        if rows.isEmpty { throw CSVError.noValidRows }
        return rows
    }

    // MARK: - Helpers

    private static func field(_ fields: [String], _ index: [String: Int], matching keyword: String) -> String {
        for (key, idx) in index {
            if key.contains(keyword), idx < fields.count {
                return fields[idx].trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private static func nonEmpty(_ s: String) -> String? {
        s.isEmpty ? nil : s
    }

    /// Parse a CSV line handling quoted fields
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    /// Try multiple date formats
    private static func parseDate(_ string: String) -> Date? {
        let formatters: [String] = [
            "dd-MMM-yyyy",
            "dd MMM yyyy",
            "yyyy-MM-dd",
            "dd/MM/yyyy",
            "MM/dd/yyyy",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]
        for fmt in formatters {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            if let date = df.date(from: string) {
                return date
            }
        }
        return nil
    }
}
