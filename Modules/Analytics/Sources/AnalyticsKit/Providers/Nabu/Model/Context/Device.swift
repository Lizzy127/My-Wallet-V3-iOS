// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import Foundation

struct Device: Encodable {
    let id: String?
    let manufacturer: String
    let model: String
    let name: String
    let type: String
}

#if canImport(UIKit)
import UIKit

extension Device {

    init(device: UIDevice = UIDevice.current) {
        id = device.identifierForVendor?.uuidString
        manufacturer = "Apple"
        model = device.model
        name = device.name
        type = "ios"
    }
}

#endif

#if canImport(AppKit)
import AppKit

extension Device {

    init(host: Host = .current()) {
        func serialNumber() -> String {
            let platformExpert = IOServiceGetMatchingService(
                kIOMasterPortDefault,
                IOServiceMatching("IOPlatformExpertDevice")
            )
            defer { IOObjectRelease(platformExpert) }
            let serialNumber = IORegistryEntryCreateCFProperty(
                platformExpert,
                kIOPlatformSerialNumberKey as CFString,
                kCFAllocatorDefault,
                0
            )
            return (serialNumber?.takeUnretainedValue() as? String) ?? "<anonymous>"
        }
        id = serialNumber()
        manufacturer = "Apple"
        model = "mac"
        name = host.localizedName ?? "<anonymous>"
        type = "macos"
    }
}

#endif
