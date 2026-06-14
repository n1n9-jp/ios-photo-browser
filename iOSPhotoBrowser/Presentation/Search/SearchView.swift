//
//  SearchView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @State private var lastViewedPhotoID: UUID?
    @AppStorage(PhotoGridSizeOption.storageKey) private var photoGridSizeRawValue = PhotoGridSizeOption.medium.rawValue

    init() {
        _viewModel = StateObject(wrappedValue: DependencyContainer.shared.makeSearchViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.searchText.isEmpty {
                    searchPromptView
                } else if viewModel.isSearching {
                    ProgressView("検索中...")
                } else if viewModel.searchResults.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "結果がありません",
                        message: "「\(viewModel.searchText)」に一致する写真が見つかりませんでした"
                    )
                } else {
                    searchResultsGrid
                }
            }
            .navigationTitle("検索")
            .toolbar {
                if !viewModel.searchResults.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        PhotoGridSizeMenu()
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "タグで検索")
            .onSubmit(of: .search) {
                Task {
                    await viewModel.search()
                }
            }
            .onChange(of: viewModel.searchText) { _, newValue in
                if newValue.isEmpty {
                    viewModel.clearSearch()
                }
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
        }
    }

    private var photoGridSize: PhotoGridSizeOption {
        PhotoGridSizeOption(rawValue: photoGridSizeRawValue) ?? .medium
    }

    private var columns: [GridItem] {
        photoGridSize.columns
    }

    private var searchPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("タグで写真を検索")
                .font(.headline)

            Text("検索バーにタグ名を入力してください")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var searchResultsGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(viewModel.searchResults.count)件の結果")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(viewModel.searchResults) { photo in
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
            }
            .onAppear {
                restoreScrollPosition(using: proxy)
            }
            .onChange(of: viewModel.searchResults.map(\.id)) { _, _ in
                restoreScrollPosition(using: proxy)
            }
            .navigationDestination(for: PhotoItem.self) { photo in
                LibraryPhotoBrowserView(
                    photos: viewModel.searchResults,
                    initialPhotoId: photo.id,
                    onCurrentPhotoChanged: { photoID in
                        lastViewedPhotoID = photoID
                    }
                )
            }
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
