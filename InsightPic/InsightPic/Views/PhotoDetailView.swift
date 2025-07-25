import SwiftUI

struct PhotoDetailView: View {
    let photo: Photo
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var fullImage: UIImage?
    @State private var isImageLoading = true
    @State private var imageLoadError: String?
    @State private var showingPhotoInfo = false
    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0
    @State private var showControls = true
    @State private var dragOffset: CGSize = .zero
    @State private var dragScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geometry in
                if isImageLoading {
                    LoadingImageView()
                } else if let error = imageLoadError {
                    ErrorImageView(error: error)
                } else if let image = fullImage {
                    EnhancedImageView(
                        image: image,
                        geometry: geometry,
                        currentScale: $currentScale,
                        finalScale: $finalScale,
                        dragOffset: $dragOffset,
                        dragScale: $dragScale,
                        showControls: $showControls,
                        onDismiss: { dismiss() }
                    )
                }
            }
            
            // Top controls overlay
            VStack {
                if showControls {
                    HStack {
                        Spacer()
                        
                        Button(action: { 
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showingPhotoInfo.toggle() 
                            }
                        }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.white)
                                .font(.system(size: 17, weight: .medium))
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 8)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 120)
                        .allowsHitTesting(false)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                Spacer()
            }
            .zIndex(1)
        }
        .statusBarHidden(!showControls)
        .animation(.easeInOut(duration: 0.25), value: showControls)
        .sheet(isPresented: $showingPhotoInfo) {
            PhotoInfoView(photo: photo)
        }
        .task {
            await loadFullImage()
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls.toggle()
            }
        }
    }
    
    private func loadFullImage() async {
        isImageLoading = true
        imageLoadError = nil
        
        let image = await viewModel.loadFullImage(for: photo)
        await MainActor.run {
            if let image = image {
                self.fullImage = image
            } else {
                self.imageLoadError = "Failed to load full resolution image"
            }
            self.isImageLoading = false
        }
    }
}

// MARK: - Loading Image View

struct LoadingImageView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Loading full resolution image...")
                .foregroundColor(.white)
                .font(.caption)
        }
    }
}

// MARK: - Error Image View

struct ErrorImageView: View {
    let error: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.white)
            
            Text("Failed to Load Image")
                .foregroundColor(.white)
                .font(.headline)
            
            Text(error)
                .foregroundColor(.gray)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

// MARK: - Enhanced Image View

struct EnhancedImageView: View {
    let image: UIImage
    let geometry: GeometryProxy
    @Binding var currentScale: CGFloat
    @Binding var finalScale: CGFloat
    @Binding var dragOffset: CGSize
    @Binding var dragScale: CGFloat
    @Binding var showControls: Bool
    let onDismiss: () -> Void
    
    @State private var currentOffset: CGSize = .zero
    @State private var finalOffset: CGSize = .zero
    @State private var isDraggingToExit = false
    
    private let dismissThreshold: CGFloat = 100
    
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(currentScale * dragScale)
            .offset(x: currentOffset.width + dragOffset.width, y: currentOffset.height + dragOffset.height)
            .gesture(
                SimultaneousGesture(
                    // Zoom gesture
                    MagnificationGesture()
                        .onChanged { value in
                            currentScale = finalScale * value
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.3)) {
                                finalScale = min(max(finalScale * value, 0.5), 3.0)
                                currentScale = finalScale
                            }
                        },
                    
