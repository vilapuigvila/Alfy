//
//  File.swift
//  Alfy
//
//  Created by albert vila on 29/5/25.
//

import Foundation

#if canImport(SwiftData)
import SwiftData

@available(iOS 17, macOS 14, *)
public protocol DatabaseManagerProtocol {
    @MainActor @discardableResult
    func insert<T: PersistentModel>(_ item: T) throws -> T

    @MainActor
    func insert<T: PersistentModel>(_ sequenceOf: [T]) throws

    @MainActor
    func fetchItems<T: PersistentModel>(_ item: T.Type, predicate: Predicate<T>?, sortBy: [SortDescriptor<T>]?) throws -> [T]

    @MainActor
    func removeItem<T: PersistentModel>(_ item: T) throws

    @MainActor
    func remove<T: PersistentModel>(_ items: [T]) throws

    @MainActor
    func deleteAll<T: PersistentModel>(_ item: T.Type) throws

    @MainActor
    func save() throws
}
#else
public protocol DatabaseManagerProtocol {}
#endif
/*
extension DatabaseManagerProtocol where Self == DatabaseManager {
    @MainActor
    public static var shared: Self {
        DatabaseManager.shared
    }
}
*/
