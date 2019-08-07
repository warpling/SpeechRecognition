//
//  ViewController.swift
//  SpeechRecognition
//
//  Created by Ryan McLeod.
//  Based on MicAnalysis by Kanstantsin Linou.
//  Copyright © 2019 AudioKit. All rights reserved.
//

import AudioKit
import UIKit
import Speech

class ViewController: UIViewController, SFSpeechRecognizerDelegate {

    @IBOutlet private var recordButton: UIButton!
    @IBOutlet private var transcriptionTextArea: UITextView!
    @IBOutlet private var amplitudeMeter: UIProgressView!

    var mic: AKMicrophone!
    var tracker: AKFrequencyTracker!
    var silence: AKBooster!

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var displayLink: CADisplayLink?

    var isAvailable: Bool = false {
        didSet {
            if isAvailable {
                setRecordButton(active: true, title: "Start Transcription")
            } else {
                isActive = false
                setRecordButton(active: false, title: "Transcription Unavailable")
                print("Transcription not available")
            }
        }
    }

    var isActive: Bool = false {
        didSet {

            guard oldValue != isActive else { return }
            guard isAvailable else {
                print("Cannot start transcription because it's not available.")
                return
            }

            if isActive {

                do {
                    try startSpeechRecognition()
                } catch {
                    print("Couldn't start speech recognition")
                }

                setRecordButton(active: true, title: "Stop transcription")

                displayLink = CADisplayLink(target: self, selector: #selector(updateUI))
                displayLink?.add(to: .main, forMode: .common)

            } else {

                do {
                    try stopSpeechRecognition()
                } catch {
                    print("Couldn't stop speech recognition")
                }

                self.setRecordButton(active: true, title: "Start Transcription")

                displayLink?.invalidate()
                amplitudeMeter.setProgress(0, animated: true)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        AKSettings.audioInputEnabled = true
        mic = AKMicrophone()
        tracker = AKFrequencyTracker(mic)
        silence = AKBooster(tracker, gain: 0)

        recordButton.isEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        AudioKit.output = silence

        speechRecognizer.delegate = self
        attemptToRequestSpeechAuthorization()
    }

    private func attemptToRequestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            /*
                The callback may not be called on the main thread. Add an
                operation to the main queue to update the record button's state.
            */
            OperationQueue.main.addOperation {
                switch authStatus {
                    case .authorized:
                        self.setRecordButton(active: true, title: "Tap to Transcribe")

                    case .denied:
                        self.setRecordButton(active: false, title: "Speech Permission denied")

                    case .restricted:
                        self.setRecordButton(active: false, title: "Speech Permission restricted")

                    case .notDetermined:
                        self.setRecordButton(active: false, title: "Speech Permission not determined")

                @unknown default:
                    self.setRecordButton(active: false, title: "Speech Permission unknown")
                }

                self.isAvailable = self.speechRecognizer.isAvailable
            }
        }
    }

    @objc func updateUI() {
        let amplitude = tracker.amplitude
        let maxAmplitude = 0.25
        let mappedAmplitude = max(min((amplitude / maxAmplitude), 1.0), 0.0)
        amplitudeMeter.setProgress(Float(mappedAmplitude), animated: false)
    }

    func setRecordButton(active: Bool, title: String) {
        self.recordButton.isEnabled = active
        self.recordButton.backgroundColor = active ? UIColor.systemRed : UIColor.systemGreen
        self.recordButton.setTitle(title, for: (active ? [] : .disabled))
        transcriptionTextArea.alpha = active ? 1 : 0.5
    }

    // MARK: - Actions

    @IBAction func didTapInputDevicesButton(_ sender: UIBarButtonItem) {
        let inputDevices = InputDeviceTableViewController()
        inputDevices.settingsDelegate = self
        let navigationController = UINavigationController(rootViewController: inputDevices)
        navigationController.preferredContentSize = CGSize(width: 300, height: 300)
        navigationController.modalPresentationStyle = .popover
        navigationController.popoverPresentationController!.delegate = self
        self.present(navigationController, animated: true, completion: nil)
    }

    @IBAction func recordButtonTapped() {
        isActive.toggle()
    }

    // MARK: - Speech

    private func startSpeechRecognition() throws {

        // Cancel the previous task if it's running.
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(AVAudioSession.Category.record)
        try audioSession.setMode(AVAudioSession.Mode.measurement)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        let inputNode = AudioKit.engine.inputNode
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to created a SFSpeechAudioBufferRecognitionRequest object") }

        // Configure request so that results are returned before audio recording is finished
        recognitionRequest.shouldReportPartialResults = true

        // A recognition task represents a speech recognition session.
        // We keep a reference to the task so that it can be cancelled.
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                self.transcriptionTextArea.text = result.bestTranscription.formattedString
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                self.isActive = false
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            self.recognitionRequest?.append(buffer)
        }

        try AudioKit.start()
        transcriptionTextArea.text = "(Go ahead, I'm listening)"
    }

    private func stopSpeechRecognition() throws {
        recognitionRequest?.endAudio()
        self.recognitionRequest = nil
        self.recognitionTask = nil

        let inputNode = AudioKit.engine.inputNode
        inputNode.removeTap(onBus: 0)

        try AudioKit.stop()
    }

    // MARK: SFSpeechRecognizerDelegate

    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        isAvailable = available
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension ViewController: UIPopoverPresentationControllerDelegate {

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }

    func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {
        popoverPresentationController.permittedArrowDirections = .up
        popoverPresentationController.barButtonItem = navigationItem.rightBarButtonItem
    }
}

// MARK: - InputDeviceDelegate

extension ViewController: InputDeviceDelegate {

    func didSelectInputDevice(_ device: AKDevice) {
        do {
            try mic.setDevice(device)
        } catch {
            AKLog("Error setting input device")
        }
    }
}
