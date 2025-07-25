import Foundation
import UIKit

// MARK: - Photo Categorization Service Protocol

protocol PhotoCategorizationServiceProtocol {
    func categorizePhoto(from result: PhotoAnalysisResult, photo: Photo) -> [PhotoType]
    func getPrimaryCategory(from result: PhotoAnalysisResult, photo: Photo) -> PhotoType
    func categorizePhotos(_ results: [PhotoAnalysisResult], photos: [Photo]) -> [UUID: [PhotoType]]
    func groupPhotosByCategory(_ photos: [Photo]) -> [PhotoType: [Photo]]
}

// MARK: - Photo Categorization Service Implementation

class PhotoCategorizationService: PhotoCategorizationServiceProtocol {
    
    func categorizePhoto(from result: PhotoAnalysisResult, photo: Photo) -> [PhotoType] {
        var categories: [PhotoType] = []
        
        // Face-based categorization
        let faceCount = result.faces.count
        if faceCount == 1 {
            categories.append(.portrait)
        } else if faceCount > 1 {
            categories.append(.groupPhoto)
            if faceCount > 6 {
                categories.append(.event)
            }
        }
        
        // Utility detection (screenshots, documents)
        if result.aestheticAnalysis?.isUtility == true {
            categories.append(.utility)
            return categories // Utility images rarely have other meaningful categories
        }
        
        // Scene and environment categorization
        categories.append(contentsOf: categorizeByScene(result: result, photo: photo))
        
        // Lighting and time-based categorization
        categories.append(contentsOf: categorizeByLighting(result: result, photo: photo))
        
        // Technical categorization
        categories.append(contentsOf: categorizeByTechnicalAspects(result: result, photo: photo))
        
        return Array(Set(categories)) // Remove duplicates
    }
    
    func getPrimaryCategory(from result: PhotoAnalysisResult, photo: Photo) -> PhotoType {
        let categories = categorizePhoto(from: result, photo: photo)
        
        // Priority order for primary category
        let priorityOrder: [PhotoType] = [
            .utility,       // Highest priority - utility images are clear cut
            .portrait,      // Single person photos
            .groupPhoto,    // Group photos
            .event,         // Special events
            .goldenHour,    // Beautiful lighting
            .landscape,     // Scenic photos
            .closeUp,       // Detail shots
            .action,        // Movement/activity
            .lowLight,      // Technical challenge
            .outdoor,       // Environment
            .indoor         // Default environment
        ]
        
        // Return first category found in priority order
        for priorityType in priorityOrder {
            if categories.contains(priorityType) {
                return priorityType
            }
        }
        
        // Fallback to legacy detection
        return PhotoType.detect(from: photo)
    }
    
    func categorizePhotos(_ results: [PhotoAnalysisResult], photos: [Photo]) -> [UUID: [PhotoType]] {
        var categorization: [UUID: [PhotoType]] = [:]
        
        // Create lookup dictionary for photos
        let photoLookup = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        
        for result in results {
            if let photo = photoLookup[result.photoId] {
                categorization[result.photoId] = categorizePhoto(from: result, photo: photo)
            }
        }
        
        return categorization
    }
    
    func groupPhotosByCategory(_ photos: [Photo]) -> [PhotoType: [Photo]] {
        var grouped: [PhotoType: [Photo]] = [:]
        
        for photo in photos {
            let primaryCategory = PhotoType.detect(from: photo) // Use enhanced detection if available
            
            if grouped[primaryCategory] == nil {
                grouped[primaryCategory] = []
            }
            grouped[primaryCategory]?.append(photo)
        }
        
        return grouped
    }
    
    // MARK: - Private Categorization Methods
    
