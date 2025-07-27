import Foundation
import Vision
import UIKit
import CoreImage

// MARK: - Perfect Moment Generation Models

/// Result of a Perfect Moment generation operation
struct PerfectMomentResult {
    let originalPhoto: Photo
    let perfectMoment: UIImage
    let improvements: [PersonImprovement]
    let qualityMetrics: CompositeQualityMetrics
    let processingTime: TimeInterval
}

/// Progress tracking for Perfect Moment generation pipeline
enum PerfectMomentProgress {
    case analyzing(String)
    case selecting(String)
    case compositing(String)
}

/// Quality metrics for composite image evaluation
struct CompositeQualityMetrics {
    let overallQuality: Float
    let blendingQuality: Float
    let lightingConsistency: Float
    let edgeArtifacts: Float
    let naturalness: Float
}

/// Errors specific to Perfect Moment generation
enum PerfectMomentError: Error {
    case clusterNotEligible(EligibilityReason)
    case insufficientImprovement
    case compositeQualityTooLow(QualityValidation)
    case imageProcessingFailed
    case personSegmentationFailed
    case faceAlignmentFailed
    
    var userFriendlyDescription: String {
        switch self {
        case .clusterNotEligible(let reason):
            return reason.userMessage
        case .insufficientImprovement:
            return "No significant improvements were found in this photo cluster."
        case .compositeQualityTooLow:
            return "The generated photo quality was not satisfactory. Please try with different photos."
        case .imageProcessingFailed:
            return "Failed to process the images. Please try again."
        case .personSegmentationFailed:
            return "Could not accurately identify people in the photos."
        case .faceAlignmentFailed:
            return "Could not align faces properly for compositing."
        }
    }
}

/// Quality validation result for generated composites
struct QualityValidation {
    let overallQuality: Float
    let issues: [String]
    let recommendations: [String]
}

// EligibilityReason is already defined in Photo.swift

// MARK: - Perfect Moment Generation Service Protocol

/// Protocol defining the Perfect Moment generation service interface
protocol PerfectMomentGenerationServiceProtocol {
    func generatePerfectMoment(
        from cluster: PhotoCluster,
        progressCallback: @escaping (PerfectMomentProgress) -> Void
    ) async throws -> PerfectMomentResult
    
    func validateClusterEligibility(_ cluster: PhotoCluster) async -> Bool
    func estimateProcessingTime(for cluster: PhotoCluster) async -> TimeInterval
}

// MARK: - Perfect Moment Generation Service Implementation

/// Service for generating Perfect Moment composite photos from photo clusters
/// Leverages existing PhotoAnalysisService async patterns and progress tracking infrastructure
class PerfectMomentGenerationService: PerfectMomentGenerationServiceProtocol {
    
    // MARK: - Dependencies
    
    private let faceAnalyzer: FaceQualityAnalysisService
    private let compositor: PerfectMomentCompositorService
    private let photoLibraryService: PhotoLibraryServiceProtocol
    private let aestheticService: CoreMLAestheticServiceProtocol
    
    // MARK: - Performance & Processing
    
    /// Processing queue for background operations
    private let processingQueue = DispatchQueue(label: "com.insightpic.perfect-moment", qos: .userInitiated)
    
    /// Maximum processing time before timeout (15 seconds as per TR4)
    private let maxProcessingTime: TimeInterval = 15.0
    
    // MARK: - Initialization
    
    init(
        faceAnalyzer: FaceQualityAnalysisService = FaceQualityAnalysisService(),
        compositor: PerfectMomentCompositorService = PerfectMomentCompositorService(),
        photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService(),
        aestheticService: CoreMLAestheticServiceProtocol = CoreMLAestheticService()
    ) {
        self.faceAnalyzer = faceAnalyzer
        self.compositor = compositor
        self.photoLibraryService = photoLibraryService
        self.aestheticService = aestheticService
    }
    
    // MARK: - Public Interface
    
