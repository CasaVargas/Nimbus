import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Nimbus

@Suite("Settings About", .serialized)
@MainActor
struct AboutSettingsTests {
    @Test func bothPaidAppsAreListedWithWorkingLinksAndBundledIcons() {
        #expect(StudioApp.all.map(\.name) == ["Beltr", "OneScribe"])
        for app in StudioApp.all {
            #expect(app.url.scheme == "https")
            #expect(!app.tagline.isEmpty)
            #expect(NSImage(named: app.imageName) != nil, "missing icon \(app.imageName)")
        }
        // The Beltr link says where the visit came from.
        #expect(StudioApp.all[0].url.absoluteString.contains("utm_source=nimbus-app"))
        #expect(StudioApp.all[1].url.host == "apps.apple.com")
    }

    @Test func aboutIsTheLastSettingsTab() {
        #expect(SettingsTab.allCases.last == .about)
        #expect(SettingsTab.about.title == "About")
    }

    @Test func rendersTheAboutPane() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            AboutSettingsView().background(DesignSystem.Color.semantic.surface),
            size: CGSize(width: 720, height: 520),
            named: "Settings-About"
        )
    }

    @Test func rendersTheSidebarSettingsRow() throws {
        try SnapshotHelpers.assertHostedSnapshot(
            SidebarSettingsLink().frame(width: 220).padding(8).background(DesignSystem.Color.semantic.surface),
            size: CGSize(width: 236, height: 48),
            named: "Sidebar-settings-row"
        )
    }
}
