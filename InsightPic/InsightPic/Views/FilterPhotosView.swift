import SwiftUI

struct FilterPhotosView: View {
    @StateObject private var clusteringViewModel = PhotoClusteringViewModel()
    @StateObject private var filterService = PhotoFilterService()
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var hasEverAnalyzed = false
    @State private var isCheckingForExistingResults = true
    @State private var selectedCategories: Set<PhotoCategory> = []
    @State private var availableCategories: [PhotoCategory: Int] = [:]
    @State private var analysisResults: [PhotoAnalysisResult] = []
    @State private var filteredPhotos: [FilteredPhoto] = []
    
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
                FilterPhotosOnboardingView(clusteringViewModel: clusteringViewModel, photoViewModel: photoViewModel)
            } else if clusteringViewModel.isClustering {
                // Analysis in progress
                FilterPhotosAnalysisView(clusteringViewModel: clusteringViewModel)
            } else {
                // Results view with category filtering
                FilterPhotosResultsView(
                    filteredPhotos: filteredPhotos,
                    selectedCategories: selectedCategories,
                    availableCategories: availableCategories,
                    photoViewModel: photoViewModel,
                    columns: columns,
                    onCategoryToggle: { category in
                        toggleCategory(category)
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
                    await loadAnalysisResults()
                    if !hasEverAnalyzed {
                        hasEverAnalyzed = true
                    }
                }
            }
        }
    }
    
    private func toggleCategory(_ category: PhotoCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        updateFilteredPhotos()
    }
    
    private func updateFilteredPhotos() {
        filteredPhotos = filterService.filterPhotos(
            photoViewModel.photos,
            analysisResults: analysisResults,
            selectedCategories: selectedCategories
        )
    }
    
    private func checkForExistingResults() async {
        // Quick check using UserDefaults cache first
        let cachedHasAnalyzed = UserDefaults.standard.bool(forKey: "hasEverAnalyzedPhotos")
        
        await MainActor.run {
            hasEverAnalyzed = cachedHasAnalyzed
            isCheckingForExistingResults = false
        }
        
        // If we have cached results, load analysis data in background
        if cachedHasAnalyzed {
            await loadAnalysisResults()
        }
    }
    
    private func loadAnalysisResults() async {
        do {
            // Load clusters from existing analysis
            let existingClusters = try await clusteringViewModel.loadExistingClusters()
            await MainActor.run {
                clusteringViewModel.clusters = existingClusters
            }
            
            // Extract analysis results from clusters
            var results: [PhotoAnalysisResult] = []
            for cluster in existingClusters {
                for photo in cluster.photos {
                    // Create mock analysis result - in real implementation this would be loaded from persistence
                    if let mockResult = createMockAnalysisResult(for: photo) {
                        results.append(mockResult)
                    }
                }
            }
            
            await MainActor.run {
                self.analysisResults = results
                self.availableCategories = filterService.getAvailableCategories(from: results)
                self.updateFilteredPhotos()
            }
            
        } catch {
            // If loading fails, will need to run analysis
            await MainActor.run {
                hasEverAnalyzed = false
            }
        }
    }
    
    private func refreshAnalysis() async {
        await clusteringViewModel.clusterPhotos(photoViewModel.photos, saveResults: true)
    }
    
    // MARK: - Mock Data Helper (temporary until full integration)
    
    private func createMockAnalysisResult(for photo: Photo) -> PhotoAnalysisResult? {
        // This is a temporary mock - in real implementation, analysis results would be persisted
        let mockObjects = generateMockObjects(for: photo)
        let faces = createMockFaces(for: photo)
        
        return PhotoAnalysisResult(
            photoId: photo.id,
            assetIdentifier: photo.assetIdentifier,
            qualityScore: Double.random(in: 0.3...0.9),
            sharpnessScore: Double.random(in: 0.4...0.9),
            exposureScore: Double.random(in: 0.4...0.9),
            compositionScore: Double.random(in: 0.3...0.8),
            faces: faces,
            objects: mockObjects,
            aestheticScore: Double.random(in: 0.3...0.8),
            timestamp: Date(),
            aestheticAnalysis: nil,
            saliencyAnalysis: nil,
            dominantColors: nil,
            sceneConfidence: Float.random(in: 0.2...0.8)
        )
    }
    
    private func generateMockObjects(for photo: Photo) -> [ObjectAnalysis] {
        // Generate realistic mock objects based on photo characteristics
        var objects: [ObjectAnalysis] = []
        
        // Add face-based objects
        if let faceQuality = photo.faceQuality {
            if faceQuality.faceCount == 1 {
                objects.append(ObjectAnalysis(identifier: "person", confidence: 0.85, boundingBox: CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)))
                objects.append(ObjectAnalysis(identifier: "portrait", confidence: 0.75, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)))
            } else if faceQuality.faceCount > 1 {
                objects.append(ObjectAnalysis(identifier: "group", confidence: 0.80, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)))
                objects.append(ObjectAnalysis(identifier: "people", confidence: 0.85, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)))
            }
        }
        
        // Add random contextual objects
        let possibleObjects = ["outdoor", "indoor", "landscape", "food", "car", "nature", "building", "sky", "tree", "water"]
        let randomObjects = possibleObjects.shuffled().prefix(Int.random(in: 1...3))
        
        for object in randomObjects {
            objects.append(ObjectAnalysis(
                identifier: object,
                confidence: Float.random(in: 0.2...0.7),
                boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)
            ))
        }
        
        return objects
    }
    
    private func createMockFaces(for photo: Photo) -> [FaceAnalysis] {
        guard let faceQuality = photo.faceQuality, faceQuality.faceCount > 0 else {
            return []
        }
        
        var faces: [FaceAnalysis] = []
        for _ in 0..<faceQuality.faceCount {
            faces.append(FaceAnalysis(
                boundingBox: CGRect(x: Double.random(in: 0.1...0.5), y: Double.random(in: 0.1...0.4),
                                  width: Double.random(in: 0.2...0.4), height: Double.random(in: 0.3...0.5)),
                confidence: Float.random(in: 0.7...0.95),
                faceQuality: Double.random(in: 0.5...0.9),
                isSmiling: Bool.random(),
                eyesOpen: Bool.random() ? true : nil,
                landmarks: nil,
                pose: nil,
                recognitionID: nil
            ))
        }
        
        return faces
    }
}

