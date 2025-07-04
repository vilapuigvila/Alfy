//
//  File.swift
//  Alfy
//
//  Created by albert vila on 30/5/25.
//

import Foundation
import Combine

/// A property wrapper that provides type-safe, reactive UserDefaults storage for Codable types.
///
/// Usage:
/// ```swift
/// struct Settings {
///     @UserDefault("username")
///     var username: String?
///
///     @UserDefault("user_age", defaultValue: 18)
///     var userAge: Int?
/// }
/// ```
@propertyWrapper
public struct UserDefault<T: Codable> {
    private let storage: UserDefaultsStorageProtocol
    private let queue: DispatchQueue
    private let subject: CurrentValueSubject<T?, Never>
    
    public let key: String
    public let defaultValue: T?
    
    /// Initialize a UserDefault property wrapper
    /// - Parameters:
    ///   - key: The UserDefaults key
    ///   - defaultValue: The default value to return when no value is stored
    ///   - storage: Custom storage implementation (defaults to UserDefaults.standard)
    public init(
        _ key: String,
        defaultValue: T? = nil,
        storage: UserDefaultsStorageProtocol = UserDefaultsStorage()
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.storage = storage
        self.queue = DispatchQueue(
            label: "UserDefaultQueue_\(key)_\(UUID().uuidString)",
            qos: .userInitiated
        )
        
        // Initialize subject with current value
        let initialValue = UserDefaultOperations<T>.readValue(
            for: key,
            defaultValue: defaultValue,
            from: storage
        )
        self.subject = CurrentValueSubject<T?, Never>(initialValue)
        
        // Listen for external UserDefaults changes
        self.setupExternalChangeObserver()
    }
    
    public var wrappedValue: T? {
        get {
            queue.sync {
                UserDefaultOperations<T>.readValue(
                    for: key,
                    defaultValue: defaultValue,
                    from: storage
                )
            }
        }
        set {
            queue.async { [subject, key, storage] in
                UserDefaultOperations<T>.writeValue(
                    newValue,
                    for: key,
                    to: storage
                )
                
                // Update subject on main queue for UI safety
                DispatchQueue.main.async {
                    subject.send(newValue)
                }
                
                // Post notification
                NotificationCenter.default.post(
                    name: .userDefaultChanged,
                    object: UserDefaultChangeInfo(key: key, value: newValue)
                )
            }
        }
    }
    
    public var projectedValue: UserDefaultPublisher<T> {
        UserDefaultPublisher(
            publisher: subject
                .receive(on: DispatchQueue.main)
                .removeDuplicates(by: UserDefaultOperations<T>.areEqual)
                .eraseToAnyPublisher(),
            key: key,
            defaultValue: defaultValue,
            storage: storage
        )
    }
    
    private func setupExternalChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak subject, key, defaultValue, storage] _ in
            let updatedValue = UserDefaultOperations<T>.readValue(
                for: key,
                defaultValue: defaultValue,
                from: storage
            )
            subject?.send(updatedValue)
        }
    }
}

// MARK: - Sources/UserDefaultsWrapper/UserDefaultPublisher.swift

/// Publisher wrapper that provides additional functionality for UserDefault properties
public struct UserDefaultPublisher<T: Codable> {
    private let _publisher: AnyPublisher<T?, Never>
    public let key: String
    public let defaultValue: T?
    private let storage: UserDefaultsStorageProtocol
    
    internal init(
        publisher: AnyPublisher<T?, Never>,
        key: String,
        defaultValue: T?,
        storage: UserDefaultsStorageProtocol
    ) {
        self._publisher = publisher
        self.key = key
        self.defaultValue = defaultValue
        self.storage = storage
    }
    
    /// The reactive publisher for value changes
    public var publisher: AnyPublisher<T?, Never> {
        _publisher
    }
    
    /// Reset the value to its default
    public func reset() {
        UserDefaultOperations<T>.writeValue(defaultValue, for: key, to: storage)
    }
    
    /// Check if the current value equals the default value
    public var isDefault: Bool {
        let currentValue = UserDefaultOperations<T>.readValue(
            for: key,
            defaultValue: defaultValue,
            from: storage
        )
        return UserDefaultOperations<T>.areEqual(currentValue, defaultValue)
    }
    
    /// Peek at the current value without triggering observers
    public func peek() -> T? {
        UserDefaultOperations<T>.readValue(
            for: key,
            defaultValue: defaultValue,
            from: storage
        )
    }
    
