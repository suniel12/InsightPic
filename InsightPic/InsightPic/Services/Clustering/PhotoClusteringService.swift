import Foundation
import Vision
import UIKit
import CoreLocation

// MARK: - Clustering Models

struct PhotoCluster: Identifiable, Hashable {
    let id = UUID()
    var photos: [Photo] = []
    var representativeFingerprint: VNFeaturePrintObservation?
    var centerLocation: CLLocation?
    var timeRange: (start: Date, end: Date)?
    
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
        // This will be updated when we integrate with analysis results
        return 0.7 // Placeholder
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
}

// MARK: - PhotoClusteringService Implementation

class PhotoClusteringService: PhotoClusteringServiceProtocol {
    
    private let photoLibraryService: PhotoLibraryServiceProtocol
    private let criteria = ClusteringCriteria()
    
    init(photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
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
        print("DEBUG: Starting SIMPLIFIED clustering of \(photos.count) photos")
        
        // Process in background for better performance
        return await withTaskGroup(of: [PhotoCluster].self) { taskGroup in
            taskGroup.addTask {
                await self.performSimplifiedClustering(photos, progressCallback: progressCallback)
            }
            
            var allClusters: [PhotoCluster] = []
            for await clusterBatch in taskGroup {
                allClusters.append(contentsOf: clusterBatch)
            }
            
            return allClusters
        }
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