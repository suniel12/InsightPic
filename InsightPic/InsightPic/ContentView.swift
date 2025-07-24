//
//  ContentView.swift
//  InsightPic
//
//  Created by Sunil Pandey on 7/24/25.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PhotoEntity.timestamp, ascending: false)],
        animation: .default)
    private var photos: FetchedResults<PhotoEntity>

    var body: some View {
        NavigationView {
            List {
                ForEach(photos) { photo in
                    NavigationLink {
                        Text("Photo at \(photo.timestamp!, formatter: itemFormatter)")
                    } label: {
                        Text(photo.assetIdentifier ?? "Unknown Photo")
                    }
                }
                .onDelete(perform: deletePhotos)
            }
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addPhoto) {
                        Label("Add Photo", systemImage: "plus")
                    }
                }
            }
            Text("Photo Curator - InsightPic")
        }
    }

    private func addPhoto() {
        withAnimation {
            let newPhoto = PhotoEntity(context: viewContext)
            newPhoto.id = UUID()
            newPhoto.assetIdentifier = "sample-\(UUID().uuidString)"
            newPhoto.timestamp = Date()

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deletePhotos(offsets: IndexSet) {
        withAnimation {
            offsets.map { photos[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView()
}
