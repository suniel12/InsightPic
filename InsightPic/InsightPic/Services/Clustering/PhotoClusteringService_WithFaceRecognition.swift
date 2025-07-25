import Foundation
import Vision
import UIKit
import CoreLocation

// MARK: - BACKUP: Complex Face Recognition Implementation
// This file contains the complex face recognition clustering implementation
// that was causing performance issues (10x slower) and over-clustering (4 groups instead of 2)
// 
// Issues identified:
// 1. Real-time face detection during clustering process
// 2. Complex facial feature extraction and comparison
// 3. Synchronous processing causing performance bottlenecks
// 4. Over-sensitive face similarity thresholds
//
// Future optimizations to consider:
// - Background/async face feature extraction
// - Cached face embeddings to avoid reprocessing
// - More efficient similarity algorithms
// - Batch processing of face detection
// - Use VNGeneratePersonInstanceMaskRequest for iOS 17+

// MARK: - BACKUP: Complex Face Recognition Implementation
// 
// This backup file contains the complex face recognition implementation
// The actual PhotoCluster and ClusteringCriteria structs are defined in
// the main PhotoClusteringService.swift file to avoid duplicate definitions

// MARK: - BACKUP: Complex Face Recognition Protocol
// 
// The actual PhotoClusteringServiceProtocol is defined in the main file

// MARK: - PhotoClusteringService Implementation WITH COMPLEX FACE RECOGNITION

class PhotoClusteringServiceWithFaceRecognition: PhotoClusteringServiceProtocol {
    
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
    
    // MARK: - Multi-Dimensional Clustering WITH COMPLEX FACE RECOGNITION
    
