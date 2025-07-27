import Foundation
import UIKit
import Darwin

// MARK: - Cluster Representative Model

struct ClusterRepresentative: Identifiable {
    let id = UUID()
    let cluster: PhotoCluster
    let bestPhoto: Photo
    let importance: Float // Based on cluster size
    let qualityScore: Float
    let facialQualityScore: Float // Enhanced facial quality scoring
    let rankingConfidence: Float // Confidence in representative selection
    let selectionReason: RepresentativeSelectionReason // Why this photo was chosen
    let timeRange: (start: Date, end: Date)?
    
    var clusterSize: Int {
        return cluster.photos.count
    }
    
    var isImportantMoment: Bool {
        return clusterSize >= 3 // 3+ photos indicates intentional moment capture
    }
    
    var combinedQualityScore: Float {
        // Weighted combination of overall quality and facial quality
        let photoType = PhotoType.detect(from: bestPhoto)
        return photoType.isPersonFocused ? 
            (qualityScore * 0.4 + facialQualityScore * 0.6) :
            (qualityScore * 0.8 + facialQualityScore * 0.2)
    }
}

// MARK: - Cluster Ranking Result

struct ClusterRankingResult {
    let photo: Photo
    let qualityScore: Float
    let facialQualityScore: Float
    let confidence: Float
    let reason: RepresentativeSelectionReason
}

// MARK: - Cluster Facial Analysis Models

/// Comprehensive facial diversity analysis for cluster optimization
struct ClusterFacialDiversityAnalysis {
    let clusterType: ClusterFacialType
    let peopleCount: Int
    let faceConsistencyScore: Float // How consistent facial quality is (0.0-1.0)
    let diversityScore: Float // How much facial variety exists (0.0-1.0)
    let bestFacePerPerson: [String: Photo] // Person ID -> Best photo for that person
    let facialQualityDistribution: FacialQualityDistribution
    let recommendedRepresentative: Photo?
    
    /// Indicates if cluster has good potential for facial optimization
    var hasGoodFacialPotential: Bool {
        return peopleCount > 0 && diversityScore > 0.2 && faceConsistencyScore > 0.4
    }
    
    /// Returns user-friendly summary of facial analysis
    var facialSummary: String {
        switch clusterType {
        case .singlePerson:
            if faceConsistencyScore > 0.7 {
                return "Single person with consistent quality"
            } else {
                return "Single person with varying expressions"
            }
        case .multiplePeople:
            if faceConsistencyScore > 0.6 && diversityScore > 0.3 {
                return "Group photo with good facial variety"
            } else if faceConsistencyScore > 0.7 {
                return "Group photo with consistent expressions"
            } else {
                return "Group photo with mixed facial quality"
            }
        case .noPeople:
            return "No people detected in cluster"
        }
    }
}

/// Types of facial clusters for specialized optimization
enum ClusterFacialType {
    case singlePerson // One person across multiple photos
    case multiplePeople // Multiple different people
    case noPeople // No faces detected
}

/// Distribution of facial quality within a cluster
struct FacialQualityDistribution {
    var excellent: Int // 0.8+ facial quality
    var good: Int // 0.6-0.8 facial quality
    var fair: Int // 0.4-0.6 facial quality
    var poor: Int // <0.4 facial quality
    
    var totalPhotos: Int {
        return excellent + good + fair + poor
    }
    
    var qualityPercentages: (excellent: Float, good: Float, fair: Float, poor: Float) {
        let total = Float(totalPhotos)
        guard total > 0 else { return (0, 0, 0, 0) }
        
        return (
            excellent: Float(excellent) / total * 100,
            good: Float(good) / total * 100,
            fair: Float(fair) / total * 100,
            poor: Float(poor) / total * 100
        )
    }
    
    var dominantQuality: String {
        let max = Swift.max(excellent, good, fair, poor)
        
        switch max {
        case excellent: return "Excellent"
        case good: return "Good"
        case fair: return "Fair"
        default: return "Poor"
        }
    }
    
    var hasGoodQualityMajority: Bool {
        return (excellent + good) > (fair + poor)
    }
}

// MARK: - Cluster Context Analysis Models

/// Comprehensive analysis of cluster context for optimal ranking
struct ClusterContextAnalysis {
    let clusterType: ClusterType
    let photoTypeBreakdown: [PhotoType: Int]
    let contentAnalysis: String
    let recommendedWeighting: RankingWeights
    let confidence: Float
    
    /// User-friendly description of cluster content
    var contextDescription: String {
        switch clusterType {
        case .portraitSession:
            return "Portrait photography session with focus on facial quality"
        case .groupEvent:
            return "Group event with multiple people and social interactions"
        case .landscapeCollection:
            return "Landscape photography emphasizing composition and technical quality"
        case .actionSequence:
            return "Action or movement sequence prioritizing sharpness and timing"
        case .mixedContent:
            return "Mixed content requiring balanced quality assessment"
        }
    }
}

/// Cluster type classification for context-aware ranking
enum ClusterType {
    case portraitSession // Single person or portrait-focused cluster
    case groupEvent // Multiple people, social gathering
    case landscapeCollection // Scenery, nature, landscapes
    case actionSequence // Sports, movement, action photos
    case mixedContent // Mixed photo types
    
    /// Indicates if this cluster type benefits from facial analysis
    var prioritizesFacialQuality: Bool {
        switch self {
        case .portraitSession, .groupEvent:
            return true
        case .landscapeCollection, .actionSequence, .mixedContent:
            return false
        }
    }
    
    /// Returns the emphasis for this cluster type
    var qualityEmphasis: String {
        switch self {
        case .portraitSession:
            return "Facial expressions and pose quality"
        case .groupEvent:
            return "Group dynamics and individual facial quality"
        case .landscapeCollection:
            return "Composition and technical excellence"
        case .actionSequence:
            return "Timing and motion capture"
        case .mixedContent:
            return "Balanced overall quality"
        }
    }
}

/// Adaptive ranking weights based on cluster context
struct RankingWeights {
    let technical: Float // Weight for technical quality (0.0-1.0)
    let facial: Float // Weight for facial quality (0.0-1.0)
    let contextual: Float // Weight for contextual factors (0.0-1.0)
    
    /// Validates that weights sum approximately to 1.0
    var isValid: Bool {
        let sum = technical + facial + contextual
        return abs(sum - 1.0) < 0.01 // Allow small floating-point variance
    }
    
    /// Pre-defined weight configurations
    static let balanced = RankingWeights(technical: 0.4, facial: 0.4, contextual: 0.2)
    static let facialPriority = RankingWeights(technical: 0.2, facial: 0.7, contextual: 0.1)
    static let technicalPriority = RankingWeights(technical: 0.7, facial: 0.1, contextual: 0.2)
    static let landscapeFocus = RankingWeights(technical: 0.6, facial: 0.1, contextual: 0.3)
    
    /// User-friendly description of weighting strategy
    var description: String {
        if facial > 0.6 {
            return "Prioritizing facial quality and expressions"
        } else if technical > 0.6 {
            return "Emphasizing technical and compositional excellence"
        } else {
            return "Using balanced quality assessment"
        }
    }
}

// MARK: - Cluster Curation Service

class ClusterCurationService: ObservableObject {
    
    // MARK: - Caching Infrastructure (Task 4.1)
    
    /// Actor for thread-safe cluster ranking cache management
    private actor RankingCacheManager {
        private var representativeCache: [UUID: ClusterRepresentative] = [:]
        private var rankingResultCache: [UUID: ClusterRankingResult] = [:]
        private var lastUpdateTimes: [UUID: Date] = [:]
        private let cacheExpirationTime: TimeInterval = 3600 // 1 hour
        
        func getRepresentative(for clusterID: UUID) -> ClusterRepresentative? {
            // Check if cache entry has expired
            if let lastUpdate = lastUpdateTimes[clusterID],
               Date().timeIntervalSince(lastUpdate) > cacheExpirationTime {
                clearCluster(clusterID)
                return nil
            }
            return representativeCache[clusterID]
        }
        
        func setRepresentative(_ representative: ClusterRepresentative, for clusterID: UUID) {
            representativeCache[clusterID] = representative
            lastUpdateTimes[clusterID] = Date()
        }
        
        func getRankingResult(for clusterID: UUID) -> ClusterRankingResult? {
            // Check if cache entry has expired
            if let lastUpdate = lastUpdateTimes[clusterID],
               Date().timeIntervalSince(lastUpdate) > cacheExpirationTime {
                clearCluster(clusterID)
                return nil
            }
            return rankingResultCache[clusterID]
        }
        
        func setRankingResult(_ result: ClusterRankingResult, for clusterID: UUID) {
            rankingResultCache[clusterID] = result
            lastUpdateTimes[clusterID] = Date()
        }
        
        func clearCluster(_ clusterID: UUID) {
            representativeCache.removeValue(forKey: clusterID)
            rankingResultCache.removeValue(forKey: clusterID)
            lastUpdateTimes.removeValue(forKey: clusterID)
        }
        
        func clearAll() {
            representativeCache.removeAll()
            rankingResultCache.removeAll()
            lastUpdateTimes.removeAll()
        }
        
        func invalidateExpiredEntries() {
            let now = Date()
            let expiredKeys = lastUpdateTimes.compactMap { key, lastUpdate in
                now.timeIntervalSince(lastUpdate) > cacheExpirationTime ? key : nil
            }
            
            for key in expiredKeys {
                clearCluster(key)
            }
        }
        
        var statistics: (representativeCount: Int, rankingCount: Int, lastCleanup: Date?) {
            return (representativeCache.count, rankingResultCache.count, lastUpdateTimes.values.max())
        }
        
        func isClusterCached(_ clusterID: UUID) -> Bool {
            guard let lastUpdate = lastUpdateTimes[clusterID] else { return false }
            return Date().timeIntervalSince(lastUpdate) <= cacheExpirationTime
        }
        
        /// Checks if cluster needs incremental update based on photo count changes
        func needsIncrementalUpdate(_ cluster: PhotoCluster) -> Bool {
            guard let cachedRepresentative = representativeCache[cluster.id] else { return true }
            
            // Check if photo count has changed (Task 4.2)
            return cachedRepresentative.clusterSize != cluster.photos.count
        }
    }
    
