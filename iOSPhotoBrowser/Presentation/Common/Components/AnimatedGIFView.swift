//
//  AnimatedGIFView.swift
//  iOSPhotoBrowser
//

import SwiftUI
import UIKit
import ImageIO

struct AnimatedGIFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if let animatedImage = GIFSupport.makeAnimatedImage(from: data),
           let frames = animatedImage.images,
           !frames.isEmpty {
            imageView.stopAnimating()
            imageView.image = nil
            imageView.animationImages = frames
            imageView.animationDuration = animatedImage.duration
            imageView.animationRepeatCount = 0
            imageView.startAnimating()
        } else {
            imageView.stopAnimating()
            imageView.animationImages = nil
            imageView.image = UIImage(data: data)
        }
    }
}

enum GIFSupport {
    static func isGIFData(_ data: Data) -> Bool {
        data.starts(with: [0x47, 0x49, 0x46, 0x38])
    }

    static func makeAnimatedImage(from data: Data) -> UIImage? {
        guard isGIFData(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            return UIImage(data: data)
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)
        var duration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }

            let frameDuration = max(0.02, delayTime(for: source, at: index))
            duration += frameDuration
            frames.append(UIImage(cgImage: cgImage))
        }

        guard !frames.isEmpty else {
            return UIImage(data: data)
        }

        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func delayTime(for source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        if let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber {
            return unclamped.doubleValue
        }

        if let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber {
            return clamped.doubleValue
        }

        return 0.1
    }
}
