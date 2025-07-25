import Foundation

// MARK: - Quality Score Models

struct PhotoScore: Codable {
    let technical: Float      // 0-1 (sharpness, exposure, composition)
    let faces: Float         // 0-1 (face quality, expressions)
    let context: Float       // 0-1 (uniqueness, timing, social context)
    let overall: Float       // Weighted combination
    let calculatedAt: Date
    
    init(technical: Float,
         faces: Float,
         context: Float,
         overall: Float? = nil,
         calculatedAt: Date = Date()) {
        self.technical = max(0, min(1, technical))
        self.faces = max(0, min(1, faces))
        self.context = max(0, min(1, context))
        self.calculatedAt = calculatedAt
        
        // Calculate overall score if not provided
        if let providedOverall = overall {
            self.overall = max(0, min(1, providedOverall))
        } else {
            // Default weighting - will be adjusted based on photo type in practice
            self.overall = max(0, min(1, (technical * 0.4 + faces * 0.4 + context * 0.2)))
        }
    }
    
    // Weighted calculation based on photo content
    static func calculate(technical: Float, faces: Float, context: Float, photoType: PhotoType) -> Float {
        let normalizedTechnical = max(0, min(1, technical))
        let normalizedFaces = max(0, min(1, faces))
        let normalizedContext = max(0, min(1, context))
        
        let score: Float
        switch photoType {
        // Person-focused photos
        case .portrait:
            score = normalizedTechnical * 0.4 + normalizedFaces * 0.4 + normalizedContext * 0.2
        case .groupPhoto, .multipleFaces:
            score = normalizedTechnical * 0.3 + normalizedFaces * 0.5 + normalizedContext * 0.2
        case .event:
            score = normalizedTechnical * 0.25 + normalizedFaces * 0.45 + normalizedContext * 0.3
            
        // Scenery-focused photos
        case .landscape, .outdoor:
            score = normalizedTechnical * 0.5 + normalizedContext * 0.4 + normalizedFaces * 0.1
        case .goldenHour:
            score = normalizedTechnical * 0.4 + normalizedContext * 0.5 + normalizedFaces * 0.1
            
        // Technical/artistic photos
        case .closeUp:
            score = normalizedTechnical * 0.6 + normalizedContext * 0.3 + normalizedFaces * 0.1
        case .action:
            score = normalizedTechnical * 0.3 + normalizedContext * 0.5 + normalizedFaces * 0.2
        case .lowLight:
            score = normalizedTechnical * 0.7 + normalizedContext * 0.2 + normalizedFaces * 0.1
            
        // Environment-based
        case .indoor:
            score = normalizedTechnical * 0.45 + normalizedFaces * 0.35 + normalizedContext * 0.2
            
        // Utility/low priority
        case .utility:
            score = max(0.1, min(0.3, normalizedTechnical * 0.8 + normalizedContext * 0.2)) // Cap utility photos
        }
        
        return max(0, min(1, score))
    }
}

struct TechnicalQualityScore: Codable {
    let sharpness: Float      // Laplacian variance analysis
    let exposure: Float       // Histogram analysis
    let composition: Float    // Rule of thirds, saliency
    let overall: Float        // Weighted average
    
    init(sharpness: Float, exposure: Float, composition: Float, overall: Float? = nil) {
        self.sharpness = max(0, min(1, sharpness))
        self.exposure = max(0, min(1, exposure))
        self.composition = max(0, min(1, composition))
        
        if let providedOverall = overall {
            self.overall = max(0, min(1, providedOverall))
        } else {
            // Equal weighting for technical aspects
            self.overall = max(0, min(1, (self.sharpness + self.exposure + self.composition) / 3.0))
        }
    }
}

struct FaceQualityScore: Codable {
    let faceCount: Int
    let averageScore: Float   // Average quality across all faces
    let eyesOpen: Bool        // All faces have open eyes
    let goodExpressions: Bool // All faces have good expressions
    let optimalSizes: Bool    // All faces are well-sized
    
    init(faceCount: Int,
         averageScore: Float,
         eyesOpen: Bool,
         goodExpressions: Bool,
         optimalSizes: Bool) {
        self.faceCount = max(0, faceCount)
        self.averageScore = max(0, min(1, averageScore))
        self.eyesOpen = eyesOpen
        self.goodExpressions = goodExpressions
        self.optimalSizes = optimalSizes
    }
    
    // Convenience initializer for no faces detected
    static var noFaces: FaceQualityScore {
        return FaceQualityScore(faceCount: 0, averageScore: 0.5, eyesOpen: false, goodExpressions: false, optimalSizes: false)
    }
    
    // Calculate composite face quality score
    var compositeScore: Float {
        guard faceCount > 0 else { return 0.5 }
        
        var score = averageScore
        
        // Bonus for good facial attributes
        if eyesOpen { score += 0.1 }
        if goodExpressions { score += 0.1 }
        if optimalSizes { score += 0.1 }
        
        return max(0, min(1, score))
    }
}