// MARK: - Onboarding View

struct FilterPhotosOnboardingView: View {
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
                    
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                
                // Title and description
                VStack(spacing: 12) {
                    Text("Filter & Sort Your Photos")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    
                    Text("AI will analyze your \(photoViewModel.photos.count) photos and organize them by content so you can find exactly what you're looking for.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                }
            }
            
            // Features list
            VStack(spacing: 16) {
                FeatureRow(icon: "person.3.fill", title: "Content Categories", description: "People, landscapes, food, cars, and more")
                FeatureRow(icon: "slider.horizontal.3", title: "Smart Filtering", description: "Find photos that match what you want to see")
                FeatureRow(icon: "eye.slash", title: "Auto Cleanup", description: "Automatically excludes screenshots and low-quality images")
            }
            
            Spacer()
            
            // Action button
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        await clusteringViewModel.loadOrCreateClusters(for: photoViewModel.photos)
                    }
                }) {
                    Text("Analyze & Filter Photos")
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

// MARK: - Analysis Progress View

struct FilterPhotosAnalysisView: View {
    @ObservedObject var clusteringViewModel: PhotoClusteringViewModel
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
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

struct FilterPhotosResultsView: View {
    let filteredPhotos: [FilteredPhoto]
    let selectedCategories: Set<PhotoCategory>
    let availableCategories: [PhotoCategory: Int]
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    let columns: [GridItem]
    let onCategoryToggle: (PhotoCategory) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Category selection chips
            if !availableCategories.isEmpty {
                CategoryChipsView(
                    availableCategories: availableCategories,
                    selectedCategories: selectedCategories,
                    onCategoryToggle: onCategoryToggle
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            
            // Results header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(filteredPhotos.count) Photos")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if selectedCategories.isEmpty {
                        Text("All photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Matching: \(selectedCategories.map { $0.rawValue }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            // Photos grid
            ScrollView {
                if filteredPhotos.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)
                        
                        VStack(spacing: 4) {
                            Text("No Photos Found")
                                .font(.headline)
                            
                            Text("Try selecting different categories or adjusting your filters")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(filteredPhotos, id: \.photo.id) { filteredPhoto in
                            FilteredPhotoThumbnailView(
                                filteredPhoto: filteredPhoto,
                                photoViewModel: photoViewModel
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

// MARK: - Category Chips View

struct CategoryChipsView: View {
    let availableCategories: [PhotoCategory: Int]
    let selectedCategories: Set<PhotoCategory>
    let onCategoryToggle: (PhotoCategory) -> Void
    
    var sortedCategories: [PhotoCategory] {
        availableCategories.keys.sorted { category1, category2 in
            let count1 = availableCategories[category1] ?? 0
            let count2 = availableCategories[category2] ?? 0
            return count1 > count2
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedCategories, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        count: availableCategories[category] ?? 0,
                        isSelected: selectedCategories.contains(category),
                        onTap: { onCategoryToggle(category) }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: PhotoCategory
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(category.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("(\(count))")
                    .font(.caption2)
                    .opacity(0.8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            )
            .foregroundColor(isSelected ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color(.tertiaryLabel), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Filtered Photo Thumbnail View

struct FilteredPhotoThumbnailView: View {
    let filteredPhoto: FilteredPhoto
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
            // Relevance score and category indicators
            VStack {
                HStack {
                    Spacer()
                    Text("\(Int(filteredPhoto.relevanceScore * 100))%")
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
                
                // Category indicators
                if !filteredPhoto.matchingCategories.isEmpty {
                    HStack {
                        ForEach(Array(filteredPhoto.matchingCategories.prefix(3)), id: \.self) { category in
                            Image(systemName: category.icon)
                                .font(.system(size: 8))
                                .foregroundColor(.white)
                                .padding(2)
                                .background(.black.opacity(0.7))
                                .cornerRadius(2)
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
        )
        .onTapGesture {
            showingDetailView = true
        }
        .fullScreenCover(isPresented: $showingDetailView) {
            PhotoDetailView(photo: filteredPhoto.photo, viewModel: photoViewModel)
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task {
            isLoading = true
            let image = await photoViewModel.loadThumbnail(for: filteredPhoto.photo)
            await MainActor.run {
                self.thumbnailImage = image
                self.isLoading = false
            }
        }
    }
}