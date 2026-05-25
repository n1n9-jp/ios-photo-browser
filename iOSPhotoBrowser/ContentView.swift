//
//  ContentView.swift
//  iOSPhotoBrowser
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("ライブラリ", systemImage: "photo.on.rectangle")
                }

            AlbumsListView()
                .tabItem {
                    Label("アルバム", systemImage: "rectangle.stack")
                }

            TagsListView()
                .tabItem {
                    Label("タグ", systemImage: "tag")
                }

            SearchView()
                .tabItem {
                    Label("検索", systemImage: "magnifyingglass")
                }

            ExtractedTextsView()
                .tabItem {
                    Label("テキスト", systemImage: "doc.text")
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
