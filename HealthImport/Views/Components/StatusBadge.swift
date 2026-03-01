import SwiftUI

struct StatusBadge: View {
    let status: ResultStatus
    var compact: Bool = false

    private var color: Color {
        switch status {
        case .normal: .green
        case .low: .orange
        case .high: .red
        case .unknown: .gray
        }
    }

    private var icon: String {
        switch status {
        case .normal: "checkmark.circle.fill"
        case .low: "arrow.down.circle.fill"
        case .high: "arrow.up.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    private var label: String {
        switch status {
        case .normal: "Normal"
        case .low: "Low"
        case .high: "High"
        case .unknown: "N/A"
        }
    }

    var body: some View {
        if compact {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
        } else {
            Label(label, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusBadge(status: .normal)
        StatusBadge(status: .low)
        StatusBadge(status: .high)
        StatusBadge(status: .unknown)
        HStack {
            StatusBadge(status: .normal, compact: true)
            StatusBadge(status: .low, compact: true)
            StatusBadge(status: .high, compact: true)
        }
    }
}
