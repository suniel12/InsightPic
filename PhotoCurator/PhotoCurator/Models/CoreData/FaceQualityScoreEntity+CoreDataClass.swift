import Foundation
import CoreData

@objc(FaceQualityScoreEntity)
public class FaceQualityScoreEntity: NSManagedObject {
    
    // MARK: - Lifecycle
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        if id == nil {
            id = UUID()
        }
    }
    
    // MARK: - Helper Methods
    
    func convertToFaceQualityScore() -> FaceQualityScore {
        return FaceQualityScore(
            faceCount: Int(faceCount),
            averageScore: averageScore,
            eyesOpen: eyesOpen,
            goodExpressions: goodExpressions,
            optimalSizes: optimalSizes
        )
    }
    
    func updateFromFaceQualityScore(_ score: FaceQualityScore) {
        faceCount = Int32(score.faceCount)
        averageScore = score.averageScore
        eyesOpen = score.eyesOpen
        goodExpressions = score.goodExpressions
        optimalSizes = score.optimalSizes
    }
}