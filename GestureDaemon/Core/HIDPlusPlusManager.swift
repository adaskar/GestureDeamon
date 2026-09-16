import Foundation
import IOKit
import IOKit.hid

public final class HIDPlusPlusManager {
    public static let shared = HIDPlusPlusManager()

    public enum TransportType: String {
        case usb = "USB Receiver"
        case bluetoothLE = "Bluetooth Low Energy"
    }

    public private(set) var connectedDeviceName: String?
    public private(set) var connectedTransport: TransportType?
    public private(set) var isDeviceOpen = false

    private var hidManager: IOHIDManager?
    private var activeDevice: IOHIDDevice?
    private var reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var isStarted = false

    // Cached HID++ 2.0 feature indices
    private var reprogFeatureIndex: UInt8?




    // Gesture Button Component IDs (Logitech specification)
    // 0x00D7: Gesture Button on M720 Triathlon (Task 0x00B4)
    // 0x00C3: Standard Gesture Button on MX Master 2S/3/3S
    // 0x00D0: Secondary Gesture / Function on select models
    // 0x01A0: Haptic Gesture Panel on MX Master 4 series
    private let gestureCIDs: [UInt16] = [0x00D7, 0x00C3, 0x00D0, 0x01A0]

    private init() {}

    deinit {
        reportBuffer.deallocate()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        // Match BOTH USB Receivers (0xFF00) and Direct Bluetooth Low Energy (0xFF43:0x0202).
        //
        // IMPORTANT — BLE matching must pin the Usage value (0x0202) in addition to the
        // Usage Page (0xFF43).  Without it:
        //   • kIOHIDPrimaryUsagePageKey alone matches any top-level HID collection whose
        //     primary usage page happens to be 0xFF43 — correct for HID++ only interfaces.
        //   • kIOHIDDeviceUsagePageKey alone matches any IOHIDDevice whose DeviceUsagePairs
        //     array contains 0xFF43 — this can match the COMPOSITE BLE device that bundles
        //     {0x0001/Mouse, 0xFF43/HID++, …} in one object.  Opening that composite device
        //     and registering an input-report callback on it delivers every mouse-movement
        //     report (125+ Hz) to handleInputReport, causing ~0.5% CPU even though the
        //     callback itself is fast — the IOKit Mach-IPC wakeup cost dominates.
        // Pinning Usage 0x0202 restricts the match to the exact HID++ logical interface only.
        let matchingCriteria: [[String: Any]] = [
            // 1. USB Unifying & Bolt Receivers (vendor-specific usage page 0xFF00)
            [
                kIOHIDVendorIDKey as String: 0x046d,
                kIOHIDPrimaryUsagePageKey as String: 0xff00
            ],
            // 2. Direct BLE — device whose primary usage IS 0xFF43:0x0202 (pure HID++ interface)
            [
                kIOHIDVendorIDKey as String: 0x046d,
                kIOHIDPrimaryUsagePageKey as String: 0xff43,
                kIOHIDPrimaryUsageKey as String: 0x0202
            ],
            // 3. Direct BLE — device that carries 0xFF43:0x0202 in its DeviceUsagePairs
            //    (some Logitech firmware exposes HID++ as a secondary collection)
            [
                kIOHIDVendorIDKey as String: 0x046d,
                kIOHIDDeviceUsagePageKey as String: 0xff43,
                kIOHIDDeviceUsageKey as String: 0x0202
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)
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
            Log.info("HID++ Manager active (listening for USB Receivers & Bluetooth LE Logitech devices).")
        } else if res == -536870174 { // 0xe00002e2 = kIOReturnNotPermitted
            Log.error("IOHIDManager access restricted. Input Monitoring permission required for Bluetooth HID++ devices.")
            PermissionHelper.requestInputMonitoring()
        } else {
            Log.error("Failed to open IOHIDManager (status \(res)).")
        }
    }

