//
//  CometChatCallUtils.swift
//  CometChat Debug
//
//  Created by Robby Chandra on 12/08/24.
//

import AVFAudio
import CallKit
import CometChatCallsSDK
import CometChatSDK
import CometChatUIKitSwift
import Foundation
import PushKit
import UIKit
import SwiftyUserDefaults

class CometChatCallUtils {

    var uuid: UUID?
    var activeCall: Call?
    var cancelCall: Bool = true
    var onCall = true
    var callController: CXCallController?
    let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
    var provider: CXProvider? = nil

    public func configureVoip(application: UIApplication, delegate: PKPushRegistryDelegate) {
        voipRegistry.delegate = delegate
        voipRegistry.desiredPushTypes = [PKPushType.voIP]

        CometChatCallEvents.addListener("loginlistener-pnToken-register-login", self)
    }

    static func registerForVoIPCalls() {
        CometChat.registerTokenForPushNotification(token: Defaults.voipToken, settings: ["voip": true]) { (success) in
            print("registerTokenForPushNotification voip: \(success)")
        } onError: { (error) in
            print("registerTokenForPushNotification voip error: \(String(describing: error?.errorDescription))")
        }
    }

    public func onProviderDidReset(provider: CXProvider) {
        if let uuid = self.uuid {
            onCall = true
            provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
        }
    }

    public func didReceiveIncomingPushWith(payload: PKPushPayload) -> CXProvider? {
        if let payloadData = payload.dictionaryPayload as? [String: Any],
           let messageObject = payloadData["message"], let dict = messageObject as? [String: Any] {
            let (baseMessage, error) = CometChat.processMessage(dict)
            if let error = error {
                guard let uuid else { return nil }
                provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                print("Error processing message: \(error)")
            } else if let baseMessage = baseMessage {
                if baseMessage.messageCategory == .call {
                    let callObject = baseMessage as! Call
                    switch callObject.callStatus {
                        case .initiated:
                            let newCallProvider = initiateCall(callObject: callObject)
                            return newCallProvider
                        case .ongoing: break
                        case .unanswered:
                            guard let uuid else { return nil }
                            provider?.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
                            handleMissedCallNotification(callObject: callObject)
                        case .rejected, .busy:
                            guard let uuid else { return nil }
                            provider?.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
                        case .cancelled:
                            guard let uuid else { return nil }
                            provider?.reportCall(with: uuid, endedAt: Date(), reason: .failed)
                            handleMissedCallNotification(callObject: callObject)
                        case .ended:
                            guard let uuid else { return nil }
                            provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                        @unknown default:
                            guard let uuid else { return nil }
                            provider?.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                    }
                }
            }
        }
        provider?.reportCall(with: uuid!, endedAt: Date(), reason: .remoteEnded)
        return nil
    }

