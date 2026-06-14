//
//  AlbumDetailView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct AlbumDetailView: View {
    @StateObject private var viewModel: AlbumDetailViewModel
    @State private var lastViewedPhotoID: UUID?
    @State private var showingRenameSheet = false
    @State private var editedAlbumName = ""
    @AppStorage(PhotoGridSizeOption.storageKey) private var photoGridSizeRawValue = PhotoGridSizeOption.medium.rawValue

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
        .sheet(isPresented: $showingRenameSheet) {
            renameAlbumSheet
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelectionMode {
                selectionActionBar
            }
        }
    }

    private var photoGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(viewModel.photos) { photo in
                        photoCell(for: photo)
                            .id(photo.id)
                    }
                }
                .padding(4)
            }
            .onAppear {
                restoreScrollPosition(using: proxy)
            }
            .onChange(of: viewModel.photos.map(\.id)) { _, _ in
                restoreScrollPosition(using: proxy)
            }
            .navigationDestination(for: PhotoItem.self) { photo in
                LibraryPhotoBrowserView(
                    photos: viewModel.photos,
                    initialPhotoId: photo.id,
                    onCurrentPhotoChanged: { photoID in
                        lastViewedPhotoID = photoID
                    }
                )
            }
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
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                PhotoGridSizeMenu()
            }

            if viewModel.canRenameAlbum {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editedAlbumName = viewModel.album.name
                        showingRenameSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }

            if viewModel.canSelectPhotosForAlbumAction && !viewModel.photos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("選択") {
                        viewModel.startSelectionMode()
                    }
                }
            }
        }
    }

    private var photoGridSize: PhotoGridSizeOption {
        PhotoGridSizeOption(rawValue: photoGridSizeRawValue) ?? .medium
    }

    private var columns: [GridItem] {
        photoGridSize.columns
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
            .simultaneousGesture(TapGesture().onEnded {
                lastViewedPhotoID = photo.id
            })
            .contextMenu {
                if viewModel.canSetCoverImage {
                    Button {
                        Task {
                            await viewModel.setCoverImage(photo)
                        }
                    } label: {
                        Label(viewModel.isCoverImage(photo) ? "表紙に設定済み" : "表紙に設定", systemImage: "photo.fill.on.rectangle.fill")
                    }
                }

                if viewModel.canMovePhotosToAnotherAlbum {
                    Button {
                        Task {
                            await viewModel.movePhotoToAnotherAlbum(photo)
                        }
                    } label: {
                        Label("別のアルバムへ移動", systemImage: "folder.badge.gearshape")
                    }
                }

                if viewModel.canRemoveFromAlbum {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.removeImage(photo)
                        }
                    } label: {
                        Label("アルバムから削除", systemImage: "minus.circle")
                    }
                } else if viewModel.canRemoveFavoriteFlag {
                    Button {
                        Task {
                            await viewModel.removeFavorite(photo)
                        }
                    } label: {
                        Label("星を外す", systemImage: "star.slash")
                    }
                }
            }
        }
    }

    private func selectablePhotoGridItem(photo: PhotoItem) -> some View {
        let isSelected = viewModel.isSelected(photo)

        return PhotoGridItem(photo: photo)
            .overlay(alignment: .bottomLeading) {
                if viewModel.isCoverImage(photo) {
                    Text("表紙")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .foregroundColor(.white)
                        .padding(6)
                }
            }
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
                Label(viewModel.albumActionButtonTitle, systemImage: viewModel.canMovePhotosToAnotherAlbum ? "folder.badge.gearshape" : "rectangle.stack.badge.plus")
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

    private var renameAlbumSheet: some View {
        NavigationStack {
            Form {
                Section("アルバム名") {
                    TextField("名前を入力", text: $editedAlbumName)
                }
            }
            .navigationTitle("アルバム名を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showingRenameSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            let didRename = await viewModel.renameAlbum(to: editedAlbumName)
                            if didRename {
                                showingRenameSheet = false
                            }
                        }
                    }
                    .disabled(editedAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var albumSelectorSheet: some View {
        NavigationStack {
            List {
                if viewModel.allAlbums.isEmpty {
                    Text("アルバムがありません")
                        .foregroundColor(.secondary)
                } else {
                    Section(viewModel.albumSelectorSectionTitle) {
                        ForEach(viewModel.allAlbums) { album in
                            Button {
                                Task {
                                    await viewModel.applySelectedPhotosToAlbum(album)
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
                    ProgressView(viewModel.albumActionProgressTitle)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle(viewModel.albumSelectorTitle)
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

    private func restoreScrollPosition(using proxy: ScrollViewProxy) {
        guard let lastViewedPhotoID else { return }

        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(lastViewedPhotoID, anchor: .center)
        }
    }
}
