import Foundation
import UIKit

// MARK: - Cluster Representative Model

struct ClusterRepresentative: Identifiable {
    let id = UUID()
    let cluster: PhotoCluster
    let bestPhoto: Photo
    let importance: Float // Based on cluster size
    let qualityScore: Float
    let facialQualityScore: Float // Enhanced facial quality scoring
    let rankingConfidence: Float // Confidence in representative selection
    let selectionReason: RepresentativeSelectionReason // Why this photo was chosen
    let timeRange: (start: Date, end: Date)?
    
    var clusterSize: Int {
        return cluster.photos.count
    }
    
    var isImportantMoment: Bool {
        return clusterSize >= 3 // 3+ photos indicates intentional moment capture
    }
    
    var combinedQualityScore: Float {
        // Weighted combination of overall quality and facial quality
        let photoType = PhotoType.detect(from: bestPhoto)
        return photoType.isPersonFocused ? 
            (qualityScore * 0.4 + facialQualityScore * 0.6) :
            (qualityScore * 0.8 + facialQualityScore * 0.2)
    }
}

// MARK: - Cluster Ranking Result

struct ClusterRankingResult {
    let photo: Photo
    let qualityScore: Float
    let facialQualityScore: Float
    let confidence: Float
    let reason: RepresentativeSelectionReason
}

// MARK: - Cluster Facial Analysis Models

/// Comprehensive facial diversity analysis for cluster optimization
struct ClusterFacialDiversityAnalysis {
    let clusterType: ClusterFacialType
    let peopleCount: Int
    let faceConsistencyScore: Float // How consistent facial quality is (0.0-1.0)
    let diversityScore: Float // How much facial variety exists (0.0-1.0)
    let bestFacePerPerson: [String: Photo] // Person ID -> Best photo for that person
    let facialQualityDistribution: FacialQualityDistribution
    let recommendedRepresentative: Photo?
    
    /// Indicates if cluster has good potential for facial optimization
    var hasGoodFacialPotential: Bool {
        return peopleCount > 0 && diversityScore > 0.2 && faceConsistencyScore > 0.4
    }
    
    /// Returns user-friendly summary of facial analysis
    var facialSummary: String {
        switch clusterType {
        case .singlePerson:
            if faceConsistencyScore > 0.7 {
                return "Single person with consistent quality"
            } else {
                return "Single person with varying expressions"
            }
        case .multiplePeople:
            if faceConsistencyScore > 0.6 && diversityScore > 0.3 {
                return "Group photo with good facial variety"
            } else if faceConsistencyScore > 0.7 {
                return "Group photo with consistent expressions"
            } else {
                return "Group photo with mixed facial quality"
            }
        case .noPeople:
            return "No people detected in cluster"
        }
    }
}

/// Types of facial clusters for specialized optimization
enum ClusterFacialType {
    case singlePerson // One person across multiple photos
    case multiplePeople // Multiple different people
    case noPeople // No faces detected
}

/// Distribution of facial quality within a cluster
struct FacialQualityDistribution {
    var excellent: Int // 0.8+ facial quality
    var good: Int // 0.6-0.8 facial quality
    var fair: Int // 0.4-0.6 facial quality
    var poor: Int // <0.4 facial quality
    
    var totalPhotos: Int {
        return excellent + good + fair + poor
    }
    
    var qualityPercentages: (excellent: Float, good: Float, fair: Float, poor: Float) {
        let total = Float(totalPhotos)
        guard total > 0 else { return (0, 0, 0, 0) }
        
        return (
            excellent: Float(excellent) / total * 100,
            good: Float(good) / total * 100,
            fair: Float(fair) / total * 100,
            poor: Float(poor) / total * 100
        )
    }
    
    var dominantQuality: String {
        let max = Swift.max(excellent, good, fair, poor)
        
        switch max {
        case excellent: return "Excellent"
        case good: return "Good"
        case fair: return "Fair"
        default: return "Poor"
        }
    }
    
    var hasGoodQualityMajority: Bool {
        return (excellent + good) > (fair + poor)
    }
}

// MARK: - Cluster Context Analysis Models

/// Comprehensive analysis of cluster context for optimal ranking
struct ClusterContextAnalysis {
    let clusterType: ClusterType
    let photoTypeBreakdown: [PhotoType: Int]
    let contentAnalysis: String
    let recommendedWeighting: RankingWeights
    let confidence: Float
    
    /// User-friendly description of cluster content
    var contextDescription: String {
        switch clusterType {
        case .portraitSession:
            return "Portrait photography session with focus on facial quality"
        case .groupEvent:
            return "Group event with multiple people and social interactions"
        case .landscapeCollection:
            return "Landscape photography emphasizing composition and technical quality"
        case .actionSequence:
            return "Action or movement sequence prioritizing sharpness and timing"
        case .mixedContent:
            return "Mixed content requiring balanced quality assessment"
        }
    }
}

/// Cluster type classification for context-aware ranking
enum ClusterType {
    case portraitSession // Single person or portrait-focused cluster
    case groupEvent // Multiple people, social gathering
    case landscapeCollection // Scenery, nature, landscapes
    case actionSequence // Sports, movement, action photos
    case mixedContent // Mixed photo types
    
    /// Indicates if this cluster type benefits from facial analysis
    var prioritizesFacialQuality: Bool {
        switch self {
        case .portraitSession, .groupEvent:
            return true
        case .landscapeCollection, .actionSequence, .mixedContent:
            return false
        }
    }
    
