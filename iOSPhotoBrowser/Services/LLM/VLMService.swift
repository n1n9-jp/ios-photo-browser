//
//  VLMService.swift
//  iOSPhotoBrowser
//
//  Vision Language Model を使用した画像からの書籍情報抽出
//  MiniCPM-V 4.0 + llama.cpp による実装
//

import Combine
import Foundation
import UIKit

/// Vision Language Model サービス
/// 画像から直接書籍情報を抽出（OCR不要）
actor VLMService: VLMServiceProtocol {
    nonisolated let serviceName = "Vision LLM (MiniCPM-V)"

    private var wrapper: MTMDWrapper?
    private var isModelLoaded = false

    init() {}

    /// VLMが利用可能かどうか（モデルがダウンロード済みか）
    nonisolated var isAvailable: Bool {
        get async {
            await MainActor.run {
                VLMModelManager.shared.isModelDownloaded
            }
        }
    }

    /// モデルをメモリに読み込む
    func loadModel() async throws {
        let isDownloaded = await MainActor.run {
            VLMModelManager.shared.isModelDownloaded
        }
        guard isDownloaded else {
            throw LLMError.modelNotLoaded
        }

        guard !isModelLoaded else { return }

        let modelPath = await MainActor.run {
            VLMModelManager.shared.modelPath
        }
        let mmprojPath = await MainActor.run {
            VLMModelManager.shared.mmprojPath
        }

        guard let modelPath = modelPath, let mmprojPath = mmprojPath else {
            throw LLMError.modelNotLoaded
        }

        // MTMDWrapper を初期化
        let newWrapper = await MTMDWrapper()

        let params = MTMDParams(
            modelPath: modelPath,
            mmprojPath: mmprojPath,
            nPredict: 512,  // 書籍情報抽出には十分
            nCtx: 4096,
            nThreads: 4,
            temperature: 0.3,  // 低めの温度で安定した出力
            useGPU: true,
            mmprojUseGPU: true,
            warmup: true
        )

        do {
            try await newWrapper.initialize(with: params)
            wrapper = newWrapper
            isModelLoaded = true
            print("[VLMService] Model loaded successfully")
        } catch {
            print("[VLMService] Failed to load model: \(error)")
            throw LLMError.modelNotLoaded
        }
    }

    /// モデルをメモリから解放
    func unloadModel() async {
        if let wrapper = wrapper {
            await wrapper.cleanup()
        }
        wrapper = nil
        isModelLoaded = false
        print("[VLMService] Model unloaded")
    }

    /// 画像から書籍情報を抽出
    func extractBookInfo(from image: UIImage) async throws -> ExtractedBookData {
        if !isModelLoaded {
            try await loadModel()
        }

        guard let wrapper = wrapper else {
            throw LLMError.modelNotLoaded
        }

        print("[VLMService] Starting extraction...")
        let response = try await generateResponse(for: image, prompt: makeVLMBookExtractionPrompt(), using: wrapper)
        print("[VLMService] Response: \(response.prefix(500))")
        return parseBookInfoResponse(response)
    }

    /// 人物写真を分類してタグ候補を返す
    func classifyPersonPhoto(from image: UIImage) async throws -> PersonPhotoClassification {
        if !isModelLoaded {
            try await loadModel()
        }

        guard let wrapper = wrapper else {
            throw LLMError.modelNotLoaded
        }

        print("[VLMService] Starting person photo classification...")
        let response = try await generateResponse(
            for: image,
            prompt: makePersonPhotoClassificationPrompt(),
            using: wrapper
        )
        print("[VLMService] Person photo classification response: \(response.prefix(500))")
        return parsePersonPhotoClassification(response)
    }

    // MARK: - Private Helpers

    private func generateResponse(
        for image: UIImage,
        prompt: String,
        using wrapper: MTMDWrapper
    ) async throws -> String {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw LLMError.extractionFailed("画像データの変換に失敗しました")
        }

        do {
            try imageData.write(to: tempURL)
        } catch {
            throw LLMError.extractionFailed("一時ファイルの作成に失敗しました: \(error.localizedDescription)")
        }

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            try await wrapper.addImageInBackground(tempURL.path)
            try await wrapper.addTextInBackground(prompt, role: "user")
            try await wrapper.startGeneration()

            let maxWaitTime: TimeInterval = 60
            let startTime = Date()

            while Date().timeIntervalSince(startTime) < maxWaitTime {
                let state = await wrapper.generationState
                let output = await wrapper.fullOutput

                if state == .completed {
                    if output.isEmpty {
                        throw LLMError.extractionFailed("タイムアウト：応答がありませんでした")
                    }
                    await wrapper.reset()
                    return output
                } else if case .failed(let error) = state {
                    throw LLMError.extractionFailed(error.localizedDescription)
                }

                try await Task.sleep(nanoseconds: 100_000_000)
            }

            throw LLMError.extractionFailed("タイムアウト：応答がありませんでした")
        } catch let error as MTMDError {
            await wrapper.reset()
            throw LLMError.extractionFailed(error.localizedDescription)
        } catch let error as LLMError {
            await wrapper.reset()
            throw error
        } catch {
            await wrapper.reset()
            throw LLMError.extractionFailed(error.localizedDescription)
        }
    }

    private func extractJSONString(from response: String) -> String? {
        var jsonString = response

        // マークダウンコードブロックを除去
        if let startRange = response.range(of: "```json"),
           let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        } else if let startRange = response.range(of: "```"),
                  let endRange = response.range(of: "```", range: startRange.upperBound..<response.endIndex) {
            jsonString = String(response[startRange.upperBound..<endRange.lowerBound])
        }

        // 最初の { から最後の } までを抽出
        if let startIndex = jsonString.firstIndex(of: "{"),
           let endIndex = jsonString.lastIndex(of: "}") {
            jsonString = String(jsonString[startIndex...endIndex])
        }

        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseBookInfoResponse(_ response: String) -> ExtractedBookData {
        guard let jsonString = extractJSONString(from: response) else {
            return ExtractedBookData(confidence: 0.1)
        }

        // JSONをパース
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[VLMService] Failed to parse JSON: \(jsonString.prefix(100))")
            return ExtractedBookData(confidence: 0.1)
        }

        let title = json["title"] as? String
        let author = json["author"] as? String
        let publisher = json["publisher"] as? String
        var isbn = json["isbn"] as? String

        // ISBNのクリーニング
        if let rawISBN = isbn {
            isbn = rawISBN.filter { $0.isNumber }
            if isbn?.count != 13 {
                isbn = nil
            }
        }

        // 信頼度スコアを計算
        var confidence = 0.0
        var fields = 0
        if title != nil && !title!.isEmpty { fields += 1 }
        if author != nil && !author!.isEmpty { fields += 1 }
        if publisher != nil && !publisher!.isEmpty { fields += 1 }
        if isbn != nil { fields += 2 }
        confidence = Double(fields) / 5.0

        // VLMは画像から直接認識するため、信頼度にボーナス
        confidence = min(1.0, confidence + 0.2)

        return ExtractedBookData(
            title: title,
            author: author,
            publisher: publisher,
            isbn: isbn,
            confidence: confidence
        )
    }

    private func parsePersonPhotoClassification(_ response: String) -> PersonPhotoClassification {
        guard let jsonString = extractJSONString(from: response) else {
            return PersonPhotoClassification()
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[VLMService] Failed to parse person classification JSON: \(jsonString.prefix(100))")
            return PersonPhotoClassification()
        }

        let peopleCount = (json["people_count"] as? String).flatMap(PersonPhotoClassification.PeopleCount.init(rawValue:))
        let framing = (json["framing"] as? String).flatMap(PersonPhotoClassification.Framing.init(rawValue:))
        let scene = (json["scene"] as? String).flatMap(PersonPhotoClassification.Scene.init(rawValue:))
        let isSelfie = json["is_selfie"] as? Bool
        let isGroupPhoto = json["is_group_photo"] as? Bool
        let confidence = json["confidence"] as? Double ?? 0.0

        return PersonPhotoClassification(
            peopleCount: peopleCount,
            framing: framing,
            scene: scene,
            isSelfie: isSelfie,
            isGroupPhoto: isGroupPhoto,
            confidence: confidence
        )
    }
}

