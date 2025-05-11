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
    
    /// 获取分割遮罩的详细信息
    /// - Parameter mask: 分割遮罩的像素缓冲区
    /// - Returns: 包含遮罩统计信息的字典
    private func getMaskStatistics(from mask: CVPixelBuffer) -> [String: Any] {
        // 锁定遮罩以便读取
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        
        guard let maskData = CVPixelBufferGetBaseAddress(mask) else {
            return ["error": "无法访问遮罩数据"]
        }
        
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        
        var pixelCounts = [Int: Int]() // 值: 数量
        var totalPixels = 0
        var personPixels = 0
        var backgroundPixels = 0
        var edgePixels = 0
        
        // 分析遮罩中的像素值分布
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x
                let value = Int((maskData + offset).load(as: UInt8.self))
                
                pixelCounts[value, default: 0] += 1
                totalPixels += 1
                
                if value < 64 {
                    backgroundPixels += 1
                } else if value > 192 {
                    personPixels += 1
                } else {
                    edgePixels += 1
                }
            }
        }
        
        // 找出最常见的前5个值
        let topValues = pixelCounts.sorted { $0.value > $1.value }.prefix(5)
        
        return [
            "dimensions": "\(width)x\(height)",
            "totalPixels": totalPixels,
            "personPixels": personPixels,
            "personPercentage": Double(personPixels) / Double(totalPixels) * 100,
            "backgroundPixels": backgroundPixels,
            "backgroundPercentage": Double(backgroundPixels) / Double(totalPixels) * 100,
            "edgePixels": edgePixels,
            "edgePercentage": Double(edgePixels) / Double(totalPixels) * 100,
            "topValues": topValues.map { "值\($0.key): \($0.value)像素 (\(Double($0.value) / Double(totalPixels) * 100)%)" }
        ]
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
        
        // 打印遮罩统计信息（可选，用于调试）
        let maskStats = getMaskStatistics(from: mask)
        print("人物分割遮罩统计信息: \(maskStats)")
        
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
        
        // Clear the context to transparent - 创建一个完全透明的背景
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // 获取原始图像的像素数据
        guard let originalImageProvider = image.dataProvider,
              let originalImageData = originalImageProvider.data,
              let originalPixels = CFDataGetBytePtr(originalImageData) else {
            throw SegmentationError.invalidImage
        }
        
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
        
        // 定义阈值常量，可以根据需要调整
        let personThreshold: UInt8 = 128 // 人物阈值，大于此值的被视为人物
        let edgeBlendFactor: Double = 1.5 // 边缘混合因子，用于平滑边缘
        
        // 获取原始图像的每像素字节数和每行字节数
        let originalBytesPerPixel = image.bitsPerPixel / 8
        let originalBytesPerRow = image.bytesPerRow
        
        // 只复制那些被确定为人物的像素
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
                
                // 计算原始图像中的像素位置
                let originalOffset = y * originalBytesPerRow + x * originalBytesPerPixel
                
                // 计算目标上下文中的像素位置
                let contextOffset = y * bytesPerRow + x * bytesPerPixel
                
                if maskValue >= personThreshold {
                    // 这是人物区域 - 从原始图像复制像素
                    // 复制RGB通道
                    for i in 0..<3 {
                        let pixelValue = originalPixels[originalOffset + i]
                        (contextData + contextOffset + i).storeBytes(of: pixelValue, as: UInt8.self)
                    }
                    
                    // 设置Alpha通道
                    if maskValue >= 220 {
                        // 完全是人物区域 - 完全不透明
                        (contextData + contextOffset + 3).storeBytes(of: UInt8(255), as: UInt8.self)
                    } else {
                        // 边缘区域 - 应用平滑过渡
                        // 计算透明度：将128-220的值映射到0-255
                        let alpha = min(255, UInt8(Double(maskValue - personThreshold) * edgeBlendFactor))
                        (contextData + contextOffset + 3).storeBytes(of: alpha, as: UInt8.self)
                    }
                }
                // 如果maskValue < personThreshold，保持完全透明（背景区域）
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
