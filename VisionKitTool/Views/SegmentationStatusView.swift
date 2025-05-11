//
//  SegmentationStatusView.swift
//  VisionKitTool
//
//  Created by Jian Cheng on 2025/5/10.
//

import SwiftUI

/// A view that displays the current status of the segmentation process
struct SegmentationStatusView: View {
    let state: SegmentationState
    
    var body: some View {
        Group {
            if state.isLoading {
                ProgressView("Processing image...")
                    .padding()
            } else if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SegmentationStatusView(state: .loading)
        SegmentationStatusView(state: .failure("An error occurred"))
        SegmentationStatusView(state: .idle)
    }
}