    public func handleMissedCallNotification(callObject: Call) {
        guard let sender = callObject.sender else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(sender.name ?? "")"
        content.body = "Missed call"
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error displaying missed call notification: \(error.localizedDescription)")
            } else {
                print("Missed call notification displayed successfully")
            }
        }
    }

    public func onAnswerCallAction(action: CXAnswerCallAction) {
        if activeCall != nil {
            startCall()
        }

        action.fulfill()
    }

    private func dismissCometChatIncomingCall(from viewController: UIViewController) {
        if let presentedViewController = viewController.presentedViewController {
            if presentedViewController is CometChatIncomingCall {
                presentedViewController.dismiss(animated: false, completion: nil)
            } else {
                dismissCometChatIncomingCall(from: presentedViewController)
            }
        }
    }

    func reloadViewController(_ rootViewController: UIViewController) {
        if let navigationController = rootViewController as? UINavigationController {
            if let visibleViewController = navigationController.visibleViewController {
                visibleViewController.viewWillAppear(true)
                visibleViewController.viewDidAppear(true)
            }
        } else {
            rootViewController.viewWillAppear(true)
            rootViewController.viewDidAppear(true)
        }

    }

    public func onEndCallAction(action: CXEndCallAction) {
        let endCallAction = CXEndCallAction(call: uuid!)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)

        callController?.request(transaction) { error in
            if let error = error {
                print("Error requesting transaction: \(error)")
            } else {
                print("Requested transaction successfully")
            }
        }

        if let activeCall = activeCall {
            if CometChat.getActiveCall() == nil
                || (CometChat.getActiveCall()?.callStatus == .initiated
                    && CometChat.getActiveCall()?.callInitiator != CometChat.getLoggedInUser()) {
                CometChat.rejectCall(
                    sessionID: activeCall.sessionID ?? "", status: .rejected, onSuccess: { [self] _ in
                        action.fulfill()
                        print("CallKit: Reject call success")
                        DispatchQueue.main.async { [self] in
                            if let scene = UIApplication.shared.connectedScenes.first(
                                where: { $0.activationState == .foregroundActive })
                                as? UIWindowScene {
                                if let rootViewController = scene.windows.first?
                                    .rootViewController {
                                    self.dismissCometChatIncomingCall(
                                        from: rootViewController)
                                    self.reloadViewController(rootViewController)
                                }
                            }
                            if let uuid = uuid {
                                provider?.reportCall(
                                    with: uuid, endedAt: Date(),
                                    reason: .remoteEnded)
                                self.uuid = nil
                            }
                        }
                    }
                ) { (error) in
                    print(
                        "CallKit: Reject call failed with error: \(String(describing: error?.errorDescription))"
                    )
                    action.fulfill()
                    if let uuid = self.uuid {
                        self.provider?.reportCall(
                            with: uuid, endedAt: Date(),
                            reason: .remoteEnded)
                        self.uuid = nil
                    }
                }
            } else {
                CometChat.endCall(sessionID: CometChat.getActiveCall()?.sessionID ?? "") { _ in
                    CometChatCalls.endSession()
                    action.fulfill()
                    print("CallKit: End call success")
                    DispatchQueue.main.async { [self] in
                        if let scene = UIApplication.shared.connectedScenes.first(where: {
                            $0.activationState == .foregroundActive
                        }) as? UIWindowScene {
                            if let rootViewController = scene.windows.first?
                                .rootViewController {
                                self.dismissCometChatIncomingCall(
                                    from: rootViewController)
                                self.reloadViewController(rootViewController)
                            }
                        }
                    }
                } onError: { error in
                    action.fulfill()
                    print(
                        "CallKit: End call failed with error: \(String(describing: error?.errorDescription))"
                    )
                }

            }
        }
    }
}

extension CometChatCallUtils {

    private func initiateCall(callObject: Call) -> CXProvider {
        activeCall = callObject
        uuid = UUID()

        let callerName = callObject.sender!.name

        let config = CXProviderConfiguration(localizedName: "Pickaroo Call")
        config.iconTemplateImageData = UIImage(named: "callkit-icon")?.pngData()
        config.includesCallsInRecents = false
        config.ringtoneSound = "ringtone.caf"
        config.supportsVideo = false

        provider = CXProvider(configuration: config)

        guard UIApplication.shared.applicationState != .active else {
            return provider!
        }

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName!.capitalized)
        if callObject.callType == .video {
            update.hasVideo = true
        } else {
            update.hasVideo = false
        }

        provider?.reportNewIncomingCall(
            with: uuid!, update: update,
            completion: { error in
                if error == nil {
                    self.configureAudioSession()
                }
            })

