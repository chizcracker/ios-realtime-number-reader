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
    private let resetButton = UIButton()
    
    // MARK: - Capture related objects
    private let captureSession = AVCaptureSession()
    private let captureSessionQueue = DispatchQueue(label: "com.example.apple-samplecode.CaptureSessionQueue")
    private var captureDevice: AVCaptureDevice?
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoDataOutputQueue")
    
    // MARK: - Recognition related objects
    // TODO: Maybe this will help: https://think4753.rssing.com/chan-74142477/all_p3.html
    private var request: VNRecognizeTextRequest!
    
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
        
        configureResetButton()
        
        // Set up the Vision request before letting ViewController set up the camera
        // so it exists when the first buffer is received.
        request = VNRecognizeTextRequest(completionHandler: boundingBoxView.recognizeTextHandler)
        
        // Starting the capture session is a blocking call. Perform setup using
        // a dedicated serial dispatch queue to prevent blocking the main thread.
        captureSessionQueue.async {
            self.setupCamera()
            
            DispatchQueue.main.async {
                self.boundingBoxView.setup()
            }
            
        }
        
    }
    
    // MARK: - Setup
    
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
        } else {
            captureSession.sessionPreset = .hd1920x1080
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
    
    private func configureResetButton() {
        resetButton.frame = CGRect(x: 0, y: 0, width: 150, height: 30)
        resetButton.center = CGPoint(x: view.center.x, y: view.frame.height - 100)
        resetButton.setTitle("Reset", for: .normal)
        resetButton.setTitleColor(.systemBlue, for: .normal)
        view.addSubview(resetButton)
        
        resetButton.addTarget(self, action: #selector(resetButtonTapped), for: .touchUpInside)
    }
    
    @objc
    private func resetButtonTapped() {
        boundingBoxView.reset()
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
            request.regionOfInterest = boundingBoxView.regionOfInterest
            request.revision = VNRecognizeTextRequestRevision3
            
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            
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
