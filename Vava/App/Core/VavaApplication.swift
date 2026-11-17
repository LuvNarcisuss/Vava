import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main @MainActor final class VavaApplication: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var reactDelegate: VavaReactDelegate?
    private var reactFactory: RCTReactNativeFactory?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let delegate = VavaReactDelegate()
        delegate.dependencyProvider = RCTAppDependencyProvider()
        let factory = RCTReactNativeFactory(delegate: delegate)
        reactDelegate = delegate
        reactFactory = factory
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        factory.startReactNative(withModuleName: "Vava", in: window, launchOptions: options)
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        VavaNative.shared?.suspend()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        VavaNative.shared?.resume()
    }
}

final class VavaReactDelegate: RCTDefaultReactNativeFactoryDelegate {
    override func sourceURL(for bridge: RCTBridge) -> URL? { bundleURL() }

    override func bundleURL() -> URL? {
        #if DEBUG
            if Bundle.main.object(forInfoDictionaryKey: "VavaUseBundledJavaScript") as? Bool == true {
                return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
            }
            return RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
        #else
            return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
        #endif
    }
}
