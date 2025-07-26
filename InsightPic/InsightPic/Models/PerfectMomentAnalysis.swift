import Foundation
import Vision
import UIKit
import CoreGraphics

// MARK: - Perfect Moment Face Analysis Data Structures

struct FaceQualityData {
    let photo: Photo
    let boundingBox: CGRect
    let landmarks: VNFaceLandmarks2D?
    let captureQuality: Float           // From VNDetectFaceCaptureQualityRequest
    let eyeState: EyeState
    let smileQuality: SmileQuality
    let faceAngle: FaceAngle
    let sharpness: Float
    let overallScore: Float
    
    init(photo: Photo,
         boundingBox: CGRect,
         landmarks: VNFaceLandmarks2D? = nil,
         captureQuality: Float,
         eyeState: EyeState,
         smileQuality: SmileQuality,
         faceAngle: FaceAngle,
         sharpness: Float,
         overallScore: Float) {
        self.photo = photo
        self.boundingBox = boundingBox
        self.landmarks = landmarks
        self.captureQuality = captureQuality
        self.eyeState = eyeState
        self.smileQuality = smileQuality
        self.faceAngle = faceAngle
        self.sharpness = sharpness
        self.overallScore = overallScore
    }
    
    /// Quality-based comparison for face selection
    var qualityRank: Float {
        // Weighted score combining all quality metrics
        let eyeScore: Float = eyeState.bothOpen ? 1.0 : 0.0
        let angleScore: Float = faceAngle.isOptimal ? 1.0 : 0.5
        
        let captureComponent = captureQuality * 0.3
        let eyeComponent = eyeScore * 0.25
        let smileComponent = smileQuality.overallQuality * 0.2
        let sharpnessComponent = sharpness * 0.15
        let angleComponent = angleScore * 0.1
        
        return captureComponent + eyeComponent + smileComponent + sharpnessComponent + angleComponent
    }
    
    /// Issues identified with this face
    var identifiedIssues: [FaceIssue] {
        var issues: [FaceIssue] = []
        
        if !eyeState.bothOpen {
            issues.append(.eyesClosed)
        }
        
        if smileQuality.overallQuality < 0.5 {
            issues.append(.poorExpression)
        }
        
        if !faceAngle.isOptimal {
            issues.append(.unflatteringAngle)
        }
        
        if sharpness < 0.6 {
            issues.append(.blurredFace)
        }
        
        if captureQuality < 0.5 {
            issues.append(.awkwardPose)
        }
        
        return issues.isEmpty ? [.none] : issues
    }
    
    /// Primary issue for this face (highest severity)
    var primaryIssue: FaceIssue {
        return identifiedIssues.max(by: { $0.severity < $1.severity }) ?? .none
    }
}

struct EyeState {
    let leftOpen: Bool
    let rightOpen: Bool
    let confidence: Float
    
    var bothOpen: Bool { leftOpen && rightOpen }
    var eitherOpen: Bool { leftOpen || rightOpen }
    
    init(leftOpen: Bool, rightOpen: Bool, confidence: Float) {
        self.leftOpen = leftOpen
        self.rightOpen = rightOpen
        self.confidence = max(0.0, min(1.0, confidence))
    }
    
    static let closedEyes = EyeState(leftOpen: false, rightOpen: false, confidence: 1.0)
    static let openEyes = EyeState(leftOpen: true, rightOpen: true, confidence: 1.0)
}

struct SmileQuality {
    let intensity: Float          // 0.0 = no smile, 1.0 = big smile
    let naturalness: Float        // 0.0 = forced, 1.0 = natural
    let confidence: Float         // Detection confidence
    
    init(intensity: Float, naturalness: Float, confidence: Float) {
        self.intensity = max(0.0, min(1.0, intensity))
        self.naturalness = max(0.0, min(1.0, naturalness))
        self.confidence = max(0.0, min(1.0, confidence))
    }
    
