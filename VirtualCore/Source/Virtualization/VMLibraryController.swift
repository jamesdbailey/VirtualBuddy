//
//  VMLibraryController.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 10/04/22.
//

import SwiftUI
import Combine
import OSLog

@MainActor
public final class VMLibraryController: ObservableObject {

    private let logger = Logger(for: VMLibraryController.self)

    public enum State {
        case loading
        case loaded([VBVirtualMachine])
        case failed(VBError)
    }
    
    @Published public private(set) var state = State.loading {
        didSet {
            if case .loaded(let vms) = state {
                self.virtualMachines = vms
            }
        }
    }
    
    @Published public private(set) var virtualMachines: [VBVirtualMachine] = []

    /// Identifiers for all VMs that are currently in a "booted" state (starting, booted, or paused).
    @Published public internal(set) var bootedMachineIdentifiers = Set<VBVirtualMachine.ID>()

    @available(*, deprecated, message: "It's not safe to use VMLibraryController as a singleton; for previews, use VMLibraryController.preview")
    public static let shared = VMLibraryController()

    let settingsContainer: VBSettingsContainer

    private let filePresenter: DirectoryObserver
    private let updateSignal = PassthroughSubject<URL, Never>()

    init(settingsContainer: VBSettingsContainer = .current) {
        self.settingsContainer = settingsContainer
        self.settings = settingsContainer.settings
        self.libraryURL = settingsContainer.settings.libraryURL
        self.filePresenter = DirectoryObserver(
            presentedItemURL: settingsContainer.settings.libraryURL,
            fileExtensions: [VBVirtualMachine.bundleExtension],
            label: "Library",
            signal: updateSignal
        )

        loadMachines()
        bind()
    }

    private var settings: VBSettings {
        didSet {
            self.libraryURL = settings.libraryURL
        }
    }

    @Published
    public private(set) var libraryURL: URL {
        didSet {
            guard oldValue != libraryURL else { return }
            loadMachines()
        }
    }

    private lazy var cancellables = Set<AnyCancellable>()
    
    private lazy var fileManager = FileManager()

    private func bind() {
        settingsContainer.$settings.sink { [weak self] newSettings in
            self?.settings = newSettings
        }
        .store(in: &cancellables)

        updateSignal
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.loadMachines()
            }
            .store(in: &cancellables)
    }

    public func loadMachines() {
        filePresenter.presentedItemURL = libraryURL

        guard let enumerator = fileManager.enumerator(at: libraryURL, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants], errorHandler: nil) else {
            state = .failed(.init("Failed to open directory at \(libraryURL.path)"))
            return
        }
        
        var vms = [VBVirtualMachine]()
        
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == VBVirtualMachine.bundleExtension else { continue }
            
            do {
                let machine = try VBVirtualMachine(bundleURL: url)
                
                vms.append(machine)
            } catch {
                assertionFailure("Failed to construct VM model: \(error)")
            }
        }

        vms.sort(by: { $0.bundleURL.creationDate > $1.bundleURL.creationDate })
        
        self.state = .loaded(vms)
    }

    public func reload(animated: Bool = true) {
        if animated {
            withAnimation(.spring()) {
                loadMachines()
            }
        } else {
            loadMachines()
        }
    }

    public func validateNewName(_ name: String, for vm: VBVirtualMachine) throws {
        try urlForRenaming(vm, to: name)
    }

    // MARK: - VM Controller References

    private final class Coordinator {
        private let lock = NSRecursiveLock()

        private var _activeVMControllers = [VBVirtualMachine.ID: WeakReference<VMController>]()

        /// References to all active `VMController` instances by VM identifier.
        /// May hold references to invalidated controllers because this does not hold a strong reference to them.
        var activeVMControllers: [VBVirtualMachine.ID: WeakReference<VMController>] {
            get { lock.withLock { _activeVMControllers } }
            set { lock.withLock { _activeVMControllers = newValue } }
        }

        func activeController(for virtualMachineID: VBVirtualMachine.ID) -> VMController? {
            activeVMControllers[virtualMachineID]?.object
        }

        /// Called when a new `VMController` is initialized so that we can reference it
        /// outside the scope of the view hierarchy (for automation).
        func addController(_ controller: VMController) {
            activeVMControllers[controller.id] = WeakReference(controller)
        }

        /// Called when a `VMController` is dying so that we can cleanup our reference to it.
        func removeController(_ controller: VMController) {
            activeVMControllers[controller.id] = nil
        }
    }

    private let coordinator = Coordinator()

    public nonisolated var activeVMControllers: [WeakReference<VMController>] { Array(coordinator.activeVMControllers.values) }

    public nonisolated func activeController(for virtualMachineID: VBVirtualMachine.ID) -> VMController? {
        coordinator.activeVMControllers[virtualMachineID]?.object
    }

    /// Called when a new `VMController` is initialized so that we can reference it
    /// outside the scope of the view hierarchy (for automation).
    nonisolated func addController(_ controller: VMController) {
        coordinator.activeVMControllers[controller.id] = WeakReference(controller)
    }

    /// Called when a `VMController` is dying so that we can cleanup our reference to it.
    nonisolated func removeController(_ controller: VMController) {
        coordinator.activeVMControllers[controller.id] = nil
    }

}

