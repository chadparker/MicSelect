import AVFoundation
import Photos
import UIKit

protocol CameraControllerDelegate: AnyObject {
    var windowOrientation: UIInterfaceOrientation { get }
    func recordingEnabled(_ enabled: Bool)
    func isRecording(_ isRecording: Bool)
    func cameraSwitchingEnabled(_ enabled: Bool)
    func resumingEnabled(_ enabled: Bool)
    func resumeFailed()
}

class CameraController: NSObject, AVCaptureFileOutputRecordingDelegate {

    // MARK: - Identifiers

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    // MARK: - Properties

    weak var delegate: CameraControllerDelegate!
    private weak var previewView: PreviewView!

    let session = AVCaptureSession()
    // Communicate with the session and other session objects on this queue
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var setupResult: SessionSetupResult = .success
    private var isSessionRunning = false
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!

    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?

    private var keyValueObservations = [NSKeyValueObservation]()

    private var recordingEnabled: Bool = false { didSet { delegate.recordingEnabled(recordingEnabled) } }
    private var isRecording: Bool = false { didSet { delegate.isRecording(isRecording) } }
    private var cameraSwitchingEnabled = false { didSet { delegate.cameraSwitchingEnabled(cameraSwitchingEnabled) } }
    private var resumingEnabled: Bool = false { didSet { delegate.resumingEnabled(resumingEnabled) } }

