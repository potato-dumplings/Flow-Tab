import Darwin
import Dispatch
import Foundation

private struct FlowTabUITestRuntimeLogFileAnchor {
    let byteCount: UInt64
    let fileNumber: UInt64?
    let creationDate: Date?
}

final class FlowTabUITestRuntimeLogObservationBaseline {
    let logsDirectoryURL: URL
    let baselineFileEventGeneration: UInt64

    private let fileManager: FileManager
    private let anchorsByPath:
        [String: FlowTabUITestRuntimeLogFileAnchor]
    private let fileEventSource:
        FlowTabUITestRuntimeLogFileEventSource

    init(
        logsDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.logsDirectoryURL = logsDirectoryURL
        self.fileManager = fileManager
        let watchRootURL = logsDirectoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileEventSource =
            FlowTabUITestRuntimeLogFileEventSource(
                logsDirectoryURL: logsDirectoryURL,
                watchRootURL: watchRootURL,
                fileManager: fileManager
            )
        self.fileEventSource = fileEventSource
        anchorsByPath = Self.logFileURLs(
            in: logsDirectoryURL,
            fileManager: fileManager
        )
        .reduce(into: [:]) { anchors, url in
            guard
                let anchor = Self.fileAnchor(
                    at: url,
                    fileManager: fileManager
                )
            else {
                return
            }
            anchors[url.path] = anchor
        }
        baselineFileEventGeneration =
            fileEventSource.generation
    }

    var fileEventGeneration: UInt64 {
        fileEventSource.generation
    }

    func fileEventObservationRegistration()
        -> FlowTabUITestConditionObservationRegistration
    {
        { [fileEventSource] readback in
            fileEventSource.addObserver {
                readback(.notificationReadback)
            }
        }
    }

    func readContents() -> String {
        Self.logFileURLs(
            in: logsDirectoryURL,
            fileManager: fileManager
        )
        .compactMap { url -> String? in
            guard
                let data = try? Data(contentsOf: url)
            else {
                return nil
            }
            let offset = startOffset(
                for: url,
                currentByteCount: data.count
            )
            return String(
                data: data.dropFirst(offset),
                encoding: .utf8
            )
        }
        .joined(separator: "\n")
    }

    func cancel() {
        fileEventSource.cancel()
    }

    deinit {
        cancel()
    }

    static func readAllContents(
        in logsDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> String {
        logFileURLs(
            in: logsDirectoryURL,
            fileManager: fileManager
        )
        .compactMap { url in
            try? String(contentsOf: url, encoding: .utf8)
        }
        .joined(separator: "\n")
    }

    private func startOffset(
        for url: URL,
        currentByteCount: Int
    ) -> Int {
        guard
            let anchor = anchorsByPath[url.path],
            UInt64(currentByteCount) >= anchor.byteCount,
            let currentAnchor = Self.fileAnchor(
                at: url,
                fileManager: fileManager
            ),
            Self.representsSameFile(
                anchor,
                currentAnchor
            )
        else {
            return 0
        }
        return min(
            Int(clamping: anchor.byteCount),
            currentByteCount
        )
    }

    private static func fileAnchor(
        at url: URL,
        fileManager: FileManager
    ) -> FlowTabUITestRuntimeLogFileAnchor? {
        guard
            let attributes = try? fileManager
                .attributesOfItem(atPath: url.path),
            let byteCount = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return FlowTabUITestRuntimeLogFileAnchor(
            byteCount: byteCount.uint64Value,
            fileNumber:
                (attributes[.systemFileNumber] as? NSNumber)?
                    .uint64Value,
            creationDate: attributes[.creationDate] as? Date
        )
    }

    private static func representsSameFile(
        _ baseline: FlowTabUITestRuntimeLogFileAnchor,
        _ current: FlowTabUITestRuntimeLogFileAnchor
    ) -> Bool {
        if let fileNumber = baseline.fileNumber {
            return current.fileNumber == fileNumber
        }
        return current.fileNumber == nil
            && current.creationDate == baseline.creationDate
    }

    fileprivate static func logFileURLs(
        in logsDirectoryURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let files = (
            try? fileManager.contentsOfDirectory(
                at: logsDirectoryURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            )
        ) ?? []
        return files
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let lhsDate = (
                    try? lhs.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    )
                    .contentModificationDate
                ) ?? .distantPast
                let rhsDate = (
                    try? rhs.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    )
                    .contentModificationDate
                ) ?? .distantPast
                return lhsDate < rhsDate
            }
    }
}