// MARK: - VLM Prompt

/// VLM用の書籍情報抽出プロンプト
private func makeVLMBookExtractionPrompt() -> String {
    """
    この画像は本の表紙です。書籍情報を抽出してJSON形式で出力してください。

    出力形式（JSONのみ、説明不要）:
    {"title": "書籍タイトル", "author": "著者名", "publisher": "出版社名", "isbn": "ISBN13桁"}

    注意:
    - 見つからない項目はnull
    - タイトルと著者名を正確に読み取ってください
    - 日本語の場合は日本語で出力
    """
}

private func makePersonPhotoClassificationPrompt() -> String {
    """
    この画像を人物写真として分類し、JSONのみを出力してください。

    出力形式:
    {
      "people_count": "one" | "two" | "three_or_more" | null,
      "framing": "face_closeup" | "upper_body" | "full_body" | "mixed" | null,
      "scene": "indoor" | "outdoor" | null,
      "is_selfie": true | false | null,
      "is_group_photo": true | false | null,
      "confidence": 0.0
    }

    ルール:
    - 許可された値以外は出力しない
    - 人物がはっきり写っていない場合は null を使う
    - people_count は人物が主題として見える人数で判定する
    - framing は最も代表的な構図を1つ選ぶ
    - is_group_photo は記念撮影や集合写真らしい場合のみ true
    - confidence は 0.0 から 1.0 の数値
    - JSON以外の説明は不要
    """
}

