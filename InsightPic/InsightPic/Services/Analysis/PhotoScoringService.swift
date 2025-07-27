import Foundation
import UIKit

// MARK: - Cluster Ranking Data Models

/// Comprehensive quality distribution analysis for photo clusters
struct ClusterQualityDistribution {
    let totalPhotos: Int
    let qualityBreakdown: [String: Int] // Quality categories and counts
    let recommendedThumbnail: Photo? // Best photo for thumbnail
    let clusterType: PhotoType // Detected cluster type
    let averageQuality: Float // Mean quality score
    let qualityRange: Float // Difference between best and worst
    
    /// Returns the percentage of photos in each quality category
    var qualityPercentages: [String: Float] {
        guard totalPhotos > 0 else { return [:] }
        
        return qualityBreakdown.mapValues { count in
            Float(count) / Float(totalPhotos) * 100.0
        }
    }
    
    /// Indicates if the cluster has consistent quality across photos
    var hasConsistentQuality: Bool {
        return qualityRange < 0.3 // Less than 30% variation
    }
    
    /// Returns a user-friendly quality summary
    var qualitySummary: String {
        if hasConsistentQuality {
            return "Consistent quality across all photos"
        } else if qualityRange > 0.6 {
            return "High quality variation - clear best choice available"
        } else {
            return "Moderate quality variation"
        }
    }
}

/// Detailed comparison results for photos within a cluster context
struct ClusterPhotoComparison {
    let photos: [Photo]
    let relativeScores: [Float] // Normalized scores within this subset (0.0-1.0)
    let qualityGaps: [Float] // Score differences between consecutive photos
    let recommendations: [String] // Analysis-based recommendations
    
    /// Returns the photo with the highest relative score
    var bestPhoto: Photo? {
        guard !photos.isEmpty,
              let maxIndex = relativeScores.firstIndex(of: relativeScores.max() ?? 0.0),
              maxIndex < photos.count else {
            return nil
        }
        return photos[maxIndex]
    }
    
    /// Returns the largest quality gap between consecutive photos
    var largestQualityGap: Float {
        return qualityGaps.max() ?? 0.0
    }
    
    /// Indicates if there's a clear winner among the compared photos
    var hasClearWinner: Bool {
        return largestQualityGap > 0.3
    }
}

// MARK: - Photo Scoring Service Protocol

protocol PhotoScoringServiceProtocol {
    func scorePhoto(_ photo: Photo) async throws -> (technical: TechnicalQualityScore, face: FaceQualityScore, overall: PhotoScore)
    func scorePhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws -> [UUID: PhotoScore]
    func updatePhotoWithScores(photoId: UUID, technicalScore: TechnicalQualityScore, faceScore: FaceQualityScore, overallScore: PhotoScore) async throws
    func getPhotosNeedingScoring() async throws -> [Photo]
    func scoreAndPersistPhoto(_ photo: Photo) async throws
    func scoreAndPersistPhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws
    func rescorePhotosWithLowQuality(threshold: Float) async throws
    func getQualityDistribution(_ photos: [Photo]) -> [String: Int]
    func getTopQualityPhotos(_ photos: [Photo], count: Int) -> [Photo]
    func getPhotosNeedingImprovement(_ photos: [Photo]) -> [(Photo, [String])]
    func getAverageQualityScore(_ photos: [Photo]) -> Float
    func getPhotosByQualityThreshold(_ photos: [Photo], minimumScore: Float) -> [Photo]
    
    // MARK: - Cluster-Aware Ranking Methods
    func rankPhotosInCluster(_ cluster: PhotoCluster) async -> [Photo]
    func getClusterQualityDistribution(_ cluster: PhotoCluster) async -> ClusterQualityDistribution
    func comparePhotosInCluster(_ photos: [Photo], cluster: PhotoCluster) async -> ClusterPhotoComparison
}

// MARK: - Photo Scoring Service Implementation

class PhotoScoringService: PhotoScoringServiceProtocol {
    
    private let analysisService: PhotoAnalysisServiceProtocol
    private let photoRepository: PhotoDataRepositoryProtocol
    private let photoLibraryService: PhotoLibraryServiceProtocol
    private let categorizationService: PhotoCategorizationServiceProtocol
    private let contextService: PhotoContextServiceProtocol
    private let coreMLAestheticService: CoreMLAestheticServiceProtocol
    
