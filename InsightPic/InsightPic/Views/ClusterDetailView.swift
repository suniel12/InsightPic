import SwiftUI

struct ClusterMomentsDetailView: View {
    let cluster: PhotoCluster
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @ObservedObject var curationService: ClusterCurationService
    @Environment(\.dismiss) private var dismiss
    
    @State private var sortedPhotos: [Photo] = []
    @State private var selectedPhoto: Photo?
    @State private var isLoading = true
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2),
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2),
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2)
    ]
    
    var body: some View {
        ZStack {
            // Background - Edge to Edge
            Color(.systemGroupedBackground)
                .ignoresSafeArea(.all)
            
            // Main Content
            VStack(spacing: 0) {
                // Cluster info header
                ClusterMomentsInfoHeader(cluster: cluster, photoCount: sortedPhotos.count)
                    .padding(.horizontal, 16)
                    .padding(.top, 60) // Account for status bar
                
                Divider()
                    .padding(.vertical, 8)
                
                // Photos grid
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else if sortedPhotos.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)
                        
                        Text("No Photos in Cluster")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(sortedPhotos, id: \.id) { photo in
                                ClusterMomentsPhotoThumbnailView(
                                    photo: photo,
                                    photoViewModel: photoViewModel,
                                    onTap: { selectedPhoto = photo }
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            
            // Floating Glass Navigation
            VStack {
                HStack {
                    Spacer()
                    
                    // Glass Done button on the right side
                    GlassDoneButton(action: { dismiss() })
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadSortedPhotos()
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoDetailGalleryView(
                initialPhoto: photo,
                photos: sortedPhotos,
                viewModel: photoViewModel,
                showPhotoCounter: true
            )
        }
    }
    
    private func loadSortedPhotos() async {
        isLoading = true
        let sorted = await curationService.getPhotosInCluster(cluster)
        await MainActor.run {
            self.sortedPhotos = sorted
            self.isLoading = false
        }
    }
}

// MARK: - Cluster Info Header

struct ClusterMomentsInfoHeader: View {
    let cluster: PhotoCluster
    let photoCount: Int
    
    private var timeRangeText: String {
        guard let timeRange = cluster.timeRange else {
            return "Unknown time"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        if Calendar.current.isDate(timeRange.start, inSameDayAs: timeRange.end) {
            // Same day - show date once, then time range
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let dateString = formatter.string(from: timeRange.start)
            
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            let startTime = formatter.string(from: timeRange.start)
            let endTime = formatter.string(from: timeRange.end)
            
            return "\(dateString) • \(startTime) - \(endTime)"
        } else {
            // Different days
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let startString = formatter.string(from: timeRange.start)
            let endString = formatter.string(from: timeRange.end)
            
            return "\(startString) - \(endString)"
        }
    }
    
    private var durationText: String {
        guard let timeRange = cluster.timeRange else {
            return ""
        }
        
        let duration = timeRange.end.timeIntervalSince(timeRange.start)
        
        if duration < 60 {
            return "\(Int(duration))s burst"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m session"
        } else {
            return "\(Int(duration / 3600))h session"
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Photo Session • \(photoCount) Photos")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(timeRangeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if photoCount >= 3 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text("Important")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.2))
                        .cornerRadius(6)
                    }
                    
                    if !durationText.isEmpty {
                        Text(durationText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            
            // Quality distribution bar
            if photoCount > 1 {
                ClusterQualityDistributionBar(photos: cluster.photos)
            }
        }
    }
}

// MARK: - Quality Distribution Bar

struct ClusterQualityDistributionBar: View {
    let photos: [Photo]
    
    private var qualityDistribution: [Float] {
        return photos.map { photo in
            if let score = photo.overallScore?.overall {
                return Float(score)
            }
            return 0.5 // Default score
        }.sorted(by: >)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Photo Quality Distribution")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 2) {
                ForEach(Array(qualityDistribution.enumerated()), id: \.offset) { index, score in
                    Rectangle()
                        .fill(qualityColor(score))
                        .frame(height: 6)
                        .cornerRadius(1)
                }
            }
            .cornerRadius(3)
        }
    }
    
    private func qualityColor(_ score: Float) -> Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// MARK: - Cluster Photo Thumbnail View (Clean - No Score Overlays)

struct ClusterMomentsPhotoThumbnailView: View {
    let photo: Photo
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    let onTap: () -> Void
    
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
                    .fill(.quaternary)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundStyle(.secondary)
                    }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 20))
                    }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .cornerRadius(8)
        // No score overlays - clean view
        .onTapGesture {
            onTap()
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task {
            isLoading = true
            let image = await photoViewModel.loadThumbnail(for: photo)
            await MainActor.run {
                self.thumbnailImage = image
                self.isLoading = false
            }
        }
    }
}


// MARK: - Photo Item for fullScreenCover


// MARK: - Preview

#Preview {
    ClusterMomentsDetailView(
        cluster: PhotoCluster(),
        photoViewModel: PhotoLibraryViewModel.preview,
        curationService: ClusterCurationService()
    )
}