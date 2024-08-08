//
//  WindowEnvironment.swift
//  StatusBuddy
//
//  Created by Guilherme Rambo on 21/12/21.
//  Copyright © 2021 Guilherme Rambo. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - Public API

public extension EnvironmentValues {
    
    /// Closes the window that's hosting this view.
    /// Only available when the view hierarchy is being presented with `HostingWindowController`.
    var closeWindow: () -> Void {
        get { self[CloseWindowEnvironmentKey.self] }
        set { self[CloseWindowEnvironmentKey.self] = newValue }
    }
    
}

public extension View {
    
    /// Sets the title for the window that contains this SwiftUI view.
    /// Only available when the view hierarchy is being presented with `HostingWindowController`.
    func windowTitle(_ title: String) -> some View {
        environment(\.windowTitle, title)
    }

    /// Sets the title visibility for the window that contains this SwiftUI view.
    /// Only available when the view hierarchy is being presented with `HostingWindowController`.
    func windowTitleHidden(_ hidden: Bool) -> some View {
        environment(\.windowTitleVisibility, hidden ? .hidden : .visible)
    }

    /// Sets whether the title bar background is hidden for the window that contains this SwiftUI view.
    /// Only available when the view hierarchy is being presented with `HostingWindowController`.
    func windowTitleBarTransparent(_ transparent: Bool) -> some View {
        environment(\.windowTitleBarTransparent, transparent)
    }
    
    /// When `true`, indicates that the view hierarchy is responsible for render its own chrome for
    /// the Cocoa window that's hosting it. Causes `HostingWindowController` to configure
    /// its window to provide no chrome.
    func rendersWindowChrome(_ flag: Bool = true) -> some View {
        environment(\.rendersWindowChrome, flag)
    }
    
    /// When `true`, the hosting window can be moved by either clicking and dragging in the title bar,
    /// or by clicking and dragging the window's background when there's no title bar.
    /// Only available when the view hierarchy is being presented with `HostingWindowController`.
    func windowMovable(_ flag: Bool = true) -> some View {
        environment(\.windowMovable, flag)
    }
    
    /// Sets the level of the Cocoa window that's hosting this view hierarchy.
    /// Only available when the view hierarchy is being presented with `HostingWindowController`.
    func windowLevel(_ level: NSWindow.Level) -> some View {
        environment(\.windowLevel, level)
    }
    
    /// Sets the style mask of the Cocoa window that's hosting this view hierarchy.
    /// Note that usage of `rendersWindowChrome` may override the style mask set using this modifier and vice-versa.
    /// Only available when the view hierarchy is being presented with `HostingWindowController`.
    func windowStyleMask(_ mask: NSWindow.StyleMask) -> some View {
        environment(\.windowStyleMask, mask)
    }
    
    /// Performs the specific block when the window hosting the view hierarchy changes its occlusion state.
    func onWindowOcclusionStateChanged(perform block: @escaping (NSWindow.OcclusionState) -> Void) -> some View {
        environment(\.onWindowOcclusionStateChanged, block)
    }

    func confirmBeforeClosingWindow(callback: @escaping () async -> Bool) -> some View {
        environment(\.confirmBeforeClosingWindow, callback)
    }

    func onWindowKeyChange(perform callback: @escaping (Bool) -> Void) -> some View {
        modifier(OnWindowKeyChangedModifier(callback: callback))
    }
    
}

// MARK: - Hosting Window Environment Keys

private struct CloseWindowEnvironmentKey: EnvironmentKey {
    static let defaultValue: () -> Void = { }
}

private struct ConfirmBeforeClosingWindowEnvironmentKey: EnvironmentKey {
    static let defaultValue: () async -> Bool = { false }
}

private struct WindowTitleEnvironmentKey: EnvironmentKey {
    static let defaultValue: String = ""
}

private struct WindowTitleVisibilityEnvironmentKey: EnvironmentKey {
    static let defaultValue: NSWindow.TitleVisibility = .visible
}

private struct WindowTitleBarTransparentEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct HostingWindowKey: EnvironmentKey {
    static let defaultValue: () -> NSWindow? = { nil }
}

private struct RendersWindowChromeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

private struct WindowMovableEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

private struct WindowLevelEnvironmentKey: EnvironmentKey {
    static let defaultValue: NSWindow.Level = .normal
}

