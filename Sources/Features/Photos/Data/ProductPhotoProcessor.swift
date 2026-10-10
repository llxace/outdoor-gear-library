import Foundation

enum ProductPhotoProcessor {
    static func process(source: URL, destination: URL, white: Bool, shadow: Bool) throws {
        let python = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".local/share/uv/tools/rembg/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path),
            let script = Bundle.main.url(forResource: "product_photo", withExtension: "py")
        else {
            throw NSError(domain: "ProductPhoto", code: 1, userInfo: [NSLocalizedDescriptionKey: "本地修图工具不可用，请检查修图环境。"])
        }
        let log = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        let worker = Process()
        worker.executableURL = python
        worker.arguments =
            [script.path, source.path, destination.path] + (white ? ["--white"] : []) + (shadow ? [] : ["--no-shadow"])
        worker.standardOutput = handle
        worker.standardError = handle
        try worker.run()
        worker.waitUntilExit()
        guard worker.terminationStatus == 0, FileManager.default.fileExists(atPath: destination.path) else {
            let diagnostic = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw NSError(
                domain: "ProductPhoto", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "照片处理失败，原图已保留。" + String(diagnostic.suffix(500))])
        }
    }
}
