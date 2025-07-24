import Foundation
import CoreData
import CoreLocation

@objc(PhotoEntity)
public class PhotoEntity: NSManagedObject {
    
    // MARK: - Computed Properties
    
    var location: CLLocation? {
        get {
            guard latitude != 0.0 || longitude != 0.0 else { return nil }
            return CLLocation(latitude: latitude, longitude: longitude)
        }
        set {
            if let location = newValue {
                latitude = location.coordinate.latitude
                longitude = location.coordinate.longitude
            } else {
                latitude = 0.0
                longitude = 0.0
            }
        }
    }
    
    // MARK: - Lifecycle
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        if id == nil {
            id = UUID()
        }
        
        if timestamp == nil {
            timestamp = Date()
        }
    }
    
    // MARK: - Helper Methods
    
    func convertToPhoto() -> Photo {
        let photoMetadata = metadata?.convertToPhotoMetadata() ?? PhotoMetadata(
            width: 0,
            height: 0,
            cameraModel: nil,
            lensModel: nil,
            focalLength: nil,
            fNumber: nil,
            exposureTime: nil,
            iso: nil,
            altitude: nil
        )
        
        return Photo(
            id: id ?? UUID(),
            assetIdentifier: assetIdentifier ?? "",
            timestamp: timestamp ?? Date(),
            location: location,
            metadata: photoMetadata,
            fingerprint: fingerprint,
            technicalQuality: scores?.technicalQuality?.convertToTechnicalQualityScore(),
            faceQuality: scores?.faceQuality?.convertToFaceQualityScore(),
            overallScore: scores?.convertToPhotoScore(),
            clusterId: clusterId
        )
    }
    
    func updateFromPhoto(_ photo: Photo) {
        assetIdentifier = photo.assetIdentifier
        timestamp = photo.timestamp
        location = photo.location
        fingerprint = photo.fingerprint
        clusterId = photo.clusterId
        
        // Update or create metadata
        if metadata == nil {
            metadata = PhotoMetadataEntity(context: managedObjectContext!)
        }
        metadata?.updateFromPhotoMetadata(photo.metadata)
        
        // Update or create scores
        if let photoScore = photo.overallScore {
            if scores == nil {
                scores = PhotoScoreEntity(context: managedObjectContext!)
            }
            scores?.updateFromPhotoScore(photoScore)
        }
        
        // Update technical quality
        if let techQuality = photo.technicalQuality {
            if scores?.technicalQuality == nil {
                scores?.technicalQuality = TechnicalQualityScoreEntity(context: managedObjectContext!)
            }
            scores?.technicalQuality?.updateFromTechnicalQualityScore(techQuality)
        }
        
        // Update face quality
        if let faceQuality = photo.faceQuality {
            if scores?.faceQuality == nil {
                scores?.faceQuality = FaceQualityScoreEntity(context: managedObjectContext!)
            }
            scores?.faceQuality?.updateFromFaceQualityScore(faceQuality)
        }
    }
}