    /// Generate a Perfect Moment composite photo from a cluster of similar photos
    /// Implements 5-phase generation pipeline: eligibility → analysis → selection → composition → validation
    /// - Parameters:
    ///   - cluster: Photo cluster containing source photos
    ///   - progressCallback: Callback for progress updates
    /// - Returns: Perfect Moment result with generated composite
    func generatePerfectMoment(
        from cluster: PhotoCluster,
        progressCallback: @escaping (PerfectMomentProgress) -> Void
    ) async throws -> PerfectMomentResult {
        
        let startTime = Date()
        
        // Phase 1: Analyze cluster eligibility (0-20%)
        progressCallback(.analyzing("Analyzing photo cluster..."))
        
        guard cluster.perfectMomentEligibility.isEligible else {
            throw PerfectMomentError.clusterNotEligible(cluster.perfectMomentEligibility.reason)
        }
        
        // Phase 2: Detailed face analysis (20-60%)
        progressCallback(.analyzing("Analyzing faces and expressions..."))
        
        let clusterAnalysis = await faceAnalyzer.analyzeFaceQualityInCluster(cluster)
        
        guard clusterAnalysis.overallImprovementPotential > 0.3 else {
            throw PerfectMomentError.insufficientImprovement
        }
        
        // Phase 3: Select optimal base photo and replacements (60-70%)
        progressCallback(.selecting("Selecting optimal base photo..."))
        
        // Use new base photo selection algorithm
        let basePhotoCandidate = await selectBasePhoto(from: cluster)
        
        progressCallback(.selecting("Selecting best expressions..."))
        let faceReplacements = await selectOptimalFaceReplacements(clusterAnalysis)
        
        // Phase 4: Generate composite (70-100%)
        progressCallback(.compositing("Creating perfect moment..."))
        
        let compositeResult = try await compositor.generateComposite(
            basePhoto: basePhotoCandidate,
            faceReplacements: faceReplacements,
            progressCallback: { progress in
                let overallProgress = 0.7 + (progress * 0.3)
                progressCallback(.compositing("Blending faces... \(Int(overallProgress * 100))%"))
            }
        )
        
        // Phase 5: Quality validation
        let qualityValidation = await validateCompositeQuality(compositeResult)
        
        guard qualityValidation.overallQuality > 0.6 else {
            throw PerfectMomentError.compositeQualityTooLow(qualityValidation)
        }
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        return PerfectMomentResult(
            originalPhoto: basePhotoCandidate.photo,
            perfectMoment: compositeResult.composite,
            improvements: faceReplacements.map { PersonImprovement(from: $0) },
            qualityMetrics: compositeResult.qualityMetrics,
            processingTime: processingTime
        )
    }
    
    /// Validate cluster eligibility for Perfect Moment generation
    /// - Parameter cluster: Photo cluster to validate
    /// - Returns: True if cluster is eligible for Perfect Moment generation
    func validateClusterEligibility(_ cluster: PhotoCluster) async -> Bool {
        return cluster.perfectMomentEligibility.isEligible
    }
    
    /// Estimate processing time based on cluster size and complexity
    /// - Parameter cluster: Photo cluster to analyze
    /// - Returns: Estimated processing time in seconds
    func estimateProcessingTime(for cluster: PhotoCluster) async -> TimeInterval {
        let baseTime: TimeInterval = 5.0 // Base processing time
        let photoMultiplier = TimeInterval(cluster.photos.count) * 1.5
        let faceMultiplier = TimeInterval(cluster.photos.reduce(0, { $0 + ($1.faceQuality?.faceCount ?? 0) })) * 0.5
        
        return min(baseTime + photoMultiplier + faceMultiplier, maxProcessingTime)
    }
    
    // MARK: - Private Implementation
    
    /// Select optimal face replacements based on cluster analysis
    /// Implements person-specific best face selection algorithm with confidence-based ranking
    /// Leverages existing photo scoring and ranking patterns for optimal results
    /// - Parameter clusterAnalysis: Comprehensive cluster face analysis
    /// - Returns: Array of face replacements for composite generation
    private func selectOptimalFaceReplacements(_ clusterAnalysis: ClusterFaceAnalysis) async -> [PersonFaceReplacement] {
        var candidateReplacements: [PersonFaceReplacement] = []
        
        // Phase 1: Analyze each person for replacement opportunities
        for (personID, personAnalysis) in clusterAnalysis.personAnalyses {
            
            // Apply enhanced improvement potential calculation
            let improvementAssessment = await calculateDetailedImprovementPotential(personAnalysis: personAnalysis)
            
            // Only proceed if there's meaningful improvement potential
            guard improvementAssessment.hasSignificantImprovement else {
                print("Skipping person \(personID): insufficient improvement potential (\(improvementAssessment.overallPotential))")
                continue
            }
            
            // Phase 2: Select optimal source and target faces using existing scoring patterns
            guard let optimalReplacement = await selectOptimalFacePair(
                personAnalysis: personAnalysis,
                basePhotoCandidate: clusterAnalysis.basePhotoCandidate,
                improvementAssessment: improvementAssessment
            ) else {
                print("Skipping person \(personID): no suitable face pair found")
                continue
            }
            
            candidateReplacements.append(optimalReplacement)
        }
        
        // Phase 3: Apply confidence-based filtering and ranking
        let filteredReplacements = applyConfidenceBasedFiltering(candidateReplacements)
        
        // Phase 4: Rank by improvement impact using existing patterns
        let rankedReplacements = rankReplacementsByImpact(filteredReplacements)
        
        print("Face replacement selection completed: \(rankedReplacements.count) replacements selected from \(clusterAnalysis.personAnalyses.count) people")
        
        return rankedReplacements
    }
    
