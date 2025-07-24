import Foundation
import CoreData

extension PhotoMetadataEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoMetadataEntity> {
        return NSFetchRequest<PhotoMetadataEntity>(entityName: "PhotoMetadataEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var width: Int32
    @NSManaged public var height: Int32
    @NSManaged public var cameraModel: String?
    @NSManaged public var lensModel: String?
    @NSManaged public var focalLength: Double
    @NSManaged public var fNumber: Double
    @NSManaged public var exposureTime: Double
    @NSManaged public var iso: Int32
    @NSManaged public var altitude: Double
    @NSManaged public var photo: PhotoEntity?

}