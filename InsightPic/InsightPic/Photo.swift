import Foundation
import CoreLocation

// MARK: - Core Models

struct Photo: Identifiable, Codable {
    let id: UUID
    let assetIdentifier: String
    let timestamp: Date
    let location: CLLocation?
    let metadata: PhotoMetadata
    
    // Analysis results (populated during processing)
    var fingerprint: Data?
    var technicalQuality: TechnicalQualityScore?
    var faceQuality: FaceQualityScore?
    var overallScore: PhotoScore?
    var clusterId: UUID?
    
    // MARK: - Computed Properties
    
    /// Detects if this photo is likely a screenshot based on metadata
    var isLikelyScreenshot: Bool {
        return ScreenshotDetector.isScreenshot(self)
    }
    
    init(id: UUID = UUID(),
         assetIdentifier: String,
         timestamp: Date,
         location: CLLocation? = nil,
         metadata: PhotoMetadata,
         fingerprint: Data? = nil,
         technicalQuality: TechnicalQualityScore? = nil,
         faceQuality: FaceQualityScore? = nil,
         overallScore: PhotoScore? = nil,
         clusterId: UUID? = nil) {
        self.id = id
        self.assetIdentifier = assetIdentifier
        self.timestamp = timestamp
        self.location = location
        self.metadata = metadata
        self.fingerprint = fingerprint
        self.technicalQuality = technicalQuality
        self.faceQuality = faceQuality
        self.overallScore = overallScore
        self.clusterId = clusterId
    }
    
    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case id, assetIdentifier, timestamp, metadata
        case fingerprint, technicalQuality, faceQuality, overallScore, clusterId
        case latitude, longitude
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        assetIdentifier = try container.decode(String.self, forKey: .assetIdentifier)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        metadata = try container.decode(PhotoMetadata.self, forKey: .metadata)
        fingerprint = try container.decodeIfPresent(Data.self, forKey: .fingerprint)
        technicalQuality = try container.decodeIfPresent(TechnicalQualityScore.self, forKey: .technicalQuality)
        faceQuality = try container.decodeIfPresent(FaceQualityScore.self, forKey: .faceQuality)
        overallScore = try container.decodeIfPresent(PhotoScore.self, forKey: .overallScore)
        clusterId = try container.decodeIfPresent(UUID.self, forKey: .clusterId)
        
        // Handle location
        if let latitude = try container.decodeIfPresent(Double.self, forKey: .latitude),
           let longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) {
            location = CLLocation(latitude: latitude, longitude: longitude)
        } else {
            location = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(assetIdentifier, forKey: .assetIdentifier)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
        try container.encodeIfPresent(technicalQuality, forKey: .technicalQuality)
        try container.encodeIfPresent(faceQuality, forKey: .faceQuality)
        try container.encodeIfPresent(overallScore, forKey: .overallScore)
        try container.encodeIfPresent(clusterId, forKey: .clusterId)
        
        // Handle location
        if let location = location {
            try container.encode(location.coordinate.latitude, forKey: .latitude)
            try container.encode(location.coordinate.longitude, forKey: .longitude)
        }
    }
}

// PhotoCluster definition moved to Services/Clustering/PhotoClusteringService.swift

struct Recommendations {
    let generatedAt: Date
    let overall: [Photo]              // Top 5 best photos
    let diverse: [Photo]              // Top 10 diverse selection  
    let byPerson: [String: [Photo]]   // Person-specific albums
    let byTime: [TimeOfDay: [Photo]]  // Time-based groupings
    let byLocation: [String: [Photo]] // Location-based groupings
    
    init(generatedAt: Date = Date(),
         overall: [Photo] = [],
         diverse: [Photo] = [],
         byPerson: [String: [Photo]] = [:],
         byTime: [TimeOfDay: [Photo]] = [:],
         byLocation: [String: [Photo]] = [:]) {
        self.generatedAt = generatedAt
        self.overall = overall
        self.diverse = diverse
        self.byPerson = byPerson
        self.byTime = byTime
        self.byLocation = byLocation
    }
}

// MARK: - Supporting Types

enum TimeOfDay: String, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case night = "Night"
    case goldenHour = "Golden Hour"
    
    static func from(date: Date) -> TimeOfDay {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        switch hour {
        case 5..<9:
            return .morning
        case 9..<17:
            return .afternoon
        case 17..<19:
            return .goldenHour
        case 19..<22:
            return .evening
        default:
            return .night
        }
    }
}

enum PhotoType {
    case multipleFaces
    case landscape
    case portrait
    
    static func detect(from photo: Photo) -> PhotoType {
        if let faceQuality = photo.faceQuality, faceQuality.faceCount > 1 {
            return .multipleFaces
        } else if let faceQuality = photo.faceQuality, faceQuality.faceCount == 1 {
            return .portrait
        } else {
            return .landscape
        }
    }
}