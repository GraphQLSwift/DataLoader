import XCTest

import DataLoaderTests

var tests = [XCTestCaseEntry]()
tests += DataLoaderTests.allTests()
tests += DataLoaderAbuseTests.allTests()
XCTMain(tests)
