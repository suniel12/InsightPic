import SwiftUI
import Vision

struct FaceAnalysisDebugView: View {
    let cluster: PhotoCluster
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var analysisResult: ClusterFaceAnalysis?
    @State private var detailedPhotoAnalyses: [String: [FaceQualityData]] = [:]
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var showingPerformanceStats = false
    @State private var analysisTime: TimeInterval = 0
    
    private let faceAnalysisService = FaceQualityAnalysisService()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "face.dashed")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        Text("Face Analysis Debug")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(getAnalysisStatus())
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    // Analysis Controls
                    VStack(spacing: 16) {
                        if isAnalyzing {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Analyzing faces...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        } else {
                            Button(action: {
                                Task {
                                    await runFaceAnalysis()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                    Text("Run Face Analysis")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                        
                        if let error = analysisError {
                            Text(error)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color(.systemRed).opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Results Display
                    if let result = analysisResult {
                        VStack(spacing: 20) {
                            // Performance Stats
                            performanceStatsView(result)
                            
                            // Detailed Photo Analysis (New!)
                            if !detailedPhotoAnalyses.isEmpty {
                                detailedPhotoAnalysisView()
                            }
                            
                            // Person Matching Analysis (Task 2.3)
                            if let result = analysisResult, !result.personAnalyses.isEmpty {
                                personMatchingVisualizationView(result)
                            }
                            
                            // Overall Analysis
                            overallAnalysisView(result)
                            
                            // Per-Person Analysis
                            personAnalysisView(result)
                            
                            // Base Photo Selection
                            basePhotoView(result)
                            
                            // Cache Statistics
                            cacheStatsView()
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Stats") {
                        showingPerformanceStats.toggle()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPerformanceStats) {
            PerformanceStatsDetailView(
                cluster: cluster,
                analysisResult: analysisResult,
                analysisTime: analysisTime,
                faceAnalysisService: faceAnalysisService
            )
        }
    }
    
    // MARK: - Analysis Methods
    
    private func runFaceAnalysis() async {
        await MainActor.run {
            isAnalyzing = true
            analysisError = nil
            analysisResult = nil
            detailedPhotoAnalyses = [:]
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Run both cluster analysis and detailed photo analysis
        async let clusterAnalysis = faceAnalysisService.analyzeFaceQualityInCluster(cluster)
        async let detailedAnalysis = faceAnalysisService.rankFaceQualityInPhotos(cluster.photos)
        
        let result = await clusterAnalysis
        let photoAnalyses = await detailedAnalysis
        let endTime = CFAbsoluteTimeGetCurrent()
        
        await MainActor.run {
            self.analysisResult = result
            self.detailedPhotoAnalyses = photoAnalyses
            self.analysisTime = endTime - startTime
            self.isAnalyzing = false
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func detailedPhotoAnalysisView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detailed Photo Analysis (Tasks 2.1-2.4)")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("Real Vision Framework ML Analysis Results")
                .font(.subheadline)
                .foregroundColor(.blue)
            
            ForEach(cluster.photos.indices, id: \.self) { index in
                let photo = cluster.photos[index]
                if let faceAnalyses = detailedPhotoAnalyses[photo.assetIdentifier] {
                    PhotoAnalysisCard(
                        photo: photo,
                        photoIndex: index + 1,
                        faceAnalyses: faceAnalyses,
                        photoViewModel: photoViewModel
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func personMatchingVisualizationView(_ result: ClusterFaceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Person Matching Analysis (Task 2.3)")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("Cross-Photo Person Identification Results")
                .font(.subheadline)
                .foregroundColor(.purple)
            
            if result.personAnalyses.isEmpty {
                Text("No people detected with multiple faces")
                    .font(.body)
                    .foregroundColor(.orange)
                    .padding()
            } else {
                ForEach(Array(result.personAnalyses.keys.sorted()), id: \.self) { personID in
                    if let personAnalysis = result.personAnalyses[personID] {
                        PersonMatchingCard(personAnalysis: personAnalysis, photoViewModel: photoViewModel)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func performanceStatsView(_ result: ClusterFaceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Analysis Time:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f seconds", analysisTime))
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Photos Processed:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(cluster.photos.count)")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("People Detected:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(result.personCount)")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Processing Speed:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f photos/sec", Double(cluster.photos.count) / analysisTime))
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func overallAnalysisView(_ result: ClusterFaceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall Analysis")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                // High-level analysis explanation
                if result.overallImprovementPotential == 0.0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("All photos are high quality!")
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        Spacer()
                    }
                    .padding(.bottom, 4)
                }
                
                HStack {
                    Text("Improvement Potential:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", result.overallImprovementPotential * 100))
                        .fontWeight(.medium)
                        .foregroundColor(improvementColor(result.overallImprovementPotential))
                }
                
                HStack {
                    Text("People with Improvements:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(result.peopleWithImprovements.count) of \(result.personCount)")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Estimated Processing Time:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f seconds", result.estimatedProcessingTime))
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func personAnalysisView(_ result: ClusterFaceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Person Analysis (\(result.personAnalyses.count) people)")
                .font(.headline)
                .fontWeight(.semibold)
            
            ForEach(Array(result.personAnalyses.keys.sorted()), id: \.self) { personID in
                if let personAnalysis = result.personAnalyses[personID] {
                    PersonAnalysisRow(personAnalysis: personAnalysis)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func basePhotoView(_ result: ClusterFaceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Base Photo Selection")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                AsyncImage(url: nil) { _ in
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .overlay(
                            Text("Photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        )
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Base Photo")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Overall Score: \(String(format: "%.2f", result.basePhotoCandidate.overallScore))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Aesthetic: \(String(format: "%.2f", result.basePhotoCandidate.aestheticScore))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Technical: \(String(format: "%.2f", result.basePhotoCandidate.technicalQuality))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func cacheStatsView() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cache Statistics")
                .font(.headline)
                .fontWeight(.semibold)
            
            Button("View Cache Stats") {
                Task {
                    let stats = await faceAnalysisService.getCacheStatistics()
                    print("Cache Statistics: Clusters: \(stats.clusterCount), Faces: \(stats.faceCount)")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBlue).opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
            
            Button("Clear Cache") {
                Task {
                    await faceAnalysisService.clearAnalysisCache()
                    print("Cache cleared")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemRed).opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    /// Get comprehensive analysis status including total faces and people detected
    private func getAnalysisStatus() -> String {
        let photoCount = cluster.photos.count
        let totalFaces = detailedPhotoAnalyses.values.flatMap { $0 }.count
        let improvementWorthyPeople = analysisResult?.personCount ?? 0
        
        if totalFaces == 0 {
            return "\(photoCount) photos • No faces detected"
        } else if improvementWorthyPeople == 0 {
            return "\(photoCount) photos • \(totalFaces) faces detected • High quality (no improvements needed)"
        } else {
            return "\(photoCount) photos • \(totalFaces) faces detected • \(improvementWorthyPeople) people need improvements"
        }
    }
    
    private func improvementColor(_ potential: Float) -> Color {
        if potential > 0.7 {
            return .green
        } else if potential > 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Supporting Views

struct PersonMatchingCard: View {
    let personAnalysis: PersonFaceQualityAnalysis
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Person Header
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.purple)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Person \(personAnalysis.personID.prefix(8))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Found in \(personAnalysis.allFaces.count) photos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Match Quality")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(String(format: "%.0f%%", personAnalysis.improvementPotential * 100))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(matchQualityColor(personAnalysis.improvementPotential))
                }
            }
            
            // Face Instances Across Photos
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(personAnalysis.allFaces.indices, id: \.self) { index in
                        let faceData = personAnalysis.allFaces[index]
                        PersonFaceInstanceView(
                            faceData: faceData,
                            instanceNumber: index + 1,
                            isBestFace: faceData.qualityRank == personAnalysis.bestFace.qualityRank,
                            isWorstFace: faceData.qualityRank == personAnalysis.worstFace.qualityRank,
                            photoViewModel: photoViewModel
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Matching Summary
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best Quality:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.2f", personAnalysis.bestFace.qualityRank))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Quality Range:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.2f", personAnalysis.qualityGain))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Replacement:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(personAnalysis.shouldReplace ? "Recommended ✅" : "Not needed ❌")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(personAnalysis.shouldReplace ? .green : .orange)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private func matchQualityColor(_ quality: Float) -> Color {
        if quality > 0.7 {
            return .green
        } else if quality > 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

struct PersonFaceInstanceView: View {
    let faceData: FaceQualityData
    let instanceNumber: Int
    let isBestFace: Bool
    let isWorstFace: Bool
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        VStack(spacing: 6) {
            // Thumbnail with quality indicator
            ZStack {
                Group {
                    if let image = thumbnailImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.5)
                            )
                    }
                }
                .frame(width: 50, height: 50)
                .cornerRadius(8)
                
                // Quality indicator overlay
                VStack {
                    HStack {
                        Spacer()
                        if isBestFace {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.caption2)
                                .padding(2)
                                .background(.black.opacity(0.7))
                                .cornerRadius(2)
                        } else if isWorstFace {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption2)
                                .padding(2)
                                .background(.black.opacity(0.7))
                                .cornerRadius(2)
                        }
                    }
                    Spacer()
                }
                .padding(2)
            }
            
            // Instance details
            VStack(spacing: 2) {
                Text("Photo \(instanceNumber)")
                    .font(.caption2)
                    .fontWeight(.medium)
                
                Text("\(String(format: "%.2f", faceData.qualityRank))")
                    .font(.caption2)
                    .foregroundColor(qualityColor(faceData.qualityRank))
                
                // Eye state indicator
                HStack(spacing: 2) {
                    Image(systemName: faceData.eyeState.bothOpen ? "eye.fill" : "eye.slash.fill")
                        .font(.caption2)
                        .foregroundColor(faceData.eyeState.bothOpen ? .green : .red)
                    
                    Image(systemName: faceData.smileQuality.isGoodSmile ? "face.smiling.fill" : "face.dashed.fill")
                        .font(.caption2)
                        .foregroundColor(faceData.smileQuality.isGoodSmile ? .green : .orange)
                }
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task {
            let image = await photoViewModel.loadThumbnail(for: faceData.photo)
            await MainActor.run {
                self.thumbnailImage = image
            }
        }
    }
    
    private func qualityColor(_ quality: Float) -> Color {
        if quality > 0.7 {
            return .green
        } else if quality > 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

struct PhotoAnalysisCard: View {
    let photo: Photo
    let photoIndex: Int
    let faceAnalyses: [FaceQualityData]
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Photo Header
            HStack {
                // Thumbnail
                Group {
                    if let image = thumbnailImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.7)
                            )
                    }
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Photo \(photoIndex)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("\(faceAnalyses.count) face(s) detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Asset: \(photo.assetIdentifier.prefix(12))...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Face Analysis Results
            if faceAnalyses.isEmpty {
                Text("No faces detected")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
            } else {
                ForEach(faceAnalyses.indices, id: \.self) { faceIndex in
                    let faceData = faceAnalyses[faceIndex]
                    FaceAnalysisDetailView(faceData: faceData, faceIndex: faceIndex + 1)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .onAppear {
            loadThumbnail()
        }
    }
    
    
    private func loadThumbnail() {
        Task {
            let image = await photoViewModel.loadThumbnail(for: photo)
            await MainActor.run {
                self.thumbnailImage = image
            }
        }
    }
    
}

struct FaceAnalysisDetailView: View {
    let faceData: FaceQualityData
    let faceIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Face \(faceIndex)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text("Quality: \(String(format: "%.2f", faceData.qualityRank))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(qualityColor(faceData.qualityRank))
            }
            
            // Eye State Detection (Task 2.1) - With Debug Values
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text("Eye State:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("L: \(faceData.eyeState.leftOpen ? "Open ✅" : "Closed ❌")")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text("R: \(faceData.eyeState.rightOpen ? "Open ✅" : "Closed ❌")")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text("(\(String(format: "%.0f%%", faceData.eyeState.confidence * 100)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Debug: Show landmark count and raw data
                if let landmarks = faceData.landmarks {
                    HStack {
                        Text("Debug:")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        
                        if let leftEye = landmarks.leftEye {
                            Text("L-Points: \(leftEye.normalizedPoints.count)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        
                        if let rightEye = landmarks.rightEye {
                            Text("R-Points: \(rightEye.normalizedPoints.count)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        
                        Text("Capture: \(String(format: "%.2f", faceData.captureQuality))")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        
                        Text("Algorithm: Enhanced EAR with Adaptive Threshold")
                            .font(.caption2)
                            .foregroundColor(.purple)
                        
                        Text("Research-Based: Traditional Formula + Personalization")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // Smile Detection (Task 2.2)
            HStack {
                Image(systemName: "face.smiling.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                
                Text("Smile:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Intensity: \(String(format: "%.2f", faceData.smileQuality.intensity))")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("Natural: \(String(format: "%.2f", faceData.smileQuality.naturalness))")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("Quality: \(faceData.smileQuality.isGoodSmile ? "Good ✅" : "Poor ❌")")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            // Technical Quality & Face Positioning
            HStack {
                Image(systemName: "camera.metering.matrix")
                    .foregroundColor(.green)
                    .font(.caption)
                
                Text("Technical:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Capture: \(String(format: "%.2f", faceData.captureQuality))")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("Sharp: \(String(format: "%.2f", faceData.sharpness))")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("Angle: \(faceData.faceAngle.isOptimal ? "Optimal ✅" : "Poor ❌")")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            // Issues Detected
            if !faceData.identifiedIssues.isEmpty && faceData.identifiedIssues != [.none] {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    
                    Text("Issues:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(faceData.identifiedIssues.map { $0.rawValue }.joined(separator: ", "))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Text("No issues detected ✅")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func qualityColor(_ quality: Float) -> Color {
        if quality > 0.7 {
            return .green
        } else if quality > 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

struct PersonAnalysisRow: View {
    let personAnalysis: PersonFaceQualityAnalysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Person \(personAnalysis.personID.prefix(8))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if personAnalysis.shouldReplace {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Faces:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(personAnalysis.allFaces.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("Improvement:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", personAnalysis.improvementPotential * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Best Quality:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", personAnalysis.bestFace.qualityRank))
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("Worst Quality:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", personAnalysis.worstFace.qualityRank))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                if !personAnalysis.issuesFixed.isEmpty {
                    Text("Issues Fixed: \(personAnalysis.issuesFixed.map { $0.rawValue }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct PerformanceStatsDetailView: View {
    let cluster: PhotoCluster
    let analysisResult: ClusterFaceAnalysis?
    let analysisTime: TimeInterval
    let faceAnalysisService: FaceQualityAnalysisService
    
    @Environment(\.dismiss) private var dismiss
    @State private var cacheStats: (clusterCount: Int, faceCount: Int) = (0, 0)
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Performance Analysis")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    // Performance Details
                    VStack(alignment: .leading, spacing: 16) {
                        DebugStatRow(title: "Total Analysis Time", value: String(format: "%.3f seconds", analysisTime))
                        DebugStatRow(title: "Photos Processed", value: "\(cluster.photos.count)")
                        DebugStatRow(title: "Average Time per Photo", value: String(format: "%.3f seconds", analysisTime / Double(cluster.photos.count)))
                        
                        if let result = analysisResult {
                            DebugStatRow(title: "People Detected", value: "\(result.personCount)")
                            DebugStatRow(title: "Faces Analyzed", value: "\(result.personAnalyses.values.reduce(0) { $0 + $1.allFaces.count })")
                            DebugStatRow(title: "Improvement Potential", value: String(format: "%.1f%%", result.overallImprovementPotential * 100))
                        }
                        
                        DebugStatRow(title: "Cache Clusters", value: "\(cacheStats.clusterCount)")
                        DebugStatRow(title: "Cache Faces", value: "\(cacheStats.faceCount)")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            cacheStats = await faceAnalysisService.getCacheStatistics()
        }
    }
}

struct DebugStatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}