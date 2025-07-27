import SwiftUI

struct PerfectMomentGeneratorView: View {
    let cluster: PhotoCluster
    @StateObject private var viewModel = PerfectMomentViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingPerfectMomentGenerator = false
    
    var body: some View {
        ZStack {
            // Background - Edge to Edge
            Color(.systemGroupedBackground)
                .ignoresSafeArea(.all)
            
            // Main Content
            VStack(spacing: 0) {
                // Content Area
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Section
                        VStack(spacing: 16) {
                            // Icon
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "sparkles")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundStyle(Color.purple)
                            }
                            
                            // Title and description
                            VStack(spacing: 8) {
                                Text("Create Perfect Moment")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                
                                Text("Combine the best expressions from \(cluster.photos.count) similar photos to create a flawless memory")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                            }
                        }
                        .padding(.top, 40)
                        
                        // Progress or Result Content
                        if viewModel.isGenerating {
                            PerfectMomentProgressView(viewModel: viewModel)
                        } else if let result = viewModel.currentResult {
                            PerfectMomentResultView(result: result, viewModel: viewModel)
                        } else if let error = viewModel.errorMessage {
                            PerfectMomentErrorView(message: error) {
                                viewModel.errorMessage = nil
                            }
                        } else {
                            // Initial state - show cluster preview
                            ClusterImprovementPreviewView(cluster: cluster)
                        }
                        
                        Spacer(minLength: 100) // Space for floating action button
                    }
                    .padding(.horizontal, 24)
                }
            }
            
            // Floating Glass Navigation
            VStack {
                // Top Navigation
                HStack {
                    Spacer()
                    
                    // Glass Done button
                    GlassDoneButton(action: { dismiss() })
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Spacer()
                
                // Bottom Action Area
                if !viewModel.isGenerating && viewModel.currentResult == nil && viewModel.errorMessage == nil {
                    VStack(spacing: 16) {
                        // Generate Perfect Moment Button
                        if cluster.perfectMomentEligibility.isEligible {
                            GlassPerfectMomentButton {
                                Task {
                                    await viewModel.generatePerfectMoment(from: cluster)
                                }
                            }
                        } else {
                            // Not eligible message
                            VStack(spacing: 8) {
                                Text("Perfect Moment Not Available")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                
                                Text(cluster.perfectMomentEligibility.reason.userMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 32)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Progress View

struct PerfectMomentProgressView: View {
    @ObservedObject var viewModel: PerfectMomentViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.purple)
                    .symbolEffect(.pulse, isActive: viewModel.isGenerating)
            }
            
            VStack(spacing: 16) {
                Text("Creating Perfect Moment")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(viewModel.progressText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color.purple))
                        .frame(maxWidth: 280)
                        .scaleEffect(y: 1.5)
                    
                    Text("\(Int(viewModel.progress * 100))% Complete")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Error View

struct PerfectMomentErrorView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.red)
            }
            
            VStack(spacing: 12) {
                Text("Unable to Create Perfect Moment")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Try Again") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Cluster Improvement Preview

struct ClusterImprovementPreviewView: View {
    let cluster: PhotoCluster
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 4)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Preview photos grid
            VStack(spacing: 12) {
                HStack {
                    Text("Photos in this cluster")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text("\(cluster.photos.count) photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .cornerRadius(8)
                }
                
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(cluster.photos.prefix(9)), id: \.id) { photo in
                        ClusterPhotoThumbnailView(photo: photo)
                    }
                    
                    if cluster.photos.count > 9 {
                        VStack {
                            Text("+\(cluster.photos.count - 9)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 80, height: 80)
                        .background(.quaternary)
                        .cornerRadius(8)
                    }
                }
            }
            
            // Improvement opportunities
            if cluster.perfectMomentEligibility.isEligible {
                VStack(spacing: 12) {
                    HStack {
                        Text("Potential Improvements")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    
                    LazyVStack(spacing: 8) {
                        ForEach(cluster.perfectMomentEligibility.estimatedImprovements, id: \.personID) { improvement in
                            ImprovementOpportunityRow(improvement: improvement)
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(.regularMaterial)
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - Supporting Views

struct ClusterPhotoThumbnailView: View {
    let photo: Photo
    @State private var thumbnailImage: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.6)
                            .foregroundStyle(.secondary)
                    }
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 14))
                    }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(width: 80, height: 80)
        .clipped()
        .cornerRadius(8)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        Task {
            isLoading = true
            // This would use PhotoLibraryViewModel.loadThumbnail in real implementation
            // For now, simulate loading
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

struct ImprovementOpportunityRow: View {
    let improvement: PersonImprovement
    
    var body: some View {
        HStack(spacing: 12) {
            // Issue icon - using the improvement type description
            Image(systemName: iconForImprovementType(improvement.improvementType))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 24, height: 24)
            
            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text(improvement.improvementType.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Better option available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Confidence indicator
            Circle()
                .fill(confidenceColor(improvement.confidence))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 8)
    }
    
    private func iconForImprovementType(_ type: ImprovementType) -> String {
        switch type {
        case .eyesClosed:
            return "eye"
        case .poorExpression:
            return "face.smiling"
        case .awkwardPose:
            return "figure.stand"
        case .blurredFace:
            return "camera.aperture"
        case .unflatteringAngle:
            return "rotate.3d"
        }
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Glass Perfect Moment Button

struct GlassPerfectMomentButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                
                Text("Create Perfect Moment")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                ZStack {
                    // Main colored background with glass effect
                    RoundedRectangle(cornerRadius: 28)
                        .fill(.thinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.purple)
                        )
                    
                    // Glass overlay effect
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .white.opacity(0.3),
                                    .clear,
                                    .black.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Subtle border
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                }
            )
            .shadow(color: .purple.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Extensions for FaceIssue (from PerfectMomentAnalysis)

extension FaceIssue {
    var icon: String {
        switch self {
        case .eyesClosed:
            return "eye.slash"
        case .poorExpression:
            return "face.dashed"
        case .awkwardPose:
            return "person.crop.circle.badge.xmark"
        case .blurredFace:
            return "camera.aperture"
        case .unflatteringAngle:
            return "rotate.3d"
        case .none:
            return "checkmark.circle"
        }
    }
    
    var description: String {
        switch self {
        case .eyesClosed:
            return "Eyes closed"
        case .poorExpression:
            return "Poor expression"
        case .awkwardPose:
            return "Awkward pose"
        case .blurredFace:
            return "Blurry face"
        case .unflatteringAngle:
            return "Unflattering angle"
        case .none:
            return "No issues detected"
        }
    }
    
}

// MARK: - Preview

#Preview {
    PerfectMomentGeneratorView(cluster: PhotoCluster.preview)
}

// MARK: - Preview Extensions

extension PhotoCluster {
    static var preview: PhotoCluster {
        // This should be replaced with actual preview data
        var cluster = PhotoCluster()
        cluster.photos = []
        return cluster
    }
}