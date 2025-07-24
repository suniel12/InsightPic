# Photo Curator Design Document

## Overview

The Photo Curator is an iOS application that intelligently curates vacation photos by clustering similar images and selecting the best shots based on technical quality, face analysis, and contextual relevance. The system transforms hundreds of trip photos into a curated selection of 5-20 best shots using Apple's Vision Framework and PhotoKit APIs.

## Code Reuse Analysis

**Project Status**: New iOS Project - Building from scratch with comprehensive architectural foundation
- **Architectural Foundation**: Leverage the detailed technical specifications from `vision.md` 
- **Project Structure**: Follow the established project structure outlined in `README.md`
- **Design patterns**: Implement the three-phase architecture (Clustering → Quality Analysis → Smart Selection)
- **Technical Stack**: Build on Vision Framework, PhotoKit, Core ML, and Core Data as specified
- **Performance Guidelines**: Follow established memory management and processing speed targets
- **Testing Approach**: Implement the comprehensive testing strategy outlined in the vision document

## Architecture

### System Architecture Building on Established Patterns

```
┌─────────────────────────────────────────────────────────────────┐
│                    Photo Curator Architecture                    │
├──────────────────┬──────────────────┬─────────────────────────────┤
│    Data Layer    │   Processing     │      Intelligence          │
│                  │     Engine       │       Engine                │
│ ┌──────────────┐ │ ┌──────────────┐ │ ┌─────────────────────────┐ │
│ │ PhotoKit     │ │ │ Vision       │ │ │ Quality Analyzer        │ │
│ │ Integration  │ │ │ Framework    │ │ │ - Sharpness Analysis    │ │
│ │              │ │ │              │ │ │ - Exposure Evaluation   │ │
│ │ - Permission │ │ │ - Feature    │ │ │ - Composition Scoring   │ │
│ │ - Library    │ │ │   Extraction │ │ │ - Face Quality Check    │ │
│ │ - Metadata   │ │ │ - Face       │ │ │                         │ │
│ │ - EXIF Data  │ │ │   Detection  │ │ └─────────────────────────┘ │
│ └──────────────┘ │ │ - Saliency   │ │                             │
│                  │ │   Analysis   │ │ ┌─────────────────────────┐ │
│ ┌──────────────┐ │ └──────────────┘ │ │ Clustering Engine       │ │
│ │ Core Data    │ │                  │ │ - Similarity Matching   │ │
│ │ Persistence  │ │                  │ │ - Time-based Grouping   │ │
│ │              │ │                  │ │ - Location Clustering   │ │
│ │ - Cache      │ │                  │ │ - Smart Selection       │ │
│ │ - Results    │ │                  │ └─────────────────────────┘ │
│ │ - Metadata   │ │                                                │
│ └──────────────┘ │                                                │
└──────────────────┴──────────────────┴─────────────────────────────┘
```

### MVC Architecture Pattern

Following iOS best practices with clear separation of concerns:

- **Models**: Photo, PhotoCluster, Recommendations, PhotoScore
- **Views**: SwiftUI views for photo library browsing, recommendations display
- **Controllers**: Processing engines and business logic coordinators
- **Services**: PhotoKit integration, Vision Framework processing, Core Data persistence

## Components and Interfaces

### 1. Photo Library Integration Layer

**Purpose**: Handle PhotoKit integration and permissions following established patterns

```swift
protocol PhotoLibraryServiceProtocol {
    func requestPhotoLibraryAccess() async -> PHAuthorizationStatus
    func fetchPhotos() async -> [PHAsset]
    func convertAssetToPhoto(_ asset: PHAsset) async -> Photo?
}

class PhotoLibraryService: PhotoLibraryServiceProtocol {
    // Implementation following PhotoKit best practices
}
```

**Key Responsibilities**:
- Photo library permission management
- Photo asset fetching and filtering
- Metadata extraction (timestamp, location, EXIF)
- Memory-efficient image loading

### 2. Vision Framework Processing Engine

**Purpose**: Leverage Vision Framework for feature extraction and analysis

```swift
protocol VisionProcessingEngineProtocol {
    func generateFingerprint(for image: UIImage) async -> VNFeaturePrintObservation?
    func detectFaces(in image: UIImage) async -> [VNFaceObservation]
    func analyzeSaliency(in image: UIImage) async -> VNSaliencyImageObservation?
}

class VisionProcessingEngine: VisionProcessingEngineProtocol {
    // Implementation using Vision Framework APIs
}
```

**Key Responsibilities**:
- Feature fingerprint generation for similarity comparison
- Face detection and landmark analysis
- Saliency analysis for composition scoring
- Error handling and fallback mechanisms

### 3. Photo Clustering Engine