    func clusterPhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws -> [PhotoCluster] {
        var clusters: [PhotoCluster] = []
        let sortedPhotos = photos.sorted { $0.timestamp < $1.timestamp }
        let totalPhotos = sortedPhotos.count
        
        print("DEBUG: Starting clustering of \(totalPhotos) photos WITH COMPLEX FACE RECOGNITION")
        
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
            
            // Find matching cluster using multi-dimensional criteria WITH FACE RECOGNITION
            let matchingCluster = await findBestMatchingClusterWithFaceRecognition(
                for: photo,
                fingerprint: fingerprint,
                image: image,
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
        
        print("DEBUG: Created \(clusters.count) clusters from \(totalPhotos) photos WITH FACE RECOGNITION")
        
        // Log cluster statistics
        for (index, cluster) in clusters.enumerated() {
            print("DEBUG: Cluster \(index + 1): \(cluster.photos.count) photos, timespan: \(cluster.timeRange?.start.formatted() ?? "N/A") - \(cluster.timeRange?.end.formatted() ?? "N/A")")
        }
        
        return clusters
    }
    
    private func findBestMatchingClusterWithFaceRecognition(
        for photo: Photo,
        fingerprint: VNFeaturePrintObservation,
        image: UIImage,
        in clusters: [PhotoCluster]
    ) async -> PhotoCluster? {
        
        // New inclusive clustering logic: Keep photos together UNLESS significantly different
        for cluster in clusters {
            guard let representativeFingerprint = cluster.representativeFingerprint else { continue }
            
            // Check visual similarity (≥50% similarity to stay in same cluster)
            let visualSimilarity = calculateSimilarity(fingerprint, representativeFingerprint)
            let visuallyTooDifferent = visualSimilarity < 0.5 // Split if <50% similar
            
            // Check time proximity (≤30 seconds from most recent photo - rolling window)
            let mostRecentPhoto = cluster.photos.max(by: { $0.timestamp < $1.timestamp })
            let timeGapFromRecent = mostRecentPhoto.map { 
                abs(photo.timestamp.timeIntervalSince($0.timestamp))
            } ?? 0
            let temporallyTooDistant = timeGapFromRecent > 30.0 // Split if >30 seconds from most recent
            
            // Check face compatibility (COMPLEX FACE RECOGNITION - PERFORMANCE BOTTLENECK)
            let facesIncompatible = !(await areFacesCompatibleComplexRecognition(photo: photo, cluster: cluster, newImage: image))
            
            // Keep in same cluster UNLESS visually too different OR temporally too distant OR faces incompatible
            let shouldSplit = visuallyTooDifferent || temporallyTooDistant || facesIncompatible
            let matches = !shouldSplit
            
            if matches {
                print("DEBUG: Photo matched cluster - Visual: \(String(format: "%.2f", visualSimilarity)), Time gap: \(String(format: "%.1f", timeGapFromRecent))s, Faces compatible: true")
                return cluster
            } else {
                var reasons: [String] = []
                if visuallyTooDifferent { reasons.append("visual difference") }
                if temporallyTooDistant { reasons.append("time gap") }
                if facesIncompatible { reasons.append("face incompatibility") }
                
                let reasonText = reasons.joined(separator: ", ")
                print("DEBUG: Photo split from cluster due to \(reasonText) - Visual: \(String(format: "%.2f", visualSimilarity)), Time gap: \(String(format: "%.1f", timeGapFromRecent))s, Faces compatible: \(!facesIncompatible)")
            }
        }
        
        return nil
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
    
    // MARK: - COMPLEX FACE RECOGNITION IMPLEMENTATION (PERFORMANCE BOTTLENECK)
    
    private func areFacesCompatibleComplexRecognition(photo: Photo, cluster: PhotoCluster, newImage: UIImage) async -> Bool {
        // PERFORMANCE ISSUE: Real-time face feature extraction during clustering
        let newFaceFeatures = await extractFaceFeatures(from: newImage)
        
        // Get representative photo from cluster and extract its face features
        guard let representativePhoto = cluster.photos.first else { return true }
        
        // PERFORMANCE ISSUE: Loading and processing cluster representative image
        guard let clusterImage = try? await loadImageForClustering(photo: representativePhoto) else {
            print("DEBUG: Could not load cluster representative image, allowing clustering")
            return true
        }
        
        // PERFORMANCE ISSUE: Real-time face feature extraction for comparison
        let clusterFaceFeatures = await extractFaceFeatures(from: clusterImage)
        
        print("DEBUG: Face compatibility - New photo faces: \(newFaceFeatures.count), Cluster faces: \(clusterFaceFeatures.count)")
        
        // Face compatibility rules based on actual face recognition:
        // - 0 faces in either: Always compatible (landscapes, objects, etc.)
        // - 1-2 faces: Must contain same people (based on feature similarity)
        // - 3+ faces: Always compatible (group photos, crowds - too complex for precise matching)
        
        switch (newFaceFeatures.count, clusterFaceFeatures.count) {
        case (0, _), (_, 0):
            // At least one photo has no faces - always compatible
            print("DEBUG: One or both photos have no faces - compatible")
            return true
            
        case (1...2, 1...2):
            // Both have 1-2 faces - check if they're the same people
            // PERFORMANCE ISSUE: Complex facial similarity comparison
            let compatible = await areSamePeopleComplexRecognition(newFaces: newFaceFeatures, clusterFaces: clusterFaceFeatures)
            print("DEBUG: Face recognition result: \(compatible ? "same people" : "different people")")
            return compatible
            
        case (let new, let cluster) where new >= 3 || cluster >= 3:
            // Group photos (3+ faces) are always compatible - too complex for precise matching
            print("DEBUG: Group photos (3+ faces) - compatible")
            return true
            
        default:
            return true
        }
    }
    
    private func extractFaceFeatures(from image: UIImage) async -> [VNFeaturePrintObservation] {
        return await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: [])
                return
            }
            
            // PERFORMANCE ISSUE: Synchronous face detection during clustering
            let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    print("Face detection failed: \(error)")
                    continuation.resume(returning: [])
                    return
                }
                
                guard let faceObservations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                print("DEBUG: Detected \(faceObservations.count) faces, extracting features...")
                
