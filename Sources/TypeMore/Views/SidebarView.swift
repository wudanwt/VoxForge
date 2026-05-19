import SwiftUI

struct SidebarView: View {
    @Binding var selection: DictationMode

    var body: some View {
        List(selection: $selection) {
            Section("模式") {
                ForEach(DictationMode.allCases) { mode in
                    Label(mode.title, systemImage: symbol(for: mode))
                        .tag(mode)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("VoxForge")
    }

    private func symbol(for mode: DictationMode) -> String {
        switch mode {
        case .literal: "text.quote"
        case .general: "text.alignleft"
        case .codingPrompt: "chevron.left.forwardslash.chevron.right"
        }
    }
}
