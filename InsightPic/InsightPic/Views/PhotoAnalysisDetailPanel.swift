import SwiftUI
import Foundation

struct PhotoAnalysisDetailPanel: View {
    let photo: Photo
    let analysisResult: PhotoAnalysisResult?
    let selectedCategories: Set<PhotoCategory>
    let filterService: PhotoFilterService
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    @State private var fullResolutionImage: UIImage?
    @State private var isLoadingImage = true
    @State private var expandedSections: Set<String> = ["overview", "classifications"]
    
    private let sections = [
        "overview": "Overview",
        "classifications": "Vision Framework Classifications",
        "categories": "Category Mapping",
        "scores": "Quality Scores",
        "faces": "Face Analysis",
        "aesthetic": "Aesthetic Analysis",
        "metadata": "Technical Metadata"
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with photo
                PhotoHeaderView(
                    photo: photo,
                    image: fullResolutionImage,
                    isLoading: isLoadingImage,
                    analysisResult: analysisResult
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                Divider()
                    .padding(.vertical, 16)
                
                // Analysis sections
                LazyVStack(spacing: 0) {
                    ForEach(Array(sections.keys), id: \.self) { sectionKey in
                        AnalysisSection(
                            title: sections[sectionKey] ?? "",
                            isExpanded: expandedSections.contains(sectionKey),
                            onToggle: { toggleSection(sectionKey) }
                        ) {
                            sectionContent(for: sectionKey)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                Spacer(minLength: 20)
            }
        }
        .onAppear {
            loadFullResolutionImage()
        }
    }
    
    @ViewBuilder
    private func sectionContent(for section: String) -> some View {
        switch section {
        case "overview":
            OverviewSection(
                photo: photo,
                analysisResult: analysisResult,
                selectedCategories: selectedCategories,
                filterService: filterService
            )
            
        case "classifications":
            ClassificationsSection(analysisResult: analysisResult)
            
        case "categories":
            CategoryMappingSection(
                analysisResult: analysisResult,
                filterService: filterService
            )
            
        case "scores":
            QualityScoresSection(analysisResult: analysisResult)
            
        case "faces":
            FaceAnalysisSection(analysisResult: analysisResult)
            
        case "aesthetic":
            AestheticAnalysisSection(analysisResult: analysisResult)
            
        case "metadata":
            MetadataSection(photo: photo, analysisResult: analysisResult)
            
        default:
            EmptyView()
        }
    }
    
    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
    
    private func loadFullResolutionImage() {
        Task {
            isLoadingImage = true
            // For preview purposes, load thumbnail
            let image = await photoViewModel.loadThumbnail(for: photo)
            await MainActor.run {
                self.fullResolutionImage = image
                self.isLoadingImage = false
            }
        }
    }
}

// MARK: - Photo Header View

struct PhotoHeaderView: View {
    let photo: Photo
    let image: UIImage?
    let isLoading: Bool
    let analysisResult: PhotoAnalysisResult?
    
    var body: some View {
        VStack(spacing: 16) {
            // Photo display
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                } else if isLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 200)
                        .overlay {
                            ProgressView()
                                .scaleEffect(1.2)
                        }
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 200)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                        }
                        .cornerRadius(12)
                }
            }
            
            // Basic info
            VStack(spacing: 8) {
                Text("Photo ID: \(photo.id.uuidString.prefix(8))...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                
                if let result = analysisResult {
                    HStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text("Overall Score")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(result.overallScore * 100))%")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(scoreColor(result.overallScore))
                        }
                        
                        VStack(spacing: 4) {
                            Text("Classifications")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(result.objects.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(spacing: 4) {
                            Text("Faces")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(result.faces.count)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }
    
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// MARK: - Analysis Section

struct AnalysisSection<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            // Section header
            Button(action: onToggle) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Section content
            if isExpanded {
                content()
                    .padding(.bottom, 16)
            }
            
            Divider()
        }
    }
}

// MARK: - Overview Section

