import SwiftUI

struct PhotoClusteringView: View {
    @StateObject private var clusteringViewModel = PhotoClusteringViewModel()
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSegment = 0
    @State private var showingClusterDetails = false
    @State private var selectedCluster: PhotoCluster?
    @State private var sortOption: ClusterSortOption = .bySize
    
    private let segments = ["Clusters", "Recommended", "Statistics"]
    
    enum ClusterSortOption: String, CaseIterable {
        case bySize = "Size"
        case byTime = "Time"
        case byQuality = "Quality"
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if clusteringViewModel.isClustering {
                    ClusteringProgressView(viewModel: clusteringViewModel)
                } else if clusteringViewModel.clusters.isEmpty {
                    ClusteringStartView(clusteringViewModel: clusteringViewModel, photoViewModel: photoViewModel)
                } else {
                    VStack {
                        // Segmented control
                        Picker("View", selection: $selectedSegment) {
                            ForEach(0..<segments.count, id: \.self) { index in
                                Text(segments[index]).tag(index)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        // Content based on selected segment
                        TabView(selection: $selectedSegment) {
                            ClustersView(
                                clusteringViewModel: clusteringViewModel,
                                photoViewModel: photoViewModel,
                                sortOption: $sortOption
                            )
                            .tag(0)
                            
                            RecommendedPhotosView(
                                clusteringViewModel: clusteringViewModel,
                                photoViewModel: photoViewModel
                            )
                            .tag(1)
                            
                            ClusteringStatisticsView(viewModel: clusteringViewModel)
                                .tag(2)
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    }
                }
            }
            .navigationTitle("Photo Clustering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if !clusteringViewModel.clusters.isEmpty && !clusteringViewModel.isClustering {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Re-cluster") {
                            Task {
                                await clusteringViewModel.refreshClustering(for: photoViewModel.photos)
                            }
                        }
                    }
                }
            }
            .alert("Clustering Error", isPresented: .constant(clusteringViewModel.errorMessage != nil)) {
                Button("OK") {
                    clusteringViewModel.clearError()
                }
            } message: {
                Text(clusteringViewModel.errorMessage ?? "")
            }
            .sheet(item: $selectedCluster) { cluster in
                ClusterDetailView(cluster: cluster, photoViewModel: photoViewModel)
            }
        }
        .onReceive(clusteringViewModel.$selectedCluster) { cluster in
            selectedCluster = cluster
            showingClusterDetails = cluster != nil
        }
    }
}

// MARK: - Clustering Progress View

struct ClusteringProgressView: View {
    @ObservedObject var viewModel: PhotoClusteringViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.3.layers.3d.down.right")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .symbolEffect(.pulse, isActive: viewModel.isClustering)
            
