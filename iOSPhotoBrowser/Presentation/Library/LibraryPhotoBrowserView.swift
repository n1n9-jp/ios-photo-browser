//
//  LibraryPhotoBrowserView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct LibraryPhotoBrowserView: View {
    let photos: [PhotoItem]
    let onCurrentPhotoChanged: ((UUID) -> Void)?
    @State private var currentIndex: Int

    init(photos: [PhotoItem], initialPhotoId: UUID, onCurrentPhotoChanged: ((UUID) -> Void)? = nil) {
        self.photos = photos
        self.onCurrentPhotoChanged = onCurrentPhotoChanged
        _currentIndex = State(initialValue: photos.firstIndex { $0.id == initialPhotoId } ?? 0)
    }

    var body: some View {
        Group {
            if photos.indices.contains(currentIndex) {
                DetailView(photoId: photos[currentIndex].id)
                    .id(photos[currentIndex].id)
                    .simultaneousGesture(photoSwipeGesture)
                    .onAppear {
                        notifyCurrentPhotoChanged()
                    }
                    .onChange(of: currentIndex) { _, _ in
                        notifyCurrentPhotoChanged()
                    }
            } else {
                EmptyStateView(
                    icon: "photo",
                    title: "写真が見つかりません",
                    message: "表示できる写真がありません"
                )
            }
        }
    }

    private var photoSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height

                guard abs(horizontalDistance) > abs(verticalDistance),
                      abs(horizontalDistance) > 60 else {
                    return
                }

                if horizontalDistance < 0 {
                    moveToNextPhoto()
                } else {
                    moveToPreviousPhoto()
                }
            }
    }

    private func moveToNextPhoto() {
        guard currentIndex < photos.count - 1 else { return }
        currentIndex += 1
    }

    private func moveToPreviousPhoto() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    private func notifyCurrentPhotoChanged() {
        guard photos.indices.contains(currentIndex) else { return }
        onCurrentPhotoChanged?(photos[currentIndex].id)
    }
}
