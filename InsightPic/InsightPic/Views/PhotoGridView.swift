import SwiftUI

struct PhotoGridView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()
    @State private var showingSettings = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2),
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2),
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.authorizationStatus == .notDetermined {
                    PermissionRequestView(viewModel: viewModel)
                } else if viewModel.isLoading {
                    LoadingView(viewModel: viewModel)
                } else if viewModel.photos.isEmpty {
                    EmptyStateView(viewModel: viewModel)
                } else {
                    PhotoGrid(viewModel: viewModel, columns: columns)
                }
            }
            .navigationTitle("InsightPic")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
                
                if !viewModel.photos.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Refresh") {
                            Task {
                                await viewModel.refreshPhotos()
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(viewModel: viewModel)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}

// MARK: - Permission Request View

struct PermissionRequestView: View {
    let viewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text("Access Your Photos")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("InsightPic needs access to your photo library to analyze and curate your best photos.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                Task {
                    await viewModel.requestPhotoLibraryAccess()
                }
            }) {
                Text("Allow Photo Access")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: viewModel.loadingProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 8)
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            Text(viewModel.loadingText)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            if viewModel.loadingProgress > 0 {
                Text("\(Int(viewModel.loadingProgress * 100))% Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let viewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            
            VStack(spacing: 16) {
                Text("No Photos Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Make sure you have photos in your library and have granted photo access.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Button("Reload Photos") {
                Task {
                    await viewModel.loadPhotosFromLibrary()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Photo Grid

struct PhotoGrid: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let columns: [GridItem]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.photos) { photo in
                    PhotoThumbnailView(photo: photo, viewModel: viewModel)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Photo Thumbnail View

struct PhotoThumbnailView: View {
    let photo: Photo
    let viewModel: PhotoLibraryViewModel
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    }
            }
        }
        .cornerRadius(4)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task {
            isLoading = true
            let image = await viewModel.loadThumbnail(for: photo)
            await MainActor.run {
                self.thumbnailImage = image
                self.isLoading = false
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingPhotoAnalysis = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Photo Library") {
                    HStack {
                        Text("Total Photos")
                        Spacer()
                        Text("\(viewModel.totalPhotosCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Photos with Location")
                        Spacer()
                        Text("\(viewModel.photosWithLocationCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    let dateRange = viewModel.dateRange
                    if let startDate = dateRange.start,
                       let endDate = dateRange.end {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date Range")
                            Text("\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("AI Analysis") {
                    Button("Analyze Photos with AI") {
                        showingPhotoAnalysis = true
                    }
                    .disabled(viewModel.photos.isEmpty)
                }
                
                Section("Actions") {
                    Button("Refresh Photo Library") {
                        Task {
                            await viewModel.refreshPhotos()
                            dismiss()
                        }
                    }
                    
                    Button("Filter Recent Photos (30 days)") {
                        viewModel.filterRecentPhotos(days: 30)
                        dismiss()
                    }
                    
                    Button("Filter Photos with Location") {
                        viewModel.filterPhotosWithLocation()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPhotoAnalysis) {
                PhotoAnalysisView(photoViewModel: viewModel)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoGridView()
}