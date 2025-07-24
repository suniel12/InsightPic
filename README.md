# InsightPic - Smart Photo Curation

InsightPic is an iOS app that automatically curates your trip photos by identifying the best shots from hundreds of similar pictures. Instead of manually sorting through 100+ photos, get intelligently selected top 5-20 photos based on unique locations and quality scoring.

## Problem Statement

When traveling, people take multiple photos of the same pose/location to ensure at least one good shot. This results in:
- Hundreds of photos from a single trip
- Only 15-20 unique locations/contexts
- Time-consuming manual curation process
- Difficulty identifying the best shots

## Solution

InsightPic uses Apple's Vision Framework and Core ML to:
1. **Cluster similar photos** by location, time, and visual similarity
2. **Score photo quality** using technical metrics and face analysis
3. **Select the best photo** from each cluster
4. **Generate personalized recommendations** (top 5 overall, top 5 with specific people)

## Key Features

- **Smart Clustering**: Groups photos by location and visual similarity
- **Quality Scoring**: Analyzes sharpness, exposure, face quality, and composition
- **Person Recognition**: Creates personalized albums ("Top 5 with Sam")
- **Privacy First**: All processing happens on-device
- **Fast Processing**: Handle 100+ photos in seconds

## Technical Stack

- **iOS 16+** (Vision Framework, PhotoKit)
- **Swift 5.7+**
- **Vision Framework** for image analysis and feature extraction
- **PhotoKit** for photo library access
- **Core ML** for advanced quality scoring (optional)

## Architecture

### Phase 1: Core Clustering Engine
- Extract visual fingerprints using Vision Framework
- Group photos by time proximity and visual similarity
- Handle edge cases (indoor/outdoor transitions, lighting changes)

### Phase 2: Quality Scoring System
- **Technical Quality**: Sharpness, exposure, composition
- **Face Analysis**: Eye state, smile detection, face angle
- **Context Awareness**: Group photos vs. individual shots

### Phase 3: Smart Selection Algorithm
- Select best photo from each cluster
- Generate overall top recommendations
- Create person-specific albums

## Getting Started

### Prerequisites
- Xcode 14+
- iOS 16+ device or simulator
- Photo library with sample images

### Installation
```bash
git clone https://github.com/yourusername/InsightPic.git
cd InsightPic
open InsightPic.xcodeproj
```

### Development Setup
1. Enable photo library permissions in Info.plist
2. Add Vision and PhotoKit frameworks
3. Configure test photo library access
4. Run initial clustering tests

## Project Structure
```
InsightPic/
├── Core/
│   ├── PhotoClusterEngine.swift
│   ├── QualityAnalyzer.swift
│   └── SmartSelector.swift
├── Models/
│   ├── Photo.swift
│   ├── PhotoCluster.swift
│   └── Recommendations.swift
├── Views/
│   ├── PhotoLibraryView.swift
│   ├── RecommendationsView.swift
│   └── ClusterView.swift
└── Tests/
    ├── ClusteringTests.swift
    └── QualityTests.swift
```

## MVP Timeline
- **Week 1**: Basic clustering with Vision Framework
- **Week 2**: Quality scoring implementation
- **Week 3**: Smart recommendations and basic UI

## Contributing
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## License
MIT License - see LICENSE file for details

## Vision
Transform how people interact with their photo memories by making curation effortless and intelligent.