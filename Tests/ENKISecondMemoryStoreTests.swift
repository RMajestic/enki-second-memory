// All images and provider results below are synthetic. No network, Keychain or owner data.
import Foundation
import Darwin

@MainActor final class MemoryAccess { var allowed = true }
actor MemoryBarrier {
    var entered = false
    var released = false
    func wait() async {
        entered = true
        while !released && !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000) }
    }
    func release() { released = true }
}

@main struct SecondMemoryStoreTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        var total = 0, failed = 0
        func check(_ title: String, _ value: Bool) { total += 1; if !value { failed += 1 }; print("\(value ? "PASS" : "FAIL") \(title)") }
        let temp = realpath(FileManager.default.temporaryDirectory.path, nil)!
        let parent = URL(fileURLWithPath: String(cString: temp)).appendingPathComponent("ENKI-Synthetic-Memory-\(UUID())")
        free(temp)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("memory")
        let access = MemoryAccess()
        let store = ENKISecondMemoryStore(root: root, authorize: { access.allowed })
        let image = try Data(contentsOf: URL(fileURLWithPath: "Backend/SecondMemory/fixtures/synthetic-table.jpg"))
        func result(_ label: String = "llaves", seconds: Double = 0) throws -> ENKIRemoteVisualResult {
            let stamp = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_793_700_000 + seconds))
            let id = UUID().uuidString.lowercased()
            let raw: [String: Any] = ["observation_id": id, "timestamp": stamp,
                "scene_description": "SYNTHETIC TEST ONLY", "objects": [["label": label, "attributes": ["test"], "location_in_scene": "superficie de prueba", "confidence": NSNull()]],
                "uncertainties": ["SYNTHETIC TRANSPORT, not Meta evidence"], "model_id": ENKIRemoteVisualResult.model,
                "source": "meta-model-api", "meta_request_id": "synthetic-only", "response_sha256": String(repeating: "a", count: 64),
                "usage": ["prompt_tokens": 10, "completion_tokens": 5, "estimated_usd": 0.0001]]
            return try ENKIRemoteVisualResult.parse(JSONSerialization.data(withJSONObject: raw), expectedID: id, timestamp: stamp)
        }
        func rejected(_ action: () async throws -> Void) async -> Bool {
            do { try await action(); return false } catch { return true }
        }
        var listing = try await store.list()
        check("Empty memory gives no fabricated answer", ENKISecondMemoryQuery.lastKeys(in: listing.records) == nil)
        let a = try result()
        check("No save without explicit consent", await rejected { _ = try await store.save(image: image, result: a, origin: .syntheticTest, explicitConsent: false) })
        check("No save of corrupt image", await rejected { _ = try await store.save(image: Data([1,2,3]), result: a, origin: .syntheticTest, explicitConsent: true) })
        let first = try await store.save(image: image, result: a, origin: .syntheticTest, explicitConsent: true)
        check("Stored evidence is exact input", try await store.evidence(first.id) == image)
        check("Confidence null survives persistence", try first.analysis().objects.first?.confidence == nil)
        check("Synthetic origin stays explicit", first.origin == .syntheticTest)
        check("Duplicate save rejected", await rejected { _ = try await store.save(image: image, result: a, origin: .syntheticTest, explicitConsent: true) })
        let newer = try await store.save(image: image, result: result("keyring", seconds: 100), origin: .syntheticTest, explicitConsent: true)
        let laterSavedButOlder = try await store.save(image: image, result: result("llaves", seconds: -100), origin: .syntheticTest, explicitConsent: true)
        listing = try await store.list()
        check("Last seen orders capture time, not save time", ENKISecondMemoryQuery.lastKeys(in: listing.records)?.id == newer.id && laterSavedButOlder.savedAt >= first.savedAt)
        check("Spanish question supported", ENKISecondMemoryQuery.supports("¿Dónde vi mis llaves por última vez?"))
        check("English key query supported", ENKISecondMemoryQuery.supports("Where did I see my keys?"))
        check("Unsupported object not invented", !ENKISecondMemoryQuery.supports("¿Dónde está mi cartera?"))
        check("Keyboard substring not a key", ENKISecondMemoryQuery.lastKeys(in: [try makeRecord(result("keyboard"), image: image)]) == nil)
        check("Negative object label does not match", ENKISecondMemoryQuery.lastKeys(in: [try makeRecord(result("sin llaves"), image: image)]) == nil)
        let reopened = ENKISecondMemoryStore(root: root, authorize: { access.allowed })
        check("Records survive reopening", try await reopened.list().records.count == 3)
        access.allowed = false
        check("Locked memory cannot list", await rejected { _ = try await store.list() })
        check("Locked memory cannot expose evidence", await rejected { _ = try await store.evidence(first.id) })
        check("Locked memory cannot delete", await rejected { try await store.delete(first.id, explicitConsent: true) })
        access.allowed = true
        check("Cancelled deletion preserves record", await rejected { try await store.delete(first.id, explicitConsent: false) })
        check("Record remains after denied deletion", try await store.evidence(first.id) == image)
        try await store.delete(first.id, explicitConsent: true)
        check("Individual deletion verified", await rejected { _ = try await store.evidence(first.id) })
        check("Other valid memories remain", try await store.list().records.count == 2)
        let corruptID = UUID()
        try Data("broken".utf8).write(to: root.appendingPathComponent(corruptID.uuidString + ".json"))
        listing = try await store.list()
        check("Corrupt metadata listed without decoding", listing.unreadable.contains(corruptID))
        try await store.delete(corruptID, explicitConsent: true)
        check("Corrupt entry deleted without touching valid ones", try await store.list().unreadable.isEmpty)
        let pendingID = UUID()
        try Data("unfinished".utf8).write(to: root.appendingPathComponent(pendingID.uuidString + ".pending"))
        check("Interrupted pending save visible for review", try await store.list().unreadable.contains(pendingID))
        try await store.delete(pendingID, explicitConsent: true)
        check("Pending item individually removable", !FileManager.default.fileExists(atPath: root.appendingPathComponent(pendingID.uuidString + ".pending").path))
        let outside = parent.appendingPathComponent("original-image.bin")
        try image.write(to: outside)
        let linkID = UUID()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(linkID.uuidString + ".json"), withDestinationURL: outside)
        check("Symlink cannot expose outside evidence", await rejected { _ = try await store.evidence(linkID) })
        try await store.delete(linkID, explicitConsent: true)
        check("Deleting link leaves original file intact", try Data(contentsOf: outside) == image)
        let rootLink = parent.appendingPathComponent("unsafe-root")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: root)
        let unsafe = ENKISecondMemoryStore(root: rootLink, authorize: { true })
        check("Root symlink rejected", await rejected { _ = try await unsafe.list() })
        let victim = newer.id
        let url = root.appendingPathComponent(victim.uuidString + ".json")
        var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String:Any]
        envelope["image"] = Data([1,2,3]).base64EncodedString()
        try JSONSerialization.data(withJSONObject: envelope).write(to: url)
        listing = try await store.list()
        check("Changed evidence fails hash verification", listing.unreadable.contains(victim) && !listing.records.contains(where: { $0.id == victim }))
        let barrier = MemoryBarrier()
        await store.setBeforeCommit { await barrier.wait() }
        let denied = try result("llaves", seconds: 200)
        let saving = Task { try await store.save(image: image, result: denied, origin: .syntheticTest, explicitConsent: true) }
        for _ in 0..<2000 { if await barrier.entered { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        check("Adversarial precommit barrier reached", await barrier.entered)
        check("Concurrent operation rejected while saving", await rejected { _ = try await store.list() })
        access.allowed = false; await barrier.release()
        check("Revocation before commit prevents save", await rejected { _ = try await saving.value })
        access.allowed = true; await store.setBeforeCommit(nil)
        check("No late committed observation after unlock", !(try await store.list()).records.contains(where: { $0.id.uuidString.lowercased() == denied.observation_id }))
        let attrs = try FileManager.default.attributesOfItem(atPath: root.path)
        check("Private root mode", (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let validFile = root.appendingPathComponent(laterSavedButOlder.id.uuidString + ".json")
        let fileAttrs = try FileManager.default.attributesOfItem(atPath: validFile.path)
        check("Private record mode", (fileAttrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let cancellationBarrier = MemoryBarrier()
        await store.setBeforeCommit { await cancellationBarrier.wait() }
        let cancelledResult = try result()
        let cancelledSave = Task { try await store.save(image:image,result:cancelledResult,origin:.syntheticTest,explicitConsent:true) }
        for _ in 0..<2000 { if await cancellationBarrier.entered { break }; try await Task.sleep(nanoseconds:1_000_000) }
        cancelledSave.cancel(); await cancellationBarrier.release()
        check("Cancelled save cannot commit later", await rejected { _ = try await cancelledSave.value })
        await store.setBeforeCommit(nil)
        check("Cancelled save releases temporary image", !FileManager.default.fileExists(atPath:root.appendingPathComponent(cancelledResult.observation_id.uppercased()+".pending").path))
        let brokenRoot = parent.appendingPathComponent("file-not-directory")
        try Data([1]).write(to: brokenRoot)
        let diskErrorStore = ENKISecondMemoryStore(root: brokenRoot, authorize:{true})
        check("Storage error is reported, not simulated success", await rejected { _ = try await diskErrorStore.list() })
        let quotaRoot = parent.appendingPathComponent("quota")
        try FileManager.default.createDirectory(at:quotaRoot,withIntermediateDirectories:false)
        for _ in 0..<ENKISecondMemoryStore.maximumRecords {
            try Data("corrupt synthetic".utf8).write(to:quotaRoot.appendingPathComponent(UUID().uuidString+".json"))
        }
        let quotaStore = ENKISecondMemoryStore(root:quotaRoot,authorize:{true})
        check("Corrupt entries count against storage quota", await rejected { _ = try await quotaStore.save(image:image,result:result(),origin:.syntheticTest,explicitConsent:true) })
        check("Quota rejection preserves existing entries", try FileManager.default.contentsOfDirectory(atPath:quotaRoot.path).filter({$0.hasSuffix(".json")}).count == ENKISecondMemoryStore.maximumRecords)
        var changedEnvelope = try JSONSerialization.jsonObject(with: Data(contentsOf:validFile)) as! [String:Any]
        var changedRecord = changedEnvelope["record"] as! [String:Any]
        var changedResponse = try JSONSerialization.jsonObject(with: Data(base64Encoded: changedRecord["response"] as! String)!) as! [String:Any]
        changedResponse["scene_description"] = "ALTERED SYNTHETIC TEXT"
        changedRecord["response"] = try JSONSerialization.data(withJSONObject:changedResponse).base64EncodedString()
        changedEnvelope["record"] = changedRecord
        try JSONSerialization.data(withJSONObject:changedEnvelope).write(to:validFile)
        check("Modified analysis cannot become evidence", try await store.list().unreadable.contains(laterSavedButOlder.id))
        check("Precise observation timestamps accepted", ENKISecondMemoryRecord.observationDate("2026-11-03T20:01:00.123Z") != nil)
        print("SECOND_MEMORY_STORE: \(total-failed)/\(total); SYNTHETIC DATA ONLY; NO NETWORK")
        exit(failed == 0 ? 0 : 1)
    }
    static func makeRecord(_ result: ENKIRemoteVisualResult, image: Data) throws -> ENKISecondMemoryRecord {
        let response = try JSONEncoder().encode(result)
        return .init(version: 1, id: UUID(uuidString: result.observation_id)!, capturedAt: ISO8601DateFormatter().date(from: result.timestamp)!, savedAt: Date(), imageSHA256: ENKISecondMemoryStore.digest(image), response: response, responseJSONSHA256: ENKISecondMemoryStore.digest(response), origin: .syntheticTest)
    }
}
