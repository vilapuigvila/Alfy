//
//  File.swift
//  Alfy
//
//  Created by albert vila on 29/5/25.
//

import Foundation

public struct Requester {
//    private static let token = "7r5zloC5zs2MjyxAfdnkd1cvuUeKpvWQ9cONyuPh"
    
    private static var _shared: URLSession = {
        URLSession.shared
    }()
    
    public static func request(
        _ urlString: String,
        headers: [[String: String]]? = nil
    ) async throws -> (Data, URLResponse) {
        guard let url = URL(string: urlString) else {
            assertionFailure()
            throw ErrorReason.urlCreationFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET" // or "POST", etc.
        
        if let headers {
            headers
                .flatMap { $0 }
                .forEach { key, value in
                    request.setValue(value, forHTTPHeaderField: key)
                }
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("[NETWORK] - \(String(describing: request.allHTTPHeaderFields))")
//        request.setValue(token, forHTTPHeaderField: "x-api-key")
        
        return try await _shared.data(for: request)
    }
}

extension Requester {
    
    public enum ErrorReason: Error {
        case dataCorrupted
        case urlCreationFailed
        case noInternetConnection
    }
}
