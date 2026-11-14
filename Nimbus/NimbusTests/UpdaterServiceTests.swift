import Foundation
import Testing
@testable import Nimbus

@Suite("Updater service")
@MainActor
struct UpdaterServiceTests {
    @Test func switchWritesThroughToTheDriver() {
        let driver = FakeUpdateDriver()
        let service = UpdaterService(driver: driver)
        #expect(!service.automaticallyChecks)

        service.setAutomaticallyChecks(true)
        #expect(driver.automaticallyChecksForUpdates)
        #expect(service.automaticallyChecks)

        service.setAutomaticallyChecks(false)
        #expect(!driver.automaticallyChecksForUpdates)
        #expect(!service.automaticallyChecks)
    }

    /// Sparkle's permission prompt changes the setting behind the service.
    @Test func followsChangesTheDriverMakes() {
        let driver = FakeUpdateDriver()
        let service = UpdaterService(driver: driver)

        driver.automaticallyChecksForUpdates = true
        driver.onChange?()

        #expect(service.automaticallyChecks)
    }

    @Test func cannotCheckBeforeStarting() {
        let driver = FakeUpdateDriver()
        let service = UpdaterService(driver: driver)
        #expect(!service.canCheck)

        service.start()
        #expect(service.canCheck)
    }

    @Test func startsOnce() {
        let driver = FakeUpdateDriver()
        let service = UpdaterService(driver: driver)

        service.start()
        service.start()
        service.startWhenActive(isActive: true)

        #expect(driver.startCount == 1)
    }

    @Test func hiddenLaunchWaitsForTheAppToBecomeActive() {
        let driver = FakeUpdateDriver()
        let service = UpdaterService(driver: driver)

        service.startWhenActive(isActive: false)
        #expect(driver.startCount == 0)
        #expect(!service.hasStarted)

        service.startWhenActive(isActive: true)
        #expect(driver.startCount == 1)
    }

    @Test func checkingStartsTheUpdaterFirst() {
        let driver = FakeUpdateDriver()
        let service = UpdaterService(driver: driver)

        service.checkForUpdates()

        #expect(driver.startCount == 1)
        #expect(driver.checkCount == 1)
    }

    @Test func withoutADriverEverythingIsOffAndInert() {
        let service = UpdaterService(driver: nil)

        service.setAutomaticallyChecks(true)
        service.start()
        service.startWhenActive(isActive: true)
        service.checkForUpdates()

        #expect(!service.isAvailable)
        #expect(!service.automaticallyChecks)
        #expect(!service.canCheck)
        #expect(!service.hasStarted)
    }

    @Test func hostedAndDebugLaunchesGetNoUpdater() {
        let defaults = isolatedDefaults()
        #expect(UpdaterService.wantsUpdater(context: .normal, defaults: defaults, isDebugBuild: false))
        #expect(!UpdaterService.wantsUpdater(context: .testHost, defaults: defaults, isDebugBuild: false))
        #expect(!UpdaterService.wantsUpdater(context: .previewHost, defaults: defaults, isDebugBuild: false))
        #expect(!UpdaterService.wantsUpdater(context: .normal, defaults: defaults, isDebugBuild: true))

        defaults.set(true, forKey: "debugEnableUpdater")
        #expect(UpdaterService.wantsUpdater(context: .normal, defaults: defaults, isDebugBuild: true))
        #expect(!UpdaterService.wantsUpdater(context: .testHost, defaults: defaults, isDebugBuild: true))
    }

    /// The test host itself must never start Sparkle.
    @Test func theTestHostHasNoUpdater() {
        #expect(!UpdaterService.live().isAvailable)
    }

    private func isolatedDefaults() -> UserDefaults {
        let defaults = ScratchDefaults.make("Updater")
        return defaults
    }
}

@MainActor
final class FakeUpdateDriver: UpdateDriver {
    var automaticallyChecksForUpdates = false
    var canCheckForUpdates: Bool { startCount > 0 }
    var onChange: (@MainActor () -> Void)?
    private(set) var startCount = 0
    private(set) var checkCount = 0

    func start() { startCount += 1 }
    func checkForUpdates() { checkCount += 1 }
}
