import SwiftUI

struct PhotoGridView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()
    @State private var showingSettings = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    LoadingView(viewModel: viewModel)
                } else if viewModel.photos.isEmpty {
                    if viewModel.authorizationStatus == .notDetermined {
                        PermissionRequestView(viewModel: viewModel)
                    } else {
                        EmptyStateView(viewModel: viewModel)
                    }
                } else {
                    PhotoGrid(viewModel: viewModel, columns: columns)
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .medium))
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
            .task {
                await viewModel.loadExistingPhotos()
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
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(viewModel.photos) { photo in
                    PhotoThumbnailView(photo: photo, viewModel: viewModel)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                }
            }
            .padding(.horizontal, 0)
        }
        .clipped()
    }
}

// MARK: - Photo Thumbnail View

struct PhotoThumbnailView: View {
    let photo: Photo
    let viewModel: PhotoLibraryViewModel
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    @State private var showingDetailView = false
    
    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.gray)
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.gray.opacity(0.5))
                            .font(.system(size: 20))
                    }
            }
        }
        .cornerRadius(0)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingDetailView = true
            }
        }
        .fullScreenCover(isPresented: $showingDetailView) {
            PhotoDetailView(photo: photo, viewModel: viewModel)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 1.05))
                ))
        }
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
    @State private var showingPhotoScoring = false
    @State private var showingPhotoClustering = false
    
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
                
                Section("AI Features") {
                    Button("Analyze Photo Quality") {
                        showingPhotoAnalysis = true
                    }
                    .disabled(viewModel.photos.isEmpty)
                    
                    Button("Quality Scoring & Assessment") {
                        showingPhotoScoring = true
                    }
                    .disabled(viewModel.photos.isEmpty)
                    
                    Button("Cluster Similar Photos") {
                        showingPhotoClustering = true
                    }
                    .disabled(viewModel.photos.isEmpty)
                }
                
                Section("Actions") {
                    Button("Filter Recent Photos (30 days)") {
                        viewModel.filterRecentPhotos(days: 30)
                        dismiss()
                    }
                    
                    Button("Filter Photos with Location") {
                        viewModel.filterPhotosWithLocation()
                        dismiss()
                    }
                }
                
                Section("Database") {
                    Button("Clear All Photos", role: .destructive) {
                        Task {
                            await viewModel.clearDatabase()
                            dismiss()
                        }
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
            .sheet(isPresented: $showingPhotoScoring) {
                PhotoScoringView(photoViewModel: viewModel)
            }
            .sheet(isPresented: $showingPhotoClustering) {
                PhotoClusteringView(photoViewModel: viewModel)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoGridView()
}