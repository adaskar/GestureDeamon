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

        // Match BOTH USB Receivers (0xFF00) and Direct Bluetooth Low Energy (0xFF43:0x0202)
        let matchingCriteria: [[String: Any]] = [
            // 1. USB Unifying & Bolt Receivers
            [
                kIOHIDVendorIDKey as String: 0x046d,
                kIOHIDPrimaryUsagePageKey as String: 0xff00
            ],
            // 2. Direct Bluetooth LE (Primary Usage Page 0xFF43)
            [
                kIOHIDVendorIDKey as String: 0x046d,
                kIOHIDPrimaryUsagePageKey as String: 0xff43
            ],
            // 3. Direct Bluetooth LE (Matched via DeviceUsagePairs collection)
            [
                kIOHIDVendorIDKey as String: 0x046d,
                kIOHIDDeviceUsagePageKey as String: 0xff43
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

        let productName = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Logitech Device"
        let transportStr = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "Unknown"

        let transport: TransportType = transportStr.localizedCaseInsensitiveContains("Bluetooth") ? .bluetoothLE : .usb
        self.connectedDeviceName = productName
        self.connectedTransport = transport

        Log.info("⚡️ Logitech Device detected: '\(productName)' over \(transport.rawValue)")

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))

        if openResult == kIOReturnSuccess {
            self.isDeviceOpen = true
            Log.info("Connected to HID++ interface on '\(productName)' successfully.")

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

            // Configure device based on transport
            switch transport {
            case .usb:
                enableReceiverNotifications(device)
            case .bluetoothLE:
                // Direct BLE devices use index 0xFF and require HID++ 2.0 Long Reports
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

        // 1. Immediate hardware diversion sync
        reapplyHardwareDiversion()

        // 2. Staged retries at +1.0s and +2.5s to account for Bluetooth link re-establishment
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Log.info("☀️ Wake stage 1 (+1.0s): Verifying HID++ hardware connection...")
            self?.reapplyHardwareDiversion()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            Log.info("☀️ Wake stage 2 (+2.5s): Confirming HID++ diversion...")
            self?.reapplyHardwareDiversion()
        }
    }

    public func reapplyHardwareDiversion() {
        self.isGestureButtonPressed = false
        guard let device = self.activeDevice, self.isDeviceOpen else {
            Log.info("No active open device found on wake. Re-checking HID Manager...")
            if self.activeDevice == nil {
                restartMatching()
            }
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
            Log.error("Failed to query HID++ feature 0x\(String(featureId, radix: 16)) (status: \(status))")
        }
    }

    private var isGestureButtonPressed = false

    private func divertGestureButtons(device: IOHIDDevice, featureIndex: UInt8, deviceIndex: UInt8) {
        // Query control count first to inspect all buttons on this mouse
        queryControlCount(device: device, featureIndex: featureIndex, deviceIndex: deviceIndex)

        for cid in gestureCIDs {
            divertControl(device: device, cid: cid, featureIndex: featureIndex, deviceIndex: deviceIndex)
        }
    }

    private func queryControlCount(device: IOHIDDevice, featureIndex: UInt8, deviceIndex: UInt8) {
        var report = [UInt8](repeating: 0x00, count: 20)
        report[0] = 0x11
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = 0x00 // Function 0: getCount
        _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, report, report.count)
    }

    private func queryControlInfo(device: IOHIDDevice, featureIndex: UInt8, controlIndex: UInt8, deviceIndex: UInt8) {
        var report = [UInt8](repeating: 0x00, count: 20)
        report[0] = 0x11
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = 0x10 // Function 1: getCidInfo
        report[4] = controlIndex
        _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, report, report.count)
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
            Log.error("Failed to divert button CID 0x\(String(format: "%04X", cid)) (status: \(status))")
        }
    }

    // MARK: - Incoming Report Processing
    private func handleInputReport(report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 7 else { return }
        let reportId = report[0]

        // Strictly ignore standard mouse pointer motion and clicks (Report ID 0x02, etc.)
        // This prevents flooding daemon.log with thousands of mouse cursor events!
        guard reportId == 0x11 || reportId == 0x10 else { return }

        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        let deviceIndex = bytes[1]

        let hex = bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
        Log.debug("📥 HID++ IN: ID=0x\(String(format: "%02X", reportId)), len=\(length) [\(hex)]")

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

                // Response to getCount() (Function 0)
                if fn == 0x00 && length >= 5 && bytes[4] > 0 && bytes[4] < 64 {
                    let count = bytes[4]
                    Log.info("📋 0x1B04 Total Control Count: \(count)")
                    if let dev = self.activeDevice {
                        for i in 0..<count {
                            queryControlInfo(device: dev, featureIndex: featureIndex, controlIndex: i, deviceIndex: deviceIndex)
                        }
                    }
                    return
                }

                // Response to getCidInfo() (Function 1)
                if fn == 0x01 && length >= 9 {
                    let cid = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
                    let task = (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
                    let flags = bytes[8]
                    Log.info("📋 Control: CID=0x\(String(format: "%04X", cid)), Task=0x\(String(format: "%04X", task)), Flags=0x\(String(format: "%02X", flags))")

                    // Divert if it is the gesture button (Task 0x00B4), or matches known gesture CIDs
                    if task == 0x00B4 || gestureCIDs.contains(cid) {
                        Log.info("🎯 Found Gesture Button Control (CID: 0x\(String(format: "%04X", cid)), Task: 0x\(String(format: "%04X", task))). Diverting...")
                        if let dev = self.activeDevice {
                            divertControl(device: dev, cid: cid, featureIndex: featureIndex, deviceIndex: deviceIndex)
                        }
                    }
                    return
                }

                // Response to setCidReporting() (Function 3)
                if fn == 0x03 {
                    Log.debug("✅ setCidReporting confirmation received from hardware.")
                    return
                }

                // Event Notification: DivertedButtonsEvent (Array of active CIDs)
                var activeCids: [UInt16] = []
                for offset in stride(from: 4, to: min(length, 12), by: 2) {
                    let activeCid = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
                    if activeCid != 0 {
                        activeCids.append(activeCid)
                    }
                }

                Log.debug("🎯 Active Diverted CIDs: [\(activeCids.map { String(format: "0x%04X", $0) }.joined(separator: ", "))]")

                // Check if any active CID is a gesture button
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
            // Wireless device connection notification from receiver
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
