import Foundation
import Vision
import UIKit
import CoreLocation

// MARK: - Clustering Models

struct PhotoSubCluster: Identifiable, Hashable {
    let id = UUID()
    var photos: [Photo] = []
    let similarityThreshold: Float
    let clusterType: SubClusterType
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoSubCluster, rhs: PhotoSubCluster) -> Bool {
        lhs.id == rhs.id
    }
}

enum SubClusterType {
    case nearIdentical(threshold: Float = 0.4)
    case similar(threshold: Float = 0.6)
    case poses(threshold: Float = 0.7)
    case temporal(timeGap: TimeInterval)
}

struct ClusterQualityMetrics {
    let diversityScore: Float          // How diverse the photos are within cluster
    let representativenessScore: Float // How well the cluster represents a coherent scene/moment
    let temporalCoherence: Float       // How well photos are temporally grouped
    let visualCoherence: Float         // How visually similar photos are
    let aestheticConsistency: Float    // How consistent quality is across photos
    let saliencyAlignment: Float       // How well salient regions align across photos
    
    var overallClusterQuality: Float {
        return (diversityScore * 0.2 + 
               representativenessScore * 0.25 + 
               temporalCoherence * 0.15 + 
               visualCoherence * 0.15 + 
               aestheticConsistency * 0.15 + 
               saliencyAlignment * 0.1)
    }
}

struct PhotoRankingScore {
    let photo: Photo
    let overallRank: Float
    let qualityScore: Float
    let clusterRelevance: Float
    let uniquenessScore: Float
    let temporalOptimality: Float
    let saliencyScore: Float
    let aestheticScore: Float
    
    var combinedScore: Float {
        return (qualityScore * 0.3 +
               clusterRelevance * 0.25 +
               uniquenessScore * 0.2 +
               temporalOptimality * 0.1 +
               saliencyScore * 0.1 +
               aestheticScore * 0.05)
    }
}

struct PhotoCluster: Identifiable, Hashable {
    let id = UUID()
    var photos: [Photo] = []
    var representativeFingerprint: VNFeaturePrintObservation?
    var centerLocation: CLLocation?
    var timeRange: (start: Date, end: Date)?
    
    // Enhanced ranking support
    var rankedPhotos: [Photo] = []
    var clusterRepresentativePhoto: Photo?
    var subClusters: [PhotoSubCluster] = []
    var clusterQualityMetrics: ClusterQualityMetrics?
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoCluster, rhs: PhotoCluster) -> Bool {
        lhs.id == rhs.id
    }
    
    var medianTimestamp: Date {
        let sorted = photos.map(\.timestamp).sorted()
        return sorted.isEmpty ? Date() : sorted[sorted.count / 2]
    }
    
    var averageQualityScore: Double {
        guard !photos.isEmpty else { return 0.0 }
        let scores = photos.compactMap { $0.overallScore?.overall }
        return scores.isEmpty ? 0.0 : Double(scores.reduce(0, +)) / Double(scores.count)
    }
    
    // Enhanced quality metrics
    var bestPhoto: Photo? {
        return rankedPhotos.first ?? photos.max { 
            ($0.overallScore?.overall ?? 0) < ($1.overallScore?.overall ?? 0) 
        }
    }
    
    var diversityScore: Float {
        return clusterQualityMetrics?.diversityScore ?? 0.0
    }
    
    var representativenessScore: Float {
        return clusterQualityMetrics?.representativenessScore ?? 0.0
    }
    
    mutating func add(_ photo: Photo, fingerprint: VNFeaturePrintObservation?) {
        photos.append(photo)
        
        // Update representative fingerprint (use first photo's fingerprint)
        if representativeFingerprint == nil {
            representativeFingerprint = fingerprint
        }
        
        // Update location center
        updateCenterLocation()
        
        // Update time range
        updateTimeRange()
    }
    
    private mutating func updateCenterLocation() {
        let locations = photos.compactMap(\.location)
        guard !locations.isEmpty else { return }
        
        let avgLat = locations.map(\.coordinate.latitude).reduce(0, +) / Double(locations.count)
        let avgLon = locations.map(\.coordinate.longitude).reduce(0, +) / Double(locations.count)
        
        centerLocation = CLLocation(latitude: avgLat, longitude: avgLon)
    }
    
    private mutating func updateTimeRange() {
        let timestamps = photos.map(\.timestamp).sorted()
        guard let first = timestamps.first, let last = timestamps.last else { return }
        timeRange = (start: first, end: last)
    }
}

struct ClusteringCriteria {
    // Simplified high-level clustering criteria as specified by user
    let visualSimilarityThreshold: Float = 0.50  // 50% similarity threshold
    let timeGapThreshold: TimeInterval = 30.0     // 30-second rolling window
    let locationRadiusMeters: Double = 50.0       // 50-meter location radius
    let maxClusterSize: Int = 20                  // 20-photo cluster size limit
    
