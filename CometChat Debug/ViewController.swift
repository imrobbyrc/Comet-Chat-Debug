//
//  ViewController.swift
//  CometChat Debug
//
//  Created by Robby Chandra on 12/08/24.
//

import UIKit
import CometChatSDK

class ViewController: UIViewController {

    @IBOutlet weak var unreadMsgButton: UIButton!

    let COMET_CHAT_DEBUG_GUID = "shopper_ewl96zm3_20240816_163159"

    override func viewDidLoad() {
        super.viewDidLoad()
        CometChatSDKUtils.login()
        CometChat.messagedelegate = self
        // Do any additional setup after loading the view.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        CometChatSDKUtils.getUnreadCount(GUID: COMET_CHAT_DEBUG_GUID, onComplete: { count in
            self.unreadMsgButton.setTitle("total unread msg: \(count)", for: .normal)
        })
    }

    @IBAction func unreadMsgButtonTapped(_ sender: Any) {
        CometChatSDKUtils.launchMessageList(GUID: COMET_CHAT_DEBUG_GUID) { messageList in
            guard let messageList = messageList else {
                print("Failed to retrieve messages, please try again later.")
                return
            }
            self.navigationController?.pushViewController(messageList, animated: true)
        }
    }
}

extension ViewController: CometChatMessageDelegate {
    func onTextMessageReceived(textMessage: TextMessage) {
        CometChatSDKUtils.getUnreadCount(GUID: COMET_CHAT_DEBUG_GUID, onComplete: { count in
            self.unreadMsgButton.setTitle("total unread msg: \(count)", for: .normal)
        })
    }

    func onMediaMessageReceived(mediaMessage: MediaMessage) {
        CometChatSDKUtils.getUnreadCount(GUID: COMET_CHAT_DEBUG_GUID, onComplete: { count in
            self.unreadMsgButton.setTitle("total unread msg: \(count)", for: .normal)
        })
    }

    func onCustomMessageReceived(customMessage: CustomMessage) {
        CometChatSDKUtils.getUnreadCount(GUID: COMET_CHAT_DEBUG_GUID, onComplete: { count in
            self.unreadMsgButton.setTitle("total unread msg: \(count)", for: .normal)
        })
    }
}



extension UIViewController {
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
}
