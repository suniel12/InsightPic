import Foundation
import CoreData

@objc(PhotoScoreEntity)
public class PhotoScoreEntity: NSManagedObject {
    
    // MARK: - Lifecycle
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        if id == nil {
            id = UUID()
        }
        
        if calculatedAt == nil {
            calculatedAt = Date()
        }
    }
    
    // MARK: - Helper Methods
    
    func convertToPhotoScore() -> PhotoScore {
        return PhotoScore(
            technical: technical,
            faces: faces,
            context: context,
            overall: overall,
            calculatedAt: calculatedAt ?? Date()
        )
    }
    
    func updateFromPhotoScore(_ score: PhotoScore) {
        technical = score.technical
        faces = score.faces
        context = score.context
        overall = score.overall
        calculatedAt = score.calculatedAt
    }
}