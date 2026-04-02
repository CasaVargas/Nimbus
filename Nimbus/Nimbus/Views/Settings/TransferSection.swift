import SwiftUI

struct TransferSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            TextField("Bandwidth Limit", text: $settings.bandwidthLimit, prompt: Text("e.g., 10M (empty for unlimited)"))
            Stepper("Concurrent Transfers: \(settings.concurrentTransfers)", value: $settings.concurrentTransfers, in: 1...20)
        }
    }
}
