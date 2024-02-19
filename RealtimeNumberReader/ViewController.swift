/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller that handles camera, preview, and cutout UI.
*/

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
	let previewView = PreviewView()
    let cutoutView = UIView()
    let numberResultView = UILabel()
    let numberDebugView = UILabel()
    let maskLayer = CAShapeLayer()
    let boundingBoxView = BoundingBoxView(name: "test", config: ViewConfigPresets.ollie.config)
    
	// The device orientation that's updated whenever the orientation changes to a
	// different supported orientation.
	var currentOrientation = UIDeviceOrientation.portrait
	
	// MARK: - Capture related objects
	private let captureSession = AVCaptureSession()
    let captureSessionQueue = DispatchQueue(label: "com.example.apple-samplecode.CaptureSessionQueue")
    
	var captureDevice: AVCaptureDevice?
    
	var videoDataOutput = AVCaptureVideoDataOutput()
    let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoDataOutputQueue")
    
	// MARK: - Region of interest (ROI) and text orientation
	// The region of the video data output buffer that recognition should be run on,
	// which gets recalculated once the bounds of the preview layer are known.
	var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
	// The text orientation to search for in the region of interest (ROI).
	var textOrientation = CGImagePropertyOrientation.up
	
	// MARK: - Coordinate transforms
	var bufferAspectRatio: Double!
	// Transform from UI orientation to buffer orientation.
	var uiRotationTransform = CGAffineTransform.identity
	// Transform bottom-left coordinates to top-left.
	var bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)

	
	// Vision to AVFoundation coordinate transform.
	var visionToAVFTransform = CGAffineTransform.identity
	
	// MARK: - View controller methods
	
	override func viewDidLoad() {
		super.viewDidLoad()
                
        let screenBounds = UIScreen.main.bounds
		
		// Set up the preview view.
		previewView.session = captureSession
        previewView.frame = CGRect(
            x: 0,
            y: 0,
            width: screenBounds.size.width,
            height: screenBounds.size.height
        )
        previewView.backgroundColor = .white
        previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        view.addSubview(previewView)
        
		// Set up the cutout view.
        cutoutView.frame = previewView.frame
		cutoutView.backgroundColor = UIColor.gray.withAlphaComponent(0.5)
        maskLayer.backgroundColor = UIColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        cutoutView.layer.mask = maskLayer
        view.addSubview(cutoutView)

        view.addSubview(numberDebugView)
        view.addSubview(numberResultView)
        
        view.addSubview(boundingBoxView)
        
        // Set up the Vision request before letting ViewController set up the camera
        // so it exists when the first buffer is received.
        request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)

        // Starting the capture session is a blocking call. Perform setup using
        // a dedicated serial dispatch queue to prevent blocking the main thread.
        captureSessionQueue.async {
            self.setupCamera()
            
            // Calculate the ROI now that the camera is setup.
            DispatchQueue.main.async {
                // Figure out the initial ROI.
                self.calculateRegionOfInterest()
            }
        }
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)

		// Only change the current orientation if the new one is landscape or portrait.
		let deviceOrientation = UIDevice.current.orientation
		if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
			currentOrientation = deviceOrientation
		}
		
		// Handle device orientation in the preview layer.
		if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
			if let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
				videoPreviewLayerConnection.videoOrientation = newVideoOrientation
			}
		}
		
		// The orientation changed. Figure out the new ROI.
		calculateRegionOfInterest()
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		updateCutout()
	}
	
	// MARK: - Setup
	
    func calculateRegionOfInterest() {
        // In landscape orientation, the desired ROI is specified as the ratio of
        // buffer width to height. When the UI is rotated to portrait, keep the
        // vertical size the same (in buffer pixels). Also try to keep the
        // horizontal size the same up to a maximum ratio.
        let desiredHeightRatio = 0.15
        let desiredWidthRatio = 0.6
        let maxPortraitWidth = 0.8
        
        // Figure out the size of the ROI.
        let size: CGSize
        if currentOrientation.isPortrait || currentOrientation == .unknown {
            print("portrait size width: \(desiredWidthRatio * bufferAspectRatio) VS \(maxPortraitWidth)")
            print("portrait size height: \(desiredHeightRatio / bufferAspectRatio)")

            size = CGSize(width: min(desiredWidthRatio * bufferAspectRatio, maxPortraitWidth), height: desiredHeightRatio / bufferAspectRatio)
        } else {
            size = CGSize(width: desiredWidthRatio, height: desiredHeightRatio)
        }
        // Center the ROI.
        // regionOfInterest.origin = CGPoint(x: (1 - size.width) / 2, y: (1 - size.height) / 2)
        // regionOfInterest.size = size
        
        let transform = bottomToTopTransform.concatenating(uiRotationTransform).inverted()
     
        print("bbBox: \(boundingBoxView.frame)")
        print("bbBox - Bounds: \(boundingBoxView.bounds)")
        
        let frameWidth = CGFloat(previewView.frame.size.width)
        let frameHeight = CGFloat(previewView.frame.size.height)

        let bbFrameBeforeTransform =
        CGRect(
            origin: CGPoint(
                x: boundingBoxView.frame.origin.x / frameWidth,
                y: boundingBoxView.frame.origin.y / frameHeight),
            size: CGSize(
                width: boundingBoxView.frame.size.width / frameWidth,
                height: boundingBoxView.frame.size.height / frameHeight)
        )
        print("bbFrameBeforeTransform: \(bbFrameBeforeTransform)")
        var bbFrame = bbFrameBeforeTransform.applying(transform)
        print("Transformed: \(bbFrame)")
        
        regionOfInterest.origin = bbFrame.origin
        regionOfInterest.size = bbFrame.size
        //regionOfInterest.origin = CGPoint(x: 0.5, y: 0.5)
        //regionOfInterest.size = CGSize(width: 0.1, height: 0.1)
        //regionOfInterest.origin = CGPoint(x: (1 - size.width) / 2, y: (1 - size.height) / 2)
        //regionOfInterest.size = size
        print("ROI: \(regionOfInterest)")

		// The ROI changed, so update the transform.
		setupOrientationAndTransform()
		
		// Update the cutout to match the new ROI.
		DispatchQueue.main.async {
			// Wait for the next run cycle before updating the cutout. This
			// ensures that the preview layer already has its new orientation.
			self.updateCutout()
		}
	}
	
	func updateCutout() {
        print("updateCutout: ROI: \(regionOfInterest)")
        print("updateCutout: previewView: \(previewView.frame)")
        
		// Figure out where the cutout ends up in layer coordinates.
		let roiRectTransform = bottomToTopTransform.concatenating(uiRotationTransform)
        let cutout = previewView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: regionOfInterest.applying(roiRectTransform))
        
        //cutout = cutoutOriginal
        print("updateCutout: Cutout: \(cutout)")
		
		// Create the mask.
		let path = UIBezierPath(rect: cutoutView.frame)
		path.append(UIBezierPath(rect: cutout))

		maskLayer.path = path.cgPath
		
		// Move the number view down to under cutout.
		var numFrame = cutout
        numFrame.origin.y += numFrame.size.height
        numberDebugView.frame = numFrame
		numFrame.origin.y += numFrame.size.height
		numberResultView.frame = numFrame
	}
	
	func setupOrientationAndTransform() {
		// Recalculate the affine transform between Vision coordinates and AVFoundation coordinates.
		
		// Compensate for the ROI.
		let roi = regionOfInterest
        // Transform coordinates in ROI to global coordinates (still normalized).
        let roiToGlobalTransform = CGAffineTransform(
            translationX: roi.origin.x,
            y: roi.origin.y
        ).scaledBy(x: roi.width, y: roi.height)
		
        // Compensate for the orientation. Buffers always come in the same orientation.
		switch currentOrientation {
            case .landscapeLeft:
                textOrientation = .up
                uiRotationTransform = .identity
            case .landscapeRight:
                textOrientation = .down
                uiRotationTransform = CGAffineTransform(translationX: 1, y: 1).rotated(by: CGFloat.pi)
            case .portraitUpsideDown:
                textOrientation = .left
                uiRotationTransform = CGAffineTransform(translationX: 1, y: 0).rotated(by: CGFloat.pi / 2)
            default: // Default everything else to .portraitUp.
                textOrientation = .right
                uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
		}
		
		// The full Vision ROI to AVFoundation transform.
		visionToAVFTransform = roiToGlobalTransform.concatenating(bottomToTopTransform).concatenating(uiRotationTransform)
	}
	
	func setupCamera() {
		guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
			print("Could not create capture device.")
			return
		}
		self.captureDevice = captureDevice
		
		// Requesting 4K buffers allows recognition of smaller text but consumes
		// more power. Use the smallest buffer size necessary to minimize
		// battery usage.
		if captureDevice.supportsSessionPreset(.hd4K3840x2160) {
			captureSession.sessionPreset = .hd4K3840x2160
			bufferAspectRatio = 3840.0 / 2160.0
		} else {
			captureSession.sessionPreset = .hd1920x1080
			bufferAspectRatio = 1920.0 / 1080.0
		}
		
		guard let deviceInput = try? AVCaptureDeviceInput(device: captureDevice) else {
			print("Could not create device input.")
			return
		}
		if captureSession.canAddInput(deviceInput) {
			captureSession.addInput(deviceInput)
		}
		
		// Configure the video data output.
		videoDataOutput.alwaysDiscardsLateVideoFrames = true
		videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
		videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
		if captureSession.canAddOutput(videoDataOutput) {
			captureSession.addOutput(videoDataOutput)
            // There's a trade-off here. Enabling stabilization temporally gives more
            // stable results and should help the recognizer converge, but if it's
            // enabled, the VideoDataOutput buffers don't match what's displayed on
            // screen, which makes drawing bounding boxes difficult. Disable stabilization
            // in this app to allow drawing detected bounding boxes on screen.
			videoDataOutput.connection(with: .video)?.preferredVideoStabilizationMode = .off
		} else {
			print("Could not add VDO output")
			return
		}
		
		// Set zoom and autofocus to help focus on very small text.
		do {
			try captureDevice.lockForConfiguration()
			captureDevice.videoZoomFactor = 2
			captureDevice.autoFocusRangeRestriction = .near
			captureDevice.unlockForConfiguration()
		} catch {
			print("Could not set zoom level due to error: \(error)")
			return
		}
		
		captureSession.startRunning()
	}
	
	// MARK: - UI drawing and interaction
	
	func showString(string: String) {
		// Stop the camera synchronously to stop receiving buffers.
        // Then update the number view asynchronously.
		captureSessionQueue.sync {
			//self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.numberResultView.text = string
                self.numberResultView.isHidden = false
            }
		}
	}
    
    func showDebugString(string: String) {
        // Stop the camera synchronously to stop receiving buffers.
        // Then update the number view asynchronously.
        captureSessionQueue.sync {
            DispatchQueue.main.async {
                self.numberDebugView.text = string
                self.numberDebugView.isHidden = false
            }
        }
    }
	
	func handleTap(_ sender: UITapGestureRecognizer) {
        captureSessionQueue.async {
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            DispatchQueue.main.async {
                self.numberResultView.isHidden = true
                self.numberDebugView.isHidden = true
            }
        }
	}
    
    
    
    var request: VNRecognizeTextRequest!
    // The temporal string tracker.
    let numberTracker = StringTracker()
    
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
                showDebugString(string: number)
                
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
            showString(string: sureNumber)
            numberTracker.reset(string: sureNumber)
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
        previewView.videoPreviewLayer.insertSublayer(layer, at: 1)
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
            let layer = self.previewView.videoPreviewLayer
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

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
	
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            // Configure for running in real time.
            request.recognitionLevel = .fast
            // Language correction doesn't help in recognizing phone numbers and also
            // slows recognition.
            request.usesLanguageCorrection = false
            // Only run on the region of interest for maximum speed.
            request.regionOfInterest = regionOfInterest
            request.revision = VNRecognizeTextRequestRevision3
            
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: textOrientation, options: [:])
            do {
                try requestHandler.perform([request])
            } catch {
                print(error)
            }
        }
    }
}

// MARK: - Utility extensions

extension AVCaptureVideoOrientation {
	init?(deviceOrientation: UIDeviceOrientation) {
		switch deviceOrientation {
		case .portrait: self = .portrait
		case .portraitUpsideDown: self = .portraitUpsideDown
		case .landscapeLeft: self = .landscapeRight
		case .landscapeRight: self = .landscapeLeft
		default: return nil
		}
	}
}
