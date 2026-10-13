import SwiftUI

extension EnvironmentValues {
    @Entry var diagnosticsService: DiagnosticsService?
    @Entry var transferNotifier: (any TransferNotifying)?
}
