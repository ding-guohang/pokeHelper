import Foundation
import HandHistoryPersistence

/// Where the personal hand library lives on disk and how the app opens it.
///
/// Kept out of `AppDependencies` on purpose: the library is reachable only from
/// the Hand Lab feature, so the feature owns its storage rather than widening
/// the app-wide dependency surface for one screen. The directory sits beside the
/// other profile data under the app's Library directory.
enum HandLabStorage {
    static func makeStore() throws -> FileHandLibraryStore {
        let directory = try libraryDirectory()
#if DEVELOPMENT_STRATEGY_FIXTURES
        if CommandLine.arguments.contains("--reset-hand-library") {
            try? FileManager.default.removeItem(at: directory)
        }
#endif
        return try FileHandLibraryStore(directory: directory)
    }

    /// Where hand-built spots are kept — beside the hand library, under the same
    /// profile data. Honours `--reset-hand-library` in a development build so a
    /// UI test starts from an empty builder store just as it does an empty
    /// library.
    static func makeConstructedSpotStore() throws -> FileConstructedSpotStore {
        let directory = try constructedSpotDirectory()
#if DEVELOPMENT_STRATEGY_FIXTURES
        if CommandLine.arguments.contains("--reset-hand-library") {
            try? FileManager.default.removeItem(at: directory)
        }
#endif
        return try FileConstructedSpotStore(directory: directory)
    }

    private static func libraryDirectory() throws -> URL {
        try base().appending(path: "handLibrary", directoryHint: .isDirectory)
    }

    private static func constructedSpotDirectory() throws -> URL {
        try base().appending(path: "constructedSpots", directoryHint: .isDirectory)
    }

    private static func base() throws -> URL {
        guard let library = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            throw HandLabStorageError.libraryDirectoryUnavailable
        }
        return library.appending(path: "PokerCoach", directoryHint: .isDirectory)
    }
}

enum HandLabStorageError: Error {
    case libraryDirectoryUnavailable
}
