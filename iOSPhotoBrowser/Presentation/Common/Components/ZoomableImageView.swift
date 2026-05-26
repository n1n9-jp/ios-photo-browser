//
//  ZoomableImageView.swift
//  iOSPhotoBrowser
//

import SwiftUI
import UIKit

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let mediaID: UUID
    let onSingleTap: () -> Void
    let onZoomStateChanged: (Bool) -> Void

    func makeUIView(context: Context) -> ZoomableImageScrollView {
        let scrollView = ZoomableImageScrollView()
        scrollView.onSingleTap = onSingleTap
        scrollView.onZoomStateChanged = onZoomStateChanged
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomableImageScrollView, context: Context) {
        scrollView.onSingleTap = onSingleTap
        scrollView.onZoomStateChanged = onZoomStateChanged
        scrollView.setImage(image, mediaID: mediaID)
    }
}

final class ZoomableImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var configuredMediaID: UUID?
    private var previousBoundsSize: CGSize = .zero
    private var needsInitialZoomReset = false
    private var baseZoomScale: CGFloat = 1
    private var currentZoomedState = false

    var onSingleTap: (() -> Void)?
    var onZoomStateChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        delegate = self
        backgroundColor = .clear
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = false
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateZoomScalesIfNeeded()
        centerImageIfNeeded()
    }

    func setImage(_ image: UIImage, mediaID: UUID) {
        guard configuredMediaID != mediaID else {
            return
        }

        configuredMediaID = mediaID
        previousBoundsSize = .zero
        currentZoomedState = false
        needsInitialZoomReset = true

        minimumZoomScale = 1
        maximumZoomScale = 1
        zoomScale = 1
        contentInset = .zero

        imageView.stopAnimating()
        imageView.animationImages = nil

        if let frames = image.images, !frames.isEmpty {
            imageView.image = nil
            imageView.animationImages = frames
            imageView.animationDuration = image.duration
            imageView.animationRepeatCount = 0
            imageView.startAnimating()
        } else {
            imageView.image = image
        }

        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size

        setNeedsLayout()
        layoutIfNeeded()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageIfNeeded()
        notifyZoomStateChangedIfNeeded()
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let targetScale = isAtBaseScale ? preferredDoubleTapZoomScale : baseZoomScale

        guard abs(targetScale - baseZoomScale) > 0.01 else {
            setZoomScale(baseZoomScale, animated: true)
            return
        }

        let location = recognizer.location(in: imageView)
        zoom(to: zoomRect(for: targetScale, centeredAt: location), animated: true)
    }

    private func updateZoomScalesIfNeeded() {
        let boundsSize = bounds.size
        guard boundsSize.width > 0,
              boundsSize.height > 0,
              imageView.bounds.width > 0,
              imageView.bounds.height > 0 else {
            return
        }

        let widthScale = boundsSize.width / imageView.bounds.width
        let heightScale = boundsSize.height / imageView.bounds.height
        let fitScale = min(widthScale, heightScale)
        let originalScale: CGFloat = 1

        baseZoomScale = fitScale
        minimumZoomScale = min(originalScale, fitScale)
        maximumZoomScale = max(fitScale * 4, originalScale * 4, 4)

        if needsInitialZoomReset {
            setZoomScale(baseZoomScale, animated: false)
            needsInitialZoomReset = false
            notifyZoomStateChangedIfNeeded(force: true)
        } else if previousBoundsSize != boundsSize {
            let clampedScale = min(max(zoomScale, minimumZoomScale), maximumZoomScale)
            setZoomScale(clampedScale, animated: false)
            notifyZoomStateChangedIfNeeded(force: true)
        }

        previousBoundsSize = boundsSize
    }

    private func centerImageIfNeeded() {
        let horizontalInset = max((bounds.width - imageView.frame.width) / 2, 0)
        let verticalInset = max((bounds.height - imageView.frame.height) / 2, 0)
        contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    private var isAtBaseScale: Bool {
        abs(zoomScale - baseZoomScale) < 0.05
    }

    private var preferredDoubleTapZoomScale: CGFloat {
        let originalScale = min(max(CGFloat(1), minimumZoomScale), maximumZoomScale)
        if abs(originalScale - baseZoomScale) > 0.05 {
            return originalScale
        }
        return min(maximumZoomScale, max(baseZoomScale * 2, baseZoomScale + 0.5))
    }

    private func zoomRect(for scale: CGFloat, centeredAt point: CGPoint) -> CGRect {
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        let origin = CGPoint(x: point.x - (size.width / 2), y: point.y - (size.height / 2))
        return CGRect(origin: origin, size: size)
    }

    private func notifyZoomStateChangedIfNeeded(force: Bool = false) {
        let isZoomed = !isAtBaseScale
        guard force || isZoomed != currentZoomedState else {
            return
        }

        currentZoomedState = isZoomed
        onZoomStateChanged?(isZoomed)
    }
}