    private func categorizeByScene(result: PhotoAnalysisResult, photo: Photo) -> [PhotoType] {
        var categories: [PhotoType] = []
        
        // Analyze objects for scene understanding
        let landscapeKeywords = ["mountain", "tree", "sky", "water", "landscape", "nature", "outdoor", "scenery", "field", "forest", "beach", "sunset", "sunrise", "cloud", "horizon", "valley", "hill"]
        let indoorKeywords = ["room", "indoor", "furniture", "wall", "ceiling", "floor", "kitchen", "bedroom", "living room", "office", "restaurant", "building interior"]
        let actionKeywords = ["sport", "running", "jumping", "dancing", "playing", "movement", "activity", "exercise", "game"]
        let closeUpKeywords = ["food", "flower", "detail", "macro", "close", "texture", "pattern"]
        
        let objectIdentifiers = result.objects.map { $0.identifier.lowercased() }
        
        // Landscape detection
        if objectIdentifiers.contains(where: { identifier in
            landscapeKeywords.contains { identifier.contains($0) }
        }) {
            categories.append(.landscape)
            categories.append(.outdoor)
        }
        
        // Indoor detection
        if objectIdentifiers.contains(where: { identifier in
            indoorKeywords.contains { identifier.contains($0) }
        }) {
            categories.append(.indoor)
        }
        
        // Action detection
        if objectIdentifiers.contains(where: { identifier in
            actionKeywords.contains { identifier.contains($0) }
        }) {
            categories.append(.action)
        }
        
        // Close-up detection
        if objectIdentifiers.contains(where: { identifier in
            closeUpKeywords.contains { identifier.contains($0) }
        }) {
            categories.append(.closeUp)
        }
        
        // Saliency-based scene analysis
        if let saliency = result.saliencyAnalysis {
            // Many focal points might indicate a busy scene (event)
            if saliency.focusPoints.count > 5 {
                categories.append(.event)
            }
            
            // Single strong focal point might be a close-up or portrait
            if saliency.focusPoints.count == 1 && saliency.compositionScore > 0.8 {
                if result.faces.count == 1 {
                    categories.append(.portrait)
                } else if result.faces.isEmpty {
                    categories.append(.closeUp)
                }
            }
        }
        
        return categories
    }
    
    private func categorizeByLighting(result: PhotoAnalysisResult, photo: Photo) -> [PhotoType] {
        var categories: [PhotoType] = []
        
        // Golden hour detection
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: photo.timestamp)
        if (hour >= 6 && hour <= 8) || (hour >= 17 && hour <= 19) {
            // Confirm with high aesthetic score for golden hour
            if result.aestheticAnalysis?.overallScore ?? -1.0 > 0.4 {
                categories.append(.goldenHour)
            }
        }
        
        // Low light detection based on exposure analysis
        if result.exposureScore < 0.4 {
            let nightHours = hour < 6 || hour > 20
            if nightHours {
                categories.append(.lowLight)
            }
        }
        
        return categories
    }
    
    private func categorizeByTechnicalAspects(result: PhotoAnalysisResult, photo: Photo) -> [PhotoType] {
        var categories: [PhotoType] = []
        
        // Action photos often have lower sharpness due to motion
        if result.sharpnessScore < 0.6 && result.exposureScore > 0.6 {
            // Good exposure but lower sharpness might indicate action
            categories.append(.action)
        }
        
        // Event photos often have multiple people and good lighting
        if result.faces.count >= 3 && result.exposureScore > 0.7 {
            categories.append(.event)
        }
        
        // Portrait photos with very high face quality
        if result.faces.count == 1 {
            let avgFaceQuality = result.faces.first?.faceQuality ?? 0.0
            if avgFaceQuality > 0.8 {
                categories.append(.portrait)
            }
        }
        
        return categories
    }
}

// MARK: - Enhanced Photo Extension

extension Photo {
    /// Uses enhanced categorization if analysis data is available
    var enhancedPhotoType: PhotoType {
        // If we have rich analysis data, we could use it here
        // For now, fall back to basic detection
        return PhotoType.detect(from: self)
    }
    
    /// Get all applicable categories for this photo
    var photoCategories: [PhotoType] {
        // This would need analysis result data to work properly
        // For now, return primary category
        return [enhancedPhotoType]
    }
}