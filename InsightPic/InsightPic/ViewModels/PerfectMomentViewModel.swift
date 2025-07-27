import Foundation
import SwiftUI
import Combine

// MARK: - Supporting Types

/// Represents the current phase of Perfect Moment generation
enum GenerationPhase: String, CaseIterable {
    case idle = "idle"
    case analyzing = "analyzing"
    case selecting = "selecting"
    case compositing = "compositing"
    case validating = "validating"
    case completed = "completed"
    case cancelled = "cancelled"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .analyzing: return "Analyzing"
        case .selecting: return "Selecting"
        case .compositing: return "Compositing"
        case .validating: return "Validating"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .failed: return "Failed"
        }
    }
    
    var canCancel: Bool {
        switch self {
        case .analyzing, .selecting, .compositing:
            return true
        case .idle, .validating, .completed, .cancelled, .failed:
            return false
        }
    }
}

/// Comparison display modes for Perfect Moment results
enum ComparisonMode: String, CaseIterable {
    case sideBySide = "side_by_side"
    case beforeAfter = "before_after"
    case overlay = "overlay"
    case fullscreen = "fullscreen"
    
    var displayName: String {
        switch self {
        case .sideBySide: return "Side by Side"
        case .beforeAfter: return "Before & After"
        case .overlay: return "Overlay"
        case .fullscreen: return "Fullscreen"
        }
    }
}

/// Shareable item that can be passed to system share sheet
struct ShareableItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
    let subtitle: String?
    let metadata: [String: Any]
    
    init(perfectMomentResult: PerfectMomentResult) {
        self.image = perfectMomentResult.perfectMoment
        self.title = "Perfect Moment"
        self.subtitle = "Enhanced photo with \(perfectMomentResult.improvements.count) improvements"
        self.metadata = [
            "processing_time": perfectMomentResult.processingTime,
            "quality_score": perfectMomentResult.qualityMetrics.overallQuality,
            "improvements": perfectMomentResult.improvements.map { $0.improvementType.rawValue }
        ]
    }
    
    init(photo: Photo, title: String, subtitle: String? = nil) {
        // Note: Photo model doesn't have direct image property - would need to load via PhotoLibraryService
        self.image = UIImage(systemName: "photo") ?? UIImage()
        self.title = title
        self.subtitle = subtitle
        self.metadata = [
            "photo_id": photo.id.uuidString,
            "timestamp": photo.timestamp,
            "is_perfect_moment": photo.isPerfectMoment
        ]
    }
}

