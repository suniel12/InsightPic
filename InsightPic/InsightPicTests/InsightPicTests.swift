import XCTest
@testable import InsightPic

final class InsightPicTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testPhotoModelCreation() throws {
        // Test basic Photo model creation
        let photoId = UUID()
        let assetId = "test-asset-123"
        let timestamp = Date()
        
        let metadata = PhotoMetadata(
            width: 1920,
            height: 1080,
            cameraMake: "Apple",
            cameraModel: "iPhone 15",
            focalLength: 26.0,
            aperture: 1.6,
            shutterSpeed: 0.016,
            iso: 100
        )
        
        let photo = Photo(
            id: photoId,
            assetIdentifier: assetId,
            timestamp: timestamp,
            location: nil,
            metadata: metadata
        )
        
        XCTAssertEqual(photo.id, photoId)
        XCTAssertEqual(photo.assetIdentifier, assetId)
        XCTAssertEqual(photo.timestamp, timestamp)
        XCTAssertNil(photo.location)
        XCTAssertEqual(photo.metadata.width, 1920)
        XCTAssertEqual(photo.metadata.height, 1080)
        XCTAssertNil(photo.fingerprint)
        XCTAssertNil(photo.overallScore)
    }
    
    func testPhotoScoreCalculation() throws {
        // Test PhotoScore calculation with different photo types
        let technicalScore: Float = 0.8
        let facesScore: Float = 0.9
        let contextScore: Float = 0.7
        
        // Test portrait photo weighting
        let portraitScore = PhotoScore.calculate(
            technical: technicalScore,
            faces: facesScore,
            context: contextScore,
            photoType: .portrait
        )
        
        let expectedPortraitScore = technicalScore * 0.4 + facesScore * 0.4 + contextScore * 0.2
        XCTAssertEqual(portraitScore, expectedPortraitScore, accuracy: 0.001)
        
        // Test landscape photo weighting
        let landscapeScore = PhotoScore.calculate(
            technical: technicalScore,
            faces: facesScore,
            context: contextScore,
            photoType: .landscape
        )
        
        let expectedLandscapeScore = technicalScore * 0.5 + contextScore * 0.4 + facesScore * 0.1
        XCTAssertEqual(landscapeScore, expectedLandscapeScore, accuracy: 0.001)
        
        // Test multiple faces photo weighting
        let multipleFacesScore = PhotoScore.calculate(
            technical: technicalScore,
            faces: facesScore,
            context: contextScore,
            photoType: .multipleFaces
        )
        
        let expectedMultipleFacesScore = technicalScore * 0.3 + facesScore * 0.5 + contextScore * 0.2
        XCTAssertEqual(multipleFacesScore, expectedMultipleFacesScore, accuracy: 0.001)
    }
    
    func testPhotoClusterCreation() throws {
        // Test PhotoCluster creation and computed properties
        let clusterId = UUID()
        let cluster = PhotoCluster(id: clusterId, photos: [])
        
        XCTAssertEqual(cluster.id, clusterId)
        XCTAssertTrue(cluster.photos.isEmpty)
        XCTAssertNil(cluster.medianTimestamp)
        XCTAssertNil(cluster.medianLocation)
    }
    
    func testTechnicalQualityScoreCreation() throws {
        // Test TechnicalQualityScore model
        let score = TechnicalQualityScore(
            sharpness: 0.8,
            exposure: 0.9,
            composition: 0.7
        )
        
        XCTAssertEqual(score.sharpness, 0.8)
        XCTAssertEqual(score.exposure, 0.9)
        XCTAssertEqual(score.composition, 0.7)
        
        let expectedOverall = (0.8 + 0.9 + 0.7) / 3.0
        XCTAssertEqual(score.overall, expectedOverall, accuracy: 0.001)
    }
    
    func testFaceQualityScoreCreation() throws {
        // Test FaceQualityScore model
        let score = FaceQualityScore(
            faceCount: 2,
            eyesOpen: 0.95,
            smiling: 0.8,
            faceSize: 0.9,
            faceAngle: 0.85
        )
        
        XCTAssertEqual(score.faceCount, 2)
        XCTAssertEqual(score.eyesOpen, 0.95)
        XCTAssertEqual(score.smiling, 0.8)
        XCTAssertEqual(score.faceSize, 0.9)
        XCTAssertEqual(score.faceAngle, 0.85)
        
        let expectedOverall = (0.95 + 0.8 + 0.9 + 0.85) / 4.0
        XCTAssertEqual(score.overall, expectedOverall, accuracy: 0.001)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
            for _ in 0..<1000 {
                let _ = Photo(
                    id: UUID(),
                    assetIdentifier: "test-\(UUID().uuidString)",
                    timestamp: Date(),
                    location: nil,
                    metadata: PhotoMetadata(
                        width: 1920,
                        height: 1080,
                        cameraMake: "Apple",
                        cameraModel: "iPhone 15"
                    )
                )
            }
        }
    }
}