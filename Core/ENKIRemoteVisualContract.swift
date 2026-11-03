import Foundation

enum ENKIRemoteVisualError: String, LocalizedError {
    case consent = "Autoriza por separado el envío de una imagen de prueba a Meta."
    case unavailable = "Backend no disponible o sin configurar. No se ha usado una simulación."
    case unauthorized = "El backend o Meta no han autorizado esta solicitud."
    case budget = "Límite interno de solicitudes o presupuesto alcanzado."
    case billing = "Meta rechaza la solicitud por facturación o saldo. No se reintentará ni se activarán pagos automáticamente."
    case rateLimit = "Meta ha alcanzado una cuota o límite de solicitudes. No se reintentará automáticamente."
    case malformed = "La respuesta no cumple el contrato visual verificable."
    case camera = "Inicia la observación y espera una imagen reciente de las gafas."
    case locked = "ENKI debe estar desbloqueado, autorizado y en primer plano."
    case image = "No se pudo preparar una imagen válida dentro del límite."
    case model = "Modelo no disponible o todavía no verificado en el backend."
    case cancelled = "Análisis cancelado. Si Meta ya recibió la imagen, no se puede retirar ni garantizar que no se facture."
    var errorDescription: String? { rawValue }
}

struct ENKIRemoteVisualResult: Codable, Sendable {
    struct Object: Codable, Sendable {
        let label: String
        let attributes: [String]
        let location_in_scene: String
        let confidence: Double?
        enum CodingKeys: String, CodingKey { case label, attributes, location_in_scene, confidence }
        func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(label, forKey: .label); try box.encode(attributes, forKey: .attributes)
            try box.encode(location_in_scene, forKey: .location_in_scene)
            if let confidence { try box.encode(confidence, forKey: .confidence) }
            else { try box.encodeNil(forKey: .confidence) }
        }
    }
    struct Usage: Codable, Sendable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let estimated_usd: Double
    }
    let observation_id: String
    let timestamp: String
    let scene_description: String
    let objects: [Object]
    let uncertainties: [String]
    let model_id: String
    let source: String
    let meta_request_id: String
    let response_sha256: String
    let usage: Usage

    static let model = "muse-spark-1.3"
    static func parse(_ data: Data, expectedID: String, timestamp: String) throws -> Self {
        guard data.count <= 128_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["observation_id", "timestamp", "scene_description", "objects", "uncertainties", "model_id", "source", "meta_request_id", "response_sha256", "usage"]),
              let objectRows = root["objects"] as? [[String: Any]],
              objectRows.allSatisfy({ Set($0.keys) == Set(["label", "attributes", "location_in_scene", "confidence"]) && $0["confidence"] is NSNull }),
              let accounting = root["usage"] as? [String: Any],
              Set(accounting.keys) == Set(["prompt_tokens", "completion_tokens", "estimated_usd"]) else { throw ENKIRemoteVisualError.malformed }
        let value = try JSONDecoder().decode(Self.self, from: data)
        func valid(_ s: String, _ max: Int) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.count <= max }
        guard value.observation_id == expectedID, UUID(uuidString: expectedID) != nil, value.timestamp == timestamp,
              value.model_id == model, value.source == "meta-model-api", valid(value.meta_request_id, 200),
              value.response_sha256.count == 64, value.response_sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              valid(value.scene_description, 2000), value.objects.count <= 40,
              value.objects.allSatisfy({ valid($0.label, 120) && valid($0.location_in_scene, 300) && $0.confidence == nil && $0.attributes.count <= 12 && $0.attributes.allSatisfy({ valid($0, 200) }) }),
              value.uncertainties.count <= 20, value.uncertainties.allSatisfy({ valid($0, 500) }),
              (0...1_048_576).contains(value.usage.prompt_tokens), (0...2048).contains(value.usage.completion_tokens),
              value.usage.estimated_usd.isFinite && value.usage.estimated_usd >= 0 else { throw ENKIRemoteVisualError.malformed }
        return value
    }
}

/// Consent expires, is never persisted and is invalidated by every lifecycle stop.
struct ENKIRemoteVisualConsent: Sendable {
    private(set) var grantedAt: TimeInterval?
    mutating func grant(at time: TimeInterval) { grantedAt = time.isFinite ? time : nil }
    mutating func revoke() { grantedAt = nil }
    func valid(at time: TimeInterval) -> Bool {
        guard let grantedAt, time.isFinite else { return false }
        return time >= grantedAt && time - grantedAt < 60
    }
}
