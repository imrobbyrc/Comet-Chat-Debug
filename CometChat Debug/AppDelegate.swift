//
//  AppDelegate.swift
//  CometChat Debug
//
//  Created by Robby Chandra on 12/08/24.
//

import UIKit
import CallKit
import PushKit
import CometChatCallsSDK
import CometChatSDK
import SwiftyUserDefaults

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

	let cometChatCallUtils = CometChatCallUtils()

	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
	) -> Bool {
		// Override point for customization after application launch.

		UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .alert, .sound]) {
			granted, _ in
			if granted {
				UNUserNotificationCenter.current().delegate = self
			}
		}
		application.registerForRemoteNotifications()

		CometChatSDKUtils.initiate()
		cometChatCallUtils.configureVoip(application: application, delegate: self)

		return true
	}

	// MARK: UISceneSession Lifecycle

	func application(
		_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
		options: UIScene.ConnectionOptions
	) -> UISceneConfiguration {
		// Called when a new scene session is being created.
		// Use this method to select a configuration to create the new scene with.
		return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
	}

	func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
		// Called when the user discards a scene session.
		// If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
		// Use this method to release any resources that were specific to the discarded scenes, as they will not return.
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (
			UNNotificationPresentationOptions
		) -> Void
	) {

		let userInfo = notification.request.content.userInfo

		if let cometUserInfo = userInfo as? [String: Any],
			CometChatSDKUtils.isCometChatNotification(userInfo: cometUserInfo)
		{
			UIApplication.shared.applicationIconBadgeNumber += 1
			completionHandler([.alert, .sound, .badge])
			return
		}
		completionHandler([.alert, .sound, .badge])
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {

		guard let userInfo = response.notification.request.content.userInfo as? [String: Any] else {
			return
		}

		if CometChatSDKUtils.isCometChatNotification(userInfo: userInfo),
			let controller = getVisibleController()
		{
			CometChatSDKUtils.handleNotification(userInfo: userInfo, controller: controller)
			completionHandler()
			return
		}
		completionHandler()
	}

    func getVisibleController() -> UIViewController? {
        var topController: UIViewController?

        let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate
        topController = sceneDelegate?.window?.rootViewController

        guard let tabBarController = topController as? UITabBarController else {
            return nil
        }

        if let navigationController = tabBarController.selectedViewController as? UINavigationController {
            return navigationController.visibleViewController
        }

        return topController
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {

        var token = ""
        for i in 0..<deviceToken.count {
            token += String(format: "%02.2hhx", arguments: [deviceToken[i]])
        }

        Defaults.deviceToken = token

        if !token.isEmpty {
            CometChatSDKUtils.registerToken()
        }
    }

}


extension AppDelegate: PKPushRegistryDelegate, CXProviderDelegate {

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let deviceToken = pushCredentials.token.reduce("", { $0 + String(format: "%02X", $1) })
        Defaults.voipToken = deviceToken
        CometChatCallUtils.registerForVoIPCalls()
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        let provider = cometChatCallUtils.didReceiveIncomingPushWith(payload: payload)
        provider?.setDelegate(self, queue: nil)
        completion()
    }

    func providerDidReset(_ provider: CXProvider) {
        cometChatCallUtils.onProviderDidReset(provider: provider)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        cometChatCallUtils.onAnswerCallAction(action: action)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        cometChatCallUtils.onEndCallAction(action: action)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        CometChatCalls.audioMuted(action.isMuted)
        action.fulfill()
    }
}
