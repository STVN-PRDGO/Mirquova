import Cocoa
import FlutterMacOS
import XCTest
@testable import mirquova

class RunnerTests: XCTestCase {

  func testReleasePageBoundary() {
    XCTAssertTrue(MainFlutterWindow.isReleasePage(
      "https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0+3"
    ))
    for value in [
      "http://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0",
      "https://github.com.evil.test/STVN-PRDGO/Mirquova/releases/tag/v0.3.0",
      "https://github.com:443/STVN-PRDGO/Mirquova/releases/tag/v0.3.0",
      "https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0?next=evil",
      "https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0%2Fevil",
      "https://github.com/STVN-PRDGO/Mirquova/releases/tag/v0.3.0\n",
    ] {
      XCTAssertFalse(MainFlutterWindow.isReleasePage(value), value)
    }
  }

}
