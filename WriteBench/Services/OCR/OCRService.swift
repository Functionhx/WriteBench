import Foundation
import Vision
import ImageIO
import UniformTypeIdentifiers
import AppKit

struct OCRPage: Identifiable, Sendable {
    var id = UUID()
    var name: String
    var imageData: Data
    var text: String
    var warning: String?
}
enum OCRPurpose: String, CaseIterable, Identifiable {
    case question = "题目", essay = "手写作文", combined = "题目 + 作文"
    var id: String { rawValue }
}
struct OCRImport: Identifiable {
    let id = UUID()
    var pages: [OCRPage]
    var purpose: OCRPurpose
}
enum OCRError: LocalizedError {
    case invalidImage(String), tooLarge, tooManyPages
    var errorDescription: String? {
        switch self {
        case .invalidImage(let name): "无法读取图片 \(name)。请选择 PNG、JPEG、HEIC 或 TIFF 图片。"
        case .tooLarge: "图片总大小超过 80 MB，或单页超过 25 MB。请缩小图片后再导入。"
        case .tooManyPages: "一次最多导入 12 页图片。"
        }
    }
}
struct VisionOCRService: Sendable {
    func recognize(urls: [URL]) async throws -> [OCRPage] {
        guard urls.count <= 12 else { throw OCRError.tooManyPages }
        // Vision performs its synchronous recognition on a worker, never on the UI actor.
        let worker = Task.detached(priority: .userInitiated) {
            var pages: [OCRPage] = []
            var totalBytes = 0
            for url in urls {
                try Task.checkCancellation()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard fileSize <= 25 * 1_024 * 1_024 else { throw OCRError.tooLarge }
                let data = try Data(contentsOf: url)
                totalBytes += data.count
                guard totalBytes <= 80 * 1_024 * 1_024 else { throw OCRError.tooLarge }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3200] as CFDictionary) else { throw OCRError.invalidImage(url.lastPathComponent) }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US", "zh-Hans"]
                request.usesLanguageCorrection = false
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                try Task.checkCancellation()
                let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
                let text = candidates.map(\.string).joined(separator: "\n")
                let lowConfidence = candidates.isEmpty || candidates.contains { $0.confidence < 0.65 }
                pages.append(OCRPage(name: url.lastPathComponent, imageData: data, text: text, warning: text.isEmpty ? "本页没有识别出文字，请手动输入或使用更清晰的照片。" : lowConfidence ? "部分文字可信度较低，请逐行核对。" : nil))
            }
            return pages
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}

@MainActor enum ImageImporter {
    static func selectImages() async -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "导入题目或手写作文"
        panel.message = "支持多页。识别后请校对，确认前不会评分。"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "识别文字"
        return await panel.begin() == .OK ? panel.urls : []
    }
}
