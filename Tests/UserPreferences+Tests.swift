//
//  Test.swift
//  Alfy
//
//  Created by albert vila on 30/5/25.
//

import Testing

import XCTest
import Combine

@testable import Alfy

final class UserDefaultTests: XCTestCase {
    private var mockStorage: MockUserDefaultsStorage!
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockUserDefaultsStorage()
        cancellables = Set<AnyCancellable>()
        UserDefaultLogger.isEnabled = false // Disable logging during tests
    }
    
    override func tearDown() {
        cancellables = nil
        mockStorage = nil
        super.tearDown()
    }
    
    func testStringStorage() {
        @UserDefault("test_string", storage: mockStorage)
        var testString: String?
        
        XCTAssertNil(testString)
        
        testString = "Hello, World!"
        XCTAssertEqual(testString, "Hello, World!")
    }
    
    func testDefaultValue() {
        @UserDefault("test_int", defaultValue: 42, storage: mockStorage)
        var testInt: Int?
        
        XCTAssertEqual(testInt, 42)
    }
    
    func testPublisher() {
        @UserDefault("test_publisher", storage: mockStorage)
        var testValue: String?
        
        let expectation = XCTestExpectation(description: "Publisher emits value")
        
        $testValue.publisher
            .dropFirst() // Skip initial value
            .sink { value in
                XCTAssertEqual(value, "Test")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        testValue = "Test"
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testReset() {
        @UserDefault("test_reset", defaultValue: "default", storage: mockStorage)
        var testValue: String?
        
        testValue = "changed"
        XCTAssertEqual(testValue, "changed")
        
        $testValue.reset()
        XCTAssertEqual(testValue, "default")
    }
}

// MARK: - Tests/UserDefaultsWrapperTests/MockUserDefaultsStorage.swift

class MockUserDefaultsStorage: UserDefaultsStorageProtocol {
    private var storage: [String: Data] = [:]
    
    func data(forKey key: String) -> Data? {
        storage[key]
    }
    
    func set(_ data: Data?, forKey key: String) {
        storage[key] = data
    }
    
    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}

