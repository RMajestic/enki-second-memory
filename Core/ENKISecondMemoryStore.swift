import Foundation
import CryptoKit
import ImageIO
import Darwin

enum ENKISecondMemoryError: String, LocalizedError {
    case locked = "Desbloquea ENKI y vuelve a autorizar la operación."
    case consent = "Confirma que quieres guardar esta imagen y el análisis en este iPhone."
    case invalid = "La observación o su evidencia no se pueden verificar."
    case storage = "No se pudo completar la operación local; no se han borrado otros recuerdos."
    case limit = "Se alcanzó el límite de memoria o falta espacio. Elimina recuerdos individualmente."
    case busy = "Hay otra operación de memoria en curso. Espera y vuelve a intentarlo."
    case duplicate = "Esta observación ya está guardada."
    var errorDescription: String? { rawValue }
}

struct ENKISecondMemoryRecord: Codable, Identifiable, Sendable {
    enum Origin: String, Codable, Sendable { case rayBanMetaLive, syntheticTest }
    let version: Int
    let id: UUID
    let capturedAt: Date
    let savedAt: Date
    let imageSHA256: String
    let response: Data
    let responseJSONSHA256: String
    let origin: Origin
    static func observationDate(_ timestamp: String) -> Date? {
        let precise = ISO8601DateFormatter(); precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
    func analysis() throws -> ENKIRemoteVisualResult {
        guard ENKISecondMemoryStore.digest(response) == responseJSONSHA256 else { throw ENKISecondMemoryError.invalid }
        let raw = try JSONDecoder().decode(ENKIRemoteVisualResult.self, from: response)
        let checked = try ENKIRemoteVisualResult.parse(response, expectedID: id.uuidString.lowercased(), timestamp: raw.timestamp)
        let stamp = Self.observationDate(raw.timestamp)
        guard version == 1, stamp == capturedAt, savedAt.timeIntervalSince1970.isFinite,
              imageSHA256.count == 64, imageSHA256.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw ENKISecondMemoryError.invalid }
        return checked
    }
}

struct ENKISecondMemoryListing: Sendable {
    let records: [ENKISecondMemoryRecord]
    let unreadable: [UUID]
}

enum ENKISecondMemoryQuery {
    static func words(_ value: String) -> Set<String> {
        Set(value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .split(whereSeparator: { !$0.isLetter }).map(String.init))
    }
    private static let keys: Set<String> = ["llave", "llaves", "llavero", "llaveros", "key", "keys", "keyring", "keychain"]
    static func supports(_ question: String) -> Bool {
        question.count <= 300 && !words(question).isDisjoint(with: keys)
    }
    static func lastKeys(in records: [ENKISecondMemoryRecord]) -> ENKISecondMemoryRecord? {
        keyRecords(in: records).first
    }
    static func keyRecords(in records: [ENKISecondMemoryRecord]) -> [ENKISecondMemoryRecord] {
        records.filter { record in
            guard let result = try? record.analysis() else { return false }
            return result.objects.contains { object in
                let terms = words(object.label)
                return !terms.isDisjoint(with: keys) && terms.isDisjoint(with: ["no", "sin", "not", "without"])
            }
        }.sorted { $0.capturedAt == $1.capturedAt ? $0.id.uuidString < $1.id.uuidString : $0.capturedAt > $1.capturedAt }
    }
}