// MARK: - VLM Model Manager

/// VLMモデルのダウンロード・管理を行うマネージャー
@MainActor
final class VLMModelManager: ObservableObject {
    static let shared = VLMModelManager()

    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadError: Error?

    private init() {
        reconcileBackupExclusion()
    }

    // MARK: - Model Information

    struct ModelInfo {
        // MiniCPM-V 4.0
        static let name = "MiniCPM-V 4.0"
        static let modelFileName = "ggml-model-Q4_0.gguf"
        static let mmprojFileName = "mmproj-model-f16.gguf"
        static let modelFileSize: Int64 = 2_080_000_000  // 約2.08GB
        static let mmprojFileSize: Int64 = 959_000_000   // 約959MB

        // ダウンロードURL（HuggingFace LFS）
        static let modelDownloadURL = "https://huggingface.co/openbmb/MiniCPM-V-4-gguf/resolve/main/ggml-model-Q4_0.gguf?download=true"
        static let mmprojDownloadURL = "https://huggingface.co/openbmb/MiniCPM-V-4-gguf/resolve/main/mmproj-model-f16.gguf?download=true"

        static var totalFileSize: Int64 {
            modelFileSize + mmprojFileSize
        }

        static var displayFileSize: String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: totalFileSize)
        }
    }

    // MARK: - Model Status

    var isModelDownloaded: Bool {
        guard let modelPath = modelPath, let mmprojPath = mmprojPath else { return false }
        return FileManager.default.fileExists(atPath: modelPath) &&
               FileManager.default.fileExists(atPath: mmprojPath)
    }

    var modelPath: String? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent("VLMModels/\(ModelInfo.modelFileName)").path
    }

    var mmprojPath: String? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent("VLMModels/\(ModelInfo.mmprojFileName)").path
    }

    // MARK: - Download

    @Published private(set) var currentDownloadFile: String = ""
    private var downloadTask: Task<Void, Error>?

    func startDownload() async throws {
        guard !isDownloading else { return }
        guard !isModelDownloaded else { return }

        // モデルディレクトリを作成
        let modelsDir = try prepareModelsDirectory()

        isDownloading = true
        downloadProgress = 0.0
        downloadError = nil

        do {
            // 1. まずビジョンモデル（小さい方）をダウンロード
            if !hasVisionProjector {
                currentDownloadFile = "mmproj-model-f16.gguf"
                let mmprojDestURL = modelsDir.appendingPathComponent(ModelInfo.mmprojFileName)
                try await downloadFile(
                    from: URL(string: ModelInfo.mmprojDownloadURL)!,
                    to: mmprojDestURL,
                    expectedSize: ModelInfo.mmprojFileSize,
                    progressOffset: 0.0,
                    progressScale: 0.3  // 全体の30%
                )
            }

            // 2. 次に言語モデル（大きい方）をダウンロード
            if !hasLanguageModel {
                currentDownloadFile = "ggml-model-Q4_0.gguf"
                let modelDestURL = modelsDir.appendingPathComponent(ModelInfo.modelFileName)
                try await downloadFile(
                    from: URL(string: ModelInfo.modelDownloadURL)!,
                    to: modelDestURL,
                    expectedSize: ModelInfo.modelFileSize,
                    progressOffset: 0.3,
                    progressScale: 0.7  // 全体の70%
                )
            }

            isDownloading = false
            downloadProgress = 1.0
            currentDownloadFile = ""
            print("[VLMModelManager] All models downloaded successfully")
        } catch {
            isDownloading = false
            currentDownloadFile = ""
            downloadError = error
            throw error
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        currentDownloadFile = ""
        print("[VLMModelManager] Download cancelled")
    }

    private func downloadFile(
        from url: URL,
        to destination: URL,
        expectedSize: Int64,
        progressOffset: Double,
        progressScale: Double
    ) async throws {
        print("[VLMModelManager] Downloading: \(url)")

        // 既存ファイルを削除
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        // URLSessionDownloadTask + Delegate を使用（高速・効率的）
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 7200  // 2時間

            let delegate = VLMDownloadDelegate(
                expectedSize: expectedSize,
                progressOffset: progressOffset,
                progressScale: progressScale,
                destination: destination,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                },
                onComplete: { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )

            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

            let task = session.downloadTask(with: request)
            task.resume()
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        print("[VLMModelManager] Downloaded: \(destination.lastPathComponent) (\(fileSize) bytes)")
    }

    func deleteModel() throws {
        if let path = modelPath, FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        if let path = mmprojPath, FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        print("[VLMModelManager] Models deleted")
    }

    // MARK: - Import from File

    /// ファイルURLからモデルをインポート
    func importModel(from sourceURL: URL) throws -> ImportResult {
        let fileName = sourceURL.lastPathComponent

        // モデルディレクトリを作成
        let modelsDir = try prepareModelsDirectory()

        // ファイル名に基づいてコピー先を決定
        var importType: ImportResult.ImportType = .unknown

        if fileName.contains("ggml-model") || fileName.contains("Q4") || fileName.contains("Q8") {
            // 言語モデル
            let destURL = modelsDir.appendingPathComponent(ModelInfo.modelFileName)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            BackupExclusionManager.excludeFromBackup(itemAt: destURL)
            importType = .languageModel
            print("[VLMModelManager] Language model imported: \(destURL.path)")
        } else if fileName.contains("mmproj") {
            // Vision projector
            let destURL = modelsDir.appendingPathComponent(ModelInfo.mmprojFileName)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            BackupExclusionManager.excludeFromBackup(itemAt: destURL)
            importType = .visionProjector
            print("[VLMModelManager] MMProj imported: \(destURL.path)")
        } else {
            throw LLMError.downloadFailed("不明なファイル形式です。ファイル名に 'ggml-model' または 'mmproj' が含まれている必要があります。")
        }

        return ImportResult(type: importType, isComplete: isModelDownloaded)
    }

    struct ImportResult {
        enum ImportType {
            case languageModel
            case visionProjector
            case unknown
        }
        let type: ImportType
        let isComplete: Bool

        var message: String {
            switch type {
            case .languageModel:
                if isComplete {
                    return "言語モデルをインポートしました。VLMの準備が完了しました。"
                } else {
                    return "言語モデルをインポートしました。ビジョンモデル (mmproj) もインポートしてください。"
                }
            case .visionProjector:
                if isComplete {
                    return "ビジョンモデルをインポートしました。VLMの準備が完了しました。"
                } else {
                    return "ビジョンモデルをインポートしました。言語モデル (ggml-model) もインポートしてください。"
                }
            case .unknown:
                return "ファイルをインポートしました。"
            }
        }
    }

    /// 個別のモデルファイルの存在確認
    var hasLanguageModel: Bool {
        guard let path = modelPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var hasVisionProjector: Bool {
        guard let path = mmprojPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private func prepareModelsDirectory() throws -> URL {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LLMError.downloadFailed("ドキュメントディレクトリにアクセスできません")
        }

        let modelsDir = documentsDir.appendingPathComponent("VLMModels", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        BackupExclusionManager.excludeDirectoryContentsFromBackup(at: modelsDir)
        return modelsDir
    }

    private func reconcileBackupExclusion() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let modelsDir = documentsDir.appendingPathComponent("VLMModels", isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelsDir.path) else {
            return
        }

        BackupExclusionManager.excludeDirectoryContentsFromBackup(at: modelsDir)
    }
}

// MARK: - VLM Download Delegate

private class VLMDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let expectedSize: Int64
    let progressOffset: Double
    let progressScale: Double
    let destination: URL
    let onProgress: (Double) -> Void
    let onComplete: (Error?) -> Void

    init(
        expectedSize: Int64,
        progressOffset: Double,
        progressScale: Double,
        destination: URL,
        onProgress: @escaping (Double) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        self.expectedSize = expectedSize
        self.progressOffset = progressOffset
        self.progressScale = progressScale
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let fileProgress = Double(totalBytesWritten) / Double(total)
        let overallProgress = progressOffset + (fileProgress * progressScale)
        onProgress(overallProgress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            // 既存ファイルを削除
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            // 一時ファイルを目的地に移動
            try FileManager.default.moveItem(at: location, to: destination)
            BackupExclusionManager.excludeFromBackup(itemAt: destination)
            onComplete(nil)
        } catch {
            onComplete(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onComplete(error)
        }
    }
}
