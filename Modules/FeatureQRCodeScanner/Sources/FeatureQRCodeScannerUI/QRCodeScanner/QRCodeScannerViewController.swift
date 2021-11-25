// Copyright © Blockchain Luxembourg S.A. All rights reserved.

import DIKit
import FeatureQRCodeScannerDomain
import PlatformKit
import PlatformUIKit
import ToolKit
import UIKit

public enum QRCodePresentationType {
    case modal(dismissWithAnimation: Bool)
    case child
}

final class QRCodeScannerViewController: UIViewController, UINavigationControllerDelegate {

    private var targetCoordinateSpace: UICoordinateSpace {
        guard isViewLoaded else {
            fatalError("viewFrame should only be accessed after the view is loaded.")
        }
        guard let window = UIApplication.shared.keyWindow else {
            fatalError("Trying to get key window before it was set!")
        }
        return window.coordinateSpace
    }

    private var scannerView: QRCodeScannerView!

    private let viewModel: QRCodeScannerViewModelProtocol
    private let presentationType: QRCodePresentationType
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.main(.medium, 16)
        label.textColor = .white
        return label
    }()

    private let closeButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(named: "close"), for: .normal)
        return button
    }()

    init(
        presentationType: QRCodePresentationType = .modal(dismissWithAnimation: true),
        viewModel: QRCodeScannerViewModelProtocol
    ) {
        self.presentationType = presentationType
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        switch presentationType {
        case .modal(dismissWithAnimation: let animated):
            modalTransitionStyle = .crossDissolve
            self.viewModel.closeButtonTapped = { [weak self] in
                guard let self = self else { return }
                self.dismiss(
                    animated: animated,
                    completion: { [weak self] in
                        self?.viewModel.completed(.failure(.dismissed))
                    }
                )
            }
        case .child:
            titleLabel.isHidden = true
        }

        self.viewModel.scanningStarted = { [weak self] in
            self?.scanDidStart()
            Logger.shared.info("Scanning started")
        }

        self.viewModel.scanningStopped = { [weak self] in
            self?.scanDidStop()
        }

        self.viewModel.scanComplete = { [weak self] result in
            self?.handleScanComplete(with: result)
        }
        self.viewModel.overlayViewModel.cameraButtonTapped = { [weak self] in
            self?.showImagePicker()
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.darkFadeBackground

        scannerView = QRCodeScannerView(viewModel: viewModel, targetCoordinateSpace: targetCoordinateSpace)
        scannerView.alpha = 1
        view.addSubview(scannerView)
        scannerView.layoutToSuperview(.leading, .trailing, .top, .bottom)

        view.addSubview(titleLabel)
        view.addSubview(closeButton)

        closeButton.addTarget(self, action: #selector(closeButtonClicked), for: .touchUpInside)

        switch presentationType {
        case .modal:
            titleLabel.isHidden = false
            titleLabel.text = viewModel.headerText
            title = viewModel.headerText
            titleLabel.layout(to: .centerY, of: closeButton)
            titleLabel.layoutToSuperview(.centerX)
            closeButton.isHidden = false
            closeButton.layout(size: .edge(44))
            closeButton.layoutToSuperview(.trailing, offset: -12)
            closeButton.layoutToSuperview(.top, offset: 12)
        case .child:
            closeButton.isHidden = true
            titleLabel.isHidden = true
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.startReadingQRCode(from: scannerView)
        scannerView?.startReadingQRCode()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.viewWillDisappear()
    }

    @objc func closeButtonClicked(sender: AnyObject) {
        viewModel.closeButtonPressed()
    }

    private func handleScanComplete(with result: Result<QRCodeScannerResultType, QRCodeScannerResultError>) {
        guard case .success = result else { return }

        switch presentationType {
        case .modal(dismissWithAnimation: let animated):
            dismiss(animated: animated) { [weak self] in
                self?.viewModel.completed(result)
            }
        case .child:
            viewModel.completed(result)
        }
    }

    private func scanDidStart() {
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseIn, .transitionCrossDissolve, .beginFromCurrentState],
            animations: {
                self.scannerView?.alpha = 1
            },
            completion: nil
        )
    }

    private func scanDidStop() {}

    private func showImagePicker() {
        let pickerController = UIImagePickerController()
        pickerController.delegate = self
        pickerController.mediaTypes = ["public.image"]
        pickerController.sourceType = .photoLibrary
        present(pickerController, animated: true, completion: nil)
    }
}

extension QRCodeScannerViewController: UIImagePickerControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        guard let pickedImage = info[.originalImage] as? UIImage else { return }
        picker.dismiss(animated: true) { [weak self] in
            self?.viewModel.handleSelectedQRImage(pickedImage)
        }
    }
}