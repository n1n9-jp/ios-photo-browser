//
//  AlbumsListView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct AlbumsListView: View {
    @StateObject private var viewModel: AlbumsViewModel
    @State private var editMode: EditMode = .inactive

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeAlbumsViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.displayedAlbums.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.stack",
                        title: "アルバムがありません",
                        message: "新しいアルバムを作成して写真を整理しましょう",
                        action: { viewModel.showingCreateSheet = true },
                        actionTitle: "アルバムを作成"
                    )
                } else {
                    albumsList
                }
            }
            .navigationTitle("アルバム")
            .toolbar {
                if !viewModel.albums.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isReordering ? "完了" : "並び替え") {
                            withAnimation {
                                editMode = isReordering ? .inactive : .active
                            }
                        }
                    }
                }

                if !isReordering {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.showingCreateSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadAlbums()
                }
            }
            .refreshable {
                await viewModel.loadAlbums()
            }
            .sheet(isPresented: $viewModel.showingCreateSheet) {
                createAlbumSheet
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
            .environment(\.editMode, $editMode)
        }
    }

    private var isReordering: Bool {
        editMode.isEditing
    }

    private var albumsList: some View {
        List {
            if viewModel.favoriteAlbumCount > 0 {
                albumRow(for: .favorites, imageCount: viewModel.favoriteAlbumCount)
            }

            if viewModel.unregisteredAlbumCount > 0 {
                albumRow(for: .unregistered, imageCount: viewModel.unregisteredAlbumCount)
            }

            if isReordering {
                ForEach(viewModel.albums) { album in
                    AlbumRow(
                        album: album,
                        imageCount: viewModel.albumImageCounts[album.id] ?? 0
                    )
                }
                .onMove(perform: viewModel.moveAlbums)
            } else {
                ForEach(viewModel.albums) { album in
                    albumRow(for: album, imageCount: viewModel.albumImageCounts[album.id] ?? 0)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let album = viewModel.albums[index]
                        Task {
                            await viewModel.deleteAlbum(album)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
        }
    }

    @ViewBuilder
    private func albumRow(for album: Album, imageCount: Int) -> some View {
        if isReordering {
            AlbumRow(album: album, imageCount: imageCount)
        } else {
            NavigationLink(value: album) {
                AlbumRow(album: album, imageCount: imageCount)
            }
        }
    }

    private var createAlbumSheet: some View {
        NavigationStack {
            Form {
                Section("アルバム名") {
                    TextField("名前を入力", text: $viewModel.newAlbumName)
                }
            }
            .navigationTitle("新規アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.showingCreateSheet = false
                        viewModel.newAlbumName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        Task {
                            await viewModel.createAlbum()
                        }
                    }
                    .disabled(!viewModel.canCreateAlbum)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct AlbumRow: View {
    let album: Album
    let imageCount: Int
    @State private var coverImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            coverThumbnail
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.headline)

                Text("\(imageCount)枚")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task(id: album.coverImageId) {
            await loadCoverImage()
        }
    }

    private var coverThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .overlay {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: coverSystemImageName)
                        .foregroundColor(coverTintColor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var coverSystemImageName: String {
        if album.isFavoriteSmartAlbum {
            return "star.fill"
        }
        if album.isUnregisteredSmartAlbum {
            return "tray.full.fill"
        }
        return "photo.on.rectangle"
    }

    private var coverTintColor: Color {
        if album.isFavoriteSmartAlbum {
            return .yellow
        }
        if album.isUnregisteredSmartAlbum {
            return .orange
        }
        return .gray
    }

    private func loadCoverImage() async {
        guard !album.isSystemSmartAlbum,
              let coverImageId = album.coverImageId,
              let photo = try? await DependencyContainer.shared.imageRepository.fetch(byId: coverImageId) else {
            coverImage = nil
            return
        }

        if let thumbnailPath = photo.thumbnailPath,
           let thumbnail = FileStorageManager.shared.loadThumbnail(fileName: thumbnailPath) {
            coverImage = thumbnail
        } else {
            coverImage = FileStorageManager.shared.loadImage(fileName: photo.filePath)
        }
    }
}
