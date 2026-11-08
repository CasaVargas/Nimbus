import Testing
import Foundation
import FileProvider
@testable import Nimbus

@Suite("FileProviderErrorText")
struct FileProviderErrorTextTests {
    @Test func providerNotFoundExplainsWhereNimbusMustRun() {
        let error = NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.Code.providerNotFound.rawValue)
        let text = FileProviderErrorText.describe(error)
        #expect(text.contains("NSFileProviderErrorDomain -2001"))
        #expect(text.contains("/Applications"))
    }

    @Test func otherErrorsReportDomainAndCodeOnly() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: 13,
                            userInfo: [NSLocalizedDescriptionKey: "Permission denied: /Users/someone/secret"])
        let text = FileProviderErrorText.describe(error)
        #expect(text == "NSPOSIXErrorDomain 13")
        #expect(!text.contains("/Users"))
    }
}
