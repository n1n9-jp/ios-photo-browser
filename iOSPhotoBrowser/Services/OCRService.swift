//
//  OCRService.swift
//  iOSPhotoBrowser
//

import Foundation
import Vision
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

actor OCRService {
    static let shared = OCRService()

    // 書籍ドメインのカスタム語彙（OCR精度向上用）
    private let bookDomainWords: [String] = [
        // ISBN関連
        "ISBN", "ISBN-13", "ISBN-10",
        // 書籍用語
        "著者", "著", "編著", "監修", "訳", "翻訳",
        "出版社", "出版", "発行", "発行所", "発売",
        "初版", "第1版", "第2版", "改訂版", "増補版",
        "新書", "文庫", "単行本", "選書", "叢書",
        // 出版社名（主要なもの）
        "岩波書店", "講談社", "新潮社", "角川書店", "集英社",
        "文藝春秋", "中央公論新社", "筑摩書房", "河出書房新社",
        "早川書房", "東京創元社", "光文社", "PHP研究所",
        "ダイヤモンド社", "日経BP", "東洋経済新報社",
        "オライリー", "技術評論社", "翔泳社", "インプレス",
        // 価格・日付
        "定価", "本体", "円", "税別", "税込",
        "年", "月", "日", "発行日", "印刷"
    ]

    private init() {}

    func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            request.customWords = self.bookDomainWords

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func extractISBN(from text: String) -> String? {
        // ISBN-13: 978 or 979 followed by 10 digits (with optional hyphens/spaces)
        // Pattern matches: 978-4-12-345678-9, 9784123456789, 978 4 12 345678 9, etc.
        let patterns = [
            // ISBN-13 with various separators
            "97[89][-\\s]?\\d[-\\s]?\\d{2,5}[-\\s]?\\d{2,7}[-\\s]?\\d",
            // ISBN-13 without separators (13 consecutive digits starting with 978 or 979)
            "97[89]\\d{10}"
        ]

        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let matched = String(text[range])
                // Remove all non-digit characters to get clean ISBN
                let cleanISBN = matched.filter { $0.isNumber }
                if cleanISBN.count == 13 {
                    return cleanISBN
                }
            }
        }

        // Also try to find ISBN-10 and convert to ISBN-13
        let isbn10Pattern = "\\d[-\\s]?\\d{2,5}[-\\s]?\\d{2,7}[-\\s]?[\\dX]"
        if let range = text.range(of: isbn10Pattern, options: .regularExpression) {
            let matched = String(text[range])
            let cleanISBN = matched.filter { $0.isNumber || $0 == "X" }
            if cleanISBN.count == 10 {
                if let isbn13 = convertISBN10to13(cleanISBN) {
                    return isbn13
                }
            }
        }

        return nil
    }

    private func convertISBN10to13(_ isbn10: String) -> String? {
        guard isbn10.count == 10 else { return nil }

        let prefix = "978"
        let isbn10Body = String(isbn10.prefix(9))
        let isbn13WithoutCheckDigit = prefix + isbn10Body

        // Calculate ISBN-13 check digit
        var sum = 0
        for (index, char) in isbn13WithoutCheckDigit.enumerated() {
            guard let digit = Int(String(char)) else { return nil }
            let multiplier = (index % 2 == 0) ? 1 : 3
            sum += digit * multiplier
        }

        let checkDigit = (10 - (sum % 10)) % 10
        return isbn13WithoutCheckDigit + String(checkDigit)
    }

    // MARK: - Apple Intelligence OCR補正

    /// Apple Intelligence を使用してOCRテキストを補正・正規化
    @available(iOS 26.0, *)
    private func correctOCRTextWithAI(_ rawText: String) async -> String {
        #if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()

            let prompt = """
            以下は本の表紙や奥付からOCRで読み取ったテキストです。
            OCRの誤認識を修正し、書籍情報として整形してください。

            特に注意する点：
            - ISBNの数字の誤り（0とO、1とI/lなど）を修正
            - 著者名、出版社名の誤字を修正
            - 日付形式の正規化（YYYY年MM月DD日）
            - 価格表記の正規化

            入力テキスト:
            \(rawText)

            修正後のテキストのみを出力してください（説明不要）:
            """

            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Apple Intelligence が利用不可または失敗した場合は元のテキストを返す
            print("Apple Intelligence correction failed: \(error)")
            return rawText
        }
        #else
        return rawText
        #endif
    }

    /// OCR実行後に自動でApple Intelligence補正を適用
    func recognizeTextWithCorrection(from image: UIImage) async throws -> String {
        let rawText = try await recognizeText(from: image)

        // Apple Intelligence が利用可能なら補正を適用
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await correctOCRTextWithAI(rawText)
        }
        #endif

        return rawText
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "画像の読み込みに失敗しました"
        case .recognitionFailed:
            return "テキストの認識に失敗しました"
        }
    }
}
