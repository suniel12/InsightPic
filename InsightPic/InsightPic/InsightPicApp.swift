//
//  InsightPicApp.swift
//  InsightPic
//
//  Created by Sunil Pandey on 7/24/25.
//

import SwiftUI
import CoreData

@main
struct InsightPicApp: App {
    let persistenceController = CoreDataStack.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.mainContext)
        }
    }
}
