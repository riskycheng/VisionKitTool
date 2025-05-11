//
//  ImageDisplayView.swift
//  VisionKitTool
//
//  Created by Jian Cheng on 2025/5/10.
//

import SwiftUI

/// A reusable view for displaying images with consistent styling
struct ImageDisplayView: View {
    let image: UIImage
    let title: String?
    let maxHeight: CGFloat
    
    init(image: UIImage, title: String? = nil, maxHeight: CGFloat = 300) {
        self.image = image
        self.title = title
        self.maxHeight = maxHeight
    }
    
    var body: some View {
        VStack(spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.headline)
            }
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: maxHeight)
                .cornerRadius(10)
        }
    }
}

#Preview {
    ImageDisplayView(
        image: UIImage(systemName: "photo") ?? UIImage(),
        title: "Sample Image"
    )
}
