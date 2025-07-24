import Foundation
import CoreData

extension PhotoClusterEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoClusterEntity> {
        return NSFetchRequest<PhotoClusterEntity>(entityName: "PhotoClusterEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var representativeFingerprint: Data?
    @NSManaged public var createdAt: Date?
    @NSManaged public var medianTimestamp: Date?
    @NSManaged public var centerLatitude: Double
    @NSManaged public var centerLongitude: Double
    @NSManaged public var photos: NSSet?

}

// MARK: Generated accessors for photos
extension PhotoClusterEntity {

    @objc(addPhotosObject:)
    @NSManaged public func addToPhotos(_ value: PhotoEntity)

    @objc(removePhotosObject:)
    @NSManaged public func removeFromPhotos(_ value: PhotoEntity)

    @objc(addPhotos:)
    @NSManaged public func addToPhotos(_ values: NSSet)

    @objc(removePhotos:)
    @NSManaged public func removeFromPhotos(_ values: NSSet)

}