    init(analysisService: PhotoAnalysisServiceProtocol = PhotoAnalysisService(),
         photoRepository: PhotoDataRepositoryProtocol = PhotoDataRepository(),
         photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService(),
         categorizationService: PhotoCategorizationServiceProtocol = PhotoCategorizationService(),
         contextService: PhotoContextServiceProtocol = PhotoContextService(),
         coreMLAestheticService: CoreMLAestheticServiceProtocol = CoreMLAestheticService()) {
        self.analysisService = analysisService
        self.photoRepository = photoRepository
        self.photoLibraryService = photoLibraryService
        self.categorizationService = categorizationService
        self.contextService = contextService
        self.coreMLAestheticService = coreMLAestheticService
    }
    
    // MARK: - Public Methods
    
    func scorePhoto(_ photo: Photo) async throws -> (technical: TechnicalQualityScore, face: FaceQualityScore, overall: PhotoScore) {
        // Load image for analysis
        guard let image = try await photoLibraryService.getFullResolutionImage(for: photo.assetIdentifier) else {
            throw PhotoCuratorError.invalidPhotoAsset(photo.assetIdentifier)
        }
        
        // Perform analysis
        let analysisResult = try await analysisService.analyzePhoto(photo, image: image)
        
        // Convert to our scoring models
        let technicalScore = createTechnicalScore(from: analysisResult)
        let faceScore = createFaceScore(from: analysisResult)
        let overallScore = await createOverallScore(from: analysisResult, technicalScore: technicalScore, faceScore: faceScore, photo: photo)
        
        return (technicalScore, faceScore, overallScore)
    }
    
    func scorePhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws -> [UUID: PhotoScore] {
        var scores: [UUID: PhotoScore] = [:]
        let totalPhotos = photos.count
        
        for (index, photo) in photos.enumerated() {
            do {
                let (_, _, overallScore) = try await scorePhoto(photo)
                scores[photo.id] = overallScore
            } catch {
                print("Failed to score photo \(photo.assetIdentifier): \(error)")
                // Continue with other photos
            }
            
            progressCallback(index + 1, totalPhotos)
        }
        
        return scores
    }
    
    func updatePhotoWithScores(photoId: UUID, technicalScore: TechnicalQualityScore, faceScore: FaceQualityScore, overallScore: PhotoScore) async throws {
        // Load the photo
        guard var photo = try await photoRepository.loadPhoto(by: photoId) else {
            throw PhotoCuratorError.invalidPhotoAsset(photoId.uuidString)
        }
        
        // Update scores
        photo.technicalQuality = technicalScore
        photo.faceQuality = faceScore
        photo.overallScore = overallScore
        
        // Save back to repository
        try await photoRepository.savePhoto(photo)
    }
    
    func getPhotosNeedingScoring() async throws -> [Photo] {
        return try await photoRepository.loadPhotosWithoutScores()
    }
    
    func scoreAndPersistPhoto(_ photo: Photo) async throws {
        let (technicalScore, faceScore, overallScore) = try await scorePhoto(photo)
        try await updatePhotoWithScores(
            photoId: photo.id,
            technicalScore: technicalScore,
            faceScore: faceScore,
            overallScore: overallScore
        )
    }
    
    func scoreAndPersistPhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws {
        let totalPhotos = photos.count
        
        for (index, photo) in photos.enumerated() {
            do {
                try await scoreAndPersistPhoto(photo)
            } catch {
                print("Failed to score and persist photo \(photo.assetIdentifier): \(error)")
                // Continue with other photos
            }
            
            progressCallback(index + 1, totalPhotos)
        }
    }
    
    // MARK: - Private Conversion Methods
    
