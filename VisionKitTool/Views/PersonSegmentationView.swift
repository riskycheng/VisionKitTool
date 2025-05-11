//
//  PersonSegmentationView.swift
//  VisionKitTool
//
//  Created by Jian Cheng on 2025/5/10.
//

import SwiftUI
import PhotosUI

/// The main view for person segmentation functionality
struct PersonSegmentationView: View {
    @StateObject private var viewModel = SegmentationViewModel()
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Original image display
                    if let originalImage = viewModel.originalImage {
                        ImageDisplayView(
                            image: originalImage,
                            title: "Original Image"
                        )
                    }
                    
                    // Segmented image display
                    if let resultImage = viewModel.segmentationState.resultImage {
                        ImageDisplayView(
                            image: resultImage,
                            title: "Segmentation Result"
                        )
                    }
                    
                    // Status display (loading/error)
                    SegmentationStatusView(state: viewModel.segmentationState)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Person Segmentation")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: viewModel.performPersonSegmentation) {
                        Image(systemName: "person.crop.rectangle")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .disabled(viewModel.originalImage == nil || viewModel.segmentationState.isLoading)
                }
            }
            .onChange(of: selectedItem) { newItem in
                viewModel.loadImage(from: newItem)
            }
        }
    }
}

#Preview {
    PersonSegmentationView()
}
