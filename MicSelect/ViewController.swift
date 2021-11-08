import UIKit

class ViewController: UIViewController {

    // MARK: - Views

    private lazy var titleLabel = UILabel().configure {
        $0.text = "MicSelect"
        $0.textAlignment = .center
        $0.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        $0.translatesAutoresizingMaskIntoConstraints = false
    }

    private var previewView = PreviewView()

    // MARK: - Properties

    let cameraHelper = CameraHelper()

    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        initialize()
        setUpCamera()
    }

    // MARK: - Methods

    private func setUpCamera() {
        previewView.session = cameraHelper.session
    }

    private func initialize() {
        view.backgroundColor = .systemGray

        view.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
