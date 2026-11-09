import Foundation
import GlimmerCore
import IOKit
import IOKit.hid

/// Liest Bewegungssensor und Deckelwinkel. Beide Schnittstellen sind undokumentiert.
final class SensorHub {
    var onSample: ((Acceleration) -> Void)?

    private var manager: IOHIDManager?
    private var lidDevice: IOHIDDevice?
    private var motionDevice: IOHIDDevice?
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    deinit {
        stop()
        buffer.deallocate()
    }

    private static func matching(_ page: Int, _ usage: Int) -> CFDictionary {
        [kIOHIDPrimaryUsagePageKey: page, kIOHIDPrimaryUsageKey: usage] as CFDictionary
    }

    private static func setReporting(_ enabled: Bool) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let property: (String) -> Int? = {
                IORegistryEntryCreateCFProperty(service, $0 as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
            }
            guard property("PrimaryUsagePage") == 0xFF00, property("PrimaryUsage") == 3 else { continue }
            let value = (enabled ? 1 : 0) as CFNumber
            IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, value)
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, value)
            IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, 10000 as CFNumber)
        }
    }

    @discardableResult
    func start() -> Bool {
        guard manager == nil else { return true }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(
            manager,
            [Self.matching(0x20, 0x8A), Self.matching(0xFF00, 3)] as CFArray
        )
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        self.manager = manager
        Self.setReporting(true)
        for device in (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [] {
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
            if product == "las" {
                IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                lidDevice = device
            } else if product == "accel" {
                IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
                IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                let context = Unmanaged.passUnretained(self).toOpaque()
                IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, _, _, _, report, length in
                    guard let context else { return }
                    let hub = Unmanaged<SensorHub>.fromOpaque(context).takeUnretainedValue()
                    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                    if let sample = SensorDecoding.acceleration(from: bytes) { hub.onSample?(sample) }
                }, context)
                motionDevice = device
            }
        }
        return motionDevice != nil
    }

    func stop() {
        guard let manager else { return }
        if let motionDevice {
            IOHIDDeviceUnscheduleFromRunLoop(motionDevice, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        Self.setReporting(false)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        motionDevice = nil
        lidDevice = nil
    }

    func lidAngle() -> Int? {
        guard let lidDevice else { return nil }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        guard IOHIDDeviceGetReport(lidDevice, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess else { return nil }
        return SensorDecoding.lidAngle(from: Array(report.prefix(length)))
    }
}