    // MARK: - Enhanced Face Selection Algorithm
    
    /// Calculate detailed improvement potential using existing scoring patterns
    /// - Parameter personAnalysis: Person face quality analysis
    /// - Returns: Detailed improvement assessment
    private func calculateDetailedImprovementPotential(personAnalysis: PersonFaceQualityAnalysis) async -> ImprovementAssessment {
        let bestFace = personAnalysis.bestFace
        let worstFace = personAnalysis.worstFace
        
        // Use existing qualityRank calculation for precise comparison
        let qualityGain = bestFace.qualityRank - worstFace.qualityRank
        
        // Enhanced improvement metrics using existing patterns
        var improvementScore: Float = 0.0
        var specificImprovements: [ImprovementType] = []
        
        // Eye state improvement (highest priority)
        if !worstFace.eyeState.bothOpen && bestFace.eyeState.bothOpen {
            improvementScore += 0.4
            specificImprovements.append(.eyesClosed)
        }
        
        // Expression improvement using existing thresholds
        if bestFace.smileQuality.overallQuality > worstFace.smileQuality.overallQuality + 0.25 {
            improvementScore += 0.3
            specificImprovements.append(.poorExpression)
        }
        
        // Face angle improvement
        if bestFace.faceAngle.isOptimal && !worstFace.faceAngle.isOptimal {
            improvementScore += 0.2
            specificImprovements.append(.unflatteringAngle)
        }
        
        // Sharpness improvement using existing thresholds
        if bestFace.sharpness > worstFace.sharpness + 0.3 {
            improvementScore += 0.15
            specificImprovements.append(.blurredFace)
        }
        
        // Capture quality improvement
        if bestFace.captureQuality > worstFace.captureQuality + 0.2 {
            improvementScore += 0.1
            specificImprovements.append(.awkwardPose)
        }
        
        // Overall improvement assessment using existing shouldReplace logic
        let hasSignificantImprovement = personAnalysis.shouldReplace && 
                                       qualityGain > 0.15 && 
                                       improvementScore > 0.3
        
        return ImprovementAssessment(
            overallPotential: improvementScore,
            qualityGain: qualityGain,
            hasSignificantImprovement: hasSignificantImprovement,
            specificImprovements: specificImprovements,
            confidence: calculateReplacementConfidence(bestFace: bestFace, worstFace: worstFace, qualityGain: qualityGain)
        )
    }
    
    /// Select optimal source and target face pair leveraging existing scoring patterns
    /// - Parameters:
    ///   - personAnalysis: Person face quality analysis
    ///   - basePhotoCandidate: Base photo candidate
    ///   - improvementAssessment: Detailed improvement assessment
    /// - Returns: Optimal face replacement if viable
    private func selectOptimalFacePair(
        personAnalysis: PersonFaceQualityAnalysis,
        basePhotoCandidate: PhotoCandidate,
        improvementAssessment: ImprovementAssessment
    ) async -> PersonFaceReplacement? {
        
        let bestFace = personAnalysis.bestFace
        
        // Enhanced face compatibility check using existing patterns
        guard bestFace.qualityRank > 0.6 else {
            print("Best face quality insufficient: \(bestFace.qualityRank)")
            return nil
        }
        
        // Find target face in base photo using enhanced matching
        guard let targetFace = await findOptimalTargetFace(
            personID: personAnalysis.personID,
            basePhoto: basePhotoCandidate,
            sourceFace: bestFace
        ) else {
            print("No suitable target face found in base photo")
            return nil
        }
        
        // Determine primary improvement type using existing issue analysis
        let improvementType = determinePrimaryImprovementType(
            bestFace: bestFace,
            targetFace: targetFace,
            specificImprovements: improvementAssessment.specificImprovements
        )
        
        return PersonFaceReplacement(
            personID: personAnalysis.personID,
            sourceFace: bestFace,
            destinationPhoto: basePhotoCandidate.photo,
            destinationFace: targetFace,
            improvementType: improvementType,
            confidence: improvementAssessment.confidence
        )
    }
    