    private func createTechnicalScore(from result: PhotoAnalysisResult) -> TechnicalQualityScore {
        // Enhanced composition scoring with saliency analysis
        var enhancedComposition = Float(result.compositionScore)
        
        // Boost composition score if saliency analysis shows good composition
        if let saliency = result.saliencyAnalysis {
            let saliencyBonus = saliency.compositionScore * 0.3 // Up to 30% bonus
            enhancedComposition = min(1.0, enhancedComposition + saliencyBonus)
        }
        
        return TechnicalQualityScore(
            sharpness: Float(result.sharpnessScore),
            exposure: Float(result.exposureScore),
            composition: enhancedComposition
        )
    }
    
    private func createFaceScore(from result: PhotoAnalysisResult) -> FaceQualityScore {
        guard !result.faces.isEmpty else {
            return FaceQualityScore.noFaces
        }
        
        let faceCount = result.faces.count
        
        // Enhanced face quality calculation with pose and expression analysis
        var totalQualityScore = 0.0
        var validFaceCount = 0
        
        for face in result.faces {
            var faceScore = face.faceQuality
            
            // Bonus for good pose (face looking toward camera)
            if let pose = face.pose {
                let poseQuality = calculatePoseQuality(pose)
                faceScore += Double(poseQuality) * 0.2 // Up to 20% bonus
            }
            
            // Expression bonus for smiles
            if face.isSmiling == true {
                faceScore += 0.15 // 15% bonus for smiling
            }
            
            // Eyes open bonus
            if face.eyesOpen == true {
                faceScore += 0.1 // 10% bonus for eyes open
            }
            
            totalQualityScore += min(1.0, faceScore)
            validFaceCount += 1
        }
        
        let averageQuality = validFaceCount > 0 ? totalQualityScore / Double(validFaceCount) : 0.0
        
        // Analyze face characteristics with enhanced logic
        let eyesOpen = result.faces.allSatisfy { $0.eyesOpen ?? true }
        let goodExpressions = analyzeExpressions(result.faces)
        let optimalSizes = analyzeFaceSizes(result.faces)
        
        return FaceQualityScore(
            faceCount: faceCount,
            averageScore: Float(averageQuality),
            eyesOpen: eyesOpen,
            goodExpressions: goodExpressions,
            optimalSizes: optimalSizes
        )
    }
    
    private func createOverallScore(from result: PhotoAnalysisResult, technicalScore: TechnicalQualityScore, faceScore: FaceQualityScore, photo: Photo) async -> PhotoScore {
        let technical = technicalScore.overall
        let faces = faceScore.compositeScore
        
        // Enhanced context scoring with comprehensive context analysis
        var enhancedContext = Float(result.aestheticScore)
        
        // Load image for Core ML aesthetic analysis
        guard let image = try? await photoLibraryService.getFullResolutionImage(for: photo.assetIdentifier) else {
            return createBasicOverallScore(result: result, technicalScore: technicalScore, faceScore: faceScore, photo: photo)
        }
        
        // Use Core ML enhanced aesthetic assessment
        let coreMLAestheticResult = await coreMLAestheticService.evaluateAesthetic(for: image)
        
        if let coreMLResult = coreMLAestheticResult {
            // Heavily penalize utility images identified by Core ML
            if coreMLResult.isUtility {
                enhancedContext = min(enhancedContext, 0.15) // Even stricter penalty for ML-detected utility images
            } else {
                // Blend Core ML aesthetic score with existing scores
                enhancedContext = enhancedContext * 0.4 + coreMLResult.aestheticScore * 0.6
            }
        }
        
        // Use Vision Framework aesthetic analysis as secondary validation
        if let aesthetics = result.aestheticAnalysis {
            if aesthetics.isUtility && coreMLAestheticResult?.isUtility != true {
                // Cross-validate utility detection
                enhancedContext = min(enhancedContext, 0.25)
            } else if !aesthetics.isUtility {
                // Normalize aesthetic score from -1,1 to 0,1 and blend
                let normalizedAesthetic = (aesthetics.overallScore + 1.0) / 2.0
                enhancedContext = enhancedContext * 0.8 + Float(normalizedAesthetic) * 0.2
            }
        }
        
        // Comprehensive context analysis
        let photoContext = contextService.analyzeContext(for: photo, result: result)
        let contextScore = contextService.calculateContextScore(from: photoContext)
        
        // Blend aesthetic and contextual scoring with Core ML enhancement
        enhancedContext = enhancedContext * 0.7 + contextScore * 0.3
        
        // Scene confidence boost for clear, recognizable content
        let sceneBonus = result.sceneConfidence * 0.06 // Reduced to balance with Core ML scores
        enhancedContext = min(1.0, enhancedContext + sceneBonus)
        
        // Determine photo type based on enhanced analysis
        let photoType = categorizationService.getPrimaryCategory(from: result, photo: photo)
        
        let overall = PhotoScore.calculate(
            technical: technical,
            faces: faces,
            context: enhancedContext,
            photoType: photoType
        )
        
        return PhotoScore(
            technical: technical,
            faces: faces,
            context: enhancedContext,
            overall: overall
        )
    }
    
