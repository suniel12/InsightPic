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
            // Load photos from library
            let libraryPhotos = try await photoLibraryService.fetchAllPhotos()
            print("DEBUG: Fetched \(libraryPhotos.count) photos from photo library")
            
            // For testing with large libraries, limit to first 100 photos
            let photosToProcess = Array(libraryPhotos.prefix(100))
            print("DEBUG: Processing first \(photosToProcess.count) photos for testing")
            
            // Update progress
            loadingProgress = 1.0
            loadingText = "Loaded \(photosToProcess.count) photos..."
            
            loadingText = "Saving photos to database..."
            
            // Save to Core Data
            try await photoRepository.savePhotos(photosToProcess)
            print("DEBUG: Saved \(photosToProcess.count) photos to database")
            
            // Load from database to get complete objects
            let loadedPhotos = try await photoRepository.loadPhotos()
            print("DEBUG: Loaded \(loadedPhotos.count) photos from database")
            
            await MainActor.run {
                photos = loadedPhotos
                print("DEBUG: UI updated with \(photos.count) photos")
            }
            
            loadingText = "Complete! Loaded \(photos.count) photos"
            
        } catch {
            if let curatorError = error as? PhotoCuratorError {
                errorMessage = curatorError.localizedDescription
            } else {
                errorMessage = "Failed to load photos: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
        loadingProgress = 0.0
    }
    
    func refreshPhotos() async {
        await loadPhotosFromLibrary()
    }
    
    func clearDatabase() async {
        isLoading = true
        loadingText = "Clearing database..."
        
        do {
            try await photoRepository.clearAllPhotos()
            photos = []
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