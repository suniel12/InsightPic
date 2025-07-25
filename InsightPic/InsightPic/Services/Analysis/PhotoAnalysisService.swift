import Foundation
import Vision
import UIKit
import CoreImage
import VideoToolbox

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
    
    // Enhanced analysis data
    let aestheticAnalysis: AestheticAnalysis?
    let saliencyAnalysis: SaliencyAnalysis?
    let dominantColors: [UIColor]?
    let sceneConfidence: Float
    
    var overallScore: Double {
        // Enhanced weighted scoring including aesthetic analysis
        var baseScore = (qualityScore * 0.25 + sharpnessScore * 0.2 + exposureScore * 0.15 + compositionScore * 0.15)
        
        // Add Vision's aesthetic score if available (normalized from -1,1 to 0,1)
        if let aesthetics = aestheticAnalysis {
            let normalizedAesthetic = Double((aesthetics.overallScore + 1.0) / 2.0)
            baseScore += normalizedAesthetic * 0.2
        } else {
            baseScore += aestheticScore * 0.1
        }
        
        // Composition bonus from saliency analysis
        if let saliency = saliencyAnalysis {
            baseScore += Double(saliency.compositionScore) * 0.05
        }
        
        return min(1.0, baseScore)
    }
}

struct FaceAnalysis {
    let boundingBox: CGRect
    let confidence: Float
    let faceQuality: Double // 0.0 to 1.0 from VNDetectFaceCaptureQualityRequest
    let isSmiling: Bool?
    let eyesOpen: Bool?
    let landmarks: VNFaceLandmarks2D?
    let pose: FacePose?
    let recognitionID: String? // For person identification
}

struct FacePose {
    let pitch: Float? // Head up/down tilt
    let yaw: Float?   // Head left/right turn  
    let roll: Float?  // Head side tilt
}

struct ObjectAnalysis {
    let identifier: String
    let confidence: Float
    let boundingBox: CGRect
}

struct AestheticAnalysis {
    let overallScore: Float      // -1.0 to 1.0 (higher is more aesthetic)
    let isUtility: Bool          // True if utility image (screenshot, document, etc.)
    let confidenceLevel: Float   // Confidence in the aesthetic assessment
}

struct SaliencyAnalysis {
    let attentionHeatmap: CGImage?     // Attention-based saliency heatmap
    let salientObjects: [CGRect]       // Bounding boxes of salient regions
    let focusPoints: [CGPoint]         // Key focal points in the image
    let compositionScore: Float        // Derived composition quality (0-1)
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
            
