import Foundation
import CoreData

extension PhotoEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoEntity> {
        return NSFetchRequest<PhotoEntity>(entityName: "PhotoEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var assetIdentifier: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var fingerprint: Data?
    @NSManaged public var clusterId: UUID?
    @NSManaged public var cluster: PhotoClusterEntity?
    @NSManaged public var metadata: PhotoMetadataEntity?
    @NSManaged public var scores: PhotoScoreEntity?

}