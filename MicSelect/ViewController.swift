import AVFoundation
import UIKit

class ViewController: UIViewController, CameraHelperDelegate {

    // MARK: - Views

    private lazy var titleLabel = UILabel().configure {
        $0.text = "MicSelect"
        $0.textAlignment = .center
        $0.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
    private lazy var recordButton = UIButton(type: .roundedRect)
    private lazy var resumeButton = UIButton(type: .roundedRect)
    private lazy var cameraButton = UIButton(type: .roundedRect)

    private lazy var previewView = PreviewView()
    private lazy var spinner = UIActivityIndicatorView(style: .large)

    // MARK: - Properties

    var cameraHelper: CameraHelper!

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViews()
        cameraHelper = CameraHelper(delegate: self, previewView: previewView)
        previewView.session = cameraHelper.session
        cameraHelper.previewView = previewView
        cameraHelper.checkAuthorization()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraHelper.startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        cameraHelper.stopSession()
        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }

    override var shouldAutorotate: Bool {
        cameraHelper.shouldAutorotate
    }

    // MARK: - CameraHelperDelegate

    var windowOrientation: UIInterfaceOrientation {
        view.window?.windowScene?.interfaceOrientation ?? .unknown
    }

    var cameraSwitchingEnabled: Bool = false {
        didSet {

        }
    }

    var recordingEnabled: Bool = false {
        didSet {
            //
        }
    }

    var isRecording: Bool = false {
        didSet {
            self.recordButton.isEnabled = true
            if isRecording {
                self.recordButton.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
            }
        }
    }

    var resumingEnabled: Bool = false {
        didSet {
            resumeButton.isHidden = !resumingEnabled
        }
    }

    func resumeFailed() {
        let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
        let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        self.present(alertController, animated: true, completion: nil)
    }

    // MARK: - Actions

    @IBAction private func toggleMovieRecording(_ recordButton: UIButton) {
        /*
         Disable the Camera button until recording finishes, and disable
         the Record button until recording starts or finishes.

         See the AVCaptureFileOutputRecordingDelegate methods.
         */
        cameraButton.isEnabled = false
        recordButton.isEnabled = false

        cameraHelper.toggleMovieRecording {
            // re-enable buttons, or use delegate methods
        }
    }

    // resume button action

    @IBAction private func changeCamera(_ cameraButton: UIButton) {
        // disable button
        cameraHelper.changeCamera {
            // enable button
        }
    }

    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton) {
        cameraHelper.resumeInterruptedSession()
    }

    // add gesture recognizer
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(
            fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view)
        )
        cameraHelper.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }

    // MARK: - Methods

    private func setUpViews() {
        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        resumeButton.isHidden = true
        // add previewView
        // add recordButton
        // add resumeButton
        // add cameraButton
    }
}