    /// Overall smile quality combining intensity and naturalness
    var overallQuality: Float {
        // Weight naturalness higher than intensity for better results
        return (intensity * 0.4) + (naturalness * 0.6)
    }
    
    var isGoodSmile: Bool {
        return overallQuality > 0.6 && confidence > 0.5
    }
    
    static let noSmile = SmileQuality(intensity: 0.0, naturalness: 0.5, confidence: 1.0)
    static let naturalSmile = SmileQuality(intensity: 0.8, naturalness: 0.9, confidence: 0.9)
}

struct FaceAngle {
    let pitch: Float              // Head up/down tilt (-90 to 90 degrees)
    let yaw: Float                // Head left/right turn (-90 to 90 degrees)  
    let roll: Float               // Head side tilt (-180 to 180 degrees)
    
    init(pitch: Float, yaw: Float, roll: Float) {
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
    }
    
    /// Whether the face angle is optimal for compositing
    var isOptimal: Bool {
        return abs(pitch) < 15 && abs(yaw) < 20 && abs(roll) < 10
    }
    
    /// Whether faces can be aligned for compositing
    func isCompatibleForAlignment(with other: FaceAngle) -> Bool {
        let pitchDiff = abs(pitch - other.pitch)
        let yawDiff = abs(yaw - other.yaw)
        let rollDiff = abs(roll - other.roll)
        
        // Allow reasonable differences for alignment
        return pitchDiff < 25 && yawDiff < 30 && rollDiff < 20
    }
    
    static let frontal = FaceAngle(pitch: 0, yaw: 0, roll: 0)
}

// MARK: - Cluster-Wide Analysis Structures

struct ClusterFaceAnalysis {
    let clusterID: UUID
    let personAnalyses: [PersonID: PersonFaceQualityAnalysis]
    let basePhotoCandidate: PhotoCandidate
    let overallImprovementPotential: Float
    
    init(clusterID: UUID,
         personAnalyses: [PersonID: PersonFaceQualityAnalysis],
         basePhotoCandidate: PhotoCandidate,
         overallImprovementPotential: Float) {
        self.clusterID = clusterID
        self.personAnalyses = personAnalyses
        self.basePhotoCandidate = basePhotoCandidate
        self.overallImprovementPotential = max(0.0, min(1.0, overallImprovementPotential))
    }
    
    /// Total number of people detected in cluster
    var personCount: Int {
        return personAnalyses.count
    }
    
    /// People who would benefit from face replacement
    var peopleWithImprovements: [PersonID] {
        return personAnalyses.compactMap { (personID, analysis) in
            analysis.improvementPotential > 0.3 ? personID : nil
        }
    }
    
    /// Estimated processing time based on complexity
    var estimatedProcessingTime: TimeInterval {
        let basetime: TimeInterval = 5.0
        let personFactor = Double(personCount) * 2.0
        let improvementFactor = Double(peopleWithImprovements.count) * 3.0
        
        return basetime + personFactor + improvementFactor
    }
}

struct PersonFaceQualityAnalysis {
    let personID: PersonID
    let allFaces: [FaceQualityData]
    let bestFace: FaceQualityData
    let worstFace: FaceQualityData
    let improvementPotential: Float
    
    init(personID: PersonID,
         allFaces: [FaceQualityData],
         bestFace: FaceQualityData,
         worstFace: FaceQualityData,
         improvementPotential: Float) {
        self.personID = personID
        self.allFaces = allFaces
        self.bestFace = bestFace
        self.worstFace = worstFace
        self.improvementPotential = max(0.0, min(1.0, improvementPotential))
    }
    
    /// Quality improvement if best face replaces worst face
    var qualityGain: Float {
        return bestFace.qualityRank - worstFace.qualityRank
    }
    
    /// Whether this person would benefit from Perfect Moment
    var shouldReplace: Bool {
        return improvementPotential > 0.4 && qualityGain > 0.2
    }
    
