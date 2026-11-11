import Foundation

// Match the fields of view on either side of a physical camera handoff.
// Zoom as far as needed on the old camera, then continue on the new one.
nonisolated struct LensTransitionPlan {
    let sourceFactor: Double
    let destinationFactor: Double
    let targetFactor: Double

    init(sourceBase: Double, sourceFactor: Double, sourceMinimum: Double, sourceMaximum: Double,
         destinationBase: Double, destinationMinimum: Double, destinationMaximum: Double,
         targetZoom: Double) {
        let currentZoom = sourceBase * sourceFactor / sourceMinimum
        let low = max(sourceBase, destinationBase)
        let high = min(sourceBase * sourceMaximum / sourceMinimum,
                       destinationBase * destinationMaximum / destinationMinimum)
        let handoff: Double
        if low <= high {
            handoff = min(high, max(low, currentZoom))
        } else {
            handoff = destinationBase > sourceBase
                ? sourceBase * sourceMaximum / sourceMinimum : sourceBase
        }
        self.sourceFactor = min(sourceMaximum, max(sourceMinimum, handoff / sourceBase * sourceMinimum))
        destinationFactor = min(destinationMaximum, max(destinationMinimum, handoff / destinationBase * destinationMinimum))
        targetFactor = min(destinationMaximum, max(destinationMinimum, targetZoom / destinationBase * destinationMinimum))
    }

    static func virtualFactor(displayedZoom: Double, displayMultiplier: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, displayedZoom / max(displayMultiplier, 0.001)))
    }

    static func duration(from start: Double, to end: Double) -> Double {
        let distance = abs(log2(max(end, 0.001) / max(start, 0.001)))
        return distance < 0.015 ? 0 : min(0.52, max(0.20, distance * 0.11))
    }
}