struct OverviewSection: View {
    let photo: Photo
    let analysisResult: PhotoAnalysisResult?
    let selectedCategories: Set<PhotoCategory>
    let filterService: PhotoFilterService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result = analysisResult {
                // Relevance score for current category selection
                if !selectedCategories.isEmpty {
                    let relevanceScore = filterService.calculateRelevanceScore(
                        for: photo,
                        analysisResult: result,
                        selectedCategories: selectedCategories
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Relevance Score")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("\(Int(relevanceScore * 100))%")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        Text("For categories: \(selectedCategories.map { $0.rawValue }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // Relevance breakdown
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Category Match (80%)")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(relevanceScore * 0.8 * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Text("Quality Score (20%)")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(result.overallScore * 0.2 * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(.leading, 8)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.all, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                
                // Top classifications
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Classifications")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(spacing: 6) {
                        ForEach(Array(result.objects.prefix(5).enumerated()), id: \.offset) { index, object in
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .leading)
                                
                                Text(object.identifier.capitalized)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Text("\(Int(object.confidence * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Mapped categories
                let mappedCategories = filterService.mapVisionLabelsToCategories(result.objects)
                if !mappedCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected Categories")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 80), spacing: 8)
                        ], spacing: 8) {
                            ForEach(Array(mappedCategories), id: \.self) { category in
                                HStack(spacing: 4) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 10))
                                    Text(category.rawValue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Classifications Section

struct ClassificationsSection: View {
    let analysisResult: PhotoAnalysisResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = analysisResult {
                Text("Apple's Vision Framework identified \(result.objects.count) classifications:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    ForEach(Array(result.objects.enumerated()), id: \.offset) { index, object in
                        ClassificationRow(
                            rank: index + 1,
                            identifier: object.identifier,
                            confidence: object.confidence
                        )
                    }
                }
            } else {
                Text("No analysis data available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ClassificationRow: View {
    let rank: Int
    let identifier: String
    let confidence: Float
    
    var body: some View {
        HStack {
            Text("\(rank).")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 25, alignment: .leading)
            
            Text(identifier.capitalized)
                .font(.subheadline)
            
            Spacer()
            
            // Confidence bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(confidenceColor(confidence))
                        .frame(width: geometry.size.width * CGFloat(confidence), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(width: 60, height: 6)
            
            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// MARK: - Category Mapping Section

struct CategoryMappingSection: View {
    let analysisResult: PhotoAnalysisResult?
    let filterService: PhotoFilterService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = analysisResult {
                Text("How Vision Framework labels map to our categories:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                let mappedCategories = filterService.mapVisionLabelsToCategories(result.objects)
                
                if mappedCategories.isEmpty {
                    Text("No categories mapped from current classifications")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(mappedCategories), id: \.self) { category in
                            CategoryMappingRow(
                                category: category,
                                objects: result.objects,
                                filterService: filterService
                            )
                        }
                    }
                }
            } else {
                Text("No analysis data available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CategoryMappingRow: View {
    let category: PhotoCategory
    let objects: [ObjectAnalysis]
    let filterService: PhotoFilterService
    
    var relatedObjects: [ObjectAnalysis] {
        // Find objects that contributed to this category mapping
        objects.filter { object in
            let testCategories = filterService.mapVisionLabelsToCategories([object])
            return testCategories.contains(category)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: category.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(relatedObjects.count) matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !relatedObjects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(relatedObjects.prefix(3), id: \.identifier) { object in
                        HStack {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(object.identifier.capitalized)
                                .font(.caption)
                            Spacer()
                            Text("\(Int(object.confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if relatedObjects.count > 3 {
                        Text("... and \(relatedObjects.count - 3) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 8)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.all, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Quality Scores Section

struct QualityScoresSection: View {
    let analysisResult: PhotoAnalysisResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = analysisResult {
                VStack(spacing: 16) {
                    ScoreRow(label: "Overall Quality", score: result.overallScore, isMain: true)
                    ScoreRow(label: "Sharpness", score: result.sharpnessScore)
                    ScoreRow(label: "Exposure", score: result.exposureScore)
                    ScoreRow(label: "Composition", score: result.compositionScore)
                    ScoreRow(label: "Aesthetic Appeal", score: result.aestheticScore)
                }
            } else {
                Text("No analysis data available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ScoreRow: View {
    let label: String
    let score: Double
    let isMain: Bool
    
    init(label: String, score: Double, isMain: Bool = false) {
        self.label = label
        self.score = score
        self.isMain = isMain
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(isMain ? .subheadline : .caption)
                    .fontWeight(isMain ? .medium : .regular)
                
                Spacer()
                
                Text("\(Int(score * 100))%")
                    .font(isMain ? .subheadline : .caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(scoreColor(score))
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: isMain ? 8 : 6)
                        .cornerRadius(isMain ? 4 : 3)
                    
                    Rectangle()
                        .fill(scoreColor(score))
                        .frame(width: geometry.size.width * CGFloat(score), height: isMain ? 8 : 6)
                        .cornerRadius(isMain ? 4 : 3)
                }
            }
            .frame(height: isMain ? 8 : 6)
        }
    }
    
    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// MARK: - Face Analysis Section

struct FaceAnalysisSection: View {
    let analysisResult: PhotoAnalysisResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = analysisResult {
                if result.faces.isEmpty {
                    Text("No faces detected in this photo")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Detected \(result.faces.count) face\(result.faces.count == 1 ? "" : "s"):")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 12) {
                        ForEach(Array(result.faces.enumerated()), id: \.offset) { index, face in
                            FaceAnalysisRow(face: face, index: index + 1)
                        }
                    }
                }
            } else {
                Text("No analysis data available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FaceAnalysisRow: View {
    let face: FaceAnalysis
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle")
                    .foregroundStyle(Color.accentColor)
                
                Text("Face \(index)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("Quality: \(Int(face.faceQuality * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                DataPair(label: "Confidence", value: "\(Int(face.confidence * 100))%")
                DataPair(label: "Smiling", value: face.isSmiling == true ? "Yes" : (face.isSmiling == false ? "No" : "Unknown"))
                DataPair(label: "Eyes Open", value: face.eyesOpen == true ? "Yes" : (face.eyesOpen == false ? "No" : "Unknown"))
                
                if let pose = face.pose {
                    DataPair(label: "Head Pose", value: "Y:\(Int(pose.yaw ?? 0))° P:\(Int(pose.pitch ?? 0))°")
                }
            }
        }
        .padding(.all, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Aesthetic Analysis Section

struct AestheticAnalysisSection: View {
    let analysisResult: PhotoAnalysisResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = analysisResult, let aesthetic = result.aestheticAnalysis {
                VStack(spacing: 12) {
                    HStack {
                        Text("Vision's Aesthetic Score:")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text("\(Int((aesthetic.overallScore + 1) * 50))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(aestheticColor(aesthetic.overallScore))
                    }
                    
                    DataPair(label: "Is Utility Image", value: aesthetic.isUtility ? "Yes" : "No")
                    DataPair(label: "Confidence", value: "\(Int(aesthetic.confidenceLevel * 100))%")
                    
                    Text("Note: Vision's aesthetic score ranges from -1 (poor) to +1 (excellent)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            } else {
                Text("Aesthetic analysis not available (requires iOS 15+)")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func aestheticColor(_ score: Float) -> Color {
        switch score {
        case 0.3...1.0: return .green
        case 0.0..<0.3: return .blue
        case -0.3..<0.0: return .orange
        default: return .red
        }
    }
}

// MARK: - Metadata Section

struct MetadataSection: View {
    let photo: Photo
    let analysisResult: PhotoAnalysisResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                DataPair(label: "Asset ID", value: String(photo.assetIdentifier.prefix(8)) + "...")
                DataPair(label: "Created", value: photo.timestamp.formatted(date: .abbreviated, time: .omitted))
                
                if let location = photo.location {
                    DataPair(label: "Location", value: "Lat: \(String(format: "%.3f", location.coordinate.latitude))")
                }
                
                if let result = analysisResult {
                    DataPair(label: "Analyzed", value: result.timestamp.formatted(date: .abbreviated, time: .shortened))
                    DataPair(label: "Scene Confidence", value: "\(Int(result.sceneConfidence * 100))%")
                }
                
                if let faceQuality = photo.faceQuality {
                    DataPair(label: "Face Count", value: "\(faceQuality.faceCount)")
                }
            }
        }
    }
}

// MARK: - Data Pair

struct DataPair: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview {
    let mockPhoto = Photo(
        id: UUID(),
        assetIdentifier: "sample-asset-id",
        timestamp: Date(),
        location: nil,
        metadata: PhotoMetadata(width: 1000, height: 1000)
    )
    
    PhotoAnalysisDetailPanel(
        photo: mockPhoto,
        analysisResult: nil,
        selectedCategories: [.people, .outdoor],
        filterService: PhotoFilterService(),
        photoViewModel: PhotoLibraryViewModel.preview
    )
}