import Foundation
import CoreML
import Vision
import UIKit

// MARK: - Core ML Aesthetic Service Protocol

protocol CoreMLAestheticServiceProtocol {
    func evaluateAesthetic(for image: UIImage) async -> CoreMLAestheticResult?
    func enhanceQualityScore(baseScore: Float, image: UIImage) async -> Float
    func isUtilityImage(_ image: UIImage) async -> Bool
}

// MARK: - Core ML Aesthetic Models

struct CoreMLAestheticResult {
    let aestheticScore: Float      // 0.0 to 1.0 (higher is more aesthetic)
    let isUtility: Bool           // True if utility image
    let confidenceLevel: Float    // Confidence in the assessment
    let modelVersion: String      // Which model was used
    
    var enhancedScore: Float {
        // Apply utility penalty
        return isUtility ? min(aestheticScore, 0.2) : aestheticScore
    }
}

// MARK: - Core ML Service Implementation

class CoreMLAestheticService: CoreMLAestheticServiceProtocol {
    
    private var aestheticModel: MLModel?
    private var utilityClassifier: MLModel?
    
    init() {
        loadModels()
    }
    
    private func loadModels() {
        // Note: These would be actual Core ML models in a real implementation
        // For now, we'll use placeholder functionality
        
        // Try to load NIMA (Neural Image Assessment) model
        // aestheticModel = try? MLModel(contentsOf: nimaModelURL)
        
        // Try to load utility classifier
        // utilityClassifier = try? MLModel(contentsOf: utilityModelURL)
        
        print("CoreML Aesthetic Service initialized (using fallback implementations)")
    }
    
    func evaluateAesthetic(for image: UIImage) async -> CoreMLAestheticResult? {
        // Implementation using multiple assessment approaches
        let visionScore = await evaluateUsingVisionFramework(image: image)
        let statisticalScore = await evaluateUsingStatisticalAnalysis(image: image)
        let compositionScore = await evaluateComposition(image: image)
        
        // Combine scores from different approaches
        let combinedScore = (visionScore * 0.4 + statisticalScore * 0.3 + compositionScore * 0.3)
        
        let isUtility = await isUtilityImage(image)
        
        return CoreMLAestheticResult(
            aestheticScore: combinedScore,
            isUtility: isUtility,
            confidenceLevel: 0.8, // High confidence in our multi-approach system
            modelVersion: "Enhanced Multi-Model v1.0"
        )
    }
    
    func enhanceQualityScore(baseScore: Float, image: UIImage) async -> Float {
        guard let aestheticResult = await evaluateAesthetic(for: image) else {
            return baseScore
        }
        
        // Blend base quality score with aesthetic assessment
        let enhancedScore = baseScore * 0.7 + aestheticResult.enhancedScore * 0.3
        
        return min(1.0, enhancedScore)
    }
    
    func isUtilityImage(_ image: UIImage) async -> Bool {
        // Multi-factor utility detection
        let hasTextContent = await detectTextContent(image: image)
        let hasScreenshotCharacteristics = detectScreenshotCharacteristics(image: image)
        let hasDocumentStructure = await detectDocumentStructure(image: image)
        let hasQRCode = await detectQRCode(image: image)
        
        // Consider it utility if it has multiple utility characteristics
        let utilityFactors = [hasTextContent, hasScreenshotCharacteristics, hasDocumentStructure, hasQRCode]
        let utilityCount = utilityFactors.filter { $0 }.count
        
        return utilityCount >= 2 || hasScreenshotCharacteristics
    }
    
    // MARK: - Vision Framework Integration
    
