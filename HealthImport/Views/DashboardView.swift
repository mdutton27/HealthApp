import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \LabResult.observationDate, order: .reverse) private var allResults: [LabResult]
    @State private var searchText = ""

    private var groupedResults: [(group: String, results: [LabResult])] {
        let filtered: [LabResult]
        if searchText.isEmpty {
            filtered = allResults
        } else {
            filtered = allResults.filter {
                $0.testName.localizedCaseInsensitiveContains(searchText) ||
                $0.testGroup.localizedCaseInsensitiveContains(searchText)
            }
        }

        let dict = Dictionary(grouping: filtered) {
            LabTestMapping.normaliseGroupName($0.testGroup)
        }

        return dict.map { (group: $0.key, results: $0.value) }
            .sorted { LabTestMapping.sortIndex(for: $0.group) < LabTestMapping.sortIndex(for: $1.group) }
    }

    /// Latest result per test name within a group
    private func latestResults(for results: [LabResult]) -> [LabResult] {
        var seen = Set<String>()
        var latest: [LabResult] = []
        let sorted = results.sorted { $0.observationDate > $1.observationDate }
        for r in sorted {
            if seen.insert(r.testName).inserted {
                latest.append(r)
            }
        }
        return latest.sorted { $0.testName < $1.testName }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allResults.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Lab Results")
            .searchable(text: $searchText, prompt: "Search tests...")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "list.clipboard")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No Results Yet")
                .font(.title2.bold())
            Text("Import a CSV or XML file from the Import tab to see your lab results here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var resultsList: some View {
        List {
            // Summary header
            Section {
                HStack(spacing: 16) {
                    statCard(title: "Tests", value: "\(uniqueTestCount)", icon: "flask.fill", color: .blue)
                    statCard(title: "Groups", value: "\(groupedResults.count)", icon: "folder.fill", color: .purple)
                    statCard(title: "Abnormal", value: "\(abnormalCount)", icon: "exclamationmark.triangle.fill", color: abnormalCount > 0 ? .orange : .green)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Test groups
            ForEach(groupedResults, id: \.group) { group, results in
                Section {
                    NavigationLink {
                        TestGroupDetailView(groupName: group)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: LabTestMapping.icon(for: group))
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(group)
                                    .font(.headline)
                                let latest = latestResults(for: results)
                                Text("\(latest.count) tests")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            let abnormal = latestResults(for: results).filter { $0.status == .high || $0.status == .low }
                            if !abnormal.isEmpty {
                                Text("\(abnormal.count)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Show latest results inline
                    ForEach(latestResults(for: results).prefix(3), id: \.id) { result in
                        NavigationLink {
                            TestHistoryView(testName: result.testName, unit: result.unit)
                        } label: {
                            ResultRowView(result: result)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var uniqueTestCount: Int {
        Set(allResults.map { $0.testName }).count
    }

    private var abnormalCount: Int {
        // Count unique tests that are currently abnormal (latest reading)
        var seen = Set<String>()
        var count = 0
        let sorted = allResults.sorted { $0.observationDate > $1.observationDate }
        for r in sorted {
            if seen.insert(r.testName).inserted {
                if r.status == .high || r.status == .low {
                    count += 1
                }
            }
        }
        return count
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: LabResult.self, inMemory: true)
}