    /// Returns the emphasis for this cluster type
    var qualityEmphasis: String {
        switch self {
        case .portraitSession:
            return "Facial expressions and pose quality"
        case .groupEvent:
            return "Group dynamics and individual facial quality"
        case .landscapeCollection:
            return "Composition and technical excellence"
        case .actionSequence:
            return "Timing and motion capture"
        case .mixedContent:
            return "Balanced overall quality"
        }
    }
}

/// Adaptive ranking weights based on cluster context
struct RankingWeights {
    let technical: Float // Weight for technical quality (0.0-1.0)
    let facial: Float // Weight for facial quality (0.0-1.0)
    let contextual: Float // Weight for contextual factors (0.0-1.0)
    
    /// Validates that weights sum approximately to 1.0
    var isValid: Bool {
        let sum = technical + facial + contextual
        return abs(sum - 1.0) < 0.01 // Allow small floating-point variance
    }
    
    /// Pre-defined weight configurations
    static let balanced = RankingWeights(technical: 0.4, facial: 0.4, contextual: 0.2)
    static let facialPriority = RankingWeights(technical: 0.2, facial: 0.7, contextual: 0.1)
    static let technicalPriority = RankingWeights(technical: 0.7, facial: 0.1, contextual: 0.2)
    static let landscapeFocus = RankingWeights(technical: 0.6, facial: 0.1, contextual: 0.3)
    
    /// User-friendly description of weighting strategy
    var description: String {
        if facial > 0.6 {
            return "Prioritizing facial quality and expressions"
        } else if technical > 0.6 {
            return "Emphasizing technical and compositional excellence"
        } else {
            return "Using balanced quality assessment"
        }
    }
}

// MARK: - Cluster Curation Service

