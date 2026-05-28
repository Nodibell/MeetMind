//
//  ChatBubbleShape.swift
//  MeetMind
//
//  Created by Developer on 29.05.2026.
//

import SwiftUI

/// Custom chat bubble shape with an elegant message tail
struct ChatBubbleShape: Shape {
    let isUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let path = CGMutablePath()
        
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        
        let radius: CGFloat = 16
        
        let topLeftRadius = radius
        let topRightRadius = radius
        let bottomLeftRadius = isUser ? radius : 4
        let bottomRightRadius = isUser ? 4 : radius
        
        path.move(to: CGPoint(x: minX + topLeftRadius, y: minY))
        path.addLine(to: CGPoint(x: maxX - topRightRadius, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + topRightRadius), radius: topRightRadius)
        
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomRightRadius))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - bottomRightRadius, y: maxY), radius: bottomRightRadius)
        
        path.addLine(to: CGPoint(x: minX + bottomLeftRadius, y: maxY))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - bottomLeftRadius), radius: bottomLeftRadius)
        
        path.addLine(to: CGPoint(x: minX, y: minY + topLeftRadius))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + topLeftRadius, y: minY), radius: topLeftRadius)
        
        return Path(path)
    }
}