**Purpose**: Group similar photos using multi-dimensional similarity criteria

```swift
protocol PhotoClusteringEngineProtocol {
    func clusterPhotos(_ photos: [Photo]) async -> [PhotoCluster]
    func calculateSimilarity(_ print1: VNFeaturePrintObservation, 
                            _ print2: VNFeaturePrintObservation) -> Float
}

class PhotoClusteringEngine: PhotoClusteringEngineProtocol {
    struct ClusteringCriteria {
        let visualSimilarity: Float = 0.75
        let timeWindowSeconds: TimeInterval = 600
        let locationRadiusMeters: Double = 50
        let maxClusterSize: Int = 20
    }
}
```

**Key Responsibilities**:
- Visual similarity calculation using Vision Framework
- Time-based grouping (10-minute windows)
- Location-based clustering (50-meter radius)
- Dynamic cluster size management

### 4. Quality Analysis Engine

**Purpose**: Evaluate photo quality using technical and contextual metrics

```swift
protocol QualityAnalysisEngineProtocol {
    func analyzeTechnicalQuality(_ photo: Photo) async -> TechnicalQualityScore
    func analyzeFaceQuality(_ photo: Photo) async -> FaceQualityScore
    func calculateOverallScore(_ photo: Photo, in cluster: PhotoCluster) async -> PhotoScore
}

class QualityAnalysisEngine: QualityAnalysisEngineProtocol {
    private let sharpnessAnalyzer: SharpnessAnalyzer
    private let exposureAnalyzer: ExposureAnalyzer
    private let compositionAnalyzer: CompositionAnalyzer
    private let faceQualityAnalyzer: FaceQualityAnalyzer
}
```

**Key Responsibilities**:
- Sharpness evaluation using Laplacian variance
- Exposure analysis through histogram evaluation
- Composition scoring using Vision Framework saliency
- Face quality assessment (eye state, smile detection, face angle)

### 5. Smart Selection Engine

**Purpose**: Select best photos from clusters using weighted scoring

```swift
protocol SmartSelectionEngineProtocol {
    func selectBestFromCluster(_ cluster: PhotoCluster) async -> Photo
    func generateRecommendations(from clusters: [PhotoCluster]) async -> Recommendations
}

class SmartSelectionEngine: SmartSelectionEngineProtocol {
    private let qualityAnalyzer: QualityAnalysisEngine
    private let contextAnalyzer: ContextAnalyzer
}
```

**Key Responsibilities**:
- Weighted scoring based on photo content (faces vs landscapes)
- Context-aware selection (golden hour, social context)
- Diverse recommendation generation
- Person-specific album creation

### 6. Data Persistence Layer

**Purpose**: Cache analysis results and manage photo metadata

```swift
protocol PhotoDataRepositoryProtocol {
    func savePhoto(_ photo: Photo) async
    func loadPhotos() async -> [Photo]
    func saveCluster(_ cluster: PhotoCluster) async
    func loadClusters() async -> [PhotoCluster]
    func cleanup() async
}

class PhotoDataRepository: PhotoDataRepositoryProtocol {
    private let coreDataStack: CoreDataStack
}
```

**Key Responsibilities**:
- Core Data integration for persistent storage
- Feature print caching to avoid recomputation
- Incremental processing support
- Orphaned data cleanup

## Data Models Following Established Conventions

### Core Models

```swift
struct Photo: Identifiable, Codable {
    let id: UUID
    let assetIdentifier: String
    let timestamp: Date
    let location: CLLocation?
    let metadata: PhotoMetadata
    
    // Analysis results (populated during processing)
    var fingerprint: Data? // Serialized VNFeaturePrintObservation
    var technicalQuality: TechnicalQualityScore?
    var faceQuality: FaceQualityScore?
    var overallScore: PhotoScore?
    var clusterId: UUID?
}

struct PhotoCluster: Identifiable {
    let id: UUID
    var photos: [Photo]
    let representativeFingerprint: Data
    let createdAt: Date
    
    // Computed properties
    var medianTimestamp: Date { /* implementation */ }
    var centerLocation: CLLocation? { /* implementation */ }
    var bestPhoto: Photo? { /* implementation */ }
}

struct Recommendations {
    let generatedAt: Date
    let overall: [Photo]              // Top 5 best photos
    let diverse: [Photo]              // Top 10 diverse selection  
    let byPerson: [String: [Photo]]   // Person-specific albums
    let byTime: [TimeOfDay: [Photo]]  // Time-based groupings
    let byLocation: [String: [Photo]] // Location-based groupings
}
```

### Quality Score Models

