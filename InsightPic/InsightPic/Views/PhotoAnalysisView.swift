import SwiftUI

struct PhotoAnalysisView: View {
    @StateObject private var analysisViewModel = PhotoAnalysisViewModel()
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSegment = 0
    @State private var showingAnalysisDetails = false
    @State private var selectedAnalysisResult: PhotoAnalysisResult?
    
    private let segments = ["Best Photos", "All Results", "Statistics"]
    
    var body: some View {
        NavigationView {
            VStack {
                if analysisViewModel.isAnalyzing {
                    AnalysisProgressView(viewModel: analysisViewModel)
                } else if analysisViewModel.analysisResults.isEmpty {
                    AnalysisStartView(analysisViewModel: analysisViewModel, photoViewModel: photoViewModel)
                } else {
                    VStack {
                        // Segmented control
                        Picker("View", selection: $selectedSegment) {
                            ForEach(0..<segments.count, id: \.self) { index in
                                Text(segments[index]).tag(index)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        // Content based on selected segment
                        TabView(selection: $selectedSegment) {
                            BestPhotosView(analysisViewModel: analysisViewModel, photoViewModel: photoViewModel)
                                .tag(0)
                            
                            AllResultsView(analysisViewModel: analysisViewModel, photoViewModel: photoViewModel)
                                .tag(1)
                            
                            StatisticsView(analysisViewModel: analysisViewModel)
                                .tag(2)
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    }
                }
            }
            .navigationTitle("Photo Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if !analysisViewModel.analysisResults.isEmpty && !analysisViewModel.isAnalyzing {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Re-analyze") {
                            Task {
                                await analysisViewModel.refreshAnalysis(for: photoViewModel.photos)
                            }
                        }
                    }
                }
            }
            .alert("Analysis Error", isPresented: .constant(analysisViewModel.errorMessage != nil)) {
                Button("OK") {
                    analysisViewModel.clearError()
                }
            } message: {
                Text(analysisViewModel.errorMessage ?? "")
            }
        }
    }
}

// MARK: - Analysis Progress View

struct AnalysisProgressView: View {
    @ObservedObject var viewModel: PhotoAnalysisViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .symbolEffect(.pulse, isActive: viewModel.isAnalyzing)
            
            VStack(spacing: 12) {
                Text("Analyzing Your Photos")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(viewModel.analysisText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 8) {
                ProgressView(value: viewModel.analysisProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 8)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                Text("\(Int(viewModel.analysisProgress * 100))% Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Analysis Start View

struct AnalysisStartView: View {
    let analysisViewModel: PhotoAnalysisViewModel
    let photoViewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text("Analyze Your Photos")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Use AI to analyze your \(photoViewModel.photos.count) photos and discover your best shots. We'll assess quality, composition, sharpness, and more.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                Task {
                    await analysisViewModel.analyzePhotos(photoViewModel.photos)
                }
            }) {
                Text("Start Analysis")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Best Photos View

struct BestPhotosView: View {
    @ObservedObject var analysisViewModel: PhotoAnalysisViewModel
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2),
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2),
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !analysisViewModel.bestPhotos.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top \(analysisViewModel.bestPhotos.count) Photos")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(analysisViewModel.bestPhotos, id: \.photoId) { result in
                                BestPhotoThumbnailView(result: result, photoViewModel: photoViewModel)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                
                // Similar photo groups
                if !analysisViewModel.similarPhotoGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Similar Photo Groups")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(Array(analysisViewModel.similarPhotoGroups.enumerated()), id: \.offset) { index, group in
                            SimilarPhotoGroupView(group: group, photoViewModel: photoViewModel, groupIndex: index)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Best Photo Thumbnail View

struct BestPhotoThumbnailView: View {
    let result: PhotoAnalysisResult
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if isLoading {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        }
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .cornerRadius(8)
            
            // Quality score badge
            VStack(spacing: 2) {
                Text(String(format: "%.0f", result.overallScore * 100))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("%")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(qualityColor(for: result.overallScore))
            )
            .padding(4)
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let photo = photoViewModel.photos.first(where: { $0.assetIdentifier == result.assetIdentifier }) else {
            isLoading = false
            return
        }
        
        Task {
            isLoading = true
            let image = await photoViewModel.loadThumbnail(for: photo)
            await MainActor.run {
                self.thumbnailImage = image
                self.isLoading = false
            }
        }
    }
    
    private func qualityColor(for score: Double) -> Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// MARK: - Similar Photo Group View

struct SimilarPhotoGroupView: View {
    let group: [PhotoAnalysisResult]
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    let groupIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group \(groupIndex + 1) (\(group.count) photos)")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group, id: \.photoId) { result in
                        BestPhotoThumbnailView(result: result, photoViewModel: photoViewModel)
                            .frame(width: 100, height: 100)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - All Results View

struct AllResultsView: View {
    @ObservedObject var analysisViewModel: PhotoAnalysisViewModel
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    var body: some View {
        List {
            ForEach(analysisViewModel.sortedByQuality(), id: \.photoId) { result in
                AnalysisResultRow(result: result, photoViewModel: photoViewModel)
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - Analysis Result Row

struct AnalysisResultRow: View {
    let result: PhotoAnalysisResult
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                }
            }
            .frame(width: 60, height: 60)
            .clipped()
            .cornerRadius(8)
            
            // Analysis details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.qualityDescription)
                        .font(.headline)
                        .foregroundColor(qualityColor(for: result.overallScore))
                    
                    Spacer()
                    
                    Text(String(format: "%.0f%%", result.overallScore * 100))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Label(String(format: "%.0f", result.sharpnessScore * 100), systemImage: "viewfinder")
                    Label(String(format: "%.0f", result.exposureScore * 100), systemImage: "sun.max")
                    if !result.faces.isEmpty {
                        Label("\(result.faces.count)", systemImage: "person.crop.circle")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if !result.primaryIssues.isEmpty {
                    Text(result.primaryIssues.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let photo = photoViewModel.photos.first(where: { $0.assetIdentifier == result.assetIdentifier }) else {
            return
        }
        
        Task {
            let image = await photoViewModel.loadThumbnail(for: photo)
            await MainActor.run {
                self.thumbnailImage = image
            }
        }
    }
    
    private func qualityColor(for score: Double) -> Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// MARK: - Statistics View

struct StatisticsView: View {
    @ObservedObject var analysisViewModel: PhotoAnalysisViewModel
    
    var body: some View {
        List {
            Section("Overall Statistics") {
                StatRow(title: "Total Analyzed", value: "\(analysisViewModel.totalAnalyzedPhotos)")
                StatRow(title: "Average Quality", value: String(format: "%.1f%%", analysisViewModel.averageQualityScore * 100))
                StatRow(title: "Photos with Faces", value: "\(analysisViewModel.photosWithFaces)")
            }
            
            Section("Quality Distribution") {
                ForEach(Array(analysisViewModel.qualityDistribution.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                    StatRow(title: key, value: "\(value) photos")
                }
            }
            
            Section("Best Photos") {
                StatRow(title: "Excellent (80%+)", value: "\(analysisViewModel.excellentPhotosCount)")
                StatRow(title: "Good (60-80%)", value: "\(analysisViewModel.goodPhotosCount)")
                StatRow(title: "Needs Improvement (<40%)", value: "\(analysisViewModel.poorPhotosCount)")
            }
        }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoAnalysisView(photoViewModel: PhotoLibraryViewModel.preview)
}