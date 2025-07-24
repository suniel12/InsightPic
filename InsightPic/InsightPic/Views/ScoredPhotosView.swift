import SwiftUI

struct ScoredPhotosView: View {
    @StateObject private var scoringViewModel = PhotoScoringViewModel()
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedQualityFilter: ScoredPhotoFilter = .all
    @State private var showingFilterSheet = false
    @State private var scoredPhotos: [Photo] = []
    @State private var isLoading = true
    
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    enum ScoredPhotoFilter: String, CaseIterable, Hashable {
        case all = "All Scored"
        case excellent = "Excellent (80%+)"
        case good = "Good (60%+)"
        case fair = "Fair (40%+)"
        case needsWork = "Needs Work (<40%)"
        case unscored = "Unscored"
        
        var description: String {
            switch self {
            case .all:
                return "Show all photos with quality scores"
            case .excellent:
                return "High quality photos ready for sharing"
            case .good:
                return "Well-composed photos with good technical quality"
            case .fair:
                return "Decent photos that might need minor adjustments"
            case .needsWork:
                return "Photos with technical issues or poor composition"
            case .unscored:
                return "Photos that haven't been analyzed yet"
            }
        }
        
        var systemImage: String {
            switch self {
            case .all:
                return "photo.on.rectangle"
            case .excellent:
                return "star.fill"
            case .good:
                return "checkmark.circle.fill"
            case .fair:
                return "minus.circle.fill"
            case .needsWork:
                return "exclamationmark.triangle.fill"
            case .unscored:
                return "questionmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .all:
                return .blue
            case .excellent:
                return .yellow
            case .good:
                return .green
            case .fair:
                return .orange
            case .needsWork:
                return .red
            case .unscored:
                return .gray
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ScoredPhotosLoadingView()
                } else if scoredPhotos.isEmpty {
                    ScoredPhotosEmptyStateView(filter: selectedQualityFilter)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 1) {
                            ForEach(scoredPhotos) { photo in
                                ScoredPhotoThumbnailView(
                                    photo: photo,
                                    viewModel: photoViewModel,
                                    showScore: selectedQualityFilter != .unscored
                                )
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                            }
                        }
                        .padding(.horizontal, 0)
                    }
                    .clipped()
                }
            }
            .navigationTitle(selectedQualityFilter.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showingFilterSheet = true }) {
                        Image(systemName: selectedQualityFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 17, weight: .medium))
                    }
                    
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                ScoredPhotoFilterView(
                    selectedFilter: $selectedQualityFilter,
                    scoringViewModel: scoringViewModel
                )
            }
            .task {
                await loadScoredPhotos()
            }
            .onChange(of: selectedQualityFilter) { _, _ in
                Task {
                    await loadScoredPhotos()
                }
            }
        }
    }
    
    private func loadScoredPhotos() async {
        isLoading = true
        
        switch selectedQualityFilter {
        case .all:
            scoredPhotos = photoViewModel.photos.filter { $0.overallScore != nil }
        case .excellent:
            scoredPhotos = await scoringViewModel.getExcellentPhotos()
        case .good:
            scoredPhotos = await scoringViewModel.getGoodPhotos()
        case .fair:
            scoredPhotos = await scoringViewModel.getPhotosByQuality(minimumScore: 0.4).filter { photo in
                guard let score = photo.overallScore?.overall else { return false }
                return score >= 0.4 && score < 0.6
            }
        case .needsWork:
            scoredPhotos = await scoringViewModel.getPoorPhotos()
        case .unscored:
            scoredPhotos = photoViewModel.photos.filter { $0.overallScore == nil }
        }
        
        isLoading = false
    }
}

// MARK: - Scored Photo Thumbnail View

struct ScoredPhotoThumbnailView: View {
    let photo: Photo
    let viewModel: PhotoLibraryViewModel
    let showScore: Bool
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    @State private var showingDetailView = false
    
    var body: some View {
        ZStack {
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
            
            // Quality Score Overlay
            if showScore, let overallScore = photo.overallScore {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(Int(overallScore.overall * 100))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.black.opacity(0.7))
                            )
                            .padding(4)
                    }
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

// MARK: - Scored Photos Loading View

struct ScoredPhotosLoadingView: View {
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                .scaleEffect(1.5)
            
            Text("Loading scored photos...")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Scored Photos Empty State View

struct ScoredPhotosEmptyStateView: View {
    let filter: ScoredPhotosView.ScoredPhotoFilter
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(filter.color)
                
                VStack(spacing: 6) {
                    Text(emptyStateTitle)
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text(emptyStateMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 40)
    }
    
    private var emptyStateTitle: String {
        switch filter {
        case .all:
            return "No Scored Photos"
        case .excellent:
            return "No Excellent Photos"
        case .good:
            return "No Good Photos"
        case .fair:
            return "No Fair Photos"
        case .needsWork:
            return "No Photos Need Work"
        case .unscored:
            return "All Photos Scored"
        }
    }
    
    private var emptyStateMessage: String {
        switch filter {
        case .all:
            return "Run photo analysis to see quality scores"
        case .excellent:
            return "No photos with excellent quality scores yet"
        case .good:
            return "No photos with good quality scores yet"
        case .fair:
            return "No photos with fair quality scores yet"
        case .needsWork:
            return "Great! No photos need improvement"
        case .unscored:
            return "All your photos have been analyzed"
        }
    }
}

// MARK: - Scored Photo Filter View

struct ScoredPhotoFilterView: View {
    @Binding var selectedFilter: ScoredPhotosView.ScoredPhotoFilter
    @ObservedObject var scoringViewModel: PhotoScoringViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ScoredPhotosView.ScoredPhotoFilter.allCases, id: \.self) { filter in
                        ScoredFilterRowView(
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
            .navigationTitle("Filter Scored Photos")
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
    
    private func getPhotoCount(for filter: ScoredPhotosView.ScoredPhotoFilter) -> Int {
        switch filter {
        case .all:
            return scoringViewModel.scoredPhotosCount
        case .excellent:
            return scoringViewModel.excellentPhotosCount
        case .good:
            return scoringViewModel.goodPhotosCount
        case .fair:
            return scoringViewModel.scoringStatistics?.fairPhotos ?? 0
        case .needsWork:
            return scoringViewModel.scoringStatistics?.poorPhotos ?? 0
        case .unscored:
            return scoringViewModel.unscoredPhotosCount
        }
    }
}

// MARK: - Scored Filter Row View

struct ScoredFilterRowView: View {
    let filter: ScoredPhotosView.ScoredPhotoFilter
    let selectedFilter: ScoredPhotosView.ScoredPhotoFilter
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
        HStack(spacing: 12) {
            Image(systemName: filter.systemImage)
                .foregroundColor(filter.color)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(filter.rawValue)
                    .font(.body)
                
                Text(filter.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
}

// MARK: - Preview

#Preview {
    ScoredPhotosView(photoViewModel: PhotoLibraryViewModel.preview)
}