// MacAudioInputDevices.swift
// OSGKeyboard · Mac
//
// Core Audio input discovery and AVAudioEngine hardware binding. AVFoundation
// does not provide a high-level macOS input picker, so the selected device UID
// is resolved to an AudioDeviceID immediately before each recording.

import AudioToolbox
import AVFoundation
import CoreAudio

struct MacAudioInputDevice: Identifiable, Sendable {
    let priorityDevice: MicrophonePriorityDevice
    let audioDeviceID: AudioDeviceID
    let isSystemDefault: Bool

    var id: String { priorityDevice.id }
}

enum MacAudioInputDevices {
    enum DeviceError: Error, LocalizedError {
        case enumerationFailed(OSStatus)
        case audioUnitUnavailable
        case bindingFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .enumerationFailed(let status):
                return "Could not enumerate microphones (Core Audio \(status))."
            case .audioUnitUnavailable:
                return "The microphone audio unit is unavailable."
            case .bindingFailed(let status):
                return "Could not select the preferred microphone (Core Audio \(status))."
            }
        }
    }

    static func available() throws -> [MacAudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { throw DeviceError.enumerationFailed(status) }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { throw DeviceError.enumerationFailed(status) }

        let defaultID = systemDefaultInputDeviceID()
        return deviceIDs.compactMap { deviceID in
            guard uint32Property(kAudioDevicePropertyDeviceIsAlive, deviceID: deviceID) == 1,
                  hasInputStreams(deviceID),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID),
                  !uid.isEmpty
            else { return nil }

            let name = stringProperty(kAudioObjectPropertyName, deviceID: deviceID) ?? uid
            let transport = uint32Property(
                kAudioDevicePropertyTransportType,
                deviceID: deviceID
            )
            return MacAudioInputDevice(
                priorityDevice: MicrophonePriorityDevice(
                    id: uid,
                    name: name,
                    kind: microphoneKind(transport: transport)
                ),
                audioDeviceID: deviceID,
                isSystemDefault: deviceID == defaultID
            )
        }
        .sorted { lhs, rhs in
            if lhs.isSystemDefault != rhs.isSystemDefault {
                return lhs.isSystemDefault
            }
            return lhs.priorityDevice.name.localizedStandardCompare(
                rhs.priorityDevice.name
            ) == .orderedAscending
        }
    }

    static func bind(_ device: MacAudioInputDevice, to engine: AVAudioEngine) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw DeviceError.audioUnitUnavailable
        }
        var deviceID = device.audioDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw DeviceError.bindingFailed(status) }
    }

    private static func systemDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        )
        return status == noErr && dataSize >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }

    private static func uint32Property(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private static func microphoneKind(transport: UInt32?) -> MicrophoneDeviceKind {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return .virtual
        default:
            return .other
        }
    }
}
