import Foundation
import UIKit

// MARK: - Photo Filter Service Protocol

protocol PhotoFilterServiceProtocol {
    func filterPhotos(_ photos: [Photo], analysisResults: [PhotoAnalysisResult], selectedCategories: Set<PhotoCategory>) -> [FilteredPhoto]
    func calculateRelevanceScore(for photo: Photo, analysisResult: PhotoAnalysisResult, selectedCategories: Set<PhotoCategory>) -> Float
    func getAvailableCategories(from analysisResults: [PhotoAnalysisResult]) -> [PhotoCategory: Int]
    func mapVisionLabelsToCategories(_ objects: [ObjectAnalysis]) -> Set<PhotoCategory>
}

// MARK: - Photo Category Enum

enum PhotoCategory: String, CaseIterable, Hashable {
    case people = "People"
    case groups = "Groups" 
    case landscapes = "Landscapes"
    case food = "Food"
    case cars = "Cars"
    case animals = "Animals"
    case events = "Events"
    case closeUps = "Close-ups"
    case sports = "Sports"
    case travel = "Travel"
    case nature = "Nature"
    case indoor = "Indoor"
    case outdoor = "Outdoor"
    
    var icon: String {
        switch self {
        case .people: return "person.fill"
        case .groups: return "person.3.fill"
        case .landscapes: return "mountain.2.fill"
        case .food: return "fork.knife"
        case .cars: return "car.fill"
        case .animals: return "pawprint.fill"
        case .events: return "party.popper.fill"
        case .closeUps: return "camera.macro"
        case .sports: return "figure.run"
        case .travel: return "airplane"
        case .nature: return "leaf.fill"
        case .indoor: return "house.fill"
        case .outdoor: return "sun.max.fill"
        }
    }
    
    var color: String {
        switch self {
        case .people: return "blue"
        case .groups: return "purple"
        case .landscapes: return "green"
        case .food: return "orange"
        case .cars: return "red"
        case .animals: return "brown"
        case .events: return "pink"
        case .closeUps: return "indigo"
        case .sports: return "cyan"
        case .travel: return "teal"
        case .nature: return "mint"
        case .indoor: return "gray"
        case .outdoor: return "yellow"
        }
    }
}

// MARK: - Filtered Photo Model

struct FilteredPhoto {
    let photo: Photo
    let analysisResult: PhotoAnalysisResult
    let relevanceScore: Float
    let matchingCategories: Set<PhotoCategory>
    let qualityScore: Float
    
    var overallScore: Float {
        return relevanceScore
    }
}

// MARK: - Photo Filter Service Implementation

class PhotoFilterService: PhotoFilterServiceProtocol, ObservableObject {
    
