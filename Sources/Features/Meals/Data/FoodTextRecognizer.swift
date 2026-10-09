import Foundation
import Vision

enum FoodTextRecognizer {
    static func recognize(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else {
                throw NSError(domain: "FoodOCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有识别到文字，请拍清晰的包装营养表。"])
            }
            return text
        }.value
    }
}
