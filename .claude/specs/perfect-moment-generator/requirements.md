# Perfect Moment Generator - Requirements

## Feature Overview
The Perfect Moment Generator solves the common problem of group photos being ruined by closed eyes, poor expressions, or awkward poses. Using photo clusters from InsightPic's existing clustering system, this feature analyzes multiple shots of the same scene to identify the best expressions for each person and creates a composite "perfect moment" photo.

## Business Justification
- **High Pain Point**: Group photos ruined by blinks, poor expressions, or awkward poses
- **Validated Market**: Apps like YouCam Makeup and Facetune have "Retake" features confirming demand
- **High Willingness to Pay**: Users value "rescuing" irreplaceable photos from important events
- **Natural Extension**: Leverages existing photo clustering pipeline perfectly

## Codebase Analysis Summary

### Existing Components to Leverage
- **PhotoCluster model**: Already groups similar photos from same scene/moment
- **Vision Framework integration**: PhotoClusteringService.swift has VNGenerateImageFeaturePrintRequest
- **Photo analysis pipeline**: PhotoAnalysisService exists with face detection capabilities
- **Quality scoring**: Photo.overallScore already tracks technical quality metrics
- **Core Image processing**: Existing thumbnail generation and image processing

### Integration Points
- **PhotoClusteringViewModel**: Will need new perfectMomentGeneration state
- **ClusterPhotosView**: New UI for "Create Perfect Moment" button
- **PhotoDataRepository**: Store generated perfect moment results
- **Existing clustering criteria**: Already filters similar photos with face compatibility

### Architecture Patterns
- **SwiftUI + ObservableObject**: Follow existing PhotoLibraryViewModel pattern
- **async/await**: Use existing async patterns from clustering service
- **Vision Framework**: Extend existing VN request patterns
- **Error handling**: Follow existing PhotoCuratorError patterns

## User Stories

### US1: Perfect Moment Discovery
**As a** user reviewing photo clusters  
**I want** to see when a cluster contains photos that could be improved by combining the best expressions  
**So that** I can rescue group photos that were ruined by blinks or poor expressions

#### Acceptance Criteria
1. WHEN I view a photo cluster with 2+ similar photos containing faces THEN the system SHALL display a "Create Perfect Moment" option
2. WHEN the cluster contains photos with different facial expressions THEN the system SHALL identify improvement opportunities  
3. WHEN no improvement is possible (single photo or no face variations) THEN the system SHALL NOT show the perfect moment option

### US2: Perfect Moment Generation
**As a** user with a group photo containing poor expressions  
**I want** to generate a composite photo using the best expressions from multiple shots  
**So that** I can create a flawless memory of an important moment

#### Acceptance Criteria
1. WHEN I tap "Create Perfect Moment" THEN the system SHALL analyze all photos in the cluster for face quality
2. WHEN multiple photos contain the same person THEN the system SHALL identify the best expression for each person
3. WHEN faces can be naturally composited THEN the system SHALL generate a seamless perfect moment photo
4. WHEN the result is generated THEN the system SHALL show before/after comparison
5. WHEN generation fails THEN the system SHALL provide clear error messaging

### US3: Quality Validation
**As a** user viewing a generated perfect moment  
**I want** to see natural-looking results that maintain photo authenticity  
**So that** the improved photo looks believable and high-quality

#### Acceptance Criteria
1. WHEN a perfect moment is generated THEN faces SHALL blend naturally with proper lighting and color matching
2. WHEN the composite is complete THEN edge artifacts SHALL be minimized through proper blending
3. WHEN viewing the result THEN the photo SHALL maintain the original's composition and background quality
4. IF the quality is insufficient THEN the system SHALL provide option to use original photo

### US4: Perfect Moment Management
**As a** user who has generated perfect moments  
**I want** to save, share, and manage the improved photos  
**So that** I can use them like any other photo in my collection

#### Acceptance Criteria
1. WHEN I approve a perfect moment THEN the system SHALL save it to my photo collection
2. WHEN saving THEN the system SHALL preserve original photo metadata (timestamp, location)
3. WHEN sharing THEN the generated photo SHALL be available through standard share sheet
4. WHEN managing photos THEN I SHALL be able to distinguish between original and generated photos

## Technical Requirements

### TR1: Vision Framework Integration
- Use VNDetectFaceRectanglesRequest for face detection
- Use VNDetectFaceLandmarksRequest for precise facial feature analysis
- Use VNDetectFaceCaptureQualityRequest for face quality scoring
- Use VNCalculateImageAestheticsScoresRequest for overall image quality
- Use VNGeneratePersonInstanceMaskRequest for person segmentation

### TR2: Quality Analysis Engine
- Implement eye state detection using facial landmarks
- Implement smile detection using lip curvature analysis  
- Calculate face quality scores combining multiple metrics
- Filter utility images using isUtility property
- Select optimal base photo using aesthetic scores

### TR3: Composite Generation
- Extract faces using person segmentation masks
- Align faces using 3D orientation matching (pitch, yaw, roll)
- Blend faces using Core Image filters
- Match lighting and color between source and destination
- Validate result quality before presenting to user

### TR4: Performance Requirements
- Process 4-person group photo in <15 seconds on A15+ devices
- Support clusters with 2-10 photos
- Maintain responsive UI during processing
- Use Neural Engine acceleration where available

## Non-Functional Requirements

### NFR1: Privacy
- All processing SHALL occur on-device using Vision Framework
- No photos SHALL be uploaded to external servers
- Generated photos SHALL be stored locally only

### NFR2: Device Compatibility  
- Require iOS 16+ for VNCalculateImageAestheticsScoresRequest
- Optimal performance on A15 Bionic or newer
- Graceful degradation on older devices

### NFR3: User Experience
- Generate natural-looking results in 80%+ of attempts
- Achieve 4.5+ user satisfaction rating for successful generations
- Process photos without blocking main UI thread

## Edge Cases & Error Handling

### EC1: Insufficient Source Material
- WHEN cluster has <2 photos THEN disable perfect moment option
- WHEN photos lack face variations THEN show "no improvements possible" message
- WHEN faces are too different (different people) THEN prevent generation

### EC2: Technical Limitations
- WHEN face alignment fails THEN fall back to original photo with explanation
- WHEN processing times out THEN provide cancellation option
- WHEN device lacks sufficient memory THEN show resource warning

### EC3: Quality Validation
- WHEN composite quality is poor THEN offer original photo as alternative
- WHEN blending artifacts are detected THEN apply additional smoothing
- WHEN color matching fails THEN adjust lighting compensation

## Success Metrics

### User Adoption
- 60% of eligible cluster viewers try Perfect Moment Generator
- 75% completion rate for initiated perfect moment generations
- 40% of users generate multiple perfect moments

### Quality Metrics
- 80% of generated photos rated "natural looking" by users
- <5% rate of obvious blending artifacts
- 90% face detection accuracy in clustered photos

### Business Impact
- 30% increase in time spent in clustering view
- 25% increase in photo sharing from InsightPic
- Premium feature driving subscription conversions

## Dependencies
- Existing photo clustering system (PhotoClusteringService)
- Vision Framework iOS 16+ capabilities
- Core Image processing pipeline
- PhotoAnalysisService face detection

## Risks & Mitigations
- **Risk**: Generated photos look artificial → **Mitigation**: Extensive quality validation and fallback to originals
- **Risk**: Processing performance issues → **Mitigation**: Background processing with progress indicators  
- **Risk**: Limited device compatibility → **Mitigation**: Feature flags and graceful degradation
- **Risk**: User expectations too high → **Mitigation**: Clear messaging about feature limitations