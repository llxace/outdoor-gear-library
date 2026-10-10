import SwiftUI
import UniformTypeIdentifiers
import UIKit

final class PadFileDialog {
    struct Request {
        let types: [UTType]
        let multiple: Bool
        let completion: (Result<[URL], Error>) -> Void
    }
    static var pending: Request?
    static let notification = Notification.Name("PadFileDialog.request")

    static func pick(_ types: [UTType], multiple: Bool = false, completion: @escaping (Result<[URL], Error>) -> Void) {
        DispatchQueue.main.async {
            pending = Request(types: types, multiple: multiple, completion: completion)
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }
    static func share(_ url: URL) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("PadFileDialog.share"), object: url) }
    }
    static func confirm(_ title: String, _ message: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
            alert.addAction(UIAlertAction(title: "确认", style: .destructive) { _ in completion(true) })
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { completion(false); return }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(alert, animated: true)
        }
    }
}

struct PadFileDialogHost: ViewModifier {
    @State private var importing = false
    @State private var types: [UTType] = [.item]
    @State private var multiple = false
    @State private var sharing: URL?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: PadFileDialog.notification)) { _ in
                guard let request = PadFileDialog.pending else { return }
                types = request.types
                multiple = request.multiple
                importing = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PadFileDialog.share"))) { event in
                sharing = event.object as? URL
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: types, allowsMultipleSelection: multiple) { result in
                let request = PadFileDialog.pending
                PadFileDialog.pending = nil
                guard let request else { return }
                switch result {
                case .success(let urls):
                    do { request.completion(.success(try urls.map(snapshot))) }
                    catch { request.completion(.failure(error)) }
                case .failure(let error): request.completion(.failure(error))
                }
            }
            .sheet(item: Binding(get: { sharing.map(ShareItem.init) }, set: { sharing = $0?.url })) { item in
                ActivityShareSheet(url: item.url)
            }
    }
    private func snapshot(_ source: URL) throws -> URL {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("PadFileDialog", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let suffix = isDirectory || source.pathExtension.isEmpty ? "" : "." + source.pathExtension
        let destination = directory.appendingPathComponent(UUID().uuidString + suffix, isDirectory: isDirectory)
        try manager.copyItem(at: source, to: destination)
        return destination
    }

}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
    init(_ url: URL) { self.url = url }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    func padFileDialogHost() -> some View { modifier(PadFileDialogHost()) }
}
