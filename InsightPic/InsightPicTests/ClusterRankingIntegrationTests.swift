import XCTest
import Vision
import UIKit
import Photos
import CoreLocation
@testable import InsightPic

/// Integration tests for cluster ranking system (Task 4.2)
/// Tests ranking accuracy, facial analysis integration, UI responsiveness, and weight refinement
class ClusterRankingIntegrationTests: XCTestCase {
    
    var clusterCurationService: ClusterCurationService!
    var faceQualityService: FaceQualityAnalysisService!
    var photoScoringService: PhotoScoringService!
    var mockPhotoLibraryService: MockPhotoLibraryService!
    
    override func setUpWithError() throws {
        mockPhotoLibraryService = MockPhotoLibraryService()
        faceQualityService = FaceQualityAnalysisService(photoLibraryService: mockPhotoLibraryService)
        photoScoringService = PhotoScoringService()
        clusterCurationService = ClusterCurationService(
            faceQualityService: faceQualityService,
            photoScoringService: photoScoringService
        )
    }
    
    override func tearDownWithError() throws {
        clusterCurationService = nil
        faceQualityService = nil
        photoScoringService = nil
        mockPhotoLibraryService = nil
    }
    
    // MARK: - Ranking Accuracy Tests (Task 4.2.1)
    
    func testRankingAccuracy_GroupPhotosCluster() async throws {
        // Test that group photos prioritize facial quality over composition
        let groupCluster = createMockGroupPhotoCluster()
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([groupCluster])
        
        guard let bestPhoto = rankedPhotos.first?.first else {
            XCTFail("Should have ranked photos in group cluster")
            return
        }
        
        // Verify that the top-ranked photo has high facial quality
        XCTAssertNotNil(bestPhoto.faceAnalysis, "Best group photo should have face analysis")
        if let faceAnalysis = bestPhoto.faceAnalysis {
            XCTAssertGreaterThan(faceAnalysis.overallFaceQuality, 0.7, "Best group photo should have high facial quality")
        }
        
        // Verify ranking consistency - top photos should have consistently high scores
        let topThreePhotos = Array(rankedPhotos.first?.prefix(3) ?? [])
        for photo in topThreePhotos {
            XCTAssertGreaterThan(photo.overallScore?.overall ?? 0, 0.6, "Top ranked photos should have high overall scores")
        }
    }
    
    func testRankingAccuracy_LandscapeCluster() async throws {
        // Test that landscape photos prioritize composition over facial features
        let landscapeCluster = createMockLandscapeCluster()
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([landscapeCluster])
        
        guard let bestPhoto = rankedPhotos.first?.first else {
            XCTFail("Should have ranked photos in landscape cluster")
            return
        }
        
        // Verify that composition scores are prioritized for landscapes
        XCTAssertNotNil(bestPhoto.overallScore?.technical, "Best landscape photo should have technical analysis")
        if let technicalScore = bestPhoto.overallScore?.technical {
            XCTAssertGreaterThan(technicalScore.compositionScore, 0.7, "Best landscape photo should have high composition score")
        }
    }
    
    func testRankingAccuracy_MixedContentCluster() async throws {
        // Test ranking accuracy for clusters with mixed content types
        let mixedCluster = createMockMixedContentCluster()
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([mixedCluster])
        
        guard let allRankedPhotos = rankedPhotos.first, allRankedPhotos.count >= 3 else {
            XCTFail("Should have multiple ranked photos in mixed cluster")
            return
        }
        
        // Verify that ranking considers both facial and technical quality appropriately
        let topPhoto = allRankedPhotos[0]
        let secondPhoto = allRankedPhotos[1]
        let thirdPhoto = allRankedPhotos[2]
        
        // Top photo should have highest overall score
        XCTAssertGreaterThanOrEqual(
            topPhoto.overallScore?.overall ?? 0,
            secondPhoto.overallScore?.overall ?? 0,
            "Top photo should have highest overall score"
        )
        
        XCTAssertGreaterThanOrEqual(
            secondPhoto.overallScore?.overall ?? 0,
            thirdPhoto.overallScore?.overall ?? 0,
            "Second photo should have higher score than third"
        )
    }
    
    // MARK: - Facial Analysis Integration Tests (Task 4.2.2)
    
