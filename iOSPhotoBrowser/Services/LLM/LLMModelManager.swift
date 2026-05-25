//
//  LLMModelManager.swift
//  iOSPhotoBrowser
//

import Foundation
import Combine

/// LLMモデルのダウンロード・管理を行うマネージャー
@MainActor
final class LLMModelManager: ObservableObject {
    static let shared = LLMModelManager()

    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadError: Error?

    private var downloader: ModelDownloader?

    private init() {
        reconcileBackupExclusion()
    }

    // MARK: - Model Status

    /// モデルがダウンロード済みかどうか
    var isModelDownloaded: Bool {
        guard let path = modelPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// モデルファイルのパス
    var modelPath: String? {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDir.appendingPathComponent("Models/\(LlamaService.ModelInfo.fileName)").path
    }

    /// モデルファイルのサイズ（ダウンロード済みの場合）
    var downloadedModelSize: Int64? {
        guard let path = modelPath else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attributes[.size] as? Int64
    }

    /// 表示用のダウンロード済みモデルサイズ
    var displayDownloadedModelSize: String? {
        guard let size = downloadedModelSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Storage Check

    /// 十分なストレージ容量があるかチェック
    func hasEnoughStorage() -> Bool {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }

        do {
            let values = try documentsDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let availableCapacity = values.volumeAvailableCapacityForImportantUsage else {
                return false
            }
            // 必要容量 + 500MBの余裕を持たせる
            let requiredCapacity = LlamaService.ModelInfo.fileSize + 500_000_000
            return availableCapacity >= requiredCapacity
        } catch {
            return false
        }
    }

    // MARK: - Download

    /// モデルのダウンロードを開始
    func startDownload() async throws {
        guard !isDownloading else { return }
        guard !isModelDownloaded else { return }

        // ストレージ容量チェック
        guard hasEnoughStorage() else {
            throw LLMError.insufficientStorage
        }

        // モデルディレクトリを作成
        let modelsDir = try prepareModelsDirectory()

        guard let url = URL(string: LlamaService.ModelInfo.downloadURL) else {
            throw LLMError.downloadFailed("無効なダウンロードURL")
        }

        let destinationURL = modelsDir.appendingPathComponent(LlamaService.ModelInfo.fileName)

        isDownloading = true
        downloadProgress = 0.0
        downloadError = nil

        print("[LLMModelManager] Starting download from: \(url)")

        // ダウンローダーを作成
        let downloader = ModelDownloader()
        self.downloader = downloader

        do {
            try await downloader.download(
                from: url,
                to: destinationURL,
                expectedSize: LlamaService.ModelInfo.fileSize
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }
            print("[LLMModelManager] Download completed successfully")
        } catch {
            downloadError = error
            isDownloading = false
            self.downloader = nil
            throw error
        }

        isDownloading = false
        self.downloader = nil
    }

    /// ダウンロードをキャンセル
    func cancelDownload() {
        downloader?.cancel()
        downloader = nil
        isDownloading = false
        downloadProgress = 0.0
    }

    // MARK: - Delete

    /// モデルを削除
    func deleteModel() throws {
        guard let path = modelPath else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }

        try FileManager.default.removeItem(atPath: path)
        print("[LLMModelManager] Model deleted")
    }

    private func prepareModelsDirectory() throws -> URL {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw LLMError.downloadFailed("ドキュメントディレクトリにアクセスできません")
        }

        let modelsDir = documentsDir.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        BackupExclusionManager.excludeDirectoryContentsFromBackup(at: modelsDir)
        return modelsDir
    }

    private func reconcileBackupExclusion() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let modelsDir = documentsDir.appendingPathComponent("Models", isDirectory: true)
        guard FileManager.default.fileExists(atPath: modelsDir.path) else {
            return
        }

        BackupExclusionManager.excludeDirectoryContentsFromBackup(at: modelsDir)
    }
}

// MARK: - Model Downloader

/// URLSessionDelegateを使用したダウンローダー
private final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var downloadTask: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var destinationURL: URL?
    private var progressHandler: ((Double) -> Void)?
    private var expectedSize: Int64 = 0

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 // 1時間
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func download(
        from url: URL,
        to destination: URL,
        expectedSize: Int64,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        self.destinationURL = destination
        self.progressHandler = onProgress
        self.expectedSize = expectedSize

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.downloadTask = session.downloadTask(with: url)
            self.downloadTask?.resume()
            print("[ModelDownloader] Download task started")
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        continuation?.resume(throwing: LLMError.downloadFailed("キャンセルされました"))
        continuation = nil
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // サーバーがContent-Lengthを返さない場合、expectedSizeを使用
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let progress = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        progressHandler?(progress)
        print("[ModelDownloader] Progress: \(Int(progress * 100))% (\(totalBytesWritten)/\(total) bytes)")
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destinationURL = destinationURL else {
            continuation?.resume(throwing: LLMError.downloadFailed("保存先が設定されていません"))
            continuation = nil
            return
        }

        do {
            // 既存ファイルがあれば削除
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            // 一時ファイルを移動
            try FileManager.default.moveItem(at: location, to: destinationURL)
            BackupExclusionManager.excludeFromBackup(itemAt: destinationURL)
            print("[ModelDownloader] File saved to: \(destinationURL.path)")
            continuation?.resume()
        } catch {
            print("[ModelDownloader] Failed to save file: \(error)")
            continuation?.resume(throwing: LLMError.downloadFailed(error.localizedDescription))
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[ModelDownloader] Download failed: \(error)")
            continuation?.resume(throwing: LLMError.downloadFailed(error.localizedDescription))
            continuation = nil
        }
    }

    // リダイレクト処理
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        print("[ModelDownloader] Redirecting to: \(request.url?.absoluteString ?? "unknown")")
        completionHandler(request)
    }
}

// MARK: - User Defaults Keys

extension LLMModelManager {
    private enum UserDefaultsKeys {
        static let enginePreference = "llm_engine_preference"
    }

    /// ユーザーのLLMエンジン設定を取得
    var enginePreference: LLMEnginePreference {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: UserDefaultsKeys.enginePreference),
                  let preference = LLMEnginePreference(rawValue: rawValue) else {
                return .auto
            }
            return preference
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: UserDefaultsKeys.enginePreference)
        }
    }
}
