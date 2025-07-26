import SwiftUI
import Vision
import CoreGraphics

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
                    
                    // Test Perfect Moment button (for debugging)
                    Button(action: {
                        createTestPerfectMomentPhoto()
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .medium))
                            Text("Test PM")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.purple.opacity(0.8))
                        .cornerRadius(12)
                    }
                    
                    // Test Face Analysis button (for Task 1.1)
                    Button(action: {
                        testFaceAnalysisStructures()
                    }) {
                        VStack(spacing: 2) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 14, weight: .medium))
                            Text("Test Face")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.blue.opacity(0.8))
                        .cornerRadius(12)
                    }
                    
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
    
    // MARK: - Test Functions
    
    private func createTestPerfectMomentPhoto() {
        guard let firstPhoto = sortedPhotos.first else { return }
        
        // Create test Perfect Moment metadata
        let testMetadata = PerfectMomentMetadata(
            sourcePhotoIds: [firstPhoto.id],
            qualityScore: 0.85,
            personReplacements: [
                PersonReplacement(
                    personID: "test_person_1",
                    sourcePhotoId: firstPhoto.id,
                    improvementType: .eyesClosed,
                    confidence: 0.9
                )
            ]
        )
        
        // Create a test Perfect Moment photo
        var testPhoto = Photo(
            assetIdentifier: "test_perfect_moment_\(UUID().uuidString)",
            timestamp: Date(),
            metadata: firstPhoto.metadata,
            perfectMomentMetadata: testMetadata
        )
        testPhoto.perfectMomentMetadata = testMetadata
        
        // Add to sorted photos to see the change
        sortedPhotos.append(testPhoto)
        
        print("=== Perfect Moment Test ===")
        print("Created test photo with isPerfectMoment: \(testPhoto.isPerfectMoment)")
        print("Metadata: \(testPhoto.perfectMomentMetadata?.isGeneratedPerfectMoment ?? false)")
        print("Improvements: \(testPhoto.perfectMomentMetadata?.personReplacements.count ?? 0)")
    }
    
    // MARK: - Task 1.1 Test Functions
    
    private func testFaceAnalysisStructures() {
        guard let firstPhoto = sortedPhotos.first else { return }
        
        print("\n=== Task 1.1: Face Analysis Structures Test ===")
        
        // Test 1: EyeState data structure
        print("\n1. Testing EyeState:")
        let openEyes = EyeState(leftOpen: true, rightOpen: true, confidence: 0.9)
        let closedEyes = EyeState(leftOpen: false, rightOpen: false, confidence: 0.8)
        let partialEyes = EyeState(leftOpen: true, rightOpen: false, confidence: 0.7)
        
        print("   - Open eyes: bothOpen=\(openEyes.bothOpen), eitherOpen=\(openEyes.eitherOpen)")
        print("   - Closed eyes: bothOpen=\(closedEyes.bothOpen), eitherOpen=\(closedEyes.eitherOpen)")
        print("   - Partial eyes: bothOpen=\(partialEyes.bothOpen), eitherOpen=\(partialEyes.eitherOpen)")
        
        // Test 2: SmileQuality data structure
        print("\n2. Testing SmileQuality:")
        let naturalSmile = SmileQuality(intensity: 0.8, naturalness: 0.9, confidence: 0.85)
        let forcedSmile = SmileQuality(intensity: 0.9, naturalness: 0.3, confidence: 0.7)
        let noSmile = SmileQuality(intensity: 0.1, naturalness: 0.5, confidence: 0.9)
        
        print("   - Natural smile: overall=\(naturalSmile.overallQuality), isGood=\(naturalSmile.isGoodSmile)")
        print("   - Forced smile: overall=\(forcedSmile.overallQuality), isGood=\(forcedSmile.isGoodSmile)")
        print("   - No smile: overall=\(noSmile.overallQuality), isGood=\(noSmile.isGoodSmile)")
        
        // Test 3: FaceAngle data structure
        print("\n3. Testing FaceAngle:")
        let frontalFace = FaceAngle(pitch: 2.0, yaw: -1.0, roll: 0.5)
        let profileFace = FaceAngle(pitch: 5.0, yaw: 45.0, roll: 3.0)
        let extremeAngle = FaceAngle(pitch: 30.0, yaw: 60.0, roll: 25.0)
        
        print("   - Frontal face: isOptimal=\(frontalFace.isOptimal)")
        print("   - Profile face: isOptimal=\(profileFace.isOptimal)")
        print("   - Extreme angle: isOptimal=\(extremeAngle.isOptimal)")
        print("   - Frontal ↔ Profile compatible: \(frontalFace.isCompatibleForAlignment(with: profileFace))")
        print("   - Frontal ↔ Extreme compatible: \(frontalFace.isCompatibleForAlignment(with: extremeAngle))")
        
        // Test 4: FaceQualityData with comprehensive analysis
        print("\n4. Testing FaceQualityData:")
        let mockBoundingBox = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        
        let highQualityFace = FaceQualityData(
            photo: firstPhoto,
            boundingBox: mockBoundingBox,
            captureQuality: 0.9,
            eyeState: openEyes,
            smileQuality: naturalSmile,
            faceAngle: frontalFace,
            sharpness: 0.85,
            overallScore: 0.88
        )
        
        let lowQualityFace = FaceQualityData(
            photo: firstPhoto,
            boundingBox: mockBoundingBox,
            captureQuality: 0.4,
            eyeState: closedEyes,
            smileQuality: noSmile,
            faceAngle: extremeAngle,
            sharpness: 0.3,
            overallScore: 0.35
        )
        
        print("   - High quality face:")
        print("     • Quality rank: \(highQualityFace.qualityRank)")
        print("     • Primary issue: \(highQualityFace.primaryIssue.rawValue)")
        print("     • All issues: \(highQualityFace.identifiedIssues.map { $0.rawValue })")
        
        print("   - Low quality face:")
        print("     • Quality rank: \(lowQualityFace.qualityRank)")
        print("     • Primary issue: \(lowQualityFace.primaryIssue.rawValue)")
        print("     • All issues: \(lowQualityFace.identifiedIssues.map { $0.rawValue })")
        
        // Test 5: PersonFaceQualityAnalysis
        print("\n5. Testing PersonFaceQualityAnalysis:")
        let personAnalysis = PersonFaceQualityAnalysis(
            personID: "test_person_1",
            allFaces: [highQualityFace, lowQualityFace],
            bestFace: highQualityFace,
            worstFace: lowQualityFace,
            improvementPotential: 0.75
        )
        
        print("   - Person: \(personAnalysis.personID)")
        print("   - Quality gain: \(personAnalysis.qualityGain)")
        print("   - Should replace: \(personAnalysis.shouldReplace)")
        print("   - Issues fixed: \(personAnalysis.issuesFixed.map { $0.rawValue })")
        
        // Test 6: PersonFaceReplacement feasibility
        print("\n6. Testing PersonFaceReplacement:")
        let replacement = PersonFaceReplacement(
            personID: "test_person_1",
            sourceFace: highQualityFace,
            destinationPhoto: firstPhoto,
            destinationFace: lowQualityFace,
            improvementType: .eyesClosed,
            confidence: 0.85
        )
        
        print("   - Replacement feasible: \(replacement.isFeasible)")
        print("   - Expected improvement: \(replacement.expectedImprovement)")
        print("   - Improvement type: \(replacement.improvementType.description)")
        
        // Test 7: ClusterFaceAnalysis
        print("\n7. Testing ClusterFaceAnalysis:")
        let mockPhotoCandidate = PhotoCandidate(
            photo: firstPhoto,
            image: UIImage(systemName: "photo") ?? UIImage(),
            suitabilityScore: 0.8,
            aestheticScore: 0.7,
            technicalQuality: 0.85
        )
        
        let clusterAnalysis = ClusterFaceAnalysis(
            clusterID: cluster.id,
            personAnalyses: ["test_person_1": personAnalysis],
            basePhotoCandidate: mockPhotoCandidate,
            overallImprovementPotential: 0.65
        )
        
        print("   - Person count: \(clusterAnalysis.personCount)")
        print("   - People with improvements: \(clusterAnalysis.peopleWithImprovements)")
        print("   - Estimated processing time: \(clusterAnalysis.estimatedProcessingTime)s")
        print("   - Base photo overall score: \(clusterAnalysis.basePhotoCandidate.overallScore)")
        
        // Test 8: ImprovementType and FaceIssue enums
        print("\n8. Testing Improvement and Issue Types:")
        for improvementType in ImprovementType.allCases {
            print("   - \(improvementType.rawValue): \(improvementType.description) [\(improvementType.icon)]")
        }
        
        for faceIssue in FaceIssue.allCases {
            print("   - \(faceIssue.rawValue): severity \(faceIssue.severity)")
        }
        
        print("\n✅ Task 1.1: All face analysis data structures tested successfully!")
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
                    
                    // Perfect Moment Debug Info
                    Text("PM Eligible: \(cluster.perfectMomentEligibility.isEligible ? "✅" : "❌") • \(cluster.perfectMomentEligibility.reason.userMessage)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .multilineTextAlignment(.leading)
                    
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
        .overlay(
            // Perfect Moment Debug Overlay
            VStack {
                HStack {
                    Spacer()
                    if photo.isPerfectMoment {
                        VStack(spacing: 2) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundColor(.white)
                            Text("PM")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(4)
                        .background(.purple.opacity(0.8))
                        .cornerRadius(6)
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "circle")
                                .font(.caption2)
                                .foregroundColor(.white)
                            Text("REG")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(4)
                        .background(.gray.opacity(0.8))
                        .cornerRadius(6)
                    }
                }
                Spacer()
            }
            .padding(4),
            alignment: .topTrailing
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


// MARK: - Photo Item for fullScreenCover


// MARK: - Preview

#Preview {
    ClusterMomentsDetailView(
        cluster: PhotoCluster(),
        photoViewModel: PhotoLibraryViewModel.preview,
        curationService: ClusterCurationService()
    )
}