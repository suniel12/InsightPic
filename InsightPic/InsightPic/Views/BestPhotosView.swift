import SwiftUI

struct CuratedBestPhotosView: View {
    @StateObject private var clusteringViewModel = PhotoClusteringViewModel()
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var hasEverAnalyzed = false
    @State private var isCheckingForExistingResults = true
    
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
                BestPhotosOnboardingView(clusteringViewModel: clusteringViewModel, photoViewModel: photoViewModel)
            } else if clusteringViewModel.isClustering {
                // Analysis in progress
                BestPhotosAnalysisView(clusteringViewModel: clusteringViewModel)
            } else {
                // Results view
                BestPhotosResultsView(clusteringViewModel: clusteringViewModel, photoViewModel: photoViewModel, columns: columns)
            }
            
            // Floating Glass Navigation
            VStack {
                HStack {
                    // Glass Done button
                    GlassDoneButton(action: { dismiss() })
                    
                    Spacer()
                    
                    Text("Best Photos")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // Glass Refresh button (when results exist)
                    if hasEverAnalyzed && !clusteringViewModel.clusters.isEmpty && !clusteringViewModel.isClustering {
                        GlassRefreshButton(action: {
                            Task {
                                await clusteringViewModel.clusterPhotos(photoViewModel.photos, saveResults: true)
                            }
                        })
                    } else {
                        // Placeholder to maintain spacing
                        Color.clear
                            .frame(width: 44, height: 44)
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
            if !isClustering && !clusteringViewModel.clusters.isEmpty && !hasEverAnalyzed {
                hasEverAnalyzed = true
            }
        }
    }
    
    private func checkForExistingResults() async {
        // Check if we have any existing cluster results
        do {
            let existingClusters = try await clusteringViewModel.loadExistingClusters()
            await MainActor.run {
                hasEverAnalyzed = !existingClusters.isEmpty
                if hasEverAnalyzed {
                    clusteringViewModel.clusters = existingClusters
                    clusteringViewModel.statistics = ClusteringStatistics(clusters: existingClusters)
                }
                isCheckingForExistingResults = false
            }
        } catch {
            await MainActor.run {
                hasEverAnalyzed = false
                isCheckingForExistingResults = false
            }
        }
    }
}

// MARK: - Onboarding View

struct BestPhotosOnboardingView: View {
    let clusteringViewModel: PhotoClusteringViewModel
    let photoViewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                
                // Title and description
                VStack(spacing: 12) {
                    Text("Find Your Best Photos")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    
                    Text("AI will analyze your \(photoViewModel.photos.count) photos to find the highest quality images and eliminate duplicates.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }
            
            // Features list
            VStack(spacing: 16) {
                FeatureRow(icon: "sparkles", title: "Smart Quality Analysis", description: "Technical quality, composition, and facial recognition")
                FeatureRow(icon: "photo.stack", title: "Duplicate Detection", description: "Groups similar photos and picks the best from each")
                FeatureRow(icon: "eye.slash", title: "Screenshot Filtering", description: "Automatically excludes screenshots and screen recordings")
            }
            
            Spacer()
            
            // Action button
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await clusteringViewModel.loadOrCreateClusters(for: photoViewModel.photos)
                    }
                }) {
                    Text("Find Best Photos")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
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

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Analysis Progress View

struct BestPhotosAnalysisView: View {
    @ObservedObject var clusteringViewModel: PhotoClusteringViewModel
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "heart.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, isActive: clusteringViewModel.isClustering)
            }
            
            VStack(spacing: 16) {
                Text("Analyzing Your Photos")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(clusteringViewModel.clusteringText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 12) {
                    ProgressView(value: clusteringViewModel.clusteringProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.accentColor))
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

struct BestPhotosResultsView: View {
    @ObservedObject var clusteringViewModel: PhotoClusteringViewModel
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    let columns: [GridItem]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 32) {
                // Header stats
                if let stats = clusteringViewModel.statistics {
                    VStack(spacing: 8) {
                        Text("Found \(clusteringViewModel.getRecommendedPhotos(count: 20).count) best photos")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("From \(stats.totalPhotos) photos in \(stats.totalClusters) groups")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                
                // Best photos grid
                let recommendedPhotos = clusteringViewModel.getRecommendedPhotos(count: 20)
                
                if !recommendedPhotos.isEmpty {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(recommendedPhotos) { photo in
                            CuratedPhotoThumbnailView(photo: photo, photoViewModel: photoViewModel)
                        }
                    }
                    .padding(.horizontal, 8)
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)
                        
                        VStack(spacing: 4) {
                            Text("No Best Photos Found")
                                .font(.headline)
                            
                            Text("Try analyzing more photos or adjusting quality settings")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Best Photo Thumbnail View

struct CuratedPhotoThumbnailView: View {
    let photo: Photo
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
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
            // Quality indicator
            VStack {
                HStack {
                    Spacer()
                    if let score = photo.overallScore?.overall {
                        Text("\(Int(score * 100))%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(4)
                    }
                }
                Spacer()
            }
        )
        .onTapGesture {
            showingDetailView = true
        }
        .fullScreenCover(isPresented: $showingDetailView) {
            PhotoDetailView(photo: photo, viewModel: photoViewModel)
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

// MARK: - Glass Navigation Components

struct GlassDoneButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(
                    ZStack {
                        // Glass background effect
                        Circle()
                            .fill(.ultraThinMaterial)
                        
                        // Subtle border
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    }
                )
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GlassRefreshButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(
                    ZStack {
                        // Glass background effect
                        Circle()
                            .fill(.ultraThinMaterial)
                        
                        // Subtle border
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    }
                )
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    CuratedBestPhotosView(photoViewModel: PhotoLibraryViewModel.preview)
}