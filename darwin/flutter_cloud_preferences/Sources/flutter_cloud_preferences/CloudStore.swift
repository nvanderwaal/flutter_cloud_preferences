import Foundation

/// The local store, mirrored to iCloud key-value storage.
///
/// UserDefaults holds the values and is the source of truth. Every write is
/// copied to `NSUbiquitousKeyValueStore`. iCloud values are only read back on a
/// fresh install (when the local store has never been opened), and then only
/// fill keys the app has not written. With live sync on, every external change
/// is applied instead.
///
/// Values are stored as property list types: String, NSNumber (bool, int and
/// double keep their type), [String] and Data.
final class CloudStore {
  static let valuesKey = "flutter_cloud_preferences.values"
  static let openedKey = "flutter_cloud_preferences.opened"

  private let defaults: UserDefaults
  private let cloud: NSUbiquitousKeyValueStore
  private let notificationCenter: NotificationCenter
  private var values: [String: Any] = [:]
  private var liveSync = false
  // On a fresh install iCloud may deliver its data after start-up. Until the
  // first external change arrives, it is merged as a restore.
  private var awaitingRestore = false
  private var observer: NSObjectProtocol?

  /// Called on the main thread with changes made outside the app.
  var onChange: ((StoreChange) -> Void)?

  init(
    defaults: UserDefaults = .standard,
    cloud: NSUbiquitousKeyValueStore = .default,
    notificationCenter: NotificationCenter = .default
  ) {
    self.defaults = defaults
    self.cloud = cloud
    self.notificationCenter = notificationCenter
  }

  deinit {
    if let observer = observer {
      notificationCenter.removeObserver(observer)
    }
  }

  /// Opens the store and returns all values. Calling it again only returns
  /// the values.
  func open(liveSync: Bool) -> [String: Any] {
    if observer == nil {
      self.liveSync = liveSync
      values = defaults.dictionary(forKey: CloudStore.valuesKey) ?? [:]
      let isFreshInstall = !defaults.bool(forKey: CloudStore.openedKey)
      defaults.set(true, forKey: CloudStore.openedKey)

      observer = notificationCenter.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: cloud,
        queue: .main
      ) { [weak self] notification in
        self?.cloudDidChange(notification)
      }
      cloud.synchronize()

      if isFreshInstall {
        // Whatever iCloud already has locally is restored before returning.
        // Anything that arrives later is reported as a restore event.
        fillMissing(from: cloud.dictionaryRepresentation)
        awaitingRestore = true
      }
    }
    return values
  }

  func set(_ value: Any, forKey key: String) {
    values[key] = value
    save()
    cloud.set(value, forKey: key)
  }

  func remove(_ key: String) {
    values.removeValue(forKey: key)
    save()
    cloud.removeObject(forKey: key)
  }

  func clear() {
    // Only keys this store wrote; other iCloud keys of the app are left alone.
    for key in values.keys {
      cloud.removeObject(forKey: key)
    }
    values.removeAll()
    save()
  }

  private func save() {
    defaults.set(values, forKey: CloudStore.valuesKey)
  }

  /// Adds the values of keys the local store does not have, and returns the
  /// keys that were added.
  @discardableResult
  private func fillMissing(from cloudValues: [String: Any]) -> [String] {
    var added: [String] = []
    for (key, value) in cloudValues where values[key] == nil && CloudStore.isSupported(value) {
      values[key] = value
      added.append(key)
    }
    if !added.isEmpty {
      save()
    }
    return added
  }

  private func cloudDidChange(_ notification: Notification) {
    let userInfo = notification.userInfo ?? [:]
    let rawReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
    let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []

    if liveSync {
      applyLiveChange(reason: rawReason, keys: changedKeys)
    } else if awaitingRestore {
      awaitingRestore = false
      let added = fillMissing(from: cloud.dictionaryRepresentation)
      if !added.isEmpty {
        onChange?(
          StoreChange(
            reason: .restored, keys: added,
            values: values.filter { added.contains($0.key) }))
      }
    }
  }

  private func applyLiveChange(reason rawReason: Int?, keys: [String]) {
    let reason: StoreChangeReason
    switch rawReason ?? NSUbiquitousKeyValueStoreServerChange {
    case NSUbiquitousKeyValueStoreInitialSyncChange: reason = .initialSync
    case NSUbiquitousKeyValueStoreQuotaViolationChange: reason = .quotaViolation
    case NSUbiquitousKeyValueStoreAccountChange: reason = .accountChange
    default: reason = .serverChange
    }
    var changed: [String: Any] = [:]
    for key in keys {
      if let value = cloud.object(forKey: key), CloudStore.isSupported(value) {
        values[key] = value
        changed[key] = value
      } else {
        values.removeValue(forKey: key)
      }
    }
    save()
    onChange?(StoreChange(reason: reason, keys: keys, values: changed))
  }

  /// Whether [value] is one of the types the Dart side reads.
  static func isSupported(_ value: Any) -> Bool {
    switch value {
    case is String, is NSNumber, is Data: return true
    case let list as [Any]: return list.allSatisfy { $0 is String }
    default: return false
    }
  }
}
