import Foundation
import CoreData

@objc(TechnicalQualityScoreEntity)
public class TechnicalQualityScoreEntity: NSManagedObject {
    
    // MARK: - Lifecycle
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        if id == nil {
            id = UUID()
        }
    }
    
    // MARK: - Helper Methods
    
    func convertToTechnicalQualityScore() -> TechnicalQualityScore {
        return TechnicalQualityScore(
            sharpness: sharpness,
            exposure: exposure,
            composition: composition,
            overall: overall
        )
    }
    
    func updateFromTechnicalQualityScore(_ score: TechnicalQualityScore) {
        sharpness = score.sharpness
        exposure = score.exposure
        composition = score.composition
        overall = score.overall
    }
}