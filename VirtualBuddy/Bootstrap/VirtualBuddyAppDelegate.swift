//
//  VirtualBuddyNSApp.swift
//  VirtualBuddy
//
//  Created by Guilherme Rambo on 07/04/22.
//

import Cocoa
@_exported import VirtualCore
@_exported import VirtualUI
import VirtualWormhole
import DeepLinkSecurity

#if BUILDING_NON_MANAGED_RELEASE
//#error("Trying to build for release without using the managed scheme. This build won't include managed entitlements. This error is here for Rambo, you may safely comment it out and keep going.")
#endif

@objc final class VirtualBuddyAppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        if #available(macOS 13.0, *) {
            Task {
                await MainActor.run {
                    DeepLinkHandler.bootstrap()
                }
            }
        }
        
        NSApp?.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            try? await GuestAdditionsDiskImage.current.installIfNeeded()
        }
    }
    
    @objc func restoreDefaultWindowPosition(_ sender: Any?) {
        guard let window = NSApp?.keyWindow ?? NSApp?.mainWindow else { return }
        
        window.setFrame(.init(x: 0, y: 0, width: 960, height: 600), display: true, animate: false)
        window.center()
    }
    
}
