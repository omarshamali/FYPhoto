//
//  AssetTransitionController.swift
//  FYPhoto
//
//  Created by xiaoyang on 2020/8/27.
//

import Foundation

let assetTransitionDuration = 0.8

class AssetTransitionController: NSObject {
    weak var navigationController: UINavigationController?
    var operation: UINavigationController.Operation = .none
    var transitionDriver: AssetTransitionDriver?
    var initiallyInteractive = false
    var panGestureRecognizer: UIPanGestureRecognizer = UIPanGestureRecognizer()

    init(navigationController nc: UINavigationController) {
        navigationController = nc
        super.init()

        nc.delegate = self
        configurePanGestureRecognizer()
    }

    func configurePanGestureRecognizer() {
        panGestureRecognizer.delegate = self
        panGestureRecognizer.maximumNumberOfTouches = 1
        panGestureRecognizer.addTarget(self, action: #selector(initiateTransitionInteractively(_:)))
        navigationController?.view.addGestureRecognizer(panGestureRecognizer)

        guard let interactivePopGestureRecognizer = navigationController?.interactivePopGestureRecognizer else { return }
        panGestureRecognizer.require(toFail: interactivePopGestureRecognizer)
    }

    @objc func initiateTransitionInteractively(_ panGesture: UIPanGestureRecognizer) {
        if panGesture.state == .began && transitionDriver == nil {
            initiallyInteractive = true
            let _ = navigationController?.popViewController(animated: true)
        }
    }
}


extension AssetTransitionController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let transitionDriver = self.transitionDriver else {
            let translation = panGestureRecognizer.translation(in: panGestureRecognizer.view)
            let translationIsVertical = (translation.y > 0) && (abs(translation.y) > abs(translation.x))
            print(#function, translationIsVertical && (navigationController?.viewControllers.count ?? 0 > 1))
            return translationIsVertical && (navigationController?.viewControllers.count ?? 0 > 1)
        }

        print("transitionDriver.isInteractive = \(transitionDriver.isInteractive)")
        return transitionDriver.isInteractive
    }
}

extension AssetTransitionController: UINavigationControllerDelegate {

    internal func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        // Remember the direction of the transition (.push or .pop)
        self.operation = operation
        if fromVC is AssetTransitioning, operation == .push {
            return self
        } else if toVC is AssetTransitioning, operation == .pop {
            return self
        } else {
            return nil
        }
        // Return ourselves as the animation controller for the pending transition
//        return self
    }

    func navigationController(_ navigationController: UINavigationController, interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {

        // Return ourselves as the interaction controller for the pending transition
        return self
    }
}


extension AssetTransitionController: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        if operation == .push {
            return 0.4
        } else {
            return 0.38
        }
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        print(#function)
    }

    func animationEnded(_ transitionCompleted: Bool) {
        // Clean up our helper object and any additional state
        transitionDriver = nil
        initiallyInteractive = false
        operation = .none
    }

    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        // The transition driver (helper object), creates the UIViewPropertyAnimator (transitionAnimator)
        // to be used for this transition. It must live the lifetime of the transitionContext.
        return (transitionDriver?.transitionAnimator)!
    }
}

extension AssetTransitionController: UIViewControllerInteractiveTransitioning {
    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        // Create our helper object to manage the transition for the given transitionContext.
        transitionDriver = AssetTransitionDriver(operation: operation, context: transitionContext, panGestureRecognizer: panGestureRecognizer, duration: transitionDuration(using: transitionContext))
    }

    var wantsInteractiveStart: Bool {
        // Determines whether the transition begins in an interactive state
        return initiallyInteractive
    }
}
