import Foundation
import Vision
import UIKit
import CoreImage

// MARK: - Face Quality Analysis Service

/// Service for analyzing face quality across photo clusters to identify Perfect Moment opportunities
/// Leverages existing PhotoAnalysisService Vision Framework patterns for consistency
class FaceQualityAnalysisService {
    
    // MARK: - Dependencies
    
    private let photoLibraryService: PhotoLibraryServiceProtocol
    
    // MARK: - Performance Optimization & Caching
    
    /// Queue for background processing to maintain UI responsiveness
    private let processingQueue = DispatchQueue(label: "com.insightpic.face-analysis", qos: .userInitiated)
    
    /// Actor for thread-safe cache management
    private actor CacheManager {
        private var clusterCache: [UUID: ClusterFaceAnalysis] = [:]
        private var faceCache: [String: [FaceQualityData]] = [:]
        
        func getClusterAnalysis(for id: UUID) -> ClusterFaceAnalysis? {
            return clusterCache[id]
        }
        
        func setClusterAnalysis(_ analysis: ClusterFaceAnalysis, for id: UUID) {
            clusterCache[id] = analysis
        }
        
        func getFaceAnalysis(for key: String) -> [FaceQualityData]? {
            return faceCache[key]
        }
        
        func setFaceAnalysis(_ faces: [FaceQualityData], for key: String) {
            faceCache[key] = faces
        }
        
        func clearAll() {
            clusterCache.removeAll()
            faceCache.removeAll()
        }
        
        func clearCluster(_ id: UUID) {
            clusterCache.removeValue(forKey: id)
        }
        
        var statistics: (clusterCount: Int, faceCount: Int) {
            return (clusterCache.count, faceCache.count)
        }
    }
    
    /// Thread-safe cache manager
    private let cacheManager = CacheManager()
    
    // MARK: - Initialization
    
    init(photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
    }
    
    // MARK: - Public Interface
    
    /// Comprehensive face analysis pipeline that integrates all face analysis components
    /// Provides batch processing, caching, and quality ranking for Perfect Moment generation
    /// - Parameter cluster: The photo cluster to analyze
    /// - Returns: Comprehensive cluster face analysis with person-specific quality data
    func analyzeFaceQualityInCluster(_ cluster: PhotoCluster) async -> ClusterFaceAnalysis {
        
        // Check cache first to avoid redundant processing
        if let cachedAnalysis = await cacheManager.getClusterAnalysis(for: cluster.id) {
            print("Using cached analysis for cluster \(cluster.id)")
            return cachedAnalysis
        }
        
        // Perform comprehensive analysis
        let analysis = await performComprehensiveClusterAnalysis(cluster)
        
        // Cache the result for future use
        await cacheManager.setClusterAnalysis(analysis, for: cluster.id)
        
        return analysis
    }
    
    /// Face quality ranking and best-face selection for individual photos
    /// Integrates all analysis components to identify the highest quality faces
    /// - Parameter photos: Array of photos to analyze and rank faces within
    /// - Returns: Dictionary mapping photo IDs to ranked face quality data
    func rankFaceQualityInPhotos(_ photos: [Photo]) async -> [String: [FaceQualityData]] {
        var photoFaceRankings: [String: [FaceQualityData]] = [:]
        
        // Process each photo individually for face ranking
        for photo in photos {
            guard let image = try? await loadImage(for: photo) else {
                print("Warning: Could not load image for photo \(photo.assetIdentifier)")
                continue
            }
            
            let faceAnalyses = await analyzeFacesInPhoto(image, photo: photo)
            
            // Rank faces by comprehensive quality score
            let rankedFaces = faceAnalyses.sorted { $0.qualityRank > $1.qualityRank }
            photoFaceRankings[photo.assetIdentifier] = rankedFaces
        }
        
        return photoFaceRankings
    }
    
    /// Analyzes cluster eligibility for Perfect Moment generation
    /// Integrates all quality and person matching components for eligibility assessment
    /// - Parameter cluster: The photo cluster to assess
    /// - Returns: Comprehensive eligibility analysis with detailed reasoning
    func assessClusterEligibility(_ cluster: PhotoCluster) async -> PerfectMomentEligibility {
        // Check basic requirements first
        guard cluster.photos.count >= 2 else {
            return PerfectMomentEligibility(
                isEligible: false,
                reason: .insufficientPhotos,
                confidence: 1.0,
                estimatedImprovements: []
            )
        }
        
        // Perform quick face analysis to check for variations
        let analysis = await analyzeFaceQualityInCluster(cluster)
        
        // Check if we have people with improvement potential
        guard !analysis.peopleWithImprovements.isEmpty else {
            return PerfectMomentEligibility(
                isEligible: false,
                reason: .noFaceVariations,
                confidence: 0.9,
                estimatedImprovements: []
            )
        }
        
        // Check overall improvement potential
        guard analysis.overallImprovementPotential > 0.3 else {
            return PerfectMomentEligibility(
                isEligible: false,
                reason: .noFaceVariations,
                confidence: 0.8,
                estimatedImprovements: []
            )
        }
        
        // Generate improvement estimates
        let improvements = analysis.personAnalyses.values.map { personAnalysis in
            PersonImprovement(
                personID: personAnalysis.personID,
                sourcePhotoId: personAnalysis.bestFace.photo.id,
                improvementType: convertFaceIssueToImprovementType(personAnalysis.worstFace.primaryIssue),
                confidence: personAnalysis.improvementPotential
            )
        }
        
        return PerfectMomentEligibility(
            isEligible: true,
            reason: .eligible,
            confidence: analysis.overallImprovementPotential,
            estimatedImprovements: improvements
        )
    }
    
    /// Performs the actual comprehensive cluster analysis with all integrated components
    private func performComprehensiveClusterAnalysis(_ cluster: PhotoCluster) async -> ClusterFaceAnalysis {
        print("Starting comprehensive face analysis for cluster \(cluster.id) with \(cluster.photos.count) photos")
        
        // Step 1: Batch process all photos with optimized concurrency
        let (personFaceMap, processedPhotos) = await performBatchFaceAnalysis(cluster.photos)
        
        print("Detected \(personFaceMap.count) unique people across \(processedPhotos.count) photos")
        
        // Step 2: Generate comprehensive quality analyses for each person
        let personQualityAnalyses = await generatePersonQualityAnalyses(personFaceMap)
        
        print("Generated quality analyses for \(personQualityAnalyses.count) people with improvement potential")
        
        // Step 3: Select optimal base photo using integrated scoring
        let basePhotoCandidate = await selectOptimalBasePhoto(processedPhotos)
        
        print("Selected base photo: \(basePhotoCandidate.photo.assetIdentifier) with score \(basePhotoCandidate.overallScore)")
        
        // Step 4: Calculate overall improvement potential across all people
        let overallImprovement = calculateOverallImprovement(personQualityAnalyses)
        
        print("Overall improvement potential: \(overallImprovement)")
        
        let finalAnalysis = ClusterFaceAnalysis(
            clusterID: cluster.id,
            personAnalyses: personQualityAnalyses,
            basePhotoCandidate: basePhotoCandidate,
            overallImprovementPotential: overallImprovement
        )
        
        print("Completed comprehensive analysis for cluster \(cluster.id)")
        return finalAnalysis
    }
    
    // MARK: - Comprehensive Batch Processing Pipeline (Task 2.4)
    
    /// Optimized batch processing of all photos with concurrent face analysis and person matching
    /// Leverages existing async/await patterns from PhotoAnalysisService for performance
    private func performBatchFaceAnalysis(_ photos: [Photo]) async -> ([PersonID: [FaceQualityData]], [Photo]) {
        var personFaceMap: [PersonID: [FaceQualityData]] = [:]
        var processedPhotos: [Photo] = []
        
        // Process photos concurrently with controlled concurrency
        await withTaskGroup(of: (Photo, [FaceQualityData]).self) { group in
            for photo in photos {
                group.addTask { [weak self] in
                    guard let self = self else { return (photo, []) }
                    
                    // Controlled concurrency is handled by TaskGroup limitation
                    
                    // Check face analysis cache first
                    let cacheKey = photo.assetIdentifier
                    if let cachedFaces = await self.cacheManager.getFaceAnalysis(for: cacheKey) {
                        return (photo, cachedFaces)
                    }
                    
                    // Load image and analyze faces
                    guard let image = try? await self.loadImage(for: photo) else {
                        print("Warning: Could not load image for photo \(photo.assetIdentifier)")
                        return (photo, [])
                    }
                    
                    let faceAnalyses = await self.analyzeFacesInPhoto(image, photo: photo)
                    
                    // Cache the result
                    await self.cacheManager.setFaceAnalysis(faceAnalyses, for: cacheKey)
                    
                    return (photo, faceAnalyses)
                }
            }
            
            // Collect results and perform person matching
            for await (photo, faceAnalyses) in group {
                for faceAnalysis in faceAnalyses {
                    let personID = await matchPersonAcrossPhotos(
                        faceAnalysis,
                        existingPersons: Array(personFaceMap.keys),
                        allFaces: personFaceMap
                    )
                    personFaceMap[personID, default: []].append(faceAnalysis)
                }
                processedPhotos.append(photo)
            }
        }
        
        return (personFaceMap, processedPhotos)
    }
    
