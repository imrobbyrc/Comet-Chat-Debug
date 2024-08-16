//
//  DefaultKeys.swift
//  CometChat Debug
//
//  Created by Robby Chandra on 12/08/24.
//

import UIKit
import SwiftyUserDefaults

// Setup User related UserDefaults
extension DefaultsKeys {

    var deviceToken: DefaultsKey<String> {
        return .init("deviceToken", defaultValue: "")
    }

    var voipToken: DefaultsKey<String> {
        return .init("voipToken", defaultValue: "")
    }
}