    public func stop() {
        guard isStarted, let manager = hidManager else { return }
        if let dev = activeDevice {
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        self.activeDevice = nil
        self.hidManager = nil
        self.isStarted = false
        self.connectedDeviceName = nil
        self.connectedTransport = nil
        self.isDeviceOpen = false
        self.reprogFeatureIndex = nil
        Log.info("HID++ Manager stopped.")
    }



    private func deviceConnected(_ device: IOHIDDevice) {
        self.activeDevice = device
        self.reprogFeatureIndex = nil
        self.isGestureButtonPressed = false

        let productName = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Logitech Device"
        let transportStr = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "Unknown"

        let transport: TransportType = transportStr.localizedCaseInsensitiveContains("Bluetooth") ? .bluetoothLE : .usb
        self.connectedDeviceName = productName
        self.connectedTransport = transport

        Log.info("⚡️ Logitech Device detected: '\(productName)' over \(transport.rawValue)")

        // Schedule device on the current (main) run loop.
        // For USB: receiver only sends infrequent HID++ frames.
        // For BLE: InputValueMatching filters out all mouse movement at the kernel driver level,
        // so only infrequent HID++ frames arrive — zero runloop wakeups during mouse movement.
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))

        if openResult == kIOReturnSuccess {
            self.isDeviceOpen = true
            Log.info("Connected to HID++ interface on '\(productName)' successfully.")

            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

            switch transport {
            case .usb:
                // USB receivers: keep input report callback. USB Unifying/Bolt receivers expose a
                // dedicated vendor interface (0xFF00) that never delivers mouse movement.
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
                enableReceiverNotifications(device)

            case .bluetoothLE:
                // Direct Bluetooth LE: DO NOT use IOHIDDeviceRegisterInputReportCallback!
                // BLE mice expose a single composite IOHIDDevice that bundles mouse movement (0x02 at 125 Hz).
                // Registering an input report callback on the composite device causes the kernel to deliver
                // 125 Mach IPC messages/sec into GestureDaemon whenever the mouse moves.
                //
                // Instead, we register IOHIDDeviceRegisterInputValueCallback with matching criteria
                // restricted strictly to Report IDs 0x11, 0x10, and UsagePage 0xFF43.
                // The kernel driver automatically filters out mouse-movement frames (0x02), eliminating
                // all runloop wakeups and achieving true 0.0% CPU!
                let matchingCriteria: [[String: Any]] = [
                    [kIOHIDElementReportIDKey as String: 0x11],
                    [kIOHIDElementReportIDKey as String: 0x10],
                    [kIOHIDElementUsagePageKey as String: 0xff43]
                ]
                IOHIDDeviceSetInputValueMatchingMultiple(device, matchingCriteria as CFArray)

                IOHIDDeviceRegisterInputValueCallback(
                    device,
                    { context, result, sender, value in
                        guard let context = context else { return }
                        let manager = Unmanaged<HIDPlusPlusManager>.fromOpaque(context).takeUnretainedValue()
                        manager.handleInputValue(value: value)
                    },
                    context
                )

                discoverBLEFeatures(device)
            }
        } else if openResult == -536870174 { // 0xe00002e2 = kIOReturnNotPermitted
            self.isDeviceOpen = false
            Log.error("⚠️ Cannot open Bluetooth HID++ channel on '\(productName)': Input Monitoring permission missing.")
            Log.error("Please grant Input Monitoring permission in System Settings -> Privacy & Security -> Input Monitoring.")
            PermissionHelper.requestInputMonitoring()
        } else {
            self.isDeviceOpen = false
            Log.error("Failed to open HID++ device '\(productName)' (status: \(openResult)).")
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        Log.info("Logitech Device disconnected.")
        if self.activeDevice == device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            self.activeDevice = nil
            self.connectedDeviceName = nil
            self.connectedTransport = nil
            self.isDeviceOpen = false
            self.reprogFeatureIndex = nil
        }
    }




    // MARK: - Sleep & Wake Recovery
    public func handleSleep() {
        Log.info("💤 System going to sleep. Resetting HID++ state...")
        self.isGestureButtonPressed = false
    }

    public func handleWake() {
        Log.info("☀️ System woke from sleep. Re-synchronizing HID++ hardware...")
        self.isGestureButtonPressed = false

        // 1. Immediately restart matching to flush any stale IOHID handles
        restartMatching()

        // 2. Staged retries at +1.5s and +3.0s to account for Bluetooth link re-establishment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            Log.info("☀️ Wake stage 1 (+1.5s): Verifying HID++ device connection...")
            if self.activeDevice == nil || !self.isDeviceOpen {
                self.restartMatching()
            } else {
                self.reapplyHardwareDiversion()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            Log.info("☀️ Wake stage 2 (+3.0s): Confirming HID++ diversion...")
            if self.activeDevice == nil || !self.isDeviceOpen {
                self.restartMatching()
            } else {
                self.reapplyHardwareDiversion()
            }
        }
    }

    public func reapplyHardwareDiversion() {
        self.isGestureButtonPressed = false
        guard let device = self.activeDevice, self.isDeviceOpen else {
            Log.info("No active open device found. Re-checking HID Manager...")
            restartMatching()
            return
        }

        switch self.connectedTransport {
        case .bluetoothLE:
            discoverBLEFeatures(device)
        case .usb:
            enableReceiverNotifications(device)
            if let reprogIndex = self.reprogFeatureIndex {
                divertGestureButtons(device: device, featureIndex: reprogIndex, deviceIndex: 0xFF)
            }
        case .none:
            discoverBLEFeatures(device)
        }
    }

    public func restartMatching() {
        stop()
        start()
    }

    // MARK: - USB Receiver Setup
    private func enableReceiverNotifications(_ device: IOHIDDevice) {
        // HID++ 1.0 Set Register 0x00 on receiver 0xFF: Enable wireless notifications
        let enableNotif: [UInt8] = [0x10, 0xFF, 0x80, 0x00, 0x10, 0x01, 0x00]
        _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x10, enableNotif, enableNotif.count)
    }

    // MARK: - Bluetooth LE Feature Discovery & Diversion
    private func discoverBLEFeatures(_ device: IOHIDDevice) {
        Log.info("Discovering HID++ 2.0 Reprogrammable Controls on Bluetooth device...")
        // Query IRoot (Feature 0x0000) for Feature 0x1B04 (REPROG_CONTROLS_V4)
        queryFeature(device: device, featureId: 0x1B04, deviceIndex: 0xFF)
    }

    private func queryFeature(device: IOHIDDevice, featureId: UInt16, deviceIndex: UInt8) {
        // HID++ 2.0 IRoot getFeature command:
        // Byte 0: 0x11 (Long Report ID)
        // Byte 1: deviceIndex (0xFF for direct BLE)
        // Byte 2: 0x00 (IRoot Feature Index)
        // Byte 3: 0x00 (Function 0: getFeature)
        // Byte 4: Feature ID MSB
        // Byte 5: Feature ID LSB
        var report = [UInt8](repeating: 0x00, count: 20)
        report[0] = 0x11
        report[1] = deviceIndex
        report[2] = 0x00
        report[3] = 0x00
        report[4] = UInt8((featureId >> 8) & 0xFF)
        report[5] = UInt8(featureId & 0xFF)

        let status = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, report, report.count)
        if status != kIOReturnSuccess {
            Log.error("Failed to query HID++ feature 0x\(String(featureId, radix: 16)) (status: \(status)). Connection may be stale.")
            self.isDeviceOpen = false
            self.activeDevice = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restartMatching()
            }
        }
    }

    private var isGestureButtonPressed = false

    private func divertGestureButtons(device: IOHIDDevice, featureIndex: UInt8, deviceIndex: UInt8) {
        for cid in gestureCIDs {
            divertControl(device: device, cid: cid, featureIndex: featureIndex, deviceIndex: deviceIndex)
        }
    }

    private func divertControl(device: IOHIDDevice, cid: UInt16, featureIndex: UInt8, deviceIndex: UInt8) {
        // HID++ 2.0 Feature 0x1B04 Function 3: setCidReporting
        // Table 6 Specification:
        // Byte 0: 0x11 (Long Report ID)
        // Byte 1: deviceIndex (0xFF for BLE)
        // Byte 2: featureIndex
        // Byte 3: 0x30 (Function 3: setCidReporting)
        // Byte 4..5: Control ID (CID)
        // Byte 6: Bit 0: Divert=1, Bit 1: Dvalid=1 -> 0x03
        // Byte 7..8: Remap (0x0000)
        var report = [UInt8](repeating: 0x00, count: 20)
        report[0] = 0x11
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = 0x30
        report[4] = UInt8((cid >> 8) & 0xFF)
        report[5] = UInt8(cid & 0xFF)
        report[6] = 0x03 // Bit 0: Divert=1, Bit 1: Dvalid=1
        report[7] = 0x00
        report[8] = 0x00

        let status = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, report, report.count)
        if status == kIOReturnSuccess {
            Log.info("Diverted button CID 0x\(String(format: "%04X", cid)) for gestures over HID++.")
        } else {
            Log.error("Failed to divert button CID 0x\(String(format: "%04X", cid)) (status: \(status)). Connection may be stale.")
            self.isDeviceOpen = false
            self.activeDevice = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.restartMatching()
            }
        }
    }

    // MARK: - Incoming Report / Value Processing

    /// Input value callback for Bluetooth LE devices.
    ///
    /// By using IOHIDDeviceSetInputValueMatchingMultiple(device, ...) with Report IDs 0x11 and 0x10,
    /// the kernel driver filters out standard mouse-movement reports (Report ID 0x02) at the driver
    /// level. This callback ONLY fires when an actual HID++ frame arrives, resulting in 0 Mach IPC
    /// messages while moving the mouse and a rock-solid 0.0% CPU footprint!
    private func handleInputValue(value: IOHIDValue) {
        let elem = IOHIDValueGetElement(value)
        let reportId = UInt8(IOHIDElementGetReportID(elem))
        let length = IOHIDValueGetLength(value)
        guard length > 0 else { return }
        let ptr = IOHIDValueGetBytePtr(value)
        guard Int(bitPattern: ptr) != 0 else { return }

        guard (reportId == 0x11 && (length == 19 || length == 20)) ||
              (reportId == 0x10 && (length == 6 || length == 7)) else {
            return
        }

        Log.debug("📥 BLE InputValue matched: ReportID=0x\(String(format: "%02X", reportId)), len=\(length)")

        var bytes: [UInt8]
        if ptr[0] == reportId && length >= 20 {
            bytes = Array(UnsafeBufferPointer(start: ptr, count: length))
        } else {
            bytes = [reportId] + Array(UnsafeBufferPointer(start: ptr, count: length))
        }

        processHIDPlusPlusReport(bytes: bytes)
    }

    /// Hot-path callback — called for USB receivers.
    private func handleInputReport(report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 7 else { return }
        let reportId = report[0]


        // Fast-exit for all non-HID++ reports.
        // For BLE composite devices this discards 125 Hz mouse-movement frames with zero
        // main-thread interaction — no Mach IPC wakeup on the main run loop.
        guard reportId == 0x11 || reportId == 0x10 else { return }

        // Copy the relevant bytes while the raw pointer is still valid on this queue.
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))

        // Dispatch all HID++ state processing to the main thread.
        // HID++ frames are rare (init responses + occasional button events) so the
        // dispatch overhead is negligible.
        DispatchQueue.main.async { [weak self] in
            self?.processHIDPlusPlusReport(bytes: bytes)
        }
    }

    /// Processes confirmed HID++ frames (0x10/0x11).
    /// ALWAYS runs on the main thread — must never be called from any other queue.
    private func processHIDPlusPlusReport(bytes: [UInt8]) {
        guard bytes.count >= 7 else { return }
        let reportId = bytes[0]
        let length   = bytes.count
        let deviceIndex = bytes[1]

        if Log.isEnabled && Log.currentLevel >= .debug {
            let hex = bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
            Log.debug("📥 HID++ IN: ID=0x\(String(format: "%02X", reportId)), len=\(length) [\(hex)]")
        }

        // 1. Long Report (20 bytes): HID++ 2.0 communication
        if reportId == 0x11 && length >= 20 {
            let featureIndex = bytes[2]
            let functionOrEvent = bytes[3]

            // Response from IRoot (Feature 0x0000): Feature Discovery Echo
            if featureIndex == 0x00 && functionOrEvent == 0x00 {
                let resolvedFeatureIndex = bytes[4]
                if resolvedFeatureIndex > 0 {
                    self.reprogFeatureIndex = resolvedFeatureIndex
                    Log.info("Resolved Reprogrammable Controls (Feature 0x1B04) at index 0x\(String(format: "%02X", resolvedFeatureIndex))")
                    if let device = self.activeDevice {
                        divertGestureButtons(device: device, featureIndex: resolvedFeatureIndex, deviceIndex: deviceIndex)
                    }
                }
                return
            }

            // Reprogrammable Controls Feature (0x1B04)
            if featureIndex == self.reprogFeatureIndex {
                let fn = functionOrEvent >> 4

                // Response to setCidReporting() (Function 3)
                if fn == 0x03 {
                    Log.debug("✅ setCidReporting confirmation received from hardware.")
                    return
                }

                // In Logitech HID++ 2.0 (Feature 0x1B04), button press/release notifications
                // are strictly Event 0 (functionOrEvent == 0x00).
                // Any other functionOrEvent value is a response to another command, query, or error,
                // and MUST NEVER be parsed as a button press!
                guard functionOrEvent == 0x00 else { return }

                // Event Notification: DivertedButtonsEvent (Array of active CIDs)
                var activeCids: [UInt16] = []
                for offset in stride(from: 4, to: min(length, 12), by: 2) {
                    let activeCid = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
                    if activeCid != 0 { activeCids.append(activeCid) }
                }

                Log.debug("🎯 Active Diverted CIDs: [\(activeCids.map { String(format: "0x%04X", $0) }.joined(separator: ", "))]")

                let isGestureDown = activeCids.contains(where: { gestureCIDs.contains($0) })

                if isGestureDown && !isGestureButtonPressed {
                    isGestureButtonPressed = true
                    Log.info("🎯 HID++ Diverted Gesture Button: PRESSED (Active CIDs: \(activeCids))")
                    EventTapManager.shared.handleHIDPlusPlusGesture(pressed: true)
                } else if !isGestureDown && isGestureButtonPressed {
                    isGestureButtonPressed = false
                    Log.info("🎯 HID++ Diverted Gesture Button: RELEASED")
                    EventTapManager.shared.handleHIDPlusPlusGesture(pressed: false)
                }
            }
        }
        // 2. Short Report (7 bytes): Legacy HID++ 1.0 or wireless notifications
        else if reportId == 0x10 && length >= 7 {
            let subId = bytes[2]
            if subId == 0x41 {
                let pairedDeviceIndex = deviceIndex
                Log.info("Wireless device connected on receiver (Device \(pairedDeviceIndex)). Initializing features...")
                if let device = self.activeDevice {
                    queryFeature(device: device, featureId: 0x1B04, deviceIndex: pairedDeviceIndex)
                }
            }
        }
    }
}

