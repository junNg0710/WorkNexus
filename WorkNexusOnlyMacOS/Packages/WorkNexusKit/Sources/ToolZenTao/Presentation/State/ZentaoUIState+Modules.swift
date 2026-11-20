/// Not in the Flutter app.
import CoreDomain
import Foundation

/// Adding a module to the board on screen, and reading its module list again.
extension ZentaoUIState {
    /// Reads the module list of the board on screen again: a module made on ZenTao's site (or by someone else) shows
    /// without restarting the app. The list on screen stays until the new one is in.
    public func reloadModuleNames(bugs: Bool) {
        guard let (key, accountId, id) = moduleKey(bugs), !reloadingModules.contains(key) else { return }
        guard moduleNames[key]?.value != nil else { loadModuleNames(bugs: bugs); return }
        reloadingModules.insert(key)
        Task {
            let paths: Outcome<[FormOption]>
            if bugs { paths = await deps.editor.bugModules(accountId: accountId, productId: id) }
            else { paths = await deps.editor.taskOptions(accountId: accountId, executionId: id).map(\.modules) }
            reloadingModules.remove(key)
            // A failed reload keeps what was listed: it is only out of date.
            if case .success(let list) = paths { setModules(list, key: key) }
        }
    }

    /// Whether the module list of the board on screen is being read again.
    public func isReloadingModules(bugs: Bool) -> Bool {
        moduleKey(bugs).map { reloadingModules.contains($0.key) } ?? false
    }

    /// Why `name` cannot be a new module under `parentId` (nil: at the top) of the board on screen, or nil.
    public func moduleNameProblem(_ name: String, parentId: String?, bugs: Bool) -> ZenTaoModuleNameProblem? {
        let paths = boardModuleNames(bugs: bugs).value ?? []
        return CheckZenTaoModuleName()(name, parentPath: paths.first { $0.id == parentId }?.path, paths: paths.map(\.path))
    }

    /// Adds module `name` under `parentId` (nil: at the top) to the product (bugs) or execution (tasks) on screen. The
    /// tree then lists it; nil, or why ZenTao did not take it.
    public func addModule(_ name: String, parentId: String?, bugs: Bool) async -> Failure? {
        guard let (key, accountId, id) = moduleKey(bugs) else { return .validation("No product or execution is open") }
        let paths = boardModuleNames(bugs: bugs).value ?? []
        let parent = paths.first { $0.id == parentId }.map { (id: $0.id, path: $0.path) }
        switch await AddZenTaoModule(deps.moduleEditor)(accountId: accountId, rootId: id, bugs: bugs, name: name, parent: parent,
                                                        paths: paths.map(\.path)) {
        case .success(let list):
            setModules(list, key: key)
            // A new module holds nothing yet: with the empty ones hidden it would not show, as if it had not been made.
            hideEmptyModules = false
            return nil
        case .failure(let f):
            return f
        }
    }

    private func setModules(_ list: [FormOption], key: String) {
        moduleNames[key] = .loaded(list.map { ZentaoModulePath(id: $0.value, path: Self.stripLeadingSlash($0.label)) })
    }
}
