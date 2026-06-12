import AVFoundation
import Foundation

public struct MovieInfo: Sendable, Hashable {
    public let frameRate: Double
    public let durationSeconds: Double

    public init(frameRate: Double, durationSeconds: Double) {
        self.frameRate = frameRate
        self.durationSeconds = durationSeconds
    }
}

/// Source of movie metadata; the pipeline needs the frame rate for
/// frame-based ↔ time-based subtitle conversion.
public protocol MovieInfoProvider: Sendable {
    func movieInfo(for url: URL) async -> MovieInfo?
}

/// AVFoundation-backed provider (replaces legacy libmediainfo).
public struct AVFoundationMovieInfoProvider: MovieInfoProvider {
    public init() {}

    public func movieInfo(for url: URL) async -> MovieInfo? {
        let asset = AVURLAsset(url: url)
        guard
            let tracks = try? await asset.loadTracks(withMediaType: .video),
            let track = tracks.first,
            let frameRate = try? await track.load(.nominalFrameRate),
            let duration = try? await asset.load(.duration)
        else {
            return nil
        }
        return MovieInfo(frameRate: Double(frameRate), durationSeconds: duration.seconds)
    }
}
