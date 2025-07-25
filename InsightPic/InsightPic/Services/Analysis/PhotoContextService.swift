import Foundation
import CoreLocation

// MARK: - Photo Context Analysis Service

protocol PhotoContextServiceProtocol {
    func analyzeContext(for photo: Photo, result: PhotoAnalysisResult) -> PhotoContext
    func calculateContextScore(from context: PhotoContext) -> Float
    func getSeasonalBonus(for date: Date) -> Float
    func getLocationContext(for location: CLLocation?) -> LocationContext
    func getTimeContext(for date: Date) -> TimeContext
}

// MARK: - Context Models

struct PhotoContext {
    let timeContext: TimeContext
    let locationContext: LocationContext
    let seasonalContext: SeasonalContext
    let socialContext: SocialContext
    let technicalContext: TechnicalContext
    let aestheticContext: AestheticContext
    
    var overallContextScore: Float {
        let weights: [Float] = [0.2, 0.15, 0.1, 0.2, 0.2, 0.15]
        let scores = [
            timeContext.score,
            locationContext.score,
            seasonalContext.score,
            socialContext.score,
            technicalContext.score,
            aestheticContext.score
        ]
        
        return zip(scores, weights).reduce(0) { $0 + $1.0 * $1.1 }
    }
}

struct TimeContext {
    let timeOfDay: TimeOfDay
    let isWeekend: Bool
    let isHoliday: Bool
    let isGoldenHour: Bool
    let isMagicHour: Bool // Blue hour
    
    var score: Float {
        var score: Float = 0.5 // Base score
        
        switch timeOfDay {
        case .goldenHour:
            score += 0.3
        case .morning, .evening:
            score += 0.2
        case .afternoon:
            score += 0.1
        case .night:
            score += 0.05 // Night photos can be special but challenging
        }
        
        if isWeekend { score += 0.1 }
        if isHoliday { score += 0.15 }
        if isGoldenHour { score += 0.2 }
        if isMagicHour { score += 0.15 }
        
        return min(1.0, score)
    }
}

struct LocationContext {
    let hasLocation: Bool
    let isSignificantLocation: Bool // Home, work, frequently visited
    let isVacationLocation: Bool
    let isLandmark: Bool
    let locationType: LocationType
    
    var score: Float {
        var score: Float = hasLocation ? 0.6 : 0.4
        
        if isVacationLocation { score += 0.2 }
        if isLandmark { score += 0.15 }
        if isSignificantLocation { score += 0.1 }
        
        switch locationType {
        case .nature:
            score += 0.15
        case .landmark:
            score += 0.12
        case .travel:
            score += 0.1
        case .event:
            score += 0.08
        case .home, .work:
            score += 0.05
        case .unknown:
            break
        }
        
        return min(1.0, score)
    }
}

struct SeasonalContext {
    let season: Season
    let month: Int
    let isHoliday: Bool
    let isSpecialDate: Bool // Birthday, anniversary, etc.
    
    var score: Float {
        var score: Float = 0.5
        
        // Seasonal bonuses for outdoor photos
        switch season {
        case .spring, .fall:
            score += 0.15 // Beautiful seasons
        case .summer:
            score += 0.1
        case .winter:
            score += 0.05
        }
        
        if isHoliday { score += 0.2 }
        if isSpecialDate { score += 0.25 }
        
        return min(1.0, score)
    }
}

struct SocialContext {
    let numberOfPeople: Int
    let hasSmiles: Bool
    let isGroupActivity: Bool
    let socialSetting: SocialSetting
    
