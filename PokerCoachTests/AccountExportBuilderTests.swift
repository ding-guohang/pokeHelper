import Foundation
import XCTest
@testable import PokerCoach

@MainActor
final class AccountExportBuilderTests: XCTestCase {
    private var root: URL!
    private let generatedAt = Date(timeIntervalSince1970: 1_786_300_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "Export-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBundleCarriesAManifestListingEveryFile() throws {
        let profile = try makeProfile()
        let destination = root.appending(path: "bundle", directoryHint: .isDirectory)

        _ = try makeBuilder().build(
            remote: remoteExport(),
            profile: profile,
            destination: destination
        )

        let manifest = try decodeManifest(in: destination)
        XCTAssertEqual(manifest.schemaVersion, AccountExportBuilder.bundleSchemaVersion)
        XCTAssertEqual(manifest.generatedAt, generatedAt)
        XCTAssertEqual(manifest.files, ["account.json"])
        for file in manifest.files {
            let url = destination.appending(path: file, directoryHint: .notDirectory)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                "manifest lists \(file) but it is missing"
            )
        }
    }

    // Corrupted backups are the user's hands too, so an export must include
    // them. They are copied verbatim because they exist precisely because the
    // parser rejected them.
    func testCorruptedBackupsAreIncludedVerbatim() throws {
        let profile = try makeProfile()
        let backupBytes = Data("{broken\n".utf8)
        let backupName = "training-events.corrupted-\(UUID().uuidString).jsonl"
        try backupBytes.write(
            to: profile.directory.appending(path: backupName, directoryHint: .notDirectory)
        )
        let destination = root.appending(path: "bundle", directoryHint: .isDirectory)

        _ = try makeBuilder().build(
            remote: remoteExport(),
            profile: profile,
            destination: destination
        )

        let copied = destination
            .appending(path: "backups", directoryHint: .isDirectory)
            .appending(path: backupName, directoryHint: .notDirectory)
        XCTAssertEqual(try Data(contentsOf: copied), backupBytes)

        let manifest = try decodeManifest(in: destination)
        XCTAssertTrue(manifest.files.contains("backups/\(backupName)"))
    }

    func testBundleContainsNoCredentialMaterial() throws {
        let profile = try makeProfile()
        let destination = root.appending(path: "bundle", directoryHint: .isDirectory)

        _ = try makeBuilder().build(
            remote: remoteExport(),
            profile: profile,
            destination: destination
        )

        let accountFile = destination.appending(
            path: "account.json",
            directoryHint: .notDirectory
        )
        let text = try String(contentsOf: accountFile, encoding: .utf8)
        for forbidden in [
            "accessToken", "refreshToken", "passwordHash", "password_hash",
            "$argon2id$", "tokenHash", "token_hash",
        ] {
            XCTAssertFalse(text.contains(forbidden), "export bundle leaked \(forbidden)")
        }
    }

    func testExportedEventsKeepTheServersShape() throws {
        let profile = try makeProfile()
        let destination = root.appending(path: "bundle", directoryHint: .isDirectory)

        _ = try makeBuilder().build(
            remote: remoteExport(),
            profile: profile,
            destination: destination
        )

        let accountFile = destination.appending(
            path: "account.json",
            directoryHint: .notDirectory
        )
        let decoded = try JSONSerialization.jsonObject(
            with: try Data(contentsOf: accountFile)
        ) as? [String: Any]
        let events = decoded?["events"] as? [[String: Any]]
        XCTAssertEqual(events?.count, 1)
        XCTAssertEqual(events?.first?["abilityDimension"] as? String, "bet-sizing")
    }

    private func makeBuilder() -> AccountExportBuilder {
        AccountExportBuilder(now: { [generatedAt] in generatedAt })
    }

    private func makeProfile() throws -> ActiveProfile {
        let directory = root.appending(path: "profile", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ActiveProfile(
            id: .anonymous,
            localUserID: UUID(),
            deviceID: UUID(),
            directory: directory
        )
    }

    private func decodeManifest(in destination: URL) throws -> AccountExportBuilder.Manifest {
        let url = destination.appending(path: "manifest.json", directoryHint: .notDirectory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            AccountExportBuilder.Manifest.self,
            from: try Data(contentsOf: url)
        )
    }

    private func remoteExport() throws -> RemoteAccountExport {
        let json = """
        {
          "schemaVersion": 1,
          "account": {
            "userID": "11111111-1111-4111-8111-111111111111",
            "createdAt": "2026-08-01T00:00:00Z"
          },
          "devices": [
            {"displayName": "iPhone", "platform": "iOS", "appVersion": "1.0.0"}
          ],
          "events": [
            {"abilityDimension": "bet-sizing", "id": "00000000-0000-0000-0000-000000000001"}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RemoteAccountExport.self, from: Data(json.utf8))
    }
}
