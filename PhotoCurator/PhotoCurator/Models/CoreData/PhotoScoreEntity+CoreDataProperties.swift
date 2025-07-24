import Foundation
import CoreData

extension PhotoScoreEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoScoreEntity> {
        return NSFetchRequest<PhotoScoreEntity>(entityName: "PhotoScoreEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var technical: Float
    @NSManaged public var faces: Float
    @NSManaged public var context: Float
    @NSManaged public var overall: Float
    @NSManaged public var calculatedAt: Date?
    @NSManaged public var photo: PhotoEntity?
    @NSManaged public var technicalQuality: TechnicalQualityScoreEntity?
    @NSManaged public var faceQuality: FaceQualityScoreEntity?

}