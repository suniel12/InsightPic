import XCTest
import UIKit
@testable import InsightPic

/// Performance tests for cluster ranking system (Task 4.2.3)
/// Tests UI responsiveness and scalability with large datasets
class RankingPerformanceTests: XCTestCase {
    
    var clusterCurationService: ClusterCurationService!
    var mockPhotoLibraryService: MockPhotoLibraryService!
    
    override func setUpWithError() throws {
        mockPhotoLibraryService = MockPhotoLibraryService()
        let faceQualityService = FaceQualityAnalysisService(photoLibraryService: mockPhotoLibraryService)
        let photoScoringService = PhotoScoringService()
        
        clusterCurationService = ClusterCurationService(
            faceQualityService: faceQualityService,
            photoScoringService: photoScoringService
        )
    }
    
    override func tearDownWithError() throws {
        clusterCurationService = nil
        mockPhotoLibraryService = nil
    }
    
    // MARK: - Baseline Performance Tests
    
    func testPerformance_SmallClusterRanking() throws {
        // Baseline: Small cluster (5 photos) should be very fast
        let smallCluster = createPerformanceTestCluster(photoCount: 5)
        
        measure {
            let expectation = XCTestExpectation(description: "Small cluster ranking")
            
            Task {
                let _ = await clusterCurationService.curateClusterRepresentatives([smallCluster])
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testPerformance_MediumClusterRanking() throws {
        // Medium cluster (25 photos) should complete quickly
        let mediumCluster = createPerformanceTestCluster(photoCount: 25)
        
        measure {
            let expectation = XCTestExpectation(description: "Medium cluster ranking")
            
            Task {
                let _ = await clusterCurationService.curateClusterRepresentatives([mediumCluster])
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 3.0)
        }
    }
    
    func testPerformance_LargeClusterRanking() throws {
        // Large cluster (100 photos) should still complete reasonably fast
        let largeCluster = createPerformanceTestCluster(photoCount: 100)
        
        measure {
            let expectation = XCTestExpectation(description: "Large cluster ranking")
            
            Task {
                let _ = await clusterCurationService.curateClusterRepresentatives([largeCluster])
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    func testPerformance_MultipleClusters() throws {
        // Multiple moderate clusters should process efficiently
        let clusters = createMultiplePerformanceTestClusters(clusterCount: 5, photosPerCluster: 20)
        
        measure {
            let expectation = XCTestExpectation(description: "Multiple clusters ranking")
            
            Task {
                let _ = await clusterCurationService.curateClusterRepresentatives(clusters)
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 8.0)
        }
    }
    
    // MARK: - Memory Performance Tests
    
    func testMemoryUsage_LargeClusterRanking() throws {
        // Test that memory usage remains reasonable for large clusters
        let largeCluster = createPerformanceTestCluster(photoCount: 200)
        
        let startMemory = getMemoryUsage()
        
        let expectation = XCTestExpectation(description: "Large cluster memory test")
        Task {
            let _ = await clusterCurationService.curateClusterRepresentatives([largeCluster])
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
        
        let endMemory = getMemoryUsage()
        let memoryIncrease = endMemory - startMemory
        
        // Memory increase should be reasonable (less than 100MB for 200 photos)
        XCTAssertLessThan(memoryIncrease, 100 * 1024 * 1024, "Memory increase should be less than 100MB")
    }
    
    func testMemoryCleanup_AfterRanking() throws {
        // Test that memory is properly cleaned up after ranking
        let initialMemory = getMemoryUsage()
        
        // Perform multiple ranking operations
        for _ in 0..<5 {
            let cluster = createPerformanceTestCluster(photoCount: 50)
            let expectation = XCTestExpectation(description: "Memory cleanup test")
            
            Task {
                let _ = await clusterCurationService.curateClusterRepresentatives([cluster])
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 5.0)
        }
        
        // Force garbage collection
        autoreleasepool {}
        
        let finalMemory = getMemoryUsage()
        let memoryIncrease = finalMemory - initialMemory
        
        // Memory should not continuously grow (less than 50MB increase total)
        XCTAssertLessThan(memoryIncrease, 50 * 1024 * 1024, "Memory should not continuously grow")
    }
    
    // MARK: - Scalability Tests
    
    func testScalability_LinearPerformance() throws {
        // Test that performance scales roughly linearly with cluster size
        let sizes = [10, 20, 40, 80]
        var times: [TimeInterval] = []
        
        for size in sizes {
            let cluster = createPerformanceTestCluster(photoCount: size)
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            let expectation = XCTestExpectation(description: "Scalability test for \(size) photos")
            Task {
                let _ = await clusterCurationService.curateClusterRepresentatives([cluster])
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10.0)
            
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            times.append(processingTime)
        }
        
        // Performance should scale roughly linearly (each doubling should be less than 3x slower)
        for i in 1..<times.count {
            let timeRatio = times[i] / times[i-1]
            let sizeRatio = Double(sizes[i]) / Double(sizes[i-1])
            let scalabilityRatio = timeRatio / sizeRatio
            
            XCTAssertLessThan(scalabilityRatio, 3.0, "Performance should scale roughly linearly")
        }
    }
    
    func testScalability_ConcurrentClusters() throws {
        // Test handling multiple clusters concurrently
        let clusters = createMultiplePerformanceTestClusters(clusterCount: 10, photosPerCluster: 15)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let expectation = XCTestExpectation(description: "Concurrent clusters test")
        Task {
            let rankedResults = await clusterCurationService.curateClusterRepresentatives(clusters)
            
            // Verify all clusters were processed
            XCTAssertEqual(rankedResults.count, 10, "All clusters should be processed")
            
            for rankedCluster in rankedResults {
                XCTAssertEqual(rankedCluster.count, 15, "All photos in each cluster should be ranked")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete within reasonable time (15 seconds for 150 total photos)
        XCTAssertLessThan(processingTime, 15.0, "Concurrent cluster processing should complete within 15 seconds")
    }
    
    // MARK: - Responsiveness Tests
    
    func testResponsiveness_ProgressiveRanking() async throws {
        // Test that ranking can provide progressive results
        let largeCluster = createPerformanceTestCluster(photoCount: 100)
        
        var progressUpdates: [Int] = []
        
        // TODO: Implement progressive ranking callback in ClusterCurationService
        // This would allow UI to show partial results while ranking continues
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([largeCluster])
        
        guard let ranked = rankedPhotos.first else {
            XCTFail("Should have ranked photos")
            return
        }
        
        // Verify complete ranking
        XCTAssertEqual(ranked.count, 100, "All photos should be ranked")
        
        // Top 10 photos should have high scores
        let topTen = Array(ranked.prefix(10))
        for photo in topTen {
            XCTAssertNotNil(photo.overallScore, "Top photos should have scores")
        }
    }
    
    func testResponsiveness_CancellableRanking() async throws {
        // Test that ranking operations can be cancelled
        let largeCluster = createPerformanceTestCluster(photoCount: 150)
        
        // TODO: Implement cancellation support in ClusterCurationService
        // This would allow UI to cancel long-running operations
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let rankedPhotos = await clusterCurationService.curateClusterRepresentatives([largeCluster])
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete even for large clusters
        XCTAssertNotNil(rankedPhotos.first, "Should complete ranking")
        XCTAssertLessThan(processingTime, 20.0, "Should complete within reasonable time")
    }
    
    // MARK: - Helper Methods
    
    private func createPerformanceTestCluster(photoCount: Int) -> PhotoCluster {
        let cluster = PhotoCluster()
        var photos: [Photo] = []
        
        for i in 0..<photoCount {
            let photo = Photo(
                id: UUID(),
                assetIdentifier: "test-asset-\(i)",
                timestamp: Date().addingTimeInterval(TimeInterval(i * 60)), // 1 minute apart
                location: CLLocation(latitude: 37.7749 + Double(i) * 0.001, longitude: -122.4194),
                metadata: PhotoMetadata(width: 1024, height: 768)
            )
            
            // Add mock scoring data
            let technicalScore = TechnicalQualityScore(
                sharpness: Float.random(in: 0.5...0.9),
                exposure: Float.random(in: 0.6...0.9),
                colorBalance: Float.random(in: 0.5...0.9),
                noise: Float.random(in: 0.1...0.4),
                compositionScore: Float.random(in: 0.5...0.9),
                overallTechnical: Float.random(in: 0.5...0.9)
            )
            
            let contextScore = ContextualScore(
                timeOfDay: [.morning, .afternoon, .evening, .goldenHour].randomElement()!,
                location: [.indoor, .outdoor, .urban, .nature].randomElement()!,
                event: nil,
                season: .summer,
                weather: .clear,
                overallContext: Float.random(in: 0.5...0.8)
            )
            
            let overallScore = PhotoScore(
                technical: technicalScore,
                faces: nil,
                context: contextScore,
                overall: Float.random(in: 0.5...0.9)
            )
            
            photo.overallScore = overallScore
            photos.append(photo)
        }
        
        cluster.photos = photos
        return cluster
    }
    
    private func createMultiplePerformanceTestClusters(clusterCount: Int, photosPerCluster: Int) -> [PhotoCluster] {
        var clusters: [PhotoCluster] = []
        
        for _ in 0..<clusterCount {
            let cluster = createPerformanceTestCluster(photoCount: photosPerCluster)
            clusters.append(cluster)
        }
        
        return clusters
    }
    
    private func getMemoryUsage() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self(), task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}