        return provider!

    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                AVAudioSession.Category.playAndRecord,
                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch let error as NSError {
            print(error)
        }
    }

    func setupCallSettingBuilder() -> CometChatCallsSDK.CallSettingsBuilder {
        var callSettingsBuilder = CometChatCallsSDK.CallSettingsBuilder()
        callSettingsBuilder = callSettingsBuilder.setIsAudioOnly(true)
        callSettingsBuilder = callSettingsBuilder.setSwitchCameraButtonDisable(true)
        callSettingsBuilder = callSettingsBuilder.setShowRecordingButton(false)
        callSettingsBuilder = callSettingsBuilder.setEnableVideoTileClick(false)
        callSettingsBuilder = callSettingsBuilder.setEnableDraggableVideoTile(false)

        return callSettingsBuilder
    }

    private func startCall() {
        let cometChatOngoingCall = CometChatOngoingCall()

        // Attempt to accept the call using the session ID from the active call
        CometChat.acceptCall(sessionID: activeCall?.sessionID ?? "") { call in
            DispatchQueue.main.async {
                let callSettingsBuilder = self.setupCallSettingBuilder()

                cometChatOngoingCall.set(callSettingsBuilder: callSettingsBuilder)
                cometChatOngoingCall.set(callWorkFlow: .defaultCalling)
                cometChatOngoingCall.set(sessionId: call?.sessionID ?? "")
                cometChatOngoingCall.modalPresentationStyle = .fullScreen
                if let sceneDelegate = UIApplication.shared.connectedScenes.first?.delegate
                    as? SceneDelegate,
                   let window = sceneDelegate.window,
                   let rootViewController = window.rootViewController {
                    var currentController = rootViewController
                    while let presentedController = currentController.presentedViewController {
                        currentController = presentedController
                    }
                    currentController.present(cometChatOngoingCall, animated: true)
                }
            }
            cometChatOngoingCall.setOnCallEnded { [weak self] _ in
                DispatchQueue.main.async {
                    if let scene = UIApplication.shared.connectedScenes.first(where: {
                        $0.activationState == .foregroundActive
                    }) as? UIWindowScene {
                        if let rootViewController = scene.windows.first?.rootViewController {
                            self?.dismissCometChatIncomingCall(from: rootViewController)
                            self?.reloadViewController(rootViewController)
                        }
                    }
                }
                self?.provider?.reportCall(
                    with: self?.uuid ?? UUID(), endedAt: Date(), reason: .remoteEnded)
            }
        } onError: { error in
            print("Error while accepting the call: \(String(describing: error?.errorDescription))")
        }
    }

    func onCallEnded(call: CometChatSDK.Call) {
        guard let uuid = uuid else { return }

        if activeCall != nil {
            let transaction = CXTransaction(action: CXEndCallAction(call: uuid))
            callController?.request(transaction, completion: { _ in })
            activeCall = nil
        }
        DispatchQueue.main.sync { [self] in
            if let scene = UIApplication.shared.connectedScenes.first(where: {
                $0.activationState == .foregroundActive
            }) as? UIWindowScene {
                if let rootViewController = scene.windows.first?.rootViewController {
                    dismissCometChatIncomingCall(from: rootViewController)
                    self.reloadViewController(rootViewController)
                }
            }
        }
    }

    func onCallInitiated(call: CometChatSDK.Call) {
        let callerName = (call.callReceiver as? CometChatSDK.User)?.name
        callController = CXCallController()
        uuid = UUID()

        let transactionCallStart = CXTransaction(
            action: CXStartCallAction(
                call: uuid!, handle: CXHandle(type: .generic, value: callerName ?? "")))
        callController?.request(transactionCallStart, completion: { _ in })
    }
}

extension CometChatCallUtils: CometChatCallEventListener {
    func onIncomingCallAccepted(call: CometChatSDK.Call) {
        print(#function)
        if activeCall != nil {
            let transactionCallAccepted = CXTransaction(action: CXAnswerCallAction(call: uuid!))
            callController?.request(transactionCallAccepted, completion: { _ in })
            activeCall = nil
        }
    }

    func onIncomingCallRejected(call: CometChatSDK.Call) {
        print(#function)
        provider?.reportCall(with: uuid!, endedAt: Date(), reason: .remoteEnded)
    }

    func onOutgoingCallAccepted(call: CometChatSDK.Call) {
        print(#function)
        let transactionCallAccepted = CXTransaction(action: CXAnswerCallAction(call: uuid!))
        callController?.request(transactionCallAccepted, completion: { _ in })
    }

    func onOutgoingCallRejected(call: CometChatSDK.Call) {
        print(#function)
        if activeCall != nil {
            let transactionCallAccepted = CXTransaction(action: CXEndCallAction(call: uuid!))
            callController?.request(transactionCallAccepted, completion: { _ in })
            activeCall = nil
        }
    }
}