    func testFacialAnalysisIntegration_QualityWeighting() async throws {
        // Test that facial quality analysis properly influences ranking
        let photos = createPhotosWithVaryingFaceQuality()
        let cluster = PhotoCluster()
        cluster.photos = photos
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([cluster])
        
        guard let ranked = rankedPhotos.first, ranked.count >= 2 else {
            XCTFail("Should have ranked multiple photos")
            return
        }
        
        let bestPhoto = ranked[0]
        let worstPhoto = ranked.last!
        
        // Best photo should have better facial quality metrics
        if let bestFaceAnalysis = bestPhoto.faceAnalysis,
           let worstFaceAnalysis = worstPhoto.faceAnalysis {
            XCTAssertGreaterThan(
                bestFaceAnalysis.overallFaceQuality,
                worstFaceAnalysis.overallFaceQuality,
                "Best ranked photo should have better facial quality"
            )
        }
    }
    
    func testFacialAnalysisIntegration_EyeStateImpact() async throws {
        // Test that eye state (open vs closed) significantly impacts ranking
        let openEyesPhoto = createMockPhotoWithEyeState(bothEyesOpen: true)
        let closedEyesPhoto = createMockPhotoWithEyeState(bothEyesOpen: false)
        
        let cluster = PhotoCluster()
        cluster.photos = [openEyesPhoto, closedEyesPhoto]
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([cluster])
        
        guard let ranked = rankedPhotos.first, ranked.count == 2 else {
            XCTFail("Should have ranked both photos")
            return
        }
        
        // Photo with open eyes should rank higher
        let topPhoto = ranked[0]
        XCTAssertEqual(topPhoto.id, openEyesPhoto.id, "Photo with open eyes should rank higher")
    }
    
    func testFacialAnalysisIntegration_SmileQualityImpact() async throws {
        // Test that smile quality affects ranking appropriately
        let naturalSmilePhoto = createMockPhotoWithSmileQuality(intensity: 0.8, naturalness: 0.9)
        let forcedSmilePhoto = createMockPhotoWithSmileQuality(intensity: 0.9, naturalness: 0.3)
        let noSmilePhoto = createMockPhotoWithSmileQuality(intensity: 0.1, naturalness: 0.5)
        
        let cluster = PhotoCluster()
        cluster.photos = [forcedSmilePhoto, naturalSmilePhoto, noSmilePhoto]
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([cluster])
        
        guard let ranked = rankedPhotos.first, ranked.count == 3 else {
            XCTFail("Should have ranked all three photos")
            return
        }
        
        // Natural smile should rank highest
        let topPhoto = ranked[0]
        XCTAssertEqual(topPhoto.id, naturalSmilePhoto.id, "Photo with natural smile should rank highest")
    }
    
    // MARK: - UI Responsiveness Tests (Task 4.2.3)
    
    func testUIResponsiveness_LargeClusterPerformance() async throws {
        // Test that ranking large clusters completes within reasonable time
        let largeCluster = createMockLargeCluster(photoCount: 50)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([largeCluster])
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete within 5 seconds for 50 photos
        XCTAssertLessThan(processingTime, 5.0, "Large cluster ranking should complete within 5 seconds")
        
        // Should still produce valid rankings
        guard let ranked = rankedPhotos.first else {
            XCTFail("Should have ranked photos in large cluster")
            return
        }
        
        XCTAssertEqual(ranked.count, 50, "Should rank all photos in large cluster")
        
        // Verify ranking quality didn't degrade with size
        let topPhoto = ranked[0]
        XCTAssertNotNil(topPhoto.overallScore, "Top photo should have scoring even in large cluster")
    }
    
    func testUIResponsiveness_MultipleClustersPerformance() async throws {
        // Test ranking multiple clusters simultaneously
        let clusters = createMultipleMockClusters(clusterCount: 10, photosPerCluster: 10)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives(clusters)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete within 10 seconds for 10 clusters of 10 photos each
        XCTAssertLessThan(processingTime, 10.0, "Multiple cluster ranking should complete within 10 seconds")
        
        // Should produce rankings for all clusters
        XCTAssertEqual(rankedPhotos.count, 10, "Should have rankings for all clusters")
        
        // Each cluster should have valid rankings
        for rankedCluster in rankedPhotos {
            XCTAssertEqual(rankedCluster.count, 10, "Each cluster should have all photos ranked")
            XCTAssertNotNil(rankedCluster.first?.overallScore, "Top photo in each cluster should have score")
        }
    }
    
    // MARK: - Ranking Weight Refinement Tests (Task 4.2.4)
    
