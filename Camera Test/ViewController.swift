//
//  ViewController.swift
//  Camera Test
//
//  Created by Tony Zhang on 2019-12-01.
//  Copyright © 2019 Tony Zhang. All rights reserved.
//

import UIKit
import Photos
import AVFoundation

class ViewController: UIViewController {

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    
    var rawImageFileURLList: [URL?] = []
    var compressedFileDataList: [Data?] = []
    
    var rawImageFileURL: URL?
    var compressedFileData: Data?
    
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var captureButton: UIButton!
    
    private func setupCaptureSession() {
        self.session.beginConfiguration()
        let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                  for: .video, position: .unspecified)
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice!), self.session.canAddInput(videoDeviceInput) else {
            return
        }
        self.session.addInput(videoDeviceInput)
        
        guard session.canAddOutput(photoOutput) else { return }
        session.sessionPreset = .photo
        session.addOutput(photoOutput)
        session.commitConfiguration()
        
        previewView.session = self.session
        
        captureButton.addTarget(self, action: #selector(onCapture), for: .touchUpInside)

        session.startRunning()
        
//        do {
//            try videoDevice?.lockForConfiguration()
//            videoDevice?.setExposureModeCustom(duration: CMTimeMake(value: 1, timescale: 1), iso: 24.0, completionHandler: nil)
//            videoDevice?.unlockForConfiguration()
//        } catch {
//            
//        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: // The user has previously granted access to the camera.
                self.setupCaptureSession()
                return
            case .notDetermined: // The user has not yet been asked for camera access.
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        self.setupCaptureSession()
                    }
                }
                return
            case .denied: // The user has previously denied access.
                return
            case .restricted: // The user can't grant access due to restrictions.
                return
            @unknown default:
                return
        }
    }
    
    @objc func onCapture(_: UIButton) {
        let exposureValues: [Float] = [-2, 0, +2]
        self.rawImageFileURLList = Array(repeating: nil, count: exposureValues.count)
        self.compressedFileDataList = Array(repeating: nil, count: exposureValues.count)
        let makeAutoExposureSettings = AVCaptureAutoExposureBracketedStillImageSettings.autoExposureSettings(exposureTargetBias:)
        let exposureSettings = exposureValues.map(makeAutoExposureSettings)

        guard let availableRawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first else { return }
        let photoSettings = AVCapturePhotoBracketSettings(
            rawPixelFormatType: availableRawFormat,
            processedFormat: [AVVideoCodecKey : AVVideoCodecType.hevc],
            bracketedSettings: exposureSettings
        )
        self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
}

extension ViewController: AVCapturePhotoCaptureDelegate {
    // Hold on to the separately delivered RAW file and compressed photo data until capture is finished.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else { print("Error capturing photo: \(error!)"); return }

        if photo.isRawPhoto {
            // Save the RAW (DNG) file data to a URL.
            let dngFileURL = self.makeUniqueTempFileURL(extension: "dng")
            do {
                try photo.fileDataRepresentation()!.write(to: dngFileURL)
                self.rawImageFileURLList[photo.sequenceCount - 1] = dngFileURL
            } catch {
                fatalError("couldn't write DNG file to URL")
            }
        } else {
            self.compressedFileDataList[photo.sequenceCount - 1] = photo.fileDataRepresentation()!
        }
    }
    
    // After both RAW and compressed versions are delivered, add them to the Photos Library.
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error == nil else { print("Error capturing photo: \(error!)"); return }
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            
            PHPhotoLibrary.shared().performChanges({ [weak self] in
                guard let self = self else {
                    return
                }
                
                for (index, value) in self.rawImageFileURLList.enumerated() {
                    guard let compressedData = self.compressedFileDataList[index], let rawURL = value else {
                        continue
                    }
                    // Add the compressed (HEIF) data as the main resource for the Photos asset.
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .photo, data: compressedData, options: nil)

                    // Add the RAW (DNG) file as an altenate resource.
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    creationRequest.addResource(with: .alternatePhoto, fileURL: rawURL, options: options)
                }
            }, completionHandler: self.handlePhotoLibraryError)
        }
    }
    
    func handlePhotoLibraryError(success: Bool, error: Error?) {}

    func makeUniqueTempFileURL(extension type: String) -> URL {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        let uniqueFilename = ProcessInfo.processInfo.globallyUniqueString
        let urlNoExt = temporaryDirectoryURL.appendingPathComponent(uniqueFilename)
        let url = urlNoExt.appendingPathExtension(type)
        return url
    }
}
