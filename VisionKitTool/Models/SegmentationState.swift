//
//  SegmentationState.swift
//  VisionKitTool
//
//  Created by Jian Cheng on 2025/5/10.
//

import Foundation
import UIKit

/// Represents the current state of the segmentation process
enum SegmentationState: Equatable {
    case idle
    case loading
    case success(UIImage)
    case failure(String)
    
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
    
    var resultImage: UIImage? {
        if case .success(let image) = self {
            return image
        }
        return nil
    }
    
    var errorMessage: String? {
        if case .failure(let message) = self {
            return message
        }
        return nil
    }
}
