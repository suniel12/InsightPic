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
    @State private var debugCluster: PhotoCluster?
    @State private var perfectMomentCluster: PhotoCluster?
    @State private var showingRankingDetail: ClusterRepresentative?
    
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
            } else if clusteringViewModel.isClustering {
                // Analysis in progress (both first-time and refresh)
                ClusterPhotosAnalysisView(clusteringViewModel: clusteringViewModel)
            } else if !hasEverAnalyzed {
                // Onboarding state - never analyzed before
                ClusterPhotosOnboardingView(clusteringViewModel: clusteringViewModel, photoViewModel: photoViewModel)
            } else {
                // Results view with cluster representatives
                ClusterPhotosResultsView(
                    clusterRepresentatives: clusterRepresentatives,
                    photoViewModel: photoViewModel,
                    columns: columns,
                    onClusterTap: { cluster in
                        selectedCluster = cluster
                    },
                    onDebugTap: { cluster in
                        debugCluster = cluster
                    },
                    onPerfectMomentTap: { cluster in
                        perfectMomentCluster = cluster
                    },
                    onRankingDetailTap: { representative in
                        showingRankingDetail = representative
                    }
                )
            }
            
            // Floating Glass Navigation
            VStack {
                HStack {
                    Spacer()
                    
                    // Glass buttons on the right side
                    HStack(spacing: 12) {
                        // Glass Refresh button (when results exist)
                        if hasEverAnalyzed && !clusteringViewModel.clusters.isEmpty && !clusteringViewModel.isClustering {
                            GlassRefreshButton(action: {
                                Task {
                                    await refreshAnalysis()
                                }
                            })
                        }
                        
                        // Glass Done button
                        GlassDoneButton(action: { dismiss() })
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
                    // Always load cluster representatives when clustering completes
                    await loadClusterRepresentatives()
                    
                    await MainActor.run {
                        if !hasEverAnalyzed {
                            // First-time clustering: Update state and show results permanently
                            hasEverAnalyzed = true
                            print("DEBUG: First-time clustering complete - showing results permanently")
                        } else {
                            // Refresh clustering: Show results permanently (same as first-time)
                            print("DEBUG: Refresh clustering complete - showing results permanently")
                        }
                        
                        // Both first-time and refresh: Stay in results view permanently
                        // User can manually dismiss using cross button when ready
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedCluster) { cluster in
            ClusterMomentsDetailView(cluster: cluster, photoViewModel: photoViewModel, curationService: curationService)
        }
        .sheet(item: $debugCluster) { cluster in
            FaceAnalysisDebugView(cluster: cluster, photoViewModel: photoViewModel)
        }
        .fullScreenCover(item: $perfectMomentCluster) { cluster in
            PerfectMomentGeneratorView(cluster: cluster)
        }
        .sheet(item: $showingRankingDetail) { representative in
            ClusterRankingDetailView(representative: representative)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    private func refreshAnalysis() async {
        // Use the exact same method as first-time clustering for identical UI flow
        await clusteringViewModel.loadOrCreateClusters(for: photoViewModel.photos)
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
                    
                    Text("AI will analyze your \(photoViewModel.photos.count) photos using visual similarity, timing, and face recognition to create smart groups that separate different people and photo sessions.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }
            
            // Features list
            VStack(spacing: 16) {
                FeatureRow(icon: "clock", title: "Rolling Window", description: "Groups photos taken within 30 seconds of each other")
                FeatureRow(icon: "person.2.fill", title: "Face-Aware", description: "Separates different people into different clusters")
                FeatureRow(icon: "brain.head.profile", title: "Smart Similarity", description: "Keeps visually similar photos together (≥50%)")
            }
            
            Spacer()
            
            // Action button
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await clusteringViewModel.loadOrCreateClusters(for: photoViewModel.photos)
                    }
                }) {
                    Text("Group Photo Sessions")
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
                Text("Grouping Photo Sessions")
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
    let onDebugTap: ((PhotoCluster) -> Void)?
    let onPerfectMomentTap: ((PhotoCluster) -> Void)?
    let onRankingDetailTap: (ClusterRepresentative) -> Void
    
    @State private var sortOption: ClusterSortOption = .qualityDescending
    @State private var showingSortOptions = false
    
    // MARK: - Computed Properties (Task 3.4)
    
    /// Sorted cluster representatives based on selected sort option
    private var sortedRepresentatives: [ClusterRepresentative] {
        switch sortOption {
        case .qualityDescending:
            return clusterRepresentatives.sorted { $0.combinedQualityScore > $1.combinedQualityScore }
        case .qualityAscending:
            return clusterRepresentatives.sorted { $0.combinedQualityScore < $1.combinedQualityScore }
        case .facialQualityDescending:
            return clusterRepresentatives.sorted { $0.facialQualityScore > $1.facialQualityScore }
        case .clusterSizeDescending:
            return clusterRepresentatives.sorted { $0.clusterSize > $1.clusterSize }
        case .clusterSizeAscending:
            return clusterRepresentatives.sorted { $0.clusterSize < $1.clusterSize }
        case .confidenceDescending:
            return clusterRepresentatives.sorted { $0.rankingConfidence > $1.rankingConfidence }
        case .chronological:
            return clusterRepresentatives.sorted { 
                ($0.timeRange?.start ?? Date.distantPast) < ($1.timeRange?.start ?? Date.distantPast)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Results header with sort button (Task 3.4)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(clusterRepresentatives.count) Photo Sessions")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    let totalPhotos = clusterRepresentatives.reduce(0) { $0 + $1.clusterSize }
                    Text("\(totalPhotos) photos in \(clusterRepresentatives.count) clusters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Sort button
                Button(action: {
                    showingSortOptions = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortOption.shortName)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(6)
                }
                .confirmationDialog("Sort Clusters", isPresented: $showingSortOptions) {
                    ForEach(ClusterSortOption.allCases, id: \.self) { option in
                        Button(option.displayName) {
                            sortOption = option
                        }
                    }
                }
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
                            Text("No Photo Sessions Found")
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
                        ForEach(sortedRepresentatives, id: \.id) { representative in
                            ClusterThumbnailView(
                                representative: representative,
                                photoViewModel: photoViewModel,
                                onTap: { onClusterTap(representative.cluster) },
                                onDebugTap: onDebugTap != nil ? { onDebugTap!(representative.cluster) } : nil,
                                onPerfectMomentTap: onPerfectMomentTap != nil ? { onPerfectMomentTap!(representative.cluster) } : nil,
                                onRankingDetailTap: { onRankingDetailTap(representative) }
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
    let onDebugTap: (() -> Void)?
    let onPerfectMomentTap: (() -> Void)?
    let onRankingDetailTap: () -> Void
    
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
            // Enhanced cluster info with ranking indicators
            VStack {
                HStack {
                    // Best Photo Badge (Task 3.2)
                    if representative.rankingConfidence > 0.8 {
                        HStack(spacing: 2) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                            Text("BEST")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.9))
                        .cornerRadius(3)
                        .padding(3)
                    }
                    
                    // Debug button (if callback provided)
                    if let onDebugTap = onDebugTap {
                        Button(action: onDebugTap) {
                            Image(systemName: "face.dashed")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                                .padding(3)
                                .background(.black.opacity(0.7))
                                .cornerRadius(3)
                        }
                        .padding(4)
                    }
                    
                    Spacer()
                    
                    // Enhanced cluster size badge with quality indicator
                    VStack(spacing: 1) {
                        Text("\(representative.clusterSize)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        // Quality rank indicator (Task 3.1)
                        HStack(spacing: 1) {
                            ForEach(0..<5, id: \.self) { index in
                                Circle()
                                    .fill(index < Int(representative.qualityScore * 5) ? .yellow : .gray.opacity(0.3))
                                    .frame(width: 3, height: 3)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.8))
                    .cornerRadius(4)
                    .padding(4)
                }
                Spacer()
                
                // Bottom indicators with enhanced ranking info
                HStack {
                    // Importance indicator
                    if representative.isImportantMoment {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                            .padding(2)
                            .background(.black.opacity(0.7))
                            .cornerRadius(2)
                    }
                    
                    // Facial quality indicator (Task 3.1)
                    if representative.facialQualityScore > 0.7 {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                            .padding(2)
                            .background(.black.opacity(0.7))
                            .cornerRadius(2)
                    }
                    
                    // Selection reason indicator (Task 3.1)
                    selectionReasonIcon
                        .font(.system(size: 8))
                        .foregroundColor(selectionReasonColor)
                        .padding(2)
                        .background(.black.opacity(0.7))
                        .cornerRadius(2)
                    
                    Spacer()
                    
                    // Perfect Moment button (US1.1, US1.2)
                    if let onPerfectMomentTap = onPerfectMomentTap,
                       representative.cluster.perfectMomentEligibility.isEligible {
                        Button(action: onPerfectMomentTap) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(3)
                                .background(.purple.opacity(0.9))
                                .cornerRadius(3)
                        }
                    }
                }
                .padding(4)
            }
        )
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            onRankingDetailTap()
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    // MARK: - Ranking Indicator Helpers (Task 3.1)
    
    /// Icon representing why this photo was selected as representative
    private var selectionReasonIcon: Image {
        switch representative.selectionReason {
        case .highestOverallQuality:
            return Image(systemName: "checkmark.circle")
        case .bestFacialQuality:
            return Image(systemName: "face.smiling")
        case .balancedQualityAndFaces:
            return Image(systemName: "scale.3d")
        case .onlyOptionAvailable:
            return Image(systemName: "1.circle")
        case .fallbackSelection:
            return Image(systemName: "arrow.down.circle")
        case .manualOverride:
            return Image(systemName: "hand.raised")
        }
    }
    
    /// Color for selection reason indicator
    private var selectionReasonColor: Color {
        switch representative.selectionReason {
        case .highestOverallQuality:
            return .green
        case .bestFacialQuality:
            return .blue
        case .balancedQualityAndFaces:
            return .purple
        case .onlyOptionAvailable:
            return .orange
        case .fallbackSelection:
            return .red
        case .manualOverride:
            return .yellow
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

// MARK: - Cluster Ranking Detail View (Task 3.3)

struct ClusterRankingDetailView: View {
    let representative: ClusterRepresentative
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with cluster info
                    VStack(spacing: 8) {
                        Text("Photo Quality Analysis")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("\(representative.clusterSize) photos in cluster")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    // Quality Scores Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quality Breakdown")
                            .font(.headline)
                        
                        // Overall Quality
                        QualityIndicatorRow(
                            title: "Overall Quality",
                            score: representative.qualityScore,
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        // Facial Quality
                        QualityIndicatorRow(
                            title: "Facial Quality",
                            score: representative.facialQualityScore,
                            icon: "face.smiling.fill",
                            color: .blue
                        )
                        
                        // Ranking Confidence
                        QualityIndicatorRow(
                            title: "Selection Confidence",
                            score: representative.rankingConfidence,
                            icon: "target",
                            color: .purple
                        )
                        
                        // Combined Score
                        QualityIndicatorRow(
                            title: "Combined Score",
                            score: representative.combinedQualityScore,
                            icon: "star.fill",
                            color: .orange
                        )
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Selection Reason Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why This Photo Was Selected")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            Image(systemName: selectionReasonIcon)
                                .font(.title2)
                                .foregroundColor(selectionReasonColor)
                                .frame(width: 40, height: 40)
                                .background(selectionReasonColor.opacity(0.1))
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(representative.selectionReason.description)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(selectionReasonExplanation)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Additional Stats
                    if representative.isImportantMoment {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Special Designation")
                                .font(.headline)
                            
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("Important Moment")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            
                            Text("This cluster contains 3+ photos, indicating intentional moment capture.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Ranking Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var selectionReasonIcon: String {
        switch representative.selectionReason {
        case .highestOverallQuality:
            return "checkmark.circle.fill"
        case .bestFacialQuality:
            return "face.smiling.fill"
        case .balancedQualityAndFaces:
            return "scale.3d"
        case .onlyOptionAvailable:
            return "1.circle.fill"
        case .fallbackSelection:
            return "arrow.down.circle.fill"
        case .manualOverride:
            return "hand.raised.fill"
        }
    }
    
    private var selectionReasonColor: Color {
        switch representative.selectionReason {
        case .highestOverallQuality:
            return .green
        case .bestFacialQuality:
            return .blue
        case .balancedQualityAndFaces:
            return .purple
        case .onlyOptionAvailable:
            return .orange
        case .fallbackSelection:
            return .red
        case .manualOverride:
            return .yellow
        }
    }
    
    private var selectionReasonExplanation: String {
        switch representative.selectionReason {
        case .highestOverallQuality:
            return "This photo scored highest across all quality metrics including sharpness, exposure, and composition."
        case .bestFacialQuality:
            return "This photo was selected for having the best facial expressions, including open eyes and natural smiles."
        case .balancedQualityAndFaces:
            return "This photo offers the best balance between technical quality and facial expression quality."
        case .onlyOptionAvailable:
            return "This was the only suitable photo available in this cluster meeting minimum quality standards."
        case .fallbackSelection:
            return "This photo was selected as a fallback when no other options met the quality criteria."
        case .manualOverride:
            return "This photo was manually selected by you, overriding the automatic ranking system."
        }
    }
}

// MARK: - Quality Indicator Row

struct QualityIndicatorRow: View {
    let title: String
    let score: Float
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title)
                .fontWeight(.medium)
            
            Spacer()
            
            // Score bar
            HStack(spacing: 8) {
                ProgressView(value: Double(score), total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: color))
                    .frame(width: 80)
                
                Text("\(Int(score * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                    .frame(width: 35, alignment: .trailing)
            }
        }
    }
}

// MARK: - Cluster Sort Options (Task 3.4)

enum ClusterSortOption: CaseIterable {
    case qualityDescending
    case qualityAscending
    case facialQualityDescending
    case clusterSizeDescending
    case clusterSizeAscending
    case confidenceDescending
    case chronological
    
    var displayName: String {
        switch self {
        case .qualityDescending:
            return "Quality: Best First"
        case .qualityAscending:
            return "Quality: Worst First"
        case .facialQualityDescending:
            return "Facial Quality: Best First"
        case .clusterSizeDescending:
            return "Size: Largest First"
        case .clusterSizeAscending:
            return "Size: Smallest First"
        case .confidenceDescending:
            return "Confidence: Highest First"
        case .chronological:
            return "Date: Oldest First"
        }
    }
    
    var shortName: String {
        switch self {
        case .qualityDescending:
            return "Quality ↓"
        case .qualityAscending:
            return "Quality ↑"
        case .facialQualityDescending:
            return "Faces ↓"
        case .clusterSizeDescending:
            return "Size ↓"
        case .clusterSizeAscending:
            return "Size ↑"
        case .confidenceDescending:
            return "Confidence ↓"
        case .chronological:
            return "Date ↑"
        }
    }
}

// MARK: - Preview

#Preview {
    ClusterPhotosView(photoViewModel: PhotoLibraryViewModel.preview)
}