    // Vision Framework label to category mappings
    private let categoryMappings: [PhotoCategory: Set<String>] = [
        .people: Set([
            "person", "human", "face", "portrait", "man", "woman", "child", "baby", 
            "boy", "girl", "adult", "people", "human face", "selfie"
        ]),
        
        .groups: Set([
            "group", "crowd", "team", "family", "friends", "gathering", "party",
            "wedding", "graduation", "meeting", "audience", "people"
        ]),
        
        .landscapes: Set([
            "landscape", "mountain", "hill", "valley", "horizon", "scenery", "vista",
            "countryside", "field", "meadow", "desert", "canyon", "cliff", "rock formation"
        ]),
        
        .food: Set([
            "food", "meal", "dish", "plate", "bowl", "pizza", "burger", "sandwich",
            "salad", "soup", "pasta", "bread", "cake", "dessert", "fruit", "vegetable",
            "coffee", "tea", "drink", "beverage", "wine", "beer", "restaurant", "dining"
        ]),
        
        .cars: Set([
            "car", "automobile", "vehicle", "truck", "van", "suv", "sedan", "coupe",
            "motorcycle", "bike", "bicycle", "bus", "taxi", "limousine", "sports car",
            "racing car", "vintage car", "electric car"
        ]),
        
        .animals: Set([
            "animal", "dog", "cat", "pet", "bird", "horse", "cow", "sheep", "pig",
            "wildlife", "wild animal", "zoo", "farm animal", "domestic animal",
            "mammal", "fish", "insect", "butterfly", "bear", "elephant", "lion"
        ]),
        
        .events: Set([
            "party", "celebration", "birthday", "wedding", "graduation", "concert",
            "festival", "ceremony", "holiday", "christmas", "halloween", "thanksgiving",
            "new year", "anniversary", "dance", "music", "performance", "stage"
        ]),
        
        .closeUps: Set([
            "close-up", "macro", "detail", "texture", "pattern", "abstract",
            "jewelry", "watch", "ring", "necklace", "flower detail", "eye",
            "hand", "fingers", "fabric", "material", "surface"
        ]),
        
        .sports: Set([
            "sport", "sports", "game", "playing", "ball", "football", "basketball",
            "soccer", "tennis", "golf", "baseball", "swimming", "running", "cycling",
            "skiing", "surfing", "climbing", "workout", "exercise", "gym", "athlete"
        ]),
        
        .travel: Set([
            "travel", "vacation", "trip", "tourism", "landmark", "monument", "museum",
            "hotel", "airport", "airplane", "train", "station", "bridge", "architecture",
            "building", "city", "urban", "street", "road", "map", "luggage", "suitcase"
        ]),
        
        .nature: Set([
            "nature", "tree", "forest", "woods", "plant", "flower", "grass", "leaf",
            "branch", "garden", "park", "lake", "river", "ocean", "beach", "water",
            "sky", "cloud", "sunset", "sunrise", "weather", "season", "outdoor"
        ]),
        
        .indoor: Set([
            "indoor", "interior", "room", "home", "house", "office", "kitchen",
            "bedroom", "living room", "bathroom", "furniture", "table", "chair",
            "sofa", "bed", "lamp", "window", "door", "wall", "ceiling", "floor"
        ]),
        
        .outdoor: Set([
            "outdoor", "outside", "exterior", "yard", "garden", "patio", "deck",
            "balcony", "street", "sidewalk", "park", "playground", "field", "beach",
            "mountain", "hiking", "camping", "picnic", "barbecue", "sky", "sun"
        ])
    ]
    
