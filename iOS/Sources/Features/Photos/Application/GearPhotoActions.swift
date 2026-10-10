import Foundation

extension GearLibrary {
    func savePhoto(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).jpg"
        do {
            try GearPhotoFileStore().save(data, to: photoURL(for: name))
            return name
        } catch {
            alert = "照片保存失败：\(error.localizedDescription)"
            return nil
        }
    }
}