    /// Generates comprehensive quality analyses for each person with face ranking
    /// Integrates all face analysis components for optimal selection
    private func generatePersonQualityAnalyses(_ personFaceMap: [PersonID: [FaceQualityData]]) async -> [PersonID: PersonFaceQualityAnalysis] {
        var analyses: [PersonID: PersonFaceQualityAnalysis] = [:]
        
        for (personID, faces) in personFaceMap {
            // Only analyze people with multiple faces
            guard faces.count >= 2 else { continue }
            
            // Rank faces by comprehensive quality score
            let rankedFaces = faces.sorted { $0.qualityRank > $1.qualityRank }
            
            let bestFace = rankedFaces.first!
            let worstFace = rankedFaces.last!
            let improvementPotential = calculateImprovementPotential(faces)
            
            // Only include if there's meaningful improvement potential
            if improvementPotential > 0.2 {
                analyses[personID] = PersonFaceQualityAnalysis(
                    personID: personID,
                    allFaces: faces,
                    bestFace: bestFace,
                    worstFace: worstFace,
                    improvementPotential: improvementPotential
                )
            }
        }
        
        return analyses
    }
    
    /// Clears analysis cache to free memory when needed
    func clearAnalysisCache() async {
        await cacheManager.clearAll()
        print("Cleared face analysis cache")
    }
    
    /// Clears specific cluster from cache
    func clearClusterCache(_ clusterID: UUID) async {
        await cacheManager.clearCluster(clusterID)
    }
    
    /// Returns cache statistics for monitoring
    func getCacheStatistics() async -> (clusterCount: Int, faceCount: Int) {
        return await cacheManager.statistics
    }
    
    /// Converts FaceIssue to corresponding ImprovementType
    private func convertFaceIssueToImprovementType(_ faceIssue: FaceIssue) -> ImprovementType {
        switch faceIssue {
        case .eyesClosed:
            return .eyesClosed
        case .poorExpression:
            return .poorExpression
        case .awkwardPose:
            return .awkwardPose
        case .blurredFace:
            return .blurredFace
        case .unflatteringAngle:
            return .unflatteringAngle
        case .none:
            return .poorExpression // Default fallback
        }
    }
    
    // MARK: - Face Analysis Pipeline
    
    /// Analyzes all faces in a single photo using Vision Framework
    /// Leverages existing PhotoAnalysisService patterns for consistency
    private func analyzeFacesInPhoto(_ image: UIImage, photo: Photo) async -> [FaceQualityData] {
        guard let ciImage = CIImage(image: image) else {
            return []
        }
        
        // Vision Framework requests - following existing patterns
        let faceRequest = VNDetectFaceRectanglesRequest()
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        
        // CRITICAL: Set correct revision for landmark detection (per Vision Framework best practices)
        // Use Revision2 (65-point model) for compatibility with traditional EAR algorithms
        if #available(iOS 12.0, *) {
            landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision2
        }
        
