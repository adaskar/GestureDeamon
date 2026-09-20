import Cocoa
import CoreGraphics

public enum ScrollAxis {
    case y
    case x
}

public struct AxisData {
    public var scrollFix: Int64 = 0
    public var scrollPt: Double = 0.0
    public var scrollFixPt: Double = 0.0
    public var fixed: Bool = false
    public var valid: Bool = false
    public var usableValue: Double = 0.0

    public init() {}
}

public struct ScrollEvent {
    public let event: CGEvent
    public var yData: AxisData
    public var xData: AxisData

    @inline(__always)
    public init(with cgEvent: CGEvent) {
        self.event = cgEvent
        self.yData = ScrollEvent.extractAxisData(event: cgEvent, axis: .y)
        self.xData = ScrollEvent.extractAxisData(event: cgEvent, axis: .x)
    }

    // MARK: - Trackpad Discrimination (Zero-allocation fast path)
    @inline(__always)
    public static func isTrackpad(with event: CGEvent) -> Bool {
        // Native trackpads, Magic Mouse, and continuous momentum report isContinuous != 0 or active phases
        if event.getDoubleValueField(.scrollWheelEventIsContinuous) != 0.0 {
            return true
        }
        if event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0.0 ||
           event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0.0 {
            return true
        }
        return false
    }

    @inline(__always)
    public func isTrackpad() -> Bool {
        return ScrollEvent.isTrackpad(with: event)
    }

    // MARK: - Axis Extraction & Manipulation
    @inline(__always)
    public static func extractAxisData(event: CGEvent, axis: ScrollAxis) -> AxisData {
        var data = AxisData()
        if axis == .y {
            data.scrollFix = Int64(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            data.scrollPt = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            data.scrollFixPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        } else {
            data.scrollFix = Int64(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            data.scrollPt = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            data.scrollFixPt = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }

        if data.scrollPt != 0.0 {
            data.fixed = false
            data.valid = true
            data.usableValue = data.scrollPt
        } else if data.scrollFixPt != 0.0 {
            data.fixed = true
            data.valid = true
            data.usableValue = data.scrollFixPt
        } else if data.scrollFix != 0 {
            data.fixed = true
            data.valid = true
            data.usableValue = Double(data.scrollFix)
        }
        return data
    }

    @inline(__always)
    public static func reverseY(_ scrollEvent: inout ScrollEvent) {
        scrollEvent.event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -scrollEvent.yData.scrollFix)
        scrollEvent.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -scrollEvent.yData.scrollPt)
        scrollEvent.event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -scrollEvent.yData.scrollFixPt)
        scrollEvent.yData.usableValue = -scrollEvent.yData.usableValue
    }

    @inline(__always)
    public static func reverseX(_ scrollEvent: inout ScrollEvent) {
        scrollEvent.event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -scrollEvent.xData.scrollFix)
        scrollEvent.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -scrollEvent.xData.scrollPt)
        scrollEvent.event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -scrollEvent.xData.scrollFixPt)
        scrollEvent.xData.usableValue = -scrollEvent.xData.usableValue
    }

    @inline(__always)
    public static func normalizeY(_ scrollEvent: inout ScrollEvent, threshold: Double) {
        let val = scrollEvent.yData.usableValue
        scrollEvent.yData.usableValue = val > 0 ? max(val.magnitude, threshold) : -max(val.magnitude, threshold)
    }

    @inline(__always)
    public static func normalizeX(_ scrollEvent: inout ScrollEvent, threshold: Double) {
        let val = scrollEvent.xData.usableValue
        scrollEvent.xData.usableValue = val > 0 ? max(val.magnitude, threshold) : -max(val.magnitude, threshold)
    }

    @inline(__always)
    public static func clearY(_ scrollEvent: inout ScrollEvent) {
        scrollEvent.event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        scrollEvent.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0.0)
        scrollEvent.event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
        scrollEvent.yData.scrollFix = 0
        scrollEvent.yData.scrollPt = 0.0
        scrollEvent.yData.scrollFixPt = 0.0
        scrollEvent.yData.usableValue = 0.0
    }

    @inline(__always)
    public static func clearX(_ scrollEvent: inout ScrollEvent) {
        scrollEvent.event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
        scrollEvent.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: 0.0)
        scrollEvent.event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
        scrollEvent.xData.scrollFix = 0
        scrollEvent.xData.scrollPt = 0.0
        scrollEvent.xData.scrollFixPt = 0.0
        scrollEvent.xData.usableValue = 0.0
    }
}
