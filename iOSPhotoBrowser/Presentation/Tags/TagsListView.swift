//
//  TagsListView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct TagsListView: View {
    @StateObject private var viewModel: TagsViewModel

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeTagsViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.tagsWithCount.isEmpty {
                    EmptyStateView(
                        icon: "tag",
                        title: "タグがありません",
                        message: "写真の詳細画面からタグを追加できます"
                    )
                } else {
                    tagsList
                }
            }
            .navigationTitle("タグ")
            .task {
                await viewModel.loadTags()
            }
            .refreshable {
                await viewModel.loadTags()
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
        }
    }

    private var tagsList: some View {
        List {
            ForEach(viewModel.tagsWithCount) { tagWithCount in
                NavigationLink(value: tagWithCount.tag) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.blue)
                        Text(tagWithCount.tag.name)
                        Spacer()
                        Text("\(tagWithCount.imageCount)枚")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let tag = viewModel.tagsWithCount[index].tag
                    Task {
                        await viewModel.deleteTag(tag)
                    }
                }
            }
        }
        .navigationDestination(for: Tag.self) { tag in
            TagImagesView(tag: tag)
        }
    }
}

struct TagImagesView: View {
    let tag: Tag
    @State private var photos: [PhotoItem] = []
    @State private var isLoading = false
    @State private var lastViewedPhotoID: UUID?
    @AppStorage(PhotoGridSizeOption.storageKey) private var photoGridSizeRawValue = PhotoGridSizeOption.medium.rawValue

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if photos.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "写真がありません",
                    message: "このタグが付いた写真はありません"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(photos) { photo in
                                NavigationLink(value: photo) {
                                    PhotoGridItem(photo: photo)
                                }
                                .id(photo.id)
                                .simultaneousGesture(TapGesture().onEnded {
                                    lastViewedPhotoID = photo.id
                                })
                            }
                        }
                        .padding(4)
                    }
                    .onAppear {
                        restoreScrollPosition(using: proxy)
                    }
                    .onChange(of: photos.map(\.id)) { _, _ in
                        restoreScrollPosition(using: proxy)
                    }
                    .navigationDestination(for: PhotoItem.self) { photo in
                        LibraryPhotoBrowserView(
                            photos: photos,
                            initialPhotoId: photo.id,
                            onCurrentPhotoChanged: { photoID in
                                lastViewedPhotoID = photoID
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(tag.name)
        .toolbar {
            if !photos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotoGridSizeMenu()
                }
            }
        }
        .task {
            await loadPhotos()
        }
    }

    private var photoGridSize: PhotoGridSizeOption {
        PhotoGridSizeOption(rawValue: photoGridSizeRawValue) ?? .medium
    }

    private var columns: [GridItem] {
        photoGridSize.columns
    }

    private func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = DependencyContainer.shared.imageRepository
            photos = try await repository.search(byTag: tag.name)
        } catch {
            print("Error loading photos: \(error)")
        }
    }

    private func restoreScrollPosition(using proxy: ScrollViewProxy) {
        guard let lastViewedPhotoID else { return }

        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(lastViewedPhotoID, anchor: .center)
        }
    }
}