                    // Pan/Dismiss gesture
                    DragGesture()
                        .onChanged { value in
                            if finalScale <= 1.0 {
                                // Swipe to dismiss when not zoomed
                                let translation = value.translation
                                
                                dragOffset = translation
                                
                                // Calculate scale based on vertical drag distance
                                let dragDistance = abs(translation.height)
                                let maxDragDistance: CGFloat = 200
                                let scaleReduction = min(dragDistance / maxDragDistance, 0.3)
                                dragScale = 1.0 - scaleReduction
                                
                                // Hide controls when dragging
                                if abs(translation.height) > 20 && showControls {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showControls = false
                                    }
                                }
                                
                                isDraggingToExit = abs(translation.height) > dismissThreshold
                            } else {
                                // Regular pan when zoomed
                                currentOffset = CGSize(
                                    width: finalOffset.width + value.translation.width,
                                    height: finalOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { value in
                            if finalScale <= 1.0 {
                                // Handle swipe to dismiss
                                let translation = value.translation
                                let velocity = value.velocity
                                
                                let shouldDismiss = abs(translation.height) > dismissThreshold || 
                                                   (abs(velocity.height) > 500 && abs(translation.height) > 50)
                                
                                if shouldDismiss {
                                    // Animate dismissal
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        dragOffset = CGSize(
                                            width: translation.width + velocity.width * 0.1,
                                            height: translation.height + velocity.height * 0.1
                                        )
                                        dragScale = 0.1
                                        showControls = false
                                    }
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        onDismiss()
                                    }
                                } else {
                                    // Bounce back
                                    withAnimation(.easeOut(duration: 0.4)) {
                                        dragOffset = .zero
                                        dragScale = 1.0
                                        showControls = true
                                    }
                                }
                                
                                isDraggingToExit = false
                            } else {
                                // Handle zoomed pan
                                finalOffset = currentOffset
                                
                                // Limit pan to image bounds
                                let maxOffsetX = (geometry.size.width * (currentScale - 1)) / 2
                                let maxOffsetY = (geometry.size.height * (currentScale - 1)) / 2
                                
                                finalOffset.width = min(max(finalOffset.width, -maxOffsetX), maxOffsetX)
                                finalOffset.height = min(max(finalOffset.height, -maxOffsetY), maxOffsetY)
                                
                                withAnimation(.easeOut(duration: 0.3)) {
                                    currentOffset = finalOffset
                                }
                            }
                        }
                )
            )
            .onTapGesture(count: 2) {
                // Double tap to zoom
                withAnimation(.easeInOut(duration: 0.3)) {
                    if finalScale > 1.0 {
                        // Zoom out
                        finalScale = 1.0
                        currentScale = 1.0
                        finalOffset = .zero
                        currentOffset = .zero
                    } else {
                        // Zoom in
                        finalScale = 2.0
                        currentScale = 2.0
                    }
                }
            }
            .onTapGesture {
                // Single tap handled by parent view
            }
    }
}

// MARK: - Photo Info View

