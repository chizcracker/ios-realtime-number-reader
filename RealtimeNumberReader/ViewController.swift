/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller that handles camera, preview, and bounding box UI.
*/

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
	private let previewView = PreviewView()
    private var boundingBoxView: BoundingBoxView!
    private let initialOrientation = UIDeviceOrientation.portrait
    
	// MARK: - Capture related objects
	private let captureSession = AVCaptureSession()
    private let captureSessionQueue = DispatchQueue(label: "com.example.apple-samplecode.CaptureSessionQueue")
	private var captureDevice: AVCaptureDevice?
	private var videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoDataOutputQueue")
    
    // MARK: - Recognition related objects
    private var request: VNRecognizeTextRequest!
	// The text orientation to search for in the region of interest (ROI).
	var textOrientation = CGImagePropertyOrientation.up
    // TODO: Understand this
    // TODO: Maybe this will help: https://think4753.rssing.com/chan-74142477/all_p3.html
	var bufferAspectRatio: Double!

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

        boundingBoxView = BoundingBoxView(name: "test", targetView: previewView, config: ViewConfigPresets.test.config)
        //view.addSubview(boundingBoxView.debugLayer)
        view.addSubview(boundingBoxView)

        // Set up the Vision request before letting ViewController set up the camera
        // so it exists when the first buffer is received.
        request = VNRecognizeTextRequest(completionHandler: boundingBoxView.recognizeTextHandler)

        // Starting the capture session is a blocking call. Perform setup using
        // a dedicated serial dispatch queue to prevent blocking the main thread.
        captureSessionQueue.async {
            self.setupCamera()
            
            // Calculate the ROI now that the camera is setup.
            DispatchQueue.main.async {
                // Initial orientation setup
                self.setupOrientationAndTransform(deviceOrientation: self.initialOrientation)
            }
        }
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)

		let deviceOrientation = UIDevice.current.orientation
		
		// Handle device orientation in the preview layer.
		if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
			if let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
				videoPreviewLayerConnection.videoOrientation = newVideoOrientation
			}
		}
        
        // Only change the current orientation if the new one is landscape or portrait.
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            setupOrientationAndTransform(deviceOrientation: deviceOrientation)
        }
    }
	
	// MARK: - Setup

    func setupOrientationAndTransform(deviceOrientation: UIDeviceOrientation) {
        // Compensate for the orientation. Buffers always come in the same orientation.
        let uiRotationTransform: CGAffineTransform
        
		switch deviceOrientation {
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
		
		// Update bounding box with new rotaion transformation.
        boundingBoxView.setRotationTransformation(uiRotationTransform: uiRotationTransform)
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
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
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
            request.regionOfInterest = boundingBoxView.getRegionOfInterest()
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
