import Foundation
import SwiftUI
import Combine

@MainActor
class PhotoScoringViewModel: ObservableObject {
    @Published var isScoring = false
    @Published var scoringProgress: Double = 0.0
    @Published var scoringText: String = ""
    @Published var errorMessage: String?
    @Published var scoringStatistics: ScoringStatistics?
    @Published var qualityDistribution: [String: Int] = [:]
    @Published var topQualityPhotos: [Photo] = []
    @Published var photosNeedingImprovement: [(Photo, [String])] = []
    
    private let scoringService: PhotoScoringServiceProtocol
    private let photoRepository: PhotoDataRepositoryProtocol
    
    init(scoringService: PhotoScoringServiceProtocol = PhotoScoringService(),
         photoRepository: PhotoDataRepositoryProtocol = PhotoDataRepository()) {
        self.scoringService = scoringService
        self.photoRepository = photoRepository
    }
    
    // MARK: - Public Methods
    
    func scoreAllPhotos() async {
        isScoring = true
        scoringProgress = 0.0
        scoringText = "Loading photos for scoring..."
        errorMessage = nil
        
        do {
            // Get photos that need scoring
            let photosToScore = try await scoringService.getPhotosNeedingScoring()
            
            if photosToScore.isEmpty {
                scoringText = "All photos already have quality scores"
                await generateStatistics()
                isScoring = false
                return
            }
            
            scoringText = "Scoring \(photosToScore.count) photos..."
            
            // Score photos with progress tracking
            try await scoringService.scoreAndPersistPhotos(photosToScore) { completed, total in
                Task { @MainActor in
                    self.scoringProgress = Double(completed) / Double(total)
                    self.scoringText = "Analyzing photo \(completed) of \(total)..."
                }
            }
            
            // Generate statistics after scoring
            await generateStatistics()
            
            scoringText = "Photo scoring complete! Analyzed \(photosToScore.count) photos"
            
        } catch {
            errorMessage = "Photo scoring failed: \(error.localizedDescription)"
            print("Photo scoring error: \(error)")
        }
        
        isScoring = false
        scoringProgress = 0.0
    }
    
    func scoreSelectedPhotos(_ photos: [Photo]) async {
        guard !photos.isEmpty else { return }
        
        isScoring = true
        scoringProgress = 0.0
        scoringText = "Scoring \(photos.count) selected photos..."
        errorMessage = nil
        
        do {
            try await scoringService.scoreAndPersistPhotos(photos) { completed, total in
                Task { @MainActor in
                    self.scoringProgress = Double(completed) / Double(total)
                    self.scoringText = "Analyzing photo \(completed) of \(total)..."
                }
            }
            
            await generateStatistics()
            scoringText = "Scoring complete! Analyzed \(photos.count) photos"
            
        } catch {
            errorMessage = "Photo scoring failed: \(error.localizedDescription)"
            print("Photo scoring error: \(error)")
        }
        
        isScoring = false
        scoringProgress = 0.0
    }
    
    func rescoreLowQualityPhotos(threshold: Float = 0.3) async {
        isScoring = true
        scoringProgress = 0.0
        scoringText = "Finding photos with low quality scores..."
        errorMessage = nil
        
        do {
            try await scoringService.rescorePhotosWithLowQuality(threshold: threshold)
            await generateStatistics()
            scoringText = "Rescoring complete!"
            
        } catch {
            errorMessage = "Rescoring failed: \(error.localizedDescription)"
            print("Rescoring error: \(error)")
        }
        
        isScoring = false
        scoringProgress = 0.0
    }
    
    func generateStatistics() async {
        do {
            let allPhotos = try await photoRepository.loadPhotos()
            
            // Generate quality distribution
            qualityDistribution = scoringService.getQualityDistribution(allPhotos)
            
            // Get top quality photos
            topQualityPhotos = scoringService.getTopQualityPhotos(allPhotos, count: 20)
            
            // Get photos needing improvement
            photosNeedingImprovement = scoringService.getPhotosNeedingImprovement(allPhotos)
            
            // Generate overall statistics
            let averageScore = scoringService.getAverageQualityScore(allPhotos)
            let scoredPhotosCount = allPhotos.filter { $0.overallScore != nil }.count
            let unscoredPhotosCount = allPhotos.count - scoredPhotosCount
            
            scoringStatistics = ScoringStatistics(
                totalPhotos: allPhotos.count,
                scoredPhotos: scoredPhotosCount,
                unscoredPhotos: unscoredPhotosCount,
                averageScore: averageScore,
                excellentPhotos: qualityDistribution["Excellent (0.8+)"] ?? 0,
                goodPhotos: qualityDistribution["Good (0.6-0.8)"] ?? 0,
                fairPhotos: qualityDistribution["Fair (0.4-0.6)"] ?? 0,
                poorPhotos: qualityDistribution["Poor (0.0-0.4)"] ?? 0
            )
            
        } catch {
            errorMessage = "Failed to generate statistics: \(error.localizedDescription)"
            print("Statistics error: \(error)")
        }
    }
    
