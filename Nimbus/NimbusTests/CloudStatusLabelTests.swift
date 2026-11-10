import Testing
import Foundation
@testable import Nimbus

@Suite("CloudStatusLabel")
struct CloudStatusLabelTests {
    @Test func aFileInTheCloudOnlySaysSo() {
        #expect(CloudStatusLabel.text(state: .cloud, isKept: false, isDirectory: false) == "In cloud")
    }

    @Test func aDownloadedFileSaysSo() {
        #expect(CloudStatusLabel.text(state: .local, isKept: false, isDirectory: false) == "Downloaded")
    }

    @Test func keptWinsOverDownloaded() {
        // Kept is the stronger promise: macOS won't remove it to free space.
        #expect(CloudStatusLabel.text(state: .local, isKept: true, isDirectory: false) == "Kept on this Mac")
        #expect(CloudStatusLabel.text(state: .cloud, isKept: true, isDirectory: false) == "Kept on this Mac")
    }

    @Test func aFolderOnlySpeaksWhenItIsKept() {
        // A folder isn't downloaded or not as a whole; its files are.
        #expect(CloudStatusLabel.text(state: .local, isKept: false, isDirectory: true) == "--")
        #expect(CloudStatusLabel.text(state: .local, isKept: true, isDirectory: true) == "Kept on this Mac")
    }

    @Test func aTransferShowsItsProgress() {
        #expect(CloudStatusLabel.text(state: .downloading(progress: 0.456), isKept: false, isDirectory: false) == "Copying 46%")
    }

    @Test func aRemovedDownloadReadsAsInCloudAgain() {
        #expect(CloudStatusLabel.text(state: .evicted, isKept: false, isDirectory: false) == "In cloud")
    }

    @Test func anErrorIsNamed() {
        #expect(CloudStatusLabel.text(state: .error(reason: "x"), isKept: false, isDirectory: false) == "Problem")
    }
}