            VStack(spacing: 12) {
                Text("Clustering Your Photos")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(viewModel.clusteringText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 8) {
                ProgressView(value: viewModel.clusteringProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 8)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                Text("\(Int(viewModel.clusteringProgress * 100))% Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Clustering Start View

struct ClusteringStartView: View {
    let clusteringViewModel: PhotoClusteringViewModel
    let photoViewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "square.3.layers.3d.down.right")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text("Cluster Your Photos")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Use AI to group your \(photoViewModel.photos.count) photos by visual similarity, time, and location. Discover unique moments and eliminate duplicates.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await clusteringViewModel.clusterPhotos(photoViewModel.photos)
                    }
                }) {
                    Text("Start Clustering")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                
                Text("This will analyze visual similarity, timestamps, and locations to group related photos together.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Clusters View

struct ClustersView: View {
    @ObservedObject var clusteringViewModel: PhotoClusteringViewModel
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Binding var sortOption: PhotoClusteringView.ClusterSortOption
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 4)
    ]
    
    var sortedClusters: [PhotoCluster] {
        switch sortOption {
        case .bySize:
            return clusteringViewModel.sortedClustersBySize()
        case .byTime:
            return clusteringViewModel.sortedClustersByTime()
        case .byQuality:
            return clusteringViewModel.sortedClustersByQuality()
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sort picker
            HStack {
                Text("Sort by:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Sort", selection: $sortOption) {
                    ForEach(PhotoClusteringView.ClusterSortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding(.horizontal)
            
            // Cluster summary
            if let stats = clusteringViewModel.statistics {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(stats.totalClusters) Clusters")
                            .font(.headline)
                        Text("Avg: \(String(format: "%.1f", stats.averageClusterSize)) photos/cluster")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("\(clusteringViewModel.multiPhotoClusters) Multi-photo")
                            .font(.subheadline)
                        Text("\(clusteringViewModel.singletonClusters) Singles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // Clusters grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(sortedClusters) { cluster in
                        ClusterThumbnailView(
                            cluster: cluster,
                            photoViewModel: photoViewModel
                        ) {
                            clusteringViewModel.selectedCluster = cluster
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Cluster Thumbnail View

struct ClusterThumbnailView: View {
    let cluster: PhotoCluster
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    let onTap: () -> Void
    
    @State private var thumbnailImages: [UIImage] = []
    @State private var isLoading = true
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Cluster thumbnail preview
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(1, contentMode: .fit)
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        // Show up to 4 thumbnails in a grid
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 1),
                            GridItem(.flexible(), spacing: 1)
                        ], spacing: 1) {
                            ForEach(Array(thumbnailImages.prefix(4).enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipped()
                            }
                        }
                    }
                    
                    // Cluster size badge
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(cluster.photos.count)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                                .padding(4)
                        }
                        Spacer()
                    }
                }
                .cornerRadius(8)
                
                // Cluster info
                VStack(spacing: 2) {
                    Text("\(cluster.photos.count) photos")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    if let timeRange = cluster.timeRange {
                        Text(timeRange.start.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadThumbnails()
        }
    }
    
    private func loadThumbnails() {
        Task {
            isLoading = true
            var images: [UIImage] = []
            
            // Load thumbnails for first 4 photos in cluster
            for photo in Array(cluster.photos.prefix(4)) {
                if let thumbnail = await photoViewModel.loadThumbnail(for: photo) {
                    images.append(thumbnail)
                }
            }
            
            await MainActor.run {
                self.thumbnailImages = images
                self.isLoading = false
            }
        }
    }
}

// MARK: - Recommended Photos View

struct RecommendedPhotosView: View {
    @ObservedObject var clusteringViewModel: PhotoClusteringViewModel
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2),
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2),
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Best photos from each cluster
                VStack(alignment: .leading, spacing: 12) {
                    Text("Best from Each Group")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    let recommendedPhotos = clusteringViewModel.getRecommendedPhotos(count: 10)
                    
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(recommendedPhotos) { photo in
                            RecommendedPhotoThumbnailView(photo: photo, photoViewModel: photoViewModel)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                
                // Diverse selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Diverse Selection")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    let diversePhotos = clusteringViewModel.getDiverseRecommendations(count: 8)
                    
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(diversePhotos) { photo in
                            RecommendedPhotoThumbnailView(photo: photo, photoViewModel: photoViewModel)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                
                // Multi-photo clusters (potential duplicates)
                if clusteringViewModel.multiPhotoClusters > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Similar Photo Groups (\(clusteringViewModel.multiPhotoClusters) groups)")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(Array(clusteringViewModel.clustersWithMinPhotos(2).prefix(5))) { cluster in
                            SimilarClusterRowView(cluster: cluster, photoViewModel: photoViewModel)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Recommended Photo Thumbnail View

struct RecommendedPhotoThumbnailView: View {
    let photo: Photo
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
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
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .cornerRadius(8)
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

// MARK: - Similar Cluster Row View

struct SimilarClusterRowView: View {
    let cluster: PhotoCluster
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(cluster.photos.count) similar photos")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cluster.photos) { photo in
                        RecommendedPhotoThumbnailView(photo: photo, photoViewModel: photoViewModel)
                            .frame(width: 80, height: 80)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Clustering Statistics View

struct ClusteringStatisticsView: View {
    @ObservedObject var viewModel: PhotoClusteringViewModel
    
    var body: some View {
        List {
            if let stats = viewModel.statistics {
                Section("Clustering Overview") {
                    StatRow(title: "Total Clusters", value: "\(stats.totalClusters)")
                    StatRow(title: "Total Photos", value: "\(stats.totalPhotos)")
                    StatRow(title: "Average Cluster Size", value: String(format: "%.1f photos", stats.averageClusterSize))
                    StatRow(title: "Largest Cluster", value: "\(stats.largestClusterSize) photos")
                }
                
                Section("Distribution") {
                    ForEach(Array(viewModel.clusterSizeDistribution.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        StatRow(title: key, value: "\(value) clusters")
                    }
                }
                
                Section("Efficiency") {
                    StatRow(title: "Multi-photo Clusters", value: "\(viewModel.multiPhotoClusters)")
                    StatRow(title: "Single Photo Clusters", value: "\(viewModel.singletonClusters)")
                    
                    let compressionRatio = stats.totalPhotos > 0 ? Double(stats.totalClusters) / Double(stats.totalPhotos) : 0
                    StatRow(title: "Compression Ratio", value: String(format: "%.1f%%", compressionRatio * 100))
                }
                
                Section("Time Analysis") {
                    let timeStats = viewModel.timeSpanStatistics
                    StatRow(title: "Shortest Time Span", value: formatTimeInterval(timeStats.shortest))
                    StatRow(title: "Longest Time Span", value: formatTimeInterval(timeStats.longest))
                    StatRow(title: "Average Time Span", value: formatTimeInterval(timeStats.average))
                }
            }
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            return "\(Int(interval/60))m"
        } else {
            return String(format: "%.1fh", interval/3600)
        }
    }
}

// MARK: - Cluster Detail View

struct ClusterDetailView: View {
    let cluster: PhotoCluster
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Cluster info
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(cluster.photos.count) Photos")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let timeRange = cluster.timeRange {
                        Label(timeRange.start.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if cluster.centerLocation != nil {
                        Label("Location data available", systemImage: "location")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // Photos grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(cluster.photos) { photo in
                            RecommendedPhotoThumbnailView(photo: photo, photoViewModel: photoViewModel)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .navigationTitle("Photo Cluster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoClusteringView(photoViewModel: PhotoLibraryViewModel.preview)
}