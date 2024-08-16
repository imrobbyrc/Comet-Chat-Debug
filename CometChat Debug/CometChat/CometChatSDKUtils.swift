//
//  CometChatSDKUtils.swift
//  CometChat Debug
//
//  Created by Robby Chandra on 12/08/24.
//

import CometChatCallsSDK
import CometChatSDK
import CometChatUIKitSwift
import SwiftyUserDefaults

class CometChatSDKUtils {
    static var authKey: String {
        return "2fba227dd192d6d6d164b4b6096ec688ca0e680b"
    }

    static var appId: String {
        return "240025ca1c91e287"
    }

    static let region = "us"

    static func initiate() {
        let uikitSettings = UIKitSettings()
        uikitSettings.set(appID: appId)
            .set(authKey: authKey)
            .set(region: region)
            .autoEstablishSocketConnection(bool: false)
            .setExtensionGroupID(id: "group.com.pick.a.roo.ios")
            .build()

        CometChatUIKit(
            uiKitSettings: uikitSettings,
            result: { result in
                switch result {
                    case .success:
                        CometChat.setSource(resource: "uikit-v4", platform: "ios", language: "swift")
                    case .failure(let error):
                        print("Initialization Error:  \(error.localizedDescription)")
                        print("Initialization Error Description:  \(error.localizedDescription)")
                }
            })
    }

    static func registerToken() {
        CometChat.registerTokenForPushNotification(token: Defaults.deviceToken, settings: ["voip": false]) { (success) in
            print("registerTokenForPushNotification chat: \(success)")
        } onError: { (error) in
            print("registerTokenForPushNotification chat error: \(String(describing: error?.errorDescription))")
        }
    }

    static func login() {
        CometChatUIKit.login(
            authToken: "customer_1041_1722494227e91fb211221a74c97945ed8d25e40a",
            result: { result in
                switch result {
                    case .success:
                        CometChatSDKUtils.registerToken()
                        CometChatCallUtils.registerForVoIPCalls()
                    case .onError(let error):
                        print("Login failed with error: \(error.errorDescription)")
                    @unknown default: break
                }
            })
    }

    static func Userlogout() {
        if let currentUser = CometChat.getLoggedInUser() {
            CometChatUIKit.logout(user: currentUser, result: { _ in })
            CometChat.disconnect {} onError: { _ in
            }
        }
    }

    static func createCometChatMessages(for group: CometChatSDK.Group) -> CometChatMessages {
        let messageComposerConfiguration = MessageComposerConfiguration()
        messageComposerConfiguration.hide(liveReaction: true)

        // Modify share sheet
        messageComposerConfiguration.setAttachmentOptions(attachmentOptions: { user, group, controller in
            guard let controller else { return [] }
            var attachmentOptions = CometChatUIKit.getDataSource()
                .getAttachmentOptions(controller: controller, user: user, group: group, id: nil)
            attachmentOptions?.removeLast()
            return attachmentOptions ?? []
        })

        // Modify 3D-Touch Action
        let messageListConfiguration = MessageListConfiguration()
        var templates_ = CometChatUIKit.getDataSource().getAllMessageTemplates()
        for i in 0 ..< templates_.count {
            templates_[i].options = nil
        }
        messageListConfiguration.set(templates: templates_)

        let messagesConfiguration = MessagesConfiguration()
        messagesConfiguration.set(messageListConfiguration: messageListConfiguration)
        messagesConfiguration.hide(details: true)

        let cometChatMessages = CometChatMessages()
        cometChatMessages.set(messagesConfiguration: messagesConfiguration)
        cometChatMessages.set(messageComposerConfiguration: messageComposerConfiguration)
        cometChatMessages.set(group: group)

        return cometChatMessages
    }

    static func launchMessageList(GUID: String, onComplete: @escaping (CometChatMessages?) -> Void) {
        CometChat.getGroup(GUID: GUID) { group in
            DispatchQueue.main.async {
                onComplete(CometChatSDKUtils.createCometChatMessages(for: group))
            }
        } onError: { _ in
            DispatchQueue.main.async {
                onComplete(nil)
            }
        }
    }

    static func getUnreadCount(GUID: String, onComplete: @escaping (Int) -> Void) {
        CometChat.getUnreadMessageCountForGroup(GUID) { response in
            DispatchQueue.main.async {
                // This should return GUID: unreadCount dictionary, but returning empty dictionary for some reason
                // TODO: fix this
                guard let unreadCount = response[GUID] as? Int else {
                    onComplete(0)
                    return
                }
                onComplete(unreadCount)
            }
        } onError: { _ in
            DispatchQueue.main.async {
                onComplete(0)
            }
        }
    }

    static func isCometChatNotification(userInfo: [String: Any]) -> Bool {
        if let messageObject = userInfo["message"] as? [String: Any],
           CometChat.processMessage(messageObject).0 != nil {
            return true
        }
        return false
    }

    static func handleNotification(userInfo: [String: Any], controller: UIViewController) {
        if let messageObject = userInfo["message"] as? [String: Any],
           let baseMessage = CometChat.processMessage(messageObject).0 {
            guard let group = (baseMessage.receiver as? CometChatSDK.Group) else { return }
            controller.navigationController?.setNavigationBarHidden(false, animated: false)
            controller.navigationController?.pushViewController(
                CometChatSDKUtils.createCometChatMessages(for: group), animated: true)
        }
    }
}
