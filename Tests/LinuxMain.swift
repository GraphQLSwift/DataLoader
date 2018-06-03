import XCTest

@testable import SwiftDataLoaderTests

XCTMain([
    testCase(DataLoaderAbuseTests.allTests),
    testCase(DataLoaderTests.allTests)
])
