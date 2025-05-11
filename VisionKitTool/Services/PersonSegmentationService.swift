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
        // 保存原始图像的方向信息，以便后续使用
        let originalOrientation = image.imageOrientation
        
        // 将图像转换为标准方向（up）以便 Vision 框架处理
        // 这一步很重要，因为 Vision 框架在处理时可能会忽略方向信息
        let normalizedImage: UIImage
        if originalOrientation != .up {
            if let cgImage = image.cgImage {
                normalizedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
            } else {
                normalizedImage = image
            }
        } else {
            normalizedImage = image
        }
        
        guard let cgImage = normalizedImage.cgImage else {
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
        
        // 移除统计信息收集，提高效率
        
        // 创建透明背景图像
        let segmentedImage = try createTransparentBackground(for: cgImage, using: mask)
        
        // 将分割后的图像还原为原始图像的方向
        if let finalCGImage = segmentedImage.cgImage {
            return UIImage(cgImage: finalCGImage, scale: image.scale, orientation: originalOrientation)
        } else {
            return segmentedImage
        }
    }
    
    /// Creates a transparent background by applying the segmentation mask
    /// - Parameters:
    ///   - image: The original image
    ///   - mask: The segmentation mask
    /// - Returns: An image with transparent background where the mask indicates
    private func createTransparentBackground(for image: CGImage, using mask: CVPixelBuffer) throws -> UIImage {
        // 创建位图上下文，支持RGBA透明度
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        // 创建上下文时直接分配内存，减少内存分配次数
        let bufferSize = bytesPerRow * height
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() } // 确保内存在函数结束时被释放
        
        // 初始化内存为0（完全透明）
        buffer.initialize(repeating: 0, count: bufferSize)
        
        guard let context = CGContext(data: buffer,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw SegmentationError.graphicsContextCreationFailed
        }
        
        // 获取原始图像的像素数据
        guard let originalImageProvider = image.dataProvider,
              let originalImageData = originalImageProvider.data,
              let originalPixels = CFDataGetBytePtr(originalImageData) else {
            throw SegmentationError.invalidImage
        }
        
        // 锁定遮罩以便读取
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        
        // 获取遮罩数据
        guard let maskData = CVPixelBufferGetBaseAddress(mask) else {
            throw SegmentationError.maskDataAccessFailed
        }
        
        // 获取遮罩属性
        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let maskBytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        
        // 计算缩放因子（如果遮罩和图像尺寸不同）
        let scaleX = Double(width) / Double(maskWidth)
        let scaleY = Double(height) / Double(maskHeight)
        
        // 定义阈值常量
        let personThreshold: UInt8 = 128 // 人物阈值
        let highConfidenceThreshold: UInt8 = 220 // 高置信度阈值
        let edgeBlendFactor: Double = 1.5 // 边缘混合因子
        
        // 获取原始图像的每像素字节数和每行字节数
        let originalBytesPerPixel = image.bitsPerPixel / 8
        let originalBytesPerRow = image.bytesPerRow
        
        // 使用并行处理提高效率
        DispatchQueue.concurrentPerform(iterations: height) { y in
            for x in 0..<width {
                // 计算遮罩中的对应位置
                let maskX = Int(Double(x) / scaleX)
                let maskY = Int(Double(y) / scaleY)
                
                // 确保在遮罩边界内
                guard maskX >= 0 && maskX < maskWidth && maskY >= 0 && maskY < maskHeight else { continue }
                
                // 获取遮罩值（0-255，255表示人物，0表示背景）
                let maskOffset = maskY * maskBytesPerRow + maskX
                let maskValue = (maskData + maskOffset).load(as: UInt8.self)
                
                // 只处理人物区域（阈值以上的像素）
                if maskValue >= personThreshold {
                    // 计算原始图像中的像素位置
                    let originalOffset = y * originalBytesPerRow + x * originalBytesPerPixel
                    
                    // 计算目标上下文中的像素位置
                    let contextOffset = y * bytesPerRow + x * bytesPerPixel
                    
                    // 复制RGB通道（一次性复制以提高效率）
                    if originalBytesPerPixel >= 3 && bytesPerPixel >= 3 {
                        memcpy(buffer + contextOffset, originalPixels + originalOffset, 3)
                    }
                    
                    // 设置Alpha通道
                    if maskValue >= highConfidenceThreshold {
                        // 完全是人物区域 - 完全不透明
                        buffer[contextOffset + 3] = 255
                    } else {
                        // 边缘区域 - 应用平滑过渡
                        buffer[contextOffset + 3] = min(255, UInt8(Double(maskValue - personThreshold) * edgeBlendFactor))
                    }
                }
                // 如果maskValue < personThreshold，保持完全透明（背景区域）
            }
        }
        
        // Create an image from the context
        guard let resultCGImage = context.makeImage() else {
            throw SegmentationError.resultImageCreationFailed
        }
        
        // 创建最终结果图像，使用标准方向（up）
        // 在processPersonSegmentation方法中会将其还原为原始图像的方向
        return UIImage(cgImage: resultCGImage, scale: 1.0, orientation: .up)
    }
    

}
