import Foundation
import CoreData

class CoreDataStack {
    static let shared = CoreDataStack()
    
    private init() {}
    
    // MARK: - Core Data Stack
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "InsightPic")
        
        // Configure persistent store description for performance
        let storeDescription = container.persistentStoreDescriptions.first
        storeDescription?.shouldInferMappingModelAutomatically = true
        storeDescription?.shouldMigrateStoreAutomatically = true
        
        // Enable persistent history tracking for CloudKit sync (future enhancement)
        storeDescription?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // In production, handle this error appropriately
                fatalError("Core Data error: \(error), \(error.userInfo)")
            }
        }
        
        // Configure merge policy for handling conflicts
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        return container
    }()
    
    var mainContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    var backgroundContext: NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    // MARK: - Save Operations
    
    func save() {
        saveContext(mainContext)
    }
    
    func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        
        context.performAndWait {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                // In production, handle this error appropriately
                fatalError("Core Data save error: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    // MARK: - Background Operations
    
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            let context = backgroundContext
            context.perform {
                do {
                    let result = try block(context)
                    self.saveContext(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Batch Operations
    
    func batchInsert<T: NSManagedObject>(
        entityName: String,
        objects: [(T) -> Void]
    ) async throws {
        try await performBackgroundTask { context in
            let batchInsert = NSBatchInsertRequest(entityName: entityName) { (managedObject: NSManagedObject) -> Bool in
                guard let currentIndex = objects.firstIndex(where: { _ in true }) else {
                    return true  // No more objects to process
                }
                
                if let typedObject = managedObject as? T {
                    objects[currentIndex](typedObject)
                }
                
                return false  // Continue processing
            }
            
            batchInsert.resultType = .objectIDs
            let result = try context.execute(batchInsert) as? NSBatchInsertResult
            
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                // Merge changes to main context
                let changes = [NSInsertedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.mainContext])
            }
        }
    }
    
    func batchDelete(fetchRequest: NSFetchRequest<NSFetchRequestResult>) async throws {
        try await performBackgroundTask { context in
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                // Merge changes to main context
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.mainContext])
            }
        }
    }
    
    // MARK: - Cleanup Operations
    
    func cleanup() async throws {
        try await performBackgroundTask { context in
            // Remove orphaned scores (scores without photos)
            let orphanedScoresRequest: NSFetchRequest<PhotoScoreEntity> = PhotoScoreEntity.fetchRequest()
            orphanedScoresRequest.predicate = NSPredicate(format: "photo == nil")
            
            let orphanedScores = try context.fetch(orphanedScoresRequest)
            for score in orphanedScores {
                context.delete(score)
            }
            
            // Remove orphaned metadata (metadata without photos)
            let orphanedMetadataRequest: NSFetchRequest<PhotoMetadataEntity> = PhotoMetadataEntity.fetchRequest()
            orphanedMetadataRequest.predicate = NSPredicate(format: "photo == nil")
            
            let orphanedMetadata = try context.fetch(orphanedMetadataRequest)
            for metadata in orphanedMetadata {
                context.delete(metadata)
            }
            
            // Remove empty clusters (clusters without photos)
            let emptyClustersRequest: NSFetchRequest<PhotoClusterEntity> = PhotoClusterEntity.fetchRequest()
            emptyClustersRequest.predicate = NSPredicate(format: "photos.@count == 0")
            
            let emptyClusters = try context.fetch(emptyClustersRequest)
            for cluster in emptyClusters {
                context.delete(cluster)
            }
        }
    }
    
    // MARK: - Database Reset
    
    func resetDatabase() async throws {
        try await performBackgroundTask { context in
            // Delete all entities
            let entityNames = ["PhotoEntity", "PhotoClusterEntity", "PhotoScoreEntity", 
                             "PhotoMetadataEntity", "TechnicalQualityScoreEntity", "FaceQualityScoreEntity"]
            
            for entityName in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                try context.execute(deleteRequest)
            }
        }
    }
    
    // MARK: - Memory Management
    
    func freeMemory() {
        mainContext.refreshAllObjects()
        
        // Clear merge policy cache
        mainContext.processPendingChanges()
        mainContext.refreshAllObjects()
    }
}