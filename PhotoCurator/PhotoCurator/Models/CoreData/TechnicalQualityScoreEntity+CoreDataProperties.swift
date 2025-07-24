import Foundation
import CoreData

extension TechnicalQualityScoreEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TechnicalQualityScoreEntity> {
        return NSFetchRequest<TechnicalQualityScoreEntity>(entityName: "TechnicalQualityScoreEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var sharpness: Float
    @NSManaged public var exposure: Float
    @NSManaged public var composition: Float
    @NSManaged public var overall: Float
    @NSManaged public var photoScore: PhotoScoreEntity?

}