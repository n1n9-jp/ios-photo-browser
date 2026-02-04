//
//  ExtractedTextsView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct ExtractedTextsView: View {
    @StateObject private var viewModel = DependencyContainer.shared.makeExtractedTextsViewModel()
    @State private var selectedItem: ExtractedTextItem?
    @State private var showingFilterSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("読み込み中...")
                } else if viewModel.items.isEmpty {
                    emptyStateView
                } else {
                    tableListView
                }
            }
            .navigationTitle("書誌情報")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Image(systemName: viewModel.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task {
                await viewModel.loadItems()
            }
            .refreshable {
                await viewModel.loadItems()
            }
            .alert("エラー", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error?.localizedDescription ?? "不明なエラー")
            }
            .sheet(item: $selectedItem) { item in
                BookDetailSheetView(
                    item: item,
                    onStatusUpdate: { readingStatus, ownershipStatus in
                        Task {
                            await viewModel.updateStatus(
                                for: item.id,
                                readingStatus: readingStatus,
                                ownershipStatus: ownershipStatus
                            )
                        }
                    },
                    onDismiss: {
                        selectedItem = nil
                    }
                )
            }
            .sheet(isPresented: $showingFilterSheet) {
                filterSheet
            }
        }
    }

    // MARK: - Filter Sheet

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("読書状況") {
                    Picker("読書状況", selection: $viewModel.readingStatusFilter) {
                        ForEach(ReadingStatusFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("所有状況") {
                    Picker("所有状況", selection: $viewModel.ownershipStatusFilter) {
                        ForEach(OwnershipStatusFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.hasActiveFilters {
                    Section {
                        Button("フィルターをクリア", role: .destructive) {
                            viewModel.clearFilters()
                        }
                    }
                }
            }
            .navigationTitle("フィルター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        showingFilterSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            if viewModel.hasActiveFilters {
                Text("該当する書誌情報がありません")
                    .font(.headline)
                Text("フィルター条件を変更してみてください")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button("フィルターをクリア") {
                    viewModel.clearFilters()
                }
                .buttonStyle(.bordered)
            } else {
                Text("書誌情報がありません")
                    .font(.headline)
                Text("詳細画面で「抽出」ボタンを押すと\nOCRでテキストを抽出し、\n書誌情報を取得できます")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private var tableListView: some View {
        List {
            ForEach(viewModel.groupedItems) { group in
                Section {
                    ForEach(group.items) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    // Book title
                                    Text(item.bookTitle ?? item.displayTitle)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)

                                    // Author
                                    if let author = item.bookAuthor {
                                        Text(author)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    // Status badges
                                    HStack(spacing: 8) {
                                        statusBadge(
                                            icon: item.readingStatus.iconName,
                                            text: item.readingStatus.displayName,
                                            color: readingStatusColor(item.readingStatus)
                                        )
                                        statusBadge(
                                            icon: item.ownershipStatus.iconName,
                                            text: item.ownershipStatus.displayName,
                                            color: item.ownershipStatus == .owned ? .green : .gray
                                        )
                                    }
                                }

                                Spacer()

                                // Chevron indicator
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(group.category)
                        Spacer()
                        Text("\(group.items.count)件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .cornerRadius(4)
    }

    private func readingStatusColor(_ status: ReadingStatus) -> Color {
        switch status {
        case .unread: return .gray
        case .reading: return .blue
        case .finished: return .green
        }
    }
}

// MARK: - Book Detail Sheet View

struct BookDetailSheetView: View {
    let item: ExtractedTextItem
    let onStatusUpdate: (ReadingStatus, OwnershipStatus) -> Void
    let onDismiss: () -> Void

    @State private var readingStatus: ReadingStatus
    @State private var ownershipStatus: OwnershipStatus
    @State private var hasChanges = false

    init(
        item: ExtractedTextItem,
        onStatusUpdate: @escaping (ReadingStatus, OwnershipStatus) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.onStatusUpdate = onStatusUpdate
        self.onDismiss = onDismiss
        _readingStatus = State(initialValue: item.readingStatus)
        _ownershipStatus = State(initialValue: item.ownershipStatus)
    }

    var body: some View {
        NavigationStack {
            List {
                // Thumbnail section
                if let path = item.thumbnailPath,
                   let image = FileStorageManager.shared.loadThumbnail(fileName: path) {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // User status section (editable)
                Section("ユーザー情報") {
                    Picker("読書状況", selection: $readingStatus) {
                        ForEach(ReadingStatus.allCases, id: \.self) { status in
                            Label(status.displayName, systemImage: status.iconName)
                                .tag(status)
                        }
                    }
                    .onChange(of: readingStatus) { _, _ in
                        hasChanges = true
                    }

                    Picker("所有状況", selection: $ownershipStatus) {
                        ForEach(OwnershipStatus.allCases, id: \.self) { status in
                            Label(status.displayName, systemImage: status.iconName)
                                .tag(status)
                        }
                    }
                    .onChange(of: ownershipStatus) { _, _ in
                        hasChanges = true
                    }
                }

                // Book info section
                Section("書誌情報") {
                    if let title = item.bookTitle {
                        infoRow("タイトル", value: title)
                    }
                    if let author = item.bookAuthor {
                        infoRow("著者", value: author)
                    }
                    if let publisher = item.bookPublisher {
                        infoRow("出版社", value: publisher)
                    }
                    if let isbn = item.bookISBN, !isbn.isEmpty {
                        infoRow("ISBN", value: isbn)
                    }
                    if let category = item.bookCategory {
                        infoRow("カテゴリ", value: category)
                    }
                    if let processedAt = item.ocrProcessedAt {
                        infoRow("取得日時", value: formatDate(processedAt))
                    }
                }

                // Extracted text section
                if let text = item.extractedText, !text.isEmpty {
                    Section {
                        DisclosureGroup("抽出テキスト") {
                            Text(text)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasChanges ? "保存" : "閉じる") {
                        if hasChanges {
                            onStatusUpdate(readingStatus, ownershipStatus)
                        }
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
