import AVFoundation
import UIKit

class ViewController: UIViewController, CameraHelperDelegate {

    // MARK: - Views

    private lazy var recordButton = UIButton(type: .roundedRect).configure {
        $0.setTitle("Record", for: .normal)
        $0.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
    }
    private lazy var resumeButton = UIButton(type: .roundedRect).configure {
        $0.setTitle("Resume", for: .normal)
        $0.addTarget(self, action: #selector(resumeInterruptedSession), for: .touchUpInside)
    }
    private lazy var cameraButton = UIButton(type: .roundedRect).configure {
        $0.setTitle("Switch Camera", for: .normal)
        $0.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
    }

    private lazy var buttonStackView = UIStackView(
        arrangedSubviews: [resumeButton, recordButton, cameraButton]
    ).configure {
        $0.axis = .horizontal
        $0.distribution = .fillEqually
        $0.translatesAutoresizingMaskIntoConstraints = false
    }

    private lazy var previewView = PreviewView()
    private lazy var spinner = UIActivityIndicatorView(style: .large).configure {
        $0.color = UIColor.yellow
    }

    private lazy var mainStackView = UIStackView(
        arrangedSubviews: [previewView, buttonStackView]
    ).configure {
        $0.axis = .vertical
        $0.translatesAutoresizingMaskIntoConstraints = false
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

    func resumingEnabled(_ enabled: Bool) {
        resumeButton.isHidden = !enabled
    }

    func cameraSwitchingEnabled(_ enabled: Bool) {
        cameraButton.isEnabled = enabled
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

    // add gesture recognizer
    @objc private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(
            fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view)
        )
        cameraHelper.focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }

    // MARK: - Methods

    private func setUpViews() {
        recordButton.isEnabled = false
        resumeButton.isHidden = true
        cameraButton.isEnabled = false
        isRecording(false)

        buttonStackView.heightAnchor.constraint(equalToConstant: 150).isActive = true

        view.addSubview(mainStackView)
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        previewView.addSubview(self.spinner)
    }

    private func setUpCamera() {
        previewView.session = cameraHelper.session
        cameraHelper.delegate = self
        cameraHelper.checkVideoAuthorization()
    }
}
