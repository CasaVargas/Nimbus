import SwiftUI

struct BrowserToolbar: ViewModifier {
    @Binding var viewMode: ViewMode
    @Binding var sortField: SortField
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onNewFolder: () -> Void
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(!canGoBack)
                .help("Back (⌘[)")

                Button(action: onForward) {
                    Label("Forward", systemImage: "chevron.right")
                }
                .disabled(!canGoForward)
                .help("Forward (⌘])")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: onNewFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Folder")

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")

                Picker("View", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
                }
                .pickerStyle(.segmented)

                Picker("Sort", selection: $sortField) {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
            }
        }
    }
}
