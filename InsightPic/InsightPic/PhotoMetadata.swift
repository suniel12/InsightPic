import Foundation

struct PhotoMetadata: Codable {
    let width: Int
    let height: Int
    let cameraModel: String?
    let lensModel: String?
    let focalLength: Double?    // in mm
    let fNumber: Double?        // aperture value
    let exposureTime: Double?   // in seconds
    let iso: Int?              // ISO value
    let altitude: Double?       // in meters
    
    init(width: Int,
         height: Int,
         cameraModel: String? = nil,
         lensModel: String? = nil,
         focalLength: Double? = nil,
         fNumber: Double? = nil,
         exposureTime: Double? = nil,
         iso: Int? = nil,
         altitude: Double? = nil) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLength = focalLength
        self.fNumber = fNumber
        self.exposureTime = exposureTime
        self.iso = iso
        self.altitude = altitude
    }
    
    // MARK: - Computed Properties
    
    var aspectRatio: Double {
        guard height > 0 else { return 1.0 }
        return Double(width) / Double(height)
    }
    
    var isLandscape: Bool {
        return width > height
    }
    
    var isPortrait: Bool {
        return height > width
    }
    
    var isSquare: Bool {
        return width == height
    }
    
    var megapixels: Double {
        return Double(width * height) / 1_000_000
    }
    
    // MARK: - Camera Settings Analysis
    
    var hasManualSettings: Bool {
        return fNumber != nil && exposureTime != nil && iso != nil
    }
    
    var isLowLight: Bool {
        guard let iso = iso else { return false }
        return iso > 800
    }
    
    var isWideAngle: Bool {
        guard let focalLength = focalLength else { return false }
        return focalLength < 24  // Equivalent to 35mm
    }
    
    var isTelephoto: Bool {
        guard let focalLength = focalLength else { return false }
        return focalLength > 85  // Equivalent to 35mm
    }
    
    var isShallowDepthOfField: Bool {
        guard let fNumber = fNumber else { return false }
        return fNumber < 2.8
    }
    
    // MARK: - Quality Indicators
    
    var resolutionQuality: Float {
        let totalPixels = width * height
        
        switch totalPixels {
        case 0..<1_000_000:      // < 1MP
            return 0.2
        case 1_000_000..<3_000_000:  // 1-3MP
            return 0.4
        case 3_000_000..<8_000_000:  // 3-8MP
            return 0.6
        case 8_000_000..<16_000_000: // 8-16MP
            return 0.8
        default:                     // > 16MP
            return 1.0
        }
    }
    
    // MARK: - Debugging Description
    
    var debugDescription: String {
        var components: [String] = []
        components.append("\(width)x\(height)")
        
        if let camera = cameraModel {
            components.append(camera)
        }
        
        if let f = fNumber {
            components.append("f/\(String(format: "%.1f", f))")
        }
        
        if let exposure = exposureTime {
            if exposure >= 1 {
                components.append("\(String(format: "%.1f", exposure))s")
            } else {
                components.append("1/\(Int(1/exposure))s")
            }
        }
        
        if let iso = iso {
            components.append("ISO \(iso)")
        }
        
        if let focal = focalLength {
            components.append("\(Int(focal))mm")
        }
        
        return components.joined(separator: ", ")
    }
}