struct PhotoInfoView: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Date", value: photo.timestamp.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Dimensions", value: "\(photo.metadata.width) × \(photo.metadata.height)")
                    
                    if let location = photo.location {
                        LabeledContent("Location", value: String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude))
                    }
                }
                
                if hasMetadata {
                    Section("Camera") {
                        if let camera = photo.metadata.cameraModel {
                            LabeledContent("Model", value: camera)
                        }
                        
                        if let focalLength = photo.metadata.focalLength {
                            LabeledContent("Focal Length", value: String(format: "%.1fmm", focalLength))
                        }
                        
                        if let aperture = photo.metadata.fNumber {
                            LabeledContent("Aperture", value: String(format: "f/%.1f", aperture))
                        }
                        
                        if let shutterSpeed = photo.metadata.exposureTime {
                            LabeledContent("Shutter", value: formatShutterSpeed(shutterSpeed))
                        }
                        
                        if let iso = photo.metadata.iso {
                            LabeledContent("ISO", value: "\(iso)")
                        }
                    }
                }
                
                if let technicalQuality = photo.technicalQuality {
                    Section("Quality") {
                        LabeledContent("Sharpness", value: "\(Int(technicalQuality.sharpness * 100))%")
                        LabeledContent("Exposure", value: "\(Int(technicalQuality.exposure * 100))%")
                        LabeledContent("Composition", value: "\(Int(technicalQuality.composition * 100))%")
                        LabeledContent("Overall", value: "\(Int(technicalQuality.overall * 100))%")
                    }
                }
                
                if let faceQuality = photo.faceQuality, faceQuality.faceCount > 0 {
                    Section("Faces") {
                        LabeledContent("Count", value: "\(faceQuality.faceCount)")
                        LabeledContent("Quality", value: "\(Int(faceQuality.averageScore * 100))%")
                        LabeledContent("Eyes Open", value: faceQuality.eyesOpen ? "Yes" : "No")
                        LabeledContent("Expressions", value: faceQuality.goodExpressions ? "Good" : "Fair")
                    }
                }
                
                if let overallScore = photo.overallScore {
                    Section("Assessment") {
                        LabeledContent("Technical", value: "\(Int(overallScore.technical * 100))%")
                        LabeledContent("Faces", value: "\(Int(overallScore.faces * 100))%")
                        LabeledContent("Context", value: "\(Int(overallScore.context * 100))%")
                        LabeledContent("Final Score") {
                            Text("\(Int(overallScore.overall * 100))%")
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var hasMetadata: Bool {
        photo.metadata.cameraModel != nil || 
        photo.metadata.focalLength != nil || 
        photo.metadata.fNumber != nil || 
        photo.metadata.exposureTime != nil || 
        photo.metadata.iso != nil
    }
    
    private func formatShutterSpeed(_ speed: Double) -> String {
        if speed < 1.0 {
            let fraction = Int(1.0 / speed)
            return "1/\(fraction)s"
        } else {
            return String(format: "%.1fs", speed)
        }
    }
}


// MARK: - Universal Photo Gallery View with Swipe Navigation

struct PhotoDetailGalleryView: View {
    let initialPhoto: Photo
    let photos: [Photo]
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentPhotoIndex: Int
    @State private var showPhotoCounter: Bool = true
    
    init(initialPhoto: Photo, photos: [Photo], viewModel: PhotoLibraryViewModel, showPhotoCounter: Bool = true) {
        self.initialPhoto = initialPhoto
        self.photos = photos
        self.viewModel = viewModel
        self.showPhotoCounter = showPhotoCounter
        
        // Set the initial index to the selected photo
        if let index = photos.firstIndex(where: { $0.id == initialPhoto.id }) {
            self._currentPhotoIndex = State(initialValue: index)
        } else {
            self._currentPhotoIndex = State(initialValue: 0)
        }
    }
    
    var currentPhoto: Photo {
        guard currentPhotoIndex >= 0 && currentPhotoIndex < photos.count else {
            return initialPhoto
        }
        return photos[currentPhotoIndex]
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Photo display with universal swipe navigation
            PhotoDetailView(photo: currentPhoto, viewModel: viewModel)
                .id(currentPhoto.id) // Force view recreation when photo changes
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            let threshold: CGFloat = 50
                            let velocity = value.velocity.width
                            
                            // Only handle horizontal swipes when there are multiple photos
                            guard photos.count > 1 else { return }
                            
                            // Check if it's a horizontal swipe (not vertical dismiss)
                            if abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                                if value.translation.width > threshold || velocity > 400 {
                                    // Swipe right - previous photo
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        if currentPhotoIndex > 0 {
                                            currentPhotoIndex -= 1
                                        }
                                    }
                                } else if value.translation.width < -threshold || velocity < -400 {
                                    // Swipe left - next photo
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        if currentPhotoIndex < photos.count - 1 {
                                            currentPhotoIndex += 1
                                        }
                                    }
                                }
                            }
                        }
                )
            
            // Photo counter overlay (only show if more than 1 photo and enabled)
            if showPhotoCounter && photos.count > 1 {
                VStack {
                    HStack {
                        Spacer()
                        
                        Text("\(currentPhotoIndex + 1) of \(photos.count)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoDetailView(
        photo: Photo(
            id: UUID(),
            assetIdentifier: "preview-photo",
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(
                width: 1920,
                height: 1080,
                cameraModel: "iPhone 15 Pro",
                focalLength: 24.0,
                fNumber: 1.8,
                exposureTime: 0.008,
                iso: 100
            )
        ),
        viewModel: PhotoLibraryViewModel.preview
    )
}