    func testRankingWeights_GroupPhotoOptimization() async throws {
        // Test that group photo weights prioritize facial quality appropriately
        let groupPhotos = createGroupPhotosWithVaryingQuality()
        let cluster = PhotoCluster()
        cluster.photos = groupPhotos
        
        // Test with current weights
        let currentRanking = await clusterCurationService.curateClusterRepresentatives([cluster])
        
        // Verify that facial quality is weighted heavily for group photos
        guard let ranked = currentRanking.first, ranked.count >= 3 else {
            XCTFail("Should have ranked multiple group photos")
            return
        }
        
        let topPhoto = ranked[0]
        let bottomPhoto = ranked.last!
        
        // Top photo should have significantly better facial quality
        if let topFaceAnalysis = topPhoto.faceAnalysis,
           let bottomFaceAnalysis = bottomPhoto.faceAnalysis {
            let faceQualityDifference = topFaceAnalysis.overallFaceQuality - bottomFaceAnalysis.overallFaceQuality
            XCTAssertGreaterThan(faceQualityDifference, 0.2, "Top photo should have significantly better facial quality")
        }
    }
    
    func testRankingWeights_ContextualAdaptation() async throws {
        // Test that ranking weights adapt based on cluster content type
        let portraitCluster = createMockPortraitCluster()
        let landscapeCluster = createMockLandscapeCluster()
        let eventCluster = createMockEventCluster()
        
        let portraitRanking = await clusterCurationService.curateClusterRepresentatives([portraitCluster])
        let landscapeRanking = await clusterCurationService.curateClusterRepresentatives([landscapeCluster])
        let eventRanking = await clusterCurationService.curateClusterRepresentatives([eventCluster])
        
        // Portrait clusters should prioritize facial quality
        if let portraitTop = portraitRanking.first?.first {
            XCTAssertNotNil(portraitTop.faceAnalysis, "Portrait cluster top photo should have face analysis")
        }
        
        // Landscape clusters should prioritize composition
        if let landscapeTop = landscapeRanking.first?.first {
            XCTAssertNotNil(landscapeTop.overallScore?.technical, "Landscape cluster top photo should have technical analysis")
        }
        
        // Event clusters should balance both
        if let eventTop = eventRanking.first?.first {
            XCTAssertNotNil(eventTop.overallScore, "Event cluster top photo should have comprehensive scoring")
        }
    }
    
    // MARK: - Analytics Integration Tests
    
    func testAnalyticsIntegration_DebugInfoGeneration() async throws {
        // Test that ranking process generates proper debug information
        let cluster = createMockGroupPhotoCluster()
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([cluster])
        
        // Verify debug information is generated
        let debugInfo = await clusterCurationService.analyticsManager.getRankingDebugInfo(for: cluster.id)
        
        XCTAssertNotNil(debugInfo, "Debug information should be generated during ranking")
        
        if let debug = debugInfo {
            XCTAssertGreaterThan(debug.decisionFactors.count, 0, "Should have decision factors recorded")
            XCTAssertGreaterThan(debug.processingTime, 0, "Should have processing time recorded")
            XCTAssertNotNil(debug.confidenceLevel, "Should have confidence level recorded")
        }
    }
    
    func testAnalyticsIntegration_QualityMetricsGeneration() async throws {
        // Test that quality metrics are properly generated and stored
        let clusters = createMultipleMockClusters(clusterCount: 3, photosPerCluster: 5)
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives(clusters)
        
        // Check that quality metrics are generated
        let qualityMetrics = await clusterCurationService.analyticsManager.generateRankingQualityMetrics(for: clusters)
        
        XCTAssertNotNil(qualityMetrics, "Quality metrics should be generated")
        
        if let metrics = qualityMetrics {
            XCTAssertGreaterThan(metrics.accuracy, 0, "Should have accuracy metrics")
            XCTAssertGreaterThan(metrics.confidence, 0, "Should have confidence metrics")
            XCTAssertGreaterThan(metrics.processingTime, 0, "Should have processing time metrics")
        }
    }
    
    // MARK: - Helper Methods for Test Data Creation
    
    private func createMockGroupPhotoCluster() -> PhotoCluster {
        let cluster = PhotoCluster()
        cluster.photos = [
            createMockPhotoWithFaces(faceCount: 3, quality: .high),
            createMockPhotoWithFaces(faceCount: 3, quality: .medium),
            createMockPhotoWithFaces(faceCount: 3, quality: .low)
        ]
        return cluster
    }
    
