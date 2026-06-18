import Foundation

/// Gates sampling to daylight hours. v1 uses a simple hour window; a real
/// sunrise/sunset calculation can replace `isDaylight` without touching callers.
struct SolarClock {
    var startHour: Int = 6
    var endHour: Int = 20

    func isDaylight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: date)
        return h >= startHour && h < endHour
    }
}
