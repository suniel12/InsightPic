import Foundation
import SwiftUI
import Combine

@MainActor
class PhotoClusteringViewModel: ObservableObject {
    @Published var clusters: [PhotoCluster] = []
    @Published var isClustering = false
    @Published var clusteringProgress: Double = 0.0
    @Published var clusteringText: String = ""
    @Published var errorMessage: String?
    @Published var statistics: ClusteringStatistics?
    @Published var selectedCluster: PhotoCluster?
    @Published var similarPhotoGroups: [[Photo]] = []
    
    private let clusteringService: PhotoClusteringServiceProtocol
    private let photoRepository: PhotoDataRepositoryProtocol
    
    init(clusteringService: PhotoClusteringServiceProtocol = PhotoClusteringService(),
         photoRepository: PhotoDataRepositoryProtocol = PhotoDataRepository()) {
        self.clusteringService = clusteringService
        self.photoRepository = photoRepository
    }
    
    // MARK: - Public Methods
    
    /// Loads existing clusters from persistence
    func loadExistingClusters() async throws -> [PhotoCluster] {
        return try await photoRepository.loadClusters()
    }
    
    /// Loads existing clusters from persistence, or creates new ones if needed
    func loadOrCreateClusters(for photos: [Photo]) async {
        print("DEBUG: loadOrCreateClusters started, setting isClustering = true")
        // Show progress for first-time clustering
        isClustering = true
        clusteringProgress = 0.0
        clusteringText = "Checking for existing photo groups..."
        errorMessage = nil
        
        do {
            // Phase 1: Check for existing clusters (0-10%)
            await updateProgress(0.05, "Checking for existing photo groups...")
            
            let existingClusters = try await photoRepository.loadClusters()
            
            // Check if we need to update clusters (new photos added, or no existing clusters)
            let needsUpdate = shouldUpdateClusters(existingClusters: existingClusters, currentPhotos: photos)
            
            await updateProgress(0.10, "Analyzing photo collection...")
            
            if !existingClusters.isEmpty && !needsUpdate {
                // Use existing clusters (10-100%)
                await updateProgress(0.50, "Loading existing photo groups...")
                
                await MainActor.run {
                    self.clusters = existingClusters
                    self.statistics = ClusteringStatistics(clusters: existingClusters)
                }
                
                await updateProgress(0.80, "Organizing photo groups...")
                findSimilarPhotoGroups()
                
                await updateProgress(1.0, "Found \(existingClusters.count) existing photo groups")
            } else {
                // Create new clusters - clustering will manage its own progress
                await updateProgress(0.15, "Starting photo clustering...")
                await clusterPhotos(photos, saveResults: true)
            }
        } catch {
            // If loading fails, create new clusters - clustering will manage its own progress
            await updateProgress(0.15, "Starting photo clustering...")
            await clusterPhotos(photos, saveResults: true)
        }
        
        print("DEBUG: Setting isClustering = false, clusters count: \(clusters.count)")
        isClustering = false
        
        // Keep progress visible briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.clusteringProgress = 0.0
        }
    }
    
    func clusterPhotos(_ photos: [Photo], saveResults: Bool = true) async {
        await clusterPhotosWithProgress(photos, saveResults: saveResults, startProgress: 0.0, endProgress: 1.0)
    }
    
    private func clusterPhotosWithProgress(_ photos: [Photo], saveResults: Bool = true, startProgress: Double, endProgress: Double) async {
        guard !photos.isEmpty else { return }
        
        isClustering = true
        clusteringProgress = startProgress
        clusteringText = "Starting photo clustering..."
        errorMessage = nil
        clusters = []
        statistics = nil
        
        let progressRange = endProgress - startProgress
        
        do {
            // Filter out screenshots before clustering
            let photosToCluster = photos.filter { !$0.isLikelyScreenshot }
            
            await updateProgress(startProgress + 0.05 * progressRange, "Preparing \(photosToCluster.count) photos for clustering...")
            
            // Phase 1: Core clustering (takes 60% of progress range)
            let clusteringEndProgress = startProgress + 0.60 * progressRange
            
            let clusteredResults = try await clusteringService.clusterPhotos(photosToCluster) { completed, total in
                Task { @MainActor in
                    let clusteringProgress = Double(completed) / Double(total)
                    let currentProgress = startProgress + (clusteringProgress * 0.60 * progressRange)
                    self.clusteringProgress = currentProgress
                    
                    // Enhanced progress text based on clustering phase
                    if clusteringProgress < 0.7 {
                        self.clusteringText = "Grouping photos \(completed) of \(total)..."
                    } else if clusteringProgress < 0.98 {
                        self.clusteringText = "Analyzing photo quality \(completed) of \(total)..."
                    } else {
                        self.clusteringText = "Ranking photos in groups..."
                    }
                }
            }
            
            // Phase 2: Post-processing (takes 25% of progress range)
            await updateProgress(clusteringEndProgress, "Processing \(clusteredResults.count) photo groups...")
            
            clusters = clusteredResults
            statistics = ClusteringStatistics(clusters: clusteredResults)
            
            await updateProgress(startProgress + 0.75 * progressRange, "Organizing photo groups...")
            findSimilarPhotoGroups()
            
            // Phase 3: Save results (takes 15% of progress range)
            if saveResults {
                await updateProgress(startProgress + 0.85 * progressRange, "Saving photo groups...")
                
                do {
                    try await photoRepository.saveClusters(clusteredResults)
                    // Update cache to indicate we have analyzed photos
                    await MainActor.run {
                        UserDefaults.standard.set(true, forKey: "hasEverAnalyzedPhotos")
                    }
                } catch {
                    print("Failed to save clusters: \(error)")
                    // Don't fail the clustering operation if save fails
                }
            }
            
            await updateProgress(endProgress, "Found \(clusteredResults.count) photo groups with \(photosToCluster.count) photos!")
            
        } catch {
            errorMessage = "Clustering failed: \(error.localizedDescription)"
            print("Photo clustering error: \(error)")
        }
    }
    
    func findSimilarPhotoGroups() {
        similarPhotoGroups = clusteringService.findSimilarPhotos(in: clusters, similarity: 0.70)
    }
    
    func getBestPhotoFromCluster(_ cluster: PhotoCluster) -> Photo? {
        guard !cluster.photos.isEmpty else { return nil }
        
        // Filter photos that have quality scores
        let scoredPhotos = cluster.photos.filter { $0.overallScore != nil }
        
        // If no photos have scores, fall back to first photo
        guard !scoredPhotos.isEmpty else {
            return cluster.photos.first
        }
        
        // Calculate smart scores for each photo considering content type
        return scoredPhotos.max { photo1, photo2 in
            let smartScore1 = calculateSmartScore(for: photo1)
            let smartScore2 = calculateSmartScore(for: photo2)
            return smartScore1 < smartScore2
        }
    }
    
    private func calculateSmartScore(for photo: Photo) -> Float {
        guard let overallScore = photo.overallScore else { return 0.0 }
        
        let technical = overallScore.technical
        let faces = overallScore.faces
        let context = overallScore.context
        
        // Determine photo type based on face count
        let faceCount = photo.faceQuality?.faceCount ?? 0
        
        let weightedScore: Float
        
        switch faceCount {
        case 0:
            // Landscape/object photos - prioritize technical quality and composition
            weightedScore = technical * 0.6 + context * 0.3 + faces * 0.1
            
        case 1:
            // Single person portraits - balance technical and face quality
            weightedScore = technical * 0.4 + faces * 0.4 + context * 0.2
            
        case 2...5:
            // Small group photos - prioritize face quality
            weightedScore = faces * 0.5 + technical * 0.3 + context * 0.2
            
        default:
            // Large group photos - heavily prioritize face quality
            weightedScore = faces * 0.6 + technical * 0.2 + context * 0.2
        }
        
        // Bonus for golden hour timing (if we have timestamp)
        var finalScore = weightedScore
        if isGoldenHour(photo.timestamp) {
            finalScore += 0.1 // 10% bonus for golden hour photos
        }
        
        return min(finalScore, 1.0) // Cap at 1.0
    }
    
    private func isGoldenHour(_ timestamp: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: timestamp)
        
        // Golden hour: 6-8 AM or 6-8 PM
        return (hour >= 6 && hour <= 8) || (hour >= 18 && hour <= 20)
    }
    
    func getClusterForPhoto(_ photo: Photo) -> PhotoCluster? {
        return clusters.first { cluster in
            cluster.photos.contains { $0.id == photo.id }
        }
    }
    
    func refreshClustering(for photos: [Photo]) async {
        await clusterPhotosWithProgress(photos, saveResults: true, startProgress: 0.0, endProgress: 1.0)
    }
    
    private func updateProgress(_ progress: Double, _ text: String) async {
        await MainActor.run {
            clusteringProgress = progress
            clusteringText = text
        }
    }
    
    // MARK: - Filtering and Sorting
    
    func sortedClustersBySize() -> [PhotoCluster] {
        return clusters.sorted { $0.photos.count > $1.photos.count }
    }
    
    func sortedClustersByTime() -> [PhotoCluster] {
        return clusters.sorted { $0.medianTimestamp < $1.medianTimestamp }
    }
    
    func sortedClustersByQuality() -> [PhotoCluster] {
        return clusters.sorted { $0.averageQualityScore > $1.averageQualityScore }
    }
    
    func clustersWithMinPhotos(_ minCount: Int) -> [PhotoCluster] {
        return clusters.filter { $0.photos.count >= minCount }
    }
    
    func clustersInTimeRange(from startDate: Date, to endDate: Date) -> [PhotoCluster] {
        return clusters.filter { cluster in
            let clusterTime = cluster.medianTimestamp
            return clusterTime >= startDate && clusterTime <= endDate
        }
    }
    
    // MARK: - Statistics and Insights
    
    var totalClusters: Int {
        clusters.count
    }
    
    var totalPhotosInClusters: Int {
        clusters.reduce(0) { $0 + $1.photos.count }
    }
    
    var averageClusterSize: Double {
        guard !clusters.isEmpty else { return 0.0 }
        return Double(totalPhotosInClusters) / Double(totalClusters)
    }
    
    var singletonClusters: Int {
        clusters.filter { $0.photos.count == 1 }.count
    }
    
    var multiPhotoClusters: Int {
        clusters.filter { $0.photos.count > 1 }.count
    }
    
    var largestClusterSize: Int {
        clusters.map { $0.photos.count }.max() ?? 0
    }
    
    var clusterSizeDistribution: [String: Int] {
        var distribution: [String: Int] = [:]
        
        distribution["Single Photo"] = clusters.filter { $0.photos.count == 1 }.count
        distribution["2-3 Photos"] = clusters.filter { $0.photos.count >= 2 && $0.photos.count <= 3 }.count
        distribution["4-10 Photos"] = clusters.filter { $0.photos.count >= 4 && $0.photos.count <= 10 }.count
        distribution["11+ Photos"] = clusters.filter { $0.photos.count > 10 }.count
        
        return distribution
    }
    
    var timeSpanStatistics: (shortest: TimeInterval, longest: TimeInterval, average: TimeInterval) {
        let timeSpans = clusters.compactMap { $0.uniqueTimeSpan }
        guard !timeSpans.isEmpty else { return (0, 0, 0) }
        
        let shortest = timeSpans.min() ?? 0
        let longest = timeSpans.max() ?? 0
        let average = timeSpans.reduce(0, +) / Double(timeSpans.count)
        
        return (shortest, longest, average)
    }
    
    // MARK: - Recommendations
    
    func getRecommendedPhotos(count: Int = 10) -> [Photo] {
        // Step 1: Get best photo from each cluster (cluster winners)
        let clusterWinners = getClusterWinners()
        
        // Step 2: From cluster winners, select the best overall photos with diversity
        return selectBestWithDiversity(from: clusterWinners, count: count)
    }
    
    func getDiverseRecommendations(count: Int = 10) -> [Photo] {
        // Step 1: Get best photo from each cluster (cluster winners)
        let clusterWinners = getClusterWinners()
        
        // Step 2: Prioritize diversity over pure quality
        return selectWithMaxDiversity(from: clusterWinners, count: count)
    }
    
    private func getClusterWinners() -> [Photo] {
        // Get the best photo from each cluster, excluding screenshots
        return clusters.compactMap { cluster in
            getBestPhotoFromCluster(cluster)
        }.filter { !$0.isLikelyScreenshot }
    }
    
    private func selectBestWithDiversity(from photos: [Photo], count: Int) -> [Photo] {
        guard !photos.isEmpty else { return [] }
        
        var selectedPhotos: [Photo] = []
        var remainingPhotos = photos
        
        // First, select the highest quality photo overall
        if let bestPhoto = remainingPhotos.max(by: { 
            calculateSmartScore(for: $0) < calculateSmartScore(for: $1) 
        }) {
            selectedPhotos.append(bestPhoto)
            remainingPhotos.removeAll { $0.id == bestPhoto.id }
        }
        
        // Then select remaining photos balancing quality and diversity
        while selectedPhotos.count < count && !remainingPhotos.isEmpty {
            let nextPhoto = findMostDiverseQualityPhoto(
                from: remainingPhotos, 
                alreadySelected: selectedPhotos
            )
            
            if let photo = nextPhoto {
                selectedPhotos.append(photo)
                remainingPhotos.removeAll { $0.id == photo.id }
            } else {
                break
            }
        }
        
        return selectedPhotos
    }
    
    private func selectWithMaxDiversity(from photos: [Photo], count: Int) -> [Photo] {
        guard !photos.isEmpty else { return [] }
        
        var selectedPhotos: [Photo] = []
        let remainingPhotos = photos
        
        // Group photos by content type for diversity
        let landscapePhotos = remainingPhotos.filter { ($0.faceQuality?.faceCount ?? 0) == 0 }
        let portraitPhotos = remainingPhotos.filter { ($0.faceQuality?.faceCount ?? 0) == 1 }
        let groupPhotos = remainingPhotos.filter { ($0.faceQuality?.faceCount ?? 0) > 1 }
        
        // Distribute selections across content types
        let targetCounts = calculateDiversityTargets(
            landscapes: landscapePhotos.count,
            portraits: portraitPhotos.count,
            groups: groupPhotos.count,
            totalCount: count
        )
        
        // Select best from each category
        selectedPhotos.append(contentsOf: selectBestFromCategory(landscapePhotos, count: targetCounts.landscapes))
        selectedPhotos.append(contentsOf: selectBestFromCategory(portraitPhotos, count: targetCounts.portraits))
        selectedPhotos.append(contentsOf: selectBestFromCategory(groupPhotos, count: targetCounts.groups))
        
        // Fill remaining slots with highest quality remaining photos
        let remaining = photos.filter { photo in !selectedPhotos.contains { $0.id == photo.id } }
        let additionalCount = count - selectedPhotos.count
        if additionalCount > 0 {
            let bestRemaining = remaining
                .sorted { calculateSmartScore(for: $0) > calculateSmartScore(for: $1) }
                .prefix(additionalCount)
            selectedPhotos.append(contentsOf: bestRemaining)
        }
        
        return Array(selectedPhotos.prefix(count))
    }
    
    private func findMostDiverseQualityPhoto(from photos: [Photo], alreadySelected: [Photo]) -> Photo? {
        return photos.max { photo1, photo2 in
            let diversity1 = calculateDiversityScore(photo1, compared: alreadySelected)
            let diversity2 = calculateDiversityScore(photo2, compared: alreadySelected)
            let quality1 = calculateSmartScore(for: photo1)
            let quality2 = calculateSmartScore(for: photo2)
            
            // Weight diversity and quality equally
            let combined1 = diversity1 * 0.5 + quality1 * 0.5
            let combined2 = diversity2 * 0.5 + quality2 * 0.5
            
            return combined1 < combined2
        }
    }
    
    private func calculateDiversityScore(_ photo: Photo, compared selectedPhotos: [Photo]) -> Float {
        guard !selectedPhotos.isEmpty else { return 1.0 }
        
        var diversityScore: Float = 0.0
        
        // Content type diversity
        let photoFaceCount = photo.faceQuality?.faceCount ?? 0
        let hasLandscape = selectedPhotos.contains { ($0.faceQuality?.faceCount ?? 0) == 0 }
        let hasPortrait = selectedPhotos.contains { ($0.faceQuality?.faceCount ?? 0) == 1 }
        let hasGroup = selectedPhotos.contains { ($0.faceQuality?.faceCount ?? 0) > 1 }
        
        switch photoFaceCount {
        case 0: diversityScore += hasLandscape ? 0.0 : 0.4
        case 1: diversityScore += hasPortrait ? 0.0 : 0.4
        default: diversityScore += hasGroup ? 0.0 : 0.4
        }
        
        // Time diversity (prefer photos from different time periods)
        let timeDiversity = calculateTimeDiversity(photo, compared: selectedPhotos)
        diversityScore += timeDiversity * 0.3
        
        // Quality uniqueness (prefer photos that stand out)
        let qualityUniqueness = calculateQualityUniqueness(photo, compared: selectedPhotos)
        diversityScore += qualityUniqueness * 0.3
        
        return min(diversityScore, 1.0)
    }
    
    private func calculateTimeDiversity(_ photo: Photo, compared selectedPhotos: [Photo]) -> Float {
        let photoTime = photo.timestamp
        let minTimeDifference: TimeInterval = 3600 // 1 hour
        
        for selectedPhoto in selectedPhotos {
            let timeDifference = abs(photoTime.timeIntervalSince(selectedPhoto.timestamp))
            if timeDifference < minTimeDifference {
                return 0.0 // Too close in time
            }
        }
        
        return 1.0 // Good time diversity
    }
    
    private func calculateQualityUniqueness(_ photo: Photo, compared selectedPhotos: [Photo]) -> Float {
        let photoScore = calculateSmartScore(for: photo)
        let tolerance: Float = 0.1
        
        for selectedPhoto in selectedPhotos {
            let selectedScore = calculateSmartScore(for: selectedPhoto)
            if abs(photoScore - selectedScore) < tolerance {
                return 0.0 // Too similar in quality
            }
        }
        
        return 1.0 // Unique quality level
    }
    
    private func calculateDiversityTargets(landscapes: Int, portraits: Int, groups: Int, totalCount: Int) -> (landscapes: Int, portraits: Int, groups: Int) {
        let totalAvailable = landscapes + portraits + groups
        guard totalAvailable > 0 else { return (0, 0, 0) }
        
        // Aim for balanced representation, but respect availability
        let landscapeRatio = min(0.4, Double(landscapes) / Double(totalAvailable))
        let portraitRatio = min(0.3, Double(portraits) / Double(totalAvailable))
        let groupRatio = min(0.3, Double(groups) / Double(totalAvailable))
        
        let landscapeTarget = max(1, min(landscapes, Int(Double(totalCount) * landscapeRatio)))
        let portraitTarget = max(1, min(portraits, Int(Double(totalCount) * portraitRatio)))
        let groupTarget = max(1, min(groups, Int(Double(totalCount) * groupRatio)))
        
        // Adjust if we exceed total count
        let total = landscapeTarget + portraitTarget + groupTarget
        if total > totalCount {
            // Proportionally reduce
            let factor = Double(totalCount) / Double(total)
            return (
                max(0, Int(Double(landscapeTarget) * factor)),
                max(0, Int(Double(portraitTarget) * factor)),
                max(0, Int(Double(groupTarget) * factor))
            )
        }
        
        return (landscapeTarget, portraitTarget, groupTarget)
    }
    
    private func selectBestFromCategory(_ photos: [Photo], count: Int) -> [Photo] {
        let sorted = photos.sorted { calculateSmartScore(for: $0) > calculateSmartScore(for: $1) }
        return Array(sorted.prefix(count))
    }
    
    /// Determines if existing clusters need to be updated based on current photos
    private func shouldUpdateClusters(existingClusters: [PhotoCluster], currentPhotos: [Photo]) -> Bool {
        // Get photo IDs from existing clusters
        let clusteredPhotoIds = Set(existingClusters.flatMap { cluster in
            cluster.photos.map { $0.id }
        })
        
        // Get current photo IDs (excluding screenshots)
        let currentPhotoIds = Set(currentPhotos.filter { !$0.isLikelyScreenshot }.map { $0.id })
        
        // If photo sets are different, we need to update
        if clusteredPhotoIds != currentPhotoIds {
            return true
        }
        
        // Check if clusters are too old (older than 7 days)
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let hasOldClusters = existingClusters.contains { cluster in
            cluster.timeRange?.start ?? Date.distantPast < weekAgo
        }
        
        return hasOldClusters
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
extension PhotoClusteringViewModel {
    static var preview: PhotoClusteringViewModel {
        let vm = PhotoClusteringViewModel()
        
        // Create sample clusters
        var cluster1 = PhotoCluster()
        cluster1.add(Photo(
            id: UUID(),
            assetIdentifier: "sample-1",
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(width: 1920, height: 1080)
        ), fingerprint: nil)
        
        var cluster2 = PhotoCluster()
        cluster2.add(Photo(
            id: UUID(),
            assetIdentifier: "sample-2", 
            timestamp: Date().addingTimeInterval(-3600),
            location: nil,
            metadata: PhotoMetadata(width: 1920, height: 1080)
        ), fingerprint: nil)
        cluster2.add(Photo(
            id: UUID(),
            assetIdentifier: "sample-3",
            timestamp: Date().addingTimeInterval(-3500),
            location: nil,
            metadata: PhotoMetadata(width: 1920, height: 1080)
        ), fingerprint: nil)
        
        vm.clusters = [cluster1, cluster2]
        vm.statistics = ClusteringStatistics(clusters: vm.clusters)
        
        return vm
    }
}
#endif