    private func createMockLandscapeCluster() -> PhotoCluster {
        let cluster = PhotoCluster()
        cluster.photos = [
            createMockLandscapePhoto(compositionScore: 0.9),
            createMockLandscapePhoto(compositionScore: 0.7),
            createMockLandscapePhoto(compositionScore: 0.5)
        ]
        return cluster
    }
    
    private func createMockMixedContentCluster() -> PhotoCluster {
        let cluster = PhotoCluster()
        cluster.photos = [
            createMockPhotoWithFaces(faceCount: 2, quality: .high),
            createMockLandscapePhoto(compositionScore: 0.8),
            createMockPhotoWithFaces(faceCount: 1, quality: .medium),
            createMockLandscapePhoto(compositionScore: 0.6)
        ]
        return cluster
    }
    
    private func createPhotosWithVaryingFaceQuality() -> [Photo] {
        return [
            createMockPhotoWithFaceQuality(overallQuality: 0.9),
            createMockPhotoWithFaceQuality(overallQuality: 0.7),
            createMockPhotoWithFaceQuality(overallQuality: 0.5),
            createMockPhotoWithFaceQuality(overallQuality: 0.3)
        ]
    }
    
    private func createMockPhotoWithEyeState(bothEyesOpen: Bool) -> Photo {
        let photo = Photo(
            id: UUID(),
            assetIdentifier: UUID().uuidString,
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(width: 1024, height: 768)
        )
        
        // Create mock face analysis with specified eye state
        let eyeState = EyeState(leftOpen: bothEyesOpen, rightOpen: bothEyesOpen, confidence: 0.9)
        let faceQuality = FaceQualityData(
            photo: photo,
            boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4),
            landmarks: nil,
            captureQuality: 0.8,
            eyeState: eyeState,
            smileQuality: SmileQuality(intensity: 0.7, naturalness: 0.8, confidence: 0.8),
            faceAngle: FaceAngle(pitch: 0, yaw: 0, roll: 0),
            sharpness: 0.8,
            overallScore: bothEyesOpen ? 0.85 : 0.4
        )
        
        let faceAnalysis = FaceAnalysis(
            detectedFaces: [faceQuality],
            overallFaceQuality: bothEyesOpen ? 0.85 : 0.4,
            dominantFaceQuality: faceQuality,
            faceCount: 1
        )
        
        photo.faceAnalysis = faceAnalysis
        
