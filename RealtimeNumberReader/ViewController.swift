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

    private var bb1: BoundingBoxView!
    private var bb2: BoundingBoxView!
    private let infoLabel1 = UILabel()
    private let infoLabel2 = UILabel()

    private let resetButton = UIButton()
    
    // MARK: - Capture related objects
    private let captureSession = AVCaptureSession()
    private let captureSessionQueue = DispatchQueue(label: "com.example.apple-samplecode.CaptureSessionQueue")
    private var captureDevice: AVCaptureDevice?
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoDataOutputQueue")
    
    // MARK: - Recognition related objects
    // TODO: Maybe this will help: https://think4753.rssing.com/chan-74142477/all_p3.html
    private var recognizer1: TextRecognizer!
    private var recognizer2: TextRecognizer!
    
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
        
        recognizer1 = TextRecognizer(targetView: previewView, callback: {
            (_ number: String) -> Void in
                DispatchQueue.main.async {
                    self.infoLabel1.text = "Number: \(number)"
                }
           
        })
        bb1 = BoundingBoxView(targetView: previewView, textRecognizer: recognizer1, config: ViewConfigPresets.ollie.config)
        view.addSubview(bb1)
        
        recognizer2 = TextRecognizer(targetView: previewView, callback: {
            (_ number: String) -> Void in
                DispatchQueue.main.async {
                    self.infoLabel2.text = "Number: \(number)"
                }
           
        })
        bb2 = BoundingBoxView(targetView: previewView, textRecognizer: recognizer2, config: ViewConfigPresets.toran.config)
        view.addSubview(bb2)
        
        setupInfoLabels()
        configureResetButton()
            
        // Starting the capture session is a blocking call. Perform setup using
        // a dedicated serial dispatch queue to prevent blocking the main thread.
        captureSessionQueue.async {
            self.setupCamera()
            
            DispatchQueue.main.async {
                self.bb1.setup()
                self.bb2.setup()
            }
            
        }
        
    }

    private func setupInfoLabels() {
        let labelWidth = UIScreen.main.bounds.size.width - 44

        // Setup info Label
        infoLabel1.text = "\(ViewConfigPresets.ollie.config.id): DEBUGGING LABEL"
        infoLabel1.textColor = .black
        
        infoLabel1.frame = CGRect(origin: ViewConfigPresets.ollie.config.debugLabelPosition, size: CGSize(width: labelWidth, height: 15))
        view.addSubview(infoLabel1)
        
        // Setup info Label
        infoLabel2.text = "\(ViewConfigPresets.toran.config.id): DEBUGGING LABEL"
        infoLabel2.textColor = .black
        
        infoLabel2.frame = CGRect(origin: ViewConfigPresets.toran.config.debugLabelPosition, size: CGSize(width: labelWidth, height: 15))
        view.addSubview(infoLabel2)
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
        bb1.reset()
        bb2.reset()
    }

}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            
            do {
                try requestHandler.perform([recognizer1.getTextRecognitionRequest(), recognizer2.getTextRecognitionRequest()])
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
