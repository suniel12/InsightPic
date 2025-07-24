import Foundation
import Vision
import UIKit
import CoreImage

// MARK: - Photo Analysis Models

struct PhotoAnalysisResult {
    let photoId: UUID
    let assetIdentifier: String
    let qualityScore: Double // 0.0 to 1.0
    let sharpnessScore: Double
    let exposureScore: Double
    let compositionScore: Double
    let faces: [FaceAnalysis]
    let objects: [ObjectAnalysis]
    let aestheticScore: Double
    let timestamp: Date
    
    var overallScore: Double {
        // Weighted average of different quality metrics
        return (qualityScore * 0.3 + sharpnessScore * 0.25 + exposureScore * 0.2 + compositionScore * 0.15 + aestheticScore * 0.1)
    }
}

struct FaceAnalysis {
    let boundingBox: CGRect
    let confidence: Float
    let faceQuality: Double // 0.0 to 1.0
    let isSmiling: Bool?
    let eyesOpen: Bool?
}

struct ObjectAnalysis {
    let identifier: String
    let confidence: Float
    let boundingBox: CGRect
}

// MARK: - PhotoAnalysisService Protocol

protocol PhotoAnalysisServiceProtocol {
    func analyzePhoto(_ photo: Photo, image: UIImage) async throws -> PhotoAnalysisResult
    func analyzePhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws -> [PhotoAnalysisResult]
    func findBestPhotos(from results: [PhotoAnalysisResult], count: Int) -> [PhotoAnalysisResult]
    func findSimilarPhotos(from results: [PhotoAnalysisResult]) -> [[PhotoAnalysisResult]]
}

// MARK: - PhotoAnalysisService Implementation

class PhotoAnalysisService: PhotoAnalysisServiceProtocol {
    
    private let imageAnalyzer = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    private let photoLibraryService: PhotoLibraryServiceProtocol
    
    init(photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
    }
    
    // MARK: - Public Methods
    
    func analyzePhoto(_ photo: Photo, image: UIImage) async throws -> PhotoAnalysisResult {
        // Analyze different aspects of the photo
        let sharpnessScore = await analyzeSharpness(image: image)
        let exposureScore = await analyzeExposure(image: image)
        let compositionScore = await analyzeComposition(image: image)
        let faces = await analyzeFaces(image: image)
        let objects = await analyzeObjects(image: image)
        let aestheticScore = await analyzeAesthetics(image: image, faces: faces, objects: objects)
        
        // Calculate overall quality score
        let qualityScore = calculateOverallQuality(
            sharpness: sharpnessScore,
            exposure: exposureScore,
            composition: compositionScore,
            faces: faces,
            objects: objects
        )
        
        return PhotoAnalysisResult(
            photoId: photo.id,
            assetIdentifier: photo.assetIdentifier,
            qualityScore: qualityScore,
            sharpnessScore: sharpnessScore,
            exposureScore: exposureScore,
            compositionScore: compositionScore,
            faces: faces,
            objects: objects,
            aestheticScore: aestheticScore,
            timestamp: Date()
        )
    }
    
    func analyzePhotos(_ photos: [Photo], progressCallback: @escaping (Int, Int) -> Void) async throws -> [PhotoAnalysisResult] {
        var results: [PhotoAnalysisResult] = []
        let totalPhotos = photos.count
        
        for (index, photo) in photos.enumerated() {
            // Load the image for analysis
            guard let image = try await loadImageForAnalysis(photo: photo) else {
                print("Warning: Could not load image for photo \(photo.assetIdentifier)")
                continue
            }
            
            // Analyze the photo
            let result = try await analyzePhoto(photo, image: image)
            results.append(result)
            
            // Report progress
            progressCallback(index + 1, totalPhotos)
        }
        
        return results
    }
    
    func findBestPhotos(from results: [PhotoAnalysisResult], count: Int) -> [PhotoAnalysisResult] {
        return Array(results.sorted { $0.overallScore > $1.overallScore }.prefix(count))
    }
    
    func findSimilarPhotos(from results: [PhotoAnalysisResult]) -> [[PhotoAnalysisResult]] {
        // Group photos by similarity (timestamp proximity for now)
        let grouped = Dictionary(grouping: results) { result in
            Calendar.current.dateInterval(of: .hour, for: result.timestamp)?.start ?? result.timestamp
        }
        
        return grouped.values.compactMap { group -> [PhotoAnalysisResult]? in
            return group.count > 1 ? Array(group) : nil
        }
    }
    
    // MARK: - Private Analysis Methods
    
    private func analyzeSharpness(image: UIImage) async -> Double {
        guard let ciImage = CIImage(image: image) else { return 0.0 }
        
        // Simplified sharpness analysis based on image resolution and quality indicators
        let width = image.size.width
        let height = image.size.height
        let pixelCount = width * height
        
        // Higher resolution typically indicates better sharpness potential
        var sharpnessScore = 0.3 // Base score
        
        if pixelCount > 2000000 { // > 2MP
            sharpnessScore += 0.4
        } else if pixelCount > 1000000 { // > 1MP
            sharpnessScore += 0.3
        } else if pixelCount > 500000 { // > 0.5MP
            sharpnessScore += 0.2
        }
        
        // Good aspect ratio bonus (indicates less cropping/quality loss)
        let aspectRatio = width / height
        if aspectRatio >= 0.75 && aspectRatio <= 1.77 {
            sharpnessScore += 0.2
        }
        
        // Apply simple variance check using grayscale conversion
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey)
        