        return photo
    }
    
    private func createMockPhotoWithSmileQuality(intensity: Float, naturalness: Float) -> Photo {
        let photo = Photo(
            id: UUID(),
            assetIdentifier: UUID().uuidString,
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(width: 1024, height: 768)
        )
        
        let smileQuality = SmileQuality(intensity: intensity, naturalness: naturalness, confidence: 0.9)
        let faceQuality = FaceQualityData(
            photo: photo,
            boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4),
            landmarks: nil,
            captureQuality: 0.8,
            eyeState: EyeState(leftOpen: true, rightOpen: true, confidence: 0.9),
            smileQuality: smileQuality,
            faceAngle: FaceAngle(pitch: 0, yaw: 0, roll: 0),
            sharpness: 0.8,
            overallScore: (intensity + naturalness) / 2.0
        )
        
        let faceAnalysis = FaceAnalysis(
            detectedFaces: [faceQuality],
            overallFaceQuality: (intensity + naturalness) / 2.0,
            dominantFaceQuality: faceQuality,
            faceCount: 1
        )
        
        photo.faceAnalysis = faceAnalysis
        
        return photo
    }
    
    private func createMockLargeCluster(photoCount: Int) -> PhotoCluster {
        let cluster = PhotoCluster()
        var photos: [Photo] = []
        
        for i in 0..<photoCount {
            let photo = createMockPhotoWithFaces(
                faceCount: Int.random(in: 1...4),
                quality: [.low, .medium, .high].randomElement()!
            )
            photos.append(photo)
        }
        
        cluster.photos = photos
        return cluster
    }
    
    private func createMultipleMockClusters(clusterCount: Int, photosPerCluster: Int) -> [PhotoCluster] {
        var clusters: [PhotoCluster] = []
        
        for _ in 0..<clusterCount {
            let cluster = createMockLargeCluster(photoCount: photosPerCluster)
            clusters.append(cluster)
        }
        
        return clusters
    }
    
    private func createGroupPhotosWithVaryingQuality() -> [Photo] {
        return [
            createMockPhotoWithFaces(faceCount: 3, quality: .high),
            createMockPhotoWithFaces(faceCount: 3, quality: .medium),
            createMockPhotoWithFaces(faceCount: 3, quality: .low),
            createMockPhotoWithFaces(faceCount: 3, quality: .medium)
        ]
    }
    
    private func createMockPortraitCluster() -> PhotoCluster {
        let cluster = PhotoCluster()
        cluster.photos = [
            createMockPhotoWithFaces(faceCount: 1, quality: .high),
            createMockPhotoWithFaces(faceCount: 1, quality: .medium),
            createMockPhotoWithFaces(faceCount: 1, quality: .low)
        ]
        return cluster
    }
    
    private func createMockEventCluster() -> PhotoCluster {
        let cluster = PhotoCluster()
        cluster.photos = [
            createMockPhotoWithFaces(faceCount: 5, quality: .high),
            createMockPhotoWithFaces(faceCount: 4, quality: .medium),
            createMockLandscapePhoto(compositionScore: 0.8),
            createMockPhotoWithFaces(faceCount: 3, quality: .medium)
        ]
        return cluster
    }
    
    private func createMockPhotoWithFaces(faceCount: Int, quality: FaceQuality) -> Photo {
        let photo = Photo(
            id: UUID(),
            assetIdentifier: UUID().uuidString,
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(width: 1024, height: 768)
        )
        
        var detectedFaces: [FaceQualityData] = []
        let baseQuality: Float = quality == .high ? 0.8 : (quality == .medium ? 0.6 : 0.4)
        
        for i in 0..<faceCount {
            let faceQuality = FaceQualityData(
                photo: photo,
                boundingBox: CGRect(x: Double(i) * 0.2, y: 0.3, width: 0.15, height: 0.2),
                landmarks: nil,
                captureQuality: baseQuality + Float.random(in: -0.1...0.1),
                eyeState: EyeState(leftOpen: true, rightOpen: true, confidence: 0.9),
                smileQuality: SmileQuality(intensity: baseQuality, naturalness: baseQuality, confidence: 0.8),
                faceAngle: FaceAngle(pitch: 0, yaw: 0, roll: 0),
                sharpness: baseQuality,
                overallScore: baseQuality
            )
            detectedFaces.append(faceQuality)
        }
        
        let faceAnalysis = FaceAnalysis(
            detectedFaces: detectedFaces,
            overallFaceQuality: baseQuality,
            dominantFaceQuality: detectedFaces.first,
            faceCount: faceCount
        )
        
        photo.faceAnalysis = faceAnalysis
        
        return photo
    }
    
    private func createMockLandscapePhoto(compositionScore: Float) -> Photo {
        let photo = Photo(
            id: UUID(),
            assetIdentifier: UUID().uuidString,
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(width: 1024, height: 768)
        )
        
        let technicalScore = TechnicalQualityScore(
            sharpness: compositionScore * 0.9,
            exposure: compositionScore * 0.8,
            colorBalance: compositionScore * 0.85,
            noise: 1.0 - (compositionScore * 0.2),
            compositionScore: compositionScore,
            overallTechnical: compositionScore
        )
        
        let overallScore = PhotoScore(
            technical: technicalScore,
            faces: nil,
            context: ContextualScore(
                timeOfDay: .goldenHour,
                location: .outdoor,
                event: nil,
                season: .summer,
                weather: .clear,
                overallContext: compositionScore * 0.7
            ),
            overall: compositionScore * 0.8
        )
        
        photo.overallScore = overallScore
        
        return photo
    }
    
    private func createMockPhotoWithFaceQuality(overallQuality: Float) -> Photo {
        let photo = Photo(
            id: UUID(),
            assetIdentifier: UUID().uuidString,
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(width: 1024, height: 768)
        )
        
        let faceQuality = FaceQualityData(
            photo: photo,
            boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4),
            landmarks: nil,
            captureQuality: overallQuality,
            eyeState: EyeState(leftOpen: true, rightOpen: true, confidence: 0.9),
            smileQuality: SmileQuality(intensity: overallQuality, naturalness: overallQuality, confidence: 0.8),
            faceAngle: FaceAngle(pitch: 0, yaw: 0, roll: 0),
            sharpness: overallQuality,
            overallScore: overallQuality
        )
        
        let faceAnalysis = FaceAnalysis(
            detectedFaces: [faceQuality],
            overallFaceQuality: overallQuality,
            dominantFaceQuality: faceQuality,
            faceCount: 1
        )
        
        photo.faceAnalysis = faceAnalysis
        
        return photo
    }
}

// MARK: - Test Helper Enums

private enum FaceQuality {
    case low, medium, high
}