@MainActor
class PerfectMomentViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isAnalyzing = false
    @Published var isGenerating = false
    @Published var progress: Float = 0.0
    @Published var progressText: String = ""
    @Published var currentResult: PerfectMomentResult?
    @Published var errorMessage: String?
    @Published var isSaving = false
    @Published var saveCompleted = false
    
    // MARK: - Enhanced Workflow State
    
    @Published var currentPhase: GenerationPhase = .idle
    @Published var canCancel = false
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var retryCount = 0
    @Published var cachedResults: [String: PerfectMomentResult] = [:]
    
    // MARK: - Result Management State
    
    @Published var resultHistory: [PerfectMomentResult] = []
    @Published var selectedResult: PerfectMomentResult?
    @Published var comparisonMode: ComparisonMode = .sideBySide
    @Published var showingShareSheet = false
    @Published var shareItem: ShareableItem?
    @Published var savedPerfectMoments: [Photo] = []
    @Published var isLoadingHistory = false
    
    // MARK: - Private Properties
    
    private let generationService: PerfectMomentGenerationServiceProtocol
    private let photoRepository: PhotoDataRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    private var currentGenerationTask: Task<Void, Never>?
    private var progressStartTime: Date?
    private let maxRetryAttempts = 3
    
    // MARK: - Initialization
    
    init(generationService: PerfectMomentGenerationServiceProtocol = PerfectMomentGenerationService(),
         photoRepository: PhotoDataRepositoryProtocol = PhotoDataRepository()) {
        self.generationService = generationService
        self.photoRepository = photoRepository
    }
    
    // MARK: - Public Methods
    
    /// Generates a Perfect Moment from the provided photo cluster with enhanced workflow state management
    func generatePerfectMoment(from cluster: PhotoCluster) async {
        // Check cache first
        let cacheKey = generateCacheKey(for: cluster)
        if let cachedResult = cachedResults[cacheKey] {
            print("Using cached Perfect Moment result for cluster")
            currentResult = cachedResult
            currentPhase = .completed
            return
        }
        
        // Cancel any existing generation task
        currentGenerationTask?.cancel()
        
        // Start new generation task
        currentGenerationTask = Task { @MainActor in
            await performGenerationWithRetry(cluster: cluster, cacheKey: cacheKey)
        }
        
        await currentGenerationTask?.value
    }
    
    /// Cancels the current generation process
    func cancelGeneration() {
        guard canCancel else { return }
        
        currentGenerationTask?.cancel()
        
        // Update state immediately
        currentPhase = .cancelled
        isGenerating = false
        canCancel = false
        progressText = "Generation cancelled by user"
        
        // Clear state after brief display
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.currentPhase == .cancelled {
                self.resetWorkflowState()
            }
        }
    }
    
    /// Retries the last failed generation
    func retryGeneration(cluster: PhotoCluster) async {
        guard retryCount < maxRetryAttempts else {
            errorMessage = "Maximum retry attempts exceeded. Please try again later."
            return
        }
        
        retryCount += 1
        await generatePerfectMoment(from: cluster)
    }
    
    // MARK: - Private Generation Methods
    
    private func performGenerationWithRetry(cluster: PhotoCluster, cacheKey: String) async {
        let maxAttempts = maxRetryAttempts
        
        for attempt in 1...maxAttempts {
            do {
                // Reset state for new attempt
                await resetGenerationState()
                
                let result = try await performGeneration(cluster: cluster)
                
                // Success - cache result and update state
                cachedResults[cacheKey] = result
                currentResult = result
                currentPhase = .completed
                retryCount = 0 // Reset retry count on success
                
                // Automatically add to result history for management
                addResultToHistory(result)
                
                // Clear progress display after brief success message
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.currentPhase == .completed {
                        self.progress = 0.0
                        self.progressText = ""
                    }
                }
                return
                
            } catch {
                retryCount = attempt
                
                // Check if this was a cancellation
                if Task.isCancelled {
                    currentPhase = .cancelled
                    return
                }
                
                // Handle different error types
                if let perfectMomentError = error as? PerfectMomentError {
                    if case .clusterNotEligible = perfectMomentError {
                        // Don't retry eligibility errors
                        await handleGenerationError(perfectMomentError)
                        return
                    }
                }
                
                // Retry transient errors
                if attempt < maxAttempts {
                    print("Perfect Moment generation attempt \(attempt) failed, retrying... Error: \(error)")
                    progressText = "Attempt \(attempt) failed, retrying..."
                    
                    // Brief delay before retry
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    
                    // Check for cancellation after delay
                    if Task.isCancelled {
                        currentPhase = .cancelled
                        return
                    }
                } else {
                    // Final attempt failed
                    await handleGenerationError(error)
                    return
                }
            }
        }
    }
    
    private func performGeneration(cluster: PhotoCluster) async throws -> PerfectMomentResult {
        progressStartTime = Date()
        
        let result = try await generationService.generatePerfectMoment(
            from: cluster,
            progressCallback: { [weak self] progressUpdate in
                Task { @MainActor in
                    await self?.handleEnhancedProgressUpdate(progressUpdate)
                }
            }
        )
        
        return result
    }
    
    private func resetGenerationState() async {
        isGenerating = true
        progress = 0.0
        errorMessage = nil
        currentResult = nil
        saveCompleted = false
        currentPhase = .analyzing
        canCancel = true
        estimatedTimeRemaining = 0
        progressStartTime = Date()
    }
    
    private func handleGenerationError(_ error: Error) async {
        currentPhase = .failed
        isGenerating = false
        canCancel = false
        
        if let perfectMomentError = error as? PerfectMomentError {
            errorMessage = perfectMomentError.userFriendlyDescription
        } else {
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }
        
        print("Perfect Moment generation failed after \(retryCount) attempts: \(error)")
    }
    
    /// Saves the generated Perfect Moment to the photo repository with enhanced metadata preservation
    func savePerfectMoment(_ result: PerfectMomentResult) async {
        isSaving = true
        errorMessage = nil
        
        do {
            // Create new Photo object with perfect moment metadata
            let perfectMomentPhoto = createPerfectMomentPhoto(from: result)
            
            // Save the generated image and photo metadata
            try await photoRepository.savePerfectMoment(perfectMomentPhoto, image: result.perfectMoment)
            
            // Add to local saved photos list
            savedPerfectMoments.insert(perfectMomentPhoto, at: 0)
            
            saveCompleted = true
            
            print("Perfect Moment saved successfully with metadata:")
            print("- Source photos: \(perfectMomentPhoto.perfectMomentMetadata?.sourcePhotoIds.count ?? 0)")
            print("- Improvements: \(perfectMomentPhoto.perfectMomentMetadata?.personReplacements.count ?? 0)")
            print("- Quality score: \(perfectMomentPhoto.perfectMomentMetadata?.qualityScore ?? 0)")
            
            // Clear save completed flag after a brief display
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.saveCompleted = false
            }
            
        } catch {
            errorMessage = "Failed to save perfect moment: \(error.localizedDescription)"
            print("Save Perfect Moment error: \(error)")
        }
        
        isSaving = false
    }
    
    /// Enhanced save with options for different save destinations
    func savePerfectMomentWithOptions(_ result: PerfectMomentResult, alsoSaveToPhotosApp: Bool = false) async {
        // Save to internal repository first
        await savePerfectMoment(result)
        
        // Optionally save to Photos app
        if alsoSaveToPhotosApp && saveCompleted {
            await saveToPhotosApp(result.perfectMoment)
        }
    }
    
    /// Saves image to the system Photos app (requires photo library permission)
    private func saveToPhotosApp(_ image: UIImage) async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                continuation.resume()
            }
            print("Perfect Moment also saved to Photos app")
        } catch {
            print("Failed to save to Photos app: \(error)")
            // Don't show error to user as this is an optional feature
        }
    }
    
    /// Analyzes a cluster to check if it's eligible for Perfect Moment generation
    func analyzePerfectMomentEligibility(for cluster: PhotoCluster) async -> PerfectMomentEligibility {
        isAnalyzing = true
        errorMessage = nil
        
        defer {
            isAnalyzing = false
        }
        
        // Use the cluster's built-in eligibility assessment
        let isEligible = await generationService.validateClusterEligibility(cluster)
        
        if isEligible {
            return cluster.perfectMomentEligibility
        } else {
            return PerfectMomentEligibility(
                isEligible: false,
                reason: .processingError,
                confidence: 0.0,
                estimatedImprovements: []
            )
        }
    }
    
    /// Resets the view model state
    func reset() {
        resetWorkflowState()
    }
    
    /// Clears cached results (useful for testing or memory management)
    func clearCache() {
        cachedResults.removeAll()
    }
    
    // MARK: - Result Management Methods
    
    /// Loads saved Perfect Moment photos from the repository
    func loadSavedPerfectMoments() async {
        isLoadingHistory = true
        errorMessage = nil
        
        do {
            let perfectMoments = try await photoRepository.loadPerfectMoments()
            savedPerfectMoments = perfectMoments
            print("Loaded \(perfectMoments.count) saved Perfect Moments")
        } catch {
            errorMessage = "Failed to load Perfect Moment history: \(error.localizedDescription)"
            print("Load Perfect Moments error: \(error)")
        }
        
        isLoadingHistory = false
    }
    
    /// Shares a Perfect Moment result using the system share sheet
    func shareResult(_ result: PerfectMomentResult) {
        shareItem = ShareableItem(perfectMomentResult: result)
        showingShareSheet = true
    }
    
    /// Shares a saved Perfect Moment photo using the system share sheet
    func sharePhoto(_ photo: Photo) {
        shareItem = ShareableItem(
            photo: photo,
            title: photo.isPerfectMoment ? "Perfect Moment" : "Photo",
            subtitle: photo.isPerfectMoment ? "Enhanced with Perfect Moment" : nil
        )
        showingShareSheet = true
    }
    
    /// Dismisses the share sheet
    func dismissShareSheet() {
        showingShareSheet = false
        shareItem = nil
    }
    
    /// Adds a result to the history and manages cache
    func addResultToHistory(_ result: PerfectMomentResult) {
        // Add to beginning of history (most recent first)
        resultHistory.insert(result, at: 0)
        
        // Limit history size to prevent memory issues
        let maxHistorySize = 50
        if resultHistory.count > maxHistorySize {
            resultHistory = Array(resultHistory.prefix(maxHistorySize))
        }
        
        // Auto-select the new result
        selectedResult = result
    }
    
    /// Selects a result for detailed viewing/comparison
    func selectResult(_ result: PerfectMomentResult) {
        selectedResult = result
    }
    
    /// Clears the selected result
    func clearSelection() {
        selectedResult = nil
    }
    
    /// Changes the comparison mode for viewing results
    func setComparisonMode(_ mode: ComparisonMode) {
        comparisonMode = mode
    }
    
    /// Deletes a saved Perfect Moment photo
    func deletePerfectMoment(_ photo: Photo) async {
        guard photo.isPerfectMoment else {
            errorMessage = "Only Perfect Moment photos can be deleted"
            return
        }
        
        do {
            try await photoRepository.deletePerfectMoment(photo)
            
            // Remove from local state
            savedPerfectMoments.removeAll { $0.id == photo.id }
            
            print("Deleted Perfect Moment photo: \(photo.id)")
        } catch {
            errorMessage = "Failed to delete Perfect Moment: \(error.localizedDescription)"
            print("Delete Perfect Moment error: \(error)")
        }
    }
    
    /// Clears result history
    func clearResultHistory() {
        resultHistory.removeAll()
        selectedResult = nil
    }
    
    // MARK: - Private Helper Methods
    
    private func resetWorkflowState() {
        currentResult = nil
        errorMessage = nil
        progress = 0.0
        progressText = ""
        isGenerating = false
        isAnalyzing = false
        isSaving = false
        saveCompleted = false
        currentPhase = .idle
        canCancel = false
        estimatedTimeRemaining = 0
        retryCount = 0
        progressStartTime = nil
        
        // Reset result management state but preserve history and saved photos
        selectedResult = nil
        showingShareSheet = false
        shareItem = nil
        isLoadingHistory = false
    }
    
    /// Initializes the ViewModel with saved Perfect Moments
    func initialize() async {
        await loadSavedPerfectMoments()
    }
    
    private func generateCacheKey(for cluster: PhotoCluster) -> String {
        // Create a cache key based on cluster photos and their IDs
        let photoIds = cluster.photos.map { $0.id.uuidString }.sorted()
        return photoIds.joined(separator: "-")
    }
    
    private func handleEnhancedProgressUpdate(_ progressUpdate: PerfectMomentProgress) async {
        let currentTime = Date()
        
        switch progressUpdate {
        case .analyzing(let text):
            currentPhase = .analyzing
            progress = 0.2
            progressText = text
            canCancel = currentPhase.canCancel
            
        case .selecting(let text):
            currentPhase = .selecting
            progress = 0.6
            progressText = text
            canCancel = currentPhase.canCancel
            
        case .compositing(let text):
            currentPhase = .compositing
            progressText = text
            canCancel = currentPhase.canCancel
            // Progress for compositing is handled by the service with specific values
        }
        
        // Update estimated time remaining
        if let startTime = progressStartTime, progress > 0.1 {
            let elapsedTime = currentTime.timeIntervalSince(startTime)
            let estimatedTotalTime = elapsedTime / Double(progress)
            estimatedTimeRemaining = max(0, estimatedTotalTime - elapsedTime)
        }
    }
    
    /// Clears any error message
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Private Methods
    
    
    private func createPerfectMomentPhoto(from result: PerfectMomentResult) -> Photo {
        // Create perfect moment metadata first
        let perfectMomentMetadata = PerfectMomentMetadata(
            isGeneratedPerfectMoment: true,
            sourcePhotoIds: [result.originalPhoto.id],
            generationTimestamp: Date(),
            qualityScore: result.qualityMetrics.overallQuality,
            personReplacements: result.improvements.map { improvement in
                PersonReplacement(
                    personID: improvement.personID,
                    sourcePhotoId: improvement.sourcePhotoId,
                    improvementType: improvement.improvementType,
                    confidence: improvement.confidence
                )
            }
        )
        
        // Generate new unique identifier for the Perfect Moment photo
        let perfectMomentPhoto = Photo(
            id: UUID(),
            assetIdentifier: UUID().uuidString,
            timestamp: result.originalPhoto.timestamp,
            location: result.originalPhoto.location,
            metadata: result.originalPhoto.metadata,
            perfectMomentMetadata: perfectMomentMetadata
        )
        
        return perfectMomentPhoto
    }
}