private final class FlowTabUITestRuntimeLogFileEventSource {
    private static let eventMask:
        DispatchSource.FileSystemEvent = [
            .write,
            .extend,
            .attrib,
            .link,
            .rename,
            .delete
        ]

    private let logsDirectoryURL: URL
    private let watchRootURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    private var sourcesByPath:
        [String: DispatchSourceFileSystemObject] = [:]
    private var observers: [UUID: () -> Void] = [:]
    private var currentGeneration: UInt64 = 0
    private var isCancelled = false

    init(
        logsDirectoryURL: URL,
        watchRootURL: URL,
        fileManager: FileManager
    ) {
        self.logsDirectoryURL = logsDirectoryURL
        self.watchRootURL = watchRootURL
        self.fileManager = fileManager
        refreshWatches()
    }

    var generation: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return currentGeneration
    }

    func addObserver(
        _ observer: @escaping () -> Void
    ) -> FlowTabUITestObservationCancellation {
        let observerID = UUID()
        lock.lock()
        if !isCancelled {
            observers[observerID] = observer
        }
        lock.unlock()
        return FlowTabUITestObservationCancellation {
            [weak self] in
            self?.removeObserver(observerID)
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        observers.removeAll()
        let sources = Array(sourcesByPath.values)
        sourcesByPath.removeAll()
        lock.unlock()
        sources.forEach { $0.cancel() }
    }

    deinit {
        cancel()
    }

    private func removeObserver(_ observerID: UUID) {
        lock.lock()
        observers.removeValue(forKey: observerID)
        lock.unlock()
    }

    private func handleFileEvent() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        currentGeneration &+= 1
        let callbacks = Array(observers.values)
        lock.unlock()

        refreshWatches()
        callbacks.forEach { $0() }
    }

    private func refreshWatches() {
        let desiredPaths = Set(watchURLs().map(\.path))
        var removedSources: [
            DispatchSourceFileSystemObject
        ] = []

        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        let removedPaths = sourcesByPath.keys.filter {
            !desiredPaths.contains($0)
        }
        for path in removedPaths {
            if let source = sourcesByPath.removeValue(
                forKey: path
            ) {
                removedSources.append(source)
            }
        }
        for path in desiredPaths
            where sourcesByPath[path] == nil
        {
            let fileDescriptor = open(path, O_EVTONLY)
            guard fileDescriptor >= 0 else { continue }
            let source =
                DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fileDescriptor,
                    eventMask: Self.eventMask,
                    queue: .main
                )
            source.setEventHandler { [weak self] in
                self?.handleFileEvent()
            }
            source.setCancelHandler {
                Darwin.close(fileDescriptor)
            }
            sourcesByPath[path] = source
            source.resume()
        }
        lock.unlock()

        removedSources.forEach { $0.cancel() }
    }

    private func watchURLs() -> [URL] {
        var logsDirectoryIsDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: logsDirectoryURL.path,
            isDirectory: &logsDirectoryIsDirectory
        ),
           logsDirectoryIsDirectory.boolValue
        {
            return [logsDirectoryURL]
                + FlowTabUITestRuntimeLogObservationBaseline
                .logFileURLs(
                    in: logsDirectoryURL,
                    fileManager: fileManager
                )
        }

        var candidate = logsDirectoryURL
        while true {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: candidate.path,
                isDirectory: &isDirectory
            ),
               isDirectory.boolValue
            {
                return [candidate]
            }
            if candidate.standardizedFileURL
                == watchRootURL.standardizedFileURL
            {
                break
            }
            let parent = candidate
                .deletingLastPathComponent()
            guard parent.path != candidate.path else {
                break
            }
            candidate = parent
        }
        return []
    }
}
