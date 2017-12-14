import UIKit
import Vision
import Alamofire
import SwiftyJSON
import AVFoundation

final class ViewController: UIViewController {
    let delay:Double = 3
    var session: AVCaptureSession?
    
    let logo = UIImageView(image: #imageLiteral(resourceName: "logo.png"))
    let label = UILabel()
    
    var currentImage:CIImage!
    var lastCheck = Date()
    
    let synthesizer = AVSpeechSynthesizer()
    let faceDetection = VNDetectFaceRectanglesRequest()
    let faceDetectionRequest = VNSequenceRequestHandler()
    
    var frontCamera: AVCaptureDevice? = {
        return AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: AVMediaType.video, position: .front)
    }()
    
    lazy var previewLayer: AVCaptureVideoPreviewLayer? = {
        guard let session = self.session else { return nil }
        
        var previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        
        return previewLayer
    }()
    
    override func loadView() {
        super.loadView()
        
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.contentMode = .scaleAspectFit
        view.addSubview(logo)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = UIFont.boldSystemFont(ofSize: 24)
        label.lineBreakMode = .byWordWrapping
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = view.frame.width - 20
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            logo.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            logo.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
            logo.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -33),
        ])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        sessionPrepare()
        session?.startRunning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.frame
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let previewLayer = previewLayer else { return }
        view.layer.addSublayer(previewLayer)
        
        view.bringSubview(toFront: logo)
        view.bringSubview(toFront: label)
    }

    func sessionPrepare() {
        session = AVCaptureSession()
        guard let session = session, let captureDevice = frontCamera else { return }
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            session.beginConfiguration()
            
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            
            output.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.commitConfiguration()
            let queue = DispatchQueue(label: "output.queue")
            output.setSampleBufferDelegate(self, queue: queue)
            print("setup delegate")
        } catch {
            print("can't setup session")
        }
    }
    
    func greet (_ name:String) {
        let bits = name.split(separator: "-")
        let person = bits[0].capitalized
        
        let greeting = PickOne([
            "Welcome \(person)!",
            "\(person) has entered the building",
            "\(person) is in the house",
            "Warning: \(person) is approaching",
            "Quick, hide and look busy, \(person) is here!",
            "Oh no, who let \(person) in?",
            "Please join me in welcoming \(person)",
        ])
        
        let utterance = AVSpeechUtterance(string: greeting)
        self.synthesizer.speak(utterance)
        label.text = greeting
    }
    
    func PickOne(_ list:Array<String>) -> String {
        let randomIndex = Int(arc4random_uniform(UInt32(list.count)))
        return list[randomIndex]
    }
    
    func detectFace() {
        if Date().timeIntervalSince1970 - lastCheck.timeIntervalSince1970 < delay {
            return
        }
        
        lastCheck = Date()
        
        try? faceDetectionRequest.perform([faceDetection], on: currentImage!)
        if let results = faceDetection.results as? [VNFaceObservation] {
            DispatchQueue.main.async(execute: {
                if !results.isEmpty {
                    let imageData = CIContext().jpegRepresentation(of: self.currentImage, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality: 0.0])
                    NSLog("Sending image of size \(imageData!.count)")
                    
                    Alamofire.upload(imageData!, to: "https://terem-welcome.herokuapp.com/").responseJSON { response in
                        if response.result.value != nil {
                            let json = JSON(response.result.value!)
                            if let id = json["id"].string {
                                self.greet(id)
                            }
                        }
                    }
                }
            })
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
        
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate)
        let ciImage = CIImage(cvImageBuffer: pixelBuffer!, options: attachments as! [String : Any]?)
        let ciImageWithOrientation = ciImage.oriented(forExifOrientation: Int32(UIImageOrientation.leftMirrored.rawValue))
        currentImage = ciImageWithOrientation
        detectFace()
    }
}

