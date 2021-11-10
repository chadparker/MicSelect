import AVFoundation
import UIKit

class ViewController: UIViewController, CameraHelperDelegate {

    // MARK: - Views

    private lazy var recordButton = UIButton(type: .roundedRect).configure {
        $0.setTitle("Record", for: .normal)
        $0.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
    }
    private lazy var cameraButton = UIButton(type: .roundedRect).configure {
        $0.setTitle("Switch Camera", for: .normal)
        $0.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
    }
    private lazy var resumeButton = UIButton(type: .roundedRect).configure {
        $0.setTitle("Resume", for: .normal)
        $0.addTarget(self, action: #selector(resumeInterruptedSession), for: .touchUpInside)
    }

    private lazy var buttonStackView = UIStackView(
        arrangedSubviews: [resumeButton, recordButton, cameraButton]
    ).configure {
        $0.axis = .horizontal
        $0.distribution = .fillEqually
        $0.translatesAutoresizingMaskIntoConstraints = false
    }

    private lazy var previewView = PreviewView().configure {
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
    private lazy var spinner = UIActivityIndicatorView(style: .large).configure {
        $0.color = UIColor.yellow
    }

    // MARK: - Properties

    private lazy var cameraHelper = CameraHelper(previewView: previewView)

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpViews()
        setUpCamera()
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

    func recordingEnabled(_ enabled: Bool) {
        recordButton.isEnabled = enabled
    }

    func isRecording(_ isRecording: Bool) {
        recordButton.setTitle(
            isRecording ? "Stop" : "Record",
            for: .normal
        )
        //recordButton.setImage(#imageLiteral(resourceName: "CaptureStop"), for: [])
    }

    func cameraSwitchingEnabled(_ enabled: Bool) {
        cameraButton.isEnabled = enabled
    }

    func resumingEnabled(_ enabled: Bool) {
        resumeButton.isHidden = !enabled
    }

    func resumeFailed() {
        let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
        let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        present(alertController, animated: true, completion: nil)
    }

    // MARK: - Actions

    @objc private func toggleRecording(_ recordButton: UIButton) {
        cameraHelper.toggleRecording()
    }

    @objc private func switchCamera(_ cameraButton: UIButton) {
        cameraHelper.switchCamera()
    }

    @objc private func resumeInterruptedSession(_ resumeButton: UIButton) {
        cameraHelper.resumeInterruptedSession()
    }

    @objc private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(
            fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view)
        )
        cameraHelper.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }

    // MARK: - Methods

    private func setUpViews() {
        recordButton.isEnabled = false
        cameraButton.isEnabled = false
        resumeButton.isHidden = true
        isRecording(false)

        view.backgroundColor = .black

        view.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        view.addSubview(buttonStackView)
        NSLayoutConstraint.activate([
            buttonStackView.heightAnchor.constraint(equalToConstant: 150),
            buttonStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            buttonStackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            buttonStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        previewView.addSubview(self.spinner)

        view.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(focusAndExposeTap))
        )
    }

    private func setUpCamera() {
        previewView.session = cameraHelper.session
        cameraHelper.delegate = self
        cameraHelper.checkVideoAuthorization()
    }
}