    /// Issues that would be fixed by replacement
    var issuesFixed: [FaceIssue] {
        let worstIssues = Set(worstFace.identifiedIssues)
        let bestIssues = Set(bestFace.identifiedIssues)
        return Array(worstIssues.subtracting(bestIssues))
    }
}

struct PhotoCandidate {
    let photo: Photo
    let image: UIImage
    let suitabilityScore: Float       // How good as base photo (0-1)
    let aestheticScore: Float         // Visual appeal score
    let technicalQuality: Float       // Image quality metrics
    
    init(photo: Photo,
         image: UIImage,
         suitabilityScore: Float,
         aestheticScore: Float,
         technicalQuality: Float) {
        self.photo = photo
        self.image = image
        self.suitabilityScore = max(0.0, min(1.0, suitabilityScore))
        self.aestheticScore = max(0.0, min(1.0, aestheticScore))
        self.technicalQuality = max(0.0, min(1.0, technicalQuality))
    }
    
    /// Overall score for base photo selection
    var overallScore: Float {
        return (suitabilityScore * 0.4) + (aestheticScore * 0.3) + (technicalQuality * 0.3)
    }
}

// MARK: - Person Matching and Replacement

typealias PersonID = String

struct PersonFaceReplacement {
    let personID: PersonID
    let sourceFace: FaceQualityData      // Best face to use
    let destinationPhoto: Photo          // Photo receiving the replacement
    let destinationFace: FaceQualityData // Face being replaced
    let improvementType: ImprovementType
    let confidence: Float                // Confidence in replacement success
    
    init(personID: PersonID,
         sourceFace: FaceQualityData,
         destinationPhoto: Photo,
         destinationFace: FaceQualityData,
         improvementType: ImprovementType,
         confidence: Float) {
        self.personID = personID
        self.sourceFace = sourceFace
        self.destinationPhoto = destinationPhoto
        self.destinationFace = destinationFace
        self.improvementType = improvementType
        self.confidence = max(0.0, min(1.0, confidence))
    }
    
    /// Whether the replacement is technically feasible
    var isFeasible: Bool {
        return sourceFace.faceAngle.isCompatibleForAlignment(with: destinationFace.faceAngle) &&
               confidence > 0.5 &&
               sourceFace.qualityRank > destinationFace.qualityRank
    }
    
    /// Expected quality improvement from replacement
    var expectedImprovement: Float {
        return sourceFace.qualityRank - destinationFace.qualityRank
    }
}

// MARK: - Vision Framework Integration Helpers

extension FaceQualityData {
    /// Create from Vision Framework face observation
    static func from(
        photo: Photo,
        faceObservation: VNFaceObservation,
        landmarks: VNFaceLandmarks2D?,
        captureQuality: Float,
        imageSize: CGSize
    ) -> FaceQualityData {
        
        // Calculate eye state from landmarks
        let eyeState = EyeState.from(landmarks: landmarks)
        
        // Calculate smile quality from landmarks
        let smileQuality = SmileQuality.from(landmarks: landmarks)
        
        // Extract face angle from observation
        let faceAngle = FaceAngle.from(faceObservation: faceObservation)
        
        // Estimate sharpness from capture quality and face size
        let faceArea = faceObservation.boundingBox.width * faceObservation.boundingBox.height
        let sharpness = min(1.0, captureQuality + Float(faceArea * 2.0))
        
        // Calculate overall score
        let overallScore = (captureQuality * 0.4) +
                          (eyeState.bothOpen ? 0.2 : 0.0) +
                          (smileQuality.overallQuality * 0.2) +
                          (faceAngle.isOptimal ? 0.2 : 0.1)
        
        return FaceQualityData(
            photo: photo,
            boundingBox: faceObservation.boundingBox,
            landmarks: landmarks,
            captureQuality: captureQuality,
            eyeState: eyeState,
            smileQuality: smileQuality,
            faceAngle: faceAngle,
            sharpness: sharpness,
            overallScore: overallScore
        )
    }
}

