import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DataLoaderTests.allTests),
        testCase(DataLoaderAbuseTests.allTests)
    ]
}
#endif