    /// Remove the stored value entirely
    public func remove() {
        storage.removeObject(forKey: key)
    }
}

// MARK: - Sources/UserDefaultsWrapper/UserDefaultsStorageProtocol.swift

/// Protocol for abstracting UserDefaults storage operations
public protocol UserDefaultsStorageProtocol {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
}

/// Default implementation using UserDefaults.standard
public struct UserDefaultsStorage: UserDefaultsStorageProtocol {
    private let userDefaults: UserDefaults
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func data(forKey key: String) -> Data? {
        userDefaults.data(forKey: key)
    }
    
    public func set(_ data: Data?, forKey key: String) {
        userDefaults.set(data, forKey: key)
    }
    
    public func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
}

// MARK: - Sources/UserDefaultsWrapper/UserDefaultOperations.swift

/// Internal operations for UserDefault reading/writing
internal enum UserDefaultOperations<T: Codable> {
    private static var jsonDecoder: JSONDecoder { JSONDecoder() }
    private static var jsonEncoder: JSONEncoder { JSONEncoder() }
    
    static func readValue(
        for key: String,
        defaultValue: T?,
        from storage: UserDefaultsStorageProtocol
    ) -> T? {
        guard let data = storage.data(forKey: key) else {
            return defaultValue
        }
        
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            UserDefaultLogger.log(
                success: false,
                operation: "decode",
                key: key,
                error: error
            )
            return defaultValue
        }
    }
    
    static func writeValue(
        _ value: T?,
        for key: String,
        to storage: UserDefaultsStorageProtocol
    ) {
        guard let value = value else {
            storage.removeObject(forKey: key)
            UserDefaultLogger.log(success: true, operation: "remove", key: key)
            return
        }
        
        do {
            let encodedValue = try jsonEncoder.encode(value)
            storage.set(encodedValue, forKey: key)
            UserDefaultLogger.log(success: true, operation: "write", key: key)
        } catch {
            UserDefaultLogger.log(
                success: false,
                operation: "encode",
                key: key,
                error: error
            )
            storage.removeObject(forKey: key)
        }
    }
    
    static func areEqual(_ lhs: T?, _ rhs: T?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let lhsValue?, let rhsValue?):
            do {
                let lhsData = try jsonEncoder.encode(lhsValue)
                let rhsData = try jsonEncoder.encode(rhsValue)
                return lhsData == rhsData
            } catch {
                return false
            }
        default:
            return false
        }
    }
}

// MARK: - Sources/UserDefaultsWrapper/UserDefaultLogger.swift

/// Configurable logging for UserDefault operations
public enum UserDefaultLogger {
    public static var isEnabled: Bool = true
    public static var logLevel: LogLevel = .info
    
    public enum LogLevel: Int, CaseIterable {
        case none = 0
        case error = 1
        case info = 2
        case debug = 3
    }
    
    internal static func log(
        success: Bool,
        operation: String,
        key: String,
        error: Error? = nil
    ) {
        guard isEnabled else { return }
        
        let level: LogLevel = success ? .info : .error
        guard level.rawValue <= logLevel.rawValue else { return }
        
        let prefix = success ? "✅" : "❌"
        let message = "\(prefix) UserDefault \(operation) for key '\(key)'"
        
        if let error = error {
            print("[USER_DEFAULT] \(message) - Error: \(error.localizedDescription)")
        } else {
            print(message)
        }
    }
}

// MARK: - Sources/UserDefaultsWrapper/Extensions.swift

extension Notification.Name {
    public static let userDefaultChanged = Notification.Name("userDefaultChanged")
}

public struct UserDefaultChangeInfo {
    public let key: String
    public let value: Any?
    
    public init(key: String, value: Any?) {
        self.key = key
        self.value = value
    }
}

// MARK: - Sources/UserDefaultsWrapper/Convenience.swift

/// Convenience extensions for common types
extension UserDefault where T == String {
    public init(_ key: String, defaultValue: String) {
        self.init(key, defaultValue: defaultValue as T?)
    }
}

extension UserDefault where T == Int {
    public init(_ key: String, defaultValue: Int) {
        self.init(key, defaultValue: defaultValue as T?)
    }
}

extension UserDefault where T == Bool {
    public init(_ key: String, defaultValue: Bool) {
        self.init(key, defaultValue: defaultValue as T?)
    }
}

extension UserDefault where T == Double {
    public init(_ key: String, defaultValue: Double) {
        self.init(key, defaultValue: defaultValue as T?)
    }
}