    // Simple face compatibility rules (no complex recognition):
    // - 0 faces: Always compatible (landscapes, objects, etc.)
    // - 1+ faces: Use basic face count grouping only
    
    // Legacy similarity definitions (for reference)
    static let sameScaneDifferentPose: Float = 0.85
    static let sameLocationDifferentFraming: Float = 0.70
    static let relatedContext: Float = 0.50
}

// MARK: - PhotoClusteringService Protocol

protocol PhotoClusteringServiceProtocol {
    func generateFingerprint(for image: UIImage) async -> VNFeaturePrintObservation?
    func calculateSimilarity(_ print1: VNFeaturePrintObservation, _ print2: VNFeaturePrintObservation) -> Float
    func clusterPhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws -> [PhotoCluster]
    func findSimilarPhotos(in clusters: [PhotoCluster], similarity: Float) -> [[Photo]]
    func rankPhotosInCluster(_ cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> PhotoCluster
    func createSubClusters(for cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> [PhotoSubCluster]
    func calculateClusterQualityMetrics(for cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> ClusterQualityMetrics
}

// MARK: - Photo Cluster Ranking Service

class PhotoClusterRankingService {
    private let photoLibraryService: PhotoLibraryServiceProtocol
    
    init(photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
    }
    
    func rankPhotosInCluster(_ cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> [PhotoRankingScore] {
        var rankingScores: [PhotoRankingScore] = []
        
        for photo in cluster.photos {
            guard let analysis = analysisResults[photo.id] else { continue }
            
            let qualityScore = Float(analysis.overallScore)
            let clusterRelevance = await calculateClusterRelevance(photo: photo, cluster: cluster, analysisResults: analysisResults)
            let uniquenessScore = await calculateUniquenessScore(photo: photo, cluster: cluster, analysisResults: analysisResults)
            let temporalOptimality = calculateTemporalOptimality(photo: photo, cluster: cluster)
            let saliencyScore = calculateSaliencyScore(analysis: analysis)
            let aestheticScore = calculateEnhancedAestheticScore(analysis: analysis)
            
            let ranking = PhotoRankingScore(
                photo: photo,
                overallRank: 0, // Will be set after sorting
                qualityScore: qualityScore,
                clusterRelevance: clusterRelevance,
                uniquenessScore: uniquenessScore,
                temporalOptimality: temporalOptimality,
                saliencyScore: saliencyScore,
                aestheticScore: aestheticScore
            )
            
            rankingScores.append(ranking)
        }
        
        // Sort by combined score and assign ranks
        rankingScores.sort { $0.combinedScore > $1.combinedScore }
        for (index, _) in rankingScores.enumerated() {
            rankingScores[index] = PhotoRankingScore(
                photo: rankingScores[index].photo,
                overallRank: Float(index + 1),
                qualityScore: rankingScores[index].qualityScore,
                clusterRelevance: rankingScores[index].clusterRelevance,
                uniquenessScore: rankingScores[index].uniquenessScore,
                temporalOptimality: rankingScores[index].temporalOptimality,
                saliencyScore: rankingScores[index].saliencyScore,
                aestheticScore: rankingScores[index].aestheticScore
            )
        }
        
        return rankingScores
    }
    
    private func calculateClusterRelevance(photo: Photo, cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> Float {
        guard let photoAnalysis = analysisResults[photo.id],
              let representativeFingerprint = cluster.representativeFingerprint else { return 0.5 }
        
        // Load image to generate fingerprint if needed
        guard let image = try? await photoLibraryService.loadImage(for: photo.assetIdentifier, targetSize: CGSize(width: 256, height: 256)),
              let photoFingerprint = await generateFingerprint(for: image) else { return 0.5 }
        
        // Calculate visual similarity to cluster representative
        let visualSimilarity = calculateSimilarity(photoFingerprint, representativeFingerprint)
        
        // Factor in face count consistency
        let photoFaceCount = photoAnalysis.faces.count
        let clusterFaceCounts: [Int] = cluster.photos.compactMap { analysisResults[$0.id]?.faces.count }
        let avgClusterFaceCount = clusterFaceCounts.isEmpty ? 0 : clusterFaceCounts.reduce(0, +) / clusterFaceCounts.count
        let faceConsistency = 1.0 - min(1.0, abs(Float(photoFaceCount - avgClusterFaceCount)) / 3.0)
        
        // Combine visual similarity and face consistency
        return visualSimilarity * 0.7 + faceConsistency * 0.3
    }
    
    private func calculateUniquenessScore(photo: Photo, cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> Float {
        guard let photoAnalysis = analysisResults[photo.id] else { return 0.5 }
        
        var uniquenessScore: Float = 1.0
        var similarityCount = 0
        
        // Compare against other photos in cluster
        for otherPhoto in cluster.photos where otherPhoto.id != photo.id {
            guard let otherAnalysis = analysisResults[otherPhoto.id] else { continue }
            
            // Load images and calculate similarity
            if let photoImage = try? await photoLibraryService.loadImage(for: photo.assetIdentifier, targetSize: CGSize(width: 256, height: 256)),
               let otherImage = try? await photoLibraryService.loadImage(for: otherPhoto.assetIdentifier, targetSize: CGSize(width: 256, height: 256)),
               let photoFingerprint = await generateFingerprint(for: photoImage),
               let otherFingerprint = await generateFingerprint(for: otherImage) {
                
                let similarity = calculateSimilarity(photoFingerprint, otherFingerprint)
                
                // High similarity reduces uniqueness
                if similarity > 0.8 {
                    uniquenessScore -= 0.3
                    similarityCount += 1
                } else if similarity > 0.6 {
                    uniquenessScore -= 0.1
                }
            }
        }
        
        // Bonus for having unique saliency regions
        if let saliency = photoAnalysis.saliencyAnalysis {
            uniquenessScore += Float(saliency.salientObjects.count) * 0.05
        }
        
        return max(0.0, min(1.0, uniquenessScore))
    }
    
    private func calculateTemporalOptimality(photo: Photo, cluster: PhotoCluster) -> Float {
        guard let timeRange = cluster.timeRange else { return 0.5 }
        
        let totalDuration = timeRange.end.timeIntervalSince(timeRange.start)
        guard totalDuration > 0 else { return 1.0 }
        
        let photoPosition = photo.timestamp.timeIntervalSince(timeRange.start) / totalDuration
        
        // Prefer photos from the middle 60% of the time range (avoid very beginning/end)
        if photoPosition >= 0.2 && photoPosition <= 0.8 {
            return 1.0
        } else if photoPosition >= 0.1 && photoPosition <= 0.9 {
            return 0.7
        } else {
            return 0.4
        }
    }
    
    private func calculateSaliencyScore(analysis: PhotoAnalysisResult) -> Float {
        guard let saliency = analysis.saliencyAnalysis else { return 0.5 }
        
        var score: Float = 0.5
        
        // Bonus for well-distributed salient objects
        let objectCount = saliency.salientObjects.count
        if objectCount >= 1 && objectCount <= 3 {
            score += 0.3 // Optimal number of salient regions
        } else if objectCount > 3 {
            score += 0.1 // Too many regions might be cluttered
        }
        
        // Use composition score from saliency analysis
        score += saliency.compositionScore * 0.2
        
        return min(1.0, score)
    }
    
    private func calculateEnhancedAestheticScore(analysis: PhotoAnalysisResult) -> Float {
        var score: Float = 0.5
        
        // Use Vision Framework aesthetic analysis if available
        if let aesthetics = analysis.aestheticAnalysis {
            // Heavily penalize utility images
            if aesthetics.isUtility {
                return 0.1
            }
            
            // Normalize from -1,1 to 0,1 range
            let normalizedScore = (aesthetics.overallScore + 1.0) / 2.0
            score = normalizedScore * 0.8 + score * 0.2
        }
        
        // Boost for good face quality
        if !analysis.faces.isEmpty {
            let avgFaceQuality = analysis.faces.reduce(0.0) { $0 + $1.faceQuality } / Double(analysis.faces.count)
            score += Float(avgFaceQuality) * 0.2
        }
        
        return min(1.0, score)
    }
    
    // Helper methods
    private func generateFingerprint(for image: UIImage) async -> VNFeaturePrintObservation? {
        return await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: nil)
                return
            }
            
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error = error {
                    print("Feature extraction failed: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let results = request.results as? [VNFeaturePrintObservation],
                      let fingerprint = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: fingerprint)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("Handler perform failed: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func calculateSimilarity(_ print1: VNFeaturePrintObservation, _ print2: VNFeaturePrintObservation) -> Float {
        var distance: Float = 0
        do {
            try print1.computeDistance(&distance, to: print2)
            return max(0, 1.0 - distance)
        } catch {
            print("Distance calculation failed: \(error)")
            return 0
        }
    }
}

// MARK: - PhotoClusteringService Implementation

class PhotoClusteringService: PhotoClusteringServiceProtocol {
    
    private let photoLibraryService: PhotoLibraryServiceProtocol
    private let criteria = ClusteringCriteria()
    private let rankingService: PhotoClusterRankingService
    
    init(photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
        self.rankingService = PhotoClusterRankingService(photoLibraryService: photoLibraryService)
    }
    
    // MARK: - Visual Fingerprinting
    
    func generateFingerprint(for image: UIImage) async -> VNFeaturePrintObservation? {
        return await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: nil)
                return
            }
            
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error = error {
                    print("Feature extraction failed: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let results = request.results as? [VNFeaturePrintObservation],
                      let fingerprint = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: fingerprint)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("Handler perform failed: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Similarity Calculation
    
    func calculateSimilarity(_ print1: VNFeaturePrintObservation, _ print2: VNFeaturePrintObservation) -> Float {
        var distance: Float = 0
        do {
            try print1.computeDistance(&distance, to: print2)
            return max(0, 1.0 - distance) // Convert distance to similarity score
        } catch {
            print("Distance calculation failed: \(error)")
            return 0
        }
    }
    
    // MARK: - Multi-Dimensional Clustering
    
    func clusterPhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws -> [PhotoCluster] {
        print("DEBUG: Starting ENHANCED clustering with ranking of \(photos.count) photos")
        
        // Process in background for better performance
        return await withTaskGroup(of: [PhotoCluster].self) { taskGroup in
            taskGroup.addTask {
                await self.performEnhancedClusteringWithRanking(photos, progressCallback: progressCallback)
            }
            
            var allClusters: [PhotoCluster] = []
            for await clusterBatch in taskGroup {
                allClusters.append(contentsOf: clusterBatch)
            }
            
            return allClusters
        }
    }
    
    private func performEnhancedClusteringWithRanking(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async -> [PhotoCluster] {
        let totalOriginalPhotos = photos.count
        
        // First perform the basic clustering (70% of total progress)
        var clusters = await performSimplifiedClustering(photos, progressCallback: { completed, total in
            let clusteringProgress = Int(Double(completed) * 0.7)
            progressCallback(clusteringProgress, totalOriginalPhotos)
        })
        
        // Generate analysis results for ranking (this would typically be pre-computed)
        print("DEBUG: Generating analysis results for ranking...")
        var analysisResults: [UUID: PhotoAnalysisResult] = [:]
        
        let analysisService = PhotoAnalysisService()
        var analysisCount = 0
        let totalPhotosForAnalysis = clusters.reduce(0) { $0 + $1.photos.count }
        
        for cluster in clusters {
            for photo in cluster.photos {
                if let image = try? await loadImageForClustering(photo: photo) {
                    if let analysis = try? await analysisService.analyzePhoto(photo, image: image) {
                        analysisResults[photo.id] = analysis
                    }
                }
                analysisCount += 1
                // Report remaining 30% of progress for analysis and ranking
                let clusteringComplete = Int(Double(totalOriginalPhotos) * 0.7)
                let analysisProgress = Int(Double(analysisCount) / Double(totalPhotosForAnalysis) * 0.3 * Double(totalOriginalPhotos))
                let totalProgress = clusteringComplete + analysisProgress
                progressCallback(min(totalProgress, totalOriginalPhotos), totalOriginalPhotos)
            }
        }
        
        // Apply ranking and enhanced clustering to each cluster
        print("DEBUG: Applying ranking and sub-clustering...")
        var enhancedClusters: [PhotoCluster] = []
        
        for cluster in clusters {
            // Rank photos within cluster
            let rankedCluster = await rankPhotosInCluster(cluster, analysisResults: analysisResults)
            
            // Create sub-clusters for better organization
            let subClusters = await createSubClusters(for: rankedCluster, analysisResults: analysisResults)
            var finalCluster = rankedCluster
            finalCluster.subClusters = subClusters
            
            enhancedClusters.append(finalCluster)
        }
        
        print("DEBUG: Enhanced clustering complete - \(enhancedClusters.count) clusters with ranking")
        
        // Log enhanced statistics
        for (index, cluster) in enhancedClusters.enumerated() {
            let qualityMetrics = cluster.clusterQualityMetrics
            let bestPhotoScore = cluster.bestPhoto?.overallScore?.overall ?? 0
            print("DEBUG: Cluster \(index + 1): \(cluster.photos.count) photos, best: \(String(format: "%.2f", bestPhotoScore)), diversity: \(String(format: "%.2f", qualityMetrics?.diversityScore ?? 0)), sub-clusters: \(cluster.subClusters.count)")
        }
        
        return enhancedClusters
    }
    
    private func performSimplifiedClustering(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async -> [PhotoCluster] {
        var clusters: [PhotoCluster] = []
        let sortedPhotos = photos.sorted { $0.timestamp < $1.timestamp }
        let totalPhotos = sortedPhotos.count
        
        for (index, photo) in sortedPhotos.enumerated() {
            // Load image for fingerprint generation
            guard let image = try? await loadImageForClustering(photo: photo) else {
                print("Warning: Could not load image for photo \(photo.assetIdentifier)")
                await MainActor.run { progressCallback(index + 1, totalPhotos) }
                continue
            }
            
            // Generate visual fingerprint
            let fingerprint = await generateFingerprint(for: image)
            guard let fingerprint = fingerprint else {
                print("Warning: Could not generate fingerprint for photo \(photo.assetIdentifier)")
                await MainActor.run { progressCallback(index + 1, totalPhotos) }
                continue
            }
            
            // Find matching cluster using simplified criteria
            let matchingCluster = findBestMatchingClusterSimplified(
                for: photo,
                fingerprint: fingerprint,
                in: clusters
            )
            
            if var cluster = matchingCluster {
                // Check cluster size limit before adding
                if cluster.photos.count >= criteria.maxClusterSize {
                    // Create sub-cluster when size limit exceeded
                    var newCluster = PhotoCluster()
                    newCluster.add(photo, fingerprint: fingerprint)
                    clusters.append(newCluster)
                    print("DEBUG: Created sub-cluster due to size limit (\(criteria.maxClusterSize))")
                } else {
                    cluster.add(photo, fingerprint: fingerprint)
                    // Update the cluster in the array
                    if let clusterIndex = clusters.firstIndex(where: { $0.id == cluster.id }) {
                        clusters[clusterIndex] = cluster
                    }
                }
            } else {
                // Create new cluster
                var newCluster = PhotoCluster()
                newCluster.add(photo, fingerprint: fingerprint)
                clusters.append(newCluster)
            }
            
            await MainActor.run { progressCallback(index + 1, totalPhotos) }
        }
        
        print("DEBUG: Created \(clusters.count) SIMPLIFIED clusters from \(totalPhotos) photos")
        
        // Log cluster statistics
        for (index, cluster) in clusters.enumerated() {
            let timeSpan = cluster.timeRange?.end.timeIntervalSince(cluster.timeRange?.start ?? Date()) ?? 0
            print("DEBUG: Cluster \(index + 1): \(cluster.photos.count) photos, \(String(format: "%.1f", timeSpan/60))min span")
        }
        
        return clusters
    }
    
    private func findBestMatchingClusterSimplified(
        for photo: Photo,
        fingerprint: VNFeaturePrintObservation,
        in clusters: [PhotoCluster]
    ) -> PhotoCluster? {
        
        for cluster in clusters {
            guard let representativeFingerprint = cluster.representativeFingerprint else { continue }
            
            // 1. Check visual similarity (≥50% as specified)
            let visualSimilarity = calculateSimilarity(fingerprint, representativeFingerprint)
            let visuallyCompatible = visualSimilarity >= criteria.visualSimilarityThreshold
            
            // 2. Check time proximity (≤30 seconds from most recent photo - rolling window)
            let timeCompatible = isTimeCompatible(photo: photo, cluster: cluster)
            
            // 3. Check location proximity (≤50 meters if location data available)
            let locationCompatible = isLocationCompatible(photo: photo, cluster: cluster)
            
            // 4. Check simple face compatibility (basic face count grouping)
            let faceCompatible = isSimpleFaceCompatible(photo: photo, cluster: cluster)
            
            // Must match ALL criteria to be in same cluster
            let matches = visuallyCompatible && timeCompatible && locationCompatible && faceCompatible
            
            if matches {
                print("DEBUG: Photo matched cluster - Visual: \(String(format: "%.2f", visualSimilarity)), Time: \(timeCompatible), Location: \(locationCompatible), Face: \(faceCompatible)")
                return cluster
            } else {
                var reasons: [String] = []
                if !visuallyCompatible { reasons.append("visual<\(criteria.visualSimilarityThreshold)") }
                if !timeCompatible { reasons.append("time>\(Int(criteria.timeGapThreshold))s") }
                if !locationCompatible { reasons.append("location>\(Int(criteria.locationRadiusMeters))m") }
                if !faceCompatible { reasons.append("face_count") }
                
                let reasonText = reasons.joined(separator: ", ")
                print("DEBUG: Photo split from cluster due to \(reasonText)")
            }
        }
        
        return nil
    }
    
    private func isTimeCompatible(photo: Photo, cluster: PhotoCluster) -> Bool {
        // Rolling window approach: check if photo is within 30 seconds of most recent photo in cluster
        let mostRecentPhoto = cluster.photos.max(by: { $0.timestamp < $1.timestamp })
        let timeGapFromRecent = mostRecentPhoto.map { 
            abs(photo.timestamp.timeIntervalSince($0.timestamp))
        } ?? 0
        
        return timeGapFromRecent <= criteria.timeGapThreshold
    }
    
    private func isLocationCompatible(photo: Photo, cluster: PhotoCluster) -> Bool {
        // If either photo or cluster has no location, they're compatible
        guard let photoLocation = photo.location,
              let clusterLocation = cluster.centerLocation else {
            return true
        }
        
        let distance = photoLocation.distance(from: clusterLocation)
        return distance <= criteria.locationRadiusMeters
    }
    
    private func isSimpleFaceCompatible(photo: Photo, cluster: PhotoCluster) -> Bool {
        // Simple face compatibility: use existing face count data only
        let photoFaceCount = photo.faceQuality?.faceCount ?? 0
        
        // Get face count from cluster representative photo
        guard let representativePhoto = cluster.photos.first else { return true }
        let clusterFaceCount = representativePhoto.faceQuality?.faceCount ?? 0
        
        // Simple rules without complex face recognition:
        // - 0 faces: Compatible with anything
        // - 1+ faces: Group by similar face count ranges
        switch (photoFaceCount, clusterFaceCount) {
        case (0, _), (_, 0):
            return true // No faces - always compatible
        case (1, 1), (2, 2):
            return true // Same small face count
        case (1...2, 3...), (3..., 1...2):
            return false // Don't mix individual/couple photos with group photos
        default:
            return true // Groups with groups are compatible
        }
    }
    
    // MARK: - Similar Photo Detection
    
    func findSimilarPhotos(in clusters: [PhotoCluster], similarity: Float = ClusteringCriteria.sameLocationDifferentFraming) -> [[Photo]] {
        var similarGroups: [[Photo]] = []
        
        // Find clusters with multiple photos that might be similar
        for cluster in clusters {
            if cluster.photos.count > 1 {
                // Group photos within cluster by higher similarity
                let groupedPhotos = groupPhotosBySimilarity(cluster.photos, threshold: similarity)
                similarGroups.append(contentsOf: groupedPhotos)
            }
        }
        
        return similarGroups.filter { $0.count > 1 }
    }
    
    private func groupPhotosBySimilarity(_ photos: [Photo], threshold: Float) -> [[Photo]] {
        // This is a simplified implementation
        // In a full implementation, we'd compare all photos pairwise
        return [photos] // Return all photos as one group for now
    }
    
    // MARK: - Performance Optimizations
    
    // Removed complex face recognition for performance
    // Using simple face count compatibility instead
    
    // MARK: - Helper Methods
    
    private func loadImageForClustering(photo: Photo) async throws -> UIImage? {
        // Load an even smaller version for clustering to improve performance
        return try await photoLibraryService.loadImage(for: photo.assetIdentifier, targetSize: CGSize(width: 256, height: 256))
    }
    
    // MARK: - Enhanced Clustering with Ranking
    
    func rankPhotosInCluster(_ cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> PhotoCluster {
        let rankingScores = await rankingService.rankPhotosInCluster(cluster, analysisResults: analysisResults)
        
        var updatedCluster = cluster
        updatedCluster.rankedPhotos = rankingScores.map { $0.photo }
        updatedCluster.clusterRepresentativePhoto = rankingScores.first?.photo
        
        // Calculate cluster quality metrics
        updatedCluster.clusterQualityMetrics = await calculateClusterQualityMetrics(for: cluster, analysisResults: analysisResults)
        
        return updatedCluster
    }
    
    func createSubClusters(for cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> [PhotoSubCluster] {
        var subClusters: [PhotoSubCluster] = []
        
        // Create near-identical sub-clusters with tight similarity threshold
        let nearIdenticalClusters = await createSubClustersByVisualSimilarity(
            photos: cluster.photos,
            analysisResults: analysisResults,
            threshold: 0.4,
            type: .nearIdentical()
        )
        subClusters.append(contentsOf: nearIdenticalClusters)
        
        // Create pose-based sub-clusters for portrait photos
        let portraitPhotos = cluster.photos.filter { photo in
            guard let analysis = analysisResults[photo.id] else { return false }
            return analysis.faces.count == 1
        }
        
        if portraitPhotos.count >= 2 {
            let poseClusters = await createSubClustersByPose(
                photos: portraitPhotos,
                analysisResults: analysisResults
            )
            subClusters.append(contentsOf: poseClusters)
        }
        
        return subClusters
    }
    
    func calculateClusterQualityMetrics(for cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> ClusterQualityMetrics {
        let diversityScore = await calculateDiversityScore(cluster: cluster, analysisResults: analysisResults)
        let representativenessScore = await calculateRepresentativenessScore(cluster: cluster, analysisResults: analysisResults)
        let temporalCoherence = calculateTemporalCoherence(cluster: cluster)
        let visualCoherence = await calculateVisualCoherence(cluster: cluster, analysisResults: analysisResults)
        let aestheticConsistency = calculateAestheticConsistency(cluster: cluster, analysisResults: analysisResults)
        let saliencyAlignment = await calculateSaliencyAlignment(cluster: cluster, analysisResults: analysisResults)
        
        return ClusterQualityMetrics(
            diversityScore: diversityScore,
            representativenessScore: representativenessScore,
            temporalCoherence: temporalCoherence,
            visualCoherence: visualCoherence,
            aestheticConsistency: aestheticConsistency,
            saliencyAlignment: saliencyAlignment
        )
    }
    
    // MARK: - Sub-clustering Implementation
    
    private func createSubClustersByVisualSimilarity(
        photos: [Photo],
        analysisResults: [UUID: PhotoAnalysisResult],
        threshold: Float,
        type: SubClusterType
    ) async -> [PhotoSubCluster] {
        var subClusters: [PhotoSubCluster] = []
        var processedPhotos: Set<UUID> = []
        
        for photo in photos {
            guard !processedPhotos.contains(photo.id) else { continue }
            
            var subClusterPhotos: [Photo] = [photo]
            processedPhotos.insert(photo.id)
            
            // Find similar photos
            for otherPhoto in photos {
                guard !processedPhotos.contains(otherPhoto.id) else { continue }
                
                if let similarity = await calculatePhotoSimilarity(photo1: photo, photo2: otherPhoto),
                   similarity >= threshold {
                    subClusterPhotos.append(otherPhoto)
                    processedPhotos.insert(otherPhoto.id)
                }
            }
            
            // Only create sub-cluster if it has multiple photos
            if subClusterPhotos.count >= 2 {
                var subCluster = PhotoSubCluster(similarityThreshold: threshold, clusterType: type)
                subCluster.photos = subClusterPhotos
                subClusters.append(subCluster)
            }
        }
        
        return subClusters
    }
    
    private func createSubClustersByPose(
        photos: [Photo],
        analysisResults: [UUID: PhotoAnalysisResult]
    ) async -> [PhotoSubCluster] {
        var subClusters: [PhotoSubCluster] = []
        var processedPhotos: Set<UUID> = []
        
        for photo in photos {
            guard !processedPhotos.contains(photo.id),
                  let analysis = analysisResults[photo.id],
                  let face = analysis.faces.first,
                  let pose = face.pose else { continue }
            
            var subClusterPhotos: [Photo] = [photo]
            processedPhotos.insert(photo.id)
            
            // Find photos with similar poses
            for otherPhoto in photos {
                guard !processedPhotos.contains(otherPhoto.id),
                      let otherAnalysis = analysisResults[otherPhoto.id],
                      let otherFace = otherAnalysis.faces.first,
                      let otherPose = otherFace.pose else { continue }
                
                if arePosesSimilar(pose1: pose, pose2: otherPose) {
                    subClusterPhotos.append(otherPhoto)
                    processedPhotos.insert(otherPhoto.id)
                }
            }
            
            if subClusterPhotos.count >= 2 {
                var subCluster = PhotoSubCluster(similarityThreshold: 0.7, clusterType: .poses())
                subCluster.photos = subClusterPhotos
                subClusters.append(subCluster)
            }
        }
        
        return subClusters
    }
    
    // MARK: - Quality Metrics Calculation
    
    private func calculateDiversityScore(cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> Float {
        guard cluster.photos.count > 1 else { return 0.0 }
        
        var totalSimilarity: Float = 0.0
        var comparisonCount = 0
        
        for i in 0..<cluster.photos.count {
            for j in (i+1)..<cluster.photos.count {
                if let similarity = await calculatePhotoSimilarity(photo1: cluster.photos[i], photo2: cluster.photos[j]) {
                    totalSimilarity += similarity
                    comparisonCount += 1
                }
            }
        }
        
        if comparisonCount == 0 { return 0.5 }
        
        let avgSimilarity = totalSimilarity / Float(comparisonCount)
        // Higher diversity = lower average similarity
        return max(0.0, 1.0 - avgSimilarity)
    }
    
    private func calculateRepresentativenessScore(cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> Float {
        guard let representativeFingerprint = cluster.representativeFingerprint else { return 0.5 }
        
        var totalRepresentativeness: Float = 0.0
        var validPhotos = 0
        
        for photo in cluster.photos {
            if let image = try? await loadImageForClustering(photo: photo),
               let fingerprint = await generateFingerprint(for: image) {
                let similarity = calculateSimilarity(fingerprint, representativeFingerprint)
                totalRepresentativeness += similarity
                validPhotos += 1
            }
        }
        
        return validPhotos > 0 ? totalRepresentativeness / Float(validPhotos) : 0.5
    }
    
    private func calculateTemporalCoherence(cluster: PhotoCluster) -> Float {
        guard let timeRange = cluster.timeRange else { return 0.0 }
        
        let totalDuration = timeRange.end.timeIntervalSince(timeRange.start)
        let photoCount = cluster.photos.count
        
        // Better coherence for shorter duration relative to photo count
        if totalDuration <= 60.0 && photoCount >= 3 {
            return 1.0 // Excellent - burst or rapid sequence
        } else if totalDuration <= 300.0 && photoCount >= 2 {
            return 0.8 // Good - within 5 minutes
        } else if totalDuration <= 3600.0 {
            return 0.6 // Fair - within an hour
        } else {
            return 0.3 // Poor - spread over long time
        }
    }
    
    private func calculateVisualCoherence(cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> Float {
        // Already calculated in representativeness - could be refined separately
        return await calculateRepresentativenessScore(cluster: cluster, analysisResults: analysisResults)
    }
    
    private func calculateAestheticConsistency(cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) -> Float {
        let qualityScores: [Double] = cluster.photos.compactMap { photo in
            analysisResults[photo.id]?.overallScore
        }
        
        guard qualityScores.count > 1 else { return 0.5 }
        
        let avgQuality = qualityScores.reduce(0.0, +) / Double(qualityScores.count)
        let variance = qualityScores.reduce(0.0) { result, score in
            result + pow(score - avgQuality, 2)
        } / Double(qualityScores.count)
        
        let standardDeviation = sqrt(variance)
        
        // Lower standard deviation = higher consistency
        return max(0.0, Float(1.0 - min(1.0, standardDeviation * 2.0)))
    }
    
    private func calculateSaliencyAlignment(cluster: PhotoCluster, analysisResults: [UUID: PhotoAnalysisResult]) async -> Float {
        let photosWithSaliency: [(Photo, SaliencyAnalysis)] = cluster.photos.compactMap { photo in
            guard let analysis = analysisResults[photo.id],
                  let saliency = analysis.saliencyAnalysis else { return nil }
            return (photo, saliency)
        }
        
        guard photosWithSaliency.count >= 2 else { return 0.5 }
        
        var totalAlignment: Float = 0.0
        var comparisonCount = 0
        
        for i in 0..<photosWithSaliency.count {
            for j in (i+1)..<photosWithSaliency.count {
                let alignment = calculateSaliencyRegionAlignment(
                    saliency1: photosWithSaliency[i].1,
                    saliency2: photosWithSaliency[j].1
                )
                totalAlignment += alignment
                comparisonCount += 1
            }
        }
        
        return comparisonCount > 0 ? totalAlignment / Float(comparisonCount) : 0.5
    }
    
    // MARK: - Helper Methods
    
    private func calculatePhotoSimilarity(photo1: Photo, photo2: Photo) async -> Float? {
        guard let image1 = try? await loadImageForClustering(photo: photo1),
              let image2 = try? await loadImageForClustering(photo: photo2),
              let fingerprint1 = await generateFingerprint(for: image1),
              let fingerprint2 = await generateFingerprint(for: image2) else {
            return nil
        }
        
        return calculateSimilarity(fingerprint1, fingerprint2)
    }
    
    private func arePosesSimilar(pose1: FacePose, pose2: FacePose, threshold: Float = 15.0) -> Bool {
        let yawDiff = abs((pose1.yaw ?? 0) - (pose2.yaw ?? 0))
        let pitchDiff = abs((pose1.pitch ?? 0) - (pose2.pitch ?? 0))
        let rollDiff = abs((pose1.roll ?? 0) - (pose2.roll ?? 0))
        
        return yawDiff <= threshold && pitchDiff <= threshold && rollDiff <= threshold
    }
    
    private func calculateSaliencyRegionAlignment(saliency1: SaliencyAnalysis, saliency2: SaliencyAnalysis) -> Float {
        let regions1 = saliency1.salientObjects
        let regions2 = saliency2.salientObjects
        
        guard !regions1.isEmpty && !regions2.isEmpty else { return 0.0 }
        
        var totalOverlap: Float = 0.0
        var maxPossibleOverlap: Float = 0.0
        
        for region1 in regions1 {
            for region2 in regions2 {
                let intersection = region1.intersection(region2)
                let union = region1.union(region2)
                
                if !union.isEmpty {
                    let overlap = Float(intersection.width * intersection.height) / Float(union.width * union.height)
                    totalOverlap += overlap
                }
                maxPossibleOverlap += 1.0
            }
        }
        
        return maxPossibleOverlap > 0 ? totalOverlap / maxPossibleOverlap : 0.0
    }
}

// MARK: - Clustering Statistics

struct ClusteringStatistics {
    let totalPhotos: Int
    let totalClusters: Int
    let averageClusterSize: Double
    let singletonClusters: Int // Clusters with only 1 photo
    let largestClusterSize: Int
    let qualityDistribution: [String: Int]
    
    init(clusters: [PhotoCluster]) {
        totalPhotos = clusters.reduce(0) { $0 + $1.photos.count }
        totalClusters = clusters.count
        averageClusterSize = totalClusters > 0 ? Double(totalPhotos) / Double(totalClusters) : 0
        singletonClusters = clusters.filter { $0.photos.count == 1 }.count
        largestClusterSize = clusters.map { $0.photos.count }.max() ?? 0
        
        // Placeholder quality distribution
        qualityDistribution = [
            "High Quality Clusters": clusters.filter { $0.averageQualityScore > 0.8 }.count,
            "Medium Quality Clusters": clusters.filter { $0.averageQualityScore > 0.6 && $0.averageQualityScore <= 0.8 }.count,
            "Low Quality Clusters": clusters.filter { $0.averageQualityScore <= 0.6 }.count
        ]
    }
}

// MARK: - Extensions

extension PhotoCluster {
    var description: String {
        let timeSpan = timeRange?.start.timeIntervalSince(timeRange?.end ?? Date()) ?? 0
        let locationDesc = centerLocation != nil ? "with location" : "no location"
        return "\(photos.count) photos, \(Int(abs(timeSpan)/60))min span, \(locationDesc)"
    }
    
    var uniqueTimeSpan: TimeInterval {
        guard let timeRange = timeRange else { return 0 }
        return timeRange.end.timeIntervalSince(timeRange.start)
    }
}

extension Array where Element == PhotoCluster {
    var totalPhotos: Int {
        return reduce(0) { $0 + $1.photos.count }
    }
    
    var averageClusterSize: Double {
        guard !isEmpty else { return 0 }
        return Double(totalPhotos) / Double(count)
    }
    
    func clustersWithMinPhotos(_ minCount: Int) -> [PhotoCluster] {
        return filter { $0.photos.count >= minCount }
    }
}