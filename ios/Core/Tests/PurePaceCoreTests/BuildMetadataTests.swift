import XCTest
@testable import PurePaceCore

final class BuildMetadataTests: XCTestCase {
    func testAcceptsValidDisplayNameAndVersion() throws {
        let version = try XCTUnwrap(SemanticVersion(parsing: "2.4.6"))
        let metadata = try XCTUnwrap(BuildMetadata(displayName: "PurePace", version: version))

        XCTAssertEqual(metadata.displayName, "PurePace")
        XCTAssertEqual(metadata.version, version)
    }

    func testAcceptsValidVersionString() throws {
        let metadata = try XCTUnwrap(
            BuildMetadata(displayName: "PurePace", versionString: "3.1.4")
        )

        XCTAssertEqual(metadata.displayName, "PurePace")
        XCTAssertEqual(metadata.version.description, "3.1.4")
    }

    func testPreservesDisplayNameExactlyAsProvided() throws {
        let version = try XCTUnwrap(SemanticVersion(parsing: "1.0.0"))
        let metadata = try XCTUnwrap(BuildMetadata(displayName: " PurePace ", version: version))

        XCTAssertEqual(metadata.displayName, " PurePace ")
    }

    func testRejectsEmptyOrWhitespaceDisplayName() throws {
        let version = try XCTUnwrap(SemanticVersion(parsing: "1.0.0"))

        for name in ["", " ", "   ", "\n", "\t \n"] {
            XCTAssertNil(
                BuildMetadata(displayName: name, version: version),
                "应拒绝空白显示名 \(name.debugDescription)"
            )
            XCTAssertNil(
                BuildMetadata(displayName: name, versionString: "1.0.0"),
                "应拒绝空白显示名 \(name.debugDescription)"
            )
        }
    }

    func testRejectsInvalidVersionString() {
        for text in ["1.2", "v1.2.3", "1.2.3-rc1", "01.2.3", ""] {
            XCTAssertNil(
                BuildMetadata(displayName: "PurePace", versionString: text),
                "应拒绝非法版本字符串 \(text.debugDescription)"
            )
        }
    }
}