```swift
struct PhotoScore {
    let technical: Float      // 0-1 (sharpness, exposure, composition)
    let faces: Float         // 0-1 (face quality, expressions)
    let context: Float       // 0-1 (uniqueness, timing, social context)
    let overall: Float       // Weighted combination
    let calculatedAt: Date
    
    // Weighted calculation based on photo content
    static func calculate(technical: Float, faces: Float, context: Float, 
                         photoType: PhotoType) -> Float {
        switch photoType {
        case .multipleFaces:
            return technical * 0.3 + faces * 0.5 + context * 0.2
        case .landscape:
            return technical * 0.5 + context * 0.4 + faces * 0.1
        case .portrait:
            return technical * 0.4 + faces * 0.4 + context * 0.2
        }
    }
}

struct TechnicalQualityScore {
    let sharpness: Float      // Laplacian variance analysis
    let exposure: Float       // Histogram analysis
    let composition: Float    // Rule of thirds, saliency
    let overall: Float        // Weighted average
}

struct FaceQualityScore {
    let faceCount: Int
    let averageScore: Float   // Average quality across all faces
    let eyesOpen: Bool        // All faces have open eyes
    let goodExpressions: Bool // All faces have good expressions
    let optimalSizes: Bool    // All faces are well-sized
}
```

## Error Handling Consistent with Current Approach

### Comprehensive Error Management

```swift
enum PhotoCuratorError: LocalizedError {
    case photoLibraryAccessDenied
    case visionFrameworkError(Error)
    case coreDataError(Error)
    case insufficientPhotos
    case processingTimeout
    case memoryPressure
    
    var errorDescription: String? {
        switch self {
        case .photoLibraryAccessDenied:
            return "Photo library access is required for photo curation"
        case .visionFrameworkError(let error):
            return "Vision analysis failed: \(error.localizedDescription)"
        case .coreDataError(let error):
            return "Data storage error: \(error.localizedDescription)"
        case .insufficientPhotos:
            return "At least 5 photos are required for curation"
        case .processingTimeout:
            return "Photo processing timed out"
        case .memoryPressure:
            return "Low memory - processing paused"
        }
    }
}
```

### Error Recovery Strategies

1. **Vision Framework Failures**: Assign neutral scores and continue processing
2. **Memory Pressure**: Implement batch processing with smaller groups
3. **Permission Denied**: Provide clear guidance and retry mechanisms
4. **Core Data Errors**: Fallback to in-memory processing with user notification
5. **Timeout Handling**: Progressive timeout extension with user feedback

## Testing Strategy Using Existing Utilities

### Unit Testing Framework

```swift
class PhotoClusteringEngineTests: XCTestCase {
    var clusteringEngine: PhotoClusteringEngine!
    var mockVisionEngine: MockVisionProcessingEngine!
    
    override func setUp() {
        super.setUp()
        mockVisionEngine = MockVisionProcessingEngine()
        clusteringEngine = PhotoClusteringEngine(visionEngine: mockVisionEngine)
    }
    
    func testSimilarPhotosClusteredTogether() async {
        // Test clustering with similar visual fingerprints
        let similarPhotos = TestDataGenerator.createSimilarPhotos(count: 5)
        
        let clusters = await clusteringEngine.clusterPhotos(similarPhotos)
        
        XCTAssertEqual(clusters.count, 1, "Similar photos should form single cluster")
        XCTAssertEqual(clusters[0].photos.count, 5, "All similar photos should be in cluster")
    }
    
    func testDifferentScenesFormSeparateClusters() async {
        // Test clustering with diverse visual content
        let diversePhotos = TestDataGenerator.createDiversePhotos(count: 10)
        
        let clusters = await clusteringEngine.clusterPhotos(diversePhotos)
        
        XCTAssertGreaterThan(clusters.count, 1, "Diverse photos should form multiple clusters")
    }
}
```

### Integration Testing

```swift
class PhotoCuratorIntegrationTests: XCTestCase {
    func testEndToEndCurationWorkflow() async {
        let photoCurator = PhotoCurator()
        let testPhotos = TestDataGenerator.createTripPhotoSet(count: 50)
        
        let recommendations = await photoCurator.curatePhotos(testPhotos)
        
        XCTAssertEqual(recommendations.overall.count, 5, "Should generate 5 top recommendations")
        XCTAssertLessThanOrEqual(recommendations.diverse.count, 10, "Should generate up to 10 diverse recommendations")
        XCTAssertTrue(recommendations.overall.allSatisfy { $0.overallScore?.overall ?? 0 > 0.5 }, "Top recommendations should have high scores")
    }
}
```

### Performance Testing

