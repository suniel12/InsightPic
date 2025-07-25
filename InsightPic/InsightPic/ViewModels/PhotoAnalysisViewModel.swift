import Foundation
import SwiftUI
import Combine

@MainActor
class PhotoAnalysisViewModel: ObservableObject {
    @Published var analysisResults: [PhotoAnalysisResult] = []
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0
    @Published var analysisText: String = ""
    @Published var errorMessage: String?
    @Published var bestPhotos: [PhotoAnalysisResult] = []
    @Published var similarPhotoGroups: [[PhotoAnalysisResult]] = []
    
    private let photoAnalysisService: PhotoAnalysisServiceProtocol
    
    init(photoAnalysisService: PhotoAnalysisServiceProtocol = PhotoAnalysisService()) {
        self.photoAnalysisService = photoAnalysisService
    }
    
    // MARK: - Public Methods
    
    func analyzePhotos(_ photos: [Photo]) async {
        guard !photos.isEmpty else { return }
        
        isAnalyzing = true
        analysisProgress = 0.0
        analysisText = "Starting photo analysis..."
        errorMessage = nil
        analysisResults = []
        
        do {
            let results = try await photoAnalysisService.analyzePhotos(photos) { completed, total in
                Task { @MainActor in
                    self.analysisProgress = Double(completed) / Double(total)
                    self.analysisText = "Analyzing photo \(completed) of \(total)..."
                }
            }
            
            analysisResults = results
            findBestPhotos()
            findSimilarPhotoGroups()
            analysisText = "Analysis complete! Found \(results.count) analyzed photos"
            
        } catch {
            errorMessage = "Analysis failed: \(error.localizedDescription)"
            print("Photo analysis error: \(error)")
        }
        
        isAnalyzing = false
        analysisProgress = 0.0
    }
    
    func findBestPhotos(count: Int = 10) {
        bestPhotos = photoAnalysisService.findBestPhotos(from: analysisResults, count: count)
    }
    
    func findSimilarPhotoGroups() {
        similarPhotoGroups = photoAnalysisService.findSimilarPhotos(from: analysisResults)
    }
    
    func getAnalysisResult(for photo: Photo) -> PhotoAnalysisResult? {
        return analysisResults.first { $0.photoId == photo.id }
    }
    
    func refreshAnalysis(for photos: [Photo]) async {
        await analyzePhotos(photos)
    }
    
    // MARK: - Statistics
    
    var averageQualityScore: Double {
        guard !analysisResults.isEmpty else { return 0.0 }
        return analysisResults.reduce(0.0) { $0 + $1.overallScore } / Double(analysisResults.count)
    }
    
    var totalAnalyzedPhotos: Int {
        analysisResults.count
    }
    
    var excellentPhotosCount: Int {
        analysisResults.filter { $0.overallScore >= 0.8 }.count
    }
    
    var goodPhotosCount: Int {
        analysisResults.filter { $0.overallScore >= 0.6 && $0.overallScore < 0.8 }.count
    }
    
    var poorPhotosCount: Int {
        analysisResults.filter { $0.overallScore < 0.4 }.count
    }
    
    var photosWithFaces: Int {
        analysisResults.filter { !$0.faces.isEmpty }.count
    }
    
    var qualityDistribution: [String: Int] {
        var distribution: [String: Int] = [
            "Excellent": 0,
            "Good": 0,
            "Fair": 0,
            "Poor": 0
        ]
        
        for result in analysisResults {
            distribution[result.qualityDescription, default: 0] += 1
        }
        
        return distribution
    }
    
    // MARK: - Sorting and Filtering
    
    func sortedByQuality() -> [PhotoAnalysisResult] {
        return analysisResults.sorted { $0.overallScore > $1.overallScore }
    }
    
    func sortedBySharpness() -> [PhotoAnalysisResult] {
        return analysisResults.sorted { $0.sharpnessScore > $1.sharpnessScore }
    }
    
    func sortedByExposure() -> [PhotoAnalysisResult] {
        return analysisResults.sorted { $0.exposureScore > $1.exposureScore }
    }
    
    func filterByQuality(minimumScore: Double) -> [PhotoAnalysisResult] {
        return analysisResults.filter { $0.overallScore >= minimumScore }
    }
    
    func filterPhotosWithFaces() -> [PhotoAnalysisResult] {
        return analysisResults.filter { !$0.faces.isEmpty }
    }
    
    func filterPhotosWithObjects() -> [PhotoAnalysisResult] {
        return analysisResults.filter { !$0.objects.isEmpty }
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
extension PhotoAnalysisViewModel {
    static var preview: PhotoAnalysisViewModel {
        let vm = PhotoAnalysisViewModel()
        
        // Add some sample analysis results
        vm.analysisResults = [
            PhotoAnalysisResult(
                photoId: UUID(),
                assetIdentifier: "sample-1",
                qualityScore: 0.85,
                sharpnessScore: 0.9,
                exposureScore: 0.8,
                compositionScore: 0.85,
                faces: [FaceAnalysis(boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), confidence: 0.95, faceQuality: 0.9, isSmiling: true, eyesOpen: true, landmarks: nil, pose: nil, recognitionID: nil)],
                objects: [ObjectAnalysis(identifier: "person", confidence: 0.9, boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))],
                aestheticScore: 0.8,
                timestamp: Date(),
                aestheticAnalysis: nil,
                saliencyAnalysis: nil,
                dominantColors: nil,
                sceneConfidence: 0.9
            ),
            PhotoAnalysisResult(
                photoId: UUID(),
                assetIdentifier: "sample-2",
                qualityScore: 0.65,
                sharpnessScore: 0.6,
                exposureScore: 0.7,
                compositionScore: 0.65,
                faces: [],
                objects: [ObjectAnalysis(identifier: "landscape", confidence: 0.8, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))],
                aestheticScore: 0.7,
                timestamp: Date().addingTimeInterval(-3600),
                aestheticAnalysis: nil,
                saliencyAnalysis: nil,
                dominantColors: nil,
                sceneConfidence: 0.8
            )
        ]
        
        vm.findBestPhotos()
        
        return vm
    }
}
#endif