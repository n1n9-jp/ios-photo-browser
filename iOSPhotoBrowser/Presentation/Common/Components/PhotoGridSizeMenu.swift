//
//  PhotoGridSizeMenu.swift
//  iOSPhotoBrowser
//

import SwiftUI

enum PhotoGridSizeOption: String, CaseIterable, Identifiable {
    case large
    case medium
    case small

    static let storageKey = "photoGridSizeOption"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .large:
            return "大きめ"
        case .medium:
            return "標準"
        case .small:
            return "小さめ"
        }
    }

    var systemImageName: String {
        switch self {
        case .large:
            return "square.grid.2x2"
        case .medium:
            return "square.grid.3x3"
        case .small:
            return "square.grid.4x3.fill"
        }
    }

    var columnCount: Int {
        switch self {
        case .large:
            return 2
        case .medium:
            return 3
        case .small:
            return 4
        }
    }

    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount)
    }
}

struct PhotoGridSizeMenu: View {
    @AppStorage(PhotoGridSizeOption.storageKey) private var photoGridSizeRawValue = PhotoGridSizeOption.medium.rawValue

    private var selectedSize: PhotoGridSizeOption {
        get { PhotoGridSizeOption(rawValue: photoGridSizeRawValue) ?? .medium }
        nonmutating set { photoGridSizeRawValue = newValue.rawValue }
    }

    var body: some View {
        Menu {
            ForEach(PhotoGridSizeOption.allCases) { size in
                Button {
                    selectedSize = size
                } label: {
                    HStack {
                        Label(size.title, systemImage: size.systemImageName)
                        if selectedSize == size {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedSize.systemImageName)
        }
    }
}
