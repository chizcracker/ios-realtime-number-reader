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
    private let targetView: PreviewView
    private let textRecognizer: TextRecognizer
    private let config: ViewConfig
    private let numberTracker = StringTracker()
    
    private let debugLayer = UIView()
    private var debug = true
    
    // MARK: - Vision <> UI Affine transformation for dubugging
    // Transform from UI orientation to buffer orientation.
    let uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
    // Transform bottom-left coordinates to top-left.
    let bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    
    init(targetView: PreviewView, textRecognizer: TextRecognizer, config: ViewConfig) {
        self.targetView = targetView
        self.textRecognizer = textRecognizer
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
        textRecognizer.setRegionOfInterest(frame: frame, targetFrame: targetView.frame)
        
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
    
    private func updateDebugInfo() {
        if(debug) { updateDebugFrame() }
    }
    
    private func updateDebugFrame() {
        let regionOfInterest = textRecognizer.getRegionOfInterest()
        log("updateDebugFrame: ROI: \(regionOfInterest)")
        log("updateDebugFrame: previewView: \(targetView.frame)")
        
        // Figure out where the cutout ends up in layer coordinates.
        let roiRectTransform = bottomToTopTransform.concatenating(uiRotationTransform)
        log("updateDebugFrame: bottomToTopTransform: \(bottomToTopTransform)")
        log("updateDebugFrame: uiRotationTransform: \(uiRotationTransform)")
        
        debugLayer.frame = targetView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: regionOfInterest.applying(roiRectTransform))
        
        log("updateDebugFrame: updated: \(debugLayer.frame)")
    }
    
    private func log(_ msg: String) {
        print("[\(config.id)]: \(msg)")
    }
    
    // This attribute hides `init(coder:)` from subclasses
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("NSCoding not supported")
    }
}
