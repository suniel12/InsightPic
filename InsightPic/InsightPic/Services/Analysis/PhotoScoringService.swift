import Foundation
import UIKit

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
}

// MARK: - Photo Scoring Service Implementation

class PhotoScoringService: PhotoScoringServiceProtocol {
    
    private let analysisService: PhotoAnalysisServiceProtocol
    private let photoRepository: PhotoDataRepositoryProtocol
    private let photoLibraryService: PhotoLibraryServiceProtocol
    private let categorizationService: PhotoCategorizationServiceProtocol
    private let contextService: PhotoContextServiceProtocol
    
    init(analysisService: PhotoAnalysisServiceProtocol = PhotoAnalysisService(),
         photoRepository: PhotoDataRepositoryProtocol = PhotoDataRepository(),
         photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService(),
         categorizationService: PhotoCategorizationServiceProtocol = PhotoCategorizationService(),
         contextService: PhotoContextServiceProtocol = PhotoContextService()) {
        self.analysisService = analysisService
        self.photoRepository = photoRepository
        self.photoLibraryService = photoLibraryService
        self.categorizationService = categorizationService
        self.contextService = contextService
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
        let overallScore = createOverallScore(from: analysisResult, technicalScore: technicalScore, faceScore: faceScore, photo: photo)
        
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
    
    private func createOverallScore(from result: PhotoAnalysisResult, technicalScore: TechnicalQualityScore, faceScore: FaceQualityScore, photo: Photo) -> PhotoScore {
        let technical = technicalScore.overall
        let faces = faceScore.compositeScore
        
        // Enhanced context scoring with comprehensive context analysis
        var enhancedContext = Float(result.aestheticScore)
        
        // Use Vision Framework aesthetic analysis if available
        if let aesthetics = result.aestheticAnalysis {
            // Heavily penalize utility images (screenshots, documents)
            if aesthetics.isUtility {
                enhancedContext = min(enhancedContext, 0.2) // Cap utility images at 20%
            } else {
                // Normalize aesthetic score from -1,1 to 0,1 and blend with basic score
                let normalizedAesthetic = (aesthetics.overallScore + 1.0) / 2.0
                enhancedContext = Float(enhancedContext * 0.3 + normalizedAesthetic * 0.7)
            }
        }
        
        // Comprehensive context analysis
        let photoContext = contextService.analyzeContext(for: photo, result: result)
        let contextScore = contextService.calculateContextScore(from: photoContext)
        
        // Blend aesthetic and contextual scoring
        enhancedContext = enhancedContext * 0.6 + contextScore * 0.4
        
        // Scene confidence boost for clear, recognizable content
        let sceneBonus = result.sceneConfidence * 0.08 // Up to 8% bonus (reduced to balance context)
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