    private func createBasicOverallScore(result: PhotoAnalysisResult, technicalScore: TechnicalQualityScore, faceScore: FaceQualityScore, photo: Photo) -> PhotoScore {
        // Fallback to basic scoring if Core ML analysis fails
        let technical = technicalScore.overall
        let faces = faceScore.compositeScore
        
        var enhancedContext = Float(result.aestheticScore)
        
        // Use Vision Framework aesthetic analysis if available
        if let aesthetics = result.aestheticAnalysis {
            if aesthetics.isUtility {
                enhancedContext = min(enhancedContext, 0.2)
            } else {
                let normalizedAesthetic = (aesthetics.overallScore + 1.0) / 2.0
                enhancedContext = Float(enhancedContext * 0.3 + normalizedAesthetic * 0.7)
            }
        }
        
        let photoContext = contextService.analyzeContext(for: photo, result: result)
        let contextScore = contextService.calculateContextScore(from: photoContext)
        enhancedContext = enhancedContext * 0.6 + contextScore * 0.4
        
        let sceneBonus = result.sceneConfidence * 0.08
        enhancedContext = min(1.0, enhancedContext + sceneBonus)
        
        let photoType = categorizationService.getPrimaryCategory(from: result, photo: photo)
        let overall = PhotoScore.calculate(technical: technical, faces: faces, context: enhancedContext, photoType: photoType)
        
        return PhotoScore(technical: technical, faces: faces, context: enhancedContext, overall: overall)
    }
    
    private func analyzeFaceSizes(_ faces: [FaceAnalysis]) -> Bool {
        // Check if faces are reasonably sized (not too small or too large)
        return faces.allSatisfy { face in
            let faceArea = face.boundingBox.width * face.boundingBox.height
            return faceArea >= 0.01 && faceArea <= 0.5 // 1% to 50% of image area
        }
    }
    
    private func determinePhotoType(from result: PhotoAnalysisResult) -> PhotoType {
        let faceCount = result.faces.count
        
        if faceCount > 1 {
            return .multipleFaces
        } else if faceCount == 1 {
            return .portrait
        } else {
            // Enhanced landscape detection using objects and aesthetic analysis
            let landscapeKeywords = ["mountain", "tree", "sky", "water", "landscape", "nature", "outdoor", "scenery", "field", "forest", "beach", "sunset", "sunrise"]
            let hasLandscapeObjects = result.objects.contains { object in
                landscapeKeywords.contains { keyword in
                    object.identifier.lowercased().contains(keyword)
                }
            }
            
            // Also check for high aesthetic score without utility flag (often landscapes)
            let isAestheticLandscape = result.aestheticAnalysis?.isUtility == false && 
                                     (result.aestheticAnalysis?.overallScore ?? -1) > 0.3
            
            return (hasLandscapeObjects || isAestheticLandscape) ? .landscape : .portrait
        }
    }
    
    // MARK: - Enhanced Analysis Helper Methods
    
    private func calculatePoseQuality(_ pose: FacePose) -> Float {
        var poseScore: Float = 1.0
        
        // Penalize extreme poses (face turned too far from camera)
        if let yaw = pose.yaw {
            let yawPenalty = min(abs(yaw) / 45.0, 1.0) // Penalize yaw > 45 degrees
            poseScore -= yawPenalty * 0.3
        }
        
        if let pitch = pose.pitch {
            let pitchPenalty = min(abs(pitch) / 30.0, 1.0) // Penalize pitch > 30 degrees
            poseScore -= pitchPenalty * 0.2
        }
        
        if let roll = pose.roll {
            let rollPenalty = min(abs(roll) / 20.0, 1.0) // Penalize roll > 20 degrees
            poseScore -= rollPenalty * 0.1
        }
        
        return max(0.0, poseScore)
    }
    