class ClusterCurationService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let faceQualityAnalysisService: FaceQualityAnalysisService
    
    // MARK: - Initialization
    
    init(faceQualityAnalysisService: FaceQualityAnalysisService = FaceQualityAnalysisService()) {
        self.faceQualityAnalysisService = faceQualityAnalysisService
    }
    
    // MARK: - Public Methods
    
    /// Analyzes clusters and returns representatives sorted by importance
    func curateClusterRepresentatives(from clusters: [PhotoCluster]) async -> [ClusterRepresentative] {
        var representatives: [ClusterRepresentative] = []
        
        for cluster in clusters {
            guard !cluster.photos.isEmpty else { continue }
            
            // Find best photo in cluster using enhanced quality scoring with facial analysis
            let rankingResult = await findBestPhotoInClusterWithRanking(cluster)
            
            // Calculate importance based on cluster size
            let importance = calculateClusterImportance(cluster)
            
            let representative = ClusterRepresentative(
                cluster: cluster,
                bestPhoto: rankingResult.photo,
                importance: importance,
                qualityScore: rankingResult.qualityScore,
                facialQualityScore: rankingResult.facialQualityScore,
                rankingConfidence: rankingResult.confidence,
                selectionReason: rankingResult.reason,
                timeRange: cluster.timeRange
            )
            
            representatives.append(representative)
        }
        
        // Sort by importance (cluster size) then by combined quality score
        return representatives.sorted { rep1, rep2 in
            if rep1.importance != rep2.importance {
                return rep1.importance > rep2.importance
            }
            return rep1.combinedQualityScore > rep2.combinedQualityScore
        }
    }
    
    /// Gets all photos in a cluster sorted by quality (best first) with enhanced facial analysis
    func getPhotosInCluster(_ cluster: PhotoCluster) async -> [Photo] {
        let clusterType = await detectClusterType(cluster)
        var photosWithScores: [(photo: Photo, combinedScore: Float)] = []
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let facialScore = await getFacialQualityScore(photo)
            
            // Weight scores based on cluster type
            let combinedScore = clusterType.isPersonFocused ?
                (qualityScore * 0.4 + facialScore * 0.6) :
                (qualityScore * 0.8 + facialScore * 0.2)
                
            photosWithScores.append((photo: photo, combinedScore: combinedScore))
        }
        
        // Sort by combined score (highest first)
        return photosWithScores.sorted { $0.combinedScore > $1.combinedScore }.map { $0.photo }
    }
    
    /// Updates cluster ranking metadata and returns an updated cluster
    func updateClusterRanking(_ cluster: PhotoCluster) async -> PhotoCluster {
        var updatedCluster = cluster
        
        // Get ranking result
        let rankingResult = await findBestPhotoInClusterWithRanking(cluster)
        
        // Get all ranked photos
        let rankedPhotos = await getPhotosInCluster(cluster)
        
        // Update cluster ranking metadata
        updatedCluster.updateRanking(
            rankedPhotos: rankedPhotos,
            representativePhoto: rankingResult.photo,
            reason: rankingResult.reason,
            confidence: rankingResult.confidence
        )
        
        return updatedCluster
    }
    
    /// Enhanced cluster ranking with group photo optimization using FaceQualityAnalysisService
    func updateClusterRankingWithGroupOptimization(_ cluster: PhotoCluster) async -> PhotoCluster {
        var updatedCluster = cluster
        
        // Determine if this cluster benefits from group photo optimization
        let clusterType = await detectClusterType(cluster)
        
        if clusterType.isPersonFocused && cluster.photos.count > 1 {
            // Use enhanced ranking for group photos
            let rankingResult = await findBestPhotoWithGroupOptimization(cluster)
            let rankedPhotos = await getRankedPhotosWithFacialAnalysis(cluster)
            
            updatedCluster.updateRanking(
                rankedPhotos: rankedPhotos,
                representativePhoto: rankingResult.photo,
                reason: rankingResult.reason,
                confidence: rankingResult.confidence
            )
        } else {
            // Use standard ranking for non-group photos
            updatedCluster = await updateClusterRanking(cluster)
        }
        
        return updatedCluster
    }
    
    /// Finds best photo with group photo optimization using facial analysis
    private func findBestPhotoWithGroupOptimization(_ cluster: PhotoCluster) async -> ClusterRankingResult {
        guard !cluster.photos.isEmpty else {
            fatalError("Cannot find best photo in empty cluster")
        }
        
        // Get comprehensive cluster face analysis
        let clusterAnalysis = await faceQualityAnalysisService.analyzeFaceQualityInCluster(cluster)
        
        var bestResult: ClusterRankingResult?
        var bestCombinedScore: Float = 0.0
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let enhancedFacialScore = await getEnhancedFacialQualityScore(photo, in: cluster)
            
            // Enhanced weighting for group photos with facial analysis insights
            let combinedScore = qualityScore * 0.3 + enhancedFacialScore * 0.7
            let reason: RepresentativeSelectionReason = enhancedFacialScore > 0.8 ? .bestFacialQuality : .balancedQualityAndFaces
            
            if combinedScore > bestCombinedScore {
                bestCombinedScore = combinedScore
                
                // Calculate enhanced confidence based on cluster analysis
                let confidence = calculateGroupPhotoConfidence(
                    combinedScore: combinedScore,
                    clusterAnalysis: clusterAnalysis,
                    photo: photo
                )
                
                bestResult = ClusterRankingResult(
                    photo: photo,
                    qualityScore: qualityScore,
                    facialQualityScore: enhancedFacialScore,
                    confidence: confidence,
                    reason: reason
                )
            }
        }
        
        return bestResult ?? ClusterRankingResult(
            photo: cluster.photos.first!,
            qualityScore: 0.0,
            facialQualityScore: 0.0,
            confidence: 0.1,
            reason: .fallbackSelection
        )
    }
    
    /// Gets ranked photos with enhanced facial analysis
    private func getRankedPhotosWithFacialAnalysis(_ cluster: PhotoCluster) async -> [Photo] {
        var photosWithScores: [(photo: Photo, combinedScore: Float)] = []
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let enhancedFacialScore = await getEnhancedFacialQualityScore(photo, in: cluster)
            
            // Group photo weighting
            let combinedScore = qualityScore * 0.3 + enhancedFacialScore * 0.7
            photosWithScores.append((photo: photo, combinedScore: combinedScore))
        }
        
        return photosWithScores.sorted { $0.combinedScore > $1.combinedScore }.map { $0.photo }
    }
    
    /// Calculates confidence for group photo ranking decisions
    private func calculateGroupPhotoConfidence(
        combinedScore: Float,
        clusterAnalysis: ClusterFaceAnalysis,
        photo: Photo
    ) -> Float {
        var confidence = combinedScore
        
        // Boost confidence if this photo is identified as a best face for someone
        if let photoAnalysis = findPhotoInClusterAnalysis(photo, in: clusterAnalysis) {
            if photoAnalysis.bestFace.photo.id == photo.id {
                confidence += 0.1 // 10% confidence boost for being someone's best face
            }
        }
        
        // Boost confidence based on overall cluster improvement potential
        if clusterAnalysis.overallImprovementPotential > 0.5 {
            confidence += clusterAnalysis.overallImprovementPotential * 0.1
        }
        
        return max(0.0, min(1.0, confidence))
    }
    
    // MARK: - Cluster-Specific Facial Quality Analysis
    
    /// Analyzes facial diversity within a cluster to optimize representative selection
    func analyzeFacialDiversity(in cluster: PhotoCluster) async -> ClusterFacialDiversityAnalysis {
        guard !cluster.photos.isEmpty else {
            return ClusterFacialDiversityAnalysis(
                clusterType: .noPeople,
                peopleCount: 0,
                faceConsistencyScore: 0.0,
                diversityScore: 0.0,
                bestFacePerPerson: [:],
                facialQualityDistribution: FacialQualityDistribution(excellent: 0, good: 0, fair: 0, poor: 0),
                recommendedRepresentative: nil
            )
        }
        
        // Get cluster face analysis
        let clusterAnalysis = await faceQualityAnalysisService.analyzeFaceQualityInCluster(cluster)
        
        // Determine cluster type based on people and diversity
        let clusterType = determineClusterFacialType(from: clusterAnalysis)
        
        // Calculate facial consistency across photos
        let consistencyScore = calculateFacialConsistency(from: clusterAnalysis)
        
        // Calculate diversity score
        let diversityScore = calculateFacialDiversity(from: clusterAnalysis)
        
        // Get best face per person
        let bestFacePerPerson = extractBestFacePerPerson(from: clusterAnalysis)
        
        // Analyze facial quality distribution
        let qualityDistribution = await analyzeFacialQualityDistribution(in: cluster)
        
        // Find recommended representative based on facial analysis
        let recommendedRepresentative = await findOptimalRepresentativeForFaces(
            cluster: cluster,
            clusterAnalysis: clusterAnalysis,
            clusterType: clusterType
        )
        
        return ClusterFacialDiversityAnalysis(
            clusterType: clusterType,
            peopleCount: clusterAnalysis.personAnalyses.count,
            faceConsistencyScore: consistencyScore,
            diversityScore: diversityScore,
            bestFacePerPerson: bestFacePerPerson,
            facialQualityDistribution: qualityDistribution,
            recommendedRepresentative: recommendedRepresentative
        )
    }
    
    /// Gets facial quality distribution for cluster optimization
    func getFacialQualityDistribution(for cluster: PhotoCluster) async -> FacialQualityDistribution {
        return await analyzeFacialQualityDistribution(in: cluster)
    }
    
    /// Finds the best representative photo based on facial diversity analysis
    func findOptimalFacialRepresentative(for cluster: PhotoCluster) async -> ClusterRankingResult {
        let diversityAnalysis = await analyzeFacialDiversity(in: cluster)
        
        if let recommendedPhoto = diversityAnalysis.recommendedRepresentative {
            let qualityScore = await getPhotoQualityScore(recommendedPhoto)
            let facialScore = await getEnhancedFacialQualityScore(recommendedPhoto, in: cluster)
            
            let reason: RepresentativeSelectionReason
            switch diversityAnalysis.clusterType {
            case .singlePerson:
                reason = .bestFacialQuality
            case .multiplePeople:
                reason = .balancedQualityAndFaces
            case .noPeople:
                reason = .highestOverallQuality
            }
            
            let confidence = calculateFacialDiversityConfidence(
                diversityAnalysis: diversityAnalysis,
                photo: recommendedPhoto
            )
            
            return ClusterRankingResult(
                photo: recommendedPhoto,
                qualityScore: qualityScore,
                facialQualityScore: facialScore,
                confidence: confidence,
                reason: reason
            )
        }
        
        // Fallback to standard ranking
        return await findBestPhotoInClusterWithRanking(cluster)
    }
    
    // MARK: - Private Facial Analysis Methods
    
    /// Determines the facial type of a cluster based on people analysis
    private func determineClusterFacialType(from clusterAnalysis: ClusterFaceAnalysis) -> ClusterFacialType {
        let peopleCount = clusterAnalysis.personAnalyses.count
        
        if peopleCount == 0 {
            return .noPeople
        } else if peopleCount == 1 {
            return .singlePerson
        } else {
            return .multiplePeople
        }
    }
    
    /// Calculates facial consistency score across cluster photos
    private func calculateFacialConsistency(from clusterAnalysis: ClusterFaceAnalysis) -> Float {
        let personAnalyses = Array(clusterAnalysis.personAnalyses.values)
        guard !personAnalyses.isEmpty else { return 0.0 }
        
        var totalConsistency: Float = 0.0
        
        for personAnalysis in personAnalyses {
            let faces = personAnalysis.allFaces
            guard faces.count > 1 else {
                totalConsistency += 1.0 // Single face is perfectly consistent
                continue
            }
            
            // Calculate quality variance for this person
            let qualityScores = faces.map { $0.qualityRank }
            let averageQuality = qualityScores.reduce(0, +) / Float(qualityScores.count)
            
            let variance = qualityScores.reduce(0) { sum, score in
                let diff = score - averageQuality
                return sum + (diff * diff)
            } / Float(qualityScores.count)
            
            // Convert variance to consistency (lower variance = higher consistency)
            let consistency = max(0.0, 1.0 - variance)
            totalConsistency += consistency
        }
        
        return totalConsistency / Float(personAnalyses.count)
    }
    
    /// Calculates facial diversity score (variation in expressions, poses, etc.)
    private func calculateFacialDiversity(from clusterAnalysis: ClusterFaceAnalysis) -> Float {
        let personAnalyses = Array(clusterAnalysis.personAnalyses.values)
        guard !personAnalyses.isEmpty else { return 0.0 }
        
        var totalDiversity: Float = 0.0
        
        for personAnalysis in personAnalyses {
            let faces = personAnalysis.allFaces
            guard faces.count > 1 else {
                totalDiversity += 0.0 // Single face has no diversity
                continue
            }
            
            // Calculate diversity based on quality range and expression variety
            let qualityScores = faces.map { $0.qualityRank }
            let qualityRange = (qualityScores.max() ?? 0) - (qualityScores.min() ?? 0)
            
            // Diversity is good when there's variation but not too extreme
            let optimalRange: Float = 0.3 // Sweet spot for quality variation
            let diversityScore = min(1.0, qualityRange / optimalRange)
            
            totalDiversity += diversityScore
        }
        
        return totalDiversity / Float(personAnalyses.count)
    }
    
    /// Extracts best face per person from cluster analysis
    private func extractBestFacePerPerson(from clusterAnalysis: ClusterFaceAnalysis) -> [String: Photo] {
        var bestFacePerPerson: [String: Photo] = [:]
        
        for (personID, personAnalysis) in clusterAnalysis.personAnalyses {
            bestFacePerPerson[personID] = personAnalysis.bestFace.photo
        }
        
        return bestFacePerPerson
    }
    
    /// Analyzes facial quality distribution within cluster
    private func analyzeFacialQualityDistribution(in cluster: PhotoCluster) async -> FacialQualityDistribution {
        var distribution = FacialQualityDistribution(excellent: 0, good: 0, fair: 0, poor: 0)
        
        for photo in cluster.photos {
            let facialScore = await getEnhancedFacialQualityScore(photo, in: cluster)
            
            switch facialScore {
            case 0.8...1.0:
                distribution.excellent += 1
            case 0.6..<0.8:
                distribution.good += 1
            case 0.4..<0.6:
                distribution.fair += 1
            default:
                distribution.poor += 1
            }
        }
        
        return distribution
    }
    
    /// Finds optimal representative based on facial analysis
    private func findOptimalRepresentativeForFaces(
        cluster: PhotoCluster,
        clusterAnalysis: ClusterFaceAnalysis,
        clusterType: ClusterFacialType
    ) async -> Photo? {
        switch clusterType {
        case .singlePerson:
            // For single person, find their best face
            if let personAnalysis = clusterAnalysis.personAnalyses.values.first {
                return personAnalysis.bestFace.photo
            }
            
        case .multiplePeople:
            // For multiple people, find photo that best represents the group
            return await findBestGroupRepresentative(cluster: cluster, clusterAnalysis: clusterAnalysis)
            
        case .noPeople:
            // For no people, use standard quality ranking
            break
        }
        
        return nil
    }
    
    /// Finds best representative for group photos with multiple people
    private func findBestGroupRepresentative(
        cluster: PhotoCluster,
        clusterAnalysis: ClusterFaceAnalysis
    ) async -> Photo? {
        var photoScores: [(photo: Photo, score: Float)] = []
        
        for photo in cluster.photos {
            var score: Float = 0.0
            var peopleInPhoto: Int = 0
            
            // Score based on how many people have good faces in this photo
            for (_, personAnalysis) in clusterAnalysis.personAnalyses {
                for face in personAnalysis.allFaces {
                    if face.photo.id == photo.id {
                        score += face.qualityRank
                        peopleInPhoto += 1
                        break
                    }
                }
            }
            
            // Normalize by number of people and apply group bonus
            if peopleInPhoto > 0 {
                score = score / Float(peopleInPhoto)
                
                // Bonus for photos that include more people
                let peopleRatio = Float(peopleInPhoto) / Float(clusterAnalysis.personAnalyses.count)
                score += peopleRatio * 0.2 // Up to 20% bonus
            }
            
            photoScores.append((photo: photo, score: score))
        }
        
        return photoScores.max(by: { $0.score < $1.score })?.photo
    }
    
    /// Calculates confidence for facial diversity-based ranking
    private func calculateFacialDiversityConfidence(
        diversityAnalysis: ClusterFacialDiversityAnalysis,
        photo: Photo
    ) -> Float {
        var confidence: Float = 0.5
        
        // Higher confidence for consistent facial quality
        confidence += diversityAnalysis.faceConsistencyScore * 0.2
        
        // Moderate diversity is good for confidence
        let optimalDiversity: Float = 0.5
        let diversityFactor = 1.0 - abs(diversityAnalysis.diversityScore - optimalDiversity)
        confidence += diversityFactor * 0.1
        
        // Higher confidence for multiple people scenarios
        switch diversityAnalysis.clusterType {
        case .multiplePeople:
            confidence += 0.1
        case .singlePerson:
            confidence += 0.05
        case .noPeople:
            confidence -= 0.1
        }
        
        return max(0.0, min(1.0, confidence))
    }
    
    // MARK: - Cluster Type Detection & Context-Aware Ranking
    
    /// Analyzes cluster content to determine optimal ranking strategy
    func analyzeClusterContext(_ cluster: PhotoCluster) async -> ClusterContextAnalysis {
        guard !cluster.photos.isEmpty else {
            return ClusterContextAnalysis(
                clusterType: .mixedContent,
                photoTypeBreakdown: [:],
                contentAnalysis: "Empty cluster",
                recommendedWeighting: RankingWeights.balanced,
                confidence: 0.0
            )
        }
        
        // Analyze photo types in cluster
        let photoTypes = await analyzePhotoTypesInCluster(cluster)
        
        // Determine cluster type based on content analysis
        let clusterType = determineClusterType(from: photoTypes, cluster: cluster)
        
        // Calculate content consistency
        let contentConsistency = calculateContentConsistency(photoTypes: photoTypes)
        
        // Get recommended ranking weights for this cluster type
        let recommendedWeighting = getOptimalRankingWeights(for: clusterType, cluster: cluster)
        
        // Generate context insights
        let contextInsights = generateContextInsights(
            clusterType: clusterType,
            photoTypes: photoTypes,
            cluster: cluster
        )
        
        return ClusterContextAnalysis(
            clusterType: clusterType,
            photoTypeBreakdown: photoTypes,
            contentAnalysis: contextInsights.joined(separator: ", "),
            recommendedWeighting: recommendedWeighting,
            confidence: contentConsistency
        )
    }
    
    /// Gets adaptive ranking weights based on cluster content analysis
    func getAdaptiveRankingWeights(for cluster: PhotoCluster) async -> RankingWeights {
        let contextAnalysis = await analyzeClusterContext(cluster)
        return contextAnalysis.recommendedWeighting
    }
    
    /// Ranks photos using adaptive weighting based on cluster context
    func rankPhotosWithAdaptiveWeighting(_ cluster: PhotoCluster) async -> [Photo] {
        let weights = await getAdaptiveRankingWeights(for: cluster)
        var photosWithScores: [(photo: Photo, adaptiveScore: Float)] = []
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let facialScore = await getEnhancedFacialQualityScore(photo, in: cluster)
            let contextScore = await getContextualScore(photo, in: cluster)
            
            // Apply adaptive weighting
            let adaptiveScore = (qualityScore * weights.technical) +
                               (facialScore * weights.facial) +
                               (contextScore * weights.contextual)
            
            photosWithScores.append((photo: photo, adaptiveScore: adaptiveScore))
        }
        
        return photosWithScores.sorted { $0.adaptiveScore > $1.adaptiveScore }.map { $0.photo }
    }
    
    // MARK: - Private Context Analysis Methods
    
    /// Analyzes photo types within a cluster for context determination
    private func analyzePhotoTypesInCluster(_ cluster: PhotoCluster) async -> [PhotoType: Int] {
        var photoTypeCounts: [PhotoType: Int] = [:]
        
        // Sample photos to avoid performance issues with large clusters
        let sampleSize = min(5, cluster.photos.count)
        let samplePhotos = Array(cluster.photos.prefix(sampleSize))
        
        for photo in samplePhotos {
            let photoType = PhotoType.detect(from: photo)
            photoTypeCounts[photoType, default: 0] += 1
        }
        
        return photoTypeCounts
    }
    
    /// Determines cluster type based on photo type analysis
    private func determineClusterType(from photoTypes: [PhotoType: Int], cluster: PhotoCluster) -> ClusterType {
        let totalPhotos = photoTypes.values.reduce(0, +)
        guard totalPhotos > 0 else { return .mixedContent }
        
        // Find dominant photo type
        let dominantType = photoTypes.max(by: { $0.value < $1.value })?.key
        let dominantCount = photoTypes.max(by: { $0.value < $1.value })?.value ?? 0
        let dominantPercentage = Float(dominantCount) / Float(totalPhotos)
        
        // If one type dominates (>70%), use specialized cluster type
        if dominantPercentage > 0.7 {
            switch dominantType {
            case .portrait, .groupPhoto, .multipleFaces:
                return cluster.photos.count > 3 ? .groupEvent : .portraitSession
            case .landscape, .outdoor, .goldenHour:
                return .landscapeCollection
            case .event:
                return .groupEvent
            case .closeUp:
                return .actionSequence
            default:
                return .mixedContent
            }
        }
        
        // Check for group event patterns
        if photoTypes[.groupPhoto] ?? 0 > 0 || photoTypes[.event] ?? 0 > 0 {
            return .groupEvent
        }
        
        // Check for portrait session patterns
        if photoTypes[.portrait] ?? 0 > 0 && cluster.photos.count > 2 {
            return .portraitSession
        }
        
        return .mixedContent
    }
    
    /// Calculates content consistency within cluster
    private func calculateContentConsistency(photoTypes: [PhotoType: Int]) -> Float {
        let totalPhotos = photoTypes.values.reduce(0, +)
        guard totalPhotos > 1 else { return 1.0 }
        
        // Calculate entropy (lower entropy = higher consistency)
        var entropy: Float = 0.0
        for count in photoTypes.values {
            let probability = Float(count) / Float(totalPhotos)
            if probability > 0 {
                entropy -= probability * log2(probability)
            }
        }
        
        // Convert entropy to consistency score (0-1, higher is more consistent)
        let maxEntropy = log2(Float(photoTypes.count))
        let consistency = maxEntropy > 0 ? 1.0 - (entropy / maxEntropy) : 1.0
        
        return max(0.0, min(1.0, consistency))
    }
    
    /// Gets optimal ranking weights for cluster type
    private func getOptimalRankingWeights(for clusterType: ClusterType, cluster: PhotoCluster) -> RankingWeights {
        switch clusterType {
        case .portraitSession:
            // Heavy emphasis on facial quality for portrait sessions
            return RankingWeights(technical: 0.2, facial: 0.7, contextual: 0.1)
            
        case .groupEvent:
            // Balanced facial and contextual for group events
            return RankingWeights(technical: 0.25, facial: 0.5, contextual: 0.25)
            
        case .landscapeCollection:
            // Technical and contextual emphasis for landscapes
            return RankingWeights(technical: 0.6, facial: 0.1, contextual: 0.3)
            
        case .actionSequence:
            // Technical quality primary for detail shots
            return RankingWeights(technical: 0.7, facial: 0.1, contextual: 0.2)
            
        case .mixedContent:
            // Balanced approach for mixed content
            return RankingWeights(technical: 0.4, facial: 0.4, contextual: 0.2)
        }
    }
    
    /// Generates context insights for cluster analysis
    private func generateContextInsights(
        clusterType: ClusterType,
        photoTypes: [PhotoType: Int],
        cluster: PhotoCluster
    ) -> [String] {
        var insights: [String] = []
        
        // Cluster type insight
        switch clusterType {
        case .portraitSession:
            insights.append("Portrait session detected - prioritizing facial quality")
        case .groupEvent:
            insights.append("Group event detected - balancing faces and context")
        case .landscapeCollection:
            insights.append("Landscape session detected - emphasizing composition")
        case .actionSequence:
            insights.append("Detail photography detected - focusing on technical quality")
        case .mixedContent:
            insights.append("Mixed content detected - using balanced approach")
        }
        
        // Content analysis insights
        let totalPhotos = photoTypes.values.reduce(0, +)
        if let dominantType = photoTypes.max(by: { $0.value < $1.value }) {
            let percentage = Float(dominantType.value) / Float(totalPhotos) * 100
            insights.append("\(dominantType.key.rawValue) photos dominate (\(Int(percentage))%)")
        }
        
        // Size-based insights
        if cluster.photos.count > 10 {
            insights.append("Large cluster - high confidence in type detection")
        } else if cluster.photos.count < 3 {
            insights.append("Small cluster - limited context for optimization")
        }
        
        return insights
    }
    
    /// Gets contextual score for a photo within cluster context
    private func getContextualScore(_ photo: Photo, in cluster: PhotoCluster) async -> Float {
        // Use existing overall score context component
        if let contextScore = photo.overallScore?.context {
            return contextScore
        }
        
        // Fallback contextual scoring
        var contextScore: Float = 0.5
        
        // Time context - photos at cluster temporal edges get slight bonus
        let timestamps = cluster.photos.map { $0.timestamp }.sorted()
        if let firstTime = timestamps.first, let lastTime = timestamps.last {
            let totalDuration = lastTime.timeIntervalSince(firstTime)
            if totalDuration > 0 {
                let photoPosition = photo.timestamp.timeIntervalSince(firstTime) / totalDuration
                let edgeBonus = min(photoPosition, 1.0 - photoPosition) * 0.1
                contextScore += Float(edgeBonus)
            }
        }
        
        return min(1.0, contextScore)
    }
    
    // MARK: - Private Helper Methods
    
    /// Enhanced photo ranking with integrated facial analysis and cluster-specific weighting
    private func findBestPhotoInClusterWithRanking(_ cluster: PhotoCluster) async -> ClusterRankingResult {
        guard !cluster.photos.isEmpty else {
            fatalError("Cannot find best photo in empty cluster")
        }
        
        // Single photo - simple case
        if cluster.photos.count == 1 {
            let photo = cluster.photos.first!
            let qualityScore = await getPhotoQualityScore(photo)
            let facialScore = await getFacialQualityScore(photo)
            
            return ClusterRankingResult(
                photo: photo,
                qualityScore: qualityScore,
                facialQualityScore: facialScore,
                confidence: 0.5, // Low confidence for single photo
                reason: .onlyOptionAvailable
            )
        }
        
        // Multiple photos - enhanced ranking
        let clusterType = await detectClusterType(cluster)
        var bestResult: ClusterRankingResult?
        var bestCombinedScore: Float = 0.0
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let facialScore = await getFacialQualityScore(photo)
            
            // Calculate combined score based on cluster type
            let combinedScore: Float
            let reason: RepresentativeSelectionReason
            
            if clusterType.isPersonFocused {
                // Prioritize facial quality for person-focused photos
                combinedScore = qualityScore * 0.4 + facialScore * 0.6
                reason = facialScore > 0.7 ? .bestFacialQuality : .balancedQualityAndFaces
            } else {
                // Prioritize overall quality for scenery photos
                combinedScore = qualityScore * 0.8 + facialScore * 0.2
                reason = .highestOverallQuality
            }
            
            if combinedScore > bestCombinedScore {
                bestCombinedScore = combinedScore
                bestResult = ClusterRankingResult(
                    photo: photo,
                    qualityScore: qualityScore,
                    facialQualityScore: facialScore,
                    confidence: calculateRankingConfidence(combinedScore: combinedScore, clusterSize: cluster.photos.count),
                    reason: reason
                )
            }
        }
        
        return bestResult ?? ClusterRankingResult(
            photo: cluster.photos.first!,
            qualityScore: 0.0,
            facialQualityScore: 0.0,
            confidence: 0.1,
            reason: .fallbackSelection
        )
    }
    
    /// Legacy method for backward compatibility
    private func findBestPhotoInCluster(_ cluster: PhotoCluster) async -> Photo {
        let result = await findBestPhotoInClusterWithRanking(cluster)
        return result.photo
    }
    
    private func calculateClusterImportance(_ cluster: PhotoCluster) -> Float {
        let clusterSize = cluster.photos.count
        
        // Importance scoring based on cluster size
        switch clusterSize {
        case 1:
            return 0.1 // Single photos are least important
        case 2:
            return 0.3 // Pair shots are moderately important
        case 3...5:
            return 0.6 // Small burst indicates intentional moment
        case 6...10:
            return 0.8 // Medium burst indicates important moment
        case 11...20:
            return 0.9 // Large burst indicates very important moment
        default:
            return 1.0 // Very large burst indicates extremely important moment
        }
    }
    
    /// Detects the dominant content type of photos in a cluster
    private func detectClusterType(_ cluster: PhotoCluster) async -> PhotoType {
        guard !cluster.photos.isEmpty else { return .utility }
        
        // Sample up to 3 photos to determine cluster type
        let samplePhotos = Array(cluster.photos.prefix(3))
        var typeVotes: [PhotoType: Int] = [:]
        
        for photo in samplePhotos {
            let photoType = PhotoType.detect(from: photo)
            typeVotes[photoType, default: 0] += 1
        }
        
        // Return the most common type, or portrait as fallback
        return typeVotes.max(by: { $0.value < $1.value })?.key ?? .portrait
    }
    
    /// Calculates facial quality score for a photo using FaceQualityAnalysisService
    private func getFacialQualityScore(_ photo: Photo) async -> Float {
        // Use face quality from existing analysis if available
        if let faceQuality = photo.faceQuality, faceQuality.faceCount > 0 {
            return faceQuality.compositeScore
        }
        
        // For photos without faces, return neutral score
        return 0.5
    }
    
    /// Enhanced facial quality scoring with cluster context using FaceQualityAnalysisService
    private func getEnhancedFacialQualityScore(_ photo: Photo, in cluster: PhotoCluster) async -> Float {
        // Use face quality from existing analysis if available and recent
        if let faceQuality = photo.faceQuality, faceQuality.faceCount > 0 {
            var baseScore = faceQuality.compositeScore
            
            // Apply cluster-specific enhancements
            if cluster.photos.count > 1 {
                // Get cluster face analysis for context
                let clusterAnalysis = await faceQualityAnalysisService.analyzeFaceQualityInCluster(cluster)
                
                // Find this photo's analysis in the cluster context
                if let photoAnalysis = findPhotoInClusterAnalysis(photo, in: clusterAnalysis) {
                    // Enhance score with detailed facial analysis
                    baseScore = calculateEnhancedFaceScore(from: photoAnalysis, baseScore: baseScore)
                }
            }
            
            return baseScore
        }
        
        // For photos without existing face analysis, perform basic analysis
        return await performBasicFaceAnalysis(photo)
    }
    
    /// Finds photo-specific analysis within cluster analysis results
    private func findPhotoInClusterAnalysis(_ photo: Photo, in clusterAnalysis: ClusterFaceAnalysis) -> PersonFaceQualityAnalysis? {
        // Look for analysis that matches this photo
        for (_, personAnalysis) in clusterAnalysis.personAnalyses {
            if personAnalysis.bestFace.photo.id == photo.id {
                return personAnalysis
            }
            // Also check other faces in case this isn't the best face
            for face in personAnalysis.allFaces {
                if face.photo.id == photo.id {
                    return personAnalysis
                }
            }
        }
        return nil
    }
    
    /// Calculates enhanced face score using detailed facial analysis
    private func calculateEnhancedFaceScore(from personAnalysis: PersonFaceQualityAnalysis, baseScore: Float) -> Float {
        var enhancedScore = baseScore
        
        // Bonus for being the best face for this person
        if personAnalysis.bestFace.qualityRank > 0.8 {
            enhancedScore += 0.1 // 10% bonus for high-quality best face
        }
        
        // Penalty if this is a problematic face
        if let worstFace = personAnalysis.allFaces.min(by: { $0.qualityRank < $1.qualityRank }) {
            if worstFace.qualityRank < 0.3 {
                enhancedScore -= 0.05 // Small penalty for low-quality faces
            }
        }
        
        // Improvement potential bonus
        if personAnalysis.improvementPotential > 0.5 {
            enhancedScore += personAnalysis.improvementPotential * 0.1
        }
        
        return max(0.0, min(1.0, enhancedScore))
    }
    
    /// Performs basic face analysis for photos without existing analysis
    private func performBasicFaceAnalysis(_ photo: Photo) async -> Float {
        // Create a temporary single-photo cluster for analysis
        var tempCluster = PhotoCluster()
        tempCluster.photos = [photo]
        
        // Get face rankings for this photo
        let faceRankings = await faceQualityAnalysisService.rankFaceQualityInPhotos([photo])
        
        if let photoFaces = faceRankings[photo.assetIdentifier], !photoFaces.isEmpty {
            // Calculate average face quality
            let averageQuality = photoFaces.reduce(0.0) { $0 + $1.qualityRank } / Float(photoFaces.count)
            return averageQuality
        }
        
        // No faces found
        return 0.5
    }
    
    /// Calculates confidence in the ranking decision based on score and cluster size
    private func calculateRankingConfidence(combinedScore: Float, clusterSize: Int) -> Float {
        // Higher confidence for:
        // - Higher quality scores
        // - Larger clusters (more options to choose from)
        let scoreConfidence = combinedScore
        let sizeConfidence = min(Float(clusterSize) / 10.0, 1.0) // Caps at cluster size 10
        
        return (scoreConfidence * 0.7 + sizeConfidence * 0.3)
    }
    
    private func getPhotoQualityScore(_ photo: Photo) async -> Float {
        // Use existing overall score if available
        if let overallScore = photo.overallScore?.overall {
            return Float(overallScore)
        }
        
        // Fallback: calculate basic quality score
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
            score += Float(techQuality.sharpness) * 0.1
            score += Float(techQuality.exposure) * 0.1
            score += Float(techQuality.composition) * 0.1
        }
        
        return min(1.0, score)
    }
    
    // MARK: - Statistics
    
    func generateClusterStatistics(_ representatives: [ClusterRepresentative]) -> ClusterStatistics {
        let totalClusters = representatives.count
        let totalPhotos = representatives.reduce(0) { $0 + $1.clusterSize }
        let importantMoments = representatives.filter { $0.isImportantMoment }.count
        let averageClusterSize = totalClusters > 0 ? Float(totalPhotos) / Float(totalClusters) : 0
        
        let largestCluster = representatives.max { $0.clusterSize < $1.clusterSize }
        
        return ClusterStatistics(
            totalClusters: totalClusters,
            totalPhotos: totalPhotos,
            importantMoments: importantMoments,
            averageClusterSize: averageClusterSize,
            largestClusterSize: largestCluster?.clusterSize ?? 0,
            analysisDate: Date()
        )
    }
}

// MARK: - Cluster Statistics

struct ClusterStatistics {
    let totalClusters: Int
    let totalPhotos: Int
    let importantMoments: Int
    let averageClusterSize: Float
    let largestClusterSize: Int
    let analysisDate: Date
    
    var importantMomentsPercentage: Float {
        guard totalClusters > 0 else { return 0 }
        return Float(importantMoments) / Float(totalClusters) * 100
    }
}