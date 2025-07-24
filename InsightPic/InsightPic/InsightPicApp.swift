//
//  InsightPicApp.swift
//  InsightPic
//
//  Created by Sunil Pandey on 7/24/25.
//

import SwiftUI

@main
struct InsightPicApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