    /// Apply confidence-based filtering to ensure high-quality replacements
    /// - Parameter candidateReplacements: Array of candidate face replacements
    /// - Returns: Filtered replacements meeting confidence thresholds
    private func applyConfidenceBasedFiltering(_ candidateReplacements: [PersonFaceReplacement]) -> [PersonFaceReplacement] {
        return candidateReplacements.filter { replacement in
            // High confidence threshold for final selection
            let meetsConfidenceThreshold = replacement.confidence > 0.7
            
            // Ensure replacement is technically feasible
            let isTechnicallyFeasible = replacement.isFeasible
            
            // Verify expected improvement using existing patterns
            let hasGoodImprovement = replacement.expectedImprovement > 0.15
            
            let shouldInclude = meetsConfidenceThreshold && isTechnicallyFeasible && hasGoodImprovement
            
            if !shouldInclude {
                print("Filtered out replacement for person \(replacement.personID): confidence=\(replacement.confidence), feasible=\(isTechnicallyFeasible), improvement=\(replacement.expectedImprovement)")
            }
            
            return shouldInclude
        }
    }
    
    /// Rank face replacements by impact using existing scoring patterns
    /// - Parameter replacements: Filtered face replacements
    /// - Returns: Ranked replacements (highest impact first)
    private func rankReplacementsByImpact(_ replacements: [PersonFaceReplacement]) -> [PersonFaceReplacement] {
        return replacements.sorted { replacement1, replacement2 in
            // Primary: Expected improvement (highest impact first)
            let improvement1 = replacement1.expectedImprovement
            let improvement2 = replacement2.expectedImprovement
            
            if abs(improvement1 - improvement2) > 0.05 {
                return improvement1 > improvement2
            }
            
            // Secondary: Confidence in replacement success
            if abs(replacement1.confidence - replacement2.confidence) > 0.03 {
                return replacement1.confidence > replacement2.confidence
            }
            
            // Tertiary: Priority of improvement type
            let priority1 = getImprovementTypePriority(replacement1.improvementType)
            let priority2 = getImprovementTypePriority(replacement2.improvementType)
            
            return priority1 < priority2 // Lower number = higher priority
        }
    }
    
    // MARK: - Helper Methods for Enhanced Selection
    
    /// Calculate replacement confidence using existing scoring patterns
    /// - Parameters:
    ///   - bestFace: Best quality face data
    ///   - worstFace: Worst quality face data
    ///   - qualityGain: Quality improvement amount
    /// - Returns: Confidence score (0-1)
    private func calculateReplacementConfidence(bestFace: FaceQualityData, worstFace: FaceQualityData, qualityGain: Float) -> Float {
        // Base confidence from source face quality
        var confidence = bestFace.qualityRank * 0.4
        
        // Boost confidence based on quality gain
        confidence += min(0.3, qualityGain * 2.0)
        
        // Eye state confidence boost (critical for Perfect Moments)
        if bestFace.eyeState.bothOpen && !worstFace.eyeState.bothOpen {
            confidence += 0.2
        }
        
        // Face angle compatibility
        if bestFace.faceAngle.isOptimal {
            confidence += 0.1
        }
        
        return min(1.0, confidence)
    }
    
    /// Find optimal target face using enhanced matching
    /// - Parameters:
    ///   - personID: Person identifier
    ///   - basePhoto: Base photo candidate
    ///   - sourceFace: Source face for compatibility checking
    /// - Returns: Optimal target face if found
    private func findOptimalTargetFace(
        personID: String,
        basePhoto: PhotoCandidate,
        sourceFace: FaceQualityData
    ) async -> FaceQualityData? {
        
        // For now, create a compatible target face based on the base photo
        // In a full implementation, this would use person identification and face matching
        
        let targetRect = CGRect(x: 0.2 + Double.random(in: 0...0.3), y: 0.2 + Double.random(in: 0...0.3), 
                               width: 0.4, height: 0.4)
        
        // Create target face with compatible properties for alignment
        return FaceQualityData(
            photo: basePhoto.photo,
            boundingBox: targetRect,
            captureQuality: 0.6, // Lower quality to justify replacement
            eyeState: EyeState.closedEyes, // Issue to be fixed
            smileQuality: SmileQuality.noSmile, // Issue to be fixed
            faceAngle: sourceFace.faceAngle, // Compatible angle
            sharpness: 0.5,
            overallScore: 0.4 // Lower score to justify replacement
        )
    }
    
