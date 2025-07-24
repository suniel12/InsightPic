import Foundation
import CoreData
import CoreLocation

@objc(PhotoClusterEntity)
public class PhotoClusterEntity: NSManagedObject {
    
    // MARK: - Computed Properties
    
    var centerLocation: CLLocation? {
        get {
            guard centerLatitude != 0.0 || centerLongitude != 0.0 else { return nil }
            return CLLocation(latitude: centerLatitude, longitude: centerLongitude)
        }
        set {
            if let location = newValue {
                centerLatitude = location.coordinate.latitude
                centerLongitude = location.coordinate.longitude
            } else {
                centerLatitude = 0.0
                centerLongitude = 0.0
            }
        }
    }
    
    var photoArray: [PhotoEntity] {
        let photoSet = photos as? Set<PhotoEntity> ?? []
        return Array(photoSet).sorted { $0.timestamp ?? Date.distantPast < $1.timestamp ?? Date.distantPast }
    }
    
    var bestPhoto: PhotoEntity? {
        return photoArray.max { photo1, photo2 in
            let score1 = photo1.scores?.overall ?? 0.5
            let score2 = photo2.scores?.overall ?? 0.5
            return score1 < score2
        }
    }
    
    // MARK: - Lifecycle
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        if id == nil {
            id = UUID()
        }
        
        if createdAt == nil {
            createdAt = Date()
        }
    }
    
    // MARK: - Helper Methods
    
    func convertToPhotoCluster() -> PhotoCluster {
        let clusterPhotos = photoArray.map { $0.convertToPhoto() }
        
        return PhotoCluster(
            id: id ?? UUID(),
            photos: clusterPhotos,
            representativeFingerprint: representativeFingerprint ?? Data(),
            createdAt: createdAt ?? Date()
        )
    }
    
    func updateFromPhotoCluster(_ cluster: PhotoCluster) {
        representativeFingerprint = cluster.representativeFingerprint
        createdAt = cluster.createdAt
        
        // Update computed values
        updateComputedValues()
    }
    
    func updateComputedValues() {
        // Update median timestamp
        let timestamps = photoArray.compactMap { $0.timestamp }.sorted()
        if !timestamps.isEmpty {
            let middleIndex = timestamps.count / 2
            medianTimestamp = timestamps[middleIndex]
        }
        
        // Update center location
        let locations = photoArray.compactMap { $0.location }
        if !locations.isEmpty {
            let avgLatitude = locations.map { $0.coordinate.latitude }.reduce(0, +) / Double(locations.count)
            let avgLongitude = locations.map { $0.coordinate.longitude }.reduce(0, +) / Double(locations.count)
            centerLocation = CLLocation(latitude: avgLatitude, longitude: avgLongitude)
        }
    }
    
    func addPhoto(_ photo: PhotoEntity) {
        addToPhotos(photo)
        photo.cluster = self
        photo.clusterId = self.id
        updateComputedValues()
    }
    
    func removePhoto(_ photo: PhotoEntity) {
        removeFromPhotos(photo)
        photo.cluster = nil
        photo.clusterId = nil
        updateComputedValues()
    }
}