import SwiftUI

struct PhotoScoringView: View {
    @StateObject private var viewModel = PhotoScoringViewModel()
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedQualityFilter: QualityFilter = .all
    @State private var showingQualityBreakdown = false
    @State private var showingRecommendations = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Section
                    ScoringHeaderView(viewModel: viewModel)
                    
                    // Progress Section (when scoring)
                    if viewModel.isScoring {
                        ScoringProgressView(viewModel: viewModel)
                    }
                    
                    // Statistics Section
                    if viewModel.scoringStatistics != nil {
                        ScoringStatisticsView(viewModel: viewModel)
                    }
                    
                    // Actions Section
                    ScoringActionsView(viewModel: viewModel, photoViewModel: photoViewModel)
                    
                    // Quality Distribution
                    if !viewModel.qualityDistribution.isEmpty {
                        QualityDistributionView(viewModel: viewModel)
                    }
                    
                    // Recommendations
                    if !viewModel.getQualityRecommendations().isEmpty {
                        RecommendationsView(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .navigationTitle("Photo Quality Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("Options") {
                        Button("View Quality Breakdown") {
                            showingQualityBreakdown = true
                        }
                        
                        Button("View Recommendations") {
                            showingRecommendations = true
                        }
                        
                        Button("Rescore Low Quality Photos") {
                            Task {
                                await viewModel.rescoreLowQualityPhotos()
                            }
                        }
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $showingQualityBreakdown) {
                QualityBreakdownView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingRecommendations) {
                RecommendationsDetailView(viewModel: viewModel)
            }
            .task {
                await viewModel.generateStatistics()
            }
        }
    }
}

// MARK: - Scoring Header View

struct ScoringHeaderView: View {
    @ObservedObject var viewModel: PhotoScoringViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("Photo Quality Analysis")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let stats = viewModel.scoringStatistics {
                Text("Grade: \(stats.qualityGrade) • Average Score: \(String(format: "%.1f", stats.averageScore * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Scoring Progress View

struct ScoringProgressView: View {
    @ObservedObject var viewModel: PhotoScoringViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: viewModel.scoringProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(height: 8)
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            Text(viewModel.scoringText)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            if viewModel.scoringProgress > 0 {
                Text("\(Int(viewModel.scoringProgress * 100))% Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Scoring Statistics View

struct ScoringStatisticsView: View {
    @ObservedObject var viewModel: PhotoScoringViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Quality Overview")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatisticCard(
                    title: "Total Photos",
                    value: "\(viewModel.totalPhotosCount)",
                    icon: "photo.on.rectangle",
                    color: .blue
                )
                
                StatisticCard(
                    title: "Analyzed",
                    value: "\(viewModel.scoredPhotosCount)",
                    subtitle: "\(Int(viewModel.scoreCompletionPercentage))% complete",
                    icon: "checkmark.circle",
                    color: .green
                )
                
                StatisticCard(
                    title: "Excellent",
                    value: "\(viewModel.excellentPhotosCount)",
                    icon: "star.fill",
                    color: .yellow
                )
                
                StatisticCard(
                    title: "Need Review",
                    value: "\(viewModel.photosNeedingImprovementCount)",
                    icon: "exclamationmark.triangle",
                    color: .orange
                )
            }
        }
    }
}

// MARK: - Statistic Card

struct StatisticCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let color: Color
    
    init(title: String, value: String, subtitle: String? = nil, icon: String, color: Color) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Scoring Actions View

struct ScoringActionsView: View {
    @ObservedObject var viewModel: PhotoScoringViewModel
    @ObservedObject var photoViewModel: PhotoLibraryViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Actions")
                .font(.headline)
            
            VStack(spacing: 8) {
                Button(action: {
                    Task {
                        await viewModel.scoreAllPhotos()
                    }
                }) {
                    Label("Analyze All Photos", systemImage: "wand.and.rays")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isScoring || viewModel.unscoredPhotosCount == 0)
                
                Button(action: {
                    Task {
                        await viewModel.scoreSelectedPhotos(photoViewModel.photos)
                    }
                }) {
                    Label("Rescore Current Photos", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isScoring || photoViewModel.photos.isEmpty)
                
                if viewModel.unscoredPhotosCount > 0 {
                    Text("\(viewModel.unscoredPhotosCount) photos need analysis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Quality Distribution View

struct QualityDistributionView: View {
    @ObservedObject var viewModel: PhotoScoringViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Quality Distribution")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(Array(viewModel.qualityDistribution.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                    HStack {
                        Text(key)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text("\(value)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - Recommendations View

struct RecommendationsView: View {
    @ObservedObject var viewModel: PhotoScoringViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Recommendations")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(viewModel.getQualityRecommendations(), id: \.self) { recommendation in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        
                        Text(recommendation)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - Quality Breakdown View

struct QualityBreakdownView: View {
    @ObservedObject var viewModel: PhotoScoringViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Top Quality Photos
                    if !viewModel.topQualityPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Quality Photos")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(viewModel.topQualityPhotos.prefix(10)) { photo in
                                        VStack {
                                            AsyncImage(url: URL(string: photo.assetIdentifier)) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle()
                                                    .fill(Color.gray.opacity(0.3))
                                            }
                                            .frame(width: 80, height: 80)
                                            .clipped()
                                            .cornerRadius(8)
                                            
                                            if let score = photo.overallScore {
                                                Text("\(Int(score.overall * 100))%")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Photos Needing Improvement
                    if !viewModel.photosNeedingImprovement.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Photos Needing Improvement")
                                .font(.headline)
                            
                            ForEach(Array(viewModel.photosNeedingImprovement.prefix(5).enumerated()), id: \.offset) { index, item in
                                let (photo, issues) = item
                                
                                HStack {
                                    AsyncImage(url: URL(string: photo.assetIdentifier)) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                    }
                                    .frame(width: 60, height: 60)
                                    .clipped()
                                    .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        if let score = photo.overallScore {
                                            Text("Score: \(Int(score.overall * 100))%")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                        }
                                        
                                        Text("Issues: \(issues.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Quality Breakdown")
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
}

// MARK: - Recommendations Detail View

struct RecommendationsDetailView: View {
    @ObservedObject var viewModel: PhotoScoringViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(viewModel.getQualityRecommendations(), id: \.self) { recommendation in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.title3)
                            
                            Text(recommendation)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Recommendations")
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
}

// MARK: - Quality Filter Enum

enum QualityFilter: String, CaseIterable {
    case all = "All Photos"
    case excellent = "Excellent (80%+)"
    case good = "Good (60-80%)"
    case fair = "Fair (40-60%)"
    case poor = "Poor (<40%)"
    case unscored = "Unscored"
}

// MARK: - Preview

#Preview {
    PhotoScoringView(photoViewModel: PhotoLibraryViewModel.preview)
}