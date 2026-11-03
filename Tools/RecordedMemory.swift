// Public evaluation adapter only. No private iOS host, camera, API key or network.
// Input was checked by recorded_memory.py; the actual core validates it again.
import Foundation
import Darwin

@main struct RecordedMemory {
    @MainActor static func main() async {
        do { try await run() }
        catch { print("Stopped safely: recorded result or local evidence could not be validated."); exit(1) }
    }
    @MainActor static func run() async throws {
        let args = CommandLine.arguments
        guard args.count == 5, args[4] == "--confirmed-local-save",
              args[3].hasPrefix("/"), !FileManager.default.fileExists(atPath: args[3]) else {
            throw ENKISecondMemoryError.consent
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let raw = try JSONDecoder().decode(ENKIRemoteVisualResult.self, from: data)
        let result = try ENKIRemoteVisualResult.parse(data, expectedID: raw.observation_id, timestamp: raw.timestamp)
        let image = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let root = URL(fileURLWithPath: args[3])
        // CLI uses owner OS permissions, not Face ID. Input is an authorized synthetic image.
        let store = ENKISecondMemoryStore(root: root, authorize: { true })
        _ = try await store.save(image: image, result: result, origin: .syntheticTest, explicitConsent: true)
        let reopened = ENKISecondMemoryStore(root: root, authorize: { true })
        let listing = try await reopened.list()
        var output: [String: Any] = [
            "mode": "OFFLINE-RECORDED-RESULT-NOT-LIVE-INFERENCE",
            "input_origin": "syntheticTest", "model_id": result.model_id,
            "provider_request_id": result.meta_request_id,
            "question": "Where did I last see my keys?",
            "saved_records": listing.records.count,
            "limits": "Hashes are integrity checks, not signed proof of provider origin or image pairing. No glasses or Face ID used."
        ]
        if let last = ENKISecondMemoryQuery.lastKeys(in: listing.records) {
            let evidence = try await reopened.evidence(last.id)
            guard evidence == image else { throw ENKISecondMemoryError.invalid }
            let answer = try last.analysis()
            let matches = answer.objects.filter { object in
                let words = ENKISecondMemoryQuery.words(object.label)
                return !words.isDisjoint(with: ["key", "keys", "keyring", "keychain", "llave", "llaves", "llavero", "llaveros"])
                    && words.isDisjoint(with: ["no", "sin", "not", "without"])
            }
            output["found"] = true
            output["captured_at"] = answer.timestamp
            output["scene_description"] = answer.scene_description
            output["locations"] = matches.map(\.location_in_scene)
            output["uncertainties"] = answer.uncertainties
            output["evidence_sha256"] = last.imageSHA256
            output["evidence_matches_supplied_fixture"] = true
        } else {
            output["found"] = false
            output["answer"] = "No saved key observation supports an answer."
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
