import SwiftUI

struct ContentView: View {
    
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "photo.on.rectangle.angled")
                    .imageScale(.large)
                    .foregroundColor(.accentColor)
                Text("Photo Curator")
                    .font(.title)
                    .padding()
                
                Text("Smart photo curation coming soon!")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Photo Curator")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}