// swiftlint:disable line_length

import UIKit
import Foundation
import StoreKit
import GameController
import Combine

/// The primary class for integrating Superwall into your application. It provides access to all its featured via static functions and variables.
public final class Paywall: NSObject {
  // MARK: - Public Properties
  /// The delegate of the Paywall instance. The delegate is responsible for handling callbacks from the SDK in response to certain events that happen on the paywall.
  @objc public static var delegate: PaywallDelegate?

  /// Properties stored about the user, set using ``Paywall/Paywall/setUserAttributes(_:)``.
  public static var userAttributes: [String: Any] {
    return IdentityManager.shared.userAttributes
  }

  /// The presented paywall view controller.
  @MainActor
  public static var presentedViewController: UIViewController? {
    return PaywallManager.shared.presentedViewController
  }

  /// A convenience variable to access and change the paywall options that you passed to ``configure(apiKey:userId:delegate:options:)``.
  public static var options: PaywallOptions {
    return ConfigManager.shared.options
  }

  /// The ``PaywallInfo`` object of the most recently presented view controller.
  @MainActor
  public static var latestPaywallInfo: PaywallInfo? {
    let presentedPaywallInfo = PaywallManager.shared.presentedViewController?.paywallInfo
    return presentedPaywallInfo ?? shared.latestDismissedPaywallInfo
  }

  /// The ``PaywallInfo`` object stored from the latest paywall that was dismissed.
  var latestDismissedPaywallInfo: PaywallInfo?

  /// The current user's id.
  ///
  /// If you haven't called ``Paywall/Paywall/logIn(userId:)`` or ``Paywall/Paywall/createAccount(userId:)``,
  /// this value will return an anonymous user id which is cached to disk
  public static var userId: String {
    return IdentityManager.shared.userId
  }

  // MARK: - Internal Properties
  /// Used as the reload function if a paywall takes to long to load. set in paywall.present
  static var shared = Paywall(apiKey: nil)
  static var isFreeTrialAvailableOverride: Bool?

  /// Used as a strong reference to any track function that doesn't directly return a publisher.
  static var trackCancellable: AnyCancellable?

  /// The publisher from the last paywall presentation.
  var presentationPublisher: AnyCancellable?

  /// The request that triggered the last successful paywall presentation.
  var lastSuccessfulPresentationRequest: PaywallPresentationRequest?
  var presentingWindow: UIWindow?
  var didTryToAutoRestore = false
  var paywallWasPresentedThisSession = false

  @MainActor
  var paywallViewController: SWPaywallViewController? {
    return PaywallManager.shared.presentedViewController
  }

  var recentlyPresented = false {
    didSet {
      guard recentlyPresented else {
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) {
        self.recentlyPresented = false
      }
    }
  }

  @MainActor
  var isPaywallPresented: Bool {
    return paywallViewController != nil
  }

  /// Indicates whether the user has an active subscription. Performed on the main thread.
  var isUserSubscribed: Bool {
    // Prevents deadlock when calling from main thread
    if Thread.isMainThread {
      return Paywall.delegate?.isUserSubscribed() ?? false
    }

    var isSubscribed = false

    let dispatchGroup = DispatchGroup()
    dispatchGroup.enter()

    onMain {
      isSubscribed = Paywall.delegate?.isUserSubscribed() ?? false
      dispatchGroup.leave()
    }

    dispatchGroup.wait()
    return isSubscribed
  }
  private static var hasCalledConfig = false

  // MARK: - Private Functions
  private override init() {}

  private init(
    apiKey: String?,
    delegate: PaywallDelegate? = nil,
    options: PaywallOptions? = nil
  ) {
    super.init()
    guard let apiKey = apiKey else {
      return
    }
    ConfigManager.shared.setOptions(options)
    Storage.shared.configure(apiKey: apiKey)

    // Initialise session events manager and app session manager on main thread
    _ = SessionEventsManager.shared
    _ = AppSessionManager.shared

    if delegate != nil {
      Self.delegate = delegate
    }

    SKPaymentQueue.default().add(self)
    Storage.shared.recordAppInstall()
    Task {
      await ConfigManager.shared.fetchConfiguration()
      await IdentityManager.shared.configure()
    }
  }

