//
//  AlbumDetailView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct AlbumDetailView: View {
    @StateObject private var viewModel: AlbumDetailViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    init(album: Album) {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeAlbumDetailViewModel(album: album))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("読み込み中...")
            } else if viewModel.photos.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "写真がありません",
                    message: viewModel.album.isUnregisteredSmartAlbum
                        ? "どのアルバムにも登録されていない写真はありません"
                        : "このアルバムにはまだ写真がありません"
                )
            } else {
                photoGrid
            }
        }
        .navigationTitle(viewModel.album.name)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            Task {
                await viewModel.loadPhotos()
            }
        }
        .refreshable {
            await viewModel.loadPhotos()
        }
        .alert("エラー", isPresented: $viewModel.showingError) {
            Button("OK") {}
        } message: {
            Text(viewModel.error?.localizedDescription ?? "不明なエラー")
        }
        .sheet(isPresented: $viewModel.showingAlbumSelector) {
            albumSelectorSheet
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelectionMode {
                selectionActionBar
            }
        }
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.photos) { photo in
                    photoCell(for: photo)
                }
            }
            .padding(4)
        }
        .navigationDestination(for: PhotoItem.self) { photo in
            LibraryPhotoBrowserView(
                photos: viewModel.photos,
                initialPhotoId: photo.id
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isSelectionMode {
            ToolbarItem(placement: .topBarLeading) {
                Button("キャンセル") {
                    viewModel.cancelSelection()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(viewModel.areAllPhotosSelected ? "全解除" : "すべて選択") {
                    viewModel.toggleSelectAll()
                }
                .disabled(viewModel.photos.isEmpty || viewModel.isPerformingBatchAction)
            }
        } else if viewModel.canBatchAddToAlbum && !viewModel.photos.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button("選択") {
                    viewModel.startSelectionMode()
                }
            }
        }
    }

    @ViewBuilder
    private func photoCell(for photo: PhotoItem) -> some View {
        if viewModel.isSelectionMode {
            Button {
                viewModel.toggleSelection(for: photo)
            } label: {
                selectablePhotoGridItem(photo: photo)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: photo) {
                selectablePhotoGridItem(photo: photo)
            }
            .contextMenu {
                if viewModel.canRemoveFromAlbum {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.removeImage(photo)
                        }
                    } label: {
                        Label("アルバムから削除", systemImage: "minus.circle")
                    }
                }
            }
        }
    }

    private func selectablePhotoGridItem(photo: PhotoItem) -> some View {
        let isSelected = viewModel.isSelected(photo)

        return PhotoGridItem(photo: photo)
            .overlay {
                if viewModel.isSelectionMode {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if viewModel.isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.white)
                        .padding(8)
                        .shadow(radius: 2)
                }
            }
    }

    private var selectionActionBar: some View {
        VStack(spacing: 12) {
            HStack {
                Text(
                    viewModel.hasSelection ? "\(viewModel.selectedPhotoCount)枚を選択中" : "画像を選択してください"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                Spacer()

                if viewModel.isPerformingBatchAction {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            Button {
                Task {
                    await viewModel.openAlbumSelector()
                }
            } label: {
                Label("アルバム追加", systemImage: "rectangle.stack.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.hasSelection || viewModel.isPerformingBatchAction)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var albumSelectorSheet: some View {
        NavigationStack {
            List {
                if viewModel.allAlbums.isEmpty {
                    Text("アルバムがありません")
                        .foregroundColor(.secondary)
                } else {
                    Section("追加先のアルバム") {
                        ForEach(viewModel.allAlbums) { album in
                            Button {
                                Task {
                                    await viewModel.addSelectedPhotos(to: album)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.stack")
                                    Text(album.name)
                                    Spacer()
                                }
                                .foregroundColor(.primary)
                            }
                            .disabled(viewModel.isPerformingBatchAction)
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isPerformingBatchAction {
                    ProgressView("追加中...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("アルバムに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        viewModel.showingAlbumSelector = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
