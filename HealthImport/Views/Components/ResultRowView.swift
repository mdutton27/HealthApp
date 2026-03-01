import SwiftUI

struct ResultRowView: View {
    let result: LabResult
    var showDate: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.testName)
                    .font(.subheadline)
                if showDate {
                    Text(result.observationDate, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Text("\(result.value)")
                    .font(.subheadline.monospacedDigit().bold())
                Text(result.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StatusBadge(status: result.status, compact: true)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    List {
        ResultRowView(result: LabResult(
            testName: "Haemoglobin",
            testGroup: "Complete Blood Count",
            value: "141",
            unit: "g/L",
            observationDate: Date(),
            referenceRangeLow: "130",
            referenceRangeHigh: "175"
        ))
        ResultRowView(result: LabResult(
            testName: "Testosterone",
            testGroup: "Hormones",
            value: "8.1",
            unit: "nmol/L",
            observationDate: Date(),
            referenceRangeLow: "8.7",
            referenceRangeHigh: "29.0"
        ))
    }
    .modelContainer(for: LabResult.self, inMemory: true)
}