    private func analyzeExpressions(_ faces: [FaceAnalysis]) -> Bool {
        guard !faces.isEmpty else { return false }
        
        // Consider expressions "good" if majority are smiling or neutral
        let smilingCount = faces.filter { $0.isSmiling == true }.count
        let neutralCount = faces.filter { $0.isSmiling == nil }.count
        let goodExpressionCount = smilingCount + neutralCount
        
        return Float(goodExpressionCount) / Float(faces.count) >= 0.6 // 60% threshold
    }
    
    private func isGoldenHour(_ timestamp: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        
        // Golden hour: 6-8 AM or 6-8 PM
        return (hour >= 6 && hour <= 8) || (hour >= 18 && hour <= 20)
    }
}

// MARK: - Photo Type Classification
// Note: PhotoType enum is defined in Photo.swift

// MARK: - Quality Assessment Extensions

extension PhotoScoringService {
    
    // MARK: - Quality Rankings
    
    func rankPhotosByQuality(_ photos: [Photo]) -> [Photo] {
        return photos.sorted { photo1, photo2 in
            let score1 = photo1.overallScore?.overall ?? 0.0
            let score2 = photo2.overallScore?.overall ?? 0.0
            return score1 > score2
        }
    }
    
    func getTopQualityPhotos(_ photos: [Photo], count: Int) -> [Photo] {
        let rankedPhotos = rankPhotosByQuality(photos)
        return Array(rankedPhotos.prefix(count))
    }
    
    func getPhotosByQualityThreshold(_ photos: [Photo], minimumScore: Float) -> [Photo] {
        return photos.filter { photo in
            guard let overallScore = photo.overallScore else { return false }
            return overallScore.overall >= minimumScore
        }
    }
    
    // MARK: - Quality Analysis
    
    func getQualityDistribution(_ photos: [Photo]) -> [String: Int] {
        var distribution: [String: Int] = [
            "Excellent (0.8+)": 0,
            "Good (0.6-0.8)": 0,
            "Fair (0.4-0.6)": 0,
            "Poor (0.0-0.4)": 0,
            "Unscored": 0
        ]
        
        for photo in photos {
            guard let score = photo.overallScore?.overall else {
                distribution["Unscored"] = (distribution["Unscored"] ?? 0) + 1
                continue
            }
            
            switch score {
            case 0.8...1.0:
                distribution["Excellent (0.8+)"] = (distribution["Excellent (0.8+)"] ?? 0) + 1
            case 0.6..<0.8:
                distribution["Good (0.6-0.8)"] = (distribution["Good (0.6-0.8)"] ?? 0) + 1
            case 0.4..<0.6:
                distribution["Fair (0.4-0.6)"] = (distribution["Fair (0.4-0.6)"] ?? 0) + 1
            default:
                distribution["Poor (0.0-0.4)"] = (distribution["Poor (0.0-0.4)"] ?? 0) + 1
            }
        }
        
        return distribution
    }
    
    func getAverageQualityScore(_ photos: [Photo]) -> Float {
        let scoredPhotos = photos.compactMap { $0.overallScore?.overall }
        guard !scoredPhotos.isEmpty else { return 0.0 }
        
        let sum = scoredPhotos.reduce(0.0, +)
        return sum / Float(scoredPhotos.count)
    }
    
    func getPhotosNeedingImprovement(_ photos: [Photo]) -> [(Photo, [String])] {
        return photos.compactMap { photo in
            guard let technical = photo.technicalQuality,
                  let overall = photo.overallScore else { return nil }
            
            var issues: [String] = []
            
            if technical.sharpness < 0.5 {
                issues.append("Sharpness")
            }
            if technical.exposure < 0.5 {
                issues.append("Exposure")
            }
            if technical.composition < 0.5 {
                issues.append("Composition")
            }
            if overall.overall < 0.5 {
                issues.append("Overall Quality")
            }
            
            return issues.isEmpty ? nil : (photo, issues)
        }
    }
}