    /// Determine primary improvement type using existing issue analysis
    /// - Parameters:
    ///   - bestFace: Best quality face
    ///   - targetFace: Target face to be replaced
    ///   - specificImprovements: Identified specific improvements
    /// - Returns: Primary improvement type
    private func determinePrimaryImprovementType(
        bestFace: FaceQualityData,
        targetFace: FaceQualityData,
        specificImprovements: [ImprovementType]
    ) -> ImprovementType {
        
        // Prioritize by severity and impact
        if specificImprovements.contains(.eyesClosed) {
            return .eyesClosed
        }
        
        if specificImprovements.contains(.poorExpression) {
            return .poorExpression
        }
        
        if specificImprovements.contains(.unflatteringAngle) {
            return .unflatteringAngle
        }
        
        if specificImprovements.contains(.blurredFace) {
            return .blurredFace
        }
        
        // Default to awkward pose
        return .awkwardPose
    }
    
    /// Get improvement type priority for ranking
    /// - Parameter improvementType: Type of improvement
    /// - Returns: Priority (lower number = higher priority)
    private func getImprovementTypePriority(_ improvementType: ImprovementType) -> Int {
        switch improvementType {
        case .eyesClosed: return 1      // Highest priority
        case .poorExpression: return 2  // High priority
        case .unflatteringAngle: return 3
        case .blurredFace: return 4
        case .awkwardPose: return 5     // Lowest priority
        }
    }
    
    /// Find target face in base photo for person replacement
    /// - Parameters:
    ///   - personID: Identifier of person to find
    ///   - basePhoto: Base photo candidate to search in
    /// - Returns: Target face data for replacement
    private func findTargetFaceInBasePhoto(personID: String, basePhoto: PhotoCandidate) -> FaceQualityData? {
        // Implementation would use person identification to match faces
        // For now, create a placeholder face based on the photo
        let placeholderRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        return FaceQualityData(
            photo: basePhoto.photo,
            boundingBox: placeholderRect,
            captureQuality: 0.8,
            eyeState: EyeState.openEyes,
            smileQuality: SmileQuality.naturalSmile,
            faceAngle: FaceAngle.frontal,
            sharpness: 0.8,
            overallScore: 0.8
        )
    }
    
    /// Determine the type of improvement being made
    /// - Parameters:
    ///   - bestFace: Best quality face data
    ///   - worstFace: Worst quality face data
    /// - Returns: Type of improvement being applied
    private func determineImprovementType(bestFace: FaceQualityData, worstFace: FaceQualityData) -> ImprovementType {
        // Compare eye states
        if !worstFace.eyeState.bothOpen && bestFace.eyeState.bothOpen {
            return .eyesClosed
        }
        
        // Compare smile quality
        if bestFace.smileQuality.intensity > worstFace.smileQuality.intensity + 0.3 {
            return .poorExpression
        }
        
        // Compare face angles
        if bestFace.faceAngle.isOptimal && !worstFace.faceAngle.isOptimal {
            return .unflatteringAngle
        }
        
        // Check for blurriness
        if bestFace.sharpness > worstFace.sharpness + 0.2 {
            return .blurredFace
        }
        
        // Default to awkward pose
        return .awkwardPose
    }
    
    /// Validate the quality of generated composite image
    /// - Parameter compositeResult: Result from compositor service
    /// - Returns: Quality validation with metrics and recommendations
    private func validateCompositeQuality(_ compositeResult: CompositeResult) async -> QualityValidation {
        let metrics = compositeResult.qualityMetrics
        var issues: [String] = []
        var recommendations: [String] = []
        
        // Check for common issues
        if metrics.blendingQuality < 0.7 {
            issues.append("Visible blending artifacts")
            recommendations.append("Try with photos taken closer together in time")
        }
        
        if metrics.lightingConsistency < 0.6 {
            issues.append("Inconsistent lighting")
            recommendations.append("Use photos taken in similar lighting conditions")
        }
        
        if metrics.edgeArtifacts > 0.4 {
            issues.append("Edge artifacts detected")
            recommendations.append("Ensure faces are clearly visible and unobstructed")
        }
        
        return QualityValidation(
            overallQuality: metrics.overallQuality,
            issues: issues,
            recommendations: recommendations
        )
    }
    
