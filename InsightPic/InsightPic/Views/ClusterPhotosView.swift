import SwiftUI

struct ClusterPhotosView: View {
    @StateObject private var clusteringViewModel = PhotoClusteringViewModel()
    @StateObject private var curationService = ClusterCurationService()
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var hasEverAnalyzed = false
    @State private var isCheckingForExistingResults = true
    @State private var clusterRepresentatives: [ClusterRepresentative] = []
    @State private var selectedCluster: PhotoCluster?
    
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
            if isCheckingForExistingResults {
                // Checking state
                ProgressView()
                    .scaleEffect(1.2)
                    .foregroundStyle(.secondary)
            } else if !hasEverAnalyzed {
                // Onboarding state - never analyzed before
                ClusterPhotosOnboardingView(clusteringViewModel: clusteringViewModel, photoViewModel: photoViewModel)
            } else if clusteringViewModel.isClustering {
                // Analysis in progress
                ClusterPhotosAnalysisView(clusteringViewModel: clusteringViewModel)
            } else {
                // Results view with cluster representatives
                ClusterPhotosResultsView(
                    clusterRepresentatives: clusterRepresentatives,
                    photoViewModel: photoViewModel,
                    columns: columns,
                    onClusterTap: { cluster in
                        selectedCluster = cluster
                    }
                )
            }
            
            // Floating Glass Navigation
            VStack {
                HStack {
                    // Glass Done button
                    GlassDoneButton(action: { dismiss() })
                    
                    Spacer()
                    
                    // Glass Refresh button (when results exist)
                    if hasEverAnalyzed && !clusteringViewModel.clusters.isEmpty && !clusteringViewModel.isClustering {
                        GlassRefreshButton(action: {
                            Task {
                                await refreshAnalysis()
                            }
                        })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Spacer()
            }
        }
        .navigationBarHidden(true) // Hide navigation bar for edge-to-edge effect
        .task {
            await checkForExistingResults()
        }
        .onChange(of: clusteringViewModel.isClustering) { _, isClustering in
            // When clustering completes and we have results, auto-transition to results view
            if !isClustering && !clusteringViewModel.clusters.isEmpty {
                Task {
                    await loadClusterRepresentatives()
                    if !hasEverAnalyzed {
                        hasEverAnalyzed = true
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedCluster) { cluster in
            ClusterMomentsDetailView(cluster: cluster, photoViewModel: photoViewModel, curationService: curationService)
        }
    }
    
    private func refreshAnalysis() async {
        await clusteringViewModel.clusterPhotos(photoViewModel.photos, saveResults: true)
    }
    
    private func checkForExistingResults() async {
        // Quick check using UserDefaults cache first
        let cachedHasAnalyzed = UserDefaults.standard.bool(forKey: "hasEverAnalyzedPhotos")
        
        await MainActor.run {
            hasEverAnalyzed = cachedHasAnalyzed
            isCheckingForExistingResults = false
        }
        
        // If we have cached results, load cluster representatives in background
        if cachedHasAnalyzed {
            await loadClusterRepresentatives()
        }
    }
    
    private func loadClusterRepresentatives() async {
        do {
            // Load clusters from existing analysis
            let existingClusters = try await clusteringViewModel.loadExistingClusters()
            await MainActor.run {
                clusteringViewModel.clusters = existingClusters
            }
            
            // Generate cluster representatives
            let representatives = await curationService.curateClusterRepresentatives(from: existingClusters)
            
            await MainActor.run {
                self.clusterRepresentatives = representatives
            }
            
        } catch {
            // If loading fails, will need to run analysis
            await MainActor.run {
                hasEverAnalyzed = false
            }
        }
    }
}

// MARK: - Onboarding View

struct ClusterPhotosOnboardingView: View {
    let clusteringViewModel: PhotoClusteringViewModel
    let photoViewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "circle.grid.2x2.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Color.purple)
                }
                
                // Title and description
                VStack(spacing: 12) {
                    Text("Discover Important Moments")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    
                    Text("AI will analyze your \(photoViewModel.photos.count) photos to find important moments where you took multiple photos, then show you the best photo from each moment.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }
            
            // Features list
            VStack(spacing: 16) {
                FeatureRow(icon: "camera.burst", title: "Burst Detection", description: "Groups photos taken within 5 seconds")
                FeatureRow(icon: "brain.head.profile", title: "Smart Similarity", description: "Uses AI to identify visually similar photos")
                FeatureRow(icon: "star.bubble", title: "Moment Ranking", description: "Larger clusters indicate more important moments")
            }
            
            Spacer()
            
            // Action button
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await clusteringViewModel.loadOrCreateClusters(for: photoViewModel.photos)
                    }
                }) {
                    Text("Find Important Moments")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.purple)
                        .cornerRadius(12)
                }
                
                Text("This process may take a few minutes depending on your library size.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }
}

// MARK: - Analysis Progress View

struct ClusterPhotosAnalysisView: View {
    @ObservedObject var clusteringViewModel: PhotoClusteringViewModel
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.purple)
                    .symbolEffect(.pulse, isActive: clusteringViewModel.isClustering)
            }
            
            VStack(spacing: 16) {
                Text("Finding Important Moments")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(clusteringViewModel.clusteringText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 12) {
                    ProgressView(value: clusteringViewModel.clusteringProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.purple))
                        .frame(maxWidth: 280)
                        .scaleEffect(y: 1.5)
                    
                    Text("\(Int(clusteringViewModel.clusteringProgress * 100))% Complete")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Results View

struct ClusterPhotosResultsView: View {
    let clusterRepresentatives: [ClusterRepresentative]
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    let columns: [GridItem]
    let onClusterTap: (PhotoCluster) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Results header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(clusterRepresentatives.count) Important Moments")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    let totalPhotos = clusterRepresentatives.reduce(0) { $0 + $1.clusterSize }
                    Text("\(totalPhotos) photos in \(clusterRepresentatives.count) clusters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            // Cluster grid
            ScrollView {
                if clusterRepresentatives.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "circle.grid.2x2")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)
                        
                        VStack(spacing: 4) {
                            Text("No Important Moments Found")
                                .font(.headline)
                            
                            Text("Try taking more photos or analyzing a larger library")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(clusterRepresentatives, id: \.id) { representative in
                            ClusterThumbnailView(
                                representative: representative,
                                photoViewModel: photoViewModel,
                                onTap: { onClusterTap(representative.cluster) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

// MARK: - Cluster Thumbnail View (without score overlays)

struct ClusterThumbnailView: View {
    let representative: ClusterRepresentative
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
        .overlay(
            // Clean cluster info badge (no scores)
            VStack {
                HStack {
                    Spacer()
                    
                    // Cluster size badge
                    Text("\(representative.clusterSize)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.7))
                        .cornerRadius(4)
                        .padding(4)
                }
                Spacer()
                
                // Importance indicator
                if representative.isImportantMoment {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                            .padding(2)
                            .background(.black.opacity(0.7))
                            .cornerRadius(2)
                        Spacer()
                    }
                    .padding(4)
                }
            }
        )
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
            let image = await photoViewModel.loadThumbnail(for: representative.bestPhoto)
            await MainActor.run {
                self.thumbnailImage = image
                self.isLoading = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ClusterPhotosView(photoViewModel: PhotoLibraryViewModel.preview)
}