// MARK: - Batch Operations

extension PhotoScoringService {
    
    func scorePhotosInBatches(_ photos: [Photo], batchSize: Int = 20, progressCallback: @escaping (Int, Int) -> Void) async throws {
        let totalPhotos = photos.count
        var processedCount = 0
        
        // Process in batches to avoid memory issues
        for i in stride(from: 0, to: photos.count, by: batchSize) {
            let endIndex = min(i + batchSize, photos.count)
            let batch = Array(photos[i..<endIndex])
            
            try await scoreAndPersistPhotos(batch) { batchCompleted, batchTotal in
                let totalCompleted = processedCount + batchCompleted
                progressCallback(totalCompleted, totalPhotos)
            }
            
            processedCount += batch.count
        }
    }
    
    func rescorePhotosWithLowQuality(threshold: Float = 0.3) async throws {
        // Load all photos
        let allPhotos = try await photoRepository.loadPhotos()
        
        // Find photos that need rescoring
        let photosToRescore = allPhotos.filter { photo in
            guard let score = photo.overallScore?.overall else { return true } // Rescore unscored photos
            return score < threshold
        }
        
        print("Rescoring \(photosToRescore.count) photos with quality below \(threshold)")
        
        try await scorePhotosInBatches(photosToRescore) { completed, total in
            print("Rescoring progress: \(completed)/\(total)")
        }
    }
}

// MARK: - Cluster-Aware Ranking

extension PhotoScoringService {
    
    /// Ranks photos within a cluster using cluster-specific context and weighting
    /// Provides enhanced ranking that considers cluster type, photo diversity, and relative quality
    /// - Parameter cluster: The photo cluster to analyze and rank
    /// - Returns: Array of photos sorted by cluster-aware ranking (best first)
    func rankPhotosInCluster(_ cluster: PhotoCluster) async -> [Photo] {
        guard !cluster.photos.isEmpty else { return [] }
        
        // Detect cluster type for appropriate weighting
        let clusterType = await detectClusterType(cluster)
        
        // Calculate cluster-aware scores for all photos
        var photosWithScores: [(photo: Photo, clusterScore: Float)] = []
        
        for photo in cluster.photos {
            let clusterScore = await calculateClusterAwareScore(photo: photo, in: cluster, clusterType: clusterType)
            photosWithScores.append((photo: photo, clusterScore: clusterScore))
        }
        
        // Sort by cluster-aware score (highest first)
        return photosWithScores.sorted { $0.clusterScore > $1.clusterScore }.map { $0.photo }
    }
    
    /// Calculates cluster-specific quality distribution for thumbnail selection optimization
    /// - Parameter cluster: The photo cluster to analyze
    /// - Returns: Quality distribution data with cluster-specific insights
    func getClusterQualityDistribution(_ cluster: PhotoCluster) async -> ClusterQualityDistribution {
        guard !cluster.photos.isEmpty else {
            return ClusterQualityDistribution(
                totalPhotos: 0,
                qualityBreakdown: [:],
                recommendedThumbnail: nil,
                clusterType: .utility,
                averageQuality: 0.0,
                qualityRange: 0.0
            )
        }
        
        let clusterType = await detectClusterType(cluster)
        var qualityBreakdown: [String: Int] = [
            "Excellent": 0,
            "Good": 0,
            "Fair": 0,
            "Poor": 0
        ]
        
        var scores: [Float] = []
        var bestPhoto: Photo?
        var bestScore: Float = 0.0
        
        for photo in cluster.photos {
            let clusterScore = await calculateClusterAwareScore(photo: photo, in: cluster, clusterType: clusterType)
            scores.append(clusterScore)
            
            // Track best photo for thumbnail recommendation
            if clusterScore > bestScore {
                bestScore = clusterScore
                bestPhoto = photo
            }
            
            // Categorize quality
            switch clusterScore {
            case 0.8...1.0:
                qualityBreakdown["Excellent"] = (qualityBreakdown["Excellent"] ?? 0) + 1
            case 0.6..<0.8:
                qualityBreakdown["Good"] = (qualityBreakdown["Good"] ?? 0) + 1
            case 0.4..<0.6:
                qualityBreakdown["Fair"] = (qualityBreakdown["Fair"] ?? 0) + 1
            default:
                qualityBreakdown["Poor"] = (qualityBreakdown["Poor"] ?? 0) + 1
            }
        }
        
        let averageQuality = scores.isEmpty ? 0.0 : scores.reduce(0, +) / Float(scores.count)
        let qualityRange = scores.isEmpty ? 0.0 : (scores.max() ?? 0.0) - (scores.min() ?? 0.0)
        
        return ClusterQualityDistribution(
            totalPhotos: cluster.photos.count,
            qualityBreakdown: qualityBreakdown,
            recommendedThumbnail: bestPhoto,
            clusterType: clusterType,
            averageQuality: averageQuality,
            qualityRange: qualityRange
        )
    }
    
