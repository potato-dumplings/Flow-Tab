import Foundation

extension RuntimeLogFileStore {
    static func makeRandomFingerprintKey() -> Data {
        Data((0..<fingerprintKeyByteCount).map { _ in UInt8.random(in: .min ... .max) })
    }

    func prepareStorageLocked() throws {
        if !fileManager.fileExists(atPath: logsDirectoryURL.path) {
            try fileManager.createDirectory(
                at: logsDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.directoryPermissions]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: Self.directoryPermissions],
            ofItemAtPath: logsDirectoryURL.path
        )
        try migrateLegacyLogsIfNeededLocked()
        try enforcePrivateFilePermissionsLocked()
    }

    private func migrateLegacyLogsIfNeededLocked() throws {
        let v1MarkerURL = logsDirectoryURL.appendingPathComponent(
            Self.privacyFormatMarkerFileName,
            isDirectory: false
        )
        let v2MarkerURL = logsDirectoryURL.appendingPathComponent(
            Self.privacyV2FormatMarkerFileName,
            isDirectory: false
        )

        if fileManager.fileExists(atPath: v1MarkerURL.path) {
            try secureFilePermissionsLocked(at: v1MarkerURL)
        } else {
            let existingURLs = try fileManager.contentsOfDirectory(
                at: logsDirectoryURL,
                includingPropertiesForKeys: nil
            )
            for url in existingURLs where url.pathExtension.lowercased() == "log" {
                try fileManager.removeItem(at: url)
            }
            try createSecureFileLocked(
                at: v1MarkerURL,
                contents: Data("1\n".utf8)
            )
            activeLogURL = nil
        }

        if fileManager.fileExists(atPath: v2MarkerURL.path) {
            try secureFilePermissionsLocked(at: v2MarkerURL)
        } else {
            try createSecureFileLocked(
                at: v2MarkerURL,
                contents: Data("2\n".utf8)
            )
        }
    }

    private func enforcePrivateFilePermissionsLocked() throws {
        var privateURLs = allManagedLogFileURLsLocked()
        privateURLs.append(
            logsDirectoryURL.appendingPathComponent(
                Self.privacyFingerprintKeyFileName,
                isDirectory: false
            )
        )
        privateURLs.append(
            logsDirectoryURL.appendingPathComponent(
                Self.privacyFormatMarkerFileName,
                isDirectory: false
            )
        )
        privateURLs.append(
            logsDirectoryURL.appendingPathComponent(
                Self.privacyV2FormatMarkerFileName,
                isDirectory: false
            )
        )
        for url in privateURLs where fileManager.fileExists(atPath: url.path) {
            try secureFilePermissionsLocked(at: url)
        }
    }

    func secureFilePermissionsLocked(at url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: url.path
        )
    }

    func createSecureFileLocked(at url: URL, contents: Data) throws {
        let didCreate = fileManager.createFile(
            atPath: url.path,
            contents: contents,
            attributes: [.posixPermissions: Self.filePermissions]
        )
        guard didCreate else {
            throw CocoaError(.fileWriteUnknown)
        }
        try secureFilePermissionsLocked(at: url)
    }

    func replaceSecureFileLocked(at url: URL, contents: Data) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try createSecureFileLocked(at: url, contents: contents)
            return
        }
        try secureFilePermissionsLocked(at: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: contents)
    }
}
