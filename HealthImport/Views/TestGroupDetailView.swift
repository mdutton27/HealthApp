import SwiftUI
import SwiftData

struct TestGroupDetailView: View {
    let groupName: String

    @Query private var allResults: [LabResult]
    @State private var showAllDates = false

    init(groupName: String) {
        self.groupName = groupName
    }

    private var groupResults: [LabResult] {
        allResults.filter {
            LabTestMapping.normaliseGroupName($0.testGroup) == groupName
        }
    }

    /// All unique test names in this group
    private var testNames: [String] {
        let names = Set(groupResults.map { $0.testName })
        return names.sorted()
    }

    /// Latest result for each test
    private func latestResult(for testName: String) -> LabResult? {
        groupResults
            .filter { $0.testName == testName }
            .sorted { $0.observationDate > $1.observationDate }
            .first
    }

    /// All unique dates for this group, sorted descending
    private var allDates: [Date] {
        let dates = Set(groupResults.map { Calendar.current.startOfDay(for: $0.observationDate) })
        return dates.sorted(by: >)
    }

    var body: some View {
        List {
            // Latest results section
            Section("Latest Results") {
                ForEach(testNames, id: \.self) { name in
                    if let result = latestResult(for: name) {
                        NavigationLink {
                            TestHistoryView(testName: name, unit: result.unit)
                        } label: {
                            ResultRowView(result: result)
                        }
                    }
                }
            }

            // Historical dates
            Section("History") {
                let dates = showAllDates ? allDates : Array(allDates.prefix(5))
                ForEach(dates, id: \.self) { date in
                    DisclosureGroup {
                        let dayResults = groupResults.filter {
                            Calendar.current.isDate($0.observationDate, inSameDayAs: date)
                        }.sorted { $0.testName < $1.testName }

                        ForEach(dayResults, id: \.id) { result in
                            ResultRowView(result: result, showDate: false)
                        }
                    } label: {
                        HStack {
                            Text(date, style: .date)
                                .font(.subheadline.bold())
                            Spacer()
                            let dayResults = groupResults.filter {
                                Calendar.current.isDate($0.observationDate, inSameDayAs: date)
                            }
                            let abnormal = dayResults.filter { $0.status == .high || $0.status == .low }
                            if !abnormal.isEmpty {
                                StatusBadge(status: .high)
                            }
                        }
                    }
                }

                if allDates.count > 5, !showAllDates {
                    Button("Show All \(allDates.count) Dates") {
                        showAllDates = true
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(groupName)
    }
}

#Preview {
    NavigationStack {
        TestGroupDetailView(groupName: "Complete Blood Count")
    }
    .modelContainer(for: LabResult.self, inMemory: true)
}
