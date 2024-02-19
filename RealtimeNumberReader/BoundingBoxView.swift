//
//  BoundingBoxView.swift
//  RealtimeNumberReader
//
//  Created by JEUNG WON KIM on 2/17/24.
//  Copyright © 2024 Apple. All rights reserved.
//

import AVFoundation
import UIKit

class BoundingBoxView: UIView {
    let name: String
   
    //private let previewView: PreviewView
    private let config: ViewConfig
    private let debugLabel = UILabel()

    
    init(name: String, config: ViewConfig) {
        self.name = name
        self.config = config

        super.init(frame: CGRect(origin: config.startingPosition, size: config.startingSize))
        self.setup()
    }
    
    func setup() {
        layer.borderWidth = config.borderWidth
        layer.borderColor = config.borderColor
        frame = CGRect(origin: config.startingPosition, size: config.startingSize)
        
        // Add Gestures
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureHandler))
        addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinchGestureHandler))
        addGestureRecognizer(pinchGesture)
        
        // Setup Debug Label
        debugLabel.text = "\(name): DEBUGGING LABEL"
        debugLabel.textColor = .black
        
        let labelWidth = UIScreen.main.bounds.size.width - 44
        debugLabel.frame = CGRect(origin: config.debugLabelPosition, size: CGSize(width: labelWidth, height: 15))
        addSubview(debugLabel)
    }


    
    override func layoutSubviews() {
        super.layoutSubviews()

        // adjust subviews
    }
    
    var initialCenter: CGPoint = CGPoint.zero
    
    @objc
    private func panGestureHandler(_ gestureRecognizer : UIPanGestureRecognizer) {
        updateViewPosition(withPanGetureRecognizer: gestureRecognizer, initialCenter: &initialCenter)
        if gestureRecognizer.state == .ended {
            log(msg: "PanGesture: new position: \(frame.origin)")
            log(msg: "X: \(Int(frame.origin.x)), Y: \(Int(frame.origin.y))")
            //updateGlobalVars()
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
        
        let newCenter = CGPoint(x: initialCenter.x + translation.x, y: initialCenter.y + translation.y)
        currentView.center = newCenter
        
        if gestureRecognizer.state == .ended || gestureRecognizer.state == .cancelled {
            initialCenter = .zero
        }
    }
    
    @objc
    private func pinchGestureHandler(_ gestureRecognizer : UIPinchGestureRecognizer) {
        scaleView(gestureRecognizer)
        if gestureRecognizer.state == .ended {
            log(msg: "pinchGestureHandler: new position: \(frame.origin)")
            log(msg: "pinchGestureHandler: new size: \(frame.size)")
            //updateGlobalVars()
        }
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
    
    func printDebugLabel(msg: String) {
        DispatchQueue.main.async {
            self.debugLabel.text = "[\(self.name)]: \(msg)"
        }
    }
    
    func log(msg: String) {
        print("[\(name)]: \(msg)")
    }
    
    // This attribute hides `init(coder:)` from subclasses
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("NSCoding not supported")
    }
}
