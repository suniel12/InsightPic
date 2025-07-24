import Foundation
import CoreData
import CoreLocation

// MARK: - PhotoEntity Extensions

extension PhotoEntity {
    func updateFromPhoto(_ photo: Photo) {
        self.id = photo.id
        self.assetIdentifier = photo.assetIdentifier
        self.timestamp = photo.timestamp
        
        // Location handling
        if let location = photo.location {
            self.locationLatitude = location.coordinate.latitude
            self.locationLongitude = location.coordinate.longitude
        } else {
            self.locationLatitude = 0.0
            self.locationLongitude = 0.0
        }
        
        self.fingerprint = photo.fingerprint
        self.clusterId = photo.clusterId
        
        // Update metadata
        if let existingMetadata = self.metadata {
            existingMetadata.updateFromPhotoMetadata(photo.metadata)
        } else if let context = self.managedObjectContext {
            let metadataEntity = PhotoMetadataEntity(context: context)
            metadataEntity.updateFromPhotoMetadata(photo.metadata)
            self.metadata = metadataEntity
        }
        
        // Update technical quality score
        if let technicalQuality = photo.technicalQuality {
            if let existingTechnical = self.technicalQuality {
                existingTechnical.updateFromTechnicalQualityScore(technicalQuality)
            } else if let context = self.managedObjectContext {
                let technicalEntity = TechnicalQualityScoreEntity(context: context)
                technicalEntity.updateFromTechnicalQualityScore(technicalQuality)
                self.technicalQuality = technicalEntity
            }
        }
        
        // Update face quality score
        if let faceQuality = photo.faceQuality {
            if let existingFace = self.faceQuality {
                existingFace.updateFromFaceQualityScore(faceQuality)
            } else if let context = self.managedObjectContext {
                let faceEntity = FaceQualityScoreEntity(context: context)
                faceEntity.updateFromFaceQualityScore(faceQuality)
                self.faceQuality = faceEntity
            }
        }
        
        // Update overall score
        if let overallScore = photo.overallScore {
            if let existingScore = self.overallScore {
                existingScore.updateFromPhotoScore(overallScore)
            } else if let context = self.managedObjectContext {
                let scoreEntity = PhotoScoreEntity(context: context)
                scoreEntity.updateFromPhotoScore(overallScore)
                self.overallScore = scoreEntity
            }
        }
    }
    
    func convertToPhoto() -> Photo {
        let location: CLLocation?
        if locationLatitude != 0.0 && locationLongitude != 0.0 {
            location = CLLocation(latitude: locationLatitude, longitude: locationLongitude)
        } else {
            location = nil
        }
        
        let metadata = self.metadata?.convertToPhotoMetadata() ?? PhotoMetadata(width: 0, height: 0)
        let technicalQuality = self.technicalQuality?.convertToTechnicalQualityScore()
        let faceQuality = self.faceQuality?.convertToFaceQualityScore()
        let overallScore = self.overallScore?.convertToPhotoScore()
        
        return Photo(
            id: id ?? UUID(),
            assetIdentifier: assetIdentifier ?? "",
            timestamp: timestamp ?? Date(),
            location: location,
            metadata: metadata,
            fingerprint: fingerprint,
            technicalQuality: technicalQuality,
            faceQuality: faceQuality,
            overallScore: overallScore,
            clusterId: clusterId
        )
    }
}

// MARK: - PhotoClusterEntity Extensions

extension PhotoClusterEntity {
    func updateFromPhotoCluster(_ cluster: PhotoCluster) {
        self.id = cluster.id
        self.createdAt = Date() // Use current time for creation
    }
    
    func convertToPhotoCluster() -> PhotoCluster {
        let photos = photoArray.map { $0.convertToPhoto() }
        
        var photoCluster = PhotoCluster()
        for photo in photos {
            photoCluster.add(photo, fingerprint: nil)
        }
        
        return photoCluster
    }
    
    var photoArray: [PhotoEntity] {
        return photos?.allObjects as? [PhotoEntity] ?? []
    }
    
    func addPhoto(_ photo: PhotoEntity) {
        photo.cluster = self
    }
    
    func removePhoto(_ photo: PhotoEntity) {
        photo.cluster = nil
    }
}

// MARK: - PhotoMetadataEntity Extensions

extension PhotoMetadataEntity {
    func updateFromPhotoMetadata(_ metadata: PhotoMetadata) {
        self.width = Int32(metadata.width)
        self.height = Int32(metadata.height)
        self.cameraMake = nil  // Not used in PhotoMetadata struct
        self.cameraModel = metadata.cameraModel
        self.focalLength = metadata.focalLength ?? 0.0
        self.aperture = metadata.fNumber ?? 0.0
        self.shutterSpeed = metadata.exposureTime ?? 0.0
        self.iso = Int32(metadata.iso ?? 0)
    }
    
    func convertToPhotoMetadata() -> PhotoMetadata {
        return PhotoMetadata(
            width: Int(width),
            height: Int(height),
            cameraModel: cameraModel,
            lensModel: nil,  // Not stored in Core Data model
            focalLength: focalLength > 0 ? focalLength : nil,
            fNumber: aperture > 0 ? aperture : nil,
            exposureTime: shutterSpeed > 0 ? shutterSpeed : nil,
            iso: iso > 0 ? Int(iso) : nil,
            altitude: nil  // Not stored in Core Data model
        )
    }
}

// MARK: - TechnicalQualityScoreEntity Extensions

extension TechnicalQualityScoreEntity {
    func updateFromTechnicalQualityScore(_ score: TechnicalQualityScore) {
        self.sharpness = score.sharpness
        self.exposure = score.exposure
        self.composition = score.composition
        self.overall = score.overall
    }
    
    func convertToTechnicalQualityScore() -> TechnicalQualityScore {
        return TechnicalQualityScore(
            sharpness: sharpness,
            exposure: exposure,
            composition: composition,
            overall: overall
        )
    }
}

// MARK: - FaceQualityScoreEntity Extensions

extension FaceQualityScoreEntity {
    func updateFromFaceQualityScore(_ score: FaceQualityScore) {
        self.faceCount = Int32(score.faceCount)
        self.eyesOpen = score.eyesOpen ? 1.0 : 0.0
        self.smiling = score.goodExpressions ? 1.0 : 0.0
        self.faceSize = score.optimalSizes ? 1.0 : 0.0
        self.faceAngle = 0.5 // Default value
        self.overall = score.compositeScore
    }
    
    func convertToFaceQualityScore() -> FaceQualityScore {
        return FaceQualityScore(
            faceCount: Int(faceCount),
            averageScore: overall,
            eyesOpen: eyesOpen > 0.5,
            goodExpressions: smiling > 0.5,
            optimalSizes: faceSize > 0.5
        )
    }
}

// MARK: - PhotoScoreEntity Extensions

extension PhotoScoreEntity {
    func updateFromPhotoScore(_ score: PhotoScore) {
        self.technical = score.technical
        self.faces = score.faces
        self.context = score.context
        self.overall = score.overall
    }
    
    func convertToPhotoScore() -> PhotoScore {
        return PhotoScore(
            technical: technical,
            faces: faces,
            context: context,
            overall: overall,
            calculatedAt: Date()
        )
    }
}