    var score: Float {
        var score: Float = 0.5
        
        // People in photos generally increase social value
        switch numberOfPeople {
        case 0:
            score += 0.0 // Scenic photos
        case 1:
            score += 0.1 // Portraits
        case 2...4:
            score += 0.2 // Small groups
        case 5...10:
            score += 0.25 // Parties, gatherings
        default:
            score += 0.15 // Very large groups might be less intimate
        }
        
        if hasSmiles { score += 0.15 }
        if isGroupActivity { score += 0.1 }
        
        switch socialSetting {
        case .celebration:
            score += 0.2
        case .family:
            score += 0.15
        case .friends:
            score += 0.12
        case .professional:
            score += 0.05
        case .solo:
            score += 0.08
        case .unknown:
            break
        }
        
        return min(1.0, score)
    }
}

struct TechnicalContext {
    let cameraType: CameraType
    let shootingMode: ShootingMode
    let hasFlash: Bool
    let isHDR: Bool
    let hasPortraitMode: Bool
    
    var score: Float {
        var score: Float = 0.5
        
        switch cameraType {
        case .dslr, .mirrorless:
            score += 0.15 // Professional cameras
        case .smartphone:
            score += 0.05
        case .pointAndShoot:
            score += 0.08
        case .unknown:
            break
        }
        
        switch shootingMode {
        case .manual:
            score += 0.1 // Intentional photography
        case .aperturePriority, .shutterPriority:
            score += 0.08
        case .portrait:
            score += 0.12
        case .auto:
            score += 0.02
        case .unknown:
            break
        }
        
        if hasPortraitMode { score += 0.1 }
        if isHDR { score += 0.05 }
        
        return min(1.0, score)
    }
}

struct AestheticContext {
    let hasGoodLighting: Bool
    let hasInterestingComposition: Bool
    let hasColorHarmony: Bool
    let visualComplexity: VisualComplexity
    let aestheticStyle: AestheticStyle
    
    var score: Float {
        var score: Float = 0.5
        
        if hasGoodLighting { score += 0.2 }
        if hasInterestingComposition { score += 0.15 }
        if hasColorHarmony { score += 0.1 }
        
        switch visualComplexity {
        case .simple:
            score += 0.1 // Clean, focused
        case .balanced:
            score += 0.15 // Ideal complexity
        case .complex:
            score += 0.05 // Can be overwhelming
        case .chaotic:
            score -= 0.1 // Usually not pleasing
        }
        
        return max(0.0, min(1.0, score))
    }
}

// MARK: - Supporting Enums

enum Season {
    case spring, summer, fall, winter
    
    static func from(date: Date) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .fall
        default: return .winter
        }
    }
}

enum LocationType {
    case home, work, nature, landmark, travel, event, unknown
}

enum SocialSetting {
    case celebration, family, friends, professional, solo, unknown
}

enum CameraType {
    case smartphone, dslr, mirrorless, pointAndShoot, unknown
}

enum ShootingMode {
    case auto, manual, aperturePriority, shutterPriority, portrait, unknown
}

enum VisualComplexity {
    case simple, balanced, complex, chaotic
}

enum AestheticStyle {
    case natural, artistic, documentary, portrait, landscape, unknown
}

// MARK: - Photo Context Service Implementation

class PhotoContextService: PhotoContextServiceProtocol {
    
    func analyzeContext(for photo: Photo, result: PhotoAnalysisResult) -> PhotoContext {
        let timeContext = getTimeContext(for: photo.timestamp)
        let locationContext = getLocationContext(for: photo.location)
        let seasonalContext = getSeasonalContext(for: photo.timestamp)
        let socialContext = getSocialContext(from: result)
        let technicalContext = getTechnicalContext(from: photo, result: result)
        let aestheticContext = getAestheticContext(from: result)
        
        return PhotoContext(
            timeContext: timeContext,
            locationContext: locationContext,
            seasonalContext: seasonalContext,
            socialContext: socialContext,
            technicalContext: technicalContext,
            aestheticContext: aestheticContext
        )
    }
    
    func calculateContextScore(from context: PhotoContext) -> Float {
        return context.overallContextScore
    }
    
    func getSeasonalBonus(for date: Date) -> Float {
        let season = Season.from(date: date)
        let context = getSeasonalContext(for: date)
        return context.score - 0.5 // Return bonus above baseline
    }
    