  // MARK: - Public Functions
  /// Configures a shared instance of ``Paywall/Paywall`` for use throughout your app.
  ///
  /// Call this as soon as your app finishes launching in `application(_:didFinishLaunchingWithOptions:)`. For a tutorial on the best practices for implementing the delegate, we recommend checking out our <doc:GettingStarted> article.
  /// - Parameters:
  ///   - apiKey: Your Public API Key that you can get from the Superwall dashboard settings. If you don't have an account, you can [sign up for free](https://superwall.com/sign-up).
  ///   - userId: Your user's unique identifier, as defined by your backend system. If you don't specify a `userId`, we'll create one for you. Calling ``Paywall/Paywall/identify(userId:)`` later on will automatically alias these two for simple reporting.
  ///   - delegate: A class that conforms to ``PaywallDelegate``. The delegate methods receive callbacks from the SDK in response to certain events on the paywall.
  ///   - options: A ``PaywallOptions`` object which allows you to customise the appearance and behavior of the paywall.
  /// - Returns: The newly configured ``Paywall/Paywall`` instance.
  @discardableResult
  @objc public static func configure(
    apiKey: String,
    delegate: PaywallDelegate? = nil,
    options: PaywallOptions? = nil
  ) -> Paywall {
    if hasCalledConfig {
      Logger.debug(
        logLevel: .warn,
        scope: .paywallCore,
        message: "Paywall.configure called multiple times. Please make sure you only call this once on app launch. Use Paywall.reset() and Paywall.identify(userId:) if you're looking to reset the userId when a user logs out."
      )
      return shared
    }
    hasCalledConfig = true
    shared = Paywall(
      apiKey: apiKey,
      delegate: delegate,
      options: options
    )
    return shared
  }

  /// Preloads all paywalls that the user may see based on campaigns and triggers turned on in your Superwall dashboard.
  ///
  /// To use this, first set ``PaywallOptions/shouldPreloadPaywalls``  to `false` when configuring the SDK. Then call this function when you would like preloading to begin.
  ///
  /// Note: This will not reload any paywalls you've already preloaded via ``Paywall/Paywall/preloadPaywalls(forTriggers:)``.
  @objc public static func preloadAllPaywalls() {
    ConfigManager.shared.preloadAllPaywalls()
  }

  /// Preloads paywalls for specific trigger names.
  ///
  /// To use this, first set ``PaywallOptions/shouldPreloadPaywalls``  to `false` when configuring the SDK. Then call this function when you would like preloading to begin.
  ///
  /// Note: This will not reload any paywalls you've already preloaded.
  @objc public static func preloadPaywalls(forTriggers triggers: Set<String>) {
    Task {
      await ConfigManager.shared.preloadPaywalls(forTriggers: triggers)
    }
  }
}

// MARK: - Gamepad
extension Paywall {
	/// Forwards Game controller events to the paywall.
  ///
  /// Call this in Gamepad's `valueChanged` function to forward game controller events to the paywall via `paywall.js`
  ///
  /// See <doc:GameControllerSupport> for more information.
  ///
  /// - Parameters:
  ///   - gamepad: The extended Gamepad controller profile.
  ///   - element: The game controller element.
	public static func gamepadValueChanged(
    gamepad: GCExtendedGamepad,
    element: GCControllerElement
  ) {
		GameControllerManager.shared.gamepadValueChanged(gamepad: gamepad, element: element)
	}

	// TODO: create debugger manager class

