//
//  IconAnimator.swift
//  AnimatedAppIcons
//
//  Created by Bryce Bostwick on 5/25/24.
//

import Foundation
import QuartzCore
import AVFoundation

class IconAnimator {

    /// How many frames the animation has
    private let numberOfFrames: Int

    /// The number of times to loop the animation
    private let numberOfLoops: Int

    /// What FPS to animate at
    private let targetFramesPerSecond: CGFloat

    /// Whether or not the animation should run by blocking the main queue.
    /// This may give better performance (at the expense of not being able to do
    /// much else while the animation is happening)
    private let shouldRunOnMainThread: Bool

    /// The `LSApplicationProxy` used to set the application icon
    private let appProxy: LSApplicationProxy = LSBundleProxy.bundleProxyForCurrentProcess()

    /// The time at which our animated started
    private var animationStartTime: CFTimeInterval = 0

    /// The number of times the animation has looped already
    private var currentLoopCount = 0

    /// Stores the completion block passed to `startAnimation`
    private var completion: (() -> Void)? = nil

    /// Whether or not this animation has been cancelled
    private var isCancelled = false
    
    private var audioPlayer: AVAudioPlayer?

    init(numberOfFrames: Int,
         numberOfLoops: Int = 1,
         targetFramesPerSecond: CGFloat = 30,
         shouldRunOnMainThread: Bool = false) {
        self.numberOfFrames = numberOfFrames
        self.targetFramesPerSecond = targetFramesPerSecond
        self.shouldRunOnMainThread = shouldRunOnMainThread
        self.numberOfLoops = numberOfLoops
        configureAudioSession()
    }

    /// Starts a new app icon animation. Can be called multiple times.
    func startAnimation(completion: (() -> Void)? = nil) {
        // Set/reset properties
        animationStartTime = CACurrentMediaTime()
        currentLoopCount = 0
        isCancelled = false
        self.completion = completion
        
        playAudio()

        // Start the animation, either using the main thread loop
        // or timer, depending on configuration
        if shouldRunOnMainThread {
            startAnimationOnMainThread()
            
        } else {
            startAnimationUsingTimer()
        }
    }

    /// Cancel the current animation, if any
    func cancel() {
        isCancelled = true
        audioPlayer?.stop()
        completion?()
    }

    /// Runs the icon animation using a `CFRunLoopTimer`
    private func startAnimationUsingTimer() {
        // Calcualte the duration of each frame, in seconds
        let frameDuration = 1.0 / targetFramesPerSecond

        // Calculate the time when we should start our timer.
        // This is set to be halfway through the next frame interval,
        // so that when we try to determine what frame we're on,
        // we're well in the middle of a frame range
        let startTime = animationStartTime + (frameDuration / 2)

        // Create a timer to run every frame
        let timer = CFRunLoopTimerCreateWithHandler(
            /* allocator: */ kCFAllocatorDefault,
            /* fireDate: */ startTime,
            /* interval: */ frameDuration,
            /* flags: */ 0,
            /* order */ 0
        ) { [weak self] timer in
            guard let self else {
                return
            }

            // If our animation was cancelled,
            // invalidate our timer and do nothing
            if isCancelled {
                CFRunLoopTimerInvalidate(timer)
            }

            // On every frame, update our icon
            let shouldContinue = self.updateFrame()

            // If we've reached our last frame,
            // invalidate the timer and call our completion block
            if (!shouldContinue) {
                CFRunLoopTimerInvalidate(timer)
                self.completion?()
            }
        }

        // Start the timer
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, CFRunLoopMode.commonModes)
    }

    /// Runs the icon animation using a loop on the main thread
    /// (sometimes better performance than `startAnimationUsingTimer`,
    /// at the expense of not being able to do other work while animating)
    private func startAnimationOnMainThread() {
        // Calculate the duration of each frame, in seconds
        let frameDuration = 1.0 / targetFramesPerSecond

        // Store the time at which we last updated the frame
        // (starting with 0, meaning we're ready to show the
        // first frame immediately)
        var lastFrameTime: CFTimeInterval = 0

        DispatchQueue.main.async {
            while (true) {
                // If our animation has been cancelled,
                // break out of our loop immediately
                if self.isCancelled {
                    break
                }

                // Check if it's been at least one frame
                // since the last time we updated our icon
                // (otherwise, just sleep)
                let currentTime = CACurrentMediaTime()
                if currentTime - lastFrameTime < frameDuration {
                    Thread.sleep(forTimeInterval: 0.001)
                    continue
                }

                // Mark the current time so that we can
                // figure out when we need to show the next frame
                lastFrameTime = currentTime

                // If we've reached our last frame,
                // call our completion block and break
                // out of our loop
                let shouldContinue = self.updateFrame()
                if (!shouldContinue) {
                    self.completion?()
                    break
                }
            }
        }
    }

    /**
     Updates the app icon based to the current frame of the animation
     based on the current time.

     - returns A boolean value indicating whether this animation still has more frames to display
     */
    private func updateFrame() -> Bool {
        // Determine the frame we _should_ be showing based on the current time
        let timeSinceStart = CACurrentMediaTime() - animationStartTime
        let totalFramesPassed = Int(timeSinceStart * targetFramesPerSecond)
        let currentFrame = totalFramesPassed % numberOfFrames

        // Determine the name of the icon to show
        let iconName = String(format: "ba_%05d", currentFrame + 1)

        print(iconName)

        // Use `LSApplicationProxy.setAlternateIconName` to update our icon
        appProxy.setAlternateIconName(iconName) { success, error in
            if !success || error != nil {
                print("Error: \(error as Any)")
                return
            }
        }

        // If we've reached the end of a loop...
        if totalFramesPassed >= numberOfFrames {
            // Check if we've looped as many times as we'd like.
            // If so, return `false` to indicate that we're done animating
            if currentLoopCount >= numberOfLoops - 1 {
                return false
            }

            // Increment the loop count
            currentLoopCount += 1

            // Update the animation start time to the beginning of the next loop
            animationStartTime = CACurrentMediaTime()
        }

        return true
    }

    private func playAudio() {
            guard let audioPath = Bundle.main.path(forResource: "bad_apple", ofType: "wav") else {
                print("Audio file not found")
                return
            }

            let audioURL = URL(fileURLWithPath: audioPath)
            
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                audioPlayer?.numberOfLoops = numberOfLoops
                audioPlayer?.play()
            } catch {
                print("Error loading audio file: \(error)")
            }
        }
    
    private func configureAudioSession() {
            let audioSession = AVAudioSession.sharedInstance()
            
            do {
                try audioSession.setCategory(.playback, mode: .default)
                try audioSession.setActive(true)
            } catch {
                print("Failed to set audio session category: \(error)")
            }
        }
}
