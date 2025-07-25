import SwiftUI

struct PhotoAnalysisDataView: View {
    @StateObject private var filterService = PhotoFilterService()
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPhoto: Photo?
    @State private var analysisResults: [PhotoAnalysisResult] = []
    @State private var isLoading = true
    @State private var selectedCategories: Set<PhotoCategory> = []
    @State private var searchText = ""
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 4)
    ]
    
    var filteredPhotos: [Photo] {
        let photos = photoViewModel.photos
        
        if searchText.isEmpty {
            return photos
        } else {
            // Filter photos that have analysis results matching search term
            return photos.filter { photo in
                if let result = analysisResults.first(where: { $0.photoId == photo.id }) {
                    return result.objects.contains { object in
                        object.identifier.lowercased().contains(searchText.lowercased())
                    }
                }
                return false
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left Panel - Photo Grid
                VStack(spacing: 0) {
                    // Search and filter controls
                    VStack(spacing: 12) {
                        SearchBar(text: $searchText)
                        
                        if !analysisResults.isEmpty {
                            CategoryFilterView(
                                availableCategories: getAvailableCategories(),
                                selectedCategories: selectedCategories,
                                onCategoryToggle: { category in
                                    toggleCategory(category)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    Divider()
                    
                    // Photo grid
                    ScrollView {
                        if isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                
                                Text("Loading analysis data...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 60)
                        } else if filteredPhotos.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundStyle(.tertiary)
                                
                                Text("No Photos Found")
                                    .font(.headline)
                                
                                Text("Try adjusting your search or filters")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 60)
                        } else {
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(filteredPhotos) { photo in
                                    PhotoThumbnailGridItem(
                                        photo: photo,
                                        isSelected: selectedPhoto?.id == photo.id,
                                        analysisResult: analysisResults.first { $0.photoId == photo.id },
                                        photoViewModel: photoViewModel,
                                        onTap: { selectedPhoto = photo }
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 16)
                        }
                    }
                }
                .frame(width: 280)
                .background(Color(.systemGroupedBackground))
                
                Divider()
                
                // Right Panel - Analysis Details
                VStack(spacing: 0) {
                    if let selectedPhoto = selectedPhoto {
                        PhotoAnalysisDetailPanel(
                            photo: selectedPhoto,
                            analysisResult: analysisResults.first { $0.photoId == selectedPhoto.id },
                            selectedCategories: selectedCategories,
                            filterService: filterService,
                            photoViewModel: photoViewModel
                        )
                    } else {
                        // Empty state for analysis panel
                        VStack(spacing: 20) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 64, weight: .light))
                                .foregroundStyle(.tertiary)
                            
                            VStack(spacing: 8) {
                                Text("Select a Photo")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                
                                Text("Choose a photo from the grid to see detailed analysis data")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Analysis Data Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Refresh Analysis") {
                            Task {
                                await loadAnalysisData()
                            }
                        }
                        
                        Button("Export Data") {
                            // TODO: Export analysis data
                        }
                        
                        Button("Clear Filters") {
                            selectedCategories.removeAll()
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await loadAnalysisData()
            }
        }
    }
    
    private func toggleCategory(_ category: PhotoCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }
    
    private func getAvailableCategories() -> [PhotoCategory: Int] {
        return filterService.getAvailableCategories(from: analysisResults)
    }
    
    private func loadAnalysisData() async {
        await MainActor.run {
            isLoading = true
        }
        
        // Load or create analysis results for all photos
        var results: [PhotoAnalysisResult] = []
        
        for photo in photoViewModel.photos {
            // For now, use mock data - in real implementation this would load from persistence
            if let mockResult = createMockAnalysisResult(for: photo) {
                results.append(mockResult)
            }
        }
        
        await MainActor.run {
            self.analysisResults = results
            self.isLoading = false
            
            // Auto-select first photo if none selected
            if selectedPhoto == nil && !photoViewModel.photos.isEmpty {
                selectedPhoto = photoViewModel.photos.first
            }
        }
    }
    
    // MARK: - Mock Data Helper (temporary until full integration)
    
    private func createMockAnalysisResult(for photo: Photo) -> PhotoAnalysisResult? {
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
            aestheticAnalysis: AestheticAnalysis(
                overallScore: Float.random(in: -0.5...0.8),
                isUtility: Bool.random() && Double.random(in: 0...1) < 0.1, // 10% chance
                confidenceLevel: Float.random(in: 0.7...0.95)
            ),
            saliencyAnalysis: nil, // Could add mock saliency data
            dominantColors: nil, // Could add mock color data
            sceneConfidence: Float.random(in: 0.2...0.8)
        )
    }
    
    private func generateMockObjects(for photo: Photo) -> [ObjectAnalysis] {
        var objects: [ObjectAnalysis] = []
        
        // Add face-based objects
        if let faceQuality = photo.faceQuality {
            if faceQuality.faceCount == 1 {
                objects.append(ObjectAnalysis(identifier: "person", confidence: 0.85, boundingBox: CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)))
                objects.append(ObjectAnalysis(identifier: "portrait", confidence: 0.75, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)))
                objects.append(ObjectAnalysis(identifier: "human face", confidence: 0.82, boundingBox: CGRect(x: 0.35, y: 0.15, width: 0.3, height: 0.4)))
            } else if faceQuality.faceCount > 1 {
                objects.append(ObjectAnalysis(identifier: "group", confidence: 0.80, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)))
                objects.append(ObjectAnalysis(identifier: "people", confidence: 0.85, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)))
                objects.append(ObjectAnalysis(identifier: "gathering", confidence: 0.65, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)))
            }
        }
        
        // Add diverse contextual objects to showcase Apple's comprehensive classification
        let contextualObjects = [
            ("outdoor", Float.random(in: 0.4...0.8)),
            ("nature", Float.random(in: 0.3...0.7)),
            ("sky", Float.random(in: 0.5...0.9)),
            ("plant", Float.random(in: 0.2...0.6)),
            ("building", Float.random(in: 0.3...0.8)),
            ("street", Float.random(in: 0.3...0.7)),
            ("food", Float.random(in: 0.2...0.8)),
            ("animal", Float.random(in: 0.1...0.6)),
            ("vehicle", Float.random(in: 0.2...0.7)),
            ("water", Float.random(in: 0.3...0.8)),
            ("indoor", Float.random(in: 0.3...0.7)),
            ("furniture", Float.random(in: 0.2...0.6)),
            ("electronics", Float.random(in: 0.1...0.5)),
            ("clothing", Float.random(in: 0.2...0.6)),
            ("flower", Float.random(in: 0.1...0.7)),
            ("tree", Float.random(in: 0.3...0.8)),
            ("grass", Float.random(in: 0.2...0.6)),
            ("architecture", Float.random(in: 0.2...0.7)),
            ("landscape", Float.random(in: 0.3...0.8)),
            ("scene", Float.random(in: 0.4...0.9))
        ]
        
        // Select 8-15 random objects to simulate Apple's detailed classification
        let selectedObjects = contextualObjects.shuffled().prefix(Int.random(in: 8...15))
        
        for (objectName, confidence) in selectedObjects {
            objects.append(ObjectAnalysis(
                identifier: objectName,
                confidence: confidence,
                boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)
            ))
        }
        
        return objects.sorted { $0.confidence > $1.confidence }
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
                pose: FacePose(
                    pitch: Float.random(in: -30...30),
                    yaw: Float.random(in: -45...45),
                    roll: Float.random(in: -20...20)
                ),
                recognitionID: nil
            ))
        }
        
        return faces
    }
}

