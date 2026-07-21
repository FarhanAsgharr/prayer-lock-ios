import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Retained for the lifetime of the app so its method-call handler is not
  /// deallocated after registration.
  private var blockingChannel: AnyObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Wire the app-blocking channel. Screen Time is iOS 16+, so on older
    // versions the channel is simply not registered and the Dart layer's
    // MissingPluginException path treats blocking as unavailable — which is the
    // correct outcome, since the API does not exist there.
    if #available(iOS 16.0, *),
       let controller = window?.rootViewController as? FlutterViewController {
      let channel = BlockingChannel(controller: controller)
      channel.register(with: controller.binaryMessenger)
      blockingChannel = channel
    }
  }
}