        if filter?.outputImage != nil {
            sharpnessScore += 0.1 // Bonus for successful processing
        }
        
        return min(1.0, sharpnessScore)
    }
    
    private func analyzeExposure(image: UIImage) async -> Double {
        guard let ciImage = CIImage(image: image) else { return 0.0 }
        
        // Calculate average brightness
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        
        guard let outputImage = filter?.outputImage else { return 0.0 }
        
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        let averageBrightness = (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / (3.0 * 255.0)
        
        // Good exposure is around 0.4-0.6 brightness
        let exposureScore: Double
        if averageBrightness < 0.2 || averageBrightness > 0.8 {
            exposureScore = 0.3 // Poor exposure (too dark or too bright)
        } else if averageBrightness >= 0.4 && averageBrightness <= 0.6 {
            exposureScore = 1.0 // Excellent exposure
        } else {
            exposureScore = 0.7 // Good exposure
        }
        
        return exposureScore
    }
    
    private func analyzeComposition(image: UIImage) async -> Double {
        // Simplified composition analysis based on aspect ratio and image dimensions
        let aspectRatio = image.size.width / image.size.height
        let isGoodAspectRatio = (aspectRatio >= 0.75 && aspectRatio <= 1.33) || // Square-ish
                               (aspectRatio >= 1.5 && aspectRatio <= 1.8)   // 16:9 or 3:2
        
        let resolution = image.size.width * image.size.height
        let isHighResolution = resolution > 1000000 // > 1MP
        
        var compositionScore = 0.5 // Base score
        
        if isGoodAspectRatio {
            compositionScore += 0.3
        }
        
        if isHighResolution {
            compositionScore += 0.2
        }
        
        return min(1.0, compositionScore)
    }
    
    private func analyzeFaces(image: UIImage) async -> [FaceAnalysis] {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: [])
                return
            }
            
            let request = VNDetectFaceRectanglesRequest { request, error in
                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let faces = observations.map { observation in
                    FaceAnalysis(
                        boundingBox: observation.boundingBox,
                        confidence: observation.confidence,
                        faceQuality: Double(observation.confidence),
                        isSmiling: nil, // Would need additional analysis
                        eyesOpen: nil   // Would need additional analysis
                    )
                }
                
                continuation.resume(returning: faces)
            }
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func analyzeObjects(image: UIImage) async -> [ObjectAnalysis] {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: [])
                return
            }
            
            let request = VNClassifyImageRequest { request, error in
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                // Take top 3 classifications with reasonable confidence
                let filteredObservations = observations.filter { $0.confidence > 0.3 }.prefix(3)
                
                let objects = filteredObservations.map { observation in
                    ObjectAnalysis(
                        identifier: observation.identifier,
                        confidence: observation.confidence,
                        boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1) // Full image for classification
                    )
                }
                
                continuation.resume(returning: Array(objects))
            }
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func analyzeAesthetics(image: UIImage, faces: [FaceAnalysis], objects: [ObjectAnalysis]) async -> Double {
        var aestheticScore = 0.5 // Base score
        
        // Bonus for faces (people photos are often more interesting)
        if !faces.isEmpty {
            aestheticScore += 0.2
            
            // Bonus for high-quality faces
            let avgFaceQuality = faces.reduce(0.0) { $0 + $1.faceQuality } / Double(faces.count)
            aestheticScore += avgFaceQuality * 0.1
        }
        
        // Bonus for interesting objects
        if !objects.isEmpty {
            let avgObjectConfidence = objects.reduce(0.0) { $0 + Double($1.confidence) } / Double(objects.count)
            aestheticScore += avgObjectConfidence * 0.15
        }
        
        return min(1.0, aestheticScore)
    }
    
    private func calculateOverallQuality(
        sharpness: Double,
        exposure: Double,
        composition: Double,
        faces: [FaceAnalysis],
        objects: [ObjectAnalysis]
    ) -> Double {
        var quality = (sharpness * 0.4 + exposure * 0.3 + composition * 0.3)
        
        // Bonus for faces
        if !faces.isEmpty {
            quality += 0.1
        }
        
        // Bonus for multiple interesting objects
        if objects.count > 2 {
            quality += 0.05
        }
        
        return min(1.0, quality)
    }
    
    private func loadImageForAnalysis(photo: Photo) async throws -> UIImage? {
        // Load full resolution image for analysis
        return try await photoLibraryService.getFullResolutionImage(for: photo.assetIdentifier)
    }
}

// MARK: - Analysis Extensions

extension PhotoAnalysisResult {
    var qualityDescription: String {
        switch overallScore {
        case 0.8...1.0: return "Excellent"
        case 0.6..<0.8: return "Good"
        case 0.4..<0.6: return "Fair"
        default: return "Poor"
        }
    }
    
    var primaryIssues: [String] {
        var issues: [String] = []
        
        if sharpnessScore < 0.5 {
            issues.append("Blurry")
        }
        
        if exposureScore < 0.5 {
            issues.append("Poor exposure")
        }
        
        if compositionScore < 0.5 {
            issues.append("Poor composition")
        }
        
        return issues
    }
}