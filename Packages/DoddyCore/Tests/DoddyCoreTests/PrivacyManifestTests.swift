import Foundation
import XCTest
@testable import DoddyCore

/// The app's privacy manifest (`DoddyApp/Resources/PrivacyInfo.xcprivacy`) declares exactly the data types
/// `DataFlow.collectedData` lists, with the same linked flag and purposes, and every type names rows of What leaves
/// this iPhone that exist. The manifest is read from the repository, so a hand edit to either side fails here.
final class PrivacyManifestTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private struct Declared: Equatable {
        let linked: Bool
        let tracking: Bool
        let purposes: Set<String>
    }

    private func manifest(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent(path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], path)
    }

    private func declaredTypes(_ path: String) throws -> [String: Declared] {
        let plist = try manifest(path)
        let entries = try XCTUnwrap(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]], "\(path) lists no collected types")
        var types: [String: Declared] = [:]
        for entry in entries {
            let type = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String)
            XCTAssertNil(types[type], "\(type) is declared twice")
            types[type] = Declared(
                linked: try XCTUnwrap(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, type),
                tracking: try XCTUnwrap(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, type),
                purposes: Set(try XCTUnwrap(entry["NSPrivacyCollectedDataTypePurposes"] as? [String], type)))
        }
        return types
    }

    func testTheAppManifestDeclaresExactlyWhatDataFlowLists() throws {
        let declared = try declaredTypes("DoddyApp/Resources/PrivacyInfo.xcprivacy")
        let listed = Dictionary(uniqueKeysWithValues: DataFlow.collectedData.map {
            ($0.type, Declared(linked: $0.linked, tracking: $0.tracking, purposes: Set($0.purposes.map(\.rawValue))))
        })
        XCTAssertEqual(DataFlow.collectedData.count, listed.count, "a type is listed twice in DataFlow.collectedData")
        XCTAssertEqual(
            Set(declared.keys).subtracting(listed.keys), [],
            "declared in PrivacyInfo.xcprivacy but not in DataFlow.collectedData")
        XCTAssertEqual(
            Set(listed.keys).subtracting(declared.keys), [],
            "listed in DataFlow.collectedData but not declared in PrivacyInfo.xcprivacy")
        for (type, entry) in listed {
            XCTAssertEqual(declared[type], entry, "\(type): linked, tracking or purposes differ between the manifest and DataFlow")
        }
    }

    func testEveryCollectedTypeNamesRowsThatExist() {
        let ids = Set(DataFlow.rows(DataFlowState(
            rememberConversations: true, shareProfileWithVoice: true, tokenServerSet: true, connectionsOn: [],
            pauseAll: false, doddyServerSet: true, askDoddyOn: true, askDoddyUsesNotes: true)).map(\.id))
        for type in DataFlow.collectedData {
            XCTAssertFalse(type.rows.isEmpty, "\(type.type) names no row")
            for row in type.rows {
                XCTAssertTrue(ids.contains(row), "\(type.type) names \(row), which What leaves this iPhone doesn't have")
            }
        }
    }

    /// What the code sends and keeps under the account (12 Nov 2026 review): these are declared, and linked.
    func testTheTypesTheCodeSendsAreDeclaredAsLinked() throws {
        let declared = try declaredTypes("DoddyApp/Resources/PrivacyInfo.xcprivacy")
        for type in ["EmailAddress", "ProductInteraction", "PhotosorVideos", "Health", "Fitness", "Contacts", "DeviceID", "UserID"] {
            let entry = try XCTUnwrap(declared["NSPrivacyCollectedDataType" + type], "\(type) isn't declared")
            XCTAssertTrue(entry.linked, "\(type) is kept under the Doddy account, so it is linked")
            XCTAssertFalse(entry.tracking)
        }
        // Logbook is analytics as well as the person's own page on the web.
        XCTAssertEqual(
            declared["NSPrivacyCollectedDataTypeProductInteraction"]?.purposes,
            ["NSPrivacyCollectedDataTypePurposeAnalytics", "NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        XCTAssertEqual(try manifest("DoddyApp/Resources/PrivacyInfo.xcprivacy")["NSPrivacyTracking"] as? Bool, false)
    }

    /// The extensions send nothing themselves: their manifests declare no collected data and no tracking.
    /// Which required-reason APIs they declare is checked by scripts/check_privacy_manifest.sh.
    func testExtensionManifestsCollectNothingAndTrackNobody() throws {
        for path in ["DoddyWidgets/PrivacyInfo.xcprivacy", "DoddyShare/PrivacyInfo.xcprivacy", "DoddyScreen/PrivacyInfo.xcprivacy"] {
            let plist = try manifest(path)
            XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false, path)
            XCTAssertEqual((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0, path)
        }
    }
}