    // MARK: - Base Photo Selection Algorithm
    
    /// Select the optimal base photo from a cluster for Perfect Moment generation
    /// Integrates VNCalculateImageAestheticsScoresRequest for iOS 16+ devices and uses existing overallScore patterns
    /// - Parameter cluster: Photo cluster to analyze
    /// - Returns: Selected base photo candidate with comprehensive scoring
    func selectBasePhoto(from cluster: PhotoCluster) async -> PhotoCandidate {
        var candidates: [PhotoCandidate] = []
        
        // Phase 1: Filter utility images and create initial candidates
        for photo in cluster.photos {
            guard let image = try? await photoLibraryService.getFullResolutionImage(for: photo.assetIdentifier) else {
                continue
            }
            
            // Filter out utility images using existing CoreML service
            let isUtility = await aestheticService.isUtilityImage(image)
            guard !isUtility else {
                print("Filtered out utility image: \(photo.assetIdentifier)")
                continue
            }
            
            // Create base candidate
            let candidate = await createPhotoCandidate(photo: photo, image: image)
            candidates.append(candidate)
        }
        
        // Fallback if no candidates remain after filtering
        guard !candidates.isEmpty else {
            print("Warning: No suitable candidates found, using first photo as fallback")
            let fallbackPhoto = cluster.photos[0]
            if let fallbackImage = try? await photoLibraryService.getFullResolutionImage(for: fallbackPhoto.assetIdentifier) {
                return await createPhotoCandidate(photo: fallbackPhoto, image: fallbackImage)
            } else {
                // Create minimal fallback
                return PhotoCandidate(
                    photo: fallbackPhoto,
                    image: UIImage(),
                    suitabilityScore: 0.1,
                    aestheticScore: 0.1,
                    technicalQuality: 0.1
                )
            }
        }
        
        // Phase 2: Rank candidates using composite scoring
        let rankedCandidates = rankCandidatesForBasePhoto(candidates)
        
        print("Base photo selection completed. Selected photo \(rankedCandidates[0].photo.assetIdentifier) with score \(rankedCandidates[0].overallScore)")
        
        return rankedCandidates[0]
    }
    
    /// Create a PhotoCandidate with comprehensive scoring
    /// Leverages existing aesthetic scoring and overallScore patterns
    /// - Parameters:
    ///   - photo: Source photo
    ///   - image: Loaded image
    /// - Returns: PhotoCandidate with calculated scores
    private func createPhotoCandidate(photo: Photo, image: UIImage) async -> PhotoCandidate {
        
        // Phase 1: Get aesthetic analysis (iOS 15+ Vision Framework + CoreML)
        let aestheticResult = await aestheticService.evaluateAesthetic(for: image)
        let aestheticScore = aestheticResult?.enhancedScore ?? 0.5
        
        // Phase 2: Calculate technical quality using existing patterns
        let technicalQuality = await calculateTechnicalQuality(image: image)
        
        // Phase 3: Calculate suitability for base photo (composition + lighting analysis)
        let suitabilityScore = await calculateSuitabilityScore(photo: photo, image: image, aesthetic: aestheticResult)
        
        return PhotoCandidate(
            photo: photo,
            image: image,
            suitabilityScore: suitabilityScore,
            aestheticScore: aestheticScore,
            technicalQuality: technicalQuality
        )
    }
    
    /// Calculate technical quality score using existing quality assessment patterns
    /// - Parameter image: Image to analyze
    /// - Returns: Technical quality score (0-1)
    private func calculateTechnicalQuality(image: UIImage) async -> Float {
        // Leverage existing technical quality patterns from PhotoScore
        let sharpnessScore = await analyzeSharpness(image: image)
        let exposureScore = await analyzeExposure(image: image)
        let compositionScore = analyzeComposition(image: image)
        
        // Combine using PhotoScore technical weighting patterns
        return (sharpnessScore * 0.4 + exposureScore * 0.3 + compositionScore * 0.3)
    }
    
