import XCTest
@testable import PurePaceCore

final class SemanticVersionTests: XCTestCase {
    func testParsesStrictThreeComponentVersions() throws {
        let cases: [(text: String, major: Int, minor: Int, patch: Int)] = [
            ("1.2.3", 1, 2, 3),
            ("0.0.0", 0, 0, 0),
            ("10.20.30", 10, 20, 30)
        ]

        for item in cases {
            let version = try XCTUnwrap(
                SemanticVersion(parsing: item.text),
                "应解析合法版本 \(item.text)"
            )
            XCTAssertEqual(version.major, item.major)
            XCTAssertEqual(version.minor, item.minor)
            XCTAssertEqual(version.patch, item.patch)
        }
    }

    func testRejectsMalformedVersions() {
        let invalid = [
            "1.2",
            "1.2.3.4",
            "v1.2.3",
            "1.2.3-rc1",
            "01.2.3",
            "1.2.3 ",
            "",
            "a.b.c",
            "1.-2.3",
            "1.2.03",
            " 1.2.3",
            "1..3",
            "+1.2.3"
        ]

        for text in invalid {
            XCTAssertNil(
                SemanticVersion(parsing: text),
                "应拒绝非法版本 \(text.debugDescription)"
            )
        }
    }

    func testComparesComponentsSegmentBySegment() throws {
        let low = try XCTUnwrap(SemanticVersion(parsing: "1.2.3"))
        let highPatch = try XCTUnwrap(SemanticVersion(parsing: "1.2.10"))
        let highMinor = try XCTUnwrap(SemanticVersion(parsing: "1.10.0"))
        let lowMinor = try XCTUnwrap(SemanticVersion(parsing: "1.9.9"))
        let same = try XCTUnwrap(SemanticVersion(parsing: "1.2.3"))

        XCTAssertLessThan(low, highPatch)
        XCTAssertGreaterThan(highMinor, lowMinor)
        XCTAssertEqual(low, same)
        XCTAssertFalse(low < same)
        XCTAssertFalse(same < low)
        XCTAssertLessThan(lowMinor, highMinor)
    }

    func testDescriptionRoundTrips() throws {
        for text in ["1.2.3", "0.0.0", "10.20.30"] {
            let version = try XCTUnwrap(SemanticVersion(parsing: text))
            XCTAssertEqual(version.description, text)
            XCTAssertEqual(SemanticVersion(parsing: version.description), version)
        }
    }
}