// MARK: - Photo Thumbnail Grid Item

struct PhotoThumbnailGridItem: View {
    let photo: Photo
    let isSelected: Bool
    let analysisResult: PhotoAnalysisResult?
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
                            .scaleEffect(0.6)
                            .foregroundStyle(.secondary)
                    }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 16))
                    }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .overlay(
            // Quality indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if let result = analysisResult {
                        Text("\(Int(result.overallScore * 100))%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.black.opacity(0.7))
                            .cornerRadius(3)
                            .padding(2)
                    }
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
            let image = await photoViewModel.loadThumbnail(for: photo)
            await MainActor.run {
                self.thumbnailImage = image
                self.isLoading = false
            }
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search classifications...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Category Filter View

struct CategoryFilterView: View {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Categories")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                if !selectedCategories.isEmpty {
                    Button("Clear") {
                        for category in selectedCategories {
                            onCategoryToggle(category)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 60), spacing: 4)
            ], spacing: 4) {
                ForEach(sortedCategories.prefix(6), id: \.self) { category in
                    CompactCategoryChip(
                        category: category,
                        count: availableCategories[category] ?? 0,
                        isSelected: selectedCategories.contains(category),
                        onTap: { onCategoryToggle(category) }
                    )
                }
            }
        }
    }
}

// MARK: - Compact Category Chip

struct CompactCategoryChip: View {
    let category: PhotoCategory
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: category.icon)
                    .font(.system(size: 10, weight: .medium))
                
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    PhotoAnalysisDataView(photoViewModel: PhotoLibraryViewModel.preview)
}