                // PERFORMANCE ISSUE: Sequential face feature extraction
                Task {
                    var faceFeatures: [VNFeaturePrintObservation] = []
                    
                    for faceObservation in faceObservations {
                        if let faceFeature = await self.generateFaceFeaturePrint(from: cgImage, faceRegion: faceObservation.boundingBox) {
                            faceFeatures.append(faceFeature)
                        }
                    }
                    
                    continuation.resume(returning: faceFeatures)
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([faceDetectionRequest])
            } catch {
                print("Face detection handler failed: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    private func generateFaceFeaturePrint(from cgImage: CGImage, faceRegion: CGRect) async -> VNFeaturePrintObservation? {
        return await withCheckedContinuation { continuation in
            // Convert normalized face region to pixel coordinates
            let imageWidth = CGFloat(cgImage.width)
            let imageHeight = CGFloat(cgImage.height)
            
            // Vision framework uses bottom-left origin, so flip Y coordinate
            let faceRect = CGRect(
                x: faceRegion.minX * imageWidth,
                y: (1.0 - faceRegion.maxY) * imageHeight,
                width: faceRegion.width * imageWidth,
                height: faceRegion.height * imageHeight
            )
            
            // PERFORMANCE ISSUE: Image cropping for each face
            guard let faceCGImage = cgImage.cropping(to: faceRect) else {
                continuation.resume(returning: nil)
                return
            }
            
            // PERFORMANCE ISSUE: Feature print generation for each face
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error = error {
                    print("Face feature extraction failed: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let results = request.results as? [VNFeaturePrintObservation],
                      let faceFeature = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: faceFeature)
            }
            
            let handler = VNImageRequestHandler(cgImage: faceCGImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("Face feature extraction handler failed: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func areSamePeopleComplexRecognition(newFaces: [VNFeaturePrintObservation], clusterFaces: [VNFeaturePrintObservation]) async -> Bool {
        // ISSUE: Over-sensitive face count comparison
        guard newFaces.count == clusterFaces.count else {
            print("DEBUG: Different number of faces (\(newFaces.count) vs \(clusterFaces.count)) - different people")
            return false
        }
        
        // For 1 face: compare directly
        if newFaces.count == 1, clusterFaces.count == 1 {
            let similarity = calculateSimilarity(newFaces[0], clusterFaces[0])
            let threshold: Float = 0.75 // ISSUE: Possibly too high threshold
            let isSamePerson = similarity >= threshold
            print("DEBUG: Single face similarity: \(String(format: "%.3f", similarity)), threshold: \(threshold), same person: \(isSamePerson)")
            return isSamePerson
        }
        
        // For 2 faces: find best matching pairs
        if newFaces.count == 2, clusterFaces.count == 2 {
            // PERFORMANCE ISSUE: Complex pairwise comparison
            let similarity1 = calculateSimilarity(newFaces[0], clusterFaces[0]) + calculateSimilarity(newFaces[1], clusterFaces[1])
            let similarity2 = calculateSimilarity(newFaces[0], clusterFaces[1]) + calculateSimilarity(newFaces[1], clusterFaces[0])
            
            let bestSimilarity = max(similarity1, similarity2) / 2.0 // Average similarity
            let threshold: Float = 0.70 // ISSUE: Possibly too high threshold
            let areSamePeople = bestSimilarity >= threshold
            print("DEBUG: Two faces best similarity: \(String(format: "%.3f", bestSimilarity)), threshold: \(threshold), same people: \(areSamePeople)")
            return areSamePeople
        }
        
        // Fallback for edge cases
        return true
    }
    
    // MARK: - Helper Methods
    
    private func loadImageForClustering(photo: Photo) async throws -> UIImage? {
        // Load a smaller version for clustering to improve performance
        return try await photoLibraryService.loadImage(for: photo.assetIdentifier, targetSize: CGSize(width: 512, height: 512))
    }
}

// MARK: - BACKUP: Clustering Statistics and Extensions
// 
// The actual ClusteringStatistics struct and PhotoCluster extensions 
// are defined in the main PhotoClusteringService.swift file