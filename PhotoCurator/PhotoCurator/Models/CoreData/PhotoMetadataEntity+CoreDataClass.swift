import Foundation
import CoreData

@objc(PhotoMetadataEntity)
public class PhotoMetadataEntity: NSManagedObject {
    
    // MARK: - Lifecycle
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        if id == nil {
            id = UUID()
        }
    }
    
    // MARK: - Helper Methods
    
    func convertToPhotoMetadata() -> PhotoMetadata {
        return PhotoMetadata(
            width: Int(width),
            height: Int(height),
            cameraModel: cameraModel,
            lensModel: lensModel,
            focalLength: focalLength > 0 ? focalLength : nil,
            fNumber: fNumber > 0 ? fNumber : nil,
            exposureTime: exposureTime > 0 ? exposureTime : nil,
            iso: iso > 0 ? Int(iso) : nil,
            altitude: altitude != 0 ? altitude : nil
        )
    }
    
    func updateFromPhotoMetadata(_ metadata: PhotoMetadata) {
        width = Int32(metadata.width)
        height = Int32(metadata.height)
        cameraModel = metadata.cameraModel
        lensModel = metadata.lensModel
        focalLength = metadata.focalLength ?? 0
        fNumber = metadata.fNumber ?? 0
        exposureTime = metadata.exposureTime ?? 0
        iso = Int32(metadata.iso ?? 0)
        altitude = metadata.altitude ?? 0
    }
}