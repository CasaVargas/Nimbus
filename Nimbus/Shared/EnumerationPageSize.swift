import Foundation

/// How many items a folder's `enumerateItems` returns per page.
///
/// rclone has no paging: every page request lists and decodes the whole
/// folder again, and the system makes a new enumerator for each page, so
/// nothing carries over. A folder of N items cost N / pageSize full
/// listings (a 5,000-item folder took eleven at 500 per page). So a page
/// is as large as the system allows: 100 times the size it suggests
/// (`NSFileProviderEnumerationObserver.suggestedPageSize`). Without a
/// suggestion, pages keep the old size.
enum EnumerationPageSize {
    static let fallback = 500
    /// The system's limit, as a multiple of its suggested size.
    static let systemMaximumFactor = 100

    static func size(suggested: Int?) -> Int {
        guard let suggested, suggested > 0 else { return fallback }
        let (size, overflow) = suggested.multipliedReportingOverflow(by: systemMaximumFactor)
        return overflow ? Int.max : size
    }
}
