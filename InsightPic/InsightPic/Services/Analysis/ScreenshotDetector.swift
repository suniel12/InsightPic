import Foundation
import CoreLocation

/// Utility for detecting screenshots based on photo metadata
struct ScreenshotDetector {
    
    /// Common iPhone screen aspect ratios
    private static let iPhoneScreenRatios: [Double] = [
        16.0/9.0,      // iPhone 8 and earlier
        19.5/9.0,      // iPhone X, 11, 12, 13 series
        20.0/9.0,      // iPhone 14 Pro, 15 Pro series
        2.16,          // iPhone 14 Pro Max, 15 Pro Max
        1.78,          // iPad (4:3 rotated to landscape)
        1.33           // iPad (4:3 portrait)
    ]
    
    /// Tolerance for aspect ratio matching
    private static let aspectRatioTolerance: Double = 0.1
    
    /// Detects if a photo is likely a screenshot
    static func isScreenshot(_ photo: Photo) -> Bool {
        var screenshotScore = 0
        
        // 1. No location data (screenshots don't have GPS) - Strong indicator
        if photo.location == nil {
            screenshotScore += 3
        }
        
        // 2. No camera metadata (screenshots don't have camera info) - Strong indicator
        if photo.metadata.cameraModel == nil {
            screenshotScore += 3
        }
        
        // 3. No camera-specific metadata - Medium indicator
        if photo.metadata.focalLength == nil && 
           photo.metadata.fNumber == nil && 
           photo.metadata.exposureTime == nil && 
           photo.metadata.iso == nil {
            screenshotScore += 2
        }
        
        // 4. Check aspect ratio matches device screen - Medium indicator
        if hasDeviceScreenAspectRatio(photo) {
            screenshotScore += 2
        }
        
        // 5. Check if filename contains screenshot keywords
        if hasScreenshotKeywords(photo.assetIdentifier) {
            screenshotScore += 4 // Very strong indicator
        }
        
        // 6. Very specific dimensions that match device screens
        if hasExactDeviceScreenDimensions(photo) {
            screenshotScore += 3
        }
        
        // Score threshold: 5+ points indicates likely screenshot
        return screenshotScore >= 5
    }
    
    /// Checks if the photo has an aspect ratio matching common device screens
    private static func hasDeviceScreenAspectRatio(_ photo: Photo) -> Bool {
        let aspectRatio = Double(photo.metadata.width) / Double(photo.metadata.height)
        
        return iPhoneScreenRatios.contains { screenRatio in
            abs(aspectRatio - screenRatio) < aspectRatioTolerance ||
            abs(aspectRatio - (1.0 / screenRatio)) < aspectRatioTolerance // Check inverted ratio too
        }
    }
    
    /// Checks if the asset identifier contains screenshot-related keywords
    private static func hasScreenshotKeywords(_ assetIdentifier: String) -> Bool {
        let lowercased = assetIdentifier.lowercased()
        let screenshotKeywords = [
            "screenshot",
            "screen shot", 
            "screen_shot",
            "screen recording",
            "screen_recording",
            "screenrecording",
            "img_",  // Common screenshot prefix
            "photo_" // Another common screenshot prefix
        ]
        
        return screenshotKeywords.contains { keyword in
            lowercased.contains(keyword)
        }
    }
    
    /// Checks if dimensions exactly match known device screen resolutions
    private static func hasExactDeviceScreenDimensions(_ photo: Photo) -> Bool {
        let width = photo.metadata.width
        let height = photo.metadata.height
        
        // Common iPhone screen resolutions (both orientations)
        let knownScreenResolutions: [(Int, Int)] = [
            // iPhone 15 Pro Max, 14 Pro Max
            (1290, 2796), (2796, 1290),
            
            // iPhone 15 Pro, 14 Pro, 13 Pro, 12 Pro
            (1179, 2556), (2556, 1179),
            
            // iPhone 15, 15 Plus, 14, 14 Plus, 13, 13 mini, 12, 12 mini
            (1170, 2532), (2532, 1170),
            (1080, 2340), (2340, 1080),
            
            // iPhone 11 Pro Max, XS Max
            (1242, 2688), (2688, 1242),
            
            // iPhone 11 Pro, XS, X
            (1125, 2436), (2436, 1125),
            
            // iPhone 11, XR
            (828, 1792), (1792, 828),
            
            // iPhone 8 Plus, 7 Plus, 6s Plus, 6 Plus
            (1242, 2208), (2208, 1242),
            
            // iPhone 8, 7, 6s, 6, SE (2nd/3rd gen)
            (750, 1334), (1334, 750),
            
            // iPhone SE (1st gen), 5s, 5c, 5
            (640, 1136), (1136, 640),
            
            // iPad Pro 12.9" (6th/5th gen)
            (2048, 2732), (2732, 2048),
            
            // iPad Pro 11" (4th/3rd gen), iPad Air (5th/4th gen)
            (1668, 2388), (2388, 1668),
            
            // iPad (10th gen)
            (1620, 2360), (2360, 1620),
            
            // iPad mini (6th gen)
            (1488, 2266), (2266, 1488)
        ]
        
        return knownScreenResolutions.contains { (screenWidth, screenHeight) in
            (width == screenWidth && height == screenHeight)
        }
    }
    
    /// Provides a detailed analysis of why a photo might be a screenshot
    static func screenshotAnalysis(_ photo: Photo) -> ScreenshotAnalysis {
        var indicators: [String] = []
        var score = 0
        
        if photo.location == nil {
            indicators.append("No GPS location data")
            score += 3
        }
        
        if photo.metadata.cameraModel == nil {
            indicators.append("No camera model information")
            score += 3
        }
        
        if photo.metadata.focalLength == nil && 
           photo.metadata.fNumber == nil && 
           photo.metadata.exposureTime == nil && 
           photo.metadata.iso == nil {
            indicators.append("No camera settings (focal length, aperture, etc.)")
            score += 2
        }
        
        if hasDeviceScreenAspectRatio(photo) {
            indicators.append("Aspect ratio matches device screen")
            score += 2
        }
        
        if hasScreenshotKeywords(photo.assetIdentifier) {
            indicators.append("Filename contains screenshot keywords")
            score += 4
        }
        
        if hasExactDeviceScreenDimensions(photo) {
            indicators.append("Exact dimensions match device screen resolution")
            score += 3
        }
        
        return ScreenshotAnalysis(
            isLikelyScreenshot: score >= 5,
            confidence: min(score, 10),
            indicators: indicators,
            aspectRatio: Double(photo.metadata.width) / Double(photo.metadata.height)
        )
    }
}

/// Detailed analysis result for screenshot detection
struct ScreenshotAnalysis {
    let isLikelyScreenshot: Bool
    let confidence: Int // 0-10 scale
    let indicators: [String]
    let aspectRatio: Double
    
    var confidenceDescription: String {
        switch confidence {
        case 0...2: return "Very Low"
        case 3...4: return "Low"
        case 5...6: return "Medium"
        case 7...8: return "High"
        default: return "Very High"
        }
    }
}