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

    private final class ManagedDevice {
        let device: IOHIDDevice
        let name: String
        let transport: TransportType
        var reprogFeatureIndex: UInt8?
        var isOpen: Bool = false
        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

        init(device: IOHIDDevice, name: String, transport: TransportType) {
            self.device = device
            self.name = name
            self.transport = transport
        }

        deinit {
            reportBuffer.deallocate()
        }
    }

    private var hidManager: IOHIDManager?
    private var activeDevice: IOHIDDevice?
    private var managedDevices: [IOHIDDevice: ManagedDevice] = [:]
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
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

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
        for (dev, _) in managedDevices {
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        managedDevices.removeAll()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.activeDevice = nil
        self.hidManager = nil
        self.isStarted = false
        self.connectedDeviceName = nil
        self.connectedTransport = nil
        self.isDeviceOpen = false
        self.reprogFeatureIndex = nil
        Log.info("HID++ Manager stopped.")
    }

    private func updateActiveDevice() {
        // Priority 1: Bluetooth LE device (direct mouse connection)
        if let ble = managedDevices.values.first(where: { $0.transport == .bluetoothLE && $0.isOpen }) {
            self.activeDevice = ble.device
            self.connectedDeviceName = ble.name
            self.connectedTransport = .bluetoothLE
            self.reprogFeatureIndex = ble.reprogFeatureIndex
            self.isDeviceOpen = true
            return
        }

        // Priority 2: USB Receiver (Unifying or Bolt dongle)
        if let usb = managedDevices.values.first(where: { $0.transport == .usb && $0.isOpen }) {
            self.activeDevice = usb.device
            self.connectedDeviceName = usb.name
            self.connectedTransport = .usb
            self.reprogFeatureIndex = usb.reprogFeatureIndex
            self.isDeviceOpen = true
            return
        }

        self.activeDevice = nil
        self.connectedDeviceName = nil
        self.connectedTransport = nil
        self.reprogFeatureIndex = nil
        self.isDeviceOpen = false
    }

    private func deviceConnected(_ device: IOHIDDevice) {
        if let existing = managedDevices[device], existing.isOpen {
            return
        }

        let productName = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Logitech Device"
        let transportStr = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "Unknown"
        let transport: TransportType = transportStr.localizedCaseInsensitiveContains("Bluetooth") ? .bluetoothLE : .usb

        Log.info("⚡️ Logitech Device detected: '\(productName)' over \(transport.rawValue)")

        let managed = ManagedDevice(device: device, name: productName, transport: transport)
        managedDevices[device] = managed

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))

        if openResult == kIOReturnSuccess {
            managed.isOpen = true
            Log.info("Connected to HID++ interface on '\(productName)' successfully.")

            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

            switch transport {
            case .usb:
                IOHIDDeviceRegisterInputReportCallback(
                    device,
                    managed.reportBuffer,
                    64,
                    { context, result, sender, type, reportId, report, reportLength in
                        guard let context = context else { return }
                        let manager = Unmanaged<HIDPlusPlusManager>.fromOpaque(context).takeUnretainedValue()
                        let dev = sender.map { Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue() }
                        manager.handleInputReport(device: dev, report: report, length: reportLength)
                    },
                    context
                )
                enableReceiverNotifications(device)
                queryFeature(device: device, featureId: 0x1B04, deviceIndex: 0x01)
                queryFeature(device: device, featureId: 0x1B04, deviceIndex: 0xFF)

            case .bluetoothLE:
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
                        let dev = sender.map { Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue() }
                        manager.handleInputValue(device: dev, value: value)
                    },
                    context
                )

                discoverBLEFeatures(device)
            }

            updateActiveDevice()
        } else if openResult == -536870174 { // 0xe00002e2 = kIOReturnNotPermitted
            Log.error("⚠️ Cannot open Bluetooth HID++ channel on '\(productName)': Input Monitoring permission missing.")
            PermissionHelper.requestInputMonitoring()
        } else {
            Log.error("Failed to open HID++ device '\(productName)' (status: \(openResult)).")
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        let name = managedDevices[device]?.name ?? "Logitech Device"
        Log.info("Logitech Device disconnected: '\(name)'.")

        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        managedDevices.removeValue(forKey: device)

        self.isGestureButtonPressed = false
        updateActiveDevice()

        if let active = self.activeDevice, let current = managedDevices[active] {
            Log.info("⚡️ Switched active HID++ device to '\(current.name)' over \(current.transport.rawValue)")
            if current.transport == .usb {
                enableReceiverNotifications(active)
                queryFeature(device: active, featureId: 0x1B04, deviceIndex: 0x01)
                queryFeature(device: active, featureId: 0x1B04, deviceIndex: 0xFF)
            } else if current.transport == .bluetoothLE {
                discoverBLEFeatures(active)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.activeDevice == nil else { return }
                self.restartMatching()
            }
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
            if self.managedDevices.isEmpty {
                self.restartMatching()
            } else {
                self.reapplyHardwareDiversion()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            Log.info("☀️ Wake stage 2 (+3.0s): Confirming HID++ diversion...")
            if self.managedDevices.isEmpty {
                self.restartMatching()
            } else {
                self.reapplyHardwareDiversion()
            }
        }
    }

    public func reapplyHardwareDiversion() {
        self.isGestureButtonPressed = false
        if managedDevices.isEmpty {
            Log.info("No active open device found. Re-checking HID Manager...")
            restartMatching()
            return
        }

        for (device, managed) in managedDevices where managed.isOpen {
            switch managed.transport {
            case .bluetoothLE:
                discoverBLEFeatures(device)
            case .usb:
                enableReceiverNotifications(device)
                for idx: UInt8 in 1...6 {
                    queryFeature(device: device, featureId: 0x1B04, deviceIndex: idx)
                }
                queryFeature(device: device, featureId: 0x1B04, deviceIndex: 0xFF)
                if let reprogIndex = managed.reprogFeatureIndex {
                    divertGestureButtons(device: device, featureIndex: reprogIndex, deviceIndex: 0xFF)
                    for idx: UInt8 in 1...6 {
                        divertGestureButtons(device: device, featureIndex: reprogIndex, deviceIndex: idx)
                    }
                }
            }
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
        // Byte 1: deviceIndex (0xFF for direct BLE, 0x01..0x06 for receiver paired devices)
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
            Log.error("Failed to query HID++ feature 0x\(String(featureId, radix: 16)) on deviceIndex 0x\(String(format: "%02X", deviceIndex)) (status: \(status)).")
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
        // Byte 1: deviceIndex (0xFF for BLE, 0x01..0x06 for receiver paired devices)
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
            Log.info("Diverted button CID 0x\(String(format: "%04X", cid)) on deviceIndex 0x\(String(format: "%02X", deviceIndex)) for gestures over HID++.")
        } else {
            Log.error("Failed to divert button CID 0x\(String(format: "%04X", cid)) on deviceIndex 0x\(String(format: "%02X", deviceIndex)) (status: \(status)).")
        }
    }

    // MARK: - Incoming Report / Value Processing

    /// Input value callback for Bluetooth LE devices.
    ///
    /// By using IOHIDDeviceSetInputValueMatchingMultiple(device, ...) with Report IDs 0x11 and 0x10,
    /// the kernel driver filters out standard mouse-movement reports (Report ID 0x02) at the driver
    /// level. This callback ONLY fires when an actual HID++ frame arrives, resulting in 0 Mach IPC
    /// messages while moving the mouse and a rock-solid 0.0% CPU footprint!
    private func handleInputValue(device: IOHIDDevice?, value: IOHIDValue) {
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

        processHIDPlusPlusReport(fromDevice: device, bytes: bytes)
    }

    /// Hot-path callback — called for USB receivers.
    private func handleInputReport(device: IOHIDDevice?, report: UnsafePointer<UInt8>, length: Int) {
        guard length >= 7 else { return }
        let reportId = report[0]

        // Fast-exit for all non-HID++ reports.
        // For BLE composite devices this discards 125 Hz mouse-movement frames with zero
        // main-thread interaction — no Mach IPC wakeup on the main run loop.
        guard reportId == 0x11 || reportId == 0x10 else { return }

        // Copy the relevant bytes while the raw pointer is still valid on this queue.
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))

        // If already on the main thread (standard when scheduled on the main run loop),
        // process immediately to eliminate dispatch scheduling latency.
        if Thread.isMainThread {
            processHIDPlusPlusReport(fromDevice: device, bytes: bytes)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.processHIDPlusPlusReport(fromDevice: device, bytes: bytes)
            }
        }
    }

    /// Processes confirmed HID++ frames (0x10/0x11).
    /// ALWAYS runs on the main thread — must never be called from any other queue.
    private func processHIDPlusPlusReport(fromDevice: IOHIDDevice?, bytes: [UInt8]) {
        guard bytes.count >= 7 else { return }
        let reportId = bytes[0]
        let length   = bytes.count
        let deviceIndex = bytes[1]
        let targetDevice = fromDevice ?? self.activeDevice

        if Log.isEnabled && Log.currentLevel >= .debug {
            let hex = bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
            Log.debug("📥 HID++ IN: ID=0x\(String(format: "%02X", reportId)), len=\(length) [\(hex)]")
        }

        // Auto-switch active device to targetDevice if report came from an open device that wasn't marked active
        if let dev = targetDevice, let managed = managedDevices[dev], self.activeDevice != dev {
            self.activeDevice = dev
            self.connectedDeviceName = managed.name
            self.connectedTransport = managed.transport
            self.reprogFeatureIndex = managed.reprogFeatureIndex
            self.isDeviceOpen = true
            Log.info("⚡️ Active device automatically switched to '\(managed.name)' (\(managed.transport.rawValue)) due to incoming traffic.")
        }

        // 1. Long Report (20 bytes): HID++ 2.0 communication
        if reportId == 0x11 && length >= 20 {
            let featureIndex = bytes[2]
            let functionOrEvent = bytes[3]

            // Response from IRoot (Feature 0x0000): Feature Discovery Echo
            if featureIndex == 0x00 && functionOrEvent == 0x00 {
                let resolvedFeatureIndex = bytes[4]
                if resolvedFeatureIndex > 0 {
                    if let dev = targetDevice, let managed = managedDevices[dev] {
                        managed.reprogFeatureIndex = resolvedFeatureIndex
                    }
                    self.reprogFeatureIndex = resolvedFeatureIndex
                    Log.info("Resolved Reprogrammable Controls (Feature 0x1B04) at index 0x\(String(format: "%02X", resolvedFeatureIndex)) on deviceIndex 0x\(String(format: "%02X", deviceIndex))")
                    if let dev = targetDevice {
                        divertGestureButtons(device: dev, featureIndex: resolvedFeatureIndex, deviceIndex: deviceIndex)
                    }
                }
                return
            }

            // Reprogrammable Controls Feature (0x1B04)
            let devReprog = targetDevice.flatMap { managedDevices[$0]?.reprogFeatureIndex }
            let expectedFeatureIndex = devReprog ?? self.reprogFeatureIndex
            if let expected = expectedFeatureIndex, featureIndex == expected {
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
                if let dev = targetDevice {
                    queryFeature(device: dev, featureId: 0x1B04, deviceIndex: pairedDeviceIndex)
                }
            }
        }
    }
}