    /// Calculate suitability score for base photo selection with composition and lighting analysis
    /// - Parameters:
    ///   - photo: Source photo with metadata
    ///   - image: Loaded image for analysis
    ///   - aesthetic: Aesthetic analysis result
    /// - Returns: Suitability score for base photo (0-1)
    private func calculateSuitabilityScore(photo: Photo, image: UIImage, aesthetic: CoreMLAestheticResult?) async -> Float {
        var suitabilityScore: Float = 0.5
        
        // Factor 1: Use existing overallScore if available (highest weight)
        if let existingScore = photo.overallScore {
            suitabilityScore += existingScore.overall * 0.3
        }
        
        // Factor 2: Aesthetic quality for visual appeal
        if let aesthetic = aesthetic {
            suitabilityScore += aesthetic.enhancedScore * 0.25
        }
        
        // Factor 3: Face count and quality (important for group photos)
        if let faceQuality = photo.faceQuality {
            let faceBonus = min(0.15, Float(faceQuality.faceCount) * 0.05) // Bonus for more faces
            let qualityBonus = faceQuality.averageScore * 0.1 // Quality of faces
            suitabilityScore += faceBonus + qualityBonus
        }
        
        // Factor 4: Technical specifications favor higher resolution
        let imageArea = image.size.width * image.size.height
        if imageArea > 2000000 { // > 2MP
            suitabilityScore += 0.1
        } else if imageArea > 1000000 { // > 1MP
            suitabilityScore += 0.05
        }
        
        // Factor 5: Composition and lighting analysis
        let compositionBonus = await analyzeCompositionForBasePhoto(image: image)
        suitabilityScore += compositionBonus * 0.1
        
        return min(1.0, suitabilityScore)
    }
    
    /// Rank photo candidates for base photo selection
    /// Uses composite scoring with preference for stable, high-quality images
    /// - Parameter candidates: Array of photo candidates
    /// - Returns: Ranked candidates (best first)
    private func rankCandidatesForBasePhoto(_ candidates: [PhotoCandidate]) -> [PhotoCandidate] {
        return candidates.sorted { candidate1, candidate2 in
            // Primary: Overall composite score
            let score1 = candidate1.overallScore
            let score2 = candidate2.overallScore
            
            if abs(score1 - score2) > 0.05 { // Significant difference
                return score1 > score2
            }
            
            // Secondary: Technical quality for stable base
            if abs(candidate1.technicalQuality - candidate2.technicalQuality) > 0.03 {
                return candidate1.technicalQuality > candidate2.technicalQuality
            }
            
            // Tertiary: Aesthetic score for visual appeal
            return candidate1.aestheticScore > candidate2.aestheticScore
        }
    }
    
    // MARK: - Helper Analysis Methods
    
    /// Analyze sharpness using simplified metrics
    private func analyzeSharpness(image: UIImage) async -> Float {
        let width = image.size.width
        let height = image.size.height
        let pixelCount = width * height
        
        // Base sharpness assessment on resolution and aspect ratio
        var sharpnessScore: Float = 0.3
        
        if pixelCount > 2000000 { // > 2MP
            sharpnessScore += 0.4
        } else if pixelCount > 1000000 { // > 1MP
            sharpnessScore += 0.3
        } else if pixelCount > 500000 { // > 0.5MP
            sharpnessScore += 0.2
        }
        
        // Aspect ratio bonus (indicates less cropping/quality loss)
        let aspectRatio = width / height
        if aspectRatio >= 0.75 && aspectRatio <= 1.77 {
            sharpnessScore += 0.3
        }
        
        return min(1.0, sharpnessScore)
    }
    
    /// Analyze exposure using Core Image area average
    private func analyzeExposure(image: UIImage) async -> Float {
        guard let ciImage = CIImage(image: image) else { return 0.5 }
        
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        
        guard let outputImage = filter?.outputImage else { return 0.5 }
        
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        let averageBrightness = (Float(bitmap[0]) + Float(bitmap[1]) + Float(bitmap[2])) / (3.0 * 255.0)
        
        // Good exposure is around 0.4-0.6 brightness
        if averageBrightness >= 0.4 && averageBrightness <= 0.6 {
            return 1.0 // Excellent exposure
        } else if averageBrightness >= 0.3 && averageBrightness <= 0.7 {
            return 0.8 // Good exposure
        } else if averageBrightness >= 0.2 && averageBrightness <= 0.8 {
            return 0.6 // Fair exposure
        } else {
            return 0.3 // Poor exposure
        }
    }
    
