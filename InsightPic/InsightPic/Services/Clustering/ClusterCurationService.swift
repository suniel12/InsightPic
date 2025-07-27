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