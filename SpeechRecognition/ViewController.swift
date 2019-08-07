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
import CoreHaptics

class ViewController: UIViewController, SFSpeechRecognizerDelegate {

    @IBOutlet private var debugButton: UIButton!
    @IBOutlet private var logTextArea: UITextView!
    @IBOutlet private var amplitudeMeter: UIProgressView!
    private var displayLink: CADisplayLink?
    private var hapticLink: CADisplayLink?

    var selectedInputDevice: AKDevice?

    var mic: AKMicrophone? = AKMicrophone()
    var tracker: AKFrequencyTracker?
    var silence: AKBooster?

    let haptics = UISelectionFeedbackGenerator()


    override func viewDidLoad() {
        super.viewDidLoad()

//        print(AudioKit.engine.inputNode.inputFormat(forBus: 0))

        AKSettings.useBluetooth = true
        AKSettings.notificationsEnabled = true
        AKSettings.defaultToSpeaker = true
        AKSettings.allowHapticsAndSystemSoundsDuringRecording = true
        AKSettings.enableLogging = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setRecordButton(active: true, title: "Start Diagnostic")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        debugTap()

        hapticLink = CADisplayLink(target: self, selector: #selector(hapticBump))
        hapticLink?.preferredFramesPerSecond = 3
        hapticLink?.add(to: .main, forMode: .common)

    }

    @objc func updateUI() {
        let amplitude = tracker?.amplitude ?? 0
        let maxAmplitude = 0.25
        let mappedAmplitude = max(min((amplitude / maxAmplitude), 1.0), 0.0)
        amplitudeMeter.setProgress(Float(mappedAmplitude), animated: false)
    }

    @objc func hapticBump() {
        haptics.selectionChanged()
    }

    func setRecordButton(active: Bool, title: String) {
        self.debugButton.isEnabled = active
        self.debugButton.backgroundColor = active ? UIColor.systemRed : UIColor.systemGreen
        self.debugButton.setTitle(title, for: (active ? [] : .disabled))
        logTextArea.alpha = active ? 1 : 0.5
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

    @IBAction func debugTap(_ sender: UIControl? = nil) {

        clearLog()
        setRecordButton(active: false, title: "Diagnostic in progress")

        let delay: TimeInterval = 1
        self.printToLog("starting in \(delay)s…")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {

            self.startEngine(microphoneEnabled: false)
            self.disableMicrophone()

            let delay: TimeInterval = 2
            self.printToLog("enabling mic in \(delay)s…")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.enableMicrophone()

                let delay: TimeInterval = 2
                self.printToLog("disabling mic in \(delay)s…")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.disableMicrophone()

                    let delay: TimeInterval = 2
                    self.printToLog("stopping in \(delay)s…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.stopEngine()

                        self.printToLog("🎉 If you didn't crash yet, congratulations.\n")
                        self.setRecordButton(active: true, title: "Start Diagnostic")
                    }
                }
            }
        }
    }

    // MARK: - Mic

    private func startEngine(microphoneEnabled: Bool) {

        self.printToLog("starting \(microphoneEnabled ? "w/o mic…" : "w/ mic…")")

        setupMicrophone()
        tracker = AKFrequencyTracker(mic)
        silence = AKBooster(tracker!, gain: 0)
        AudioKit.output = silence!

        AKSettings.audioInputEnabled = microphoneEnabled

        let sessionCategory = AKSettings.computedSessionCategory()
        let sessionOptions = AKSettings.computedSessionOptions()
        do {
            try AKSettings.setSession(category: sessionCategory, with: sessionOptions)
            print ("Audio sample rate is: \(AVAudioSession.sharedInstance().sampleRate)")
        } catch {
            AKLog("Error setting AKSettings")
        }

        try! AudioKit.start()

        if microphoneEnabled {
            enableMicrophone()
        } else {
            disableMicrophone()
        }

        displayLink = CADisplayLink(target: self, selector: #selector(updateUI))
        displayLink?.add(to: .main, forMode: .common)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged(notification:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil)

        self.printToLog("✅ started.")
    }

    private func enableMicrophone() {
        AKSettings.audioInputEnabled = true

        let sessionCategory = AKSettings.computedSessionCategory()
        let sessionOptions = AKSettings.computedSessionOptions()
        do {
            try AKSettings.setSession(category: sessionCategory, with: sessionOptions)
        } catch {
            AKLog("Error setting AKSettings")
        }

        tracker?.start()
    }

    private func disableMicrophone() {
        tracker?.stop()
        AKSettings.audioInputEnabled = false

        let sessionCategory = AKSettings.computedSessionCategory()
        let sessionOptions = AKSettings.computedSessionOptions()
        do {
            try AKSettings.setSession(category: sessionCategory, with: sessionOptions)
        } catch {
            AKLog("Error setting AKSettings")
        }
    }

    private func attachMicrophone() {
        // Attempt to set sample rate from the get go
//        let inputFormat = AudioKit.engine.inputNode.inputFormat(forBus: 0)
        //            print("Sample rate: \(inputFormat.sampleRate)")
//        AKSettings.sampleRate = inputFormat.sampleRate
//        AKSettings.channelCount = inputFormat.channelCount
        //        mic = AKMicrophone(with: inputFormat) // CRASH HAPPENS HERE


//        AudioKit.output!.connect(to: tracker!)
//        AudioKit.output!.disconnectOutput()

        AKSettings.audioInputEnabled = true
        
    }

    private func detachMicrophone() {

        if let tracker = tracker,
            let silence = silence {
            tracker.disconnectOutput(from: silence)
//            tracker = nil
//            mic = nil
        }

        AKSettings.audioInputEnabled = false
    }

    private func setupMicrophone() {
        if mic == nil {
            mic = AKMicrophone()
        }

        if let selectedInputDevice = selectedInputDevice {
            do {
                try mic!.setDevice(selectedInputDevice)
                print ("Microphone set to \(selectedInputDevice)")
            } catch {
                print ("Could not set the audio input device to the AKMic: \(error)")
            }
        } else {
            print ("Microphone set to default")
        }
    }

    private func stopEngine() {

        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)

        displayLink?.invalidate()

        let inputNode = AudioKit.engine.inputNode
        inputNode.removeTap(onBus: 0)

        do {
            try AudioKit.stop()
        } catch {
            AKLog("Error stopping AudioKit")
        }

        mic?.disconnectOutput()
        tracker?.disconnectOutput()
        silence?.disconnectOutput()
        mic = nil
        tracker = nil
        silence = nil

        AKSettings.audioInputEnabled = false

        self.printToLog("🛑 stopped.")
    }

    // MARK: - Notification

    @objc func audioRouteChanged(notification: Notification) {
        print("Route changed > Sample Rate: \(AudioKit.engine.inputNode.inputFormat(forBus: 0).sampleRate)")
        // The inputNode won't actually be changed or report it's new sample rate for a short period of time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("Route changed >> Sample Rate: \(AudioKit.engine.inputNode.inputFormat(forBus: 0).sampleRate)")
        }
    }

    // MARK: - Logging

    private func printToLog(_ text: String) {
        self.logTextArea.text += "\n\(text)"
    }

    private func clearLog() {
        self.logTextArea.text = ""
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
        selectedInputDevice = device
    }
}