	/// Overrides the default device locale for testing purposes.
  ///
  /// You can also preview your paywall in different locales using the in-app debugger. See <doc:InAppPreviews> for more.
	///  - Parameter localeIdentifier: The locale identifier for the language you would like to test.
	public static func localizationOverride(localeIdentifier: String? = nil) {
		LocalizationManager.shared.selectedLocale = localeIdentifier
	}

  /// Attemps to implicitly trigger a paywall for a given analytical event.
  ///
  ///  - Parameters:
  ///     - event: The data of an analytical event data that could trigger a paywall.
  @MainActor
  func handleImplicitTrigger(forEvent event: EventData) async {
    await IdentityManager.hasIdentity.async()

    let presentationInfo: PresentationInfo = .implicitTrigger(event)

    let outcome = PaywallLogic.canTriggerPaywall(
      eventName: event.name,
      triggers: Set(ConfigManager.shared.triggers.keys),
      isPaywallPresented: isPaywallPresented
    )

    switch outcome {
    case .deepLinkTrigger:
      if isPaywallPresented {
        await Paywall.dismiss()
      }
      let presentationRequest = PaywallPresentationRequest(presentationInfo: presentationInfo)
      await Paywall.shared.internallyPresent(presentationRequest)
        .asyncNoValue()
    case .triggerPaywall:
      // delay in case they are presenting a view controller alongside an event they are calling
      let twoHundredMilliseconds = UInt64(200_000_000)
      try? await Task.sleep(nanoseconds: twoHundredMilliseconds)
      let presentationRequest = PaywallPresentationRequest(presentationInfo: presentationInfo)
      await Paywall.shared.internallyPresent(presentationRequest)
        .asyncNoValue()
    case .disallowedEventAsTrigger:
      Logger.debug(
        logLevel: .warn,
        scope: .paywallCore,
        message: "Event Used as Trigger",
        info: ["message": "You can't use events as triggers"],
        error: nil
      )
    case .dontTriggerPaywall:
      return
    }
	}
}

// MARK: - SWPaywallViewControllerDelegate
extension Paywall: SWPaywallViewControllerDelegate {
  @MainActor
  func eventDidOccur(
    paywallViewController: SWPaywallViewController,
    result: PaywallPresentationResult
  ) {
		// TODO: log this
    switch result {
    case .closed:
      self.dismiss(
        paywallViewController,
        state: .closed
      )
    case .initiatePurchase(let productId):
      guard let product = StoreKitManager.shared.productsById[productId] else {
        return
      }
      paywallViewController.loadingState = .loadingPurchase
      Paywall.delegate?.purchase(product: product)
    case .initiateRestore:
      self.tryToRestore(
        paywallViewController,
        userInitiated: true
      )
    case .openedURL(let url):
      Paywall.delegate?.willOpenURL?(url: url)
    case .openedUrlInSafari(let url):
      Paywall.delegate?.willOpenURL?(url: url)
    case .openedDeepLink(let url):
      Paywall.delegate?.willOpenDeepLink?(url: url)
    case .custom(let string):
      Paywall.delegate?.handleCustomPaywallAction?(withName: string)
    }
	}

  // MARK: - Unavailable methods
  @available(*, unavailable, renamed: "configure(apiKey:delegate:options:)")
  @discardableResult
  @objc public static func configure(
    apiKey: String,
    userId: String?,
    delegate: PaywallDelegate? = nil,
    options: PaywallOptions? = nil
  ) -> Paywall {
    return shared
  }

  /// Links a `userId` to Superwall's automatically generated alias. Call this as soon as you have a userId. If a user with a different id was previously identified, calling this will automatically call `Paywall.reset()`
  ///  - Parameter userId: Your user's unique identifier, as defined by your backend system.
  ///  - Returns: The shared Paywall instance.
  @available(*, unavailable, message: "Please use login(userId:) or createAccount(userId:).")
  @discardableResult
  @objc public static func identify(userId: String) -> Paywall {
    return shared
  }
}