// MARK: - Computed Properties

extension PerfectMomentViewModel {
    /// Whether any operation is currently in progress
    var isProcessing: Bool {
        isGenerating || isAnalyzing || isSaving || isLoadingHistory
    }
    
    /// Whether a successful result is available
    var hasResult: Bool {
        currentResult != nil
    }
    
    /// Whether an error occurred
    var hasError: Bool {
        errorMessage != nil
    }
    
    /// Whether generation can be retried
    var canRetry: Bool {
        currentPhase == .failed && retryCount < maxRetryAttempts
    }
    
    /// Whether sharing is available
    var canShare: Bool {
        shareItem != nil
    }
    
    /// Whether there are saved Perfect Moments available
    var hasSavedPerfectMoments: Bool {
        !savedPerfectMoments.isEmpty
    }
    
    /// Whether there is result history available
    var hasResultHistory: Bool {
        !resultHistory.isEmpty
    }
    
    /// Current result or selected result for display
    var displayResult: PerfectMomentResult? {
        selectedResult ?? currentResult
    }
    
    /// User-friendly status text for UI display
    var statusText: String {
        if isGenerating {
            let baseText = progressText.isEmpty ? "Generating perfect moment..." : progressText
            
            // Add estimated time if available
            if estimatedTimeRemaining > 0 {
                let timeText = formatTimeRemaining(estimatedTimeRemaining)
                return "\(baseText) • \(timeText) remaining"
            }
            
            return baseText
        } else if isAnalyzing {
            return "Analyzing photos..."
        } else if isSaving {
            return "Saving perfect moment..."
        } else if saveCompleted {
            return "Perfect moment saved successfully!"
        } else if currentPhase == .cancelled {
            return "Generation cancelled"
        } else if currentPhase == .failed {
            if canRetry {
                return "Generation failed (attempt \(retryCount)/\(maxRetryAttempts))"
            } else {
                return "Generation failed"
            }
        } else if hasError {
            return errorMessage ?? "An error occurred"
        } else if hasResult {
            return "Perfect moment ready"
        } else {
            return "Ready to generate perfect moment"
        }
    }
    
