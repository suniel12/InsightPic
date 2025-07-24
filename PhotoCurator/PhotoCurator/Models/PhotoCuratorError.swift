import Foundation

// MARK: - PhotoCuratorError

enum PhotoCuratorError: LocalizedError {
    case photoLibraryAccessDenied
    case photoLibraryAccessRestricted
    case visionFrameworkError(Error)
    case coreDataError(Error)
    case insufficientPhotos
    case processingTimeout
    case memoryPressure
    case invalidPhotoAsset(String)
    case fingerprintGenerationFailed
    case clusteringFailed(Error)
    case qualityAnalysisFailed(Error)
    case dataCorruption
    case networkError(Error)
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Photo library access is required for photo curation. Please enable access in Settings."
            
        case .photoLibraryAccessRestricted:
            return "Photo library access is restricted. Please check your device restrictions."
            
        case .visionFrameworkError(let error):
            return "Vision analysis failed: \(error.localizedDescription)"
            
        case .coreDataError(let error):
            return "Data storage error: \(error.localizedDescription)"
            
        case .insufficientPhotos:
            return "At least 5 photos are required for curation."
            
        case .processingTimeout:
            return "Photo processing timed out. Please try again with fewer photos."
            
        case .memoryPressure:
            return "Low memory detected. Processing has been paused to prevent crashes."
            
        case .invalidPhotoAsset(let identifier):
            return "Invalid photo asset: \(identifier). The photo may have been deleted."
            
        case .fingerprintGenerationFailed:
            return "Failed to generate photo fingerprints for similarity analysis."
            
        case .clusteringFailed(let error):
            return "Photo clustering failed: \(error.localizedDescription)"
            
        case .qualityAnalysisFailed(let error):
            return "Quality analysis failed: \(error.localizedDescription)"
            
        case .dataCorruption:
            return "Data corruption detected. Please reset the app data."
            
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
            
        case .unknownError(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "The app does not have permission to access your photo library."
            
        case .photoLibraryAccessRestricted:
            return "Photo library access is restricted by device policies."
            
        case .visionFrameworkError:
            return "The Vision Framework encountered an error during image analysis."
            
        case .coreDataError:
            return "The database encountered an error while saving or loading data."
            
        case .insufficientPhotos:
            return "Photo curation requires analyzing multiple photos to find similarities."
            
        case .processingTimeout:
            return "The processing operation took longer than expected."
            
        case .memoryPressure:
            return "The device is running low on available memory."
            
        case .invalidPhotoAsset:
            return "The photo asset could not be loaded from the library."
            
        case .fingerprintGenerationFailed:
            return "Visual fingerprints could not be generated for photo comparison."
            
        case .clusteringFailed:
            return "Similar photos could not be grouped together."
            
        case .qualityAnalysisFailed:
            return "Photo quality scores could not be calculated."
            
        case .dataCorruption:
            return "Stored data appears to be corrupted or invalid."
            
        case .networkError:
            return "A network operation failed."
            
        case .unknownError:
            return "An unexpected error occurred in the system."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Go to Settings > Privacy & Security > Photos and enable access for this app."
            
        case .photoLibraryAccessRestricted:
            return "Check with your device administrator or parent to enable photo access."
            
        case .visionFrameworkError:
            return "Try restarting the app or selecting different photos."
            
        case .coreDataError:
            return "Try restarting the app. If the problem persists, you may need to reset app data."
            
        case .insufficientPhotos:
            return "Select at least 5 photos from your library to enable curation features."
            
        case .processingTimeout:
            return "Try processing fewer photos at once, or restart the app and try again."
            
        case .memoryPressure:
            return "Close other apps to free up memory, then restart this app."
            
        case .invalidPhotoAsset:
            return "Remove this photo from your selection and try again."
            
        case .fingerprintGenerationFailed:
            return "Try with different photos or restart the app."
            
        case .clusteringFailed:
            return "Try restarting the app or processing photos in smaller batches."
            
        case .qualityAnalysisFailed:
            return "Try with different photos or restart the app."
            
        case .dataCorruption:
            return "Reset app data in Settings, then import your photos again."
            
        case .networkError:
            return "Check your internet connection and try again."
            
        case .unknownError:
            return "Try restarting the app. If the problem persists, contact support."
        }
    }
    
    // MARK: - Error Classification
    
    var isRecoverable: Bool {
        switch self {
        case .photoLibraryAccessDenied, .photoLibraryAccessRestricted, .insufficientPhotos:
            return true
        case .memoryPressure, .processingTimeout:
            return true
        case .invalidPhotoAsset:
            return true
        case .dataCorruption:
            return false
        default:
            return true
        }
    }
    
    var requiresUserAction: Bool {
        switch self {
        case .photoLibraryAccessDenied, .photoLibraryAccessRestricted:
            return true
        case .insufficientPhotos:
            return true
        case .dataCorruption:
            return true
        default:
            return false
        }
    }
    
    var severity: ErrorSeverity {
        switch self {
        case .dataCorruption, .coreDataError:
            return .critical
        case .photoLibraryAccessDenied, .photoLibraryAccessRestricted:
            return .high
        case .memoryPressure, .processingTimeout:
            return .medium
        case .insufficientPhotos, .invalidPhotoAsset:
            return .low
        default:
            return .medium
        }
    }
}

// MARK: - Error Severity

enum ErrorSeverity: Int, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
    
    var description: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .critical:
            return "Critical"
        }
    }
}

// MARK: - Error Recovery Strategies

struct ErrorRecoveryStrategy {
    let error: PhotoCuratorError
    let strategy: RecoveryAction
    
    enum RecoveryAction {
        case requestPermissions
        case reducePhotoCount
        case freeMemory
        case restartProcessing
        case resetAppData
        case skipCurrentOperation
        case fallbackToDefault
        case none
    }
    
    static func strategy(for error: PhotoCuratorError) -> ErrorRecoveryStrategy {
        let action: RecoveryAction
        
        switch error {
        case .photoLibraryAccessDenied, .photoLibraryAccessRestricted:
            action = .requestPermissions
        case .insufficientPhotos:
            action = .none  // User needs to select more photos
        case .memoryPressure:
            action = .freeMemory
        case .processingTimeout:
            action = .reducePhotoCount
        case .dataCorruption:
            action = .resetAppData
        case .invalidPhotoAsset:
            action = .skipCurrentOperation
        case .visionFrameworkError, .fingerprintGenerationFailed:
            action = .fallbackToDefault
        case .clusteringFailed, .qualityAnalysisFailed:
            action = .restartProcessing
        default:
            action = .restartProcessing
        }
        
        return ErrorRecoveryStrategy(error: error, strategy: action)
    }
}

// MARK: - Error Logging

struct ErrorLogger {
    static func log(_ error: PhotoCuratorError, context: String = "") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let severity = error.severity.description
        let description = error.localizedDescription
        
        print("[\(timestamp)] [\(severity)] PhotoCurator Error: \(description)")
        if !context.isEmpty {
            print("Context: \(context)")
        }
        
        // In production, send to analytics service
        #if DEBUG
        print("Error Details: \(error)")
        #endif
    }
    
    static func logRecovery(_ strategy: ErrorRecoveryStrategy, success: Bool) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let action = strategy.strategy
        let result = success ? "SUCCESS" : "FAILED"
        
        print("[\(timestamp)] Recovery Strategy \(action) - \(result)")
    }
}