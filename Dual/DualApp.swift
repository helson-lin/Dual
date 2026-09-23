//
//  DualApp.swift
//  Dual
//
//  Created by lin on 2026/3/23.
//

import AppKit
import SwiftUI
import Sparkle

@main
struct DualApp: App {
    private let updaterController: SPUStandardUpdaterController?

    init() {
        // The window refuses full screen, so AppKit's automatic menu item would
        // only ever no-op. Registering the default keeps it out of the View menu.
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])

        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        updaterController = publicKey?.isEmpty == false
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.string("menu.checkForUpdates")) {
                    updaterController?.updater.checkForUpdates()
                }
                .disabled(updaterController == nil)

                Button(L10n.string("menu.viewOnGitHub")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/helson-lin/Dual")!)
                }

                Button(L10n.string("menu.viewFanBar")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/helson-lin/FanBar")!)
                }
            }
        }
    }
}
