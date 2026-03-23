//
//  DualApp.swift
//  Dual
//
//  Created by lin on 2026/3/23.
//

import SwiftUI
import CoreData

@main
struct DualApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
