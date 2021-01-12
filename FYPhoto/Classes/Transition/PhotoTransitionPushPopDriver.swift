//
//  PhotoTransitionDriver.swift
//  FYPhoto
//
//  Created by xiaoyang on 2020/9/1.
//

import Foundation

class PhotoTransitionDriver: TransitionDriver {
    var transitionAnimator: UIViewPropertyAnimator!
    var isInteractive: Bool {
        return transitionContext.isInteractive
    }
    let transitionContext: UIViewControllerContextTransitioning
    let isPresenting: Bool
    let isNavigationAnimation: Bool
    
    private let duration: TimeInterval
    private var itemFrameAnimator: UIViewPropertyAnimator?
    var fromAssetTransitioning: PhotoTransitioning?
    var toAssetTransitioning: PhotoTransitioning?

    var toView: UIView?
    var fromView: UIView?

    var visualEffectView = UIVisualEffectView()

    /// The snapshotView that is animating between the two view controllers.
    fileprivate let transitionImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.accessibilityIgnoresInvertColors = true
        return imageView
    }()

    // MARK: Initialization

    init(isPresenting: Bool, isNavigationAnimation: Bool, context: UIViewControllerContextTransitioning, duration: TimeInterval) {
        self.transitionContext = context
        self.isPresenting = isPresenting
        self.duration = duration
        self.isNavigationAnimation = isNavigationAnimation
        
        setup(context)
    }

    func setup(_ context: UIViewControllerContextTransitioning) {
        // Setup the transition "chrome"
        guard
            let fromViewController = context.viewController(forKey: .from),
            let toViewController = context.viewController(forKey: .to)
        else {
            return
        }
        self.fromAssetTransitioning = fromViewController as? PhotoTransitioning
        self.toAssetTransitioning = toViewController as? PhotoTransitioning
        if isNavigationAnimation {
            let fromView = context.view(forKey: .from)
            self.fromView = fromView
            let toView = context.view(forKey: .to)
            self.toView = toView
        } else {
            let toView = context.view(forKey: .to)
            self.toView = toView            
        }

//        self.fromAssetTransitioning = fromAssetTransitioning
//        self.toAssetTransitioning = toAssetTransitioning
//        self.toView = toView
//        self.fromView = fromView

        let containerView = context.containerView

        // Create a visual effect view and animate the effect in the transition animator
        let effect: UIVisualEffect? = !isPresenting ? UIBlurEffect(style: .extraLight) : nil
        let targetEffect: UIVisualEffect? = !isPresenting ? nil : UIBlurEffect(style: .light)
        //        let visualEffectView = UIVisualEffectView(effect: effect)
        visualEffectView.effect = effect
        visualEffectView.frame = containerView.bounds
        visualEffectView.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        containerView.addSubview(visualEffectView)

        // Insert the toViewController's view into the transition container view
        var topView: UIView?
        var topViewTargetAlpha: CGFloat = 0.0
        if isPresenting {
            topView = toView
            topViewTargetAlpha = 1.0
            if let to = toView {
                to.alpha = 0.0
                containerView.addSubview(to)
            }
        } else {
            topView = fromView
            topViewTargetAlpha = 0.0
            if let to = toView {
                containerView.insertSubview(to, at: 0)
            }
        }

        // Ensure the toView has the correct size and position
        toView?.frame = context.finalFrame(for: toViewController)

        if let fromImage = fromAssetTransitioning?.referenceImage() {
            transitionImageView.image = fromImage
        }

        if let frame = fromAssetTransitioning?.imageFrame() {
            transitionImageView.frame = frame
        }

        containerView.addSubview(transitionImageView)

        // Inform the view controller's the transition is about to start
        fromAssetTransitioning?.transitionWillStart()
        toAssetTransitioning?.transitionWillStart()

        // Create a UIViewPropertyAnimator that lives the lifetime of the transition
        let spring = CGFloat(0.95)
        transitionAnimator = UIViewPropertyAnimator(duration: duration, dampingRatio: spring) {
            topView?.alpha = topViewTargetAlpha
            self.visualEffectView.effect = targetEffect
        }

        if transitionAnimator.state == .inactive {
            transitionAnimator.startAnimation()
        }

        if !isPresenting {
            // HACK: By delaying 0.005s, I get a layout-refresh on the toViewController,
            // which means its collectionview has updated its layout,
            // and our toAssetTransitioning?.imageFrame() is accurate, even if
            // the device has rotated.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
                self.transitionAnimator.addAnimations {
                    if let imageFrame = self.toAssetTransitioning?.imageFrame() {
                        self.transitionImageView.frame = imageFrame
                    }
                }
            }
        } else {
            transitionAnimator.addAnimations {
                if let referencedImage = self.fromAssetTransitioning?.referenceImage(),
                    let toView = self.toView {
                    let toReferenceFrame = Self.calculateZoomInImageFrame(image: referencedImage, forView: toView)
                    self.transitionImageView.frame = toReferenceFrame
                }
            }
        }

        transitionAnimator.addCompletion { _ in
            // Finish the protocol handshake
            self.fromAssetTransitioning?.transitionDidEnd()
            self.toAssetTransitioning?.transitionDidEnd()
            // Remove transition views
            self.transitionImageView.image = nil
            self.transitionImageView.removeFromSuperview()
            self.visualEffectView.removeFromSuperview()

            self.transitionContext.finishInteractiveTransition()
            self.transitionContext.completeTransition(true)
        }
    }
}
