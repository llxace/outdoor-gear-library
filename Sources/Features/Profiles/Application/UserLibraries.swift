import Foundation
import Combine

final class UserLibraries: ObservableObject {
    @Published private(set) var users: [LibraryUser] = []
    @Published private(set) var selectedID: UUID
    @Published private(set) var store: GearStore { didSet { observeStore() } }
    @Published private(set) var ready = false
    private var storeChanges: AnyCancellable?
    @Published var error: String?
    let root: URL
    private static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private var repository: UserCatalogRepository { UserCatalogRepository(root: root) }
    var currentUser: LibraryUser {
        users.first { $0.id == selectedID } ?? LibraryUser(id: Self.defaultID, name: "默认用户")
    }

    init(root directory: URL? = nil) {
        root = directory ?? LocalAssetFiles.libraryRoot
        selectedID = Self.defaultID
        store = GearStore(root: root)
        do {
            if repository.exists {
                let catalog = try repository.load()
                try restoreCatalog(catalog)
            } else {
                users = [LibraryUser(id: Self.defaultID, name: "默认用户")]
                try persist(users: users, selectedID: selectedID)
            }
            ready = true
        } catch {
            if users.isEmpty { users = [LibraryUser(id: Self.defaultID, name: "默认用户")] }
            self.error = "用户资料读取失败，已保留原文件：\(error.localizedDescription)"
        }
        observeStore()
    }
    private func restoreCatalog(_ catalog: UserCatalog) throws {
        guard Set(catalog.users.map(\.id)).count == catalog.users.count,
            catalog.users.contains(where: { $0.id == Self.defaultID }),
            catalog.users.contains(where: { $0.id == catalog.selectedID }),
            catalog.users.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw CocoaError(.fileReadCorruptFile) }
        users = catalog.users
        if catalog.selectedID != Self.defaultID {
            guard
                LocalAssetFiles.exists(
                    self.directory(for: catalog.selectedID).appendingPathComponent("inventory.json"))
            else { throw CocoaError(.fileNoSuchFile) }
            let restored = GearStore(root: self.directory(for: catalog.selectedID), seedInitialInventory: false)
            guard restored.ready else { throw CocoaError(.fileReadCorruptFile) }
            store = restored
        }
        selectedID = catalog.selectedID
    }
    private func observeStore() {
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    private func directory(for id: UUID) -> URL {
        id == Self.defaultID
            ? root
            : root.appendingPathComponent("Users", isDirectory: true).appendingPathComponent(
                id.uuidString, isDirectory: true)
    }
    private func persist(users: [LibraryUser], selectedID: UUID) throws {
        try repository.save(users: users, selectedID: selectedID)
    }
    func library(for id: UUID) -> GearStore? {
        guard ready, users.contains(where: { $0.id == id }) else { return nil }
        if id == selectedID { return store }
        guard LocalAssetFiles.exists(directory(for: id).appendingPathComponent("inventory.json")) else {
            error = "该用户的装备资料文件缺失，未切换或重建，请先恢复资料。"
            return nil
        }
        let next = GearStore(root: directory(for: id), seedInitialInventory: false)
        guard next.ready else {
            error = next.error
            return nil
        }
        return next
    }
    @discardableResult func select(_ id: UUID) -> Bool {
        guard ready else { return false }
        guard id != selectedID else { return true }
        guard let next = library(for: id) else { return false }
        do {
            try persist(users: users, selectedID: id)
            selectedID = id
            store = next
            return true
        } catch {
            self.error = "切换用户失败：\(error.localizedDescription)"
            return false
        }
    }
    @discardableResult func saveUser(
        name input: String, renaming: UUID? = nil, avatarURL: URL? = nil, removeAvatar: Bool = false
    ) -> Bool {
        guard ready else { return false }
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateName(name, renaming: renaming) else { return false }
        let id = renaming ?? UUID()
        var updated = users
        var nextStore: GearStore?
        let index: Int
        if renaming != nil {
            guard let existing = updated.firstIndex(where: { $0.id == id }) else { return false }
            index = existing
            updated[index].name = name
        } else {
            let next = GearStore(root: directory(for: id), seedInitialInventory: false)
            guard next.ready else {
                error = next.error
                return false
            }
            nextStore = next
            updated.append(LibraryUser(id: id, name: name))
            index = updated.count - 1
        }
        return saveProfile(updated, at: index, nextStore: nextStore, avatarURL: avatarURL, removeAvatar: removeAvatar)
    }
    private func validateName(_ name: String, renaming: UUID?) -> Bool {
        guard !name.isEmpty,
            !users.contains(where: {
                $0.id != renaming && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            })
        else {
            error = "用户名不能为空或重复。"
            return false
        }
        return true
    }
    private func saveProfile(
        _ profiles: [LibraryUser], at index: Int, nextStore: GearStore?, avatarURL: URL?, removeAvatar: Bool
    ) -> Bool {
        var updated = profiles
        let id = updated[index].id
        var copiedAvatar: URL?
        do {
            if let avatarURL {
                let destination = try repository.copyAvatar(avatarURL)
                copiedAvatar = destination
                updated[index].avatarFile = destination.lastPathComponent
            } else if removeAvatar {
                updated[index].avatarFile = nil
            }
            try persist(users: updated, selectedID: nextStore == nil ? selectedID : id)
            users = updated
            if let nextStore {
                selectedID = id
                store = nextStore
            }
            return true
        } catch {
            if let copiedAvatar { LocalAssetFiles.removeDrafts([copiedAvatar]) }
            self.error = "保存用户资料失败：\(error.localizedDescription)"
            return false
        }
    }
    func avatarURL(for user: LibraryUser) -> URL? {
        guard let file = user.avatarFile, !file.isEmpty, file != ".", file != "..",
            URL(fileURLWithPath: file).lastPathComponent == file
        else { return nil }
        return root.appendingPathComponent("Avatars", isDirectory: true).appendingPathComponent(file)
    }

}
