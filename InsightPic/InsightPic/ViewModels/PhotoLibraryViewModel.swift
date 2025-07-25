import Foundation
import SwiftUI
import Photos
import Combine

@MainActor
class PhotoLibraryViewModel: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var isLoading = false
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var loadingProgress: Double = 0.0
    @Published var loadingText: String = ""
    
    private let photoLibraryService: PhotoLibraryServiceProtocol
    private let photoRepository: PhotoDataRepositoryProtocol
    
    init(photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService(),
         photoRepository: PhotoDataRepositoryProtocol = PhotoDataRepository()) {
        self.photoLibraryService = photoLibraryService
        self.photoRepository = photoRepository
    }
    
    // MARK: - Initialization
    
    func loadExistingPhotos() async {
        do {
            let existingPhotos = try await photoRepository.loadPhotos()
            await MainActor.run {
                photos = existingPhotos
                print("DEBUG: Loaded \(existingPhotos.count) existing photos from database on startup")
            }
        } catch {
            print("DEBUG: No existing photos found on startup: \(error)")
        }
    }
    
    // MARK: - Public Methods
    
    func requestPhotoLibraryAccess() async {
        isLoading = true
        loadingText = "Checking for existing photos..."
        
        // First check if we already have photos in the database
        do {
            let existingPhotos = try await photoRepository.loadPhotos()
            if !existingPhotos.isEmpty {
                photos = existingPhotos
                loadingText = "Loaded \(existingPhotos.count) photos from database"
                print("DEBUG: Found \(existingPhotos.count) existing photos in database")
                isLoading = false
                return
            }
        } catch {
            print("DEBUG: No existing photos found, will load from library")
        }
        
        loadingText = "Requesting photo library access..."
        authorizationStatus = await photoLibraryService.requestAuthorization()
        
        switch authorizationStatus {
        case .authorized, .limited:
            await loadPhotosFromLibrary()
        case .denied, .restricted:
            errorMessage = "Photo library access is required to analyze your photos. Please enable it in Settings."
        case .notDetermined:
            errorMessage = "Photo library access was not granted."
        @unknown default:
            errorMessage = "Unknown authorization status."
        }
        
        isLoading = false
    }
    
    func loadPhotosFromLibrary() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            errorMessage = "Photo library access is required."
            return
        }
        
        isLoading = true
        loadingProgress = 0.0
        loadingText = "Loading photos from your library..."
        errorMessage = nil
        
        do {
            // Phase 1: Fetch limited photos from library with progress (0-30%)
            await updateProgress(0.05, "Fetching photos from library...")
            
            let photosToProcess = try await photoLibraryService.fetchLimitedPhotos(count: 100) { fetched, total in
                Task { @MainActor in
                    let fetchProgress = Double(fetched) / Double(total)
                    let currentProgress = 0.05 + (fetchProgress * 0.25) // 5% to 30%
                    self.loadingProgress = currentProgress
                    self.loadingText = "Fetched \(fetched) of \(total) photos..."
                }
            }
            print("DEBUG: Fetched \(photosToProcess.count) photos from photo library")
            
            await updateProgress(0.30, "Found \(photosToProcess.count) photos for processing...")
            
            // Phase 2: Save photos with dynamic progress (30-90%)
            await updateProgress(0.35, "Saving photos to database...")
            
            // Save photos with progress tracking
            try await savePhotosWithProgress(photosToProcess, startProgress: 0.35, endProgress: 0.85)
            
            print("DEBUG: Saved \(photosToProcess.count) photos to database")
            
            // Phase 3: Load from database (85-95%)
            await updateProgress(0.85, "Loading processed photos...")
            
            let loadedPhotos = try await photoRepository.loadPhotos()
            print("DEBUG: Loaded \(loadedPhotos.count) photos from database")
            
            await updateProgress(0.95, "Finalizing...")
            
            await MainActor.run {
                photos = loadedPhotos
                print("DEBUG: UI updated with \(photos.count) photos")
            }
            
            // Complete
            await updateProgress(1.0, "Complete! Loaded \(photos.count) photos")
            
        } catch {
            if let curatorError = error as? PhotoCuratorError {
                errorMessage = curatorError.localizedDescription
            } else {
                errorMessage = "Failed to load photos: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
        
        // Keep progress at 100% for a moment before resetting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.loadingProgress = 0.0
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func updateProgress(_ progress: Double, _ text: String) async {
        await MainActor.run {
            loadingProgress = progress
            loadingText = text
        }
    }
    
    private func savePhotosWithProgress(_ photos: [Photo], startProgress: Double, endProgress: Double) async throws {
        let totalPhotos = photos.count
        let progressRange = endProgress - startProgress
        
        // Process photos in smaller batches for better progress feedback
        let batchSize = max(1, totalPhotos / 20) // 20 progress updates
        
        for (index, photoBatch) in photos.chunked(into: batchSize).enumerated() {
            let currentProgress = startProgress + (Double(index * batchSize) / Double(totalPhotos)) * progressRange
            let processedCount = min((index + 1) * batchSize, totalPhotos)
            
            await updateProgress(currentProgress, "Saving photos \(processedCount)/\(totalPhotos)...")
            
            // Save this batch
            try await photoRepository.savePhotos(photoBatch)
            
            // Small delay to make progress visible
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        // Ensure we reach the end progress
        await updateProgress(endProgress, "Saved \(totalPhotos) photos to database")
    }
    
    func clearDatabase() async {
        isLoading = true
        loadingText = "Clearing database..."
        
        do {
            try await photoRepository.clearAllPhotos()
            photos = []
            // Clear the analysis cache as well
            UserDefaults.standard.set(false, forKey: "hasEverAnalyzedPhotos")
            loadingText = "Database cleared"
            print("DEBUG: Database cleared successfully")
        } catch {
            errorMessage = "Failed to clear database: \(error.localizedDescription)"
            print("DEBUG: Database clear error: \(error)")
        }
        
        isLoading = false
    }
    
    func loadThumbnail(for photo: Photo) async -> UIImage? {
        do {
            return try await photoLibraryService.getThumbnail(for: photo.assetIdentifier)
        } catch {
            print("Failed to load thumbnail for \(photo.assetIdentifier): \(error)")
            return nil
        }
    }
    
    func loadFullImage(for photo: Photo) async -> UIImage? {
        do {
            return try await photoLibraryService.getFullResolutionImage(for: photo.assetIdentifier)
        } catch {
            print("Failed to load full image for \(photo.assetIdentifier): \(error)")
            return nil
        }
    }
    
    // MARK: - Photo Filtering
    
    func filterRecentPhotos(days: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        photos = photos.filter { $0.timestamp >= cutoffDate }
    }
    
    func filterPhotosWithLocation() {
        photos = photos.filter { $0.location != nil }
    }
    
    func searchPhotos(byDateRange startDate: Date, endDate: Date) async {
        isLoading = true
        loadingText = "Searching photos in date range..."
        
        do {
            let filteredPhotos = try await photoLibraryService.fetchPhotosInDateRange(
                from: startDate,
                to: endDate
            )
            photos = filteredPhotos
        } catch {
            errorMessage = "Failed to search photos: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Statistics
    
    var totalPhotosCount: Int {
        photos.count
    }
    
    var photosWithLocationCount: Int {
        photos.filter { $0.location != nil }.count
    }
    
    var dateRange: (start: Date?, end: Date?) {
        guard !photos.isEmpty else { return (nil, nil) }
        
        let sortedDates = photos.map { $0.timestamp }.sorted()
        return (sortedDates.first, sortedDates.last)
    }
    
    var photosByYear: [Int: [Photo]] {
        Dictionary(grouping: photos) { photo in
            Calendar.current.component(.year, from: photo.timestamp)
        }
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        errorMessage = nil
    }
    
    func showError(_ message: String) {
        errorMessage = message
    }
}

// MARK: - Preview Support

#if DEBUG
extension PhotoLibraryViewModel {
    static var preview: PhotoLibraryViewModel {
        let vm = PhotoLibraryViewModel()
        vm.photos = [
            Photo(
                id: UUID(),
                assetIdentifier: "preview-1",
                timestamp: Date().addingTimeInterval(-86400),
                location: nil,
                metadata: PhotoMetadata(width: 1920, height: 1080, cameraModel: "iPhone 15")
            ),
            Photo(
                id: UUID(),
                assetIdentifier: "preview-2",
                timestamp: Date().addingTimeInterval(-172800),
                location: nil,
                metadata: PhotoMetadata(width: 3024, height: 4032, cameraModel: "iPhone 15 Pro")
            )
        ]
        return vm
    }
}
#endif

// MARK: - Array Extension for Batching

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}