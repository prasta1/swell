import Testing
import Foundation
@testable import Swell

@Suite("Forced daylight sampler tick", .timeLimit(.minutes(2)))
struct ForcedDaylightSamplerTests {

    @MainActor
    @Test("Sampler tick runs with always-daylight clock")
    func forcedDaylightTick() async throws {
        let registry = try SpotRegistry.bundled()
        let store = try HistoryStore(inMemory: true)
        let detector = try YOLODetector()
        let conditions = ConditionsService()
        
        let clock = SolarClock(startHour: 0, endHour: 24)
        let sampler = Sampler(
            registry: registry,
            store: store,
            detector: detector,
            conditions: conditions,
            clock: clock
        )
        
        print("🌅 Running forced daylight sampler tick...")
        await sampler.tick()
        
        for spot in registry.activeSpots {
            let sample = try store.latest(spotID: spot.id)
            if let sample {
                print("📊 \(spot.name): count=\(sample.count.map(String.init) ?? "nil"), conf=\(String(format: "%.3f", sample.confidence)), ts=\(sample.timestamp)")
            } else {
                print("📊 \(spot.name): no samples")
            }
        }
        
        #expect(true)
    }
}
