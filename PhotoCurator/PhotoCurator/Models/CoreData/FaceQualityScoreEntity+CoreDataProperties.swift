import Foundation
import CoreData

extension FaceQualityScoreEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FaceQualityScoreEntity> {
        return NSFetchRequest<FaceQualityScoreEntity>(entityName: "FaceQualityScoreEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var faceCount: Int32
    @NSManaged public var averageScore: Float
    @NSManaged public var eyesOpen: Bool
    @NSManaged public var goodExpressions: Bool
    @NSManaged public var optimalSizes: Bool
    @NSManaged public var photoScore: PhotoScoreEntity?

}