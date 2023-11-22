//
//  ConfigurationModels+Validation.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 19/07/22.
//

import Cocoa
import UniformTypeIdentifiers

public extension VBMacConfiguration {
    
    func validate(for model: VBVirtualMachine, skipVirtualizationConfig: Bool) async -> SupportState {
        var tempModel = model
        tempModel.configuration = self

        guard !skipVirtualizationConfig else {
            return hostSupportState
        }

        do {
            let config = try await VMInstance.makeConfiguration(for: tempModel)
            
            try config.validate()
            
            return hostSupportState
        } catch {
            return hostSupportState.merged(with: .unsupported([error.localizedDescription]))
        }
    }
    
}

public extension VBMacConfiguration {
    /// The state of this configuration for the current host, used to indicate
    /// possible issues the user may have with it, or to prevent unsupported
    /// configurations from being saved.
    var hostSupportState: SupportState {
        var warnings = [String]()
        var errors = [String]()
        
        if !hardware.pointingDevice.kind.isSupportedByHost {
            errors.append("\(hardware.pointingDevice.kind.name) requires macOS 13 or later.")
        }
        if hasSharedFolders {
            if VBMacConfiguration.isFileSharingSupported {
                warnings.append(VBMacConfiguration.fileSharingNotice)
            } else {
                errors.append(VBMacConfiguration.fileSharingNotice)
            }
        }
        if hardware.networkDevices.contains(where: { $0.kind == .bridge }), !VBNetworkDevice.appSupportsBridgedNetworking {
            errors.append(VBNetworkDevice.bridgeUnsupportedMessage)
        }
        
        return SupportState(errors: errors, warnings: warnings)
    }

    static let isFileSharingSupported: Bool = {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return false
        }
    }()

    static let fileSharingNotice: String = {
        let tip = "For previous OS versions, you can use the standard macOS file sharing feature in System Preferences > Sharing."

        if isFileSharingSupported {
            return "File sharing requires the virtual machine to be running macOS 13 or later. \(tip)"
        } else {
            return "File sharing requires both the host Mac and the virtual machine to be running macOS 13 or later. \(tip)"
        }
    }()
}

public extension VBMacConfiguration.SupportState {
    var errors: [String] {
        guard case .unsupported(let errors) = self else {
            return []
        }
        return errors
    }
    
    var warnings: [String] {
        guard case .warnings(let warnings) = self else {
            return []
        }
        return warnings
    }
    
    var allowsSaving: Bool { errors.isEmpty }
    
    init(errors: [String] = [], warnings: [String] = []) {
        if errors.isEmpty {
            if warnings.isEmpty {
                self = .supported
            } else {
                self = .warnings(warnings)
            }
        } else {
            self = .unsupported(errors)
        }
    }
    
    func merged(with other: Self) -> Self {
        Self.init(errors: errors + other.errors, warnings: warnings + other.warnings)
    }
}

public extension VBNetworkDevice {
    static var appSupportsBridgedNetworking: Bool {
        NSApplication.shared.hasEntitlement("com.apple.vm.networking")
    }
    
    static let bridgeUnsupportedMessage = "Bridged network devices are not available in this build of the app."
}

public extension VBDisplayDevice {
    static let automaticallyReconfiguresDisplayWarningMessage = "Automatic display configuration is only recognized by VMs running macOS 14 and later."
    
    static var automaticallyReconfiguresDisplaySupportedByHost: Bool {
        if #available(macOS 14.0, *) {
            return true
        } else {
            return false
        }
    }
}

public extension VBPointingDevice.Kind {
    var warning: String? {
        guard self == .trackpad else { return nil }
        return "Trackpad is only recognized by VMs running macOS 13 and later."
    }
    
    var error: String? {
        guard !isSupportedByHost else { return nil }
        return "Trackpad requires both host and VM to be on macOS 13 or later."
    }

    var isSupportedByHost: Bool {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return self == .mouse
        }
    }
}

public extension VBKeyboardDevice.Kind {
    var warning: String? {
        guard self != .generic else { return nil }
        return "Mac keyboard is only recognized by VMs running macOS 13 and later."
    }

    var error: String? {
        guard !isSupportedByHost else { return nil }
        return "Mac keyboard requires macOS 14 or later on host and macOS 13 or later on VM."
    }

    var isSupportedByHost: Bool {
        switch self {
        case .generic:
            return true
        case .mac:
            if #available(macOS 14.0, *) {
                return true
            } else {
                return false
            }
        }
    }
}

public extension VBGuestType {
    var isSupportedByHost: Bool {
        switch self {
        case .mac:
            return true
        case .linux:
            guard #available(macOS 13.0, *) else { return false }
            #if DEBUG
            return !UserDefaults.standard.bool(forKey: "VBSimulateLinuxGuestNotSupported")
            #else
            return true
            #endif
        }
    }

    static let supportedByHost: [VBGuestType] = {
        allCases.filter(\.isSupportedByHost)
    }()

    var supportsVirtualTrackpad: Bool { self == .mac }

    var supportsKeyboardCustomization: Bool { self == .mac }

    var supportsDisplayPPI: Bool { self == .mac }

    var supportedRestoreImageTypes: Set<UTType> {
        switch self {
        case .mac: return [.ipsw]
        case .linux: return [.iso, .img]
        }
    }
    
}

public extension UTType {
    static let ipsw = UTType(filenameExtension: "ipsw")!
    static let iso = UTType(filenameExtension: "iso")!
    static let img = UTType(filenameExtension: "img")!
}
