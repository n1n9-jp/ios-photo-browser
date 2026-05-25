//
//  iOSPhotoBrowserApp.swift
//  iOSPhotoBrowser
//

import SwiftUI

@main
struct iOSPhotoBrowserApp: App {
    init() {
        BackupExclusionManager.reconcileManagedDirectories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
