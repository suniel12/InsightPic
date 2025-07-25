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
    let visualSimilarity: Float = 0.75
    let timeWindowSeconds: TimeInterval = 600  // 10 minutes
    let locationRadiusMeters: Double = 50
    let maxClusterSize: Int = 20
    let minSimilarityThreshold: Float = 0.50
    
    // Similarity level definitions based on vision.md
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
        var clusters: [PhotoCluster] = []
        let sortedPhotos = photos.sorted { $0.timestamp < $1.timestamp }
        let totalPhotos = sortedPhotos.count
        
        print("DEBUG: Starting clustering of \(totalPhotos) photos")
        
        for (index, photo) in sortedPhotos.enumerated() {
            // Load image for fingerprint generation
            guard let image = try await loadImageForClustering(photo: photo) else {
                print("Warning: Could not load image for photo \(photo.assetIdentifier)")
                progressCallback(index + 1, totalPhotos)
                continue
            }
            
            // Generate visual fingerprint
            let fingerprint = await generateFingerprint(for: image)
            guard let fingerprint = fingerprint else {
                print("Warning: Could not generate fingerprint for photo \(photo.assetIdentifier)")
                progressCallback(index + 1, totalPhotos)
                continue
            }
            
            // Find matching cluster using multi-dimensional criteria
            let matchingCluster = findBestMatchingCluster(
                for: photo,
                fingerprint: fingerprint,
                in: clusters
            )
            
            if var cluster = matchingCluster {
                cluster.add(photo, fingerprint: fingerprint)
                // Update the cluster in the array
                if let clusterIndex = clusters.firstIndex(where: { $0.id == cluster.id }) {
                    clusters[clusterIndex] = cluster
                }
            } else {
                // Create new cluster
                var newCluster = PhotoCluster()
                newCluster.add(photo, fingerprint: fingerprint)
                clusters.append(newCluster)
            }
            
            progressCallback(index + 1, totalPhotos)
        }
        
        print("DEBUG: Created \(clusters.count) clusters from \(totalPhotos) photos")
        
        // Log cluster statistics
        for (index, cluster) in clusters.enumerated() {
            print("DEBUG: Cluster \(index + 1): \(cluster.photos.count) photos, timespan: \(cluster.timeRange?.start.formatted() ?? "N/A") - \(cluster.timeRange?.end.formatted() ?? "N/A")")
        }
        
        return clusters
    }
    
    private func findBestMatchingCluster(
        for photo: Photo,
        fingerprint: VNFeaturePrintObservation,
        in clusters: [PhotoCluster]
    ) -> PhotoCluster? {
        
        // Enhanced clustering logic: BOTH similarity AND time must match for burst detection
        return clusters.first { cluster in
            guard let representativeFingerprint = cluster.representativeFingerprint else { return false }
            
            // Check visual similarity (must be ≥80%)
            let visualSimilarity = calculateSimilarity(fingerprint, representativeFingerprint)
            let visualMatch = visualSimilarity >= 0.8 // 80% similarity threshold
            
            // Check time proximity (must be ≤5 seconds from any photo in cluster)
            let timeMatch = cluster.photos.contains { clusterPhoto in
                let timeDifference = abs(photo.timestamp.timeIntervalSince(clusterPhoto.timestamp))
                return timeDifference <= 5.0 // 5-second window for burst detection
            }
            
            // BOTH criteria must be met for burst photography clustering
            let matches = visualMatch && timeMatch
            
            if matches {
                print("DEBUG: Photo matched cluster - Visual: \(String(format: "%.2f", visualSimilarity)), Burst detection successful")
            }
            
            return matches
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
    
    // MARK: - Helper Methods
    
    private func loadImageForClustering(photo: Photo) async throws -> UIImage? {
        // Load a smaller version for clustering to improve performance
        return try await photoLibraryService.loadImage(for: photo.assetIdentifier, targetSize: CGSize(width: 512, height: 512))
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