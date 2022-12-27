//
//  Recording.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import Foundation
import AppKit
import ScreenCaptureKit
import AVFAudio

extension AppDelegate {
    @objc func prepRecord(_ sender: NSMenuItem) {
        // file preparation
        //audioOnly = sender.identifier?.rawValue == "audio"
        if sender.identifier?.rawValue == "display" {
            screen = availableContent!.displays.first // todo: pick the actual display
        } else if sender.identifier?.rawValue != "audio" {
            window = availableContent!.windows.first(where: { app in
                sender.title == String(app.windowID) // sender.title == app.owningApplication!.bundleIdentifier
            })
        }
        if window != nil {
            filter = SCContentFilter(desktopIndependentWindow: window!)
        } else {
            let excluded = self.availableContent?.applications.filter { app in
                //self.excludedWindows.contains(app.bundleIdentifier)
                //Bundle.main.bundleIdentifier == app.bundleIdentifier
                false
            }
            filter = SCContentFilter(display: screen ?? availableContent!.displays.first!, excludingApplications: excluded ?? [], exceptingWindows: [])
        }
        let audioOnly = screen == nil && window == nil
        if audioOnly {
            audioFile = try! AVAudioFile(forWriting: NSURL(fileURLWithPath: "/Users/mnpn/Downloads/" + getFileName() + ".m4a") as URL, settings: audioSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        Task { await record(audioOnly: audioOnly) }

        // while recording, keep a timer which updates the menu's stats
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMenu()
        }
        RunLoop.current.add(updateTimer!, forMode: .common) // required to have the menu update while open
    }

    func record(audioOnly: Bool) async {
        let conf = SCStreamConfiguration()
        conf.width = 2
        conf.height = 2
        let scale: Int = NSScreen.main != nil ? Int(NSScreen.main!.backingScaleFactor) : 1
        if !audioOnly {
            conf.width = window == nil ? availableContent!.displays[0].width*scale : Int((window?.frame.width)!*CGFloat(scale))
            conf.height = window == nil ? availableContent!.displays[0].height*scale : Int((window?.frame.height)!*CGFloat(scale))
        }

        conf.minimumFrameInterval = CMTime(value: 1, timescale: audioOnly ? 1 : 60)
        conf.showsCursor = true
        conf.capturesAudio = true
        conf.sampleRate = audioSettings["AVSampleRateKey"] as! Int
        conf.channelCount = audioSettings["AVNumberOfChannelsKey"] as! Int

        stream = SCStream(filter: filter!, configuration: conf, delegate: self)
        do {
            try! stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try! stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            if !audioOnly {
                initVideo(conf: conf)
            }
            try await stream?.startCapture()
        } catch {
            assertionFailure("capture failed")
            return
        }
        isRecording = true
        updateIcon()
        createMenu()
    }

    @objc func stopRecording() {
        if screen != nil || window != nil {
            closeVideo()
        } else {
            audioFile = nil // nilling the file closes it
        }
        stream?.stopCapture()
        isRecording = false
        window = nil
        screen = nil
        updateIcon()
        updateTimer?.invalidate()
        createMenu()
    }

    func getFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        return "Recording at " + dateFormatter.string(from: Date())
    }

    func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter.string(from: TimeInterval(duration))!
    }
}