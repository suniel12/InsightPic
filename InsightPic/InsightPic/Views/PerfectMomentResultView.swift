import SwiftUI

struct PerfectMomentResultView: View {
    let result: PerfectMomentResult
    @ObservedObject var viewModel: PerfectMomentViewModel
    @State private var showingShareSheet = false
    @State private var showingComparison = false
    
    // US3.4: Quality validation check
    private var isQualityInsufficient: Bool {
        result.qualityMetrics.overallQuality < 0.6
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Main Result Display
            VStack(spacing: 16) {
                // Generated Perfect Moment
                VStack(spacing: 8) {
                    Text("Your Perfect Moment")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Image(uiImage: result.perfectMoment)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple, lineWidth: 2)
                        )
                        .shadow(color: .purple.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                
                // Comparison Toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingComparison.toggle()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: showingComparison ? "eye.slash" : "eye")
                            .font(.system(size: 14, weight: .medium))
                        
                        Text(showingComparison ? "Hide Comparison" : "Compare with Original")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.purple.opacity(0.1))
                    .cornerRadius(20)
                }
                
                // Before/After Comparison (when toggled)
                if showingComparison {
                    BeforeAfterComparisonView(result: result)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            
            // Improvements Summary
            ImprovementsSummaryView(improvements: result.improvements)
            
            // Quality Metrics
            QualityMetricsView(metrics: result.qualityMetrics)
            
            // Quality Validation Warning (US3.4)
            if isQualityInsufficient {
                QualityWarningView(result: result, onUseOriginal: {
                    viewModel.useOriginalPhoto(result.originalPhoto)
                })
            }
            
            // Action Buttons
            VStack(spacing: 12) {
                // Primary Actions
                HStack(spacing: 12) {
                    // Save Button
                    Button(action: {
                        Task {
                            await viewModel.savePerfectMoment(result)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Text("Save to Photos")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.thinMaterial)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(Color.green)
                                    )
                                
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                            }
                        )
                        .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .disabled(viewModel.isSaving)
                    
                    // Share Button
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Text("Share")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.thinMaterial)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(Color.blue)
                                    )
                                
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                            }
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                }
                
                // Processing Time
                Text("Generated in \(String(format: "%.1f", result.processingTime))s")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingShareSheet) {
            // Use ActivityViewController for all iOS versions for simplicity
            ActivityViewController(activityItems: [result.perfectMoment])
        }
    }
}

// MARK: - Before/After Comparison

struct BeforeAfterComparisonView: View {
    let result: PerfectMomentResult
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Before & After Comparison")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                // Original
                VStack(spacing: 6) {
                    Text("Original")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Note: In actual implementation, would use PhotoLibraryViewModel.loadThumbnail
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 140, height: 140)
                        .cornerRadius(8)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                }
                
                // Arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.purple)
                
                // Perfect Moment
                VStack(spacing: 6) {
                    Text("Perfect Moment")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .fontWeight(.medium)
                    
                    Image(uiImage: result.perfectMoment)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 140, maxHeight: 140)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.purple, lineWidth: 1.5)
                        )
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Improvements Summary

struct ImprovementsSummaryView: View {
    let improvements: [PersonImprovement]
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Improvements Made")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(improvements.count) people")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(8)
            }
            
            if improvements.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    
                    Text("No improvements needed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("This photo was already perfect!")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(improvements, id: \.personID) { improvement in
                        ImprovementDetailRow(improvement: improvement)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct ImprovementDetailRow: View {
    let improvement: PersonImprovement
    
    var body: some View {
        HStack(spacing: 12) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.green)
            
            // Improvement description
            VStack(alignment: .leading, spacing: 2) {
                Text(improvement.improvementType.description)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Person \(improvement.personID.prefix(8))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Confidence indicator
            ConfidenceBadge(confidence: improvement.confidence)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Quality Metrics

struct QualityMetricsView: View {
    let metrics: CompositeQualityMetrics
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quality Assessment")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                OverallQualityBadge(quality: metrics.overallQuality)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QualityMetricItem(
                    title: "Blending",
                    value: metrics.blendingQuality,
                    icon: "paintbrush.pointed"
                )
                
                QualityMetricItem(
                    title: "Lighting",
                    value: metrics.lightingConsistency,
                    icon: "lightbulb"
                )
                
                QualityMetricItem(
                    title: "Naturalness",
                    value: metrics.naturalness,
                    icon: "leaf"
                )
                
                QualityMetricItem(
                    title: "Edge Quality",
                    value: 1.0 - metrics.edgeArtifacts,
                    icon: "scissors"
                )
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

struct QualityMetricItem: View {
    let title: String
    let value: Float
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(qualityColor(value))
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            
            Text("\(Int(value * 100))%")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(qualityColor(value))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(qualityColor(value).opacity(0.1))
        .cornerRadius(8)
    }
    
    private func qualityColor(_ value: Float) -> Color {
        if value > 0.8 {
            return .green
        } else if value > 0.6 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Quality Warning View (US3.4)

struct QualityWarningView: View {
    let result: PerfectMomentResult
    let onUseOriginal: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quality Warning")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text("The generated photo quality may not meet your expectations. You can use the original photo instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                Button("Use Original Photo") {
                    onUseOriginal()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
                
                Text("Quality: \(Int(result.qualityMetrics.overallQuality * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Supporting Views

struct ConfidenceBadge: View {
    let confidence: Float
    
    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor(confidence))
            .cornerRadius(6)
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.6 {
            return .orange
        } else {
            return .red
        }
    }
}

struct OverallQualityBadge: View {
    let quality: Float
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: quality > 0.8 ? "star.fill" : quality > 0.6 ? "star.leadinghalf.filled" : "star")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(qualityColor(quality))
            
            Text(qualityLabel(quality))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(qualityColor(quality))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(qualityColor(quality).opacity(0.1))
        .cornerRadius(8)
    }
    
    private func qualityColor(_ quality: Float) -> Color {
        if quality > 0.8 {
            return .green
        } else if quality > 0.6 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func qualityLabel(_ quality: Float) -> String {
        if quality > 0.9 {
            return "Excellent"
        } else if quality > 0.8 {
            return "Very Good"
        } else if quality > 0.6 {
            return "Good"
        } else if quality > 0.4 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
}

// MARK: - iOS 15 Compatibility

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Missing Type Extensions

// MARK: - Placeholder Types

// Note: PerfectMomentResult and CompositeQualityMetrics are defined in PerfectMomentGenerationService.swift

// MARK: - Preview

#Preview {
    PerfectMomentResultView(
        result: PerfectMomentResult(
            originalPhoto: Photo.preview,
            perfectMoment: UIImage(systemName: "photo") ?? UIImage(),
            improvements: [
                PersonImprovement(
                    personID: "person1",
                    sourcePhotoId: UUID(),
                    improvementType: .eyesClosed,
                    confidence: 0.9
                ),
                PersonImprovement(
                    personID: "person2",
                    sourcePhotoId: UUID(),
                    improvementType: .poorExpression,
                    confidence: 0.8
                )
            ],
            qualityMetrics: CompositeQualityMetrics(
                overallQuality: 0.85,
                blendingQuality: 0.9,
                lightingConsistency: 0.8,
                edgeArtifacts: 0.1,
                naturalness: 0.85
            ),
            processingTime: 12.5
        ),
        viewModel: PerfectMomentViewModel()
    )
}

extension Photo {
    static var preview: Photo {
        // This should be replaced with actual preview data
        return Photo(
            assetIdentifier: "preview",
            timestamp: Date(),
            location: nil,
            metadata: PhotoMetadata(width: 1920, height: 1080)
        )
    }
}