    func filterPhotos(_ photos: [Photo], analysisResults: [PhotoAnalysisResult], selectedCategories: Set<PhotoCategory>) -> [FilteredPhoto] {
        // Create lookup dictionary for analysis results
        let analysisLookup = Dictionary(uniqueKeysWithValues: analysisResults.map { ($0.photoId, $0) })
        
        var filteredPhotos: [FilteredPhoto] = []
        
        for photo in photos {
            guard let analysisResult = analysisLookup[photo.id] else { continue }
            
            // Skip screenshots/utility images
            if analysisResult.aestheticAnalysis?.isUtility == true {
                continue
            }
            
            let relevanceScore = calculateRelevanceScore(
                for: photo,
                analysisResult: analysisResult,
                selectedCategories: selectedCategories
            )
            
            let matchingCategories = mapVisionLabelsToCategories(analysisResult.objects)
            let qualityScore = Float(analysisResult.overallScore)
            
            let filteredPhoto = FilteredPhoto(
                photo: photo,
                analysisResult: analysisResult,
                relevanceScore: relevanceScore,
                matchingCategories: matchingCategories,
                qualityScore: qualityScore
            )
            
            filteredPhotos.append(filteredPhoto)
        }
        
        // Sort by relevance score (highest first)
        return filteredPhotos.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    func calculateRelevanceScore(for photo: Photo, analysisResult: PhotoAnalysisResult, selectedCategories: Set<PhotoCategory>) -> Float {
        // If no categories selected, use quality-based scoring
        if selectedCategories.isEmpty {
            return Float(analysisResult.overallScore)
        }
        
        // Map photo's objects to categories
        let photoCategories = mapVisionLabelsToCategories(analysisResult.objects)
        
        // Add face-based categories
        var enhancedPhotoCategories = photoCategories
        let faceCount = analysisResult.faces.count
        if faceCount == 1 {
            enhancedPhotoCategories.insert(.people)
        } else if faceCount > 1 {
            enhancedPhotoCategories.insert(.groups)
            if faceCount > 5 {
                enhancedPhotoCategories.insert(.events)
            }
        }
        
        // Calculate category relevance (80% weight for category match)
        let categoryScore = calculateCategoryRelevance(
            photoCategories: enhancedPhotoCategories,
            selectedCategories: selectedCategories,
            analysisResult: analysisResult
        )
        
        // Quality score (20% weight)
        let qualityScore = Float(analysisResult.overallScore)
        
        // Combined relevance score
        let relevanceScore = categoryScore * 0.8 + qualityScore * 0.2
        
        return min(1.0, relevanceScore)
    }
    
    func getAvailableCategories(from analysisResults: [PhotoAnalysisResult]) -> [PhotoCategory: Int] {
        var categoryCounts: [PhotoCategory: Int] = [:]
        
        for result in analysisResults {
            // Skip utility images
            if result.aestheticAnalysis?.isUtility == true { continue }
            
            let categories = mapVisionLabelsToCategories(result.objects)
            var enhancedCategories = categories
            
            // Add face-based categories
            let faceCount = result.faces.count
            if faceCount == 1 {
                enhancedCategories.insert(.people)
            } else if faceCount > 1 {
                enhancedCategories.insert(.groups)
                if faceCount > 5 {
                    enhancedCategories.insert(.events)
                }
            }
            
            // Count occurrences
            for category in enhancedCategories {
                categoryCounts[category, default: 0] += 1
            }
        }
        
        return categoryCounts
    }
    
    func mapVisionLabelsToCategories(_ objects: [ObjectAnalysis]) -> Set<PhotoCategory> {
        var matchedCategories: Set<PhotoCategory> = []
        
        for object in objects {
            let objectLabel = object.identifier.lowercased()
            
            // Check each category's mappings
            for (category, keywords) in categoryMappings {
                if keywords.contains(where: { keyword in
                    objectLabel.contains(keyword) || keyword.contains(objectLabel)
                }) {
                    matchedCategories.insert(category)
                }
            }
        }
        
        return matchedCategories
    }
    
    // MARK: - Private Helper Methods
    
    private func calculateCategoryRelevance(
        photoCategories: Set<PhotoCategory>,
        selectedCategories: Set<PhotoCategory>,
        analysisResult: PhotoAnalysisResult
    ) -> Float {
        // No category matches
        let matchingCategories = photoCategories.intersection(selectedCategories)
        if matchingCategories.isEmpty {
            return 0.1 // Very low score for non-matching photos
        }
        
        // Base score for category match
        var categoryScore: Float = 0.7
        
        // Bonus for multiple category matches
        let matchCount = matchingCategories.count
        if matchCount > 1 {
            categoryScore += min(0.2, Float(matchCount - 1) * 0.1) // Up to 20% bonus
        }
        
        // Confidence-based weighting
        let objectConfidence = analysisResult.objects.reduce(0.0) { partialResult, object in
            let objectLabel = object.identifier.lowercased()
            let isRelevant = categoryMappings.values.contains { keywords in
                keywords.contains(where: { keyword in
                    objectLabel.contains(keyword) || keyword.contains(objectLabel)
                })
            }
            return isRelevant ? partialResult + Double(object.confidence) : partialResult
        }
        
        let avgConfidence = Float(objectConfidence / Double(max(1, analysisResult.objects.count)))
        categoryScore += avgConfidence * 0.1 // Up to 10% confidence bonus
        
        return min(1.0, categoryScore)
    }
}