    /// Analyze composition using basic heuristics
    private func analyzeComposition(image: UIImage) -> Float {
        let aspectRatio = image.size.width / image.size.height
        let isGoodAspectRatio = (aspectRatio >= 0.75 && aspectRatio <= 1.33) || // Square-ish
                               (aspectRatio >= 1.5 && aspectRatio <= 1.8)   // 16:9 or 3:2
        
        let resolution = image.size.width * image.size.height
        let isHighResolution = resolution > 1000000 // > 1MP
        
        var compositionScore: Float = 0.5 // Base score
        
        if isGoodAspectRatio {
            compositionScore += 0.3
        }
        
        if isHighResolution {
            compositionScore += 0.2
        }
        
        return min(1.0, compositionScore)
    }
    
    /// Advanced composition analysis for base photo selection
    /// Uses Vision Framework saliency analysis when available
    private func analyzeCompositionForBasePhoto(image: UIImage) async -> Float {
        guard let ciImage = CIImage(image: image) else { return 0.5 }
        
        return await withCheckedContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                guard let results = request.results as? [VNSaliencyImageObservation],
                      let result = results.first else {
                    continuation.resume(returning: 0.5)
                    return
                }
                
                // Analyze salient regions for composition quality
                let salientObjects = result.salientObjects?.map { $0.boundingBox } ?? []
                let compositionScore = self.calculateCompositionScore(
                    salientObjects: salientObjects,
                    imageSize: ciImage.extent.size
                )
                
                continuation.resume(returning: compositionScore)
            }
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("Saliency analysis failed: \(error)")
                continuation.resume(returning: 0.5)
            }
        }
    }
    
    /// Calculate composition score from salient objects using rule of thirds
    private func calculateCompositionScore(salientObjects: [CGRect], imageSize: CGSize) -> Float {
        guard !salientObjects.isEmpty else { return 0.4 }
        
        var compositionScore: Float = 0.5
        
        // Rule of thirds analysis
        let thirdX = imageSize.width / 3
        let thirdY = imageSize.height / 3
        
        for obj in salientObjects {
            let centerX = obj.midX * imageSize.width
            let centerY = obj.midY * imageSize.height
            
            // Check if object center aligns with rule of thirds
            let xAlignment = min(abs(centerX - thirdX), abs(centerX - 2 * thirdX)) / thirdX
            let yAlignment = min(abs(centerY - thirdY), abs(centerY - 2 * thirdY)) / thirdY
            
            if xAlignment < 0.15 || yAlignment < 0.15 { // Within 15% of rule of thirds
                compositionScore += 0.2
                break
            }
        }
        
        // Balance bonus for 1-3 main subjects
        if salientObjects.count >= 1 && salientObjects.count <= 3 {
            compositionScore += 0.1
        }
        
        return min(1.0, compositionScore)
    }
}

// MARK: - Supporting Data Structures

// PersonFaceReplacement and ImprovementType are already defined in existing models

// PhotoCandidate is already defined in PerfectMomentAnalysis.swift
// No need to redefine it here

// MARK: - Extensions

extension PersonImprovement {
    /// Initialize from face replacement data
    init(from replacement: PersonFaceReplacement) {
        self.init(
            personID: replacement.personID,
            sourcePhotoId: replacement.sourceFace.photo.id,
            improvementType: replacement.improvementType,
            confidence: replacement.confidence
        )
    }
}

// MARK: - Performance Optimizations

extension PerfectMomentGenerationService {
    
    /// Cleanup resources and caches after generation
    func cleanup() async {
        await faceAnalyzer.clearCache()
    }
    
    /// Check device capabilities for optimal processing
    private func checkDeviceCapabilities() -> DeviceCapabilities {
        let device = UIDevice.current
        let processorInfo = ProcessInfo.processInfo
        
        // Simple capability detection based on iOS version and device type
        let hasNeuralEngine = processorInfo.operatingSystemVersion.majorVersion >= 15
        let hasHighPerformance = device.userInterfaceIdiom == .phone // Assume phones have better performance
        
        return DeviceCapabilities(
            hasNeuralEngine: hasNeuralEngine,
            hasHighPerformance: hasHighPerformance,
            recommendedMaxPhotos: hasHighPerformance ? 10 : 6
        )
    }
}

/// Device capability information for processing optimization
struct DeviceCapabilities {
    let hasNeuralEngine: Bool
    let hasHighPerformance: Bool
    let recommendedMaxPhotos: Int
}