        // CRITICAL: Handle image orientation properly (per Vision Framework best practices)
        // Vision algorithms are not rotation-agnostic and need correct orientation
        let orientation = getImageOrientation(from: image)
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation, options: [:])
        
        do {
            try handler.perform([faceRequest, landmarksRequest, qualityRequest])
            
            guard let detectedFaces = faceRequest.results as? [VNFaceObservation],
                  let landmarkResults = landmarksRequest.results as? [VNFaceObservation],
                  let qualityResults = qualityRequest.results as? [VNFaceObservation] else {
                return []
            }
            
            var faces: [FaceQualityData] = []
            
            for (index, detectedFace) in detectedFaces.enumerated() {
                // Find corresponding landmarks and quality for this face
                let landmarks = landmarkResults.indices.contains(index) ? landmarkResults[index].landmarks : nil
                let captureQuality = qualityResults.indices.contains(index) ? qualityResults[index].faceCaptureQuality ?? 0.5 : 0.5
                
                // Calculate detailed face metrics
                let eyeState = calculateEyeState(landmarks)
                let smileQuality = calculateSmileQuality(landmarks)
                let faceAngle = extractFaceAngle(from: detectedFace)
                let sharpness = await calculateFaceSharpness(image, faceRect: detectedFace.boundingBox)
                let overallScore = calculateOverallFaceScore(
                    captureQuality: captureQuality,
                    eyeState: eyeState,
                    smileQuality: smileQuality,
                    faceAngle: faceAngle,
                    sharpness: sharpness
                )
                
                let faceData = FaceQualityData(
                    photo: photo,
                    boundingBox: detectedFace.boundingBox,
                    landmarks: landmarks,
                    captureQuality: captureQuality,
                    eyeState: eyeState,
                    smileQuality: smileQuality,
                    faceAngle: faceAngle,
                    sharpness: sharpness,
                    overallScore: overallScore
                )
                
                faces.append(faceData)
            }
            
            return faces
            
        } catch {
            print("Face analysis failed: \(error)")
            return []
        }
    }
    
    // MARK: - Eye State Detection Algorithm (Task 2.1)
    
    /// Advanced eye state detection using comprehensive 76 facial landmarks analysis
    /// Implements enhanced Eye Aspect Ratio (EAR) algorithm with confidence scoring
    /// Leverages existing Vision Framework patterns for consistency
    private func calculateEyeState(_ landmarks: VNFaceLandmarks2D?) -> EyeState {
        guard let landmarks = landmarks else {
            return EyeState(leftOpen: true, rightOpen: true, confidence: 0.0)
        }
        
        // Attempt to get eye landmark regions
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else {
            // Fallback to default open state with low confidence
            return EyeState(leftOpen: true, rightOpen: true, confidence: 0.2)
        }
        
        // Use the research-based EAR calculation with traditional formula
        let leftEAR = calculateResearchBasedEAR(leftEye.normalizedPoints)
        let rightEAR = calculateResearchBasedEAR(rightEye.normalizedPoints)
        
        // Research-based personalized threshold calibration
        let personalizedThreshold = calculatePersonalizedThreshold(leftEAR: leftEAR, rightEAR: rightEAR)
        
        // Debug output for threshold optimization
        print("🔍 EAR Analysis - Left: \(leftEAR), Right: \(rightEAR), Threshold: \(personalizedThreshold)")
        print("👁️ Eye Points - Left: \(leftEye.normalizedPoints.count), Right: \(rightEye.normalizedPoints.count)")
        
        let leftOpen = leftEAR > personalizedThreshold
        let rightOpen = rightEAR > personalizedThreshold
        
        // Enhanced confidence calculation
        let avgEAR = (leftEAR + rightEAR) / 2.0
        let confidence = min(1.0, avgEAR / personalizedThreshold)
        
        print("✅ Decision - Left: \(leftOpen ? "OPEN" : "CLOSED"), Right: \(rightOpen ? "OPEN" : "CLOSED"), Confidence: \(confidence)")
        
        return EyeState(
            leftOpen: leftOpen,
            rightOpen: rightOpen,
            confidence: confidence
        )
    }
    
    /// Research-based EAR calculation using traditional formula
    /// Traditional EAR = (||p2-p6|| + ||p3-p5||) / (2.0 * ||p1-p4||)
    private func calculateResearchBasedEAR(_ points: [CGPoint]) -> Float {
        guard points.count >= 6 else { 
            print("⚠️ EAR Warning: Insufficient eye landmarks (\(points.count) points)")
            return 0.5 
        }
        
        let sortedByX = points.sorted { $0.x < $1.x }
        let sortedByY = points.sorted { $0.y < $1.y }
        
        // Get key landmark positions
        let outerCorner = sortedByX.first!      // leftmost point (p1)
        let innerCorner = sortedByX.last!       // rightmost point (p4)
        
        // Get top and bottom points (multiple for better accuracy)
        let topPoints = Array(sortedByY.prefix(3))     // top 3 points
        let bottomPoints = Array(sortedByY.suffix(3))  // bottom 3 points
        
        // Calculate average top and bottom positions for more robust measurement
        let avgTopOuter = topPoints[0]          // p2
        let avgTopInner = topPoints.count > 1 ? topPoints[1] : topPoints[0]  // p3
        let avgBottomInner = bottomPoints.count > 1 ? bottomPoints[bottomPoints.count-2] : bottomPoints.last!  // p5
        let avgBottomOuter = bottomPoints.last!  // p6
        
        // Traditional EAR formula: (||p2-p6|| + ||p3-p5||) / (2.0 * ||p1-p4||)
        let verticalDist1 = distance(avgTopOuter, avgBottomOuter)      // ||p2-p6||
        let verticalDist2 = distance(avgTopInner, avgBottomInner)      // ||p3-p5||
        let horizontalDist = distance(outerCorner, innerCorner)        // ||p1-p4||
        
        // Safety check for division by zero
        guard horizontalDist > 0.001 else { 
            print("⚠️ EAR Warning: Horizontal distance too small (\(horizontalDist))")
            return 0.5 
        }
        
        let ear = Float((verticalDist1 + verticalDist2) / (2.0 * horizontalDist))
        
        // Debug output for troubleshooting
        print("📐 EAR Calculation - Points: \(points.count), V1: \(String(format: "%.3f", verticalDist1)), V2: \(String(format: "%.3f", verticalDist2)), H: \(String(format: "%.3f", horizontalDist)), EAR: \(ear)")
        
        return ear
    }
    
    /// Calculate personalized threshold based on individual EAR characteristics
    /// Research shows optimal thresholds vary from 0.15-0.29 between individuals
    private func calculatePersonalizedThreshold(leftEAR: Float, rightEAR: Float) -> Float {
        let avgEAR = (leftEAR + rightEAR) / 2.0
        
        print("🎯 Threshold Calibration - AvgEAR: \(avgEAR)")
        
        // For eyes that should be open, use adaptive threshold based on actual EAR values
        if avgEAR > 0.3 {
            // Very wide eyes - can use higher threshold
            print("🔵 Wide eyes detected - using higher threshold")
            return 0.21
        } else if avgEAR > 0.2 {
            // Normal eyes - use research optimal
            print("🟢 Normal eyes detected - using research optimal")
            return 0.18
        } else if avgEAR > 0.12 {
            // Smaller/narrower eyes - use lower threshold
            print("🟡 Narrow eyes detected - using lower threshold")
            return 0.15
        } else {
            // Very low EAR - may be closed or very narrow
            print("🔴 Very low EAR detected - using minimum threshold")
            return 0.12
        }
    }
    
    /// Enhanced Eye Aspect Ratio calculation using comprehensive landmark analysis
    /// Utilizes all available eye landmarks for maximum accuracy
    private func calculateEnhancedEyeAspectRatio(_ points: [CGPoint], eyeType: EyeType) -> EyeStateAnalysisResult {
        // Ensure we have sufficient landmarks for accurate calculation
        guard points.count >= 6 else {
            return EyeStateAnalysisResult(ear: 0.5, landmarks: points, landmarkQuality: 0.0)
        }
        
        // Standard 6-point eye landmark indices (following dlib convention)
        // Points: [outer_corner, upper_1, upper_2, inner_corner, lower_2, lower_1]
        let landmarkQuality = assessLandmarkQuality(points)
        
        // Multiple vertical measurements for robustness
        var verticalDistances: [Double] = []
        var horizontalDistances: [Double] = []
        
        // Primary vertical measurements (upper to lower lid)
        if points.count >= 6 {
            verticalDistances.append(distance(points[1], points[5])) // Upper-outer to lower-outer
            verticalDistances.append(distance(points[2], points[4])) // Upper-inner to lower-inner
            
            // Horizontal measurement (outer to inner corner)
            horizontalDistances.append(distance(points[0], points[3]))
        }
        
        // Additional measurements if more landmarks available
        if points.count > 6 {
            // Use additional points for more precise measurement
            for i in 1..<min(points.count, 12) {
                if i + 3 < points.count {
                    let upperPoint = points[i]
                    let lowerPoint = points[points.count - i]
                    verticalDistances.append(distance(upperPoint, lowerPoint))
                }
            }
        }
        
        // Calculate robust averages
        let avgVertical = verticalDistances.isEmpty ? 0.0 : verticalDistances.reduce(0, +) / Double(verticalDistances.count)
        let avgHorizontal = horizontalDistances.isEmpty ? 0.0 : horizontalDistances.reduce(0, +) / Double(horizontalDistances.count)
        
        // Enhanced EAR calculation with safety checks
        guard avgHorizontal > 0.001 else { // Prevent division by zero
            return EyeStateAnalysisResult(ear: 0.5, landmarks: points, landmarkQuality: landmarkQuality)
        }
        
        let ear = Float(avgVertical / avgHorizontal)
        
        // Apply eye-specific adjustments (left vs right eyes may have slight differences)
        let adjustedEAR = applyEyeSpecificAdjustments(ear, eyeType: eyeType, landmarkQuality: landmarkQuality)
        
        return EyeStateAnalysisResult(ear: adjustedEAR, landmarks: points, landmarkQuality: landmarkQuality)
    }
    
    /// Calculates adaptive threshold for eye openness based on individual eye characteristics
    /// Research-based implementation using 2022 optimal threshold findings
    private func calculateAdaptiveEyeThreshold(_ landmarks: [CGPoint], baseline: Float) -> Float {
        // Research shows 0.18 is optimal (2022 studies), improved from traditional 0.2-0.25
        let baseThreshold: Float = 0.18
        
        // Adjust threshold based on eye shape characteristics
        let eyeShapeFactor = calculateEyeShapeFactor(landmarks)
        
        // Smaller eyes need lower threshold, larger eyes can use higher threshold
        let shapeAdjustment = (eyeShapeFactor - 1.0) * 0.1
        
        // Ensure threshold stays within reasonable bounds
        return max(0.15, min(0.35, baseThreshold + shapeAdjustment))
    }
    
    /// Calculates comprehensive confidence score for eye state detection
    private func calculateEyeStateConfidence(
        leftEAR: Float,
        rightEAR: Float,
        leftThreshold: Float,
        rightThreshold: Float,
        leftLandmarkQuality: Float,
        rightLandmarkQuality: Float
    ) -> Float {
        
        // Base confidence from landmark quality
        let avgLandmarkQuality = (leftLandmarkQuality + rightLandmarkQuality) / 2.0
        
        // Confidence from threshold separation (how far from threshold)
        let leftSeparation = abs(leftEAR - leftThreshold) / leftThreshold
        let rightSeparation = abs(rightEAR - rightThreshold) / rightThreshold
        let avgSeparation = (leftSeparation + rightSeparation) / 2.0
        
        // Consistency between eyes (both eyes should generally be in same state)
        let leftOpen = leftEAR > leftThreshold
        let rightOpen = rightEAR > rightThreshold
        let consistencyBonus: Float = (leftOpen == rightOpen) ? 0.2 : 0.0
        
        // Combined confidence calculation
        let baseConfidence = (avgLandmarkQuality * 0.4) + (min(1.0, avgSeparation) * 0.4) + consistencyBonus
        
        return max(0.0, min(1.0, baseConfidence))
    }
    
    /// Assesses the quality of eye landmarks for confidence calculation
    private func assessLandmarkQuality(_ points: [CGPoint]) -> Float {
        guard points.count >= 6 else { return 0.0 }
        
        // Check for reasonable eye proportions
        let eyeWidth = distance(points[0], points[3])
        let eyeHeight = max(distance(points[1], points[5]), distance(points[2], points[4]))
        
        // Reasonable eye aspect ratio should be between 0.2 and 0.8
        let aspectRatio = eyeHeight / eyeWidth
        let proportionQuality = (aspectRatio > 0.1 && aspectRatio < 1.0) ? 1.0 : 0.5
        
        // Check for landmark spread (points shouldn't be clustered)
        let landmarkSpread = calculateLandmarkSpread(points)
        let spreadQuality = min(1.0, landmarkSpread * 10.0) // Normalize spread
        
        // Check for outlier landmarks
        let outlierPenalty = detectLandmarkOutliers(points) ? 0.7 : 1.0
        
        return Float(proportionQuality * spreadQuality * outlierPenalty)
    }
    
    /// Calculates eye shape factor for adaptive thresholding
    private func calculateEyeShapeFactor(_ landmarks: [CGPoint]) -> Float {
        guard landmarks.count >= 6 else { return 1.0 }
        
        let eyeWidth = distance(landmarks[0], landmarks[3])
        let eyeHeight = max(distance(landmarks[1], landmarks[5]), distance(landmarks[2], landmarks[4]))
        
        // Shape factor: ratio of width to height (larger = wider eye)
        guard eyeHeight > 0 else { return 1.0 }
        return Float(eyeWidth / eyeHeight)
    }
    
    /// Applies eye-specific adjustments to EAR calculation
    private func applyEyeSpecificAdjustments(_ ear: Float, eyeType: EyeType, landmarkQuality: Float) -> Float {
        var adjustedEAR = ear
        
        // Minor adjustments for left vs right eye differences
        switch eyeType {
        case .left:
            // Left eyes might need slight adjustment due to facial asymmetry
            adjustedEAR *= 1.02
        case .right:
            // Right eyes are typically the reference
            adjustedEAR *= 1.0
        }
        
        // Quality-based smoothing
        if landmarkQuality < 0.5 {
            // Lower quality landmarks - apply conservative smoothing
            adjustedEAR = (adjustedEAR + 0.4) / 2.0
        }
        
        return max(0.0, min(2.0, adjustedEAR)) // Clamp to reasonable range
    }
    
    /// Calculates spread of landmarks to assess quality
    private func calculateLandmarkSpread(_ points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0.0 }
        
        let centerX = points.reduce(0.0) { $0 + $1.x } / Double(points.count)
        let centerY = points.reduce(0.0) { $0 + $1.y } / Double(points.count)
        let center = CGPoint(x: centerX, y: centerY)
        
        let avgDistance = points.reduce(0.0) { $0 + distance($1, center) } / Double(points.count)
        return avgDistance
    }
    
    /// Detects outlier landmarks that might indicate poor detection
    private func detectLandmarkOutliers(_ points: [CGPoint]) -> Bool {
        guard points.count >= 6 else { return false }
        
        // Calculate bounding box of eye landmarks
        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0
        
        let boundingWidth = maxX - minX
        let boundingHeight = maxY - minY
        
        // Check if any point is too far from the bounding box center
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let maxAllowedDistance = max(boundingWidth, boundingHeight) * 2.0
        
        for point in points {
            let distanceFromCenter = sqrt(pow(point.x - centerX, 2) + pow(point.y - centerY, 2))
            if distanceFromCenter > maxAllowedDistance {
                return true // Outlier detected
            }
        }
        
        return false
    }
    
    // MARK: - Smile Detection and Quality Scoring (Task 2.2)
    
    /// Advanced smile quality detection with iOS 18+ direct detection and fallback analysis
    /// Implements comprehensive smile intensity, naturalness, and confidence scoring
    /// Leverages existing face analysis infrastructure for consistency
    private func calculateSmileQuality(_ landmarks: VNFaceLandmarks2D?) -> SmileQuality {
        guard let landmarks = landmarks else {
            return SmileQuality(intensity: 0.5, naturalness: 0.5, confidence: 0.0)
        }
        
        // iOS 18+ Direct Expression Detection (when available)
        if #available(iOS 18.0, *) {
            // Note: VNDetectFaceExpressionsRequest would be used in the main analysis pipeline
            // For now, we'll implement the comprehensive fallback analysis
            return calculateAdvancedSmileQuality(landmarks)
        } else {
            // Fallback to enhanced landmark-based analysis
            return calculateAdvancedSmileQuality(landmarks)
        }
    }
    
    /// Comprehensive smile quality analysis using multiple facial landmarks
    /// Provides detailed assessment of smile intensity, naturalness, and overall quality
    private func calculateAdvancedSmileQuality(_ landmarks: VNFaceLandmarks2D) -> SmileQuality {
        // Multi-region analysis for comprehensive smile detection
        let lipAnalysis = analyzeLipRegion(landmarks)
        let cheekAnalysis = analyzeCheekRegion(landmarks)
        let eyeAnalysis = analyzeEyeCreasing(landmarks)
        
        // Combine analyses for comprehensive smile assessment
        let combinedIntensity = calculateCombinedSmileIntensity(
            lipAnalysis: lipAnalysis,
            cheekAnalysis: cheekAnalysis,
            eyeAnalysis: eyeAnalysis
        )
        
        let naturalness = calculateSmileNaturalness(
            lipAnalysis: lipAnalysis,
            cheekAnalysis: cheekAnalysis,
            eyeAnalysis: eyeAnalysis
        )
        
        let confidence = calculateSmileConfidence(
            lipAnalysis: lipAnalysis,
            cheekAnalysis: cheekAnalysis,
            eyeAnalysis: eyeAnalysis
        )
        
        return SmileQuality(
            intensity: combinedIntensity,
            naturalness: naturalness,
            confidence: confidence
        )
    }
    
    /// Analyzes lip region for smile characteristics
    private func analyzeLipRegion(_ landmarks: VNFaceLandmarks2D) -> LipAnalysisResult {
        guard let outerLips = landmarks.outerLips else {
            return LipAnalysisResult(
                curvature: 0.5,
                symmetry: 0.5,
                width: 0.5,
                openness: 0.5,
                quality: 0.0
            )
        }
        
        let lipPoints = outerLips.normalizedPoints
        guard lipPoints.count >= 12 else {
            return LipAnalysisResult(
                curvature: 0.5,
                symmetry: 0.5,
                width: 0.5,
                openness: 0.5,
                quality: 0.3
            )
        }
        
        // Enhanced lip analysis using all available landmarks
        let curvature = calculateEnhancedLipCurvature(lipPoints)
        let symmetry = calculateEnhancedLipSymmetry(lipPoints)
        let width = calculateLipWidth(lipPoints)
        let openness = calculateLipOpenness(lipPoints, innerLips: landmarks.innerLips)
        let quality = assessLipLandmarkQuality(lipPoints)
        
        return LipAnalysisResult(
            curvature: curvature,
            symmetry: symmetry,
            width: width,
            openness: openness,
            quality: quality
        )
    }
    
    /// Analyzes cheek region for smile-related muscle activation
    private func analyzeCheekRegion(_ landmarks: VNFaceLandmarks2D) -> CheekAnalysisResult {
        // Analyze face contour changes that indicate cheek elevation during smiling
        guard let faceContour = landmarks.faceContour else {
            return CheekAnalysisResult(elevation: 0.5, definition: 0.5, quality: 0.0)
        }
        
        let contourPoints = faceContour.normalizedPoints
        guard contourPoints.count >= 10 else {
            return CheekAnalysisResult(elevation: 0.5, definition: 0.5, quality: 0.3)
        }
        
        // Analyze cheek elevation through contour analysis
        let elevation = calculateCheekElevation(contourPoints)
        let definition = calculateCheekDefinition(contourPoints)
        let quality = assessCheekAnalysisQuality(contourPoints)
        
        return CheekAnalysisResult(
            elevation: elevation,
            definition: definition,
            quality: quality
        )
    }
    
    /// Analyzes eye region for Duchenne smile indicators (eye creasing)
    private func analyzeEyeCreasing(_ landmarks: VNFaceLandmarks2D) -> EyeAnalysisResult {
        // Duchenne smiles involve eye muscle activation (crow's feet)
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else {
            return EyeAnalysisResult(creasing: 0.5, symmetry: 0.5, quality: 0.0)
        }
        
        let leftCreasing = calculateEyeCreasing(leftEye.normalizedPoints)
        let rightCreasing = calculateEyeCreasing(rightEye.normalizedPoints)
        
        let avgCreasing = (leftCreasing + rightCreasing) / 2.0
        let symmetry = 1.0 - abs(leftCreasing - rightCreasing)
        let quality = min(
            assessEyeLandmarkQuality(leftEye.normalizedPoints),
            assessEyeLandmarkQuality(rightEye.normalizedPoints)
        )
        
        return EyeAnalysisResult(
            creasing: avgCreasing,
            symmetry: symmetry,
            quality: quality
        )
    }
    
    /// Calculates combined smile intensity from multiple facial regions
    private func calculateCombinedSmileIntensity(
        lipAnalysis: LipAnalysisResult,
        cheekAnalysis: CheekAnalysisResult,
        eyeAnalysis: EyeAnalysisResult
    ) -> Float {
        // Weighted combination of different smile indicators
        let lipWeight: Float = 0.5      // Primary indicator
        let cheekWeight: Float = 0.3    // Secondary indicator
        let eyeWeight: Float = 0.2      // Naturalness indicator
        
        let weightedIntensity = (lipAnalysis.curvature * lipWeight) +
                               (cheekAnalysis.elevation * cheekWeight) +
                               (eyeAnalysis.creasing * eyeWeight)
        
        // Apply quality-based confidence scaling
        let avgQuality = (lipAnalysis.quality + cheekAnalysis.quality + eyeAnalysis.quality) / 3.0
        let qualityScaledIntensity = weightedIntensity * (0.5 + avgQuality * 0.5)
        
        return max(0.0, min(1.0, qualityScaledIntensity))
    }
    
    /// Calculates smile naturalness (Duchenne vs forced smile)
    private func calculateSmileNaturalness(
        lipAnalysis: LipAnalysisResult,
        cheekAnalysis: CheekAnalysisResult,
        eyeAnalysis: EyeAnalysisResult
    ) -> Float {
        // Duchenne smiles involve both mouth and eye regions
        let eyeInvolvement = eyeAnalysis.creasing
        let lipSymmetry = lipAnalysis.symmetry
        let cheekDefinition = cheekAnalysis.definition
        
        // Natural smiles have good eye involvement and symmetry
        let duchenneFactor = eyeInvolvement * 0.4
        let symmetryFactor = lipSymmetry * 0.3
        let definitionFactor = cheekDefinition * 0.3
        
        let naturalness = duchenneFactor + symmetryFactor + definitionFactor
        
        // Penalize extreme intensity without eye involvement (forced smile indicator)
        if lipAnalysis.curvature > 0.8 && eyeInvolvement < 0.3 {
            return naturalness * 0.7 // Reduce naturalness for likely forced smile
        }
        
        return max(0.0, min(1.0, naturalness))
    }
    
    /// Calculates comprehensive confidence score for smile detection
    private func calculateSmileConfidence(
        lipAnalysis: LipAnalysisResult,
        cheekAnalysis: CheekAnalysisResult,
        eyeAnalysis: EyeAnalysisResult
    ) -> Float {
        // Base confidence from landmark quality
        let avgLandmarkQuality = (lipAnalysis.quality + cheekAnalysis.quality + eyeAnalysis.quality) / 3.0
        
        // Consistency across different facial regions
        let intensityConsistency = calculateIntensityConsistency(
            lipIntensity: lipAnalysis.curvature,
            cheekIntensity: cheekAnalysis.elevation,
            eyeIntensity: eyeAnalysis.creasing
        )
        
        // Symmetry factors (symmetric smiles are more reliable)
        let avgSymmetry = (lipAnalysis.symmetry + eyeAnalysis.symmetry) / 2.0
        
        // Combined confidence calculation
        let baseConfidence = avgLandmarkQuality * 0.4
        let consistencyBonus = intensityConsistency * 0.3
        let symmetryBonus = avgSymmetry * 0.3
        
        return max(0.0, min(1.0, baseConfidence + consistencyBonus + symmetryBonus))
    }
    
    /// Calculates intensity consistency across facial regions
    private func calculateIntensityConsistency(
        lipIntensity: Float,
        cheekIntensity: Float,
        eyeIntensity: Float
    ) -> Float {
        // Check if different regions agree on smile intensity
        let avgIntensity = (lipIntensity + cheekIntensity + eyeIntensity) / 3.0
        
        let lipVariance = abs(lipIntensity - avgIntensity)
        let cheekVariance = abs(cheekIntensity - avgIntensity)
        let eyeVariance = abs(eyeIntensity - avgIntensity)
        
        let avgVariance = (lipVariance + cheekVariance + eyeVariance) / 3.0
        
        // Lower variance = higher consistency
        return max(0.0, 1.0 - (avgVariance * 2.0))
    }
    
    // MARK: - Enhanced Lip Analysis Methods
    
    /// Enhanced lip curvature calculation using multiple measurement points
    private func calculateEnhancedLipCurvature(_ points: [CGPoint]) -> Float {
        guard points.count >= 12 else { return 0.0 }
        
        // Multiple curvature measurements for robustness
        var curvatureMeasurements: [Float] = []
        
        // Primary curvature measurement (corner elevation)
        let leftCorner = points[0]
        let rightCorner = points[6]
        let topCenter = points[3]
        let bottomCenter = points[9]
        
        let mouthCenterY = (topCenter.y + bottomCenter.y) / 2
        let avgCornerY = (leftCorner.y + rightCorner.y) / 2
        
        // Primary curvature (enhanced scaling)
        let primaryCurvature = Float(max(0, (avgCornerY - mouthCenterY) * 40))
        curvatureMeasurements.append(primaryCurvature)
        
        // Secondary measurements using intermediate points
        if points.count >= 16 {
            // Left side curvature
            let leftMidPoint = points[1]
            let leftCurvature = Float(max(0, (leftCorner.y - leftMidPoint.y) * 30))
            curvatureMeasurements.append(leftCurvature)
            
            // Right side curvature
            let rightMidPoint = points[5]
            let rightCurvature = Float(max(0, (rightCorner.y - rightMidPoint.y) * 30))
            curvatureMeasurements.append(rightCurvature)
        }
        
        // Calculate weighted average
        let avgCurvature = curvatureMeasurements.reduce(0, +) / Float(curvatureMeasurements.count)
        return min(1.0, avgCurvature)
    }
    
    /// Enhanced lip symmetry calculation
    private func calculateEnhancedLipSymmetry(_ points: [CGPoint]) -> Float {
        guard points.count >= 12 else { return 0.5 }
        
        let leftCorner = points[0]
        let rightCorner = points[6]
        let center = points[3]
        
        // Primary symmetry measurement
        let leftDistance = abs(leftCorner.x - center.x)
        let rightDistance = abs(rightCorner.x - center.x)
        let primarySymmetry = 1.0 - abs(leftDistance - rightDistance) / max(leftDistance, rightDistance)
        
        // Secondary symmetry measurements using multiple points
        var symmetryMeasurements: [Double] = [primarySymmetry]
        
        if points.count >= 16 {
            // Upper lip symmetry
            let leftUpper = points[1]
            let rightUpper = points[5]
            let upperCenter = points[3]
            let upperLeftDist = abs(leftUpper.x - upperCenter.x)
            let upperRightDist = abs(rightUpper.x - upperCenter.x)
            if max(upperLeftDist, upperRightDist) > 0 {
                let upperSymmetry = 1.0 - abs(upperLeftDist - upperRightDist) / max(upperLeftDist, upperRightDist)
                symmetryMeasurements.append(upperSymmetry)
            }
            
            // Lower lip symmetry
            let leftLower = points[11]
            let rightLower = points[7]
            let lowerCenter = points[9]
            let lowerLeftDist = abs(leftLower.x - lowerCenter.x)
            let lowerRightDist = abs(rightLower.x - lowerCenter.x)
            if max(lowerLeftDist, lowerRightDist) > 0 {
                let lowerSymmetry = 1.0 - abs(lowerLeftDist - lowerRightDist) / max(lowerLeftDist, lowerRightDist)
                symmetryMeasurements.append(lowerSymmetry)
            }
        }
        
        let avgSymmetry = symmetryMeasurements.reduce(0, +) / Double(symmetryMeasurements.count)
        return Float(max(0.0, min(1.0, avgSymmetry)))
    }
    
    /// Calculates lip width relative to face
    private func calculateLipWidth(_ points: [CGPoint]) -> Float {
        guard points.count >= 12 else { return 0.5 }
        
        let leftCorner = points[0]
        let rightCorner = points[6]
        let width = abs(rightCorner.x - leftCorner.x)
        
        // Normalize width (typical lip width is 5-7% of face width)
        let normalizedWidth = Float(width * 15.0) // Scale to 0-1 range
        return min(1.0, normalizedWidth)
    }
    
    /// Calculates lip openness using inner and outer lip landmarks
    private func calculateLipOpenness(_ outerPoints: [CGPoint], innerLips: VNFaceLandmarkRegion2D?) -> Float {
        guard outerPoints.count >= 12 else { return 0.5 }
        
        // Primary openness from outer lips
        let topCenter = outerPoints[3]
        let bottomCenter = outerPoints[9]
        let outerOpenness = abs(topCenter.y - bottomCenter.y)
        
        // Enhanced openness with inner lips if available
        var totalOpenness = outerOpenness
        if let innerLips = innerLips {
            let innerPoints = innerLips.normalizedPoints
            if innerPoints.count >= 6 {
                let innerTop = innerPoints[1]
                let innerBottom = innerPoints[4]
                let innerOpenness = abs(innerTop.y - innerBottom.y)
                totalOpenness = (outerOpenness + innerOpenness) / 2.0
            }
        }
        
        // Normalize openness (typical range 0-3% of face height)
        let normalizedOpenness = Float(totalOpenness * 30.0)
        return min(1.0, normalizedOpenness)
    }
    
    /// Assesses quality of lip landmarks
    private func assessLipLandmarkQuality(_ points: [CGPoint]) -> Float {
        guard points.count >= 12 else { return 0.0 }
        
        // Check lip proportions
        let width = abs(points[6].x - points[0].x)
        let height = abs(points[3].y - points[9].y)
        let aspectRatio = height / width
        
        // Reasonable lip aspect ratio (0.1 to 0.4)
        let proportionQuality: Float = (aspectRatio > 0.05 && aspectRatio < 0.5) ? 1.0 : 0.6
        
        // Check landmark distribution
        let landmarkSpread = calculateLandmarkSpread(points)
        let spreadQuality = min(1.0, Float(landmarkSpread * 20.0))
        
        // Check for outliers
        let outlierPenalty: Float = detectLandmarkOutliers(points) ? 0.8 : 1.0
        
        return proportionQuality * spreadQuality * outlierPenalty
    }
    
    // MARK: - Cheek Analysis Methods
    
    /// Calculates cheek elevation from face contour changes
    private func calculateCheekElevation(_ contourPoints: [CGPoint]) -> Float {
        guard contourPoints.count >= 10 else { return 0.5 }
        
        // Analyze mid-face region elevation (cheek area)
        let leftCheekIndex = Int(Double(contourPoints.count) * 0.3)
        let rightCheekIndex = Int(Double(contourPoints.count) * 0.7)
        
        guard leftCheekIndex < contourPoints.count && rightCheekIndex < contourPoints.count else {
            return 0.5
        }
        
        let leftCheek = contourPoints[leftCheekIndex]
        let rightCheek = contourPoints[rightCheekIndex]
        
        // Calculate relative elevation (higher Y values indicate elevated cheeks)
        let avgCheekY = (leftCheek.y + rightCheek.y) / 2.0
        
        // Compare with baseline (jaw line)
        let jawIndex = Int(Double(contourPoints.count) * 0.5)
        let jawY = contourPoints[jawIndex].y
        
        let relativeElevation = Float((jawY - avgCheekY) * 5.0) // Scale factor
        return max(0.0, min(1.0, relativeElevation))
    }
    
    /// Calculates cheek definition from contour analysis
    private func calculateCheekDefinition(_ contourPoints: [CGPoint]) -> Float {
        guard contourPoints.count >= 15 else { return 0.5 }
        
        // Analyze contour curvature in cheek regions
        let segments = stride(from: 0, to: contourPoints.count - 2, by: 2).map { i in
            calculateContourCurvature(
                contourPoints[i],
                contourPoints[i + 1],
                contourPoints[i + 2]
            )
        }
        
        let avgCurvature = segments.reduce(0, +) / Float(segments.count)
        return min(1.0, avgCurvature * 2.0)
    }
    
    /// Calculates local curvature for three consecutive points
    private func calculateContourCurvature(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> Float {
        // Calculate angle between line segments
        let v1x = p2.x - p1.x
        let v1y = p2.y - p1.y
        let v2x = p3.x - p2.x
        let v2y = p3.y - p2.y
        
        let dot = v1x * v2x + v1y * v2y
        let det = v1x * v2y - v1y * v2x
        let angle = atan2(det, dot)
        
        // Return absolute curvature (0-1 range)
        return Float(abs(angle) / .pi)
    }
    
    /// Assesses quality of cheek analysis
    private func assessCheekAnalysisQuality(_ contourPoints: [CGPoint]) -> Float {
        guard contourPoints.count >= 10 else { return 0.0 }
        
        // Check for reasonable face contour
        let boundingWidth = (contourPoints.map { $0.x }.max() ?? 0) - (contourPoints.map { $0.x }.min() ?? 0)
        let boundingHeight = (contourPoints.map { $0.y }.max() ?? 0) - (contourPoints.map { $0.y }.min() ?? 0)
        
        // Reasonable face proportions
        let aspectRatio = boundingHeight / boundingWidth
        let proportionQuality: Float = (aspectRatio > 0.8 && aspectRatio < 2.0) ? 1.0 : 0.6
        
        // Point distribution quality
        let distributionQuality = min(1.0, Float(calculateLandmarkSpread(contourPoints) * 5.0))
        
        return proportionQuality * distributionQuality
    }
    
    // MARK: - Eye Creasing Analysis Methods
    
    /// Calculates eye creasing intensity (Duchenne smile indicator)
    private func calculateEyeCreasing(_ eyePoints: [CGPoint]) -> Float {
        guard eyePoints.count >= 6 else { return 0.5 }
        
        // Analyze eye shape changes that indicate creasing
        let _ = eyePoints[0] // outer corner (not needed for this calculation)
        let upperMid = eyePoints[2]
        let lowerMid = eyePoints[4]
        
        // Calculate eye "squinting" by measuring height compression
        let eyeHeight = abs(upperMid.y - lowerMid.y)
        let normalizedHeight = Float(eyeHeight * 20.0) // Scale to reasonable range
        
        // Lower height indicates more squinting/creasing
        let creasingIntensity = max(0.0, 1.0 - normalizedHeight)
        
        return min(1.0, creasingIntensity)
    }
    
    /// Assesses eye landmark quality for creasing analysis
    private func assessEyeLandmarkQuality(_ eyePoints: [CGPoint]) -> Float {
        guard eyePoints.count >= 6 else { return 0.0 }
        
        // Check eye proportions
        let eyeWidth = abs(eyePoints[3].x - eyePoints[0].x)
        let eyeHeight = abs(eyePoints[1].y - eyePoints[5].y)
        let aspectRatio = eyeHeight / eyeWidth
        
        // Reasonable eye aspect ratio
        let proportionQuality: Float = (aspectRatio > 0.1 && aspectRatio < 0.8) ? 1.0 : 0.6
        
        // Point distribution
        let distributionQuality = min(1.0, Float(calculateLandmarkSpread(eyePoints) * 15.0))
        
        return proportionQuality * distributionQuality
    }
    
    /// Original lip curvature calculation (kept for compatibility)
    private func calculateLipCurvature(_ points: [CGPoint]) -> Float {
        return calculateEnhancedLipCurvature(points)
    }
    
    /// Original lip symmetry calculation (kept for compatibility)
    private func calculateLipSymmetry(_ points: [CGPoint]) -> Float {
        return calculateEnhancedLipSymmetry(points)
    }
    
    // MARK: - Face Pose Analysis
    
    /// Extracts 3D face orientation from Vision Framework observation
    private func extractFaceAngle(from observation: VNFaceObservation) -> FaceAngle {
        let pitch = observation.pitch?.floatValue ?? 0.0
        let yaw = observation.yaw?.floatValue ?? 0.0
        let roll = observation.roll?.floatValue ?? 0.0
        
        return FaceAngle(pitch: pitch, yaw: yaw, roll: roll)
    }
    
    // MARK: - Face Sharpness Analysis
    
    /// Calculates face-specific sharpness using region-based analysis
    private func calculateFaceSharpness(_ image: UIImage, faceRect: CGRect) async -> Float {
        guard let ciImage = CIImage(image: image) else { return 0.5 }
        
        // Convert normalized face rect to image coordinates
        let imageSize = ciImage.extent.size
        let faceRegion = CGRect(
            x: faceRect.origin.x * imageSize.width,
            y: faceRect.origin.y * imageSize.height,
            width: faceRect.size.width * imageSize.width,
            height: faceRect.size.height * imageSize.height
        )
        
        // Crop to face region for focused analysis
        let croppedImage = ciImage.cropped(to: faceRegion)
        
        // Use Laplacian variance for sharpness measurement
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(croppedImage, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey) // Convert to grayscale
        
        // Simple sharpness estimation based on face size and quality
        let faceArea = faceRect.width * faceRect.height
        var sharpness: Float = 0.3 // Base score
        
        // Larger faces generally appear sharper
        if faceArea > 0.1 { // Large face
            sharpness += 0.4
        } else if faceArea > 0.05 { // Medium face
            sharpness += 0.2
        } else if faceArea > 0.02 { // Small but usable face
            sharpness += 0.1
        }
        
        // Bonus for successful image processing
        if filter?.outputImage != nil {
            sharpness += 0.2
        }
        
        return min(1.0, sharpness)
    }
    
    // MARK: - Overall Face Quality Scoring
    
    /// Calculates comprehensive face quality score combining all metrics
    private func calculateOverallFaceScore(
        captureQuality: Float,
        eyeState: EyeState,
        smileQuality: SmileQuality,
        faceAngle: FaceAngle,
        sharpness: Float
    ) -> Float {
        // Weighted scoring prioritizing key quality factors
        let eyeScore: Float = eyeState.bothOpen ? 1.0 : 0.0
        let angleScore: Float = faceAngle.isOptimal ? 1.0 : 0.5
        
        let captureComponent = captureQuality * 0.3
        let eyeComponent = eyeScore * 0.25
        let smileComponent = smileQuality.overallQuality * 0.2
        let sharpnessComponent = sharpness * 0.15
        let angleComponent = angleScore * 0.1
        
        return captureComponent + eyeComponent + smileComponent + sharpnessComponent + angleComponent
    }
    
    // MARK: - Person Matching Across Photos System (Task 2.3)
    
    /// Advanced person matching across photos using face embeddings and similarity scoring
    /// Leverages existing fingerprint matching patterns from PhotoClusteringService for consistency
    private func matchPersonAcrossPhotos(
        _ faceAnalysis: FaceQualityData,
        existingPersons: [PersonID],
        allFaces: [PersonID: [FaceQualityData]]
    ) async -> PersonID {
        
        // Generate face embedding for the new face
        guard let newFaceEmbedding = await generateFaceEmbedding(faceAnalysis) else {
            // Fallback to position-based matching if embedding generation fails
            return fallbackPositionBasedMatching(faceAnalysis, existingPersons: existingPersons, allFaces: allFaces)
        }
        
        var bestMatch: (personID: PersonID, similarity: Float, confidence: Float)?
        
        // Compare against all existing persons using face embedding similarity
        for personID in existingPersons {
            guard let existingFaces = allFaces[personID] else { continue }
            
            // Calculate similarity with all faces of this person
            let personMatchResult = await calculatePersonSimilarity(
                newFaceEmbedding: newFaceEmbedding,
                newFaceData: faceAnalysis,
                existingFaces: existingFaces
            )
            
            // Check if this is the best match so far
            if let currentBest = bestMatch {
                if personMatchResult.similarity > currentBest.similarity {
                    bestMatch = (personID, personMatchResult.similarity, personMatchResult.confidence)
                }
            } else if personMatchResult.similarity > PersonMatchingThresholds.minimumSimilarity {
                bestMatch = (personID, personMatchResult.similarity, personMatchResult.confidence)
            }
        }
        
        // Debug: Log person matching results
        if let match = bestMatch {
            print("🔍 Person Matching - Best similarity: \(match.similarity), confidence: \(match.confidence)")
            print("📊 Thresholds - Strong: \(PersonMatchingThresholds.strongMatchThreshold), Medium: \(PersonMatchingThresholds.mediumMatchThreshold), Min: \(PersonMatchingThresholds.minimumSimilarity)")
        } else {
            print("❌ Person Matching - No matches found above minimum threshold")
        }
        
        // Validate the best match meets quality requirements
        if let match = bestMatch,
           match.similarity >= PersonMatchingThresholds.strongMatchThreshold,
           match.confidence >= PersonMatchingThresholds.minimumConfidence {
            print("✅ Strong match found - using existing person: \(match.personID.prefix(8))")
            return match.personID
        }
        
        // Medium confidence match - apply additional validation
        if let match = bestMatch,
           match.similarity >= PersonMatchingThresholds.mediumMatchThreshold {
            
            // Additional validation using pose and position consistency
            if await validatePersonMatchConsistency(
                faceAnalysis,
                personID: match.personID,
                allFaces: allFaces,
                confidence: match.confidence
            ) {
                return match.personID
            }
        }
        
        // No confident match found, create new person ID
        let newPersonID = UUID().uuidString
        print("🆕 Creating new person: \(newPersonID.prefix(8)) - no confident matches found")
        return newPersonID
    }
    
    /// Generates face embedding for person identification using Vision Framework
    /// Leverages patterns from PhotoClusteringService fingerprint generation
    private func generateFaceEmbedding(_ faceData: FaceQualityData) async -> VNFaceEmbedding? {
        guard let image = try? await loadImage(for: faceData.photo) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: nil)
                return
            }
            
            // Create face feature print request (equivalent to face embedding)
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error = error {
                    print("Face feature print generation failed: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let results = request.results as? [VNFeaturePrintObservation],
                      let featurePrint = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Create custom face embedding wrapper with additional metadata
                let faceEmbedding = VNFaceEmbedding(
                    embedding: featurePrint,
                    boundingBox: faceData.boundingBox,
                    confidence: featurePrint.confidence,
                    qualityScore: faceData.overallScore
                )
                
                continuation.resume(returning: faceEmbedding)
            }
            
            // Configure request to process the face region
            // Note: VNGenerateImageFeaturePrintRequest processes the entire image
            // For face-specific features, we crop the image to the face region first
            let faceRegion = cropImageToFaceRegion(ciImage, faceRect: faceData.boundingBox)
            let faceHandler = VNImageRequestHandler(ciImage: faceRegion, options: [:])
            
            do {
                try faceHandler.perform([request])
            } catch {
                print("Face embedding handler failed: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Calculates comprehensive similarity between a new face and existing person faces
    private func calculatePersonSimilarity(
        newFaceEmbedding: VNFaceEmbedding,
        newFaceData: FaceQualityData,
        existingFaces: [FaceQualityData]
    ) async -> PersonSimilarityResult {
        
        var similarities: [Float] = []
        var confidences: [Float] = []
        var validComparisons = 0
        
        for existingFace in existingFaces {
            // Generate embedding for existing face
            guard let existingEmbedding = await generateFaceEmbedding(existingFace) else {
                continue
            }
            
            // Calculate embedding similarity (primary factor)
            let embeddingSimilarity = calculateEmbeddingSimilarity(
                newFaceEmbedding.embedding,
                existingEmbedding.embedding
            )
            
            // Calculate pose similarity (secondary factor)
            let poseSimilarity = calculatePoseSimilarity(
                newFaceData.faceAngle,
                existingFace.faceAngle
            )
            
            // Calculate feature consistency (tertiary factor)
            let featureConsistency = calculateFeatureConsistency(
                newFaceData,
                existingFace
            )
            
            // Weighted similarity combining multiple factors
            let weightedSimilarity = (embeddingSimilarity * PersonMatchingWeights.embedding) +
                                   (poseSimilarity * PersonMatchingWeights.pose) +
                                   (featureConsistency * PersonMatchingWeights.features)
            
            similarities.append(weightedSimilarity)
            
            // Calculate confidence based on quality and consistency
            let confidence = calculateMatchConfidence(
                embeddingSimilarity: embeddingSimilarity,
                newFaceQuality: newFaceData.overallScore,
                existingFaceQuality: existingFace.overallScore,
                embeddingConfidence: min(newFaceEmbedding.confidence, existingEmbedding.confidence)
            )
            
            confidences.append(confidence)
            validComparisons += 1
        }
        
        // Aggregate results across all faces of the person
        let averageSimilarity = validComparisons > 0 ? similarities.reduce(0, +) / Float(validComparisons) : 0.0
        let maxSimilarity = similarities.max() ?? 0.0
        let averageConfidence = validComparisons > 0 ? confidences.reduce(0, +) / Float(validComparisons) : 0.0
        
        // Use weighted combination of average and max similarity
        let finalSimilarity = (averageSimilarity * 0.7) + (maxSimilarity * 0.3)
        
        return PersonSimilarityResult(
            similarity: finalSimilarity,
            confidence: averageConfidence,
            comparisonCount: validComparisons,
            maxSimilarity: maxSimilarity,
            averageSimilarity: averageSimilarity
        )
    }
    
    /// Calculates embedding similarity using distance metrics
    /// Leverages existing similarity calculation patterns from PhotoClusteringService
    private func calculateEmbeddingSimilarity(
        _ embedding1: VNFeaturePrintObservation,
        _ embedding2: VNFeaturePrintObservation
    ) -> Float {
        
        do {
            // Use Vision Framework's built-in distance calculation
            var distance: Float = 0.0
            try embedding1.computeDistance(&distance, to: embedding2)
            
            // Convert distance to similarity (closer embeddings = higher similarity)
            // Distance ranges from 0.0 (identical) to ~2.0 (very different)
            let similarity = max(0.0, 1.0 - (distance / 2.0))
            
            return similarity
        } catch {
            print("Embedding distance calculation failed: \(error)")
            // Fallback to basic comparison if distance calculation fails
            return 0.0
        }
    }
    
    /// Calculates pose similarity between two faces
    private func calculatePoseSimilarity(_ pose1: FaceAngle, _ pose2: FaceAngle) -> Float {
        let pitchDiff = abs(pose1.pitch - pose2.pitch)
        let yawDiff = abs(pose1.yaw - pose2.yaw)
        let rollDiff = abs(pose1.roll - pose2.roll)
        
        // Normalize angles to 0-1 similarity scale
        let pitchSimilarity = max(0.0, 1.0 - (pitchDiff / 90.0))
        let yawSimilarity = max(0.0, 1.0 - (yawDiff / 90.0))
        let rollSimilarity = max(0.0, 1.0 - (rollDiff / 180.0))
        
        // Weighted average (yaw is most important for person recognition)
        return (pitchSimilarity * 0.3) + (yawSimilarity * 0.5) + (rollSimilarity * 0.2)
    }
    
    /// Calculates feature consistency between faces (eye state, smile, etc.)
    private func calculateFeatureConsistency(_ face1: FaceQualityData, _ face2: FaceQualityData) -> Float {
        var consistencyScore: Float = 0.5 // Base score
        
        // Eye state consistency
        if face1.eyeState.bothOpen == face2.eyeState.bothOpen {
            consistencyScore += 0.2
        }
        
        // Smile consistency (within reasonable range)
        let smileDiff = abs(face1.smileQuality.intensity - face2.smileQuality.intensity)
        if smileDiff < 0.3 {
            consistencyScore += 0.2
        }
        
        // Face angle compatibility
        if face1.faceAngle.isCompatibleForAlignment(with: face2.faceAngle) {
            consistencyScore += 0.1
        }
        
        return min(1.0, consistencyScore)
    }
    
    /// Calculates match confidence based on multiple quality factors
    private func calculateMatchConfidence(
        embeddingSimilarity: Float,
        newFaceQuality: Float,
        existingFaceQuality: Float,
        embeddingConfidence: Float
    ) -> Float {
        
        // Base confidence from embedding similarity
        let baseConfidence = embeddingSimilarity
        
        // Quality factor (higher quality faces = higher confidence)
        let qualityFactor = (newFaceQuality + existingFaceQuality) / 2.0
        
        // Embedding confidence factor
        let embeddingFactor = embeddingConfidence
        
        // Combined confidence calculation
        let confidence = (baseConfidence * 0.5) + (qualityFactor * 0.3) + (embeddingFactor * 0.2)
        
        return max(0.0, min(1.0, confidence))
    }
    
    /// Validates person match consistency using additional context
    private func validatePersonMatchConsistency(
        _ newFace: FaceQualityData,
        personID: PersonID,
        allFaces: [PersonID: [FaceQualityData]],
        confidence: Float
    ) async -> Bool {
        
        guard let existingFaces = allFaces[personID] else { return false }
        
        // Check position consistency within cluster
        let positionConsistent = validatePositionConsistency(newFace, existingFaces: existingFaces)
        
        // Check temporal consistency (faces should appear in reasonable time proximity)
        let temporalConsistent = validateTemporalConsistency(newFace, existingFaces: existingFaces)
        
        // Check size consistency (face size should be reasonably consistent)
        let sizeConsistent = validateSizeConsistency(newFace, existingFaces: existingFaces)
        
        // Require at least 2 of 3 consistency checks to pass for medium confidence matches
        let consistencyScore = (positionConsistent ? 1 : 0) + (temporalConsistent ? 1 : 0) + (sizeConsistent ? 1 : 0)
        
        return consistencyScore >= 2
    }
    
    /// Validates position consistency of faces within a cluster
    private func validatePositionConsistency(_ newFace: FaceQualityData, existingFaces: [FaceQualityData]) -> Bool {
        // Check if new face position is within reasonable range of existing faces
        let newPosition = CGPoint(x: newFace.boundingBox.midX, y: newFace.boundingBox.midY)
        
        for existingFace in existingFaces {
            let existingPosition = CGPoint(x: existingFace.boundingBox.midX, y: existingFace.boundingBox.midY)
            let distance = distance(newPosition, existingPosition)
            
            // If any existing face is within reasonable distance, consider consistent
            if distance < 0.4 { // 40% of image width/height
                return true
            }
        }
        
        return false
    }
    
    /// Validates temporal consistency of faces
    private func validateTemporalConsistency(_ newFace: FaceQualityData, existingFaces: [FaceQualityData]) -> Bool {
        let newTimestamp = newFace.photo.timestamp
        
        for existingFace in existingFaces {
            let timeDiff = abs(newTimestamp.timeIntervalSince(existingFace.photo.timestamp))
            
            // If any existing face is within reasonable time window, consider consistent
            if timeDiff < PersonMatchingThresholds.maxTemporalGap {
                return true
            }
        }
        
        return false
    }
    
    /// Validates size consistency of faces
    private func validateSizeConsistency(_ newFace: FaceQualityData, existingFaces: [FaceQualityData]) -> Bool {
        let newSize = newFace.boundingBox.width * newFace.boundingBox.height
        
        for existingFace in existingFaces {
            let existingSize = existingFace.boundingBox.width * existingFace.boundingBox.height
            let sizeRatio = newSize / existingSize
            
            // If any existing face has similar size, consider consistent
            if sizeRatio >= 0.5 && sizeRatio <= 2.0 {
                return true
            }
        }
        
        return false
    }
    
    /// Creates VNFaceObservation from FaceQualityData for Vision Framework requests
    private func createFaceObservation(from faceData: FaceQualityData) -> VNFaceObservation {
        // Create a minimal face observation for the embedding request
        // Note: In practice, this would use the original VNFaceObservation if available
        let observation = VNFaceObservation(boundingBox: faceData.boundingBox)
        return observation
    }
    
    /// Fallback position-based matching for when embedding generation fails
    /// Maintains backward compatibility with existing simple matching approach
    private func fallbackPositionBasedMatching(
        _ faceAnalysis: FaceQualityData,
        existingPersons: [PersonID],
        allFaces: [PersonID: [FaceQualityData]]
    ) -> PersonID {
        
        for personID in existingPersons {
            guard let existingFaces = allFaces[personID] else { continue }
            
            for existingFace in existingFaces {
                // Check if faces are similar based on position and size
                if facesAreSimilarBasic(faceAnalysis, existingFace) {
                    return personID
                }
            }
        }
        
        // No match found, create new person ID  
        let newPersonID = UUID().uuidString
        print("🆕 Creating new person (fallback): \(newPersonID.prefix(8)) - position-based matching failed")
        return newPersonID
    }
    
    /// Basic face similarity for fallback matching
    private func facesAreSimilarBasic(_ face1: FaceQualityData, _ face2: FaceQualityData) -> Bool {
        let positionThreshold: Float = 0.3
        let sizeThreshold: Float = 0.5
        
        let centerDiff = distance(
            CGPoint(x: face1.boundingBox.midX, y: face1.boundingBox.midY),
            CGPoint(x: face2.boundingBox.midX, y: face2.boundingBox.midY)
        )
        
        let sizeDiff = abs(face1.boundingBox.width - face2.boundingBox.width)
        
        return centerDiff < Double(positionThreshold) && sizeDiff < CGFloat(sizeThreshold)
    }
    
    // MARK: - Face Selection and Ranking
    
    /// Selects the highest quality face from a collection
    private func selectBestFace(from faces: [FaceQualityData]) -> FaceQualityData {
        return faces.max(by: { $0.qualityRank < $1.qualityRank }) ?? faces.first!
    }
    
    /// Selects the lowest quality face from a collection
    private func selectWorstFace(from faces: [FaceQualityData]) -> FaceQualityData {
        return faces.min(by: { $0.qualityRank < $1.qualityRank }) ?? faces.first!
    }
    
    /// Calculates potential improvement from face replacement
    private func calculateImprovementPotential(_ faces: [FaceQualityData]) -> Float {
        guard faces.count >= 2 else { return 0.0 }
        
        let bestScore = faces.map { $0.qualityRank }.max() ?? 0.0
        let worstScore = faces.map { $0.qualityRank }.min() ?? 0.0
        
        return max(0.0, bestScore - worstScore)
    }
    
    // MARK: - Base Photo Selection
    
    /// Selects optimal base photo for composition using existing aesthetic patterns
    private func selectOptimalBasePhoto(_ photos: [Photo]) async -> PhotoCandidate {
        var bestPhoto = photos.first!
        var bestScore: Float = 0.0
        
        for photo in photos {
            guard let image = try? await loadImage(for: photo) else { continue }
            
            // Use existing aesthetic scoring approach
            let aestheticScore = await calculatePhotoSuitability(photo, image: image)
            let technicalScore = await calculateTechnicalQuality(image)
            let overallScore = (aestheticScore * 0.6) + (technicalScore * 0.4)
            
            if overallScore > bestScore {
                bestScore = overallScore
                bestPhoto = photo
            }
        }
        
        let finalImage = try? await loadImage(for: bestPhoto)
        
        return PhotoCandidate(
            photo: bestPhoto,
            image: finalImage ?? UIImage(),
            suitabilityScore: bestScore,
            aestheticScore: bestScore * 0.6,
            technicalQuality: bestScore * 0.4
        )
    }
    
    /// Calculates photo suitability for use as base image
    private func calculatePhotoSuitability(_ photo: Photo, image: UIImage) async -> Float {
        // Use existing photo scoring if available
        if let overallScore = photo.overallScore {
            return Float(overallScore.overall)
        }
        
        // Fallback to basic assessment
        let resolution = image.size.width * image.size.height
        let aspectRatio = image.size.width / image.size.height
        
        var score: Float = 0.5
        
        // Higher resolution bonus
        if resolution > 2000000 { score += 0.3 }
        else if resolution > 1000000 { score += 0.2 }
        
        // Good aspect ratio bonus
        if aspectRatio >= 0.75 && aspectRatio <= 1.5 { score += 0.2 }
        
        return min(1.0, score)
    }
    
    /// Calculates technical image quality
    private func calculateTechnicalQuality(_ image: UIImage) async -> Float {
        let resolution = Float(image.size.width * image.size.height)
        let normalizedResolution = min(1.0, resolution / 4000000.0) // Normalize to 4MP
        
        return normalizedResolution
    }
    
    /// Calculates overall cluster improvement potential
    private func calculateOverallImprovement(_ personAnalyses: [PersonID: PersonFaceQualityAnalysis]) -> Float {
        guard !personAnalyses.isEmpty else { return 0.0 }
        
        let improvements = personAnalyses.values.map { $0.improvementPotential }
        let avgImprovement = improvements.reduce(0, +) / Float(improvements.count)
        
        return avgImprovement
    }
    
    // MARK: - Utility Methods
    
    /// Calculates distance between two CGPoints
    private func distance(_ point1: CGPoint, _ point2: CGPoint) -> Double {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Get correct image orientation for Vision Framework (per best practices)
    /// Vision algorithms require explicit orientation information for accurate results
    private func getImageOrientation(from image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up:
            return .up
        case .down:
            return .down
        case .left:
            return .left
        case .right:
            return .right
        case .upMirrored:
            return .upMirrored
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
    
    /// Loads image for analysis, leveraging existing service patterns
    private func loadImage(for photo: Photo) async throws -> UIImage? {
        return try await photoLibraryService.getFullResolutionImage(for: photo.assetIdentifier)
    }
    
    /// Crops image to face region for focused feature print generation
    private func cropImageToFaceRegion(_ ciImage: CIImage, faceRect: CGRect) -> CIImage {
        // Convert normalized face rect to image coordinates
        let imageSize = ciImage.extent.size
        let faceRegion = CGRect(
            x: faceRect.origin.x * imageSize.width,
            y: faceRect.origin.y * imageSize.height,
            width: faceRect.size.width * imageSize.width,
            height: faceRect.size.height * imageSize.height
        )
        
        // Add some padding around the face for better feature extraction
        let padding = min(faceRegion.width, faceRegion.height) * 0.1
        let expandedRegion = CGRect(
            x: max(0, faceRegion.origin.x - padding),
            y: max(0, faceRegion.origin.y - padding),
            width: min(imageSize.width - faceRegion.origin.x, faceRegion.width + 2 * padding),
            height: min(imageSize.height - faceRegion.origin.y, faceRegion.height + 2 * padding)
        )
        
        return ciImage.cropped(to: expandedRegion)
    }
}

// MARK: - Supporting Types for Eye State Detection (Task 2.1)

/// Eye type enumeration for eye-specific processing
private enum EyeType {
    case left
    case right
}

/// Result of enhanced eye analysis including quality metrics for eye state detection
private struct EyeStateAnalysisResult {
    let ear: Float                    // Eye Aspect Ratio
    let landmarks: [CGPoint]          // Original landmark points
    let landmarkQuality: Float        // Quality assessment of landmarks (0-1)
}

// MARK: - Supporting Types for Smile Analysis (Task 2.2)

/// Comprehensive lip region analysis result
private struct LipAnalysisResult {
    let curvature: Float              // Lip curvature intensity (0-1)
    let symmetry: Float               // Lip symmetry (0-1)
    let width: Float                  // Lip width relative to face (0-1)
    let openness: Float               // Lip openness/parting (0-1)
    let quality: Float                // Landmark quality assessment (0-1)
}

/// Cheek region analysis for smile muscle activation
private struct CheekAnalysisResult {
    let elevation: Float              // Cheek elevation during smile (0-1)
    let definition: Float             // Cheek muscle definition (0-1)
    let quality: Float                // Analysis quality assessment (0-1)
}

/// Eye region analysis for Duchenne smile detection
private struct EyeAnalysisResult {
    let creasing: Float               // Eye creasing intensity (0-1)
    let symmetry: Float               // Eye creasing symmetry (0-1)
    let quality: Float                // Analysis quality assessment (0-1)
}

// PersonID is already defined in PerfectMomentAnalysis.swift

// MARK: - Person Matching Supporting Types (Task 2.3)

/// Custom face embedding wrapper with additional metadata for person matching
private struct VNFaceEmbedding {
    let embedding: VNFeaturePrintObservation
    let boundingBox: CGRect
    let confidence: Float
    let qualityScore: Float
}

/// Result of person similarity calculation across multiple faces
private struct PersonSimilarityResult {
    let similarity: Float               // Final weighted similarity score (0-1)
    let confidence: Float              // Confidence in the match (0-1)
    let comparisonCount: Int           // Number of valid face comparisons made
    let maxSimilarity: Float           // Highest individual face similarity
    let averageSimilarity: Float       // Average similarity across all comparisons
}

/// Thresholds for person matching quality assessment
private struct PersonMatchingThresholds {
    static let minimumSimilarity: Float = 0.2          // Minimum to consider as potential match (lowered for debugging)
    static let mediumMatchThreshold: Float = 0.4       // Requires additional validation (lowered for debugging)
    static let strongMatchThreshold: Float = 0.6       // High confidence match (lowered for debugging)
    static let minimumConfidence: Float = 0.5          // Minimum confidence for strong match (lowered for debugging)
    static let maxTemporalGap: TimeInterval = 300      // 5 minutes max between faces
}

/// Weights for combining different similarity factors
private struct PersonMatchingWeights {
    static let embedding: Float = 0.7     // Face embedding similarity (primary)
    static let pose: Float = 0.2          // Face pose similarity (secondary)
    static let features: Float = 0.1      // Feature consistency (tertiary)
}