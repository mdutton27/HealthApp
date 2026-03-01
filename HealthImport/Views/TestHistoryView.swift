import SwiftUI
import SwiftData
import Charts

struct TestHistoryView: View {
    let testName: String
    let unit: String

    @Query private var allResults: [LabResult]

    private var results: [LabResult] {
        allResults
            .filter { $0.testName == testName }
            .sorted { $0.observationDate < $1.observationDate }
    }

    private var latestResult: LabResult? {
        results.last
    }

    private var refLow: Double? {
        latestResult?.referenceRangeLow.flatMap { Double($0) }
    }

    private var refHigh: Double? {
        latestResult?.referenceRangeHigh.flatMap { Double($0) }
    }

    var body: some View {
        List {
            // Current value header
            if let latest = latestResult {
                Section {
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(latest.value)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            Text(latest.unit)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        StatusBadge(status: latest.status)

                        if let low = latest.referenceRangeLow, let high = latest.referenceRangeHigh,
                           !low.isEmpty || !high.isEmpty {
                            Text("Reference: \(low) - \(high) \(latest.unit)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(latest.observationDate, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }

            // Trend chart
            if results.count > 1 {
                Section("Trend") {
                    chartView
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }

            // All readings
            Section("All Readings (\(results.count))") {
                ForEach(results.reversed(), id: \.id) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.observationDate, style: .date)
                                .font(.subheadline)
                            if let doctor = result.doctor {
                                Text(doctor)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(result.value)
                                    .font(.subheadline.monospacedDigit().bold())
                                Text(result.unit)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            StatusBadge(status: result.status, compact: true)
                        }
                    }

                    if let comments = result.clinicianComments, !comments.isEmpty, comments != "ok" {
                        Text(comments)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.leading, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(testName)
    }

    @ViewBuilder
    private var chartView: some View {
        let numericResults = results.filter { $0.numericValue != nil }

        if numericResults.isEmpty {
            Text("No numeric values to chart")
                .foregroundStyle(.secondary)
        } else {
            Chart {
                // Reference range band
                if let low = refLow, let high = refHigh,
                   let firstDate = numericResults.first?.observationDate,
                   let lastDate = numericResults.last?.observationDate {
                    RectangleMark(
                        xStart: .value("Start", firstDate),
                        xEnd: .value("End", lastDate),
                        yStart: .value("Low", low),
                        yEnd: .value("High", high)
                    )
                    .foregroundStyle(.green.opacity(0.1))
                }

                // Data line
                ForEach(numericResults, id: \.id) { result in
                    LineMark(
                        x: .value("Date", result.observationDate),
                        y: .value("Value", result.numericValue ?? 0)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Date", result.observationDate),
                        y: .value("Value", result.numericValue ?? 0)
                    )
                    .foregroundStyle(result.status == .normal || result.status == .unknown ? .blue : .orange)
                    .symbolSize(40)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    NavigationStack {
        TestHistoryView(testName: "Haemoglobin", unit: "g/L")
    }
    .modelContainer(for: LabResult.self, inMemory: true)
}
