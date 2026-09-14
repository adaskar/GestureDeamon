import Foundation
import IOKit
import IOKit.hid

public final class HIDPlusPlusManager {
    public static let shared = HIDPlusPlusManager()

    private var hidManager: IOHIDManager?
    private var activeDevice: IOHIDDevice?
    private var reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var isStarted = false

    private init() {}

    deinit {
        reportBuffer.deallocate()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        // Match Logitech Unifying & Bolt receivers on HID++ vendor page
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x046d,
            kIOHIDPrimaryUsagePageKey as String: 0xff00,
            kIOHIDPrimaryUsageKey as String: 0x01
        ]

        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<HIDPlusPlusManager>.fromOpaque(context).takeUnretainedValue()
            manager.deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let manager = Unmanaged<HIDPlusPlusManager>.fromOpaque(context).takeUnretainedValue()
            manager.deviceDisconnected(device)
        }, context)

        let res = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if res == kIOReturnSuccess {
            Log.info("HID++ Manager active (scanning for Logitech receivers).")
        } else {
            Log.error("Failed to open IOHIDManager for HID++ (status \(res)).")
        }
    }

    public func stop() {
        guard isStarted, let manager = hidManager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        self.activeDevice = nil
        self.hidManager = nil
        self.isStarted = false
        Log.info("HID++ Manager stopped.")
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        self.activeDevice = device
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Logitech Receiver"
        Log.info("HID++ Device connected: \(name)")

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer,
            64,
            { context, result, sender, type, reportId, report, reportLength in
                guard let context = context else { return }
                let manager = Unmanaged<HIDPlusPlusManager>.fromOpaque(context).takeUnretainedValue()
                manager.handleInputReport(report: report, length: reportLength)
            },
            context
        )

        // Enable wireless device notifications on Unifying receiver
        enableReceiverNotifications(device)
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        Log.info("HID++ Device disconnected.")
        if self.activeDevice == device {
            self.activeDevice = nil
        }
    }

    private func enableReceiverNotifications(_ device: IOHIDDevice) {
        // HID++ 1.0 Set Register 0x00 on receiver 0xFF: Enable device notifications
        let enableNotif: [UInt8] = [0x10, 0xFF, 0x80, 0x00, 0x10, 0x01, 0x00]
        _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x10, enableNotif, enableNotif.count)
    }

    private func handleInputReport(report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 7 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))

        // Raw HID++ report routing
        let reportId = bytes[0]
        let deviceIndex = bytes[1]

        // Check for reprogrammable button divert event (Feature 0x1B04 Long Report)
        if reportId == 0x11 && length >= 20 {
            let status = bytes[6]
            if status == 0x01 {
                Log.info("HID++ Diverted Button Pressed (Device \(deviceIndex))")
            } else if status == 0x00 {
                Log.info("HID++ Diverted Button Released (Device \(deviceIndex))")
            }
        }
    }
}