    /// Performs relative quality comparison within cluster context
    /// - Parameters:
    ///   - photos: Photos to compare
    ///   - cluster: Cluster context for comparison
    /// - Returns: Comparison result with relative rankings
    func comparePhotosInCluster(_ photos: [Photo], cluster: PhotoCluster) async -> ClusterPhotoComparison {
        guard photos.count >= 2 else {
            return ClusterPhotoComparison(
                photos: photos,
                relativeScores: photos.map { _ in 0.5 },
                qualityGaps: [],
                recommendations: []
            )
        }
        
        let clusterType = await detectClusterType(cluster)
        var relativeScores: [Float] = []
        var qualityGaps: [Float] = []
        
        // Calculate cluster-aware scores for comparison
        var scores: [Float] = []
        for photo in photos {
            let score = await calculateClusterAwareScore(photo: photo, in: cluster, clusterType: clusterType)
            scores.append(score)
        }
        
        // Calculate relative scores (normalized within this subset)
        let maxScore = scores.max() ?? 1.0
        let minScore = scores.min() ?? 0.0
        let scoreRange = maxScore - minScore
        
        for score in scores {
            let relativeScore = scoreRange > 0 ? (score - minScore) / scoreRange : 0.5
            relativeScores.append(relativeScore)
        }
        
        // Calculate quality gaps between consecutive photos
        for i in 1..<scores.count {
            qualityGaps.append(scores[i-1] - scores[i])
        }
        
        // Generate recommendations
        let recommendations = generateClusterRankingRecommendations(
            photos: photos,
            scores: scores,
            clusterType: clusterType
        )
        
        return ClusterPhotoComparison(
            photos: photos,
            relativeScores: relativeScores,
            qualityGaps: qualityGaps,
            recommendations: recommendations
        )
    }
    
    // MARK: - Private Helper Methods
    
    /// Detects the dominant photo type in a cluster for appropriate ranking weights
    private func detectClusterType(_ cluster: PhotoCluster) async -> PhotoType {
        guard !cluster.photos.isEmpty else { return .utility }
        
        // Sample photos to determine cluster type
        let sampleSize = min(3, cluster.photos.count)
        let samplePhotos = Array(cluster.photos.prefix(sampleSize))
        
        var typeVotes: [PhotoType: Int] = [:]
        
        for photo in samplePhotos {
            let photoType = PhotoType.detect(from: photo)
            typeVotes[photoType, default: 0] += 1
        }
        
        // Return the most common type, or portrait as fallback
        return typeVotes.max(by: { $0.value < $1.value })?.key ?? .portrait
    }
    