```swift
class PhotoCuratorPerformanceTests: XCTestCase {
    func testProcessing100PhotosPerformance() {
        let photoCurator = PhotoCurator()
        let testPhotos = TestDataGenerator.createPhotoSet(count: 100)
        
        measure {
            let _ = await photoCurator.curatePhotos(testPhotos)
        }
        
        // Should complete in under 10 seconds as per requirements
    }
    
    func testMemoryUsageDuringProcessing() {
        let photoCurator = PhotoCurator()
        let testPhotos = TestDataGenerator.createPhotoSet(count: 100)
        
        let initialMemory = getCurrentMemoryUsage()
        let _ = await photoCurator.curatePhotos(testPhotos)
        let finalMemory = getCurrentMemoryUsage()
        
        let memoryIncrease = finalMemory - initialMemory
        XCTAssertLessThan(memoryIncrease, 200_000_000, "Memory usage should not exceed 200MB")
    }
}
```

## Performance Optimization Strategy

### Memory Management
- **Batch Processing**: Process photos in groups of 20-50 to prevent memory spikes
- **Image Downsizing**: Resize images to maximum 1024px for analysis
- **Weak References**: Use weak references in clusters to prevent retain cycles
- **Cache Management**: Implement LRU cache for feature prints with size limits

### Processing Speed Optimization
- **Concurrent Processing**: Use GCD concurrent queues for independent operations
- **Incremental Analysis**: Skip re-analysis of previously processed photos
- **Background Processing**: Leverage background app refresh for large libraries
- **Progressive Loading**: Stream results as they become available

### Core Data Optimization
- **Batch Operations**: Use batch inserts/updates for better performance
- **Lazy Loading**: Load photo data on-demand to reduce memory footprint
- **Index Optimization**: Create indexes on frequently queried fields
- **Cleanup Scheduling**: Regular cleanup of orphaned data

## User Interface Architecture

### SwiftUI View Hierarchy

```swift
struct ContentView: View {
    @StateObject private var photoCurator = PhotoCurator()
    @State private var selectedPhotos: [Photo] = []
    
    var body: some View {
        NavigationStack {
            VStack {
                PhotoLibraryPickerView(selectedPhotos: $selectedPhotos)
                
                if !selectedPhotos.isEmpty {
                    ProcessingProgressView(curator: photoCurator)
                    RecommendationsView(recommendations: photoCurator.recommendations)
                }
            }
        }
    }
}
```

### Key UI Components
- **PhotoLibraryPickerView**: PhotoKit integration with permission handling
- **ProcessingProgressView**: Real-time progress indicators during analysis
- **RecommendationsView**: Tabbed interface showing different recommendation types
- **PhotoClusterView**: Expandable clusters showing similar photos
- **PhotoDetailView**: Individual photo with quality metrics overlay

## Data Flow Architecture

### Processing Pipeline

1. **Photo Import**: PhotoKit → Photo models with metadata
2. **Feature Extraction**: Vision Framework → Feature prints cached in Core Data  
3. **Clustering**: Similarity analysis → PhotoCluster formation
4. **Quality Analysis**: Technical + Face analysis → PhotoScore calculation
5. **Smart Selection**: Weighted scoring → Best photo per cluster
6. **Recommendation Generation**: Diverse selection → Recommendations model
7. **UI Updates**: Reactive UI updates via Combine/SwiftUI

### State Management

Using SwiftUI's reactive patterns with @StateObject and @ObservableObject:
- **PhotoCurator**: Main coordinator managing processing state
- **RecommendationsStore**: Manages recommendation data and UI state
- **ProgressTracker**: Tracks processing progress across different stages

## Security and Privacy Considerations

### Data Protection
- **On-Device Processing**: All analysis occurs locally, no cloud processing
- **Photo Library Permissions**: Explicit user consent with clear usage description
- **Secure Storage**: Core Data encryption for cached analysis results
- **Memory Security**: Secure memory handling for temporary image data

### Privacy Compliance
- **No External Transmission**: Photos never leave the device
- **Minimal Data Collection**: Only collect essential metadata for functionality
- **User Control**: Users can delete cached analysis data at any time
- **Transparent Processing**: Clear UI indicators showing what analysis is occurring

## Deployment and Distribution Strategy

### App Store Guidelines Compliance
- **Photo Library Usage**: Clear NSPhotoLibraryUsageDescription
- **Performance Requirements**: Meet App Store performance standards
- **Accessibility**: Full VoiceOver and accessibility support
- **Device Compatibility**: Support iPhone and iPad with adaptive layouts

### Version Management
- **Core Data Migration**: Smooth migration paths for schema updates
- **Feature Flags**: Gradual rollout of new analysis features
- **Backward Compatibility**: Support for older iOS versions where possible

This design document provides a comprehensive technical foundation for implementing the Photo Curator feature while leveraging established iOS development patterns and the detailed architectural vision already outlined in the project documentation.