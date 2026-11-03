import Foundation

@main struct ObservationTests {
    static func main() {
        var count = 0, failures = 0
        func check(_ name: String, _ condition: Bool) {
            count += 1; if !condition { failures += 1 }
            print("\(condition ? "PASS" : "FAIL") \(name)")
        }
        let camera = UUID()
        let healthy = ENKIObservationSession.Conditions(authorized: true, foreground: true, cameraID: camera, streaming: true)
        var session = ENKIObservationSession()
        check("Consent required", !session.start(consent: false, conditions: healthy, now: 10))
        var denied = healthy; denied.authorized = false
        check("Owner authorization required", !session.start(consent: true, conditions: denied, now: 10))
        denied = healthy; denied.foreground = false
        check("Foreground required", !session.start(consent: true, conditions: denied, now: 10))
        denied = healthy; denied.cameraID = nil
        check("Existing camera identity required", !session.start(consent: true, conditions: denied, now: 10))
        denied = healthy; denied.streaming = false
        check("Existing stream required", !session.start(consent: true, conditions: denied, now: 10))
        denied = healthy; denied.conflicting = true
        check("Replay recorder playback conflict rejected", !session.start(consent: true, conditions: denied, now: 10))
        denied = healthy; denied.thermalPressure = true
        check("Thermal pressure rejected", !session.start(consent: true, conditions: denied, now: 10))
        check("Nonfinite clock rejected", !session.start(consent: true, conditions: healthy, now: .nan))
        check("Explicit start", session.start(consent: true, conditions: healthy, now: 10))
        let generation = session.id
        check("Cannot replace active session", !session.start(consent: true, conditions: healthy, now: 11) && session.id == generation)
        var times: [Double] = []
        // 15 fps simulated transport, one consent/start only, 5 minutes.
        for index in 0..<4500 {
            let time = 10 + Double(index) / 15
            if session.offer(conditions: healthy, now: time) {
                session.completeSample(valid: true, now: time)
                times.append(time)
            }
        }
        check("Automatic periodic samples without further actions", times.count >= 280 && times.count <= 300)
        check("Every sample interval at least one second", zip(times, times.dropFirst()).allSatisfy { $1 - $0 >= 1 })
        check("Counts include all received frames", session.received == 4500)
        check("Successful samples counted", session.selected == times.count)
        check("Cadence discards accounted", session.rateLimited + session.selected == session.received)
        session.validate(healthy, now: 310)
        check("Stops at exactly five minutes", !session.active && session.reason == .expired && session.duration(at: 999) == 300)
        check("No sample at/after deadline", !session.offer(conditions: healthy, now: 310))
        let selected = session.selected
        check("No implicit restart on new frames", !session.offer(conditions: healthy, now: 311) && session.selected == selected)

        func stopping(_ conditions: ENKIObservationSession.Conditions, _ expected: ENKIObservationSession.Stop, _ label: String) {
            var s = ENKIObservationSession()
            _ = s.start(consent: true, conditions: healthy, now: 1)
            let accepted = s.offer(conditions: conditions, now: 1.5)
            check(label, !accepted && !s.active && s.reason == expected)
            check(label + " cannot resume", !s.offer(conditions: healthy, now: 2))
        }
        denied = healthy; denied.authorized = false
        stopping(denied, .authorization, "Lock / revocation stops before sampling")
        denied = healthy; denied.foreground = false
        stopping(denied, .background, "App switch / phone lock stops before sampling")
        denied = healthy; denied.streaming = false
        stopping(denied, .camera, "Glasses disconnect stops")
        denied = healthy; denied.cameraID = UUID()
        stopping(denied, .camera, "New camera identity cannot inherit observation")
        denied = healthy; denied.conflicting = true
        stopping(denied, .conflict, "Other camera consumer stops observation only")
        denied = healthy; denied.thermalPressure = true
        stopping(denied, .pressure, "Thermal protection stops")

        session = ENKIObservationSession()
        _ = session.start(consent: true, conditions: healthy, now: 0)
        check("First valid frame eligible", session.offer(conditions: healthy, now: 0))
        session.completeSample(valid: false, now: 0)
        check("Invalid image counted without successful sample", session.invalid == 1 && session.selected == 0)
        check("Invalid image does not permit burst retries", !session.offer(conditions: healthy, now: 0.5))
        check("Duplicate timestamp rejected", !session.offer(conditions: healthy, now: 0.5) && session.invalid == 2)
        check("Regressive timestamp rejected", !session.offer(conditions: healthy, now: 0.4) && session.invalid == 3)
        check("Next normal slot allowed", session.offer(conditions: healthy, now: 1))
        session.completeSample(valid: true, now: 1)
        session.stop(.manual, now: 1.2)
        check("Manual stop retains only metrics", !session.active && session.cameraID == nil && session.reason == .manual)
        session.completeSample(valid: true, now: 2)
        check("Late completion after stop ignored", session.selected == 1)
        session.stop(.camera, now: 3)
        check("Stop is idempotent; original reason retained", session.reason == .manual && session.ended == 1.2)
        check("Explicit new session possible", session.start(consent: true, conditions: healthy, now: 4))
        check("New session resets metrics and identity", session.selected == 0 && session.received == 0 && session.id != generation)
        session.validate(healthy, now: 7)
        check("Missing frames watchdog stops", !session.active && session.reason == .stale)
        session = ENKIObservationSession()
        _ = session.start(consent: true, conditions: healthy, now: 10)
        _ = session.offer(conditions: healthy, now: 10)
        check("Three second capture gap does not count a new sample", !session.offer(conditions: healthy, now: 13) && session.reason == .stale)
        check("No image fields in content-free state", Mirror(reflecting: session).children.allSatisfy {
            !["Data", "UIImage", "CVPixelBuffer"].contains(String(describing: type(of: $0.value)))
        })
        print("SECOND_MEMORY_CORE: \(count - failures)/\(count); synthetic clock/transport, not hardware")
        if failures > 0 { exit(1) }
    }
}