    // MARK: - Quality Filtering
    
    func getPhotosByQuality(minimumScore: Float) async -> [Photo] {
        do {
            let allPhotos = try await photoRepository.loadPhotos()
            return scoringService.getPhotosByQualityThreshold(allPhotos, minimumScore: minimumScore)
        } catch {
            errorMessage = "Failed to filter photos by quality: \(error.localizedDescription)"
            return []
        }
    }
    
    func getExcellentPhotos() async -> [Photo] {
        return await getPhotosByQuality(minimumScore: 0.8)
    }
    
    func getGoodPhotos() async -> [Photo] {
        return await getPhotosByQuality(minimumScore: 0.6)
    }
    
    func getPoorPhotos() async -> [Photo] {
        do {
            let allPhotos = try await photoRepository.loadPhotos()
            return allPhotos.filter { photo in
                guard let score = photo.overallScore?.overall else { return false }
                return score < 0.4
            }
        } catch {
            errorMessage = "Failed to get poor quality photos: \(error.localizedDescription)"
            return []
        }
    }
    
    // MARK: - Statistics Computed Properties
    
    var totalPhotosCount: Int {
        scoringStatistics?.totalPhotos ?? 0
    }
    
    var scoredPhotosCount: Int {
        scoringStatistics?.scoredPhotos ?? 0
    }
    
    var unscoredPhotosCount: Int {
        scoringStatistics?.unscoredPhotos ?? 0
    }
    
    var averageQualityScore: Float {
        scoringStatistics?.averageScore ?? 0.0
    }
    
    var scoreCompletionPercentage: Double {
        guard totalPhotosCount > 0 else { return 0.0 }
        return Double(scoredPhotosCount) / Double(totalPhotosCount) * 100.0
    }
    
    var excellentPhotosCount: Int {
        scoringStatistics?.excellentPhotos ?? 0
    }
    
    var goodPhotosCount: Int {
        scoringStatistics?.goodPhotos ?? 0
    }
    
    var photosNeedingImprovementCount: Int {
        photosNeedingImprovement.count
    }
    
    // MARK: - Quality Recommendations
    
    func getQualityRecommendations() -> [String] {
        var recommendations: [String] = []
        
        guard let stats = scoringStatistics else { return recommendations }
        
        if stats.unscoredPhotos > 0 {
            recommendations.append("Score \(stats.unscoredPhotos) remaining photos to complete analysis")
        }
        
        if stats.averageScore < 0.5 {
            recommendations.append("Consider reviewing photo composition and technical settings")
        }
        
        if stats.poorPhotos > stats.excellentPhotos {
            recommendations.append("Focus on improving photo quality - more poor photos than excellent ones")
        }
        
        if photosNeedingImprovementCount > 0 {
            recommendations.append("Review \(photosNeedingImprovementCount) photos that need technical improvements")
        }
        
        if stats.excellentPhotos > 0 {
            recommendations.append("Great job! You have \(stats.excellentPhotos) excellent quality photos")
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

// MARK: - Scoring Statistics Model

struct ScoringStatistics {
    let totalPhotos: Int
    let scoredPhotos: Int
    let unscoredPhotos: Int
    let averageScore: Float
    let excellentPhotos: Int
    let goodPhotos: Int
    let fairPhotos: Int
    let poorPhotos: Int
    
    var scoreDistributionText: String {
        return """
        Excellent: \(excellentPhotos)
        Good: \(goodPhotos)
        Fair: \(fairPhotos)
        Poor: \(poorPhotos)
        """
    }
    
    var qualityGrade: String {
        switch averageScore {
        case 0.8...1.0: return "A"
        case 0.7..<0.8: return "B+"
        case 0.6..<0.7: return "B"
        case 0.5..<0.6: return "C+"
        case 0.4..<0.5: return "C"
        default: return "D"
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension PhotoScoringViewModel {
    static var preview: PhotoScoringViewModel {
        let vm = PhotoScoringViewModel()
        
        vm.scoringStatistics = ScoringStatistics(
            totalPhotos: 100,
            scoredPhotos: 85,
            unscoredPhotos: 15,
            averageScore: 0.72,
            excellentPhotos: 12,
            goodPhotos: 28,
            fairPhotos: 35,
            poorPhotos: 10
        )
        
        vm.qualityDistribution = [
            "Excellent (0.8+)": 12,
            "Good (0.6-0.8)": 28,
            "Fair (0.4-0.6)": 35,
            "Poor (0.0-0.4)": 10,
            "Unscored": 15
        ]
        
        return vm
    }
}
#endif