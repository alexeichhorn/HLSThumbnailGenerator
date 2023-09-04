//
//  ThumbnailGenerator.swift
//
//  Copyright (c) 2019 Todd Kramer (http://www.tekramer.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import AVFoundation
import CoreImage

public final class ThumbnailGenerator: AVAssetImageGenerator {

    private enum PlayerState {
        case loading
        case ready
    }

    private(set) var times: [Double] = []

    var player: AVPlayer!
    private var observer: NSKeyValueObservation?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var playerState: PlayerState = .loading {
        didSet {
            guard playerState == .ready, !times.isEmpty else { return }
			generateNextThumbnail(completionHandler: { _, _, _ in })

        }
    }

    private let mainQueue: Dispatching
    private let backgroundQueue: Dispatching

    init(asset: AVAsset, mainQueue: Dispatching, backgroundQueue: Dispatching) {
        self.mainQueue = mainQueue
        self.backgroundQueue = backgroundQueue

		super.init(asset: asset)

        setup()
    }

	public convenience override init(asset: AVAsset) {
        let defaultBackgroundQueue = DispatchQueue(label: "com.thumbnail-generator.background")
        self.init(asset: asset, mainQueue: DispatchQueue.main, backgroundQueue: defaultBackgroundQueue)
    }

    // MARK: - Setup

    private func setup() {
        setupPlayer()
        setupObserver()
        setupVideoOutput()
    }

    private func setupPlayer() {
        let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: [])
        player = AVPlayer(playerItem: playerItem)
        player.rate = 0
    }

    private func setupObserver() {
        self.observer = player.currentItem?.observe(\.status, options:  [.new, .old]) { [weak self] (playerItem, change) in
            guard let self = self, case .readyToPlay = playerItem.status, self.playerState == .loading else  { return }
            self.playerState = .ready
        }
    }

    private func setupVideoOutput() {
        let settings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
        guard let videoOutput = videoOutput else { return }
        player.currentItem?.add(videoOutput)
    }

    // MARK: - Thumbnail Generation

	public override func generateCGImageAsynchronously(for requestedTime: CMTime, completionHandler handler: @escaping (CGImage?, CMTime, Error?) -> Void) {
		generateThumbnail(atTimeInSeconds: requestedTime.seconds, completionHandler: handler)
	}

	public override func generateCGImagesAsynchronously(forTimes requestedTimes: [NSValue], completionHandler handler: @escaping AVAssetImageGeneratorCompletionHandler) {
		generateThumbnails(atTimesInSeconds: requestedTimes.map { $0.timeValue.seconds }, completionHandler: {
			handler($1, $0, $1, $2 == nil ? .succeeded : .failed, $2)
		})
	}

    public func generateThumbnails(atTimesInSeconds times: [Double], completionHandler handler: @escaping (CGImage?, CMTime, Error?) -> Void) {
        self.times += times
        guard playerState == .ready else { return }
		backgroundQueue.async {
			self.generateNextThumbnail(completionHandler: handler)
		}
    }

    private func generateNextThumbnail(completionHandler handler: @escaping (CGImage?, CMTime, Error?) -> Void) {
        guard !times.isEmpty else { return }
        let time = times.removeFirst()
		generateThumbnail(atTimeInSeconds: time, completionHandler: handler)
    }

    private func generateThumbnail(atTimeInSeconds time: Double, completionHandler handler: @escaping (CGImage?, CMTime, Error?) -> Void) {
        let time = CMTime(seconds: time, preferredTimescale: 1)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] isFinished in
            guard let self = self else { return }
            guard isFinished else {
                self.mainQueue.async {
					handler(nil, time, ThumbnailGenerationError.seekInterrupted)
                }
				self.generateNextThumbnail(completionHandler: handler)
                return
            }
            self.backgroundQueue.delay(0.3) {
                self.didFinishSeeking(toTime: time, completionHandler: handler)
            }
        }
    }

    private func didFinishSeeking(toTime time: CMTime, completionHandler handler: @escaping (CGImage?, CMTime, Error?) -> Void) {
        guard let buffer = videoOutput?.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            mainQueue.async {
				handler(nil, time, ThumbnailGenerationError.copyPixelBufferFailed)
            }
            generateNextThumbnail(completionHandler: handler)
            return
        }
        processPixelBuffer(buffer, atTime: time.seconds, completionHandler: handler)
    }

    private func processPixelBuffer(_ buffer: CVPixelBuffer, atTime time: Double, completionHandler handler: @escaping (CGImage?, CMTime, Error?) -> Void) {
        defer {
			generateNextThumbnail(completionHandler: handler)
        }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let imageRect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        guard let videoImage = CIContext().createCGImage(ciImage, from: imageRect) else {
            mainQueue.async {
				handler(nil, CMTime(seconds: time, preferredTimescale: .max), ThumbnailGenerationError.imageCreationFailed)
            }
            return
        }
        mainQueue.async {
			handler(videoImage, CMTime(seconds: time, preferredTimescale: .max), nil)
        }
    }

}