    /// Formatted display of phase and progress information
    var phaseDisplayText: String {
        let phaseText = currentPhase.displayName
        
        if isGenerating && progress > 0 {
            let progressPercent = Int(progress * 100)
            return "\(phaseText) (\(progressPercent)%)"
        }
        
        return phaseText
    }
    
    // MARK: - Private Helper Methods
    
    private func formatTimeRemaining(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension PerfectMomentViewModel {
    static var preview: PerfectMomentViewModel {
        let vm = PerfectMomentViewModel()
        
        // Create sample result for preview
        let sampleOriginalPhoto = Photo(
            id: UUID(),
            assetIdentifier: "sample-original",
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(width: 1920, height: 1080)
        )
        
        let sampleImprovements = [
            PersonImprovement(
                personID: "person-1",
                sourcePhotoId: UUID(),
                improvementType: .eyesClosed,
                confidence: 0.95
            ),
            PersonImprovement(
                personID: "person-2", 
                sourcePhotoId: UUID(),
                improvementType: .poorExpression,
                confidence: 0.87
            )
        ]
        
        let sampleQualityMetrics = CompositeQualityMetrics(
            overallQuality: 0.92,
            blendingQuality: 0.89,
            lightingConsistency: 0.94,
            edgeArtifacts: 0.91,
            naturalness: 0.88
        )
        
        vm.currentResult = PerfectMomentResult(
            originalPhoto: sampleOriginalPhoto,
            perfectMoment: UIImage(systemName: "sparkles") ?? UIImage(),
            improvements: sampleImprovements,
            qualityMetrics: sampleQualityMetrics,
            processingTime: 12.5
        )
        
        return vm
    }
    
    static var previewGenerating: PerfectMomentViewModel {
        let vm = PerfectMomentViewModel()
        vm.isGenerating = true
        vm.currentPhase = .compositing
        vm.progress = 0.65
        vm.progressText = "Blending faces for perfect expressions..."
        vm.canCancel = true
        vm.estimatedTimeRemaining = 45
        return vm
    }
    
    static var previewError: PerfectMomentViewModel {
        let vm = PerfectMomentViewModel()
        vm.currentPhase = .failed
        vm.errorMessage = "Unable to create perfect moment. The photos don't contain enough face variations to improve."
        vm.retryCount = 1
        return vm
    }
    
    static var previewCancelled: PerfectMomentViewModel {
        let vm = PerfectMomentViewModel()
        vm.currentPhase = .cancelled
        vm.progressText = "Generation cancelled by user"
        return vm
    }
    
    static var previewWithCache: PerfectMomentViewModel {
        let vm = PerfectMomentViewModel()
        vm.cachedResults["sample-cache-key"] = PerfectMomentResult(
            originalPhoto: Photo(
                id: UUID(),
                assetIdentifier: "cached-sample",
                timestamp: Date(),
                location: nil,
                metadata: PhotoMetadata(width: 1920, height: 1080)
            ),
            perfectMoment: UIImage(systemName: "sparkles") ?? UIImage(),
            improvements: [],
            qualityMetrics: CompositeQualityMetrics(
                overallQuality: 0.92,
                blendingQuality: 0.89,
                lightingConsistency: 0.94,
                edgeArtifacts: 0.91,
                naturalness: 0.88
            ),
            processingTime: 8.2
        )
        return vm
    }
    
    static var previewWithHistory: PerfectMomentViewModel {
        let vm = PerfectMomentViewModel()
        
        // Add sample result history
        let sampleResult1 = PerfectMomentResult(
            originalPhoto: Photo(
                id: UUID(),
                assetIdentifier: "history-sample-1",
                timestamp: Date().addingTimeInterval(-3600),
                location: nil,
                metadata: PhotoMetadata(width: 1920, height: 1080)
            ),
            perfectMoment: UIImage(systemName: "photo") ?? UIImage(),
            improvements: [
                PersonImprovement(
                    personID: "person-1",
                    sourcePhotoId: UUID(),
                    improvementType: .eyesClosed,
                    confidence: 0.95
                )
            ],
            qualityMetrics: CompositeQualityMetrics(
                overallQuality: 0.88,
                blendingQuality: 0.85,
                lightingConsistency: 0.92,
                edgeArtifacts: 0.89,
                naturalness: 0.86
            ),
            processingTime: 12.3
        )
        
        let sampleResult2 = PerfectMomentResult(
            originalPhoto: Photo(
                id: UUID(),
                assetIdentifier: "history-sample-2",
                timestamp: Date(),
                location: nil,
                metadata: PhotoMetadata(width: 1920, height: 1080)
            ),
            perfectMoment: UIImage(systemName: "photo.fill") ?? UIImage(),
            improvements: [
                PersonImprovement(
                    personID: "person-2",
                    sourcePhotoId: UUID(),
                    improvementType: .poorExpression,
                    confidence: 0.87
                )
            ],
            qualityMetrics: CompositeQualityMetrics(
                overallQuality: 0.94,
                blendingQuality: 0.91,
                lightingConsistency: 0.96,
                edgeArtifacts: 0.93,
                naturalness: 0.92
            ),
            processingTime: 8.7
        )
        
        vm.resultHistory = [sampleResult2, sampleResult1]
        vm.selectedResult = sampleResult2
        vm.comparisonMode = .sideBySide
        
        // Add sample saved Perfect Moments
        vm.savedPerfectMoments = [
            Photo(
                id: UUID(),
                assetIdentifier: "saved-pm-1",
                timestamp: Date().addingTimeInterval(-86400),
                location: nil,
                metadata: PhotoMetadata(width: 1920, height: 1080),
                perfectMomentMetadata: PerfectMomentMetadata(
                    isGeneratedPerfectMoment: true,
                    sourcePhotoIds: [UUID()],
                    generationTimestamp: Date().addingTimeInterval(-86400),
                    qualityScore: 0.91,
                    personReplacements: []
                )
            ),
            Photo(
                id: UUID(),
                assetIdentifier: "saved-pm-2",
                timestamp: Date().addingTimeInterval(-172800),
                location: nil,
                metadata: PhotoMetadata(width: 1920, height: 1080),
                perfectMomentMetadata: PerfectMomentMetadata(
                    isGeneratedPerfectMoment: true,
                    sourcePhotoIds: [UUID(), UUID()],
                    generationTimestamp: Date().addingTimeInterval(-172800),
                    qualityScore: 0.89,
                    personReplacements: []
                )
            )
        ]
        
        return vm
    }
    
    static var previewSharing: PerfectMomentViewModel {
        let vm = PerfectMomentViewModel()
        let sampleResult = PerfectMomentResult(
            originalPhoto: Photo(
                id: UUID(),
                assetIdentifier: "share-sample",
                timestamp: Date(),
                location: nil,
                metadata: PhotoMetadata(width: 1920, height: 1080)
            ),
            perfectMoment: UIImage(systemName: "square.and.arrow.up") ?? UIImage(),
            improvements: [],
            qualityMetrics: CompositeQualityMetrics(
                overallQuality: 0.93,
                blendingQuality: 0.90,
                lightingConsistency: 0.95,
                edgeArtifacts: 0.92,
                naturalness: 0.91
            ),
            processingTime: 10.1
        )
        
        vm.currentResult = sampleResult
        vm.shareItem = ShareableItem(perfectMomentResult: sampleResult)
        vm.showingShareSheet = true
        
        return vm
    }
}
#endif