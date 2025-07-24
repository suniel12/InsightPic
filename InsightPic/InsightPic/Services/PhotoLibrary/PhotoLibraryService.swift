import Foundation
import Photos
import UIKit
import CoreLocation

// MARK: - PhotoLibraryService Protocol

protocol PhotoLibraryServiceProtocol {
    func requestAuthorization() async -> PHAuthorizationStatus
    func fetchAllPhotos() async throws -> [Photo]
    func fetchPhotosInDateRange(from startDate: Date, to endDate: Date) async throws -> [Photo]
    func loadImage(for assetIdentifier: String, targetSize: CGSize) async throws -> UIImage?
    func getThumbnail(for assetIdentifier: String) async throws -> UIImage?
    func getFullResolutionImage(for assetIdentifier: String) async throws -> UIImage?
}

// MARK: - PhotoLibraryService Implementation

class PhotoLibraryService: PhotoLibraryServiceProtocol {
    private let imageManager = PHImageManager.default()
    private let requestOptions: PHImageRequestOptions
    
    init() {
        requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .exact
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> PHAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    // MARK: - Photo Fetching
    
    func fetchAllPhotos() async throws -> [Photo] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        return try await convertAssetsToPhotos(assets)
    }
    
    func fetchPhotosInDateRange(from startDate: Date, to endDate: Date) async throws -> [Photo] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue,
            startDate as NSDate,
            endDate as NSDate
        )
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        return try await convertAssetsToPhotos(assets)
    }
    
    // MARK: - Image Loading
    
    func loadImage(for assetIdentifier: String, targetSize: CGSize) async throws -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject else {
            throw PhotoCuratorError.invalidPhotoAsset(assetIdentifier)
        }
        
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    func getThumbnail(for assetIdentifier: String) async throws -> UIImage? {
        return try await loadImage(for: assetIdentifier, targetSize: CGSize(width: 150, height: 150))
    }
    
    func getFullResolutionImage(for assetIdentifier: String) async throws -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject else {
            throw PhotoCuratorError.invalidPhotoAsset(assetIdentifier)
        }
        
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .none
            
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func convertAssetsToPhotos(_ fetchResult: PHFetchResult<PHAsset>) async throws -> [Photo] {
        var photos: [Photo] = []
        
        for i in 0..<fetchResult.count {
            let asset = fetchResult.object(at: i)
            
            // Extract metadata
            let metadata = await extractMetadata(from: asset)
            
            // Create location if available
            let location = asset.location
            
            // Create Photo object
            let photo = Photo(
                id: UUID(),
                assetIdentifier: asset.localIdentifier,
                timestamp: asset.creationDate ?? Date(),
                location: location,
                metadata: metadata
            )
            
            photos.append(photo)
        }
        
        return photos
    }
    
    private func extractMetadata(from asset: PHAsset) async -> PhotoMetadata {
        // Get image dimensions
        let width = Int(asset.pixelWidth)
        let height = Int(asset.pixelHeight)
        
        // Try to get detailed metadata from the asset
        let metadata: PhotoMetadata = await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .fastFormat
            options.resizeMode = .none
            
            imageManager.requestImageDataAndOrientation(for: asset, options: options) { data, dataUTI, orientation, info in
                guard let imageData = data,
                      let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                      let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
                    continuation.resume(returning: PhotoMetadata(width: width, height: height))
                    return
                }
                
                let metadata = self.parseImageProperties(imageProperties, width: width, height: height)
                continuation.resume(returning: metadata)
            }
        }
        
        return metadata
    }
    
    private func parseImageProperties(_ properties: [String: Any], width: Int, height: Int) -> PhotoMetadata {
        var cameraModel: String?
        var lensModel: String?
        var focalLength: Double?
        var fNumber: Double?
        var exposureTime: Double?
        var iso: Int?
        var altitude: Double?
        
        // Extract TIFF metadata
        if let tiffData = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            cameraModel = tiffData[kCGImagePropertyTIFFModel as String] as? String
        }
        
        // Extract EXIF metadata
        if let exifData = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            lensModel = exifData[kCGImagePropertyExifLensModel as String] as? String
            focalLength = exifData[kCGImagePropertyExifFocalLength as String] as? Double
            fNumber = exifData[kCGImagePropertyExifFNumber as String] as? Double
            exposureTime = exifData[kCGImagePropertyExifExposureTime as String] as? Double
            
            if let isoArray = exifData[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber],
               let firstISO = isoArray.first {
                iso = firstISO.intValue
            }
        }
        
        // Extract GPS metadata for altitude
        if let gpsData = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            altitude = gpsData[kCGImagePropertyGPSAltitude as String] as? Double
        }
        
        return PhotoMetadata(
            width: width,
            height: height,
            cameraModel: cameraModel,
            lensModel: lensModel,
            focalLength: focalLength,
            fNumber: fNumber,
            exposureTime: exposureTime,
            iso: iso,
            altitude: altitude
        )
    }
}

// MARK: - PhotoLibraryService Extensions

extension PhotoLibraryService {
    
    // Batch processing for large photo libraries
    func fetchPhotosInBatches(batchSize: Int = 100, progressCallback: @escaping (Int, Int) -> Void) async throws -> [Photo] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        let totalCount = assets.count
        var allPhotos: [Photo] = []
        
        for batchStart in stride(from: 0, to: totalCount, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalCount)
            var batchPhotos: [Photo] = []
            
            for i in batchStart..<batchEnd {
                let asset = assets.object(at: i)
                let metadata = await extractMetadata(from: asset)
                
                let photo = Photo(
                    id: UUID(),
                    assetIdentifier: asset.localIdentifier,
                    timestamp: asset.creationDate ?? Date(),
                    location: asset.location,
                    metadata: metadata
                )
                
                batchPhotos.append(photo)
            }
            
            allPhotos.append(contentsOf: batchPhotos)
            progressCallback(batchEnd, totalCount)
        }
        
        return allPhotos
    }
    
    // Filter photos by various criteria
    func fetchRecentPhotos(days: Int = 30) async throws -> [Photo] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return try await fetchPhotosInDateRange(from: startDate, to: Date())
    }
    
    func fetchPhotosWithLocation() async throws -> [Photo] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(
            format: "mediaType == %d AND location != nil",
            PHAssetMediaType.image.rawValue
        )
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        return try await convertAssetsToPhotos(assets)
    }
}