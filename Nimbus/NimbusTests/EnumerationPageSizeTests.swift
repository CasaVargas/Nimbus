import Testing
@testable import Nimbus

struct EnumerationPageSizeTests {
    @Test func usesTheLargestPageTheSystemAllows() {
        #expect(EnumerationPageSize.size(suggested: 200) == 20_000)
        #expect(EnumerationPageSize.size(suggested: 1) == 100)
    }

    @Test func fallsBackWithoutASuggestion() {
        #expect(EnumerationPageSize.size(suggested: nil) == 500)
        #expect(EnumerationPageSize.size(suggested: 0) == 500)
        #expect(EnumerationPageSize.size(suggested: -1) == 500)
    }

    @Test func doesNotOverflow() {
        #expect(EnumerationPageSize.size(suggested: Int.max) == Int.max)
    }
}