private struct WindowStyleMaskEnvironmentKey: EnvironmentKey {
    static let defaultValue: NSWindow.StyleMask = defaultHostingWindowStyleMask
}

private struct WindowOnOcclusionStateChangedEnvironmentKey: EnvironmentKey {
    static let defaultValue: ((NSWindow.OcclusionState) -> Void)? = nil
}

extension EnvironmentValues {
    
    private var windowChromeConsumer: WindowChromeConsumer? {
        cocoaWindow?.windowController as? WindowChromeConsumer
    }
    
    /// Set and used internally by `HostingWindowController`.
    var cocoaWindow: NSWindow? {
        get { self[HostingWindowKey.self]() }
        set { self[HostingWindowKey.self] = { [weak newValue] in newValue } }
    }
    
    var windowTitle: String {
        get { self[WindowTitleEnvironmentKey.self] }
        set {
            self[WindowTitleEnvironmentKey.self] = newValue
            cocoaWindow?.title = newValue
        }
    }

    var windowTitleVisibility: NSWindow.TitleVisibility {
        get { self[WindowTitleVisibilityEnvironmentKey.self] }
        set {
            self[WindowTitleVisibilityEnvironmentKey.self] = newValue
            cocoaWindow?.titleVisibility = newValue
        }
    }

    var windowTitleBarTransparent: Bool {
        get { self[WindowTitleBarTransparentEnvironmentKey.self] }
        set {
            self[WindowTitleBarTransparentEnvironmentKey.self] = newValue
            cocoaWindow?.titlebarAppearsTransparent = newValue
        }
    }
    
    var rendersWindowChrome: Bool {
        get { self[RendersWindowChromeEnvironmentKey.self] }
        set {
            self[RendersWindowChromeEnvironmentKey.self] = newValue
            windowChromeConsumer?.viewRendersWindowChrome = newValue
        }
    }
    
    var windowMovable: Bool {
        get { self[WindowMovableEnvironmentKey.self] }
        set {
            self[WindowMovableEnvironmentKey.self] = newValue
            cocoaWindow?.isMovable = newValue
            cocoaWindow?.isMovableByWindowBackground = newValue
        }
    }
    
    var windowLevel: NSWindow.Level {
        get { self[WindowLevelEnvironmentKey.self] }
        set {
            self[WindowLevelEnvironmentKey.self] = newValue
            cocoaWindow?.level = newValue
        }
    }
    
    var windowStyleMask: NSWindow.StyleMask {
        get { self[WindowStyleMaskEnvironmentKey.self] }
        set {
            self[WindowStyleMaskEnvironmentKey.self] = newValue
            guard let cocoaWindow = cocoaWindow else {
                return
            }

            var effectiveNewValue = newValue
            
            // Can't remove .fullScreen when the window is in full screen (causes crash).
            if cocoaWindow.styleMask.contains(.fullScreen) {
                effectiveNewValue.insert(.fullScreen)
            }
            
            // TODO: HACK!
            /// Setting styleMask without this dispatch results in a crash when
            /// built with the macOS 15 SDK and running under macOS 15.
            /// The crash is a precondition failure: `setting value during update: 360192`.
            DispatchQueue.main.async {
                cocoaWindow.styleMask = effectiveNewValue
            }
        }
    }
    
    var onWindowOcclusionStateChanged: ((NSWindow.OcclusionState) -> Void)? {
        get { self[WindowOnOcclusionStateChangedEnvironmentKey.self] }
        set {
            self[WindowOnOcclusionStateChangedEnvironmentKey.self] = newValue
            windowChromeConsumer?.onWindowOcclusionStateChanged = newValue
        }
    }

    var confirmBeforeClosingWindow: () async -> Bool {
        get { self[ConfirmBeforeClosingWindowEnvironmentKey.self] }
        set {
            self[ConfirmBeforeClosingWindowEnvironmentKey.self] = newValue
            windowChromeConsumer?.confirmBeforeClosingCallback = newValue
        }
    }
    
}

private struct OnWindowKeyChangedModifier: ViewModifier {

    var callback: (Bool) -> Void

    @Environment(\.cocoaWindow)
    private var window

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window)) { notification in
                guard notification.object as? NSWindow === window else { return }
                callback(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: window)) { notification in
                guard notification.object as? NSWindow === window else { return }
                callback(false)
            }
    }

}