    /// Calculates cluster-aware quality score with context-specific weighting
    private func calculateClusterAwareScore(photo: Photo, in cluster: PhotoCluster, clusterType: PhotoType) async -> Float {
        // Get base quality scores
        let baseQuality: Float
        if let overallScore = photo.overallScore?.overall {
            baseQuality = overallScore
        } else {
            // Calculate quality score using existing private method
            baseQuality = await calculateFallbackQualityScore(photo)
        }
        
        let technicalQuality = photo.technicalQuality?.overall ?? 0.5
        let faceQuality = photo.faceQuality?.compositeScore ?? 0.5
        
        // Apply cluster type-specific weighting
        let clusterScore: Float
        
        switch clusterType {
        case .portrait, .groupPhoto, .multipleFaces:
            // Person-focused: prioritize facial quality
            clusterScore = baseQuality * 0.3 + technicalQuality * 0.2 + faceQuality * 0.5
            
        case .landscape, .outdoor, .goldenHour:
            // Scenery-focused: prioritize technical quality and composition
            clusterScore = baseQuality * 0.5 + technicalQuality * 0.4 + faceQuality * 0.1
            
        case .event:
            // Event photos: balance all factors with slight face preference
            clusterScore = baseQuality * 0.4 + technicalQuality * 0.25 + faceQuality * 0.35
            
        case .closeUp:
            // Close-ups: heavy technical emphasis
            clusterScore = baseQuality * 0.3 + technicalQuality * 0.6 + faceQuality * 0.1
            
        default:
            // Default balanced weighting
            clusterScore = baseQuality * 0.5 + technicalQuality * 0.3 + faceQuality * 0.2
        }
        
        // Apply diversity bonus for variety within cluster
        let diversityBonus = calculateDiversityBonus(photo: photo, in: cluster)
        
        return min(1.0, clusterScore + diversityBonus)
    }
    
    /// Calculates diversity bonus for photos that add variety to cluster representation
    private func calculateDiversityBonus(photo: Photo, in cluster: PhotoCluster) -> Float {
        // Simple diversity bonus based on timestamp spread
        guard cluster.photos.count > 1 else { return 0.0 }
        
        let timestamps = cluster.photos.map { $0.timestamp }
        let photoTime = photo.timestamp
        
        // Photos at the temporal edges of the cluster get slight bonus for representing timeline diversity
        let sortedTimes = timestamps.sorted()
        if let firstTime = sortedTimes.first, let lastTime = sortedTimes.last {
            let totalDuration = lastTime.timeIntervalSince(firstTime)
            if totalDuration > 0 {
                let positionInTimeline = photoTime.timeIntervalSince(firstTime) / totalDuration
                
                // Bonus for photos at beginning (0.0) or end (1.0) of timeline
                let edgeBonus = min(positionInTimeline, 1.0 - positionInTimeline)
                return Float(edgeBonus * 0.05) // Small bonus up to 5%
            }
        }
        
        return 0.0
    }
    
    /// Calculates a fallback quality score when overall score is not available
    private func calculateFallbackQualityScore(_ photo: Photo) async -> Float {
        // Use the existing getPhotoQualityScore method from the main class
        var score: Float = 0.5 // Base score
        
        // Boost for face photos
        if let faceQuality = photo.faceQuality, faceQuality.faceCount > 0 {
            score += 0.2
            if faceQuality.faceCount > 1 {
                score += 0.1 // Group photos get extra boost
            }
        }
        
        // Technical quality factors
        if let techQuality = photo.technicalQuality {
            score += techQuality.sharpness * 0.1
            score += techQuality.exposure * 0.1
            score += techQuality.composition * 0.1
        }
        
        return min(1.0, score)
    }
    
    /// Generates ranking recommendations based on cluster analysis
    private func generateClusterRankingRecommendations(
        photos: [Photo],
        scores: [Float],
        clusterType: PhotoType
    ) -> [String] {
        var recommendations: [String] = []
        
        // Find best and worst photos
        guard let maxScore = scores.max(),
              let minScore = scores.min() else {
            return ["Unable to analyze photo quality"]
        }
        
        let scoreRange = maxScore - minScore
        
        // Recommendation based on score distribution
        if scoreRange < 0.2 {
            recommendations.append("Photos have similar quality - any could serve as thumbnail")
        } else if scoreRange > 0.5 {
            recommendations.append("Significant quality variation - best photo is much better choice")
        }
        
        // Type-specific recommendations
        switch clusterType {
        case .portrait, .groupPhoto, .multipleFaces:
            recommendations.append("For group photos, prioritizing facial quality and expressions")
        case .landscape, .outdoor:
            recommendations.append("For landscape photos, prioritizing composition and technical quality")
        case .event:
            recommendations.append("For event photos, balancing faces and overall scene quality")
        default:
            recommendations.append("Using balanced quality assessment")
        }
        
        return recommendations
    }
}