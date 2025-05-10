//
//  ContentView.swift
//  VisionKitTool
//
//  Created by Jian Cheng on 2025/5/10.
//

import SwiftUI
import PhotosUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum SegmentationType: String, CaseIterable, Identifiable {
    case person = "Person"
    case object = "Object"
    
    var id: String { self.rawValue }
}

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var segmentedImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var segmentationType: SegmentationType = .person
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .cornerRadius(10)
                    }
                    
                    if let segmentedImage = segmentedImage {
                        Text("Segmentation Result")
                            .font(.headline)
                        
                        Image(uiImage: segmentedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .cornerRadius(10)
                    }
                    
                    if isProcessing {
                        ProgressView("Processing image...")
                    }
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Vision Segmentation")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: performSegmentation) {
                        Image(systemName: segmentationType == .person ? "person.crop.rectangle" : "cube")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .disabled(selectedImage == nil || isProcessing)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Segmentation Type", selection: $segmentationType) {
                        ForEach(SegmentationType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            .onChange(of: selectedItem) { newItem in
                loadTransferable(from: newItem)
            }
        }
    }
    
    private func loadTransferable(from item: PhotosPickerItem?) {
        segmentedImage = nil
        errorMessage = nil
        
        guard let item = item else {
            selectedImage = nil
            return
        }
        
        item.loadTransferable(type: Data.self) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let data = data, let uiImage = UIImage(data: data) {
                        self.selectedImage = uiImage
                    } else {
                        self.errorMessage = "Could not load image data"
                    }
                case .failure(let error):
                    self.errorMessage = "Error loading image: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func performSegmentation() {
        guard let selectedImage = selectedImage else { return }
        
        isProcessing = true
        errorMessage = nil
        
        // Process in background to keep UI responsive
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let segmentationResult: UIImage
                
                switch segmentationType {
                case .person:
                    segmentationResult = try segmentPersonFromImage(selectedImage)
                case .object:
                    segmentationResult = try segmentObjectFromImage(selectedImage)
                }
                
                DispatchQueue.main.async {
                    self.segmentedImage = segmentationResult
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Segmentation failed: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func segmentPersonFromImage(_ image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "VisionKitTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get CGImage from UIImage"])
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
            throw NSError(domain: "VisionKitTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "No segmentation mask generated"])
        }
        
        // Create a transparent background image
        let transparentImage = try createTransparentBackground(for: cgImage, using: mask)
        return transparentImage
    }
    
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
            throw NSError(domain: "VisionKitTool", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
        }
        
        // Draw the original image
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Lock the mask for reading
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        
        // Get the mask data
        guard let maskData = CVPixelBufferGetBaseAddress(mask) else {
            throw NSError(domain: "VisionKitTool", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to get mask data"])
        }
        
        // Get the context data
        guard let contextData = context.data else {
            throw NSError(domain: "VisionKitTool", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to get context data"])
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
            throw NSError(domain: "VisionKitTool", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to create result image"])
        }
        
        return UIImage(cgImage: resultCGImage)
    }
    
    private func segmentObjectFromImage(_ image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "VisionKitTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get CGImage from UIImage"])
        }
        
        // Create a request for object detection
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        
        // Create a request handler
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        // Get the saliency mask
        guard let results = request.results, !results.isEmpty,
              let salientObjects = results.first?.salientObjects,
              !salientObjects.isEmpty else {
            throw NSError(domain: "VisionKitTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "No salient objects detected"])
        }
        
        // Find the most salient object (highest confidence)
        guard let mostSalientObject = salientObjects.max(by: { $0.confidence < $1.confidence }) else {
            throw NSError(domain: "VisionKitTool", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not determine most salient object"])
        }
        
        // Create a mask from the bounding box
        let mask = try createMaskFromBoundingBox(mostSalientObject.boundingBox, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
        
        // Apply the mask to the original image
        return try applyMaskToImage(image: cgImage, mask: mask)
    }
    
    private func createMaskFromBoundingBox(_ boundingBox: CGRect, imageSize: CGSize) throws -> CVPixelBuffer {
        // Create a pixel buffer for the mask
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(imageSize.width),
                                         Int(imageSize.height),
                                         kCVPixelFormatType_OneComponent8,
                                         attrs,
                                         &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "VisionKitTool", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }
        
        // Lock the buffer for writing
        CVPixelBufferLockBaseAddress(buffer, .init(rawValue: 0))
        
        // Get a pointer to the pixel data
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))
            throw NSError(domain: "VisionKitTool", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to get pixel buffer base address"])
        }
        
        // Clear the buffer (set all pixels to 0)
        memset(baseAddress, 0, CVPixelBufferGetDataSize(buffer))
        
        // Convert normalized bounding box to pixel coordinates
        let x = Int(boundingBox.origin.x * imageSize.width)
        let y = Int((1 - boundingBox.origin.y - boundingBox.height) * imageSize.height) // Flip Y coordinate
        let width = Int(boundingBox.width * imageSize.width)
        let height = Int(boundingBox.height * imageSize.height)
        
        // Calculate row bytes (stride)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        // Fill the bounding box area with white (255)
        for row in max(0, y)..<min(Int(imageSize.height), y + height) {
            let rowStart = baseAddress.advanced(by: row * bytesPerRow)
            for col in max(0, x)..<min(Int(imageSize.width), x + width) {
                rowStart.advanced(by: col).storeBytes(of: UInt8(255), as: UInt8.self)
            }
        }
        
        // Unlock the buffer
        CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))
        
        return buffer
    }
    
    private func applyMaskToImage(image: CGImage, mask: CVPixelBuffer) throws -> UIImage {
        // Create CIImage from the input image
        let ciImage = CIImage(cgImage: image)
        
        // Create CIImage from the mask
        let ciMask = CIImage(cvPixelBuffer: mask)
        
        // Use a simpler approach with CIImage compositing
        // First, create a black background image
        let blackBackground = CIImage(color: .black).cropped(to: ciImage.extent)
        
        // Create a white background for the mask
        let whiteBackground = CIImage(color: .white).cropped(to: ciImage.extent)
        
        // Ensure the mask is properly sized
        let scaleX = CGFloat(image.width) / CGFloat(CVPixelBufferGetWidth(mask))
        let scaleY = CGFloat(image.height) / CGFloat(CVPixelBufferGetHeight(mask))
        let scaledMask = ciMask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Try a different approach using CISourceOverCompositing
        let context = CIContext(options: [.useSoftwareRenderer: false])
        
        // Use the mask to blend the image with a transparent background
        let filter = CIFilter.blendWithAlphaMask()
        filter.inputImage = ciImage
        filter.backgroundImage = blackBackground
        filter.maskImage = scaledMask
        
        guard let outputImage = filter.outputImage else {
            throw NSError(domain: "VisionKitTool", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to apply mask"])
        }
        
        // Create a CGImage from the CIImage
        do {
            guard let outputCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
                throw NSError(domain: "VisionKitTool", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create final image"])
            }
            
            return UIImage(cgImage: outputCGImage)
        } catch {
            // Fallback method if the first approach fails
            print("First approach failed, trying fallback method: \(error.localizedDescription)")
            
            // Try a simpler approach - just display the mask for debugging
            guard let maskCGImage = context.createCGImage(scaledMask, from: scaledMask.extent) else {
                throw NSError(domain: "VisionKitTool", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create mask image"])
            }
            
            return UIImage(cgImage: maskCGImage)
        }
    }
}

#Preview {
    ContentView()
}
