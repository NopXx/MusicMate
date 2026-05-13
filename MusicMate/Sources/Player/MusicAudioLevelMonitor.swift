import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import Accelerate
import os

private final class FFTBandProcessor: @unchecked Sendable {
    static let bandCount = 10
    static let fftSize = 1024
    private static let log2n = vDSP_Length(log2(Float(FFTBandProcessor.fftSize)))

    let bandsLock = OSAllocatedUnfairLock<[Float]>(initialState: Array(repeating: 0, count: FFTBandProcessor.bandCount))

    private let fftSetup: FFTSetup
    private var hann: [Float]
    private var ring: [Float]
    private var ringIdx: Int = 0
    private var monoMix: [Float]
    private let monoCap = 8192
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    private var bandStart: [Int]
    private var bandEnd: [Int]

    init() {
        fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        hann = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        ring = [Float](repeating: 0, count: Self.fftSize)
        monoMix = [Float](repeating: 0, count: 8192)
        windowed = [Float](repeating: 0, count: Self.fftSize)
        realp = [Float](repeating: 0, count: Self.fftSize / 2)
        imagp = [Float](repeating: 0, count: Self.fftSize / 2)
        magnitudes = [Float](repeating: 0, count: Self.fftSize / 2)
        bandStart = [Int](repeating: 0, count: Self.bandCount)
        bandEnd = [Int](repeating: 0, count: Self.bandCount)
        computeBands(sampleRate: 48000)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    func setSampleRate(_ rate: Float) {
        computeBands(sampleRate: rate)
    }

    private func computeBands(sampleRate: Float) {
        let minF: Float = 60
        let nyquist = sampleRate / 2
        let maxF: Float = min(nyquist * 0.9, 14000)
        let ratio = powf(maxF / minF, 1.0 / Float(Self.bandCount))
        let binWidth = sampleRate / Float(Self.fftSize)
        for i in 0..<Self.bandCount {
            let f0 = minF * powf(ratio, Float(i))
            let f1 = minF * powf(ratio, Float(i + 1))
            let b0 = max(1, Int(f0 / binWidth))
            let b1 = max(b0 + 1, Int(f1 / binWidth))
            bandStart[i] = b0
            bandEnd[i] = min(Self.fftSize / 2, b1)
        }
    }

    func feedInterleaved(_ p: UnsafePointer<Float>, frames: Int, channels: Int) {
        let n = min(frames, monoCap)
        if channels == 1 {
            for i in 0..<n { monoMix[i] = p[i] }
        } else {
            let invC = 1.0 / Float(channels)
            for i in 0..<n {
                var s: Float = 0
                for c in 0..<channels { s += p[i * channels + c] }
                monoMix[i] = s * invC
            }
        }
        feedMono(count: n)
    }

    func feedNonInterleaved(left: UnsafePointer<Float>, right: UnsafePointer<Float>?, frames: Int) {
        let n = min(frames, monoCap)
        if let r = right {
            for i in 0..<n { monoMix[i] = (left[i] + r[i]) * 0.5 }
        } else {
            for i in 0..<n { monoMix[i] = left[i] }
        }
        feedMono(count: n)
    }

    private func feedMono(count: Int) {
        var i = 0
        while i < count {
            let space = Self.fftSize - ringIdx
            let take = min(space, count - i)
            for k in 0..<take {
                ring[ringIdx + k] = monoMix[i + k]
            }
            ringIdx += take
            i += take
            if ringIdx >= Self.fftSize {
                ringIdx = 0
                process()
            }
        }
    }

    private func process() {
        ring.withUnsafeBufferPointer { rp in
            hann.withUnsafeBufferPointer { hp in
                windowed.withUnsafeMutableBufferPointer { wp in
                    vDSP_vmul(rp.baseAddress!, 1, hp.baseAddress!, 1, wp.baseAddress!, 1, vDSP_Length(Self.fftSize))
                }
            }
        }
        realp.withUnsafeMutableBufferPointer { rePtr in
            imagp.withUnsafeMutableBufferPointer { imPtr in
                var sc = DSPSplitComplex(realp: rePtr.baseAddress!, imagp: imPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.fftSize / 2) { cptr in
                        vDSP_ctoz(cptr, 2, &sc, 1, vDSP_Length(Self.fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &sc, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { mp in
                    vDSP_zvmags(&sc, 1, mp.baseAddress!, 1, vDSP_Length(Self.fftSize / 2))
                }
            }
        }
        var size = Int32(Self.fftSize / 2)
        magnitudes.withUnsafeMutableBufferPointer { mp in
            vvsqrtf(mp.baseAddress!, mp.baseAddress!, &size)
        }
        var divisor = Float(Self.fftSize)
        magnitudes.withUnsafeMutableBufferPointer { mp in
            vDSP_vsdiv(mp.baseAddress!, 1, &divisor, mp.baseAddress!, 1, vDSP_Length(Self.fftSize / 2))
        }
        var out = [Float](repeating: 0, count: Self.bandCount)
        for i in 0..<Self.bandCount {
            let s = bandStart[i]
            let e = bandEnd[i]
            var sum: Float = 0
            for b in s..<e { sum += magnitudes[b] }
            let avg = sum / Float(max(1, e - s))
            let boost: Float = 1.0 + Float(i) * 0.4
            out[i] = min(1, avg * 28 * boost)
        }
        bandsLock.withLock { $0 = out }
    }
}

@MainActor
final class MusicAudioLevelMonitor: ObservableObject {
    static let shared = MusicAudioLevelMonitor()

    @Published private(set) var bands: [Float] = Array(repeating: 0, count: FFTBandProcessor.bandCount)

    private var processTapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tapASBD: AudioStreamBasicDescription?
    private var currentPID: pid_t = -1
    private var watchTimer: Timer?
    private var publishTimer: Timer?
    private var started = false
    private let processor = FFTBandProcessor()

    func start() {
        if started { return }
        started = true
        attemptAttach()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.attemptAttach() }
        }
        publishTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let raw = self.processor.bandsLock.withLock { $0 }
            Task { @MainActor in
                var smoothed = self.bands
                let n = min(raw.count, smoothed.count)
                for i in 0..<n {
                    let r = raw[i]
                    if r > smoothed[i] {
                        smoothed[i] = smoothed[i] * 0.2 + r * 0.8
                    } else {
                        smoothed[i] = smoothed[i] * 0.7 + r * 0.3
                    }
                }
                self.bands = smoothed
            }
        }
    }

    private func attemptAttach() {
        let pid = musicPID() ?? -1
        if pid == currentPID && processTapID != kAudioObjectUnknown { return }
        teardown()
        currentPID = pid
        guard pid > 0 else {
            NSLog("[AudioTap] Music.app not running")
            return
        }
        guard #available(macOS 14.2, *) else {
            NSLog("[AudioTap] requires macOS 14.2+")
            return
        }
        guard let processObjID = processAudioObjectID(forPID: pid) else {
            NSLog("[AudioTap] cannot translate pid \(pid) to AudioObjectID")
            return
        }
        NSLog("[AudioTap] attaching pid=\(pid) processObjID=\(processObjID)")
        installTap(processObjectID: processObjID)
    }

