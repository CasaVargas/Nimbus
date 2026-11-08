import SwiftUI

/// Actions the frontmost browser exposes to the menu bar. Published by
/// `BrowserView` via `.focusedSceneValue`; consumed by `AppCommands` so the
/// File/Go/View menus operate on whichever browser has focus.
struct BrowserMenuActions {
    var canGoBack: Bool
    var canGoForward: Bool
    var viewMode: ViewMode
    var goBack: () -> Void
    var goForward: () -> Void
    var newFolder: () -> Void
    var refresh: () -> Void
    var setViewMode: (ViewMode) -> Void
}

extension FocusedValues {
    @Entry var browserActions: BrowserMenuActions?
    @Entry var sidebarSelection: Binding<SidebarSelection?>?
}

/// The app's menu bar. New Window is deliberately replaced — a second
/// window sharing one daemon/mount state is untested territory — and its
/// ⌘N goes to New Folder, matching the in-app "use ⌘N" copy.
struct AppCommands: Commands {
    @FocusedValue(\.browserActions) private var browser
    @FocusedValue(\.sidebarSelection) private var sidebarSelection

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Folder") { browser?.newFolder() }
                .keyboardShortcut("n")
                .disabled(browser == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("as List") { browser?.setViewMode(.list) }
                .keyboardShortcut("1")
                .disabled(browser == nil)
            Button("as Grid") { browser?.setViewMode(.grid) }
                .keyboardShortcut("2")
                .disabled(browser == nil)
            Divider()
            Button("Refresh") { browser?.refresh() }
                .keyboardShortcut("r")
                .disabled(browser == nil)
        }

        CommandMenu("Go") {
            Button("Back") { browser?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(browser?.canGoBack ?? false))
            Button("Forward") { browser?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(browser?.canGoForward ?? false))
            Divider()
            Button("Home") { sidebarSelection?.wrappedValue = .home }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Copy Between Clouds") { sidebarSelection?.wrappedValue = .copySync }
                .keyboardShortcut("4", modifiers: [.command, .shift])
            Button("Backups") { sidebarSelection?.wrappedValue = .backups }
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }
}
