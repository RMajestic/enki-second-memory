import Foundation

/// Content-free state machine. Time is monotonic uptime, never wall-clock time.
struct ENKIObservationSession {
    enum Stop: String {
        case manual = "Finalizada por el propietario"
        case expired = "Límite de cinco minutos alcanzado"
        case authorization = "Autorización revocada"
        case background = "ENKI dejó de estar en primer plano"
        case camera = "Sesión de cámara perdida o sustituida"
        case stale = "Sin fotogramas nuevos durante tres segundos"
        case conflict = "Otra capacidad necesita la cámara"
        case pressure = "Protección térmica"
    }
    struct Conditions {
        var authorized: Bool
        var foreground: Bool
        var cameraID: UUID?
        var streaming: Bool
        var conflicting: Bool = false
        var thermalPressure: Bool = false
    }
    private(set) var id: UUID?
    private(set) var cameraID: UUID?
    private(set) var started: TimeInterval?
    private(set) var ended: TimeInterval?
    private(set) var reason: Stop?
    private(set) var received = 0
    private(set) var selected = 0
    private(set) var invalid = 0
    private(set) var rateLimited = 0
    private(set) var maximumInputGap: TimeInterval = 0
    private(set) var maximumSampleGap: TimeInterval = 0
    private(set) var firstSample: TimeInterval?
    private(set) var lastSample: TimeInterval?
    private var lastInput: TimeInterval?
    var active: Bool { id != nil }
    func duration(at now: TimeInterval) -> TimeInterval {
        guard let started else { return 0 }
        return max(0, min(300, (ended ?? now) - started))
    }

    mutating func start(consent: Bool, conditions: Conditions, now: TimeInterval) -> Bool {
        guard !active, consent, now.isFinite, conditions.authorized, conditions.foreground,
              conditions.streaming, let camera = conditions.cameraID,
              !conditions.conflicting, !conditions.thermalPressure else { return false }
        self = Self()
        id = UUID(); cameraID = camera; started = now
        return true
    }

    mutating func validate(_ conditions: Conditions, now: TimeInterval) {
        guard active, let started else { return }
        if !conditions.authorized { stop(.authorization, now: now) }
        else if !conditions.foreground { stop(.background, now: now) }
        else if !conditions.streaming || conditions.cameraID != cameraID { stop(.camera, now: now) }
        else if conditions.conflicting { stop(.conflict, now: now) }
        else if conditions.thermalPressure { stop(.pressure, now: now) }
        else if !now.isFinite || now < started { stop(.camera, now: started) }
        else if now - started >= 300 { stop(.expired, now: now) }
        else if now - (lastInput ?? started) >= 3 { stop(.stale, now: now) }
    }

    /// Called only for newly published frames, never by the timer or a retained preview.
    mutating func offer(conditions: Conditions, now: TimeInterval) -> Bool {
        validate(conditions, now: now)
        guard active else { return false }
        received += 1
        if let lastInput {
            guard now > lastInput else { invalid += 1; return false }
            maximumInputGap = max(maximumInputGap, now - lastInput)
        }
        lastInput = now
        if let lastSample, now - lastSample < 1 { rateLimited += 1; return false }
        // Reserve this slot even if image decoding fails: retries cannot exceed 1 Hz.
        if let lastSample { maximumSampleGap = max(maximumSampleGap, now - lastSample) }
        lastSample = now
        return true
    }

    mutating func completeSample(valid: Bool, now: TimeInterval) {
        guard active else { return }
        if valid { selected += 1; if firstSample == nil { firstSample = now } }
        else { invalid += 1 }
    }

    mutating func stop(_ reason: Stop, now: TimeInterval) {
        guard active else { return }
        ended = now.isFinite ? now : started
        self.reason = reason; id = nil; cameraID = nil
    }
}
