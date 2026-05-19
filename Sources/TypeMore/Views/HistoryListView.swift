import SwiftUI

struct HistoryListView: View {
    var records: [TranscriptRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("历史记录")
                .font(.headline)

            if records.isEmpty {
                ContentUnavailableView("暂无历史记录", systemImage: "clock")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.text)
                            .lineLimit(2)
                        Text("\(record.targetApplicationName) • \(record.mode.title)\(record.optimizedWithLLM ? " • 大模型优化" : "") • \(record.createdAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180)
            }
        }
    }
}
