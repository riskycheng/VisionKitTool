//
//  PersonSegmentationService.swift
//  VisionKitTool
//
//  Created by Jian Cheng on 2025/5/10.
//

import Foundation
import UIKit
import Vision
import CoreImage

/// Protocol defining the contract for person segmentation services
protocol PersonSegmentationServiceProtocol {
    /// Segments a person from the provided image
    /// - Parameter image: The source image containing a person
    /// - Returns: A new image with the person segmented (transparent background)
    func segmentPerson(from image: UIImage) async throws -> UIImage
}

/// Service responsible for person segmentation using Vision framework
class PersonSegmentationService: PersonSegmentationServiceProtocol {
    
    enum SegmentationError: Error, LocalizedError {
        case invalidImage
        case noSegmentationMask
        case graphicsContextCreationFailed
        case maskDataAccessFailed
        case contextDataAccessFailed
        case resultImageCreationFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Could not get CGImage from UIImage"
            case .noSegmentationMask:
                return "No segmentation mask generated"
            case .graphicsContextCreationFailed:
                return "Failed to create graphics context"
            case .maskDataAccessFailed:
                return "Failed to get mask data"
            case .contextDataAccessFailed:
                return "Failed to get context data"
            case .resultImageCreationFailed:
                return "Failed to create result image"
            }
        }
    }
    
    /// Segments a person from the provided image
    /// - Parameter image: The source image containing a person
    /// - Returns: A new image with the person segmented (transparent background)
    func segmentPerson(from image: UIImage) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try self.processPersonSegmentation(image)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Processes the person segmentation request
    /// - Parameter image: The source image containing a person
    /// - Returns: A new image with the person segmented (transparent background)
    private func processPersonSegmentation(_ image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw SegmentationError.invalidImage
        }
        
        // Create a request to segment persons in the image with higher quality
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate // Use accurate for better results
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        
        // Create a request handler
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        // Get the segmentation mask
        guard let mask = request.results?.first?.pixelBuffer else {
            throw SegmentationError.noSegmentationMask
        }
        
        // Create a transparent background image
        return try createTransparentBackground(for: cgImage, using: mask)
    }
    
    /// Creates a transparent background by applying the segmentation mask
    /// - Parameters:
    ///   - image: The original image
    ///   - mask: The segmentation mask
    /// - Returns: An image with transparent background where the mask indicates
    private func createTransparentBackground(for image: CGImage, using mask: CVPixelBuffer) throws -> UIImage {
        // Create a bitmap context with RGBA to support transparency
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw SegmentationError.graphicsContextCreationFailed
        }
        
        // Clear the context to transparent
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw the original image
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Lock the mask for reading
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        
        // Get the mask data
        guard let maskData = CVPixelBufferGetBaseAddress(mask) else {
            throw SegmentationError.maskDataAccessFailed
        }
        
        // Get the context data
        guard let contextData = context.data else {
            throw SegmentationError.contextDataAccessFailed
        }
        
        // Get mask properties
        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let maskBytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        
        // Calculate scaling factors if mask and image have different dimensions
        let scaleX = Double(width) / Double(maskWidth)
        let scaleY = Double(height) / Double(maskHeight)
        
        // Apply the mask to the image data
        for y in 0..<height {
            for x in 0..<width {
                // Calculate the corresponding position in the mask
                let maskX = Int(Double(x) / scaleX)
                let maskY = Int(Double(y) / scaleY)
                
                // Ensure we're within mask bounds
                guard maskX >= 0 && maskX < maskWidth && maskY >= 0 && maskY < maskHeight else { continue }
                
                // Get the mask value (0-255, where 255 is person, 0 is background)
                let maskOffset = maskY * maskBytesPerRow + maskX
                let maskValue = (maskData + maskOffset).load(as: UInt8.self)
                
                // Skip if this isn't part of a person (adjust threshold as needed)
                if maskValue < 200 { // Higher threshold for cleaner cutout
                    // Calculate position in the context data
                    let contextOffset = y * bytesPerRow + x * bytesPerPixel
                    
                    // Set alpha to 0 (transparent) for background
                    (contextData + contextOffset + 3).storeBytes(of: UInt8(0), as: UInt8.self)
                }
            }
        }
        
        // Create an image from the context
        guard let resultCGImage = context.makeImage() else {
            throw SegmentationError.resultImageCreationFailed
        }
        
        // Create a UIImage with the same orientation as the original
        let originalUIImage = UIImage(cgImage: image)
        return UIImage(cgImage: resultCGImage, scale: originalUIImage.scale, orientation: originalUIImage.imageOrientation)
    }
}
