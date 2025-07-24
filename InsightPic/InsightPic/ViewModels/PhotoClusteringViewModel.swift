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
    
    init(clusteringService: PhotoClusteringServiceProtocol = PhotoClusteringService()) {
        self.clusteringService = clusteringService
    }
    
    // MARK: - Public Methods
    
    func clusterPhotos(_ photos: [Photo]) async {
        guard !photos.isEmpty else { return }
        
        isClustering = true
        clusteringProgress = 0.0
        clusteringText = "Starting photo clustering..."
        errorMessage = nil
        clusters = []
        statistics = nil
        
        do {
            let clusteredResults = try await clusteringService.clusterPhotos(photos) { completed, total in
                Task { @MainActor in
                    self.clusteringProgress = Double(completed) / Double(total)
                    self.clusteringText = "Clustering photo \(completed) of \(total)..."
                }
            }
            
            clusters = clusteredResults
            statistics = ClusteringStatistics(clusters: clusteredResults)
            findSimilarPhotoGroups()
            clusteringText = "Clustering complete! Found \(clusteredResults.count) photo groups"
            
        } catch {
            errorMessage = "Clustering failed: \(error.localizedDescription)"
            print("Photo clustering error: \(error)")
        }
        
        isClustering = false
        clusteringProgress = 0.0
    }
    
    func findSimilarPhotoGroups() {
        similarPhotoGroups = clusteringService.findSimilarPhotos(in: clusters, similarity: 0.70)
    }
    
    func getBestPhotoFromCluster(_ cluster: PhotoCluster) -> Photo? {
        // For now, return the first photo
        // This will be enhanced when we integrate with quality scoring
        return cluster.photos.first
    }
    
    func getClusterForPhoto(_ photo: Photo) -> PhotoCluster? {
        return clusters.first { cluster in
            cluster.photos.contains { $0.id == photo.id }
        }
    }
    
    func refreshClustering(for photos: [Photo]) async {
        await clusterPhotos(photos)
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
        // Get best photo from each cluster, sorted by cluster quality
        let bestFromEachCluster = sortedClustersByQuality().compactMap { cluster in
            getBestPhotoFromCluster(cluster)
        }
        
        return Array(bestFromEachCluster.prefix(count))
    }
    
    func getDiverseRecommendations(count: Int = 10) -> [Photo] {
        // Prioritize larger clusters and time diversity
        var recommendations: [Photo] = []
        let sortedBySize = sortedClustersBySize()
        
        // Take one photo from each cluster, starting with largest
        for cluster in sortedBySize {
            if recommendations.count >= count { break }
            
            if let bestPhoto = getBestPhotoFromCluster(cluster) {
                recommendations.append(bestPhoto)
            }
        }
        
        return recommendations
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