            // Enhanced face detection with landmarks and quality
            let faceRequest = VNDetectFaceRectanglesRequest()
            let landmarksRequest = VNDetectFaceLandmarksRequest()
            let qualityRequest = VNDetectFaceCaptureQualityRequest()
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            
            do {
                try handler.perform([faceRequest, landmarksRequest, qualityRequest])
                
                guard let faceObservations = faceRequest.results as? [VNFaceObservation],
                      let landmarkObservations = landmarksRequest.results as? [VNFaceObservation],
                      let qualityObservations = qualityRequest.results as? [VNFaceObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                var enhancedFaces: [FaceAnalysis] = []
                
                for faceObs in faceObservations {
                    // Find corresponding landmarks and quality for this face
                    let landmarks = landmarkObservations.first { $0.boundingBox == faceObs.boundingBox }?.landmarks
                    let quality = qualityObservations.first { $0.boundingBox == faceObs.boundingBox }?.faceCaptureQuality ?? 0.0
                    
                    // Extract pose information if available
                    var pose: FacePose? = nil
                    if let pitch = faceObs.pitch?.floatValue,
                       let yaw = faceObs.yaw?.floatValue,
                       let roll = faceObs.roll?.floatValue {
                        pose = FacePose(pitch: pitch, yaw: yaw, roll: roll)
                    }
                    
                    // Analyze smile and eye state from landmarks
                    var isSmiling: Bool? = nil
                    var eyesOpen: Bool? = nil
                    
                    if let landmarks = landmarks {
                        isSmiling = detectSmile(from: landmarks)
                        eyesOpen = detectEyesOpen(from: landmarks)
                    }
                    
                    let faceAnalysis = FaceAnalysis(
                        boundingBox: faceObs.boundingBox,
                        confidence: faceObs.confidence,
                        faceQuality: Double(quality),
                        isSmiling: isSmiling,
                        eyesOpen: eyesOpen,
                        landmarks: landmarks,
                        pose: pose,
                        recognitionID: nil // Will be filled by person recognition
                    )
                    
                    enhancedFaces.append(faceAnalysis)
                }
                
                continuation.resume(returning: enhancedFaces)
                
            } catch {
                print("Face analysis error: \(error)")
                continuation.resume(returning: [])
            }
        }
    }
    
    private func detectSmile(from landmarks: VNFaceLandmarks2D) -> Bool {
        // Basic smile detection using mouth corner positions
        guard let outerLips = landmarks.outerLips else { return false }
        let points = outerLips.normalizedPoints
        
        if points.count >= 12 {
            let leftCorner = points[0]
            let rightCorner = points[6]
            let topCenter = points[3]
            let bottomCenter = points[9]
            
            // Simple heuristic: if mouth corners are higher than mouth center, likely smiling
            let mouthCenterY = (topCenter.y + bottomCenter.y) / 2
            let avgCornerY = (leftCorner.y + rightCorner.y) / 2
            
            return avgCornerY > mouthCenterY + 0.005 // Small threshold
        }
        
        return false
    }
    
    private func detectEyesOpen(from landmarks: VNFaceLandmarks2D) -> Bool {
        // Basic eye openness detection using eye region heights
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else { return true }
        
        let leftPoints = leftEye.normalizedPoints
        let rightPoints = rightEye.normalizedPoints
        
        if leftPoints.count >= 6 && rightPoints.count >= 6 {
            // Calculate eye openness ratio for both eyes
            let leftHeight = abs(leftPoints[1].y - leftPoints[4].y)
            let rightHeight = abs(rightPoints[1].y - rightPoints[4].y)
            
            // If both eyes have reasonable height, consider them open
            return leftHeight > 0.005 && rightHeight > 0.005
        }
        
        return true // Default to eyes open if can't determine
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
                
                // Take all classifications with reasonable confidence for enhanced categorization
                // Lowered threshold and removed limit to capture more categories
                let filteredObservations = observations.filter { $0.confidence > 0.1 }.prefix(20)
                
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
    
    func analyzePhoto(_ photo: Photo, image: UIImage) async throws -> PhotoAnalysisResult {
        // Perform all analyses concurrently for better performance
        async let faces = analyzeFaces(image: image)
        async let objects = analyzeObjects(image: image)
        async let aesthetics = analyzeAesthetics(image: image) // Returns AestheticAnalysis?
        async let saliency = analyzeSaliency(image: image)
        
        // Calculate traditional quality metrics
        let sharpness = await analyzeSharpness(image: image)
        let exposure = await analyzeExposure(image: image)
        let composition = await analyzeComposition(image: image)
        let basicAesthetic = await analyzeAesthetics(image: image, faces: await faces, objects: await objects)
        let overall = calculateOverallQuality(
            sharpness: sharpness,
            exposure: exposure,
            composition: composition,
            faces: await faces,
            objects: await objects
        )
        
        // Extract scene confidence from objects
        let sceneConfidence = (await objects).first?.confidence ?? 0.0
        
        // Create comprehensive analysis result
        return PhotoAnalysisResult(
            photoId: photo.id,
            assetIdentifier: photo.assetIdentifier,
            qualityScore: overall,
            sharpnessScore: sharpness,
            exposureScore: exposure,
            compositionScore: composition,
            faces: await faces,
            objects: await objects,
            aestheticScore: basicAesthetic,
            timestamp: Date(),
            aestheticAnalysis: await aesthetics,
            saliencyAnalysis: await saliency,
            dominantColors: extractDominantColors(from: image),
            sceneConfidence: sceneConfidence
        )
    }
    
    private func analyzeAesthetics(image: UIImage) async -> AestheticAnalysis? {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: nil)
                return
            }
            
            // Check if aesthetic analysis is available (iOS 15+)
            if #available(iOS 15.0, *) {
                let request = VNCalculateImageAestheticsScoresRequest { request, error in
                    guard let results = request.results as? [VNImageAestheticsScoresObservation],
                          let result = results.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let analysis = AestheticAnalysis(
                        overallScore: result.overallScore,
                        isUtility: result.isUtility,
                        confidenceLevel: 1.0 // Vision doesn't provide confidence for aesthetics
                    )
                    
                    continuation.resume(returning: analysis)
                }
                
                let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
                try? handler.perform([request])
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func analyzeSaliency(image: UIImage) async -> SaliencyAnalysis? {
        return await withCheckedContinuation { continuation in
            guard let ciImage = CIImage(image: image) else {
                continuation.resume(returning: nil)
                return
            }
            
            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                guard let results = request.results as? [VNSaliencyImageObservation],
                      let result = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Extract salient object bounding boxes
                let salientObjects = result.salientObjects?.map { $0.boundingBox } ?? []
                
                // Calculate focus points from salient regions
                let focusPoints = salientObjects.map { box in
                    CGPoint(x: box.midX, y: box.midY)
                }
                
                // Calculate composition score based on saliency distribution
                let compositionScore = self.calculateCompositionFromSaliency(
                    salientObjects: salientObjects,
                    imageSize: CGSize(width: ciImage.extent.width, height: ciImage.extent.height)
                )
                
                let analysis = SaliencyAnalysis(
                    attentionHeatmap: result.pixelBuffer.createCGImage(),
                    salientObjects: salientObjects,
                    focusPoints: focusPoints,
                    compositionScore: compositionScore
                )
                
                continuation.resume(returning: analysis)
            }
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            try? handler.perform([request])
        }
    }
    
    private func extractDominantColors(from image: UIImage) -> [UIColor]? {
        // Simple dominant color extraction (this could be enhanced with more sophisticated algorithms)
        guard CIImage(image: image) != nil else { return nil }
        
        // For now, return nil - could implement k-means clustering or use Core Image filters
        return nil
    }
    
    private func calculateCompositionFromSaliency(salientObjects: [CGRect], imageSize: CGSize) -> Float {
        guard !salientObjects.isEmpty else { return 0.5 }
        
        var compositionScore: Float = 0.5
        
        // Rule of thirds analysis
        let thirdX = imageSize.width / 3
        let thirdY = imageSize.height / 3
        
        for obj in salientObjects {
            let centerX = obj.midX * imageSize.width
            let centerY = obj.midY * imageSize.height
            
            // Check if object center aligns with rule of thirds
            let xAlignment = min(abs(centerX - thirdX), abs(centerX - 2 * thirdX)) / thirdX
            let yAlignment = min(abs(centerY - thirdY), abs(centerY - 2 * thirdY)) / thirdY
            
            if xAlignment < 0.1 || yAlignment < 0.1 {
                compositionScore += 0.2
            }
        }
        
        return min(1.0, compositionScore)
    }
    
    private func loadImageForAnalysis(photo: Photo) async throws -> UIImage? {
        // Load full resolution image for analysis
        return try await photoLibraryService.getFullResolutionImage(for: photo.assetIdentifier)
    }
}

// MARK: - Helper Extensions

extension CVPixelBuffer {
    func createCGImage() -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(self, options: nil, imageOut: &cgImage)
        return cgImage
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