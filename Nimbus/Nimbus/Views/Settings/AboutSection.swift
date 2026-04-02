import SwiftUI

struct AboutSection: View {
    var body: some View {
        Form {
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            }
            LabeledContent("Build") {
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
            }
        }
    }
}