    @available(macOS 14.2, *)
    private func installTap(processObjectID: AudioObjectID) {
        let desc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        desc.uuid = UUID()
        desc.isPrivate = true

        var tapID: AudioObjectID = kAudioObjectUnknown
        let createStatus = AudioHardwareCreateProcessTap(desc, &tapID)
        guard createStatus == noErr, tapID != kAudioObjectUnknown else {
            NSLog("[AudioTap] CreateProcessTap failed: \(createStatus)")
            return
        }
        processTapID = tapID

        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &asbdSize, &asbd)
        tapASBD = asbd
        processor.setSampleRate(Float(asbd.mSampleRate))

        guard let outputUID = defaultOutputDeviceUID() else { return }
        let aggUID = "com.nopxx.musicmate.audiotap.\(UUID().uuidString)"
        let aggDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MusicMate Tap",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: desc.uuid.uuidString
                ]
            ]
        ]
        var aggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &aggID)
        guard aggStatus == noErr else {
            NSLog("[AudioTap] CreateAggregateDevice failed: \(aggStatus)")
            return
        }
        aggregateDeviceID = aggID

        let proc = processor
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = Int(asbd.mChannelsPerFrame)

        var procID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inInput, _, _, _ in
            guard isFloat else { return }
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
            if isNonInterleaved {
                guard abl.count >= 1, let lRaw = abl[0].mData else { return }
                let frames = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
                let l = lRaw.assumingMemoryBound(to: Float.self)
                if abl.count >= 2, let rRaw = abl[1].mData {
                    let r = rRaw.assumingMemoryBound(to: Float.self)
                    proc.feedNonInterleaved(left: l, right: r, frames: frames)
                } else {
                    proc.feedNonInterleaved(left: l, right: nil, frames: frames)
                }
            } else {
                guard let raw = abl[0].mData else { return }
                let frames = Int(abl[0].mDataByteSize) / (max(1, channels) * MemoryLayout<Float>.size)
                let p = raw.assumingMemoryBound(to: Float.self)
                proc.feedInterleaved(p, frames: frames, channels: max(1, channels))
            }
        }
        guard procStatus == noErr, let procID else {
            NSLog("[AudioTap] CreateIOProc failed: \(procStatus)")
            return
        }
        ioProcID = procID
        let startStatus = AudioDeviceStart(aggID, procID)
        NSLog("[AudioTap] started tapID=\(tapID) aggID=\(aggID) startStatus=\(startStatus) channels=\(channels) sampleRate=\(asbd.mSampleRate) nonInterleaved=\(isNonInterleaved)")
    }

    private func teardown() {
        if aggregateDeviceID != kAudioObjectUnknown, let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if #available(macOS 14.2, *), processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
        }
        ioProcID = nil
        aggregateDeviceID = kAudioObjectUnknown
        processTapID = kAudioObjectUnknown
        processor.bandsLock.withLock { v in
            for i in 0..<v.count { v[i] = 0 }
        }
    }

    private func processAudioObjectID(forPID pid: pid_t) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidVar = pid
        var objID: AudioObjectID = kAudioObjectUnknown
        var outSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            UInt32(MemoryLayout<pid_t>.size),
            &pidVar,
            &outSize,
            &objID
        )
        guard st == noErr, objID != kAudioObjectUnknown else { return nil }
        return objID
    }

    private func musicPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.Music" }?
            .processIdentifier
    }

    private func defaultOutputDeviceUID() -> String? {
        var devID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID) == noErr,
              devID != kAudioObjectUnknown else {
            return nil
        }
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let st = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(devID, &uidAddr, 0, nil, &uidSize, $0)
        }
        guard st == noErr else { return nil }
        return uid as String
    }
}