    var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        if let movieFileOutput = movieFileOutput {
            return !movieFileOutput.isRecording
        }
        return true
    }

    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInDualWideCamera],
        mediaType: .video,
        position: .unspecified
    )

    // MARK: - Init

    init(previewView: PreviewView) {
        self.previewView = previewView
    }

    // MARK: - Configuration

    func checkVideoAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
        default:
            setupResult = .notAuthorized
        }

        sessionQueue.async {
            self.configureSession()
        }
    }

    private func configureSession() {
        guard setupResult == .success else { return }

        session.beginConfiguration()

        // Add video input
        do {
            var defaultVideoDevice: AVCaptureDevice?
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let dualWideCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                defaultVideoDevice = dualWideCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput

                DispatchQueue.main.async {
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.delegate.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.delegate.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        // Add an audio input device
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)

            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }

        // Add the video output
        let movieFileOutput = AVCaptureMovieFileOutput()
        if self.session.canAddOutput(movieFileOutput) {
            self.session.addOutput(movieFileOutput)
            self.session.sessionPreset = .vga640x480

            if let connection = movieFileOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            self.session.commitConfiguration()

            self.movieFileOutput = movieFileOutput

            DispatchQueue.main.async {
                self.recordingEnabled = true
            }
        }

        session.commitConfiguration()
    }

    // MARK: - Session Start/Stop

    func startSession() {
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
            case .notAuthorized:
                fatalError("not authorized")
            case .configurationFailed:
                fatalError("config failed")
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
    }

    func resumeInterruptedSession() {
        sessionQueue.async {
            /*
             The session might fail to start running, for example, if a phone or FaceTime call is still
             using audio or video. This failure is communicated by the session posting a
             runtime error notification. To avoid repeatedly failing to start the session,
             only try to restart the session in the error handler if you aren't
             trying to resume the session.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    self.delegate.resumeFailed()
                }
            } else {
                DispatchQueue.main.async {
                    self.resumingEnabled = false
                }
            }
        }
    }

    // MARK: - Device Configuration

    func switchCamera() {
        recordingEnabled = false
        cameraSwitchingEnabled = false

        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position

            let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )
            var newVideoDevice: AVCaptureDevice? = nil

            switch currentPosition {
            case .unspecified, .front:
                newVideoDevice = backVideoDeviceDiscoverySession.devices.first
            case .back:
                newVideoDevice = frontVideoDeviceDiscoverySession.devices.first
            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                newVideoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            }

            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

                    self.session.beginConfiguration()

                    // Remove the existing device input first, because AVCaptureSession doesn't support
                    // simultaneous use of the rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)

                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)

                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        self.session.sessionPreset = .high

                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }

                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }

            DispatchQueue.main.async {
                self.recordingEnabled = self.movieFileOutput != nil
                self.cameraSwitchingEnabled = true
            }
        }
    }

    @objc func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(
            with: .continuousAutoFocus,
            exposureMode: .continuousAutoExposure,
            at: devicePoint,
            monitorSubjectAreaChange: false
        )
    }

    func focus(with focusMode: AVCaptureDevice.FocusMode,
               exposureMode: AVCaptureDevice.ExposureMode,
               at devicePoint: CGPoint,
               monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }

        recordingEnabled = false
        cameraSwitchingEnabled = false

        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }

                // Update the orientation on the movie file output video connection before recording.
                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!

                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes

                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }

                // Start recording video to a temporary file.
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                movieFileOutput.stopRecording()
            }
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    // Did start recording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        // Enable the Record button to let the user stop recording.
        DispatchQueue.main.async {
            self.recordingEnabled = true
            self.isRecording = true
        }
    }

    // Did finish recording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Note: Because we use a unique file path for each recording, a new recording won't overwrite a recording mid-save.
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid

                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }

        var success = true

        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }

        if success {
            // Check the authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                    }, completionHandler: { success, error in
                        if !success {
                            print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanup()
                    }
                    )
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }

        DispatchQueue.main.async {
            self.recordingEnabled = true
            self.isRecording = false
            // Only enable the ability to change camera if the device has more than one camera.
            self.cameraSwitchingEnabled = self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
        }
    }

    // MARK: - KVO & Notifications

    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }

            DispatchQueue.main.async {
                self.recordingEnabled = isSessionRunning && self.movieFileOutput != nil
                // Only enable the ability to change camera if the device has more than one camera.
                self.cameraSwitchingEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
            }
        }
        keyValueObservations.append(keyValueObservation)

        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: videoDeviceInput.device
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )

        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)

        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }

    // MARK: - Error Handling

    @objc func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }

        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumingEnabled = true
                    }
                }
            }
        } else {
            self.resumingEnabled = true
        }
    }

    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        /*
         The frame rates used here are only for demonstration purposes.
         Your frame rate throttling may be different depending on your app's camera configuration.
         */
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            if self.movieFileOutput == nil || self.movieFileOutput?.isRecording == false {
                do {
                    try self.videoDeviceInput.device.lockForConfiguration()
                    print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                    self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                    self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                    self.videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }

    @objc func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios you want to enable the user to resume the session.
         For example, if music playback is initiated from Control Center while
         using AVCam, then the user can let AVCam resume
         the session running, which will stop music playback. Note that stopping
         music playback in Control Center will not automatically resume the session.
         Also note that it's not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")

            var showResumeButton = false
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                showResumeButton = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // TODO: add cameraUnavailableLabel
                // Fade-in a label to inform the user that the camera is unavailable.
//                cameraUnavailableLabel.alpha = 0
//                cameraUnavailableLabel.isHidden = false
//                UIView.animate(withDuration: 0.25) {
//                    self.cameraUnavailableLabel.alpha = 1
//                }
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                print("Session stopped running due to shutdown system pressure level.")
            }
            if showResumeButton {
                self.resumingEnabled = true
            }
        }
    }

    @objc func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")

        if self.resumingEnabled {
            self.resumingEnabled = false
        }
        // TODO: add cameraUnavailableLabel
//        if !cameraUnavailableLabel.isHidden {
//            UIView.animate(withDuration: 0.25,
//                           animations: {
//                            self.cameraUnavailableLabel.alpha = 0
//            }, completion: { _ in
//                self.cameraUnavailableLabel.isHidden = true
//            }
//            )
//        }
    }
}

// MARK: - Extensions

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

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        return uniqueDevicePositions.count
    }
}
