import Foundation
import UIKit

// MARK: - Cluster Representative Model

struct ClusterRepresentative: Identifiable {
    let id = UUID()
    let cluster: PhotoCluster
    let bestPhoto: Photo
    let importance: Float // Based on cluster size
    let qualityScore: Float
    let timeRange: (start: Date, end: Date)?
    
    var clusterSize: Int {
        return cluster.photos.count
    }
    
    var isImportantMoment: Bool {
        return clusterSize >= 3 // 3+ photos indicates intentional moment capture
    }
}

// MARK: - Cluster Curation Service

class ClusterCurationService: ObservableObject {
    
    // MARK: - Public Methods
    
    /// Analyzes clusters and returns representatives sorted by importance
    func curateClusterRepresentatives(from clusters: [PhotoCluster]) async -> [ClusterRepresentative] {
        var representatives: [ClusterRepresentative] = []
        
        for cluster in clusters {
            guard !cluster.photos.isEmpty else { continue }
            
            // Find best photo in cluster using quality scoring
            let bestPhoto = await findBestPhotoInCluster(cluster)
            
            // Calculate importance based on cluster size
            let importance = calculateClusterImportance(cluster)
            
            // Get quality score for best photo
            let qualityScore = await getPhotoQualityScore(bestPhoto)
            
            let representative = ClusterRepresentative(
                cluster: cluster,
                bestPhoto: bestPhoto,
                importance: importance,
                qualityScore: qualityScore,
                timeRange: cluster.timeRange
            )
            
            representatives.append(representative)
        }
        
        // Sort by importance (cluster size) then by quality
        return representatives.sorted { rep1, rep2 in
            if rep1.importance != rep2.importance {
                return rep1.importance > rep2.importance
            }
            return rep1.qualityScore > rep2.qualityScore
        }
    }
    
    /// Gets all photos in a cluster sorted by quality (best first)
    func getPhotosInCluster(_ cluster: PhotoCluster) async -> [Photo] {
        var photosWithScores: [(photo: Photo, score: Float)] = []
        
        for photo in cluster.photos {
            let score = await getPhotoQualityScore(photo)
            photosWithScores.append((photo: photo, score: score))
        }
        
        // Sort by quality score (highest first)
        return photosWithScores.sorted { $0.score > $1.score }.map { $0.photo }
    }
    
    // MARK: - Private Helper Methods
    
    private func findBestPhotoInCluster(_ cluster: PhotoCluster) async -> Photo {
        guard !cluster.photos.isEmpty else {
            fatalError("Cannot find best photo in empty cluster")
        }
        
        var bestPhoto = cluster.photos.first!
        var bestScore: Float = 0.0
        
        for photo in cluster.photos {
            let score = await getPhotoQualityScore(photo)
            if score > bestScore {
                bestScore = score
                bestPhoto = photo
            }
        }
        
        return bestPhoto
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