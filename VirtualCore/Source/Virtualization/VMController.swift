//
//  VMController.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 07/04/22.
//

import Cocoa
import Foundation
import Virtualization
import Combine
import OSLog

public struct VMSessionOptions: Hashable, Codable {
    @DecodableDefault.False
    public var bootInRecoveryMode = false
    
    @DecodableDefault.False
    public var bootOnInstallDevice = false

    @DecodableDefault.False
    public var autoBoot = false

    public static let `default` = VMSessionOptions()
}

public enum VMState: Equatable {
    case idle
    case starting
    case running(VZVirtualMachine)
    case paused(VZVirtualMachine)
    case stopped(Error?)
}

@MainActor
public final class VMController: ObservableObject {

    public let id: VBVirtualMachine.ID

    private let library = VMLibraryController.shared

    private lazy var logger = Logger(for: Self.self)
    
    @Published
    public var options = VMSessionOptions.default {
        didSet {
            instance?.options = options
        }
    }
    
    public typealias State = VMState
    
    @Published
    public private(set) var state = State.idle
    
    private(set) var virtualMachine: VZVirtualMachine?

    @Published
    public var virtualMachineModel: VBVirtualMachine

    private lazy var cancellables = Set<AnyCancellable>()
    
    public init(with vm: VBVirtualMachine, options: VMSessionOptions? = nil) {
        self.id = vm.id
        self.virtualMachineModel = vm
        virtualMachineModel.reloadMetadata()
        if virtualMachineModel.metadata.installImageURL != nil && !virtualMachineModel.metadata.installFinished {
            self.options.bootOnInstallDevice = true
        }

        if let options {
            self.options = options
        }

        /// Ensure configuration is persisted whenever it changes.
        $virtualMachineModel
            .dropFirst()
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { updatedModel in
                do {
                    try updatedModel.saveMetadata()
                } catch {
                    assertionFailure("Failed to save configuration: \(error)")
                }
            }
            .store(in: &cancellables)

        library.addController(self)
    }

    private var instance: VMInstance?
    
    private func createInstance() throws -> VMInstance {
        let newInstance = VMInstance(with: virtualMachineModel, onVMStop: { [weak self] error in
            self?.state = .stopped(error)
        })
        
        newInstance.options = options
        
        return newInstance
    }

    public func start() async throws {
        state = .starting
        
        try await updatingState {
            let newInstance = try createInstance()
            self.instance = newInstance

            try await newInstance.startVM()
            let vm = try newInstance.virtualMachine

            state = .running(vm)
            virtualMachineModel.metadata.installFinished = true
        }
    }
    
    public func pause() async throws {
        try await updatingState {
            let instance = try ensureInstance()

            try await instance.pause()
            let vm = try instance.virtualMachine

            state = .paused(vm)
        }

        unhideCursor()
    }
    
    public func resume() async throws {
        try await updatingState {
            let instance = try ensureInstance()

            try await instance.resume()
            let vm = try instance.virtualMachine

            state = .running(vm)
        }

        unhideCursor()
    }
    
    public func stop() async throws {
        try await updatingState {
            let instance = try ensureInstance()

            try await instance.stop()

            state = .stopped(nil)
        }

        unhideCursor()
    }
    
    public func forceStop() async throws {
        try await updatingState {
            let instance = try ensureInstance()

            try await instance.forceStop()

            state = .stopped(nil)
        }

        unhideCursor()
    }

    private func updatingState(perform block: () async throws -> Void) async throws {
        do {
            try await block()
        } catch {
            state = .stopped(error)
            throw error
        }
    }

    private func ensureInstance() throws -> VMInstance {
        guard let instance = instance else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        
        instance.options = options
        
        return instance
    }

    public func storeScreenshot(with data: Data) {
        do {
            try virtualMachineModel.write(data, forMetadataFileNamed: VBVirtualMachine.screenshotFileName)
            try virtualMachineModel.invalidateThumbnail()
        } catch {
            logger.error("Error storing screenshot: \(error)")
        }
    }

    public func invalidate() {
        library.removeController(self)
    }

    deinit {
        #if DEBUG
        print("\(id) Bye bye 👋")
        #endif
        library.removeController(self)
    }

}

public extension VMState {

    static func ==(lhs: VMState, rhs: VMState) -> Bool {
        switch lhs {
        case .idle: return rhs.isIdle
        case .starting: return rhs.isStarting
        case .running: return rhs.isRunning
        case .paused: return rhs.isPaused
        case .stopped: return rhs.isStopped
        }
    }

    var isIdle: Bool {
        guard case .idle = self else { return false }
        return true
    }

    var isStarting: Bool {
        guard case .starting = self else { return false }
        return true
    }

    var isRunning: Bool {
        guard case .running = self else { return false }
        return true
    }

    var isPaused: Bool {
        guard case .paused = self else { return false }
        return true
    }

    var isStopped: Bool {
        guard case .stopped = self else { return false }
        return true
    }

    var canStart: Bool {
        switch self {
        case .idle, .stopped:
            return true
        default:
            return false
        }
    }

    var canResume: Bool {
        switch self {
        case .paused:
            return true
        default:
            return false
        }
    }

    var canPause: Bool {
        switch self {
        case .running:
            return true
        default:
            return false
        }
    }

}

public extension VMController {
    
    var canStart: Bool { state.canStart }

    var canResume: Bool { state.canResume }

    var canPause: Bool { state.canPause }

}

public extension VMController {
    /// Workaround for cursor disappearing due to it being captured
    /// by Virtualization during state transitions.
    func unhideCursor() {
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            NSCursor.unhide()
        }
    }
}
