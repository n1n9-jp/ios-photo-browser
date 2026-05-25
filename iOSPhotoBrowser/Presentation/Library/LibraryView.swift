//
//  LibraryView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel: LibraryViewModel
    @State private var showingImportSheet = false
    @State private var showingSettings = false

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeLibraryViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.photos.isEmpty {
                    EmptyStateView(
                        icon: "photo.on.rectangle.angled",
                        title: "写真がありません",
                        message: "上部の「＋」ボタンから写真を追加してください"
                    )
                } else {
                    photoGrid
                }
            }
            .navigationTitle("ライブラリ")
            .toolbar {
                if viewModel.isSelectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("キャンセル") {
                            viewModel.cancelSelection()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.toggleSelectAll()
                        } label: {
                            Text(viewModel.areAllPhotosSelected ? "全解除" : "すべて選択")
                        }
                        .disabled(viewModel.photos.isEmpty || viewModel.isPerformingBatchAction)
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingImportSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            sortMenu
                            Button("選択") {
                                viewModel.startSelectionMode()
                            }
                            .disabled(viewModel.photos.isEmpty)
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                }
            }
            .task {
                await viewModel.loadPhotos()
            }
            .refreshable {
                await viewModel.loadPhotos()
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
            .alert("削除確認", isPresented: $viewModel.showingDeleteConfirmation) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    Task {
                        await viewModel.deleteSelectedPhotos()
                    }
                }
            } message: {
                Text("\(viewModel.selectedPhotoCount)枚の画像を削除しますか？この操作は取り消せません。")
            }
            .sheet(isPresented: $showingImportSheet) {
                // Reload photos when sheet is dismissed
                Task {
                    await viewModel.loadPhotos()
                }
            } content: {
                ImportView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $viewModel.showingTagEditor) {
                tagEditorSheet
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
            DetailView(photoId: photo.id)
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
                Text(viewModel.hasSelection ? "\(viewModel.selectedPhotoCount)枚を選択中" : "画像を選択してください")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.isPerformingBatchAction {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.showingTagEditor = true
                } label: {
                    Label("タグ追加", systemImage: "tag")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await viewModel.openAlbumSelector()
                    }
                } label: {
                    Label("アルバム追加", systemImage: "rectangle.stack.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    viewModel.showingDeleteConfirmation = true
                } label: {
                    Label("削除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .font(.subheadline)
            .disabled(!viewModel.hasSelection || viewModel.isPerformingBatchAction)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    viewModel.changeSortOption(option)
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if viewModel.sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var tagEditorSheet: some View {
        NavigationStack {
            Form {
                Section("選択中の画像") {
                    Text("\(viewModel.selectedPhotoCount)枚")
                        .foregroundColor(.secondary)
                }

                Section("追加するタグ") {
                    TextField("タグ名", text: $viewModel.newTagName)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("タグを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        viewModel.showingTagEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        Task {
                            await viewModel.addTagToSelectedPhotos()
                        }
                    }
                    .disabled(
                        viewModel.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        !viewModel.hasSelection ||
                        viewModel.isPerformingBatchAction
                    )
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
