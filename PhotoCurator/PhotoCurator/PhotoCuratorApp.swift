import SwiftUI

@main
struct PhotoCuratorApp: App {
    let persistenceContainer = CoreDataStack.shared.persistentContainer
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceContainer.viewContext)
        }
    }
}