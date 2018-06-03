import XCTest

import SwiftDataLoaderTests

var tests = [XCTestCaseEntry]()
tests += DataLoaderTests.allTests()
tests += DataLoaderAbuseTests.allTests()
XCTMain(tests)
