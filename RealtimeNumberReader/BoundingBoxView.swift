//
//  BoundingBoxView.swift
//  RealtimeNumberReader
//
//  Created by JEUNG WON KIM on 2/17/24.
//  Copyright © 2024 Apple. All rights reserved.
//

import AVFoundation
import UIKit
import Vision

class BoundingBoxView: UIView {
    let name: String
    
    private let targetView: PreviewView
    private let config: ViewConfig
    let debugLayer = UIView()
    private let infoLabel = UILabel()
    private let numberTracker = StringTracker()
    private var debug = true
    
    // MARK: - Region of interest (ROI) and text orientation
    // The region of the video data output buffer that recognition should be run on,
    // which gets recalculated once the bounds of the preview layer are known.
    var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    // Transform from UI orientation to buffer orientation.
    let uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
    // Transform bottom-left coordinates to top-left.
    let bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    var visionToAVFTransform = CGAffineTransform.identity
    
    init(name: String, targetView: PreviewView, config: ViewConfig) {
        self.name = name
        self.targetView = targetView
        self.config = config

        super.init(frame: CGRect(origin: config.startingPosition, size: config.startingSize))
    }
    
    func setup() {
        layer.borderWidth = config.borderWidth
        layer.borderColor = config.borderColor
        setRegionOfInterest()
        
        // Add Gestures
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureHandler))
        addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinchGestureHandler))
        addGestureRecognizer(pinchGesture)
        
        // Setup info Label
        infoLabel.text = "\(name): DEBUGGING LABEL"
        infoLabel.textColor = .black
        
        let labelWidth = UIScreen.main.bounds.size.width - 44
        infoLabel.frame = CGRect(origin: config.debugLabelPosition, size: CGSize(width: labelWidth, height: 15))
        targetView.addSubview(infoLabel)
        
        // Setup debug layer
        if(debug) {
            debugLayer.layer.frame = CGRect(origin: config.startingPosition, size: config.startingSize)
            debugLayer.layer.borderColor = UIColor.red.cgColor
            debugLayer.layer.borderWidth = config.borderWidth + 1
            targetView.addSubview(debugLayer)
            updateDebugFrame()
        }
    }
    
    func reset() {
        frame = CGRect(origin: config.startingPosition, size: config.startingSize)
        setRegionOfInterest()
    }
    
    // MARK: - Getters/Setters
    
    private func setRegionOfInterest() {
        // update ROI
        log("setRegionOfInterest: updating ROI: \(regionOfInterest)")
        let newRoi = toRegionOfInterest()
        regionOfInterest.origin = newRoi.origin
        regionOfInterest.size = newRoi.size
        log("setRegionOfInterest: ROI: \(regionOfInterest)")
        
        // update transform
        visionToAVFTransform = getVisionToAVFTransform()
        
        // update debugFrame
        if(debug) { updateDebugInfo() }
    }
    
    // MARK: - UI
    
    private var initialCenter: CGPoint = CGPoint.zero
    
    @objc
    private func panGestureHandler(_ gestureRecognizer : UIPanGestureRecognizer) {
        updateViewPosition(withPanGetureRecognizer: gestureRecognizer, initialCenter: &initialCenter)
        if gestureRecognizer.state == .ended {
            log("PanGesture: new position: \(frame.origin)")
            log("X: \(Int(frame.origin.x)), Y: \(Int(frame.origin.y))")
            setRegionOfInterest()
        }
    }
    
    private func updateViewPosition(withPanGetureRecognizer gestureRecognizer: UIPanGestureRecognizer, initialCenter: inout CGPoint) {
        guard let currentView = gestureRecognizer.view else {return}
        // Get the changes in the X and Y directions relative to
        // the superview's coordinate space.
        let translation = gestureRecognizer.translation(in: self)
        if gestureRecognizer.state == .began {
            // Save the view's original position.
            initialCenter = currentView.center
        }
        
        let scaleX = currentView.transform.a
        let scaleY = currentView.transform.d
        let newCenter = CGPoint(x: initialCenter.x + translation.x * scaleX, y: initialCenter.y + translation.y * scaleY)
        currentView.center = newCenter
        
        if gestureRecognizer.state == .ended || gestureRecognizer.state == .cancelled {
            initialCenter = .zero
        }
    }
    
    @objc
    private func pinchGestureHandler(_ gestureRecognizer : UIPinchGestureRecognizer) {
        scaleView(gestureRecognizer)
        if gestureRecognizer.state == .ended {
            log("pinchGestureHandler: new position: \(frame.origin)")
            log("pinchGestureHandler: new size: \(frame.size)")
            
        }
        setRegionOfInterest()
    }
    
    @objc
    private func scaleView(_ gestureRecognizer : UIPinchGestureRecognizer) {
        guard let currentView = gestureRecognizer.view else { return }
        if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
            currentView.transform = currentView.transform.scaledBy(x: gestureRecognizer.scale, y: gestureRecognizer.scale)
            currentView.layer.borderWidth = currentView.layer.borderWidth.scaled(by: 1/gestureRecognizer.scale)
            gestureRecognizer.scale = 1.0
        }
    }
    
    // MARK: - Text recognition
    
    // The Vision recognition handler.
    func recognizeTextHandler(request: VNRequest, error: Error?) {
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
            
            if let result = candidate.string.extractNumber() {
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
            printInfoLabel("Result: \(sureNumber)")
        }
    }
    
    private func toRegionOfInterest() -> CGRect{
        // Figure out the size of the ROI.
        let frameWidth = CGFloat(targetView.frame.size.width)
        let frameHeight = CGFloat(targetView.frame.size.height)
        log("toROI: \(regionOfInterest)")
        log("toROI: frameWidth: \(frameWidth), frameHeight: \(frameHeight)")
        log("toROI: bounding box width: \(frame.size.width), bounding box height: \(frame.size.height)")
        
        let normalized = CGRect(
            origin: CGPoint(
                x: frame.origin.x / frameWidth,
                y: frame.origin.y / frameHeight),
            size: CGSize(
                width: frame.size.width / frameWidth,
                height: frame.size.height / frameHeight)
        )
            .applying(self.bottomToTopTransform)
        log("toROI: normalized: \(normalized)")
        return normalized
    }
    
    private func getVisionToAVFTransform() -> CGAffineTransform{
        // Recalculate the affine transform between Vision coordinates and AVFoundation coordinates.
        // Compensate for the ROI.
        // Transform coordinates in ROI to global coordinates (still normalized).
        let roiToGlobalTransform = CGAffineTransform(
            translationX: regionOfInterest.origin.x,
            y: regionOfInterest.origin.y
        ).scaledBy(x: regionOfInterest.width, y: regionOfInterest.height)
        
        return roiToGlobalTransform.concatenating(bottomToTopTransform).concatenating(uiRotationTransform)
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
    
    private func updateDebugInfo() {
        printInfoLabel("Box: \(frame), ROI: \(regionOfInterest)")
        if(debug) { updateDebugFrame() }
    }
    
    private func updateDebugFrame() {
        log("updateDebugFrame: ROI: \(regionOfInterest)")
        log("updateDebugFrame: previewView: \(targetView.frame)")
        
        // Figure out where the cutout ends up in layer coordinates.
        let roiRectTransform = bottomToTopTransform.concatenating(uiRotationTransform)
        log("updateDebugFrame: bottomToTopTransform: \(bottomToTopTransform)")
        log("updateDebugFrame: uiRotationTransform: \(uiRotationTransform)")
        
        debugLayer.frame = targetView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: regionOfInterest.applying(roiRectTransform))
        
        log("updateDebugFrame: updated: \(debugLayer.frame)")
    }
    
    
    private func printInfoLabel(_ msg: String) {
        DispatchQueue.main.async {
            self.infoLabel.text = "[\(self.name)]: \(msg)"
        }
    }
    
    private func log(_ msg: String) {
        print("[\(name)]: \(msg)")
    }
    
    // This attribute hides `init(coder:)` from subclasses
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("NSCoding not supported")
    }
}