// MARK: - Queries

public extension VMLibraryController {
    func virtualMachines(matching predicate: (VBVirtualMachine) -> Bool) -> [VBVirtualMachine] {
        virtualMachines.filter(predicate)
    }

    func virtualMachine(named name: String) -> VBVirtualMachine? {
        virtualMachines(matching: { $0.name.caseInsensitiveCompare(name) == .orderedSame }).first
    }
}

// MARK: - Management Actions

public extension VMLibraryController {

    @discardableResult
    func duplicate(_ vm: VBVirtualMachine) throws -> VBVirtualMachine {
        let newName = "Copy of " + vm.name

        let copyURL = try urlForRenaming(vm, to: newName)

        try fileManager.copyItem(at: vm.bundleURL, to: copyURL)

        var newVM = try VBVirtualMachine(bundleURL: copyURL)

        newVM.bundleURL.creationDate = .now
        newVM.uuid = UUID()

        try newVM.saveMetadata()

        reload()

        return newVM
    }

    func moveToTrash(_ vm: VBVirtualMachine) async throws {
        try await NSWorkspace.shared.recycle([vm.bundleURL])

        reload()
    }

    func rename(_ vm: VBVirtualMachine, to newName: String) throws {
        let newURL = try urlForRenaming(vm, to: newName)

        try fileManager.moveItem(at: vm.bundleURL, to: newURL)

        reload(animated: false)
    }

    @discardableResult
    func urlForRenaming(_ vm: VBVirtualMachine, to name: String) throws -> URL {
        guard name.count >= 3 else {
            throw Failure("Name must be at least 3 characters long.")
        }

        let newURL = vm
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(name)
            .appendingPathExtension(VBVirtualMachine.bundleExtension)

        guard !fileManager.fileExists(atPath: newURL.path) else {
            throw Failure("Another virtual machine is already using this name, please choose another one.")
        }

        return newURL
    }
    
}

// MARK: - Download Helpers

public extension VMLibraryController {

    func getDownloadsBaseURL() throws -> URL {
        let baseURL = libraryURL.appendingPathComponent("_Downloads")
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }

        return baseURL
    }

    func existingLocalURL(for remoteURL: URL) throws -> URL? {
        let localURL = try getDownloadsBaseURL()

        let downloadedFileURL = localURL.appendingPathComponent(remoteURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: downloadedFileURL.path) {
            return downloadedFileURL
        } else {
            return nil
        }
    }

}

extension NSWorkspace: @unchecked Sendable { }