/// Isolated, explicit-save store. One atomic protected file per observation.
/// Existing Apple Vision memory, Photos and media-library files are never opened.
actor ENKISecondMemoryStore {
    static let maximumRecords = 40
    static let maximumFileBytes = 1_600_000
    private struct Envelope: Codable { let record: ENKISecondMemoryRecord; let image: Data }
    private let root: URL
    private let authorize: @MainActor @Sendable () -> Bool
    private var operating = false
    #if DEBUG
    private var beforeCommit: (@Sendable () async -> Void)?
    func setBeforeCommit(_ hook: (@Sendable () async -> Void)?) { beforeCommit = hook }
    #endif

    init(root: URL? = nil, authorize: @escaping @MainActor @Sendable () -> Bool) {
        // Canonicalize only the OS-provided home, not an arbitrary memory root.
        let canonicalHome = realpath(NSHomeDirectory(), nil)
        let home = canonicalHome.map { String(cString: $0) } ?? NSHomeDirectory()
        if let canonicalHome { free(canonicalHome) }
        let support = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support", isDirectory: true)
        self.root = root ?? support.appendingPathComponent("ENKI/SecondMemoryV1", isDirectory: true)
        self.authorize = authorize
    }
    private func check() async throws {
        try Task.checkCancellation()
        guard await authorize() else { throw ENKISecondMemoryError.locked }
        try Task.checkCancellation()
    }
    private func enter() throws {
        guard !operating else { throw ENKISecondMemoryError.busy }; operating = true
    }
    private func openRoot() throws -> Int32 {
        guard root.isFileURL, root.path.hasPrefix("/") else { throw ENKISecondMemoryError.invalid }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ENKISecondMemoryError.storage }
        do {
            for component in root.pathComponents.dropFirst() {
                guard component != ".", component != "..", !component.contains("/"), !component.contains("\0") else { throw ENKISecondMemoryError.invalid }
                if mkdirat(fd, component, 0o700) != 0 && errno != EEXIST { throw ENKISecondMemoryError.storage }
                let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw ENKISecondMemoryError.invalid }
                close(fd); fd = next
            }
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
            #endif
            guard fchmod(fd, 0o700) == 0 else { throw ENKISecondMemoryError.storage }
            // Explicit local-only policy; report backup exclusion in the physical protocol.
            var url = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return fd
        } catch { close(fd); throw error }
    }
    private func lock(_ fd: Int32) throws -> Int32 {
        let lease = openat(fd, ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lease >= 0 else { throw ENKISecondMemoryError.storage }
        var info = stat()
        guard fstat(lease, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              flock(lease, LOCK_EX | LOCK_NB) == 0 else { close(lease); throw ENKISecondMemoryError.busy }
        return lease
    }
    private func ids(_ fd: Int32) throws -> [UUID] {
        let copy = dup(fd)
        guard copy >= 0, let stream = fdopendir(copy) else { if copy >= 0 { close(copy) }; throw ENKISecondMemoryError.storage }
        defer { closedir(stream) }; rewinddir(stream)
        var result: [UUID] = [], total = 0
        while true {
            errno = 0
            guard let item = readdir(stream) else {
                guard errno == 0 else { throw ENKISecondMemoryError.storage }; break
            }
            total += 1; guard total <= 500 else { throw ENKISecondMemoryError.limit }
            let name = withUnsafePointer(to: &item.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) } }
            let suffix = name.hasSuffix(".json") ? ".json" : (name.hasSuffix(".pending") ? ".pending" : "")
            guard !suffix.isEmpty, let id = UUID(uuidString: String(name.dropLast(suffix.count))), name == id.uuidString + suffix else { continue }
            if !result.contains(id) { result.append(id) }
        }
        return result
    }
    private func read(_ fd: Int32, id: UUID) throws -> Envelope {
        let file = openat(fd, id.uuidString + ".json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw ENKISecondMemoryError.invalid }; defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= Self.maximumFileBytes else { throw ENKISecondMemoryError.invalid }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(file, &buffer, buffer.count)
            guard count >= 0 else { throw ENKISecondMemoryError.storage }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
            guard bytes.count <= Self.maximumFileBytes else { throw ENKISecondMemoryError.limit }
        }
        let value = try JSONDecoder().decode(Envelope.self, from: bytes)
        guard value.record.id == id, value.image.count <= 1_000_000,
              Self.digest(value.image) == value.record.imageSHA256 else { throw ENKISecondMemoryError.invalid }
        _ = try value.record.analysis()
        try Self.validateImage(value.image)
        return value
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func validateImage(_ data: Data) throws {
        guard !data.isEmpty, data.count <= 1_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 1280, height <= 1280, width * height <= 1_000_000,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw ENKISecondMemoryError.invalid }
    }

    func list() async throws -> ENKISecondMemoryListing {
        try enter(); defer { operating = false }; try await check()
        let fd = try openRoot(); defer { close(fd) }; let lease = try lock(fd); defer { close(lease) }
        var records: [ENKISecondMemoryRecord] = [], unreadable: [UUID] = []
        for id in try ids(fd) {
            if let item = try? read(fd, id: id) { records.append(item.record) } else { unreadable.append(id) }
        }
        try await check()
        return .init(records: records.sorted { $0.capturedAt > $1.capturedAt }, unreadable: unreadable)
    }
    func evidence(_ id: UUID) async throws -> Data {
        try enter(); defer { operating = false }; try await check()
        let fd = try openRoot(); defer { close(fd) }; let lease = try lock(fd); defer { close(lease) }
        let bytes = try read(fd, id: id).image; try await check(); return bytes
    }
    func save(image: Data, result: ENKIRemoteVisualResult, origin: ENKISecondMemoryRecord.Origin,
              explicitConsent: Bool) async throws -> ENKISecondMemoryRecord {
        try enter(); defer { operating = false }; try await check()
        guard explicitConsent else { throw ENKISecondMemoryError.consent }
        try Self.validateImage(image)
        guard let id = UUID(uuidString: result.observation_id), let stamp = ENKISecondMemoryRecord.observationDate(result.timestamp) else { throw ENKISecondMemoryError.invalid }
        let response = try JSONEncoder().encode(result)
        let record = ENKISecondMemoryRecord(version: 1, id: id, capturedAt: stamp, savedAt: Date(),
            imageSHA256: Self.digest(image), response: response, responseJSONSHA256: Self.digest(response), origin: origin)
        _ = try record.analysis()
        let bytes = try JSONEncoder().encode(Envelope(record: record, image: image))
        guard bytes.count <= Self.maximumFileBytes else { throw ENKISecondMemoryError.limit }
        let fd = try openRoot(); defer { close(fd) }; let lease = try lock(fd); defer { close(lease) }
        guard try ids(fd).count < Self.maximumRecords else { throw ENKISecondMemoryError.limit }
        var disk = statfs(); guard fstatfs(fd, &disk) == 0,
            UInt64(disk.f_bavail) * UInt64(disk.f_bsize) > UInt64(bytes.count + 32 * 1024 * 1024) else { throw ENKISecondMemoryError.limit }
        let destination = id.uuidString + ".json"
        var existing = stat()
        guard fstatat(fd, destination, &existing, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else { throw ENKISecondMemoryError.duplicate }
        let pending = id.uuidString + ".pending"
        let file = openat(fd, pending, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw ENKISecondMemoryError.storage }
        defer { close(file); unlinkat(fd, pending, 0) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.appendingPathComponent(pending).path)
        #endif
        try bytes.withUnsafeBytes { raw in
            var position = 0
            while position < raw.count {
                let n = Darwin.write(file, raw.baseAddress!.advanced(by: position), raw.count - position)
                guard n > 0 else { throw ENKISecondMemoryError.storage }; position += n
            }
        }
        guard fsync(file) == 0 else { throw ENKISecondMemoryError.storage }
        #if DEBUG
        if let beforeCommit { await beforeCommit() }
        #endif
        try await check()
        // linkat refuses replacement, commits the exact protected inode, and never follows symlinks.
        guard linkat(fd, pending, fd, destination, 0) == 0 else { throw ENKISecondMemoryError.storage }
        return record
    }
    func delete(_ id: UUID, explicitConsent: Bool) async throws {
        try enter(); defer { operating = false }; try await check()
        guard explicitConsent else { throw ENKISecondMemoryError.consent }
        let fd = try openRoot(); defer { close(fd) }; let lease = try lock(fd); defer { close(lease) }
        let names = [id.uuidString + ".json", id.uuidString + ".pending"]
        var found: [String] = []
        for name in names {
            var value = stat()
            if fstatat(fd, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw ENKISecondMemoryError.storage }; continue
            }
            guard value.st_mode & S_IFMT == S_IFREG || value.st_mode & S_IFMT == S_IFLNK else { throw ENKISecondMemoryError.invalid }
            found.append(name)
        }
        guard !found.isEmpty else { throw ENKISecondMemoryError.invalid }
        try await check()
        for name in found {
            guard unlinkat(fd, name, 0) == 0 else { throw ENKISecondMemoryError.storage }
        }
        for name in names {
            var value = stat()
            guard fstatat(fd, name, &value, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else { throw ENKISecondMemoryError.storage }
        }
    }
}
