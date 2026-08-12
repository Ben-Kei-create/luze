//
//  luzeApp.swift
//  luze
//
//  Created by 茂木史明 on 2026/08/12.
//

import SwiftUI

@main
struct luzeApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
    }
}