    private func evaluateUsingVisionFramework(image: UIImage) async -> Float {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: 0.5)
                return
            }
            
            // Use Vision's aesthetic analysis if available
            if #available(iOS 15.0, *) {
                let request = VNCalculateImageAestheticsScoresRequest { request, error in
                    guard let results = request.results as? [VNImageAestheticsScoresObservation],
                          let result = results.first else {
                        continuation.resume(returning: 0.5)
                        return
                    }
                    
                    // Normalize from -1,1 to 0,1
                    let normalizedScore = (result.overallScore + 1.0) / 2.0
                    continuation.resume(returning: normalizedScore)
                }
                
                let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
                try? handler.perform([request])
            } else {
                continuation.resume(returning: 0.5)
            }
        }
    }
    
    // MARK: - Statistical Analysis
    
    private func evaluateUsingStatisticalAnalysis(image: UIImage) async -> Float {
        guard let ciImage = CIImage(image: image) else { return 0.5 }
        
        var score: Float = 0.5
        
        // Color distribution analysis
        score += await analyzeColorDistribution(ciImage: ciImage) * 0.3
        
        // Contrast and exposure analysis
        score += analyzeContrastAndExposure(ciImage: ciImage) * 0.4
        
        // Noise analysis
        score += analyzeImageNoise(ciImage: ciImage) * 0.3
        
        return min(1.0, score)
    }
    
    private func analyzeColorDistribution(ciImage: CIImage) async -> Float {
        // Analyze color variance and distribution using area average instead
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        
        guard let outputImage = filter?.outputImage else { return 0.0 }
        
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        // Calculate color variance from RGB values
        let r = Float(bitmap[0]) / 255.0
        let g = Float(bitmap[1]) / 255.0
        let b = Float(bitmap[2]) / 255.0
        
        let mean = (r + g + b) / 3.0
        let variance = ((r - mean) * (r - mean) + (g - mean) * (g - mean) + (b - mean) * (b - mean)) / 3.0
        
        return min(0.3, variance * 2.0) // Normalize and cap
    }
    
    private func analyzeContrastAndExposure(ciImage: CIImage) -> Float {
        // Use Core Image filters to analyze contrast
        let exposureFilter = CIFilter(name: "CIExposureAdjust")
        exposureFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        exposureFilter?.setValue(0.0, forKey: kCIInputEVKey)
        
        // Analyze histogram for exposure quality
        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        
        guard let outputImage = filter?.outputImage else { return 0.0 }
        
        let context = CIContext()
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        let brightness = (Float(bitmap[0]) + Float(bitmap[1]) + Float(bitmap[2])) / (3.0 * 255.0)
        
        // Good exposure is around 0.3-0.7 brightness
        if brightness >= 0.3 && brightness <= 0.7 {
            return 0.4
        } else if brightness >= 0.2 && brightness <= 0.8 {
            return 0.3
        } else {
            return 0.1
        }
    }
    
    private func analyzeImageNoise(ciImage: CIImage) -> Float {
        // Use noise reduction filter to estimate noise level
        let noiseFilter = CIFilter(name: "CINoiseReduction")
        noiseFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        noiseFilter?.setValue(0.02, forKey: "inputNoiseLevel")
        noiseFilter?.setValue(0.40, forKey: "inputSharpness")
        
        // Lower noise typically indicates higher quality
        // This is a simplified implementation
        return 0.3 // Placeholder - would need more sophisticated noise analysis
    }
    
    // MARK: - Composition Analysis
    
    private func evaluateComposition(image: UIImage) async -> Float {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: 0.5)
                return
            }
            
            // Use saliency analysis for composition evaluation
            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                guard let results = request.results as? [VNSaliencyImageObservation],
                      let result = results.first else {
                    continuation.resume(returning: 0.5)
                    return
                }
                
                let compositionScore = self.evaluateCompositionFromSaliency(
                    salientObjects: result.salientObjects?.map { $0.boundingBox } ?? [],
                    imageSize: ciImage.extent.size
                )
                
                continuation.resume(returning: compositionScore)
            }
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func evaluateCompositionFromSaliency(salientObjects: [CGRect], imageSize: CGSize) -> Float {
        guard !salientObjects.isEmpty else { return 0.3 }
        
        var compositionScore: Float = 0.5
        
        // Rule of thirds analysis
        let thirdX = imageSize.width / 3
        let thirdY = imageSize.height / 3
        
        let ruleOfThirdsPoints = [
            CGPoint(x: thirdX, y: thirdY),
            CGPoint(x: 2 * thirdX, y: thirdY),
            CGPoint(x: thirdX, y: 2 * thirdY),
            CGPoint(x: 2 * thirdX, y: 2 * thirdY)
        ]
        
        for obj in salientObjects {
            let center = CGPoint(x: obj.midX * imageSize.width, y: obj.midY * imageSize.height)
            
            // Check proximity to rule of thirds points
            for rulePoint in ruleOfThirdsPoints {
                let distance = sqrt(pow(center.x - rulePoint.x, 2) + pow(center.y - rulePoint.y, 2))
                let normalizedDistance = distance / min(imageSize.width, imageSize.height)
                
                if normalizedDistance < 0.1 { // Within 10% of image dimension
                    compositionScore += 0.2
                    break
                }
            }
        }
        
        // Balance analysis - prefer 1-3 main subjects
        if salientObjects.count >= 1 && salientObjects.count <= 3 {
            compositionScore += 0.1
        }
        
        return min(1.0, compositionScore)
    }
    
    // MARK: - Utility Detection Methods
    
    private func detectTextContent(image: UIImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: false)
                return
            }
            
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: false)
                    return
                }
                
                // Consider it text-heavy if there are many text regions
                let hasSignificantText = observations.count > 5 ||
                                       observations.contains { $0.boundingBox.width * $0.boundingBox.height > 0.1 }
                
                continuation.resume(returning: hasSignificantText)
            }
            
            request.recognitionLevel = .fast
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func detectScreenshotCharacteristics(image: UIImage) -> Bool {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        // Common screenshot aspect ratios
        let commonScreenRatios: [CGFloat] = [9.0/16.0, 16.0/9.0, 4.0/3.0, 3.0/4.0, 1.0, 19.5/9.0, 9.0/19.5]
        
        for ratio in commonScreenRatios {
            if abs(aspectRatio - ratio) < 0.05 { // 5% tolerance
                // Additional checks for screenshot characteristics
                if size.width >= 1080 || size.height >= 1080 { // High resolution
                    return true
                }
            }
        }
        
        return false
    }
    
    private func detectDocumentStructure(image: UIImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: false)
                return
            }
            
            // Use rectangle detection as a proxy for document structure
            let request = VNDetectRectanglesRequest { request, error in
                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: false)
                    return
                }
                
                // If we find large rectangular regions, it might be a document
                let hasLargeRectangles = observations.contains { rect in
                    let area = rect.boundingBox.width * rect.boundingBox.height
                    return area > 0.3 // More than 30% of image area
                }
                
                continuation.resume(returning: hasLargeRectangles)
            }
            
            request.minimumAspectRatio = 0.3
            request.maximumAspectRatio = 3.0
            request.minimumSize = 0.2
            request.minimumConfidence = 0.6
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func detectQRCode(image: UIImage) async -> Bool {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: false)
                return
            }
            
            let request = VNDetectBarcodesRequest { request, error in
                guard let observations = request.results as? [VNBarcodeObservation] else {
                    continuation.resume(returning: false)
                    return
                }
                
                let hasQRCode = !observations.isEmpty
                continuation.resume(returning: hasQRCode)
            }
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateVariance(values: [Float]) -> Float {
        guard !values.isEmpty else { return 0.0 }
        
        let mean = values.reduce(0.0, +) / Float(values.count)
        let variance = values.reduce(0.0) { result, value in
            result + pow(value - mean, 2)
        } / Float(values.count)
        
        return variance
    }
}

// MARK: - Extensions

extension CoreMLAestheticResult {
    var qualityDescription: String {
        switch aestheticScore {
        case 0.8...1.0: return "Exceptional"
        case 0.6..<0.8: return "High Quality"
        case 0.4..<0.6: return "Good"
        case 0.2..<0.4: return "Fair"
        default: return "Poor"
        }
    }
    
    var recommendations: [String] {
        var suggestions: [String] = []
        
        if isUtility {
            suggestions.append("Consider removing utility images from photo collections")
        }
        
        if aestheticScore < 0.4 {
            suggestions.append("Consider retaking with better composition")
            suggestions.append("Check lighting and exposure")
        } else if aestheticScore < 0.7 {
            suggestions.append("Good photo - minor improvements possible")
        }
        
        return suggestions
    }
}