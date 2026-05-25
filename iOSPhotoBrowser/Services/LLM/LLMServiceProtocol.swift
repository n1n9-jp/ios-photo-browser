//
//  LLMServiceProtocol.swift
//  iOSPhotoBrowser
//

import Foundation

// MARK: - Extracted Data Model

/// LLMが抽出した書籍情報
struct ExtractedBookData: Sendable {
    var title: String?
    var author: String?
    var publisher: String?
    var isbn: String?
    var confidence: Double  // 0.0-1.0 の信頼度スコア

    init(
        title: String? = nil,
        author: String? = nil,
        publisher: String? = nil,
        isbn: String? = nil,
        confidence: Double = 0.0
    ) {
        self.title = title
        self.author = author
        self.publisher = publisher
        self.isbn = isbn
        self.confidence = confidence
    }

    /// 有効なデータが含まれているかどうか
    var hasValidData: Bool {
        title != nil || author != nil || isbn != nil
    }

    /// ISBNが有効な形式かチェック
    var hasValidISBN: Bool {
        guard let isbn = isbn else { return false }
        let cleanISBN = isbn.filter { $0.isNumber }
        return cleanISBN.count == 13 && (cleanISBN.hasPrefix("978") || cleanISBN.hasPrefix("979"))
    }
}

// MARK: - Person Photo Classification Model

struct PersonPhotoClassification: Sendable {
    enum PeopleCount: String, Sendable {
        case one
        case two
        case threeOrMore = "three_or_more"

        var tagName: String {
            switch self {
            case .one: return "1人"
            case .two: return "2人"
            case .threeOrMore: return "3人以上"
            }
        }
    }

    enum Framing: String, Sendable {
        case faceCloseup = "face_closeup"
        case upperBody = "upper_body"
        case fullBody = "full_body"
        case mixed

        var tagName: String {
            switch self {
            case .faceCloseup: return "顔アップ"
            case .upperBody: return "上半身"
            case .fullBody: return "全身"
            case .mixed: return "複数構図"
            }
        }
    }

    enum Scene: String, Sendable {
        case indoor
        case outdoor

        var tagName: String {
            switch self {
            case .indoor: return "屋内"
            case .outdoor: return "屋外"
            }
        }
    }

    var peopleCount: PeopleCount?
    var framing: Framing?
    var scene: Scene?
    var isSelfie: Bool?
    var isGroupPhoto: Bool?
    var confidence: Double

    init(
        peopleCount: PeopleCount? = nil,
        framing: Framing? = nil,
        scene: Scene? = nil,
        isSelfie: Bool? = nil,
        isGroupPhoto: Bool? = nil,
        confidence: Double = 0.0
    ) {
        self.peopleCount = peopleCount
        self.framing = framing
        self.scene = scene
        self.isSelfie = isSelfie
        self.isGroupPhoto = isGroupPhoto
        self.confidence = confidence
    }

    var hasValidData: Bool {
        peopleCount != nil || framing != nil || scene != nil || isSelfie == true || isGroupPhoto == true
    }

    var suggestedTags: [String] {
        var tags: [String] = []

        if let peopleCount {
            tags.append(peopleCount.tagName)
        }
        if let framing {
            tags.append(framing.tagName)
        }
        if let scene {
            tags.append(scene.tagName)
        }
        if isSelfie == true {
            tags.append("自撮り")
        }
        if isGroupPhoto == true {
            tags.append("集合写真")
        }

        return Array(NSOrderedSet(array: tags)) as? [String] ?? tags
    }
}

// MARK: - LLM Service Protocol

/// LLMサービスのプロトコル
/// 各LLM実装（Apple Foundation Models、llama.cpp）はこのプロトコルに準拠する
protocol LLMServiceProtocol {
    /// OCRテキストから書籍情報を抽出
    func extractBookInfo(from ocrText: String) async throws -> ExtractedBookData

    /// サービスが利用可能かどうか
    var isAvailable: Bool { get async }

    /// サービス名（デバッグ・表示用）
    var serviceName: String { get }
}

// MARK: - VLM Service Protocol

import UIKit

/// Vision Language Model サービスのプロトコル
/// 画像から直接書籍情報を抽出（OCR不要）
protocol VLMServiceProtocol {
    /// 画像から書籍情報を抽出
    func extractBookInfo(from image: UIImage) async throws -> ExtractedBookData

    /// 人物写真を分類してタグ候補を返す
    func classifyPersonPhoto(from image: UIImage) async throws -> PersonPhotoClassification

    /// サービスが利用可能かどうか
    var isAvailable: Bool { get async }

    /// サービス名（デバッグ・表示用）
    var serviceName: String { get }

    /// モデルをメモリに読み込む
    func loadModel() async throws

    /// モデルをメモリから解放
    func unloadModel() async
}

// MARK: - LLM Errors

enum LLMError: Error, LocalizedError {
    case notAvailable
    case modelNotLoaded
    case extractionFailed(String)
    case invalidResponse
    case downloadFailed(String)
    case insufficientStorage

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "LLMサービスが利用できません"
        case .modelNotLoaded:
            return "モデルが読み込まれていません"
        case .extractionFailed(let reason):
            return "書籍情報の抽出に失敗しました: \(reason)"
        case .invalidResponse:
            return "無効なレスポンスです"
        case .downloadFailed(let reason):
            return "モデルのダウンロードに失敗しました: \(reason)"
        case .insufficientStorage:
            return "ストレージ容量が不足しています"
        }
    }
}

// MARK: - LLM Configuration

/// LLMサービスの設定
enum LLMEnginePreference: String, CaseIterable {
    case auto = "auto"
    case appleIntelligence = "apple"
    case localModel = "local"
    case none = "none"

    var displayName: String {
        switch self {
        case .auto: return "自動（推奨）"
        case .appleIntelligence: return "Apple Intelligence"
        case .localModel: return "ローカルモデル"
        case .none: return "使用しない"
        }
    }

    var description: String {
        switch self {
        case .auto: return "利用可能な最適なエンジンを自動選択"
        case .appleIntelligence: return "iOS 26以降で利用可能"
        case .localModel: return "オフライン対応、約2GBのダウンロードが必要"
        case .none: return "LLMを使用せず、OCRテキストのみを使用"
        }
    }
}

// MARK: - Prompt Templates

/// 書籍情報抽出用のプロンプトを生成
func makeBookExtractionPrompt(ocrText: String) -> String {
    """
    以下は本の表紙や奥付からOCRで読み取ったテキストです。
    書籍情報を抽出してJSON形式で出力してください。

    OCRテキスト:
    \(ocrText)

    出力形式（JSONのみ、説明不要）:
    {
      "title": "書籍タイトル",
      "author": "著者名",
      "publisher": "出版社名",
      "isbn": "ISBN-13（13桁の数字のみ）"
    }

    注意:
    - ISBNは数字のみ13桁（978または979で始まる）
    - 見つからない項目はnull
    - OCRの誤認識（0とO、1とIやl）を考慮して推測
    - タイトルや著者名の明らかな誤字は修正
    """
}
