import Foundation

extension Date {
    static func approximatelyEqual(_ d1: Date, _ d2: Date, threshold: Double = 0.001) -> Bool {
        let time1 = d1.timeIntervalSinceReferenceDate
        let time2 = d2.timeIntervalSinceReferenceDate
        let diff = abs(time1 - time2)
        return diff <= threshold
    }
}