extension EyeState {
    /// Create from Vision Framework landmarks
    static func from(landmarks: VNFaceLandmarks2D?) -> EyeState {
        guard let landmarks = landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else {
            return EyeState(leftOpen: true, rightOpen: true, confidence: 0.5)
        }
        
        let leftEAR = calculateEyeAspectRatio(leftEye.normalizedPoints)
        let rightEAR = calculateEyeAspectRatio(rightEye.normalizedPoints)
        
        let eyeOpenThreshold: Float = 0.25
        
        return EyeState(
            leftOpen: leftEAR > eyeOpenThreshold,
            rightOpen: rightEAR > eyeOpenThreshold,
            confidence: min(leftEAR, rightEAR) / eyeOpenThreshold
        )
    }
    
    /// Calculate Eye Aspect Ratio for openness detection
    private static func calculateEyeAspectRatio(_ points: [CGPoint]) -> Float {
        guard points.count >= 6 else { return 0.5 }
        
        // Calculate vertical distances
        let vertical1 = distance(points[1], points[5])
        let vertical2 = distance(points[2], points[4])
        
        // Calculate horizontal distance
        let horizontal = distance(points[0], points[3])
        
        // Eye Aspect Ratio formula
        return Float((vertical1 + vertical2) / (2.0 * horizontal))
    }
    
    private static func distance(_ p1: CGPoint, _ p2: CGPoint) -> Double {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
}

extension SmileQuality {
    /// Create from Vision Framework landmarks
    static func from(landmarks: VNFaceLandmarks2D?) -> SmileQuality {
        guard let landmarks = landmarks,
              let outerLips = landmarks.outerLips else {
            return SmileQuality(intensity: 0.5, naturalness: 0.5, confidence: 0.3)
        }
        
        let lipPoints = outerLips.normalizedPoints
        let curvature = calculateLipCurvature(lipPoints)
        let symmetry = calculateLipSymmetry(lipPoints)
        
        return SmileQuality(
            intensity: curvature,
            naturalness: symmetry,
            confidence: 0.7
        )
    }
    
    /// Calculate lip curvature for smile intensity
    private static func calculateLipCurvature(_ points: [CGPoint]) -> Float {
        guard points.count >= 12 else { return 0.0 }
        
        let leftCorner = points[0]
        let rightCorner = points[6]
        let topCenter = points[3]
        let bottomCenter = points[9]
        
        let mouthCenterY = (topCenter.y + bottomCenter.y) / 2
        let avgCornerY = (leftCorner.y + rightCorner.y) / 2
        
        // Positive curvature indicates upward curve (smile)
        let curvature = Float(max(0, (avgCornerY - mouthCenterY) * 20))
        return min(1.0, curvature)
    }
    
    /// Calculate lip symmetry for naturalness
    private static func calculateLipSymmetry(_ points: [CGPoint]) -> Float {
        guard points.count >= 12 else { return 0.5 }
        
        let leftCorner = points[0]
        let rightCorner = points[6]
        let center = points[3]
        
        let leftDistance = abs(leftCorner.x - center.x)
        let rightDistance = abs(rightCorner.x - center.x)
        
        let symmetry = 1.0 - abs(leftDistance - rightDistance) / max(leftDistance, rightDistance)
        return Float(max(0.0, min(1.0, symmetry)))
    }
}

extension FaceAngle {
    /// Create from Vision Framework face observation
    static func from(faceObservation: VNFaceObservation) -> FaceAngle {
        let pitch = faceObservation.pitch?.floatValue ?? 0.0
        let yaw = faceObservation.yaw?.floatValue ?? 0.0
        let roll = faceObservation.roll?.floatValue ?? 0.0
        
        return FaceAngle(pitch: pitch, yaw: yaw, roll: roll)
    }
}