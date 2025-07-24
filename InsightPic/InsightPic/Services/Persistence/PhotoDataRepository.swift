import Foundation
import CoreData

// MARK: - Repository Protocol

protocol PhotoDataRepositoryProtocol {
    func savePhoto(_ photo: Photo) async throws
    func savePhotos(_ photos: [Photo]) async throws
    func loadPhotos() async throws -> [Photo]
    func loadPhoto(by id: UUID) async throws -> Photo?
    func loadPhoto(by assetIdentifier: String) async throws -> Photo?
    func deletePhoto(_ photo: Photo) async throws
    func deletePhotos(with assetIdentifiers: [String]) async throws
    func clearAllPhotos() async throws
    
    func saveCluster(_ cluster: PhotoCluster) async throws
    func saveClusters(_ clusters: [PhotoCluster]) async throws
    func loadClusters() async throws -> [PhotoCluster]
    func loadCluster(by id: UUID) async throws -> PhotoCluster?
    func deleteCluster(_ cluster: PhotoCluster) async throws
    func deleteClusters(with ids: [UUID]) async throws
    
    func cleanup() async throws
    func resetDatabase() async throws
}

// MARK: - PhotoDataRepository Implementation

class PhotoDataRepository: PhotoDataRepositoryProtocol {
    private let coreDataStack: CoreDataStack
    
    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }
    
    // MARK: - Photo Operations
    
    func savePhoto(_ photo: Photo) async throws {
        try await coreDataStack.performBackgroundTask { context in
            // Check if photo already exists
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", photo.id as CVarArg)
            fetchRequest.fetchLimit = 1
            
            let existingPhotoEntity = try context.fetch(fetchRequest).first
            let photoEntity = existingPhotoEntity ?? PhotoEntity(context: context)
            
            photoEntity.updateFromPhoto(photo)
        }
    }
    
    func savePhotos(_ photos: [Photo]) async throws {
        try await coreDataStack.performBackgroundTask { context in
            for photo in photos {
                // Check if photo already exists
                let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", photo.id as CVarArg)
                fetchRequest.fetchLimit = 1
                
                let existingPhotoEntity = try context.fetch(fetchRequest).first
                let photoEntity = existingPhotoEntity ?? PhotoEntity(context: context)
                
                photoEntity.updateFromPhoto(photo)
            }
        }
    }
    
    func loadPhotos() async throws -> [Photo] {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PhotoEntity.timestamp, ascending: false)]
            
            let photoEntities = try context.fetch(fetchRequest)
            return photoEntities.map { $0.convertToPhoto() }
        }
    }
    
    func loadPhoto(by id: UUID) async throws -> Photo? {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            fetchRequest.fetchLimit = 1
            
            let photoEntity = try context.fetch(fetchRequest).first
            return photoEntity?.convertToPhoto()
        }
    }
    
    func loadPhoto(by assetIdentifier: String) async throws -> Photo? {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "assetIdentifier == %@", assetIdentifier)
            fetchRequest.fetchLimit = 1
            
            let photoEntity = try context.fetch(fetchRequest).first
            return photoEntity?.convertToPhoto()
        }
    }
    
    func deletePhoto(_ photo: Photo) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", photo.id as CVarArg)
            fetchRequest.fetchLimit = 1
            
            if let photoEntity = try context.fetch(fetchRequest).first {
                context.delete(photoEntity)
            }
        }
    }
    
    func deletePhotos(with assetIdentifiers: [String]) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = PhotoEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "assetIdentifier IN %@", assetIdentifiers)
            
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.coreDataStack.mainContext])
            }
        }
    }
    
    // MARK: - Cluster Operations
    
    func saveCluster(_ cluster: PhotoCluster) async throws {
        try await coreDataStack.performBackgroundTask { context in
            // Check if cluster already exists
            let fetchRequest: NSFetchRequest<PhotoClusterEntity> = PhotoClusterEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", cluster.id as CVarArg)
            fetchRequest.fetchLimit = 1
            
            let existingClusterEntity = try context.fetch(fetchRequest).first
            let clusterEntity = existingClusterEntity ?? PhotoClusterEntity(context: context)
            
            clusterEntity.updateFromPhotoCluster(cluster)
            
            // Update photo relationships
            for photo in cluster.photos {
                let photoFetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
                photoFetchRequest.predicate = NSPredicate(format: "id == %@", photo.id as CVarArg)
                photoFetchRequest.fetchLimit = 1
                
                if let photoEntity = try context.fetch(photoFetchRequest).first {
                    clusterEntity.addPhoto(photoEntity)
                }
            }
        }
    }
    
    func saveClusters(_ clusters: [PhotoCluster]) async throws {
        try await coreDataStack.performBackgroundTask { context in
            for cluster in clusters {
                // Check if cluster already exists
                let fetchRequest: NSFetchRequest<PhotoClusterEntity> = PhotoClusterEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", cluster.id as CVarArg)
                fetchRequest.fetchLimit = 1
                
                let existingClusterEntity = try context.fetch(fetchRequest).first
                let clusterEntity = existingClusterEntity ?? PhotoClusterEntity(context: context)
                
                clusterEntity.updateFromPhotoCluster(cluster)
                
                // Update photo relationships
                for photo in cluster.photos {
                    let photoFetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
                    photoFetchRequest.predicate = NSPredicate(format: "id == %@", photo.id as CVarArg)
                    photoFetchRequest.fetchLimit = 1
                    
                    if let photoEntity = try context.fetch(photoFetchRequest).first {
                        clusterEntity.addPhoto(photoEntity)
                    }
                }
            }
        }
    }
    
    func loadClusters() async throws -> [PhotoCluster] {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoClusterEntity> = PhotoClusterEntity.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PhotoClusterEntity.createdAt, ascending: false)]
            
            let clusterEntities = try context.fetch(fetchRequest)
            return clusterEntities.map { $0.convertToPhotoCluster() }
        }
    }
    
    func loadCluster(by id: UUID) async throws -> PhotoCluster? {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoClusterEntity> = PhotoClusterEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            fetchRequest.fetchLimit = 1
            
            let clusterEntity = try context.fetch(fetchRequest).first
            return clusterEntity?.convertToPhotoCluster()
        }
    }
    
    func deleteCluster(_ cluster: PhotoCluster) async throws {
        try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoClusterEntity> = PhotoClusterEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", cluster.id as CVarArg)
            fetchRequest.fetchLimit = 1
            
            if let clusterEntity = try context.fetch(fetchRequest).first {
                // Remove cluster relationship from photos but don't delete photos
                for photoEntity in clusterEntity.photoArray {
                    clusterEntity.removePhoto(photoEntity)
                }
                
                context.delete(clusterEntity)
            }
        }
    }
    
    func deleteClusters(with ids: [UUID]) async throws {
        try await coreDataStack.performBackgroundTask { context in
            for id in ids {
                let fetchRequest: NSFetchRequest<PhotoClusterEntity> = PhotoClusterEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                fetchRequest.fetchLimit = 1
                
                if let clusterEntity = try context.fetch(fetchRequest).first {
                    // Remove cluster relationship from photos but don't delete photos
                    for photoEntity in clusterEntity.photoArray {
                        clusterEntity.removePhoto(photoEntity)
                    }
                    
                    context.delete(clusterEntity)
                }
            }
        }
    }
    
    // MARK: - Utility Operations
    
    func cleanup() async throws {
        try await coreDataStack.cleanup()
    }
    
    func resetDatabase() async throws {
        try await coreDataStack.resetDatabase()
    }
    
    // MARK: - Advanced Queries
    
    func loadPhotosWithoutClusters() async throws -> [Photo] {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "cluster == nil")
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PhotoEntity.timestamp, ascending: false)]
            
            let photoEntities = try context.fetch(fetchRequest)
            return photoEntities.map { $0.convertToPhoto() }
        }
    }
    
    func loadPhotosWithoutScores() async throws -> [Photo] {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "overallScore == nil")
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PhotoEntity.timestamp, ascending: false)]
            
            let photoEntities = try context.fetch(fetchRequest)
            return photoEntities.map { $0.convertToPhoto() }
        }
    }
    
    func loadPhotosWithoutFingerprints() async throws -> [Photo] {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "fingerprint == nil")
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PhotoEntity.timestamp, ascending: false)]
            
            let photoEntities = try context.fetch(fetchRequest)
            return photoEntities.map { $0.convertToPhoto() }
        }
    }
    
    func countPhotos() async throws -> Int {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoEntity> = PhotoEntity.fetchRequest()
            return try context.count(for: fetchRequest)
        }
    }
    
    func countClusters() async throws -> Int {
        return try await coreDataStack.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<PhotoClusterEntity> = PhotoClusterEntity.fetchRequest()
            return try context.count(for: fetchRequest)
        }
    }
    
    func clearAllPhotos() async throws {
        try await coreDataStack.performBackgroundTask { context in
            // Delete all photos
            let photoFetchRequest: NSFetchRequest<NSFetchRequestResult> = PhotoEntity.fetchRequest()
            let photoBatchDeleteRequest = NSBatchDeleteRequest(fetchRequest: photoFetchRequest)
            try context.execute(photoBatchDeleteRequest)
            
            // Delete all clusters
            let clusterFetchRequest: NSFetchRequest<NSFetchRequestResult> = PhotoClusterEntity.fetchRequest()
            let clusterBatchDeleteRequest = NSBatchDeleteRequest(fetchRequest: clusterFetchRequest)
            try context.execute(clusterBatchDeleteRequest)
            
            // Delete all photo metadata
            let metadataFetchRequest: NSFetchRequest<NSFetchRequestResult> = PhotoMetadataEntity.fetchRequest()
            let metadataBatchDeleteRequest = NSBatchDeleteRequest(fetchRequest: metadataFetchRequest)
            try context.execute(metadataBatchDeleteRequest)
            
            // Delete all photo scores
            let scoreFetchRequest: NSFetchRequest<NSFetchRequestResult> = PhotoScoreEntity.fetchRequest()
            let scoreBatchDeleteRequest = NSBatchDeleteRequest(fetchRequest: scoreFetchRequest)
            try context.execute(scoreBatchDeleteRequest)
            
            try context.save()
        }
    }
}