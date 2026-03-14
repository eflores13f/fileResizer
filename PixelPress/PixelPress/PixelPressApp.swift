//
//  PixelpressApp.swift
//  FileResizer is being renamed to PixelPress
//
//  Created by eflo on 3/13/26.

import SwiftUI

@main
struct PixelPressApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 820)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