    /// Thread-safe ranking cache manager
    private let rankingCacheManager = RankingCacheManager()
    
    // MARK: - Dependencies
    
    private let faceQualityAnalysisService: FaceQualityAnalysisService
    
    // MARK: - Initialization
    
    init(faceQualityAnalysisService: FaceQualityAnalysisService = FaceQualityAnalysisService()) {
        self.faceQualityAnalysisService = faceQualityAnalysisService
        
        // Schedule periodic cache cleanup
        schedulePeriodicCacheCleanup()
    }
    
    // MARK: - Cache Management (Task 4.1)
    
    /// Schedules periodic cache cleanup to prevent memory bloat
    private func schedulePeriodicCacheCleanup() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(1800)) // Clean every 30 minutes
                await rankingCacheManager.invalidateExpiredEntries()
                print("📊 ClusterCuration: Cleaned expired cache entries")
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Optimized batch processing for facial analysis across multiple clusters (Task 4.3)
    private func batchProcessFacialAnalysis(for clusters: [PhotoCluster]) async -> [UUID: ClusterFaceAnalysis] {
        var results: [UUID: ClusterFaceAnalysis] = [:]
        
        // Group clusters by priority (clusters with people get higher priority)
        let prioritizedClusters = await withTaskGroup(of: (PhotoCluster, Bool).self) { group in
            for cluster in clusters {
                group.addTask {
                    let photoType = await self.detectClusterType(cluster)
                    let hasPeople = photoType.isPersonFocused
                    return (cluster, hasPeople)
                }
            }
            
            var clusterPriorities: [(PhotoCluster, Bool)] = []
            for await result in group {
                clusterPriorities.append(result)
            }
            
            return clusterPriorities.sorted { $0.1 && !$1.1 }.map { $0.0 }
        }
        
        // Process clusters in batches to prevent memory issues
        let batchSize = 3 // Process 3 clusters at a time
        
        for batch in stride(from: 0, to: prioritizedClusters.count, by: batchSize).map({
            Array(prioritizedClusters[$0..<min($0 + batchSize, prioritizedClusters.count)])
        }) {
            print("📊 ClusterCuration: Batch processing \(batch.count) clusters for facial analysis...")
            
            await withTaskGroup(of: (UUID, ClusterFaceAnalysis).self) { group in
                for cluster in batch {
                    group.addTask {
                        let analysis = await self.faceQualityAnalysisService.analyzeFaceQualityInCluster(cluster)
                        return (cluster.id, analysis)
                    }
                }
                
                for await (clusterID, analysis) in group {
                    results[clusterID] = analysis
                }
            }
            
            // Small delay between batches to prevent overwhelming the system
            if batch.count == batchSize {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        
        return results
    }
    
    /// Analyzes clusters and returns representatives sorted by importance (with intelligent caching)
    func curateClusterRepresentatives(from clusters: [PhotoCluster]) async -> [ClusterRepresentative] {
        var representatives: [ClusterRepresentative] = []
        var cacheMisses = 0
        var cacheHits = 0
        
        print("📊 ClusterCuration: Processing \(clusters.count) clusters...")
        
        for cluster in clusters {
            guard !cluster.photos.isEmpty else { continue }
            
            // Check cache first (Task 4.1 - Intelligent Caching)
            if let cachedRepresentative = await rankingCacheManager.getRepresentative(for: cluster.id) {
                // Check if incremental update is needed (Task 4.2)
                let needsUpdate = await rankingCacheManager.needsIncrementalUpdate(cluster)
                
                if !needsUpdate {
                    representatives.append(cachedRepresentative)
                    cacheHits += 1
                    continue
                } else {
                    print("🔄 ClusterCuration: Incremental update needed for cluster \(cluster.id) (photo count changed)")
                }
            }
            
            // Cache miss or needs update - perform ranking analysis
            cacheMisses += 1
            
            // Find best photo in cluster using enhanced quality scoring with facial analysis
            let rankingResult = await findBestPhotoInClusterWithRanking(cluster)
            
            // Calculate importance based on cluster size
            let importance = calculateClusterImportance(cluster)
            
            let representative = ClusterRepresentative(
                cluster: cluster,
                bestPhoto: rankingResult.photo,
                importance: importance,
                qualityScore: rankingResult.qualityScore,
                facialQualityScore: rankingResult.facialQualityScore,
                rankingConfidence: rankingResult.confidence,
                selectionReason: rankingResult.reason,
                timeRange: cluster.timeRange
            )
            
            // Cache the representative and ranking result for future use (Task 4.1)
            await rankingCacheManager.setRepresentative(representative, for: cluster.id)
            await rankingCacheManager.setRankingResult(rankingResult, for: cluster.id)
            
            // Record debug information for analytics (Task 4.1.4)
            if cluster.photos.count > 1 {
                let alternativePhotos = cluster.photos.filter { $0.id != rankingResult.photo.id }.prefix(3).map { photo in
                    RankingDebugInfo.PhotoRankingDetail(
                        photo: photo,
                        technicalScore: Float(photo.overallScore?.technical ?? 0.5),
                        facialScore: photo.faceQuality?.compositeScore ?? 0.5,
                        contextScore: Float(photo.overallScore?.context ?? 0.5),
                        combinedScore: Float(photo.overallScore?.overall ?? 0.5),
                        rankPosition: cluster.photos.firstIndex(where: { $0.id == photo.id }) ?? 0,
                        disqualificationReasons: []
                    )
                }
                
                let clusterType = await detectClusterType(cluster)
                let weights = getOptimalRankingWeights(for: .mixedContent, cluster: cluster) // Simplified
                
                let decisionFactors = RankingDebugInfo.DecisionFactors(
                    clusterType: .mixedContent, // Simplified for now
                    weightingUsed: weights,
                    facialAnalysisInfluence: clusterType.isPersonFocused ? 0.7 : 0.3,
                    cacheHit: false,
                    confidenceLevel: rankingResult.confidence
                )
                
                let processingSteps = [
                    RankingDebugInfo.ProcessingStep(
                        step: "Ranking Analysis",
                        duration: 0.1, // Simplified
                        photosProcessed: cluster.photos.count,
                        cacheHits: cacheHits
                    )
                ]
                
                await recordRankingDebugInfo(
                    clusterID: cluster.id,
                    selectedPhoto: rankingResult.photo,
                    alternativePhotos: Array(alternativePhotos),
                    decisionFactors: decisionFactors,
                    processingSteps: processingSteps
                )
            }
            
            representatives.append(representative)
        }
        
        // Log cache performance statistics
        let cacheStats = await rankingCacheManager.statistics
        print("📊 ClusterCuration: Cache performance - Hits: \(cacheHits), Misses: \(cacheMisses), Total cached: \(cacheStats.representativeCount)")
        
        // Sort by importance (cluster size) then by combined quality score
        return representatives.sorted { rep1, rep2 in
            if rep1.importance != rep2.importance {
                return rep1.importance > rep2.importance
            }
            return rep1.combinedQualityScore > rep2.combinedQualityScore
        }
    }
    
    // MARK: - Background Processing (Task 4.4)
    
    /// Updates cluster rankings in the background with progress reporting
    func updateRankingsInBackground(
        for clusters: [PhotoCluster],
        progressCallback: @escaping (Float, String) -> Void
    ) async {
        let total = Float(clusters.count)
        
        for (index, cluster) in clusters.enumerated() {
            let progress = Float(index) / total
            progressCallback(progress, "Updating cluster \(index + 1) of \(clusters.count)...")
            
            // Check if update is needed
            let needsUpdate = await rankingCacheManager.needsIncrementalUpdate(cluster)
            
            if needsUpdate {
                // Perform ranking analysis
                let rankingResult = await findBestPhotoInClusterWithRanking(cluster)
                let importance = calculateClusterImportance(cluster)
                
                let representative = ClusterRepresentative(
                    cluster: cluster,
                    bestPhoto: rankingResult.photo,
                    importance: importance,
                    qualityScore: rankingResult.qualityScore,
                    facialQualityScore: rankingResult.facialQualityScore,
                    rankingConfidence: rankingResult.confidence,
                    selectionReason: rankingResult.reason,
                    timeRange: cluster.timeRange
                )
                
                // Update cache
                await rankingCacheManager.setRepresentative(representative, for: cluster.id)
                await rankingCacheManager.setRankingResult(rankingResult, for: cluster.id)
            }
            
            // Small delay to prevent overwhelming the system
            try? await Task.sleep(for: .milliseconds(50))
        }
        
        progressCallback(1.0, "Ranking updates complete")
    }
    
    // MARK: - Ranking Analytics and Validation (Task 4.1)
    
    /// Comprehensive ranking quality metrics for algorithm validation
    struct RankingQualityMetrics {
        let accuracy: Float                    // How often automatic selection matches user preference
        let confidence: Float                  // Average ranking confidence across clusters
        let faceQualityImprovement: Float     // Facial quality improvement vs random selection
        let overallQualityImprovement: Float  // Overall quality improvement vs random selection
        let consistencyScore: Float           // How consistent rankings are across similar clusters
        let processingTime: TimeInterval      // Average time to compute rankings
        let cacheHitRate: Float              // Cache performance metric
        let userOverrideRate: Float          // How often users manually override selections
        let clusterTypeAccuracy: [ClusterType: Float] // Accuracy broken down by cluster type
        
        var qualityGrade: String {
            let avgScore = (accuracy + confidence + faceQualityImprovement + overallQualityImprovement + consistencyScore) / 5.0
            switch avgScore {
            case 0.9...1.0: return "Excellent"
            case 0.8..<0.9: return "Very Good"
            case 0.7..<0.8: return "Good"
            case 0.6..<0.7: return "Fair"
            default: return "Needs Improvement"
            }
        }
    }
    
    /// User satisfaction tracking for thumbnail selections
    struct UserSatisfactionData {
        let clusterID: UUID
        let selectedRepresentative: Photo
        let userAction: UserAction
        let timestamp: Date
        let sessionDuration: TimeInterval?
        let deviceInfo: DeviceInfo?
        
        enum UserAction {
            case accepted           // User kept automatic selection
            case manualOverride     // User changed to different photo
            case rejected          // User dismissed cluster
            case shared            // User shared the photo (high satisfaction indicator)
            case saved             // User saved photo to favorites
        }
        
        struct DeviceInfo {
            let model: String
            let osVersion: String
            let appVersion: String
        }
    }
    
    /// A/B Testing framework for ranking algorithm improvements
    struct ABTestConfig {
        let testID: String
        let isActive: Bool
        let variantA: RankingWeights    // Control group weights
        let variantB: RankingWeights    // Test group weights
        let trafficSplit: Float         // Percentage for variant B (0.0-1.0)
        let startDate: Date
        let endDate: Date
        let minimumSampleSize: Int
        
        var isCurrentlyRunning: Bool {
            let now = Date()
            return isActive && now >= startDate && now <= endDate
        }
    }
    
    /// Debug information for ranking decisions
    struct RankingDebugInfo {
        let clusterID: UUID
        let selectedPhoto: Photo
        let alternativePhotos: [PhotoRankingDetail]
        let decisionFactors: DecisionFactors
        let processingSteps: [ProcessingStep]
        let timestamp: Date
        
        struct PhotoRankingDetail {
            let photo: Photo
            let technicalScore: Float
            let facialScore: Float
            let contextScore: Float
            let combinedScore: Float
            let rankPosition: Int
            let disqualificationReasons: [String]
        }
        
        struct DecisionFactors {
            let clusterType: ClusterType
            let weightingUsed: RankingWeights
            let facialAnalysisInfluence: Float
            let cacheHit: Bool
            let confidenceLevel: Float
        }
        
        struct ProcessingStep {
            let step: String
            let duration: TimeInterval
            let photosProcessed: Int
            let cacheHits: Int
        }
    }
    
    /// Analytics data manager using Actor pattern for thread safety
    private actor AnalyticsManager {
        private var qualityMetrics: [Date: RankingQualityMetrics] = [:]
        private var userSatisfactionData: [UserSatisfactionData] = []
        private var debugLogs: [RankingDebugInfo] = []
        private var abTestConfigs: [String: ABTestConfig] = [:]
        private var abTestResults: [String: [UserSatisfactionData]] = [:]
        
        // Data retention: Keep 30 days of analytics data
        private let dataRetentionDays: TimeInterval = 30 * 24 * 60 * 60
        
        func recordQualityMetrics(_ metrics: RankingQualityMetrics) {
            qualityMetrics[Date()] = metrics
            cleanupOldData()
        }
        
        func recordUserSatisfaction(_ data: UserSatisfactionData) {
            userSatisfactionData.append(data)
            
            // Also record for A/B test if applicable
            if let activeTest = getActiveABTest() {
                abTestResults[activeTest.testID, default: []].append(data)
            }
            
            cleanupOldData()
        }
        
        func recordDebugInfo(_ info: RankingDebugInfo) {
            debugLogs.append(info)
            
            // Keep only last 1000 debug entries to prevent memory bloat
            if debugLogs.count > 1000 {
                debugLogs.removeFirst(debugLogs.count - 1000)
            }
        }
        
        func getLatestQualityMetrics() -> RankingQualityMetrics? {
            return qualityMetrics.values.max(by: { $0.processingTime < $1.processingTime })
        }
        
        func getUserSatisfactionSummary(days: Int = 7) -> (totalInteractions: Int, satisfactionRate: Float, overrideRate: Float) {
            let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))
            let recentData = userSatisfactionData.filter { $0.timestamp >= cutoffDate }
            
            let total = recentData.count
            let satisfied = recentData.filter { 
                $0.userAction == .accepted || $0.userAction == .shared || $0.userAction == .saved 
            }.count
            let overrides = recentData.filter { $0.userAction == .manualOverride }.count
            
            let satisfactionRate = total > 0 ? Float(satisfied) / Float(total) : 0.0
            let overrideRate = total > 0 ? Float(overrides) / Float(total) : 0.0
            
            return (total, satisfactionRate, overrideRate)
        }
        
        func setABTestConfig(_ config: ABTestConfig) {
            abTestConfigs[config.testID] = config
        }
        
        func getActiveABTest() -> ABTestConfig? {
            return abTestConfigs.values.first { $0.isCurrentlyRunning }
        }
        
        func getABTestResults(_ testID: String) -> [UserSatisfactionData] {
            return abTestResults[testID] ?? []
        }
        
        func getDebugInfo(for clusterID: UUID) -> [RankingDebugInfo] {
            return debugLogs.filter { $0.clusterID == clusterID }
        }
        
        private func cleanupOldData() {
            let cutoffDate = Date().addingTimeInterval(-dataRetentionDays)
            
            // Clean quality metrics
            qualityMetrics = qualityMetrics.filter { $0.key >= cutoffDate }
            
            // Clean user satisfaction data
            userSatisfactionData = userSatisfactionData.filter { $0.timestamp >= cutoffDate }
            
            // Clean A/B test results
            for (testID, results) in abTestResults {
                abTestResults[testID] = results.filter { $0.timestamp >= cutoffDate }
            }
        }
    }
    
    /// Thread-safe analytics manager
    private let analyticsManager = AnalyticsManager()
    
    // MARK: - Cache Management Public Interface
    
    /// Clears cluster ranking cache to free memory when needed
    func clearRankingCache() async {
        await rankingCacheManager.clearAll()
        print("🧹 ClusterCuration: Cleared ranking cache")
    }
    
    /// Clears specific cluster from cache (useful when cluster content changes)
    func clearClusterCache(_ clusterID: UUID) async {
        await rankingCacheManager.clearCluster(clusterID)
        print("🧹 ClusterCuration: Cleared cache for cluster \(clusterID)")
    }
    
    /// Returns cache statistics for monitoring
    func getRankingCacheStatistics() async -> (representativeCount: Int, rankingCount: Int, lastCleanup: Date?) {
        return await rankingCacheManager.statistics
    }
    
    /// Forces cache invalidation and cleanup
    func performCacheCleanup() async {
        await rankingCacheManager.invalidateExpiredEntries()
        let stats = await rankingCacheManager.statistics
        print("🧹 ClusterCuration: Manual cache cleanup complete. Cached items: \(stats.representativeCount)")
    }
    
    // MARK: - Analytics and Validation Public Interface (Task 4.1)
    
    /// Records user satisfaction data for tracking thumbnail selection quality
    func recordUserSatisfaction(
        clusterID: UUID,
        selectedPhoto: Photo,
        userAction: UserSatisfactionData.UserAction,
        sessionDuration: TimeInterval? = nil
    ) async {
        let deviceInfo = UserSatisfactionData.DeviceInfo(
            model: await getDeviceModel(),
            osVersion: await getOSVersion(),
            appVersion: await getAppVersion()
        )
        
        let satisfactionData = UserSatisfactionData(
            clusterID: clusterID,
            selectedRepresentative: selectedPhoto,
            userAction: userAction,
            timestamp: Date(),
            sessionDuration: sessionDuration,
            deviceInfo: deviceInfo
        )
        
        await analyticsManager.recordUserSatisfaction(satisfactionData)
        print("📊 ClusterCuration: Recorded user satisfaction - Action: \(userAction), Cluster: \(clusterID)")
    }
    
    /// Generates comprehensive ranking quality metrics for algorithm validation
    func generateRankingQualityMetrics(for clusters: [PhotoCluster]) async -> RankingQualityMetrics {
        let startTime = Date()
        
        // Calculate various quality metrics
        let accuracy = await calculateRankingAccuracy(clusters)
        let confidence = await calculateAverageConfidence(clusters)
        let faceQualityImprovement = await calculateFaceQualityImprovement(clusters)
        let overallQualityImprovement = await calculateOverallQualityImprovement(clusters)
        let consistencyScore = await calculateConsistencyScore(clusters)
        let cacheStats = await rankingCacheManager.statistics
        let cacheHitRate = cacheStats.representativeCount > 0 ? Float(cacheStats.representativeCount) / Float(clusters.count) : 0.0
        let userSatisfactionSummary = await analyticsManager.getUserSatisfactionSummary()
        let clusterTypeAccuracy = await calculateClusterTypeAccuracy(clusters)
        
        let processingTime = Date().timeIntervalSince(startTime)
        
        let metrics = RankingQualityMetrics(
            accuracy: accuracy,
            confidence: confidence,
            faceQualityImprovement: faceQualityImprovement,
            overallQualityImprovement: overallQualityImprovement,
            consistencyScore: consistencyScore,
            processingTime: processingTime,
            cacheHitRate: cacheHitRate,
            userOverrideRate: userSatisfactionSummary.overrideRate,
            clusterTypeAccuracy: clusterTypeAccuracy
        )
        
        await analyticsManager.recordQualityMetrics(metrics)
        print("📊 ClusterCuration: Generated quality metrics - Grade: \(metrics.qualityGrade), Accuracy: \(String(format: "%.1f%%", accuracy * 100))")
        
        return metrics
    }
    
    /// Sets up A/B testing configuration for ranking algorithm improvements
    func configureABTest(
        testID: String,
        variantA: RankingWeights,
        variantB: RankingWeights,
        trafficSplit: Float = 0.5,
        durationDays: Int = 14
    ) async {
        let config = ABTestConfig(
            testID: testID,
            isActive: true,
            variantA: variantA,
            variantB: variantB,
            trafficSplit: trafficSplit,
            startDate: Date(),
            endDate: Date().addingTimeInterval(TimeInterval(durationDays * 24 * 60 * 60)),
            minimumSampleSize: 100
        )
        
        await analyticsManager.setABTestConfig(config)
        print("🧪 ClusterCuration: Configured A/B test '\(testID)' for \(durationDays) days with \(Int(trafficSplit * 100))% traffic split")
    }
    
    /// Gets A/B test results for analysis
    func getABTestResults(_ testID: String) async -> [UserSatisfactionData] {
        return await analyticsManager.getABTestResults(testID)
    }
    
    /// Records detailed debug information for ranking decisions
    func recordRankingDebugInfo(
        clusterID: UUID,
        selectedPhoto: Photo,
        alternativePhotos: [RankingDebugInfo.PhotoRankingDetail],
        decisionFactors: RankingDebugInfo.DecisionFactors,
        processingSteps: [RankingDebugInfo.ProcessingStep]
    ) async {
        let debugInfo = RankingDebugInfo(
            clusterID: clusterID,
            selectedPhoto: selectedPhoto,
            alternativePhotos: alternativePhotos,
            decisionFactors: decisionFactors,
            processingSteps: processingSteps,
            timestamp: Date()
        )
        
        await analyticsManager.recordDebugInfo(debugInfo)
    }
    
    /// Gets debug information for a specific cluster
    func getDebugInfo(for clusterID: UUID) async -> [RankingDebugInfo] {
        return await analyticsManager.getDebugInfo(for: clusterID)
    }
    
    /// Gets current user satisfaction summary
    func getUserSatisfactionSummary(days: Int = 7) async -> (totalInteractions: Int, satisfactionRate: Float, overrideRate: Float) {
        return await analyticsManager.getUserSatisfactionSummary(days: days)
    }
    
    /// Gets latest ranking quality metrics
    func getLatestQualityMetrics() async -> RankingQualityMetrics? {
        return await analyticsManager.getLatestQualityMetrics()
    }
    
    // MARK: - Private Analytics Helper Methods
    
    private func calculateRankingAccuracy(_ clusters: [PhotoCluster]) async -> Float {
        // Compare automatic selections with user preferences based on historical data
        let userSatisfactionSummary = await analyticsManager.getUserSatisfactionSummary(days: 30)
        
        // If we have user data, use satisfaction rate as accuracy proxy
        if userSatisfactionSummary.totalInteractions > 0 {
            return userSatisfactionSummary.satisfactionRate
        }
        
        // Fallback: Use confidence-based estimation
        let totalConfidence = clusters.compactMap { $0.rankingConfidence }.reduce(0, +)
        return clusters.isEmpty ? 0.5 : totalConfidence / Float(clusters.count)
    }
    
    private func calculateAverageConfidence(_ clusters: [PhotoCluster]) async -> Float {
        let confidenceScores = clusters.compactMap { $0.rankingConfidence }
        return confidenceScores.isEmpty ? 0.0 : confidenceScores.reduce(0, +) / Float(confidenceScores.count)
    }
    
    private func calculateFaceQualityImprovement(_ clusters: [PhotoCluster]) async -> Float {
        var totalImprovement: Float = 0.0
        var clustersWithFaces = 0
        
        for cluster in clusters {
            if let representative = cluster.clusterRepresentativePhoto,
               let faceQuality = representative.faceQuality?.compositeScore {
                
                // Calculate average face quality of other photos in cluster
                let otherPhotos = cluster.photos.filter { $0.id != representative.id }
                let otherFaceQualities = otherPhotos.compactMap { $0.faceQuality?.compositeScore }
                
                if !otherFaceQualities.isEmpty {
                    let averageOtherQuality = otherFaceQualities.reduce(0, +) / Float(otherFaceQualities.count)
                    totalImprovement += max(0, faceQuality - averageOtherQuality)
                    clustersWithFaces += 1
                }
            }
        }
        
        return clustersWithFaces > 0 ? totalImprovement / Float(clustersWithFaces) : 0.0
    }
    
    private func calculateOverallQualityImprovement(_ clusters: [PhotoCluster]) async -> Float {
        var totalImprovement: Float = 0.0
        var validClusters = 0
        
        for cluster in clusters {
            if let representative = cluster.clusterRepresentativePhoto,
               let repQuality = representative.overallScore?.overall {
                
                // Calculate average quality of other photos in cluster
                let otherPhotos = cluster.photos.filter { $0.id != representative.id }
                let otherQualities = otherPhotos.compactMap { $0.overallScore?.overall }
                
                if !otherQualities.isEmpty {
                    let averageOtherQuality = otherQualities.reduce(0.0) { $0 + Double($1) } / Double(otherQualities.count)
                    totalImprovement += max(0, Float(Double(repQuality) - averageOtherQuality))
                    validClusters += 1
                }
            }
        }
        
        return validClusters > 0 ? totalImprovement / Float(validClusters) : 0.0
    }
    
    private func calculateConsistencyScore(_ clusters: [PhotoCluster]) async -> Float {
        // Group clusters by type and calculate ranking consistency within each type
        let clustersByType = Dictionary(grouping: clusters) { cluster in
            // Simple cluster type detection based on photo count and content
            cluster.photos.count >= 3 ? "group" : "single"
        }
        
        var totalConsistency: Float = 0.0
        var typeCount = 0
        
        for (_, typeClusters) in clustersByType {
            if typeClusters.count > 1 {
                let confidenceScores = typeClusters.compactMap { $0.rankingConfidence }
                if confidenceScores.count > 1 {
                    let variance = calculateVariance(values: confidenceScores)
                    let consistency = max(0, 1.0 - variance) // Lower variance = higher consistency
                    totalConsistency += consistency
                    typeCount += 1
                }
            }
        }
        
        return typeCount > 0 ? totalConsistency / Float(typeCount) : 0.8 // Default high consistency
    }
    
    private func calculateClusterTypeAccuracy(_ clusters: [PhotoCluster]) async -> [ClusterType: Float] {
        var typeAccuracy: [ClusterType: Float] = [:]
        
        // This is a simplified implementation - in a real scenario, you'd compare against ground truth
        for clusterType in [ClusterType.portraitSession, .groupEvent, .landscapeCollection, .actionSequence, .mixedContent] {
            let typeClusters = clusters.filter { cluster in
                // Simple heuristic to determine cluster type
                switch clusterType {
                case .portraitSession, .groupEvent:
                    return cluster.photos.allSatisfy { $0.faceQuality?.faceCount ?? 0 > 0 }
                case .landscapeCollection:
                    return cluster.photos.allSatisfy { $0.faceQuality?.faceCount ?? 0 == 0 }
                case .actionSequence:
                    return cluster.photos.count >= 5
                case .mixedContent:
                    return true // Fallback
                }
            }
            
            if !typeClusters.isEmpty {
                let avgConfidence = typeClusters.compactMap { $0.rankingConfidence }.reduce(0, +) / Float(typeClusters.count)
                typeAccuracy[clusterType] = avgConfidence
            }
        }
        
        return typeAccuracy
    }
    
    // MARK: - Weight Refinement System (Task 4.2.4)
    
    /// Adaptive weights based on cluster content type and user feedback
    struct AdaptiveRankingWeights {
        let technicalWeight: Float
        let facialWeight: Float
        let contextualWeight: Float
        let clusterType: ClusterType
        let confidenceLevel: Float
        
        static func defaultWeights(for clusterType: ClusterType) -> AdaptiveRankingWeights {
            switch clusterType {
            case .groupEvent:
                return AdaptiveRankingWeights(
                    technicalWeight: 0.25,
                    facialWeight: 0.60,
                    contextualWeight: 0.15,
                    clusterType: clusterType,
                    confidenceLevel: 0.8
                )
            case .portraitSession:
                return AdaptiveRankingWeights(
                    technicalWeight: 0.30,
                    facialWeight: 0.55,
                    contextualWeight: 0.15,
                    clusterType: clusterType,
                    confidenceLevel: 0.8
                )
            case .landscapeCollection:
                return AdaptiveRankingWeights(
                    technicalWeight: 0.70,
                    facialWeight: 0.05,
                    contextualWeight: 0.25,
                    clusterType: clusterType,
                    confidenceLevel: 0.9
                )
            case .actionSequence:
                return AdaptiveRankingWeights(
                    technicalWeight: 0.45,
                    facialWeight: 0.35,
                    contextualWeight: 0.20,
                    clusterType: clusterType,
                    confidenceLevel: 0.7
                )
            case .mixedContent:
                return AdaptiveRankingWeights(
                    technicalWeight: 0.40,
                    facialWeight: 0.40,
                    contextualWeight: 0.20,
                    clusterType: clusterType,
                    confidenceLevel: 0.6
                )
            }
        }
    }
    
    /// Determines optimal ranking weights based on cluster content analysis
    private func getOptimalRankingWeights(for cluster: PhotoCluster) async -> AdaptiveRankingWeights {
        let clusterType = await analyzeClusterType(cluster)
        var weights = AdaptiveRankingWeights.defaultWeights(for: clusterType)
        
        // Note: User feedback integration would require additional analytics infrastructure
        // This is a placeholder for future user satisfaction tracking
        
        // Adjust weights based on content quality distribution
        weights = adjustWeightsForContentQuality(weights, cluster: cluster)
        
        return weights
    }
    
    /// Analyzes cluster content to determine primary type
    private func analyzeClusterType(_ cluster: PhotoCluster) async -> ClusterType {
        // Analyze cluster content manually for now
        let photosWithScores = cluster.photos.compactMap { $0.overallScore }
        guard !photosWithScores.isEmpty else { return .mixedContent }
        
        let facialScoreCount = photosWithScores.filter { $0.faces > 0 }.count
        let faceRatio = Float(facialScoreCount) / Float(photosWithScores.count)
        
        if faceRatio > 0.8 {
            return .groupEvent
        } else if faceRatio < 0.3 {
            return .landscapeCollection
        } else {
            return .mixedContent
        }
    }
    
    /// Refines weights based on user satisfaction feedback
    private func refineWeightsBasedOnFeedback(
        _ baseWeights: AdaptiveRankingWeights,
        feedback: [UserSatisfactionData]
    ) -> AdaptiveRankingWeights {
        guard !feedback.isEmpty else { return baseWeights }
        
        // Calculate satisfaction metrics
        let totalInteractions = feedback.count
        let positiveInteractions = feedback.filter { data in
            data.userAction == .accepted || 
            data.userAction == .shared || 
            data.userAction == .saved
        }.count
        
        let satisfactionRate = Float(positiveInteractions) / Float(totalInteractions)
        
        // Adjust weights based on satisfaction
        var adjustedWeights = baseWeights
        
        if satisfactionRate < 0.6 {
            // Low satisfaction - adjust weights to emphasize different factors
            switch baseWeights.clusterType {
            case .groupEvent:
                // Increase facial weight even more for group photos
                adjustedWeights = AdaptiveRankingWeights(
                    technicalWeight: baseWeights.technicalWeight * 0.8,
                    facialWeight: min(0.8, baseWeights.facialWeight * 1.2),
                    contextualWeight: baseWeights.contextualWeight,
                    clusterType: baseWeights.clusterType,
                    confidenceLevel: baseWeights.confidenceLevel * 0.9
                )
            case .landscapeCollection:
                // Increase technical weight for landscapes
                adjustedWeights = AdaptiveRankingWeights(
                    technicalWeight: min(0.8, baseWeights.technicalWeight * 1.1),
                    facialWeight: baseWeights.facialWeight,
                    contextualWeight: baseWeights.contextualWeight * 0.9,
                    clusterType: baseWeights.clusterType,
                    confidenceLevel: baseWeights.confidenceLevel * 0.9
                )
            default:
                // Boost contextual weight for portraits, action, and mixed content
                adjustedWeights = AdaptiveRankingWeights(
                    technicalWeight: baseWeights.technicalWeight * 0.9,
                    facialWeight: baseWeights.facialWeight * 0.9,
                    contextualWeight: min(0.4, baseWeights.contextualWeight * 1.2),
                    clusterType: baseWeights.clusterType,
                    confidenceLevel: baseWeights.confidenceLevel * 0.9
                )
            }
        }
        
        return adjustedWeights
    }
    
    /// Adjusts weights based on cluster content quality distribution
    private func adjustWeightsForContentQuality(
        _ baseWeights: AdaptiveRankingWeights,
        cluster: PhotoCluster
    ) -> AdaptiveRankingWeights {
        let photos = cluster.photos
        guard !photos.isEmpty else { return baseWeights }
        
        // Analyze quality variance in different dimensions
        let technicalScores = photos.compactMap { $0.overallScore?.technical }
        let facialScores = photos.compactMap { $0.overallScore?.faces }
        let contextScores = photos.compactMap { $0.overallScore?.context }
        
        let technicalVariance = calculateVariance(values: technicalScores)
        let facialVariance = calculateVariance(values: facialScores)
        let contextVariance = calculateVariance(values: contextScores)
        
        var adjustedWeights = baseWeights
        
        // If there's high variance in a dimension, increase its weight
        // This helps distinguish between photos when quality varies significantly
        let varianceThreshold: Float = 0.1
        
        if technicalVariance > varianceThreshold {
            adjustedWeights = AdaptiveRankingWeights(
                technicalWeight: min(0.8, baseWeights.technicalWeight * 1.15),
                facialWeight: baseWeights.facialWeight * 0.95,
                contextualWeight: baseWeights.contextualWeight * 0.95,
                clusterType: baseWeights.clusterType,
                confidenceLevel: baseWeights.confidenceLevel
            )
        }
        
        if facialVariance > varianceThreshold && baseWeights.clusterType != .landscapeCollection {
            adjustedWeights = AdaptiveRankingWeights(
                technicalWeight: adjustedWeights.technicalWeight * 0.95,
                facialWeight: min(0.8, adjustedWeights.facialWeight * 1.15),
                contextualWeight: adjustedWeights.contextualWeight * 0.95,
                clusterType: baseWeights.clusterType,
                confidenceLevel: baseWeights.confidenceLevel
            )
        }
        
        // Normalize weights to ensure they sum to 1.0
        let totalWeight = adjustedWeights.technicalWeight + adjustedWeights.facialWeight + adjustedWeights.contextualWeight
        
        return AdaptiveRankingWeights(
            technicalWeight: adjustedWeights.technicalWeight / totalWeight,
            facialWeight: adjustedWeights.facialWeight / totalWeight,
            contextualWeight: adjustedWeights.contextualWeight / totalWeight,
            clusterType: adjustedWeights.clusterType,
            confidenceLevel: adjustedWeights.confidenceLevel
        )
    }
    
    // MARK: - Device Info Helper Methods
    
    private func getDeviceModel() async -> String {
        return await MainActor.run {
            var systemInfo = utsname()
            uname(&systemInfo)
            let modelCode = withUnsafePointer(to: &systemInfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                    ptr in String.init(validatingUTF8: ptr)
                }
            }
            return modelCode ?? "Unknown"
        }
    }
    
    private func getOSVersion() async -> String {
        return await MainActor.run {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        }
    }
    
    private func getAppVersion() async -> String {
        return await MainActor.run {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        }
    }
    
    /// Helper function to calculate variance of float values
    private func calculateVariance(values: [Float]) -> Float {
        guard values.count > 1 else { return 0.0 }
        
        let mean = values.reduce(0.0, +) / Float(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        let variance = squaredDifferences.reduce(0.0, +) / Float(values.count)
        
        return variance
    }
    
    /// Gets all photos in a cluster sorted by quality (best first) with enhanced facial analysis
    func getPhotosInCluster(_ cluster: PhotoCluster) async -> [Photo] {
        let clusterType = await detectClusterType(cluster)
        var photosWithScores: [(photo: Photo, combinedScore: Float)] = []
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let facialScore = await getFacialQualityScore(photo)
            
            // Weight scores based on cluster type
            let combinedScore = clusterType.isPersonFocused ?
                (qualityScore * 0.4 + facialScore * 0.6) :
                (qualityScore * 0.8 + facialScore * 0.2)
                
            photosWithScores.append((photo: photo, combinedScore: combinedScore))
        }
        
        // Sort by combined score (highest first)
        return photosWithScores.sorted { $0.combinedScore > $1.combinedScore }.map { $0.photo }
    }
    
    /// Updates cluster ranking metadata and returns an updated cluster
    func updateClusterRanking(_ cluster: PhotoCluster) async -> PhotoCluster {
        var updatedCluster = cluster
        
        // Get ranking result
        let rankingResult = await findBestPhotoInClusterWithRanking(cluster)
        
        // Get all ranked photos
        let rankedPhotos = await getPhotosInCluster(cluster)
        
        // Update cluster ranking metadata
        updatedCluster.updateRanking(
            rankedPhotos: rankedPhotos,
            representativePhoto: rankingResult.photo,
            reason: rankingResult.reason,
            confidence: rankingResult.confidence
        )
        
        return updatedCluster
    }
    
    /// Enhanced cluster ranking with group photo optimization using FaceQualityAnalysisService
    func updateClusterRankingWithGroupOptimization(_ cluster: PhotoCluster) async -> PhotoCluster {
        var updatedCluster = cluster
        
        // Determine if this cluster benefits from group photo optimization
        let clusterType = await detectClusterType(cluster)
        
        if clusterType.isPersonFocused && cluster.photos.count > 1 {
            // Use enhanced ranking for group photos
            let rankingResult = await findBestPhotoWithGroupOptimization(cluster)
            let rankedPhotos = await getRankedPhotosWithFacialAnalysis(cluster)
            
            updatedCluster.updateRanking(
                rankedPhotos: rankedPhotos,
                representativePhoto: rankingResult.photo,
                reason: rankingResult.reason,
                confidence: rankingResult.confidence
            )
        } else {
            // Use standard ranking for non-group photos
            updatedCluster = await updateClusterRanking(cluster)
        }
        
        return updatedCluster
    }
    
    /// Finds best photo with group photo optimization using facial analysis
    private func findBestPhotoWithGroupOptimization(_ cluster: PhotoCluster) async -> ClusterRankingResult {
        guard !cluster.photos.isEmpty else {
            fatalError("Cannot find best photo in empty cluster")
        }
        
        // Get comprehensive cluster face analysis
        let clusterAnalysis = await faceQualityAnalysisService.analyzeFaceQualityInCluster(cluster)
        
        var bestResult: ClusterRankingResult?
        var bestCombinedScore: Float = 0.0
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let enhancedFacialScore = await getEnhancedFacialQualityScore(photo, in: cluster)
            
            // Enhanced weighting for group photos with facial analysis insights
            let combinedScore = qualityScore * 0.3 + enhancedFacialScore * 0.7
            let reason: RepresentativeSelectionReason = enhancedFacialScore > 0.8 ? .bestFacialQuality : .balancedQualityAndFaces
            
            if combinedScore > bestCombinedScore {
                bestCombinedScore = combinedScore
                
                // Calculate enhanced confidence based on cluster analysis
                let confidence = calculateGroupPhotoConfidence(
                    combinedScore: combinedScore,
                    clusterAnalysis: clusterAnalysis,
                    photo: photo
                )
                
                bestResult = ClusterRankingResult(
                    photo: photo,
                    qualityScore: qualityScore,
                    facialQualityScore: enhancedFacialScore,
                    confidence: confidence,
                    reason: reason
                )
            }
        }
        
        return bestResult ?? ClusterRankingResult(
            photo: cluster.photos.first!,
            qualityScore: 0.0,
            facialQualityScore: 0.0,
            confidence: 0.1,
            reason: .fallbackSelection
        )
    }
    
    /// Gets ranked photos with enhanced facial analysis
    private func getRankedPhotosWithFacialAnalysis(_ cluster: PhotoCluster) async -> [Photo] {
        var photosWithScores: [(photo: Photo, combinedScore: Float)] = []
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let enhancedFacialScore = await getEnhancedFacialQualityScore(photo, in: cluster)
            
            // Group photo weighting
            let combinedScore = qualityScore * 0.3 + enhancedFacialScore * 0.7
            photosWithScores.append((photo: photo, combinedScore: combinedScore))
        }
        
        return photosWithScores.sorted { $0.combinedScore > $1.combinedScore }.map { $0.photo }
    }
    
    /// Calculates confidence for group photo ranking decisions
    private func calculateGroupPhotoConfidence(
        combinedScore: Float,
        clusterAnalysis: ClusterFaceAnalysis,
        photo: Photo
    ) -> Float {
        var confidence = combinedScore
        
        // Boost confidence if this photo is identified as a best face for someone
        if let photoAnalysis = findPhotoInClusterAnalysis(photo, in: clusterAnalysis) {
            if photoAnalysis.bestFace.photo.id == photo.id {
                confidence += 0.1 // 10% confidence boost for being someone's best face
            }
        }
        
        // Boost confidence based on overall cluster improvement potential
        if clusterAnalysis.overallImprovementPotential > 0.5 {
            confidence += clusterAnalysis.overallImprovementPotential * 0.1
        }
        
        return max(0.0, min(1.0, confidence))
    }
    
    // MARK: - Cluster-Specific Facial Quality Analysis
    
    /// Analyzes facial diversity within a cluster to optimize representative selection
    func analyzeFacialDiversity(in cluster: PhotoCluster) async -> ClusterFacialDiversityAnalysis {
        guard !cluster.photos.isEmpty else {
            return ClusterFacialDiversityAnalysis(
                clusterType: .noPeople,
                peopleCount: 0,
                faceConsistencyScore: 0.0,
                diversityScore: 0.0,
                bestFacePerPerson: [:],
                facialQualityDistribution: FacialQualityDistribution(excellent: 0, good: 0, fair: 0, poor: 0),
                recommendedRepresentative: nil
            )
        }
        
        // Get cluster face analysis
        let clusterAnalysis = await faceQualityAnalysisService.analyzeFaceQualityInCluster(cluster)
        
        // Determine cluster type based on people and diversity
        let clusterType = determineClusterFacialType(from: clusterAnalysis)
        
        // Calculate facial consistency across photos
        let consistencyScore = calculateFacialConsistency(from: clusterAnalysis)
        
        // Calculate diversity score
        let diversityScore = calculateFacialDiversity(from: clusterAnalysis)
        
        // Get best face per person
        let bestFacePerPerson = extractBestFacePerPerson(from: clusterAnalysis)
        
        // Analyze facial quality distribution
        let qualityDistribution = await analyzeFacialQualityDistribution(in: cluster)
        
        // Find recommended representative based on facial analysis
        let recommendedRepresentative = await findOptimalRepresentativeForFaces(
            cluster: cluster,
            clusterAnalysis: clusterAnalysis,
            clusterType: clusterType
        )
        
        return ClusterFacialDiversityAnalysis(
            clusterType: clusterType,
            peopleCount: clusterAnalysis.personAnalyses.count,
            faceConsistencyScore: consistencyScore,
            diversityScore: diversityScore,
            bestFacePerPerson: bestFacePerPerson,
            facialQualityDistribution: qualityDistribution,
            recommendedRepresentative: recommendedRepresentative
        )
    }
    
    /// Gets facial quality distribution for cluster optimization
    func getFacialQualityDistribution(for cluster: PhotoCluster) async -> FacialQualityDistribution {
        return await analyzeFacialQualityDistribution(in: cluster)
    }
    
    /// Finds the best representative photo based on facial diversity analysis
    func findOptimalFacialRepresentative(for cluster: PhotoCluster) async -> ClusterRankingResult {
        let diversityAnalysis = await analyzeFacialDiversity(in: cluster)
        
        if let recommendedPhoto = diversityAnalysis.recommendedRepresentative {
            let qualityScore = await getPhotoQualityScore(recommendedPhoto)
            let facialScore = await getEnhancedFacialQualityScore(recommendedPhoto, in: cluster)
            
            let reason: RepresentativeSelectionReason
            switch diversityAnalysis.clusterType {
            case .singlePerson:
                reason = .bestFacialQuality
            case .multiplePeople:
                reason = .balancedQualityAndFaces
            case .noPeople:
                reason = .highestOverallQuality
            }
            
            let confidence = calculateFacialDiversityConfidence(
                diversityAnalysis: diversityAnalysis,
                photo: recommendedPhoto
            )
            
            return ClusterRankingResult(
                photo: recommendedPhoto,
                qualityScore: qualityScore,
                facialQualityScore: facialScore,
                confidence: confidence,
                reason: reason
            )
        }
        
        // Fallback to standard ranking
        return await findBestPhotoInClusterWithRanking(cluster)
    }
    
    // MARK: - Private Facial Analysis Methods
    
    /// Determines the facial type of a cluster based on people analysis
    private func determineClusterFacialType(from clusterAnalysis: ClusterFaceAnalysis) -> ClusterFacialType {
        let peopleCount = clusterAnalysis.personAnalyses.count
        
        if peopleCount == 0 {
            return .noPeople
        } else if peopleCount == 1 {
            return .singlePerson
        } else {
            return .multiplePeople
        }
    }
    
    /// Calculates facial consistency score across cluster photos
    private func calculateFacialConsistency(from clusterAnalysis: ClusterFaceAnalysis) -> Float {
        let personAnalyses = Array(clusterAnalysis.personAnalyses.values)
        guard !personAnalyses.isEmpty else { return 0.0 }
        
        var totalConsistency: Float = 0.0
        
        for personAnalysis in personAnalyses {
            let faces = personAnalysis.allFaces
            guard faces.count > 1 else {
                totalConsistency += 1.0 // Single face is perfectly consistent
                continue
            }
            
            // Calculate quality variance for this person
            let qualityScores = faces.map { $0.qualityRank }
            let averageQuality = qualityScores.reduce(0, +) / Float(qualityScores.count)
            
            let variance = qualityScores.reduce(0) { sum, score in
                let diff = score - averageQuality
                return sum + (diff * diff)
            } / Float(qualityScores.count)
            
            // Convert variance to consistency (lower variance = higher consistency)
            let consistency = max(0.0, 1.0 - variance)
            totalConsistency += consistency
        }
        
        return totalConsistency / Float(personAnalyses.count)
    }
    
    /// Calculates facial diversity score (variation in expressions, poses, etc.)
    private func calculateFacialDiversity(from clusterAnalysis: ClusterFaceAnalysis) -> Float {
        let personAnalyses = Array(clusterAnalysis.personAnalyses.values)
        guard !personAnalyses.isEmpty else { return 0.0 }
        
        var totalDiversity: Float = 0.0
        
        for personAnalysis in personAnalyses {
            let faces = personAnalysis.allFaces
            guard faces.count > 1 else {
                totalDiversity += 0.0 // Single face has no diversity
                continue
            }
            
            // Calculate diversity based on quality range and expression variety
            let qualityScores = faces.map { $0.qualityRank }
            let qualityRange = (qualityScores.max() ?? 0) - (qualityScores.min() ?? 0)
            
            // Diversity is good when there's variation but not too extreme
            let optimalRange: Float = 0.3 // Sweet spot for quality variation
            let diversityScore = min(1.0, qualityRange / optimalRange)
            
            totalDiversity += diversityScore
        }
        
        return totalDiversity / Float(personAnalyses.count)
    }
    
    /// Extracts best face per person from cluster analysis
    private func extractBestFacePerPerson(from clusterAnalysis: ClusterFaceAnalysis) -> [String: Photo] {
        var bestFacePerPerson: [String: Photo] = [:]
        
        for (personID, personAnalysis) in clusterAnalysis.personAnalyses {
            bestFacePerPerson[personID] = personAnalysis.bestFace.photo
        }
        
        return bestFacePerPerson
    }
    
    /// Analyzes facial quality distribution within cluster
    private func analyzeFacialQualityDistribution(in cluster: PhotoCluster) async -> FacialQualityDistribution {
        var distribution = FacialQualityDistribution(excellent: 0, good: 0, fair: 0, poor: 0)
        
        for photo in cluster.photos {
            let facialScore = await getEnhancedFacialQualityScore(photo, in: cluster)
            
            switch facialScore {
            case 0.8...1.0:
                distribution.excellent += 1
            case 0.6..<0.8:
                distribution.good += 1
            case 0.4..<0.6:
                distribution.fair += 1
            default:
                distribution.poor += 1
            }
        }
        
        return distribution
    }
    
    /// Finds optimal representative based on facial analysis
    private func findOptimalRepresentativeForFaces(
        cluster: PhotoCluster,
        clusterAnalysis: ClusterFaceAnalysis,
        clusterType: ClusterFacialType
    ) async -> Photo? {
        switch clusterType {
        case .singlePerson:
            // For single person, find their best face
            if let personAnalysis = clusterAnalysis.personAnalyses.values.first {
                return personAnalysis.bestFace.photo
            }
            
        case .multiplePeople:
            // For multiple people, find photo that best represents the group
            return await findBestGroupRepresentative(cluster: cluster, clusterAnalysis: clusterAnalysis)
            
        case .noPeople:
            // For no people, use standard quality ranking
            break
        }
        
        return nil
    }
    
    /// Finds best representative for group photos with multiple people
    private func findBestGroupRepresentative(
        cluster: PhotoCluster,
        clusterAnalysis: ClusterFaceAnalysis
    ) async -> Photo? {
        var photoScores: [(photo: Photo, score: Float)] = []
        
        for photo in cluster.photos {
            var score: Float = 0.0
            var peopleInPhoto: Int = 0
            
            // Score based on how many people have good faces in this photo
            for (_, personAnalysis) in clusterAnalysis.personAnalyses {
                for face in personAnalysis.allFaces {
                    if face.photo.id == photo.id {
                        score += face.qualityRank
                        peopleInPhoto += 1
                        break
                    }
                }
            }
            
            // Normalize by number of people and apply group bonus
            if peopleInPhoto > 0 {
                score = score / Float(peopleInPhoto)
                
                // Bonus for photos that include more people
                let peopleRatio = Float(peopleInPhoto) / Float(clusterAnalysis.personAnalyses.count)
                score += peopleRatio * 0.2 // Up to 20% bonus
            }
            
            photoScores.append((photo: photo, score: score))
        }
        
        return photoScores.max(by: { $0.score < $1.score })?.photo
    }
    
    /// Calculates confidence for facial diversity-based ranking
    private func calculateFacialDiversityConfidence(
        diversityAnalysis: ClusterFacialDiversityAnalysis,
        photo: Photo
    ) -> Float {
        var confidence: Float = 0.5
        
        // Higher confidence for consistent facial quality
        confidence += diversityAnalysis.faceConsistencyScore * 0.2
        
        // Moderate diversity is good for confidence
        let optimalDiversity: Float = 0.5
        let diversityFactor = 1.0 - abs(diversityAnalysis.diversityScore - optimalDiversity)
        confidence += diversityFactor * 0.1
        
        // Higher confidence for multiple people scenarios
        switch diversityAnalysis.clusterType {
        case .multiplePeople:
            confidence += 0.1
        case .singlePerson:
            confidence += 0.05
        case .noPeople:
            confidence -= 0.1
        }
        
        return max(0.0, min(1.0, confidence))
    }
    
    // MARK: - Cluster Type Detection & Context-Aware Ranking
    
    /// Analyzes cluster content to determine optimal ranking strategy
    func analyzeClusterContext(_ cluster: PhotoCluster) async -> ClusterContextAnalysis {
        guard !cluster.photos.isEmpty else {
            return ClusterContextAnalysis(
                clusterType: .mixedContent,
                photoTypeBreakdown: [:],
                contentAnalysis: "Empty cluster",
                recommendedWeighting: RankingWeights.balanced,
                confidence: 0.0
            )
        }
        
        // Analyze photo types in cluster
        let photoTypes = await analyzePhotoTypesInCluster(cluster)
        
        // Determine cluster type based on content analysis
        let clusterType = determineClusterType(from: photoTypes, cluster: cluster)
        
        // Calculate content consistency
        let contentConsistency = calculateContentConsistency(photoTypes: photoTypes)
        
        // Get recommended ranking weights for this cluster type
        let recommendedWeighting = getOptimalRankingWeights(for: clusterType, cluster: cluster)
        
        // Generate context insights
        let contextInsights = generateContextInsights(
            clusterType: clusterType,
            photoTypes: photoTypes,
            cluster: cluster
        )
        
        return ClusterContextAnalysis(
            clusterType: clusterType,
            photoTypeBreakdown: photoTypes,
            contentAnalysis: contextInsights.joined(separator: ", "),
            recommendedWeighting: recommendedWeighting,
            confidence: contentConsistency
        )
    }
    
    /// Gets adaptive ranking weights based on cluster content analysis
    func getAdaptiveRankingWeights(for cluster: PhotoCluster) async -> RankingWeights {
        let contextAnalysis = await analyzeClusterContext(cluster)
        return contextAnalysis.recommendedWeighting
    }
    
    /// Ranks photos using adaptive weighting based on cluster context
    func rankPhotosWithAdaptiveWeighting(_ cluster: PhotoCluster) async -> [Photo] {
        let weights = await getAdaptiveRankingWeights(for: cluster)
        var photosWithScores: [(photo: Photo, adaptiveScore: Float)] = []
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let facialScore = await getEnhancedFacialQualityScore(photo, in: cluster)
            let contextScore = await getContextualScore(photo, in: cluster)
            
            // Apply adaptive weighting
            let adaptiveScore = (qualityScore * weights.technical) +
                               (facialScore * weights.facial) +
                               (contextScore * weights.contextual)
            
            photosWithScores.append((photo: photo, adaptiveScore: adaptiveScore))
        }
        
        return photosWithScores.sorted { $0.adaptiveScore > $1.adaptiveScore }.map { $0.photo }
    }
    
    // MARK: - Private Context Analysis Methods
    
    /// Analyzes photo types within a cluster for context determination
    private func analyzePhotoTypesInCluster(_ cluster: PhotoCluster) async -> [PhotoType: Int] {
        var photoTypeCounts: [PhotoType: Int] = [:]
        
        // Sample photos to avoid performance issues with large clusters
        let sampleSize = min(5, cluster.photos.count)
        let samplePhotos = Array(cluster.photos.prefix(sampleSize))
        
        for photo in samplePhotos {
            let photoType = PhotoType.detect(from: photo)
            photoTypeCounts[photoType, default: 0] += 1
        }
        
        return photoTypeCounts
    }
    
    /// Determines cluster type based on photo type analysis
    private func determineClusterType(from photoTypes: [PhotoType: Int], cluster: PhotoCluster) -> ClusterType {
        let totalPhotos = photoTypes.values.reduce(0, +)
        guard totalPhotos > 0 else { return .mixedContent }
        
        // Find dominant photo type
        let dominantType = photoTypes.max(by: { $0.value < $1.value })?.key
        let dominantCount = photoTypes.max(by: { $0.value < $1.value })?.value ?? 0
        let dominantPercentage = Float(dominantCount) / Float(totalPhotos)
        
        // If one type dominates (>70%), use specialized cluster type
        if dominantPercentage > 0.7 {
            switch dominantType {
            case .portrait, .groupPhoto, .multipleFaces:
                return cluster.photos.count > 3 ? .groupEvent : .portraitSession
            case .landscape, .outdoor, .goldenHour:
                return .landscapeCollection
            case .event:
                return .groupEvent
            case .closeUp:
                return .actionSequence
            default:
                return .mixedContent
            }
        }
        
        // Check for group event patterns
        if photoTypes[.groupPhoto] ?? 0 > 0 || photoTypes[.event] ?? 0 > 0 {
            return .groupEvent
        }
        
        // Check for portrait session patterns
        if photoTypes[.portrait] ?? 0 > 0 && cluster.photos.count > 2 {
            return .portraitSession
        }
        
        return .mixedContent
    }
    
    /// Calculates content consistency within cluster
    private func calculateContentConsistency(photoTypes: [PhotoType: Int]) -> Float {
        let totalPhotos = photoTypes.values.reduce(0, +)
        guard totalPhotos > 1 else { return 1.0 }
        
        // Calculate entropy (lower entropy = higher consistency)
        var entropy: Float = 0.0
        for count in photoTypes.values {
            let probability = Float(count) / Float(totalPhotos)
            if probability > 0 {
                entropy -= probability * log2(probability)
            }
        }
        
        // Convert entropy to consistency score (0-1, higher is more consistent)
        let maxEntropy = log2(Float(photoTypes.count))
        let consistency = maxEntropy > 0 ? 1.0 - (entropy / maxEntropy) : 1.0
        
        return max(0.0, min(1.0, consistency))
    }
    
    /// Gets optimal ranking weights for cluster type
    private func getOptimalRankingWeights(for clusterType: ClusterType, cluster: PhotoCluster) -> RankingWeights {
        switch clusterType {
        case .portraitSession:
            // Heavy emphasis on facial quality for portrait sessions
            return RankingWeights(technical: 0.2, facial: 0.7, contextual: 0.1)
            
        case .groupEvent:
            // Balanced facial and contextual for group events
            return RankingWeights(technical: 0.25, facial: 0.5, contextual: 0.25)
            
        case .landscapeCollection:
            // Technical and contextual emphasis for landscapes
            return RankingWeights(technical: 0.6, facial: 0.1, contextual: 0.3)
            
        case .actionSequence:
            // Technical quality primary for detail shots
            return RankingWeights(technical: 0.7, facial: 0.1, contextual: 0.2)
            
        case .mixedContent:
            // Balanced approach for mixed content
            return RankingWeights(technical: 0.4, facial: 0.4, contextual: 0.2)
        }
    }
    
    /// Generates context insights for cluster analysis
    private func generateContextInsights(
        clusterType: ClusterType,
        photoTypes: [PhotoType: Int],
        cluster: PhotoCluster
    ) -> [String] {
        var insights: [String] = []
        
        // Cluster type insight
        switch clusterType {
        case .portraitSession:
            insights.append("Portrait session detected - prioritizing facial quality")
        case .groupEvent:
            insights.append("Group event detected - balancing faces and context")
        case .landscapeCollection:
            insights.append("Landscape session detected - emphasizing composition")
        case .actionSequence:
            insights.append("Detail photography detected - focusing on technical quality")
        case .mixedContent:
            insights.append("Mixed content detected - using balanced approach")
        }
        
        // Content analysis insights
        let totalPhotos = photoTypes.values.reduce(0, +)
        if let dominantType = photoTypes.max(by: { $0.value < $1.value }) {
            let percentage = Float(dominantType.value) / Float(totalPhotos) * 100
            insights.append("\(dominantType.key.rawValue) photos dominate (\(Int(percentage))%)")
        }
        
        // Size-based insights
        if cluster.photos.count > 10 {
            insights.append("Large cluster - high confidence in type detection")
        } else if cluster.photos.count < 3 {
            insights.append("Small cluster - limited context for optimization")
        }
        
        return insights
    }
    
    /// Gets contextual score for a photo within cluster context
    private func getContextualScore(_ photo: Photo, in cluster: PhotoCluster) async -> Float {
        // Use existing overall score context component
        if let contextScore = photo.overallScore?.context {
            return contextScore
        }
        
        // Fallback contextual scoring
        var contextScore: Float = 0.5
        
        // Time context - photos at cluster temporal edges get slight bonus
        let timestamps = cluster.photos.map { $0.timestamp }.sorted()
        if let firstTime = timestamps.first, let lastTime = timestamps.last {
            let totalDuration = lastTime.timeIntervalSince(firstTime)
            if totalDuration > 0 {
                let photoPosition = photo.timestamp.timeIntervalSince(firstTime) / totalDuration
                let edgeBonus = min(photoPosition, 1.0 - photoPosition) * 0.1
                contextScore += Float(edgeBonus)
            }
        }
        
        return min(1.0, contextScore)
    }
    
    // MARK: - Private Helper Methods
    
    /// Enhanced photo ranking with integrated facial analysis and cluster-specific weighting
    private func findBestPhotoInClusterWithRanking(_ cluster: PhotoCluster) async -> ClusterRankingResult {
        guard !cluster.photos.isEmpty else {
            fatalError("Cannot find best photo in empty cluster")
        }
        
        // Single photo - simple case
        if cluster.photos.count == 1 {
            let photo = cluster.photos.first!
            let qualityScore = await getPhotoQualityScore(photo)
            let facialScore = await getFacialQualityScore(photo)
            
            return ClusterRankingResult(
                photo: photo,
                qualityScore: qualityScore,
                facialQualityScore: facialScore,
                confidence: 0.5, // Low confidence for single photo
                reason: .onlyOptionAvailable
            )
        }
        
        // Multiple photos - enhanced ranking
        let clusterType = await detectClusterType(cluster)
        var bestResult: ClusterRankingResult?
        var bestCombinedScore: Float = 0.0
        
        for photo in cluster.photos {
            let qualityScore = await getPhotoQualityScore(photo)
            let facialScore = await getFacialQualityScore(photo)
            
            // Calculate combined score based on cluster type
            let combinedScore: Float
            let reason: RepresentativeSelectionReason
            
            if clusterType.isPersonFocused {
                // Prioritize facial quality for person-focused photos
                combinedScore = qualityScore * 0.4 + facialScore * 0.6
                reason = facialScore > 0.7 ? .bestFacialQuality : .balancedQualityAndFaces
            } else {
                // Prioritize overall quality for scenery photos
                combinedScore = qualityScore * 0.8 + facialScore * 0.2
                reason = .highestOverallQuality
            }
            
            if combinedScore > bestCombinedScore {
                bestCombinedScore = combinedScore
                bestResult = ClusterRankingResult(
                    photo: photo,
                    qualityScore: qualityScore,
                    facialQualityScore: facialScore,
                    confidence: calculateRankingConfidence(combinedScore: combinedScore, clusterSize: cluster.photos.count),
                    reason: reason
                )
            }
        }
        
        return bestResult ?? ClusterRankingResult(
            photo: cluster.photos.first!,
            qualityScore: 0.0,
            facialQualityScore: 0.0,
            confidence: 0.1,
            reason: .fallbackSelection
        )
    }
    
    /// Legacy method for backward compatibility
    private func findBestPhotoInCluster(_ cluster: PhotoCluster) async -> Photo {
        let result = await findBestPhotoInClusterWithRanking(cluster)
        return result.photo
    }
    
    private func calculateClusterImportance(_ cluster: PhotoCluster) -> Float {
        let clusterSize = cluster.photos.count
        
        // Importance scoring based on cluster size
        switch clusterSize {
        case 1:
            return 0.1 // Single photos are least important
        case 2:
            return 0.3 // Pair shots are moderately important
        case 3...5:
            return 0.6 // Small burst indicates intentional moment
        case 6...10:
            return 0.8 // Medium burst indicates important moment
        case 11...20:
            return 0.9 // Large burst indicates very important moment
        default:
            return 1.0 // Very large burst indicates extremely important moment
        }
    }
    
    /// Detects the dominant content type of photos in a cluster
    private func detectClusterType(_ cluster: PhotoCluster) async -> PhotoType {
        guard !cluster.photos.isEmpty else { return .utility }
        
        // Sample up to 3 photos to determine cluster type
        let samplePhotos = Array(cluster.photos.prefix(3))
        var typeVotes: [PhotoType: Int] = [:]
        
        for photo in samplePhotos {
            let photoType = PhotoType.detect(from: photo)
            typeVotes[photoType, default: 0] += 1
        }
        
        // Return the most common type, or portrait as fallback
        return typeVotes.max(by: { $0.value < $1.value })?.key ?? .portrait
    }
    
    /// Calculates facial quality score for a photo using FaceQualityAnalysisService
    private func getFacialQualityScore(_ photo: Photo) async -> Float {
        // Use face quality from existing analysis if available
        if let faceQuality = photo.faceQuality, faceQuality.faceCount > 0 {
            return faceQuality.compositeScore
        }
        
        // For photos without faces, return neutral score
        return 0.5
    }
    
    /// Enhanced facial quality scoring with cluster context using FaceQualityAnalysisService
    private func getEnhancedFacialQualityScore(_ photo: Photo, in cluster: PhotoCluster) async -> Float {
        // Use face quality from existing analysis if available and recent
        if let faceQuality = photo.faceQuality, faceQuality.faceCount > 0 {
            var baseScore = faceQuality.compositeScore
            
            // Apply cluster-specific enhancements
            if cluster.photos.count > 1 {
                // Get cluster face analysis for context
                let clusterAnalysis = await faceQualityAnalysisService.analyzeFaceQualityInCluster(cluster)
                
                // Find this photo's analysis in the cluster context
                if let photoAnalysis = findPhotoInClusterAnalysis(photo, in: clusterAnalysis) {
                    // Enhance score with detailed facial analysis
                    baseScore = calculateEnhancedFaceScore(from: photoAnalysis, baseScore: baseScore)
                }
            }
            
            return baseScore
        }
        
        // For photos without existing face analysis, perform basic analysis
        return await performBasicFaceAnalysis(photo)
    }
    
    /// Finds photo-specific analysis within cluster analysis results
    private func findPhotoInClusterAnalysis(_ photo: Photo, in clusterAnalysis: ClusterFaceAnalysis) -> PersonFaceQualityAnalysis? {
        // Look for analysis that matches this photo
        for (_, personAnalysis) in clusterAnalysis.personAnalyses {
            if personAnalysis.bestFace.photo.id == photo.id {
                return personAnalysis
            }
            // Also check other faces in case this isn't the best face
            for face in personAnalysis.allFaces {
                if face.photo.id == photo.id {
                    return personAnalysis
                }
            }
        }
        return nil
    }
    
    /// Calculates enhanced face score using detailed facial analysis
    private func calculateEnhancedFaceScore(from personAnalysis: PersonFaceQualityAnalysis, baseScore: Float) -> Float {
        var enhancedScore = baseScore
        
        // Bonus for being the best face for this person
        if personAnalysis.bestFace.qualityRank > 0.8 {
            enhancedScore += 0.1 // 10% bonus for high-quality best face
        }
        
        // Penalty if this is a problematic face
        if let worstFace = personAnalysis.allFaces.min(by: { $0.qualityRank < $1.qualityRank }) {
            if worstFace.qualityRank < 0.3 {
                enhancedScore -= 0.05 // Small penalty for low-quality faces
            }
        }
        
        // Improvement potential bonus
        if personAnalysis.improvementPotential > 0.5 {
            enhancedScore += personAnalysis.improvementPotential * 0.1
        }
        
        return max(0.0, min(1.0, enhancedScore))
    }
    
    /// Performs basic face analysis for photos without existing analysis
    private func performBasicFaceAnalysis(_ photo: Photo) async -> Float {
        // Create a temporary single-photo cluster for analysis
        var tempCluster = PhotoCluster()
        tempCluster.photos = [photo]
        
        // Get face rankings for this photo
        let faceRankings = await faceQualityAnalysisService.rankFaceQualityInPhotos([photo])
        
        if let photoFaces = faceRankings[photo.assetIdentifier], !photoFaces.isEmpty {
            // Calculate average face quality
            let averageQuality = photoFaces.reduce(0.0) { $0 + $1.qualityRank } / Float(photoFaces.count)
            return averageQuality
        }
        
        // No faces found
        return 0.5
    }
    
    /// Calculates confidence in the ranking decision based on score and cluster size
    private func calculateRankingConfidence(combinedScore: Float, clusterSize: Int) -> Float {
        // Higher confidence for:
        // - Higher quality scores
        // - Larger clusters (more options to choose from)
        let scoreConfidence = combinedScore
        let sizeConfidence = min(Float(clusterSize) / 10.0, 1.0) // Caps at cluster size 10
        
        return (scoreConfidence * 0.7 + sizeConfidence * 0.3)
    }
    
    private func getPhotoQualityScore(_ photo: Photo) async -> Float {
        // Use existing overall score if available
        if let overallScore = photo.overallScore?.overall {
            return Float(overallScore)
        }
        
        // Fallback: calculate basic quality score
        var score: Float = 0.5 // Base score
        
        // Boost for face photos
        if let faceQuality = photo.faceQuality, faceQuality.faceCount > 0 {
            score += 0.2
            if faceQuality.faceCount > 1 {
                score += 0.1 // Group photos get extra boost
            }
        }
        
        // Technical quality factors
        if let techQuality = photo.technicalQuality {
            score += Float(techQuality.sharpness) * 0.1
            score += Float(techQuality.exposure) * 0.1
            score += Float(techQuality.composition) * 0.1
        }
        
        return min(1.0, score)
    }
    
    // MARK: - Manual Representative Override (Task 3.1.2)
    
    /// Updates the cluster representative with manual selection
    func updateClusterRepresentative(_ cluster: PhotoCluster, newRepresentative: Photo) async {
        // Validate that the photo belongs to the cluster
        guard cluster.photos.contains(where: { $0.id == newRepresentative.id }) else {
            print("Warning: Cannot set representative photo that is not in cluster")
            return
        }
        
        // Update the cluster with manual selection
        var updatedCluster = cluster
        updatedCluster.setManualRepresentative(newRepresentative)
        
        // In a real implementation, you would persist this change
        // For now, we'll just log the action
        print("✅ Manual representative updated for cluster \(cluster.id): \(newRepresentative.assetIdentifier)")
    }
    
    /// Recomputes the cluster representative using automatic ranking
    func recomputeClusterRepresentative(_ cluster: PhotoCluster) async {
        // Clear manual override and recompute
        var updatedCluster = cluster
        updatedCluster.clearRanking()
        
        // Recompute the best representative
        let rankingResult = await findBestPhotoInClusterWithRanking(updatedCluster)
        
        // Update with automatic selection
        updatedCluster.updateRanking(
            rankedPhotos: await rankPhotosWithAdaptiveWeighting(updatedCluster),
            representativePhoto: rankingResult.photo,
            reason: rankingResult.reason,
            confidence: rankingResult.confidence
        )
        
        print("✅ Automatic representative recomputed for cluster \(cluster.id): \(rankingResult.photo.assetIdentifier)")
    }
    
    /// Gets updated cluster with current representative settings
    func getUpdatedCluster(_ clusterId: UUID) async -> PhotoCluster? {
        // In a real implementation, this would fetch from persistent storage
        // For now, return nil as this is a placeholder
        print("Note: getUpdatedCluster is placeholder - would fetch from storage")
        return nil
    }
    
    // MARK: - Statistics
    
    func generateClusterStatistics(_ representatives: [ClusterRepresentative]) -> ClusterStatistics {
        let totalClusters = representatives.count
        let totalPhotos = representatives.reduce(0) { $0 + $1.clusterSize }
        let importantMoments = representatives.filter { $0.isImportantMoment }.count
        let averageClusterSize = totalClusters > 0 ? Float(totalPhotos) / Float(totalClusters) : 0
        
        let largestCluster = representatives.max { $0.clusterSize < $1.clusterSize }
        
        return ClusterStatistics(
            totalClusters: totalClusters,
            totalPhotos: totalPhotos,
            importantMoments: importantMoments,
            averageClusterSize: averageClusterSize,
            largestClusterSize: largestCluster?.clusterSize ?? 0,
            analysisDate: Date()
        )
    }
}

// MARK: - Cluster Statistics

struct ClusterStatistics {
    let totalClusters: Int
    let totalPhotos: Int
    let importantMoments: Int
    let averageClusterSize: Float
    let largestClusterSize: Int
    let analysisDate: Date
    
    var importantMomentsPercentage: Float {
        guard totalClusters > 0 else { return 0 }
        return Float(importantMoments) / Float(totalClusters) * 100
    }
}
