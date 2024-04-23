//
//  WorkmanagerUserDefaultsHelper.swift
//  workmanager
//
//  Created by Kymer Gryson on 13/08/2019.
//

import Foundation

struct UserDefaultsHelper {

    // MARK: Properties

    private static let userDefaults = UserDefaults(suiteName: "\(SwiftWorkmanagerPlugin.identifier).userDefaults")!

    enum Key {
        case callbackHandle

        var stringValue: String {
            return "\(SwiftWorkmanagerPlugin.identifier).\(self)"
        }
    }

    // MARK: callbackHandle

    static func storeCallbackHandle(_ handle: Int64) {
       store(handle, key: .callbackHandle)
    }

    static func getStoredCallbackHandle() -> Int64? {
        return getValue(for: .callbackHandle)
    }

    // MARK: Private helper functions

    private static func store<T>(_ value: T, key: Key) {
        userDefaults.setValue(value, forKey: key.stringValue)
    }

    private static func getValue<T>(for key: Key) -> T? {
        return userDefaults.value(forKey: key.stringValue) as? T
    }

}
