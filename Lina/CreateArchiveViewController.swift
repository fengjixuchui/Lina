//
//  CreateArchiveViewController.swift
//  Lina
//
//  Created by Snoolie Keffaber on 2025/05/17.
//

import UIKit
import NeoAppleArchive
import MobileCoreServices

class CreateArchiveViewController: UIViewController, UIDocumentPickerDelegate {
    enum CreationType {
        case aar
        case aea
        case key
        case auth
    }
    
    private var currentCreationType: CreationType = .aar
    private var directoryPicker: UIDocumentPickerViewController!
    private var selectedDirectoryURL: URL?
    private let progressView = UIProgressView(progressViewStyle: .bar)
    // MARK: - For AEA
    private var selectedPrivateKeyURL: URL?
    private var selectedAuthDataURL: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupDocumentPickers()
    }
    
    private func setupViews() {
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemGroupedBackground
        } else {
            // Fallback on earlier versions
        }
        title = "Create Archive"
        
        let container = UIView()
        if #available(iOS 13.0, *) {
            container.backgroundColor = .secondarySystemGroupedBackground
        } else {
            // Fallback on earlier versions
        }
        container.layer.cornerRadius = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        /*let selectButton = UIButton(type: .system)
        selectButton.setTitle("Select Directory", for: .normal)
        selectButton.makePrimaryActionButton()
        selectButton.addTarget(self, action: #selector(selectDirectory), for: .touchUpInside)*/
        
        let createButton = UIButton(type: .system)
        createButton.setTitle("Create Archive", for: .normal)
        createButton.makePrimaryActionButton()
        createButton.addTarget(self, action: #selector(pressedCreateArchive), for: .touchUpInside)
        
        let createAEAButton = UIButton(type: .system)
        createAEAButton.setTitle("Create Encrypted Archive", for: .normal)
        createAEAButton.makePrimaryActionButton()
        createAEAButton.addTarget(self, action: #selector(pressedCreateAEAArchive), for: .touchUpInside)
        
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true
        
        //stackView.addArrangedSubview(selectButton)
        stackView.addArrangedSubview(createButton)
        stackView.addArrangedSubview(createAEAButton)
        stackView.addArrangedSubview(progressView)
        
        container.addSubview(stackView)
        view.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            stackView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            
            progressView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }
    
    private func setupDocumentPickers() {
        directoryPicker = UIDocumentPickerViewController(documentTypes: [kUTTypeFolder as String], in: .open)
        directoryPicker.delegate = self
    }
    
    @objc private func selectDirectory() {
        directoryPicker.delegate = self
        present(directoryPicker, animated: true)
    }
    
    @objc private func pressedCreateArchive() {
        currentCreationType = .aar
        directoryPicker.delegate = self
        present(directoryPicker, animated: true)
    }
    
    @objc private func pressedCreateAEAArchive() {
        currentCreationType = .aea
        let keyPicker = UIDocumentPickerViewController(documentTypes: [kUTTypeData as String], in: .open)
        keyPicker.delegate = self
        present(keyPicker, animated: true)
    }
    
    private func createArchive() {
        guard let inputURL = selectedDirectoryURL else {
            showAlert(title: "Error", message: "Please select a directory first")
            return
        }
        
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("Archive_\(Date().timeIntervalSince1970).aar")
        
        progressView.isHidden = false
        progressView.progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Create plain archive
            let plainArchive = neo_aa_archive_plain_from_directory(inputURL.path)
            
            // Write to path
            neo_aa_archive_plain_write_path(plainArchive, outputPath.path)
            
            // Cleanup
            neo_aa_archive_plain_destroy_nozero(plainArchive)
            
            DispatchQueue.main.async {
                self.progressView.isHidden = true
                self.showSuccess(outputPath: outputPath)
            }
        }
    }
    
    private func handleKeySelection(_ url: URL) {
        do {
            let keyData = try Data(contentsOf: url)
            guard keyData.count == 97 else {
                showAlert(title: "Invalid Key", message: "Key must be 97 bytes ECDSA-P256 in X9.63 format")
                return
            }
                
            selectedPrivateKeyURL = url
            promptForAuthData()
        } catch {
            showAlert(title: "Error", message: "Could not read key file")
        }
    }
        
    private func promptForAuthData() {
        let authPicker = UIDocumentPickerViewController(documentTypes: [kUTTypeData as String], in: .open)
        authPicker.delegate = self
        present(authPicker, animated: true)
    }
        
    private func createAEAArchive() {
        guard
            let aarURL = selectedDirectoryURL,
            let keyURL = selectedPrivateKeyURL,
            let authURL = selectedAuthDataURL
        else { return }
            
        do {
            let keyData = try Data(contentsOf: keyURL)
            let authData = try Data(contentsOf: authURL)
            let aeaData = try AEAProfile0Handler.createAEAFromAAR(
                aarURL: aarURL,
                privateKey: keyData,
                authData: authData
            )
            
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("temp_\(Date().timeIntervalSince1970).aea")
            try aeaData.write(to: tempURL)
                
            let savePicker = UIDocumentPickerViewController(
                documentTypes: [kUTTypeData as String],
                in: .exportToService
            )
            savePicker.delegate = self
            present(savePicker, animated: true)
                
        } catch let error as AEAProfile0Handler.AEAError {
            handleAEAError(error)
        } catch {
            showAlert(title: "Error", message: error.localizedDescription)
        }
    }
    
    private func handleAEAError(_ error: AEAProfile0Handler.AEAError) {
        let message: String
        switch error {
        case .invalidKeySize:
            message = "Private key must be 97 bytes (Raw X9.63 ECDSA-P256)"
        case .invalidKeyFormat:
            message = "Invalid ECDSA-P256 key format (Needs Raw X9.63 ECDSA-P256)"
        case .signingFailed:
            message = "Failed to sign archive"
        case .invalidArchive:
            message = "Invalid AAR file"
        case .unsupportedProfile:
            message = "Unsupported AEA profile"
        case .extractionFailed:
            message = "Failed to extract archive"
        }
        showAlert(title: "Error", message: message)
    }
    
    private func showSuccess(outputPath: URL) {
        let alert = UIAlertController(
            title: "Success!",
            message: "Archive created at \(outputPath.lastPathComponent). Press \"Share\" to save your file.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.addAction(UIAlertAction(title: "Share", style: .default) { _ in
            self.shareFile(url: outputPath)
        })
        
        present(alert, animated: true)
    }
    
    private func shareFile(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activityVC, animated: true)
    }
    
    // MARK: - Document Picker Delegate
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        if currentCreationType == .aar {
            selectedDirectoryURL = url
            createArchive()
        } else if currentCreationType == .aea {
            selectedDirectoryURL = url
            promptForAuthData()
        } else if currentCreationType == .key {
            handleKeySelection(url)
        } else {
            // Must be .auth
            selectedAuthDataURL = url
            createAEAArchive()
        }
    }
}

extension UIViewController {
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension UIButton {
    func makePrimaryActionButton() {
        backgroundColor = .systemBlue
        layer.cornerRadius = 12
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)
        setTitleColor(.white, for: .normal)
        titleLabel?.font = .boldSystemFont(ofSize: 18)
        contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        titleLabel?.lineBreakMode = .byWordWrapping
        titleLabel?.numberOfLines = 0
        titleLabel?.textAlignment = .center
    }
}
