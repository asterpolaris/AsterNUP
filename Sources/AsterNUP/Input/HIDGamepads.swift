import Foundation
import IOKit.hid
import GameController

/// Gamepads macOS pairs but Apple's GameController framework does not list (e.g. some Nintendo Switch Online
/// controllers or a Pro Controller in a mode macOS does not claim), read as raw HID gamepads, as nxnative's host does.
/// A device GameController already lists is skipped, so no press is delivered twice.
final class HIDGamepads {
    struct Device: Hashable { var name: String; var vendorID: Int; var productID: Int; var transport: String; var claimedByGameController: Bool }

    static let nintendoVendor = 0x057E
    var onAction: ((NavAction) -> Void)?
    var onHomeTap: (() -> Void)?
    private(set) var devices: [IOHIDDevice: Device] = [:]
    var onDevicesChanged: (() -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var hat: [IOHIDDevice: NavAction?] = [:]
    private var axis: [IOHIDDevice: [UInt32: NavAction?]] = [:]
    private var homeDown: [IOHIDDevice: Date] = [:]
    private var claimCheckedAt: [IOHIDDevice: Date] = [:]
    private var background = false

    init() {
        let match: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, match as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<HIDGamepads>.fromOpaque(ctx!).takeUnretainedValue().added(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<HIDGamepads>.fromOpaque(ctx!).takeUnretainedValue().removed(dev)
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            Unmanaged<HIDGamepads>.fromOpaque(ctx!).takeUnretainedValue().input(value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess { AppLog.write("HID gamepads: IOHIDManagerOpen returned \(r)") }
    }

    /// While a game is in front, only the HOME button is delivered: IOKit stops queueing every stick, trigger and motion
    /// report for AsterNUP, so the launcher does no work per controller report while the game reads the same pad.
    func setBackground(_ bg: Bool) {
        guard bg != background else { return }
        background = bg
        if bg {
            let home: [String: Any] = [kIOHIDElementUsagePageKey: kHIDPage_Button, kIOHIDElementUsageKey: 13]
            IOHIDManagerSetInputValueMatching(manager, home as CFDictionary)
        } else {
            IOHIDManagerSetInputValueMatching(manager, nil)
        }
        hat.removeAll(); axis.removeAll()
    }

    private func prop(_ d: IOHIDDevice, _ k: String) -> Any? { IOHIDDeviceGetProperty(d, k as CFString) }

    private func added(_ d: IOHIDDevice) {
        let name = prop(d, kIOHIDProductKey) as? String ?? "HID gamepad"
        let dev = Device(name: name, vendorID: prop(d, kIOHIDVendorIDKey) as? Int ?? 0, productID: prop(d, kIOHIDProductIDKey) as? Int ?? 0,
                         transport: prop(d, kIOHIDTransportKey) as? String ?? "?", claimedByGameController: Self.listedByGameController(name))
        devices[d] = dev
        AppLog.write("HID gamepad connected: \(name) vid=\(String(format: "%04X", dev.vendorID)) pid=\(String(format: "%04X", dev.productID)) \(dev.transport) gc=\(dev.claimedByGameController)")
        onDevicesChanged?()
    }

    private func removed(_ d: IOHIDDevice) {
        devices[d] = nil; hat[d] = nil; axis[d] = nil; homeDown[d] = nil; claimCheckedAt[d] = nil
        onDevicesChanged?()
    }

    static func listedByGameController(_ name: String) -> Bool {
        let n = name.lowercased()
        return GCController.controllers().contains { c in
            let v = (c.vendorName ?? "").lowercased()
            return !v.isEmpty && (v == n || n.contains(v) || v.contains(n))
        }
    }

    private func input(_ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let dev = IOHIDElementGetDevice(el)
        guard var info = devices[dev] else { return }
        // Re-check now and then (not on every report): GameController may list the device a moment after HID sees it.
        if Date().timeIntervalSince(claimCheckedAt[dev] ?? .distantPast) > 2 {
            claimCheckedAt[dev] = Date()
            info.claimedByGameController = Self.listedByGameController(info.name)
            devices[dev] = info
        }
        guard !info.claimedByGameController else { return }
        let page = IOHIDElementGetUsagePage(el), usage = IOHIDElementGetUsage(el)
        let v = IOHIDValueGetIntegerValue(value)
        if page == UInt32(kHIDPage_Button) {
            button(Int(usage), pressed: v != 0, dev: dev, nintendo: info.vendorID == Self.nintendoVendor)
        } else if page == UInt32(kHIDPage_GenericDesktop) {
            if usage == UInt32(kHIDUsage_GD_Hatswitch) {
                let lo = IOHIDElementGetLogicalMin(el), hi = IOHIDElementGetLogicalMax(el)
                let n = hi - lo + 1, idx = v - lo
                var d: NavAction?
                if idx >= 0 && idx < n {
                    let eighth = n == 8 ? idx : idx * 8 / max(n, 1)   // 0 = up, clockwise
                    switch eighth { case 0, 1: d = .up; case 2, 3: d = .right; case 4, 5: d = .down; case 6, 7: d = .left; default: d = nil }
                }
                if hat[dev] ?? nil != d { hat[dev] = d; if let d { onAction?(d) } }
            } else if usage == UInt32(kHIDUsage_GD_X) || usage == UInt32(kHIDUsage_GD_Y) {
                let lo = Double(IOHIDElementGetLogicalMin(el)), hi = Double(IOHIDElementGetLogicalMax(el))
                guard hi > lo else { return }
                let f = (Double(v) - lo) / (hi - lo) * 2 - 1   // -1…1
                let isX = usage == UInt32(kHIDUsage_GD_X)
                let d: NavAction? = f > 0.6 ? (isX ? .right : .down) : f < -0.6 ? (isX ? .left : .up) : nil
                var a = axis[dev] ?? [:]
                if a[usage] ?? nil != d { a[usage] = d; axis[dev] = a; if let d { onAction?(d) } }
            }
        }
    }

    /// Nintendo controllers in HID mode report buttons in this order (Pro Controller / Joy-Con simple report):
    /// 1 B, 2 A, 3 Y, 4 X, 5 L, 6 R, 7 ZL, 8 ZR, 9 −, 10 +, 11 L-stick, 12 R-stick, 13 HOME, 14 Capture.
    /// Other gamepads: 1 confirm, 2 back, 3 X, 4 Y, 5 L, 6 R, 9 −, 10 +, 13 HOME.
    private func button(_ n: Int, pressed: Bool, dev: IOHIDDevice, nintendo: Bool) {
        let map: [Int: NavAction] = nintendo
            ? [1: .back, 2: .confirm, 3: .y, 4: .x, 5: .shoulderL, 6: .shoulderR, 9: .minus, 10: .plus]
            : [1: .confirm, 2: .back, 3: .x, 4: .y, 5: .shoulderL, 6: .shoulderR, 9: .minus, 10: .plus]
        if n == 13 {
            if pressed { homeDown[dev] = Date() }
            else if let t = homeDown.removeValue(forKey: dev), Date().timeIntervalSince(t) < 0.8 { onHomeTap?() }
            return
        }
        if pressed, let a = map[n] { onAction?(a) }
    }
}
