//
//  TextRecognitionService.swift
//  RealtimeNumberReader
//
//  Created by JEUNG WON KIM on 2/27/24.
//  Copyright © 2024 Apple. All rights reserved.
//

import AVFoundation
import UIKit
import Vision

class TextRecognizer {
    // MARK: - Region of interest (ROI) and text orientation
    private let bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    private var textRecognitionRequest: VNRecognizeTextRequest?
    private let callback: (String) -> Void
    private let numberTracker: StringTracker
    private let targetView: PreviewView

    // The region of the video data output buffer that recognition should be run on,
    // which gets recalculated once the bounds of the preview layer are known.
    var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    // Transform from UI orientation to buffer orientation.
    let uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
    // Transform bottom-left coordinates to top-left.
    var visionToAVFTransform = CGAffineTransform.identity
    
    init(targetView: PreviewView, callback: @escaping (String) -> Void) {
        self.targetView = targetView
        self.numberTracker = StringTracker()
        self.callback = callback
    }
    
    func getTextRecognitionRequest() -> VNRecognizeTextRequest {
        if(textRecognitionRequest == nil) {
            textRecognitionRequest = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        }
        
        let request = textRecognitionRequest!
        
        request.recognitionLevel = .fast
        // Language correction doesn't help in recognizing phone numbers and also
        // slows recognition.
        request.usesLanguageCorrection = false
        // Only run on the region of interest for maximum speed.
        request.regionOfInterest = regionOfInterest
        request.revision = VNRecognizeTextRequestRevision3
        
        return request
    }

    func getRegionOfInterest() -> CGRect {
        return regionOfInterest
    }
    
    func getVisionToAVFTransform() -> CGAffineTransform {
        return visionToAVFTransform
    }

    func setRegionOfInterest(frame: CGRect, targetFrame: CGRect) {
        // update ROI
        print("setRegionOfInterest: updating ROI: \(regionOfInterest)")
        regionOfInterest = normalizeFrame(frame: frame, targetFrame: targetFrame)
        print("setRegionOfInterest: ROI: \(regionOfInterest)")
        
        updateVisionToAVFTransform()
    }
    
    private func normalizeFrame(frame: CGRect, targetFrame: CGRect) -> CGRect{
        // Figure out the size of the ROI.
        let frameWidth = CGFloat(targetFrame.size.width)
        let frameHeight = CGFloat(targetFrame.size.height)

        let normalized = CGRect(
            origin: CGPoint(
                x: frame.origin.x / frameWidth,
                y: frame.origin.y / frameHeight),
            size: CGSize(
                width: frame.size.width / frameWidth,
                height: frame.size.height / frameHeight)
        )
            .applying(bottomToTopTransform)
        return normalized
    }
    
    private func updateVisionToAVFTransform() {
        // Recalculate the affine transform between Vision coordinates and AVFoundation coordinates.
        // Compensate for the ROI.
        // Transform coordinates in ROI to global coordinates (still normalized).
        let roiToGlobalTransform = CGAffineTransform(
            translationX: regionOfInterest.origin.x,
            y: regionOfInterest.origin.y
        ).scaledBy(x: regionOfInterest.width, y: regionOfInterest.height)
        
        visionToAVFTransform = roiToGlobalTransform.concatenating(bottomToTopTransform).concatenating(uiRotationTransform)
    }
    
    // The Vision recognition handler.
    private func recognizeTextHandler(request: VNRequest, error: Error?) {
        var numbers = [String]()
        var redBoxes = [CGRect]() // Shows all recognized text lines.
        var greenBoxes = [CGRect]() // Shows words that might be serials.
        
        guard let results = request.results as? [VNRecognizedTextObservation] else {
            return
        }
        
        let maximumCandidates = 1
        
        for visionResult in results {
            guard let candidate = visionResult.topCandidates(maximumCandidates).first else { continue }
            
            // Draw red boxes around any detected text and green boxes around
            // any detected phone numbers. The phone number may be a substring
            // of the visionResult. If it's a substring, draw a green box around
            // the number and a red box around the full string. If the number
            // covers the full result, only draw the green box.
            var numberIsSubstring = true
            
            if let result = candidate.string.extractNumber(pattern: "\\S+") {
                let (range, number) = result
                
                // The number might not cover full visionResult. Extract the bounding
                // box of the substring.
                if let box = try? candidate.boundingBox(for: range)?.boundingBox {
                    numbers.append(number)
                    greenBoxes.append(box)
                    numberIsSubstring = !(range.lowerBound == candidate.string.startIndex && range.upperBound == candidate.string.endIndex)
                }
            }
            if numberIsSubstring {
                redBoxes.append(visionResult.boundingBox)
            }
        }
        
        // Log any found numbers.
        numberTracker.logFrame(strings: numbers)
        show(boxGroups: [(color: .red, boxes: redBoxes), (color: .green, boxes: greenBoxes)])
        
        // Check if there are any temporally stable numbers.
        if let sureNumber = numberTracker.getStableString() {
            numberTracker.reset(string: sureNumber)
            self.callback(sureNumber)
        }
    }
    
    // MARK: - Bounding box drawing
    
    // Draw a box on the screen, which must be done the main queue.
    var boxLayer = [CAShapeLayer]()
    func draw(rect: CGRect, color: CGColor) {
        let layer = CAShapeLayer()
        layer.opacity = 0.5
        layer.borderColor = color
        layer.borderWidth = 3
        layer.frame = rect
        boxLayer.append(layer)
        targetView.videoPreviewLayer.insertSublayer(layer, at: 1)
    }
    
    // Remove all drawn boxes. Must be called on main queue.
    func removeBoxes() {
        for layer in boxLayer {
            layer.removeFromSuperlayer()
        }
        boxLayer.removeAll()
    }
    
    typealias ColoredBoxGroup = (color: UIColor, boxes: [CGRect])
    
    // Draws groups of colored boxes.
    func show(boxGroups: [ColoredBoxGroup]) {
        DispatchQueue.main.async {
            let layer = self.targetView.videoPreviewLayer
            self.removeBoxes()
            for boxGroup in boxGroups {
                let color = boxGroup.color
                for box in boxGroup.boxes {
                    let rect = layer.layerRectConverted(fromMetadataOutputRect: box.applying(self.visionToAVFTransform))
                    self.draw(rect: rect, color: color.cgColor)
                }
            }
        }
    }
}
