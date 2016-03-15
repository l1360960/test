//
//  MovieOverviewControl.swift
//  LoveLiver
//
//  Created by BAN Jun on 2016/03/15.
//  Copyright © 2016年 mzp. All rights reserved.
//

import Cocoa
import AVFoundation
import Ikemen


private let overviewHeight: CGFloat = 64


class MovieOverviewControl: NSView {
    var player: AVPlayer? {
        willSet {
            guard let playerTimeObserver = playerTimeObserver else { return }
            player?.removeTimeObserver(playerTimeObserver)
        }
        didSet {
            reload()
            observePlayer()
        }
    }
    var playerTimeObserver: AnyObject?
    var currentTimePercent: CGFloat? {
        didSet {
            // FIXME: redraw only dirty rect
            setNeedsDisplayInRect(bounds)
        }
    }
    var imageGenerator: AVAssetImageGenerator?
    var numberOfPages: UInt = 0 {
        didSet { setNeedsDisplayInRect(bounds) }
    }
    var thumbnails = [NSImage]()

    init(player: AVPlayer) {
        self.player = player
        
        super.init(frame: NSZeroRect)

        setContentCompressionResistancePriority(NSLayoutPriorityDefaultHigh, forOrientation: .Vertical)
        setContentHuggingPriority(NSLayoutPriorityDefaultHigh, forOrientation: .Vertical)

        observePlayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        return nil
    }

    override var intrinsicContentSize: NSSize {
        return CGSize(width: NSViewNoIntrinsicMetric, height: overviewHeight)
    }

    func reload() {
        imageGenerator?.cancelAllCGImageGeneration()
        imageGenerator = nil
        thumbnails.removeAll()

        guard let item = player?.currentItem,
            let track = item.asset.tracksWithMediaType(AVMediaTypeVideo).first else {
                numberOfPages = 0
                return
        }

        // each page preserves aspect ratio of video and varies number of pages so that fill self.bounds.width
        let pageSize = NSSize(width: bounds.height / track.naturalSize.height * track.naturalSize.width, height: bounds.height)
        numberOfPages = UInt(ceil(bounds.width / pageSize.width))
        let duration = item.duration
        let times: [CMTime] = (0..<numberOfPages).map { i in
            CMTime(value: duration.value * Int64(i) / Int64(numberOfPages), timescale: duration.timescale)
        }

        // generate thumbnails for each page in background
        let generator = AVAssetImageGenerator(asset: item.asset) ※ {
            $0.maximumSize = pageSize
        }
        imageGenerator = generator
        generator.generateCGImagesAsynchronouslyForTimes(times.map {NSValue(CMTime: $0)}) { (requestedTime, cgImage, actualTime, result, error) -> Void in
            guard let cgImage = cgImage where result == .Succeeded else { return }

            let thumb = NSImage(CGImage: cgImage, size: NSZeroSize)

            dispatch_async(dispatch_get_main_queue()) {
                guard self.imageGenerator === generator else { return } // avoid appending result from outdated requests
                self.thumbnails.append(thumb)
                self.setNeedsDisplayInRect(self.bounds)
            }
        }
    }

    func observePlayer() {
        if let playerTimeObserver = playerTimeObserver {
            player?.removeTimeObserver(playerTimeObserver)
        }

        if  let player = player,
            let item = player.currentItem {
                playerTimeObserver = player.addPeriodicTimeObserverForInterval(CMTime(value: 1, timescale: 30), queue: dispatch_get_main_queue()) { [weak self] time in
                    let duration = item.duration
                    self?.currentTimePercent =
                        CGFloat(time.convertScale(duration.timescale, method: CMTimeRoundingMethod.Default).value)
                        / CGFloat(duration.value)
                }
        }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()

        reload()
    }

    override func drawRect(dirtyRect: NSRect) {
        NSColor.blackColor().setFill()
        NSRectFillUsingOperation(dirtyRect, .CompositeCopy)

        let cellWidth = bounds.width / CGFloat(numberOfPages)
        for (i, t) in thumbnails.enumerate() {
            let pageRect = NSRect(x: CGFloat(i) * cellWidth, y: 0, width: cellWidth, height: bounds.height)
            t.drawInRect(pageRect)
        }

        if let currentTimePercent = currentTimePercent {
            NSColor.redColor().setFill()
            NSRectFillUsingOperation(NSRect(x: currentTimePercent * bounds.width, y: 0, width: 1, height: bounds.height), .CompositeCopy)
        }
    }

    override func mouseDown(theEvent: NSEvent) {
        guard let item = player?.currentItem else { return }
        let duration = item.duration

        let p = convertPoint(theEvent.locationInWindow, fromView: nil)
        let time = CMTime(value: Int64(CGFloat(duration.value) * p.x / bounds.width), timescale: duration.timescale)
        player?.seekToTime(time)
    }
}