import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var importManager = FileImportManager()
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch importManager.importState {
                case .idle:
                    idleView
                case .parsing:
                    progressView("Parsing file...")
                case .previewing(let count):
                    previewView(count: count)
                case .saving:
                    progressView("Saving results...")
                case .complete:
                    completeView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Import Lab Results")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText, .xml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task {
                            await importManager.parseFile(url: url)
                        }
                    }
                case .failure(let error):
                    importManager.importState = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Sub-views

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Import Lab Results")
                .font(.title2.bold())

            Text("Select a CSV or XML file containing your lab results. The app will automatically detect test names, values, and reference ranges.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 8) {
                Label("CSV files (comma-separated)", systemImage: "tablecells")
                Label("XML files (Apple Health export format)", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                showFilePicker = true
            } label: {
                Label("Select File", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func previewView(count: Int) -> some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)

                Text("\(count) results found")
                    .font(.title3.bold())

                Text("Review the results below, then tap Import to save them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()

            // Preview list
            List {
                let grouped = Dictionary(grouping: importManager.previewResults) { $0.testGroup }
                let sortedGroups = grouped.keys.sorted {
                    LabTestMapping.sortIndex(for: $0) < LabTestMapping.sortIndex(for: $1)
                }

                ForEach(sortedGroups, id: \.self) { group in
                    Section(LabTestMapping.normaliseGroupName(group)) {
                        ForEach(grouped[group] ?? [], id: \.testName) { result in
                            HStack {
                                Text(result.testName)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(result.value) \(result.unit)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            // Action buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    importManager.reset()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task {
                        await importManager.confirmImport(modelContext: modelContext)
                    }
                } label: {
                    Text("Import \(count) Results")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
    }

    private var completeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Import Complete")
                .font(.title2.bold())

            if let summary = importManager.lastImportSummary {
                VStack(spacing: 12) {
                    summaryRow("New results saved", value: "\(summary.newRecords)")
                    if summary.duplicatesSkipped > 0 {
                        summaryRow("Duplicates skipped", value: "\(summary.duplicatesSkipped)")
                    }
                    if summary.healthKitWritten > 0 {
                        summaryRow("Written to HealthKit", value: "\(summary.healthKitWritten)")
                    }
                    if !summary.groups.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test groups imported:")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(summary.groups, id: \.self) { group in
                                    Text(group)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(.blue.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 32)
            }

            Button {
                importManager.reset()
            } label: {
                Text("Import Another File")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func progressView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Import Error")
                .font(.title2.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                importManager.reset()
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}

/// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

#Preview {
    ImportView()
        .modelContainer(for: LabResult.self, inMemory: true)
}
