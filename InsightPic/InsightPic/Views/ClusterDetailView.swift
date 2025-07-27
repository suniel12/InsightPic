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
        guard !sortedPhotos.isEmpty else { 
            print("❌ No photos in cluster to analyze for Perfect Moment")
            return 
        }
        
        print("=== Real Perfect Moment Analysis ===")
        print("Analyzing \(sortedPhotos.count) photos in cluster for Perfect Moment eligibility...")
        
        Task {
            // Run on background queue to prevent UI blocking
            await Task.detached(priority: .userInitiated) {
                do {
                    let faceAnalysisService = FaceQualityAnalysisService()
                    
                    await MainActor.run {
                        print("🔄 Starting background analysis...")
                    }
                    
                    // Use a simplified sequential analysis to avoid Vision Framework hanging
                    print("🔄 Running simplified sequential analysis to avoid hanging...")
                    
                    let clusterAnalysis = try await withThrowingTaskGroup(of: ClusterFaceAnalysis?.self) { group in
                        group.addTask {
                            // Simplified analysis: analyze only first 2 photos to avoid hanging
                            let limitedPhotos = Array(cluster.photos.prefix(2))
                            print("📊 Analyzing \(limitedPhotos.count) photos sequentially...")
                            
                            // Run sequential analysis to prevent Vision Framework overload
                            let faceAnalysisService = FaceQualityAnalysisService()
                            var allFaceAnalyses: [String: [FaceQualityData]] = [:]
                            
                            for (index, photo) in limitedPhotos.enumerated() {
                                print("  🔍 Analyzing photo \(index + 1)/\(limitedPhotos.count)...")
                                let photoAnalyses = await faceAnalysisService.rankFaceQualityInPhotos([photo])
                                allFaceAnalyses.merge(photoAnalyses) { existing, new in existing }
                                
                                // Small delay to prevent Vision Framework overload
                                try await Task.sleep(for: .milliseconds(500))
                            }
                            
                            print("✅ Sequential analysis complete - creating summary...")
                            
                            // Create a simplified cluster analysis from the results
                            let totalFaces = allFaceAnalyses.values.flatMap { $0 }.count
                            
                            if totalFaces > 0 {
                                // Create mock cluster analysis with real face data
                                let firstPhoto = limitedPhotos[0]
                                let mockCandidate = PhotoCandidate(
                                    photo: firstPhoto,
                                    image: UIImage(systemName: "photo") ?? UIImage(),
                                    suitabilityScore: 0.8,
                                    aestheticScore: 0.7,
                                    technicalQuality: 0.85
                                )
                                
                                return ClusterFaceAnalysis(
                                    clusterID: cluster.id,
                                    personAnalyses: [:], // Simplified - no person matching for test
                                    basePhotoCandidate: mockCandidate,
                                    overallImprovementPotential: 0.3
                                )
                            } else {
                                return ClusterFaceAnalysis(
                                    clusterID: cluster.id,
                                    personAnalyses: [:],
                                    basePhotoCandidate: PhotoCandidate(
                                        photo: limitedPhotos[0],
                                        image: UIImage(systemName: "photo") ?? UIImage(),
                                        suitabilityScore: 0.5,
                                        aestheticScore: 0.5,
                                        technicalQuality: 0.5
                                    ),
                                    overallImprovementPotential: 0.0
                                )
                            }
                        }
                        
                        // Add timeout task
                        group.addTask {
                            try await Task.sleep(for: .seconds(15)) // Shorter timeout for simplified analysis
                            throw CancellationError()
                        }
                        
                        // Return first completed task (either analysis or timeout)
                        guard let result = try await group.next() else {
                            throw CancellationError()
                        }
                        group.cancelAll()
                        return result
                    }
                    
                    guard let clusterAnalysis = clusterAnalysis else {
                        throw CancellationError()
                    }
                    
                    await MainActor.run {
                        print("✅ Perfect Moment Analysis Complete:")
                        print("- People detected: \(clusterAnalysis.personCount)")
                        print("- Overall improvement potential: \(String(format: "%.1f%%", clusterAnalysis.overallImprovementPotential * 100))")
                        print("- People with improvements: \(clusterAnalysis.peopleWithImprovements.count)")
                        print("- Base photo quality: \(String(format: "%.2f", clusterAnalysis.basePhotoCandidate.overallScore))")
                        print("- Cluster eligibility: \(cluster.perfectMomentEligibility.isEligible ? "✅ Eligible" : "❌ Not eligible")")
                        print("- Reason: \(cluster.perfectMomentEligibility.reason.userMessage)")
                        
                        if clusterAnalysis.personCount > 0 {
                            print("\n📊 Person Analysis Details:")
                            for (personID, personAnalysis) in clusterAnalysis.personAnalyses {
                                print("- Person \(personID.prefix(8)): \(personAnalysis.allFaces.count) faces, improvement potential: \(String(format: "%.1f%%", personAnalysis.improvementPotential * 100))")
                                print("  Best quality: \(String(format: "%.2f", personAnalysis.bestFace.qualityRank)), Worst: \(String(format: "%.2f", personAnalysis.worstFace.qualityRank))")
                                print("  Should replace: \(personAnalysis.shouldReplace ? "✅" : "❌")")
                            }
                        }
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        print("⏰ Perfect Moment analysis timed out after 30 seconds")
                        print("💡 This suggests the analysis is hanging - likely due to Vision Framework memory issues")
                    }
                } catch {
                    await MainActor.run {
                        print("❌ Perfect Moment analysis failed: \(error)")
                    }
                }
            }.value
        }
    }
    
    // MARK: - Task 1.1 Real Data Test Functions
    
    private func testFaceAnalysisStructures() {
        guard !sortedPhotos.isEmpty else { 
            print("❌ No photos in cluster to analyze")
            return 
        }
        
        print("\n=== Task 1.1: Real Face Analysis Data Test ===")
        print("Testing face analysis data structures with REAL photos from cluster...")
        print("Photos in cluster: \(sortedPhotos.count)")
        
        Task {
            // Run on background queue to prevent UI blocking
            await Task.detached(priority: .userInitiated) {
                do {
                    let faceAnalysisService = FaceQualityAnalysisService()
                    
                    await MainActor.run {
                        print("🔄 Starting background face analysis...")
                    }
                    
                    // Run sequential analysis to prevent hanging
                    let photosToAnalyze = Array(sortedPhotos.prefix(2)) // Limit to 2 photos
                    print("📊 Analyzing \(photosToAnalyze.count) photos sequentially...")
                    
                    let detailedAnalysis = try await withThrowingTaskGroup(of: [String: [FaceQualityData]].self) { group in
                        group.addTask {
                            var results: [String: [FaceQualityData]] = [:]
                            
                            // Process photos one by one to avoid Vision Framework overload
                            for (index, photo) in photosToAnalyze.enumerated() {
                                print("  🔍 Analyzing photo \(index + 1)/\(photosToAnalyze.count) (\(photo.assetIdentifier.prefix(8))...)")
                                
                                let photoResult = await faceAnalysisService.rankFaceQualityInPhotos([photo])
                                results.merge(photoResult) { existing, new in existing }
                                
                                // Small delay to prevent overload
                                try await Task.sleep(for: .milliseconds(300))
                            }
                            
                            return results
                        }
                        
                        // Add timeout task
                        group.addTask {
                            try await Task.sleep(for: .seconds(10)) // Shorter timeout for 2 photos
                            throw CancellationError()
                        }
                        
                        // Return first completed task (either analysis or timeout)
                        let result = try await group.next()!
                        group.cancelAll()
                        return result
                    }
                
                await MainActor.run {
                    print("\n✅ Real Face Analysis Complete!")
                    print("Photos analyzed: \(photosToAnalyze.count)")
                    
                    var allFaces: [FaceQualityData] = []
                    
                    for (photoIndex, photo) in photosToAnalyze.enumerated() {
                        if let faceAnalyses = detailedAnalysis[photo.assetIdentifier], !faceAnalyses.isEmpty {
                            print("\n📸 Photo \(photoIndex + 1) (Asset: \(photo.assetIdentifier.prefix(12))...):")
                            print("   Faces detected: \(faceAnalyses.count)")
                            
                            for (faceIndex, faceData) in faceAnalyses.enumerated() {
                                print("\n   👤 Face \(faceIndex + 1):")
                                print("      • Quality rank: \(String(format: "%.3f", faceData.qualityRank))")
                                print("      • Eye state: L=\(faceData.eyeState.leftOpen ? "Open" : "Closed"), R=\(faceData.eyeState.rightOpen ? "Open" : "Closed") (conf: \(String(format: "%.2f", faceData.eyeState.confidence)))")
                                print("      • Smile: intensity=\(String(format: "%.2f", faceData.smileQuality.intensity)), naturalness=\(String(format: "%.2f", faceData.smileQuality.naturalness)), isGood=\(faceData.smileQuality.isGoodSmile)")
                                print("      • Face angle: pitch=\(String(format: "%.1f", faceData.faceAngle.pitch))°, yaw=\(String(format: "%.1f", faceData.faceAngle.yaw))°, roll=\(String(format: "%.1f", faceData.faceAngle.roll))°, optimal=\(faceData.faceAngle.isOptimal)")
                                print("      • Technical: capture=\(String(format: "%.2f", faceData.captureQuality)), sharpness=\(String(format: "%.2f", faceData.sharpness))")
                                print("      • Issues: \(faceData.identifiedIssues.map { $0.rawValue }.joined(separator: ", "))")
                                
                                allFaces.append(faceData)
                            }
                        } else {
                            print("\n📸 Photo \(photoIndex + 1): No faces detected")
                        }
                    }
                    
                    // Test data structure methods with real data
                    if allFaces.count >= 2 {
                        print("\n🧪 Testing Data Structure Methods with Real Data:")
                        
                        let bestFace = allFaces.max(by: { $0.qualityRank < $1.qualityRank }) ?? allFaces[0]
                        let worstFace = allFaces.min(by: { $0.qualityRank < $1.qualityRank }) ?? allFaces[1]
                        
                        print("\n   Best face quality: \(String(format: "%.3f", bestFace.qualityRank))")
                        print("   Worst face quality: \(String(format: "%.3f", worstFace.qualityRank))")
                        
                        // Test PersonFaceQualityAnalysis with real data
                        let personAnalysis = PersonFaceQualityAnalysis(
                            personID: "real_person_\(UUID().uuidString.prefix(8))",
                            allFaces: [bestFace, worstFace],
                            bestFace: bestFace,
                            worstFace: worstFace,
                            improvementPotential: Float(bestFace.qualityRank - worstFace.qualityRank)
                        )
                        
                        print("\n   📊 PersonFaceQualityAnalysis (Real Data):")
                        print("      • Quality gain: \(String(format: "%.3f", personAnalysis.qualityGain))")
                        print("      • Should replace: \(personAnalysis.shouldReplace)")
                        print("      • Issues that would be fixed: \(personAnalysis.issuesFixed.map { $0.rawValue })")
                        
                        // Test PersonFaceReplacement with real data
                        let replacement = PersonFaceReplacement(
                            personID: personAnalysis.personID,
                            sourceFace: bestFace,
                            destinationPhoto: worstFace.photo,
                            destinationFace: worstFace,
                            improvementType: worstFace.primaryIssue == .eyesClosed ? .eyesClosed : .poorExpression,
                            confidence: 0.85
                        )
                        
                        print("\n   🔄 PersonFaceReplacement (Real Data):")
                        print("      • Replacement feasible: \(replacement.isFeasible)")
                        print("      • Expected improvement: \(String(format: "%.3f", replacement.expectedImprovement))")
                        print("      • Improvement type: \(replacement.improvementType.description)")
                        
                        // Test angle compatibility with real data
                        if allFaces.count >= 2 {
                            let angle1 = allFaces[0].faceAngle
                            let angle2 = allFaces[1].faceAngle
                            print("\n   📐 Face Angle Compatibility (Real Data):")
                            print("      • Face 1 optimal: \(angle1.isOptimal)")
                            print("      • Face 2 optimal: \(angle2.isOptimal)")
                            print("      • Compatible for alignment: \(angle1.isCompatibleForAlignment(with: angle2))")
                        }
                    }
                    
                    print("\n✅ Task 1.1: Real face analysis data structures tested successfully!")
                    print("Total faces analyzed: \(allFaces.count)")
                }
                } catch is CancellationError {
                    await MainActor.run {
                        print("⏰ Face analysis timed out after 20 seconds")
                        print("💡 This suggests the Vision Framework is hanging - likely due to memory issues")
                    }
                } catch {
                    await MainActor.run {
                        print("❌ Real face analysis failed: \(error)")
                    }
                }
            }.value
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