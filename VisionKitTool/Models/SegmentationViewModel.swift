//
//  SegmentationViewModel.swift
//  VisionKitTool
//
//  Created by Jian Cheng on 2025/5/10.
//

import Foundation
import UIKit
import Combine
import SwiftUI
import PhotosUI

/// ViewModel that manages the segmentation process and state
class SegmentationViewModel: ObservableObject {
    // Published properties for UI updates
    @Published var originalImage: UIImage?
    @Published var segmentationState: SegmentationState = .idle
    
    // Dependencies
    private let segmentationService: PersonSegmentationServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(segmentationService: PersonSegmentationServiceProtocol = PersonSegmentationService()) {
        self.segmentationService = segmentationService
    }
    
    /// Loads an image from a PhotosPickerItem
    func loadImage(from item: PhotosUI.PhotosPickerItem?) {
        // Reset the state when a new image is loaded
        segmentationState = .idle
        
        guard let item = item else {
            originalImage = nil
            return
        }
        
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    if let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            self.originalImage = uiImage
                        }
                    } else {
                        await MainActor.run {
                            self.segmentationState = .failure("Could not load image data")
                        }
                    }
                } else {
                    await MainActor.run {
                        self.segmentationState = .failure("Could not load image data")
                    }
                }
            } catch {
                await MainActor.run {
                    self.segmentationState = .failure("Error loading image: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Performs person segmentation on the current image
    func performPersonSegmentation() {
        guard let image = originalImage else {
            segmentationState = .failure("No image selected")
            return
        }
        
        segmentationState = .loading
        
        Task {
            do {
                let result = try await segmentationService.segmentPerson(from: image)
                await MainActor.run {
                    segmentationState = .success(result)
                }
            } catch {
                await MainActor.run {
                    segmentationState = .failure("Segmentation failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Clears the current state
    func reset() {
        originalImage = nil
        segmentationState = .idle
    }
}