    func getLocationContext(for location: CLLocation?) -> LocationContext {
        return LocationContext(
            hasLocation: location != nil,
            isSignificantLocation: false, // Would need user data
            isVacationLocation: false, // Would need travel detection
            isLandmark: false, // Would need landmark database
            locationType: .unknown
        )
    }
    
    func getTimeContext(for date: Date) -> TimeContext {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        
        let timeOfDay = TimeOfDay.from(date: date)
        let isWeekend = weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
        let isGoldenHour = (hour >= 6 && hour <= 8) || (hour >= 17 && hour <= 19)
        let isMagicHour = (hour >= 19 && hour <= 20) || (hour >= 5 && hour <= 6)
        
        return TimeContext(
            timeOfDay: timeOfDay,
            isWeekend: isWeekend,
            isHoliday: false, // Would need holiday calendar
            isGoldenHour: isGoldenHour,
            isMagicHour: isMagicHour
        )
    }
    
    // MARK: - Private Context Analysis Methods
    
    private func getSeasonalContext(for date: Date) -> SeasonalContext {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let season = Season.from(date: date)
        
        return SeasonalContext(
            season: season,
            month: month,
            isHoliday: false, // Would need holiday detection
            isSpecialDate: false // Would need user data
        )
    }
    
    private func getSocialContext(from result: PhotoAnalysisResult) -> SocialContext {
        let numberOfPeople = result.faces.count
        let hasSmiles = result.faces.contains { $0.isSmiling == true }
        let isGroupActivity = numberOfPeople >= 3
        
        let socialSetting: SocialSetting
        switch numberOfPeople {
        case 0:
            socialSetting = .solo
        case 1:
            socialSetting = .solo
        case 2...4:
            socialSetting = .friends
        case 5...10:
            socialSetting = hasSmiles ? .celebration : .friends
        default:
            socialSetting = .celebration
        }
        
        return SocialContext(
            numberOfPeople: numberOfPeople,
            hasSmiles: hasSmiles,
            isGroupActivity: isGroupActivity,
            socialSetting: socialSetting
        )
    }
    
    private func getTechnicalContext(from photo: Photo, result: PhotoAnalysisResult) -> TechnicalContext {
        let cameraModel = photo.metadata.cameraModel?.lowercased() ?? ""
        
        let cameraType: CameraType
        if cameraModel.contains("iphone") || cameraModel.contains("android") {
            cameraType = .smartphone
        } else if cameraModel.contains("canon") || cameraModel.contains("nikon") || cameraModel.contains("sony") {
            cameraType = .dslr
        } else {
            cameraType = .unknown
        }
        
        return TechnicalContext(
            cameraType: cameraType,
            shootingMode: .unknown, // Would need EXIF analysis
            hasFlash: false, // Would need EXIF analysis
            isHDR: false, // Would need metadata analysis
            hasPortraitMode: result.faces.count == 1 && result.exposureScore > 0.7
        )
    }
    
    private func getAestheticContext(from result: PhotoAnalysisResult) -> AestheticContext {
        let hasGoodLighting = result.exposureScore > 0.7
        let hasInterestingComposition = result.saliencyAnalysis?.compositionScore ?? 0.0 > 0.6
        let hasColorHarmony = result.aestheticAnalysis?.overallScore ?? -1.0 > 0.3
        
        let visualComplexity: VisualComplexity
        let objectCount = result.objects.count
        switch objectCount {
        case 0...2:
            visualComplexity = .simple
        case 3...5:
            visualComplexity = .balanced
        case 6...10:
            visualComplexity = .complex
        default:
            visualComplexity = .chaotic
        }
        
        return AestheticContext(
            hasGoodLighting: hasGoodLighting,
            hasInterestingComposition: hasInterestingComposition,
            hasColorHarmony: hasColorHarmony,
            visualComplexity: visualComplexity,
            aestheticStyle: .unknown
        )
    }
}