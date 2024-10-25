import Foundation
import KrispNoiseFilter
import LiveKit

enum LiveKitKrispNoiseFilterError: Error {
    case globalInitializationFailed
}

public class LiveKitKrispNoiseFilter: @unchecked Sendable {
    public var isEnabled: Bool {
        get { _state.isEnabled }
        set { _state.mutate { $0.isEnabled = newValue } }
    }
    public var didFailToInitialize: Bool {
        _state.didFailToInitialize
    }
    public var failedToProcessChannels: [Int] {
        _state.channelsFailed.sorted()
    }

    private let krisp = KrispNoiseFilter()

    private struct State {
        var isEnabled: Bool = true
        var isInitializedWithRate: Int?
        var didFailToInitialize: Bool = false
        var channelsFailed: Set<Int> = []
    }

    private let _state = StateSync(State())

    public init() {
        // This should never fail
        if !KrispNoiseFilter.krispGlobalInit() {
            _state.mutate { $0.didFailToInitialize = true }
        }
    }
}

extension LiveKitKrispNoiseFilter: AudioCustomProcessingDelegate {
    public var audioProcessingName: String { kLiveKitKrispAudioProcessorName }

    // This will be invoked anytime sample rate changes, for example switching Speaker <-> AirPods.
    public func audioProcessingInitialize(sampleRate sampleRateHz: Int, channels: Int) {
        let isFirstInitialize = _state.mutate {
            let result = $0.isInitializedWithRate == nil
            $0.isInitializedWithRate = sampleRateHz
            return result
        }

        if isFirstInitialize {
            krisp.initialize(Int32(sampleRateHz), numChannels: Int32(channels))
        } else {
            // Krisp already initialized, reset with new sample rate.
            krisp.reset(Int32(sampleRateHz))
        }
    }

    public func audioProcessingProcess(audioBuffer: LiveKit.LKAudioBuffer) {
        guard _state.isEnabled else { return }

        for channel in 0 ..< audioBuffer.channels {
            let result = krisp.process(withBands: Int32(audioBuffer.bands),
                                       frames: Int32(audioBuffer.frames),
                                       bufferSize: Int32(audioBuffer.framesPerBand),
                                       buffer: audioBuffer.rawBuffer(forChannel: channel))
            if !result {
                _state.mutate { state in
                    state.channelsFailed.insert(channel)
                }
            }
        }
    }

    public func audioProcessingRelease() {
        print("LiveKitKrispNoiseFilter Release")
    }
}

extension LiveKitKrispNoiseFilter: RoomDelegate {
    public func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        krisp.update(room.toContext(connectionState))
    }
}

extension Room {
    func toContext(_ connectionState: ConnectionState) -> LiveKitRoomContext {
        LiveKitRoomContext(sid: sid?.stringValue,
                           name: name,
                           serverVersion: serverVersion,
                           serverRegion: serverRegion,
                           serverNodeId: serverNodeId,
                           connectionState: LiveKitConnectionState(rawValue: connectionState.rawValue) ?? .Disconnected,
                           url: url,
                           token: token)
    }
}
