import SwiftUI

struct PhotoGridView: View {
    @StateObject private var viewModel = PhotoLibraryViewModel()
    @State private var showingSettings = false
    @State private var showingFilter = false
    @State private var showingFilterPhotos = false
    @State private var qualityFilter: QualityFilter = .all
    
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    enum QualityFilter: String, CaseIterable, Hashable {
        case all = "All Photos"
        case excellent = "Excellent (80%+)"
        case good = "Good (60%+)"
        case fair = "Fair (40%+)"
        case needsWork = "Needs Work (<40%)"
        
        var threshold: Float? {
            switch self {
            case .all: return nil
            case .excellent: return 0.8
            case .good: return 0.6
            case .fair: return 0.4
            case .needsWork: return 0.0
            }
        }
        
        var upperThreshold: Float? {
            switch self {
            case .needsWork: return 0.4
            default: return nil
            }
        }
    }
    
    private var filteredPhotos: [Photo] {
        let photos = viewModel.photos
        
        switch qualityFilter {
        case .all:
            return photos
        case .excellent:
            return photos.filter { photo in
                guard let score = photo.overallScore?.overall else { return false }
                return score >= 0.8
            }
        case .good:
            return photos.filter { photo in
                guard let score = photo.overallScore?.overall else { return false }
                return score >= 0.6
            }
        case .fair:
            return photos.filter { photo in
                guard let score = photo.overallScore?.overall else { return false }
                return score >= 0.4 && score < 0.6
            }
        case .needsWork:
            return photos.filter { photo in
                guard let score = photo.overallScore?.overall else { return true }
                return score < 0.4
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Main Content - Edge to Edge
            Group {
                if viewModel.isLoading {
                    LoadingView(viewModel: viewModel)
                } else if viewModel.photos.isEmpty {
                    if viewModel.authorizationStatus == .notDetermined {
                        PermissionRequestView(viewModel: viewModel)
                    } else {
                        EmptyStateView(viewModel: viewModel)
                    }
                } else {
                    FilteredPhotoGrid(photos: filteredPhotos, viewModel: viewModel, columns: columns)
                }
            }
            .ignoresSafeArea(.all) // Edge-to-edge content
            
            // Floating Glass UI Elements
            VStack {
                // Top floating toolbar with glass effect
                HStack {
                    Spacer()
                    
                    if !viewModel.photos.isEmpty {
                        HStack(spacing: 12) {
                            // Filter button with glass effect
                            GlassButton(
                                icon: qualityFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill",
                                action: { showingFilter = true }
                            )
                            
                            // Settings button with glass effect
                            GlassButton(
                                icon: "ellipsis.circle",
                                action: { showingSettings = true }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8) // Just below status bar
                
                Spacer()
                
                // Bottom floating heart button with glass effect
                if !viewModel.photos.isEmpty {
                    HStack {
                        Spacer()
                        
                        GlassFilterButton(action: { showingFilterPhotos = true })
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34) // Above home indicator
                }
            }
        }
        .navigationBarHidden(true) // Hide navigation bar for edge-to-edge effect
            .sheet(isPresented: $showingSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingFilter) {
                QualityFilterView(selectedFilter: $qualityFilter, photoCount: viewModel.photos.count, viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $showingFilterPhotos) {
                FilterPhotosView(photoViewModel: viewModel)
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadExistingPhotos()
            }
    }
}

// MARK: - Permission Request View

struct PermissionRequestView: View {
    let viewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tertiary)
                
                VStack(spacing: 8) {
                    Text("Access Your Photos")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Analyze and curate your best photos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button(action: {
                Task {
                    await viewModel.requestPhotoLibraryAccess()
                }
            }) {
                Text("Continue")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: viewModel.loadingProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .frame(maxWidth: 200)
            
            VStack(spacing: 6) {
                Text(viewModel.loadingText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                
                if viewModel.loadingProgress > 0 {
                    Text("\(Int(viewModel.loadingProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let viewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tertiary)
                
                VStack(spacing: 6) {
                    Text("No Photos")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Check your photo library and permissions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button("Try Again") {
                Task {
                    await viewModel.loadPhotosFromLibrary()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Photo Grid

struct PhotoGrid: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let columns: [GridItem]
    
    var body: some View {
        FilteredPhotoGrid(photos: viewModel.photos, viewModel: viewModel, columns: columns)
    }
}

struct FilteredPhotoGrid: View {
    let photos: [Photo]
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let columns: [GridItem]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(photos) { photo in
                    PhotoThumbnailView(photo: photo, viewModel: viewModel)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                }
            }
            .padding(.horizontal, 0)
        }
        .clipped()
    }
}

// MARK: - Photo Thumbnail View

struct PhotoThumbnailView: View {
    let photo: Photo
    let viewModel: PhotoLibraryViewModel
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    @State private var showingDetailView = false
    
    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.gray)
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.gray.opacity(0.5))
                            .font(.system(size: 20))
                    }
            }
        }
        .cornerRadius(0)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingDetailView = true
            }
        }
        .fullScreenCover(isPresented: $showingDetailView) {
            PhotoDetailView(photo: photo, viewModel: viewModel)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .scale(scale: 1.05))
                ))
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task {
            isLoading = true
            let image = await viewModel.loadThumbnail(for: photo)
            await MainActor.run {
                self.thumbnailImage = image
                self.isLoading = false
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingPhotoAnalysis = false
    @State private var showingPhotoScoring = false
    @State private var showingPhotoClustering = false
    @State private var showingScoredPhotos = false
    @State private var showingFilterPhotos = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Photos", value: "\(viewModel.totalPhotosCount)")
                    LabeledContent("With Location", value: "\(viewModel.photosWithLocationCount)")
                    
                    let dateRange = viewModel.dateRange
                    if let startDate = dateRange.start,
                       let endDate = dateRange.end {
                        LabeledContent("Date Range") {
                            Text("\(startDate.formatted(date: .abbreviated, time: .omitted)) - \(endDate.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Library")
                }
                
                Section {
                    Button("Analyze Quality") {
                        showingPhotoAnalysis = true
                    }
                    .disabled(viewModel.photos.isEmpty)
                    
                    Button("Score Photos") {
                        showingPhotoScoring = true
                    }
                    .disabled(viewModel.photos.isEmpty)
                    
                    Button("View Scored Photos") {
                        showingScoredPhotos = true
                    }
                    .disabled(viewModel.photos.isEmpty)
                    
                    Button("Filter & Sort Photos") {
                        showingFilterPhotos = true
                    }
                    .disabled(viewModel.photos.isEmpty)
                } header: {
                    Text("AI Features")
                }
                
                Section {
                    Button("Recent (30 days)") {
                        viewModel.filterRecentPhotos(days: 30)
                        dismiss()
                    }
                    
                    Button("With Location") {
                        viewModel.filterPhotosWithLocation()
                        dismiss()
                    }
                } header: {
                    Text("Filters")
                }
                
                Section {
                    Button("Clear All Photos", role: .destructive) {
                        Task {
                            await viewModel.clearDatabase()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPhotoAnalysis) {
                PhotoAnalysisView(photoViewModel: viewModel)
            }
            .sheet(isPresented: $showingPhotoScoring) {
                PhotoScoringView(photoViewModel: viewModel)
            }
            .sheet(isPresented: $showingScoredPhotos) {
                ScoredPhotosView(photoViewModel: viewModel)
            }
            .sheet(isPresented: $showingPhotoClustering) {
                PhotoClusteringView(photoViewModel: viewModel)
            }
            .fullScreenCover(isPresented: $showingFilterPhotos) {
                FilterPhotosView(photoViewModel: viewModel)
            }
        }
    }
}

// MARK: - Quality Filter View

struct QualityFilterView: View {
    @Binding var selectedFilter: PhotoGridView.QualityFilter
    let photoCount: Int
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PhotoGridView.QualityFilter.allCases, id: \.self) { filter in
                        FilterRowView(
                            filter: filter,
                            selectedFilter: selectedFilter,
                            photoCount: getPhotoCount(for: filter),
                            onTap: {
                                selectedFilter = filter
                                dismiss()
                            }
                        )
                    }
                } header: {
                    Text("Filter by Quality Score")
                } footer: {
                    Text("Quality scores are based on technical analysis including sharpness, exposure, composition, and face detection.")
                }
            }
            .navigationTitle("Filter Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    
    private func getPhotoCount(for filter: PhotoGridView.QualityFilter) -> Int {
        guard let threshold = filter.threshold else {
            return viewModel.photos.count
        }
        
        return viewModel.photos.filter { photo in
            guard let score = photo.overallScore?.overall else {
                return filter == .needsWork // Count unscored photos in "Needs Work"
            }
            
            if let upperThreshold = filter.upperThreshold {
                return score >= threshold && score < upperThreshold
            } else {
                return score >= threshold
            }
        }.count
    }
}

// MARK: - Filter Row View

struct FilterRowView: View {
    let filter: PhotoGridView.QualityFilter
    let selectedFilter: PhotoGridView.QualityFilter
    let photoCount: Int
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            filterInfoView
            Spacer()
            photoCountView
            if selectedFilter == filter {
                checkmarkView
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private var filterInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(filter.rawValue)
                .font(.body)
            
            Text(filterDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var photoCountView: some View {
        Text("\(photoCount)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
    
    private var checkmarkView: some View {
        Image(systemName: "checkmark")
            .foregroundColor(.accentColor)
            .fontWeight(.semibold)
    }
    
    private var filterDescription: String {
        switch filter {
        case .all:
            return "Show all photos"
        case .excellent:
            return "High quality photos ready for sharing"
        case .good:
            return "Well-composed photos with good technical quality"
        case .fair:
            return "Decent photos that might need minor adjustments"
        case .needsWork:
            return "Photos with technical issues or poor composition"
        }
    }
}

// MARK: - Glass Effect Components

struct GlassButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(
                    ZStack {
                        // Glass background effect
                        RoundedRectangle(cornerRadius: 22)
                            .fill(.ultraThinMaterial)
                        
                        // Subtle border
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    }
                )
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GlassHeartButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "heart.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    ZStack {
                        // Main colored background with glass effect
                        Circle()
                            .fill(.thinMaterial)
                            .background(
                                Circle()
                                    .fill(Color.accentColor)
                            )
                        
                        // Glass overlay effect
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.3),
                                        .white.opacity(0.1),
                                        .clear,
                                        .black.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Subtle border
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    }
                )
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.1), value: false)
    }
}

struct GlassFilterButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(
                    ZStack {
                        // Main colored background with glass effect
                        Circle()
                            .fill(.thinMaterial)
                            .background(
                                Circle()
                                    .fill(Color.accentColor)
                            )
                        
                        // Glass overlay effect
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.3),
                                        .white.opacity(0.1),
                                        .clear,
                                        .black.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Subtle border
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    }
                )
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.1), value: false)
    }
}

// MARK: - Preview

#Preview {
    PhotoGridView()
}