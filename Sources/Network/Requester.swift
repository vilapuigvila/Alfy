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
        headers: [HeaderParamCase]? = nil
    ) async throws -> (Data, URLResponse) {
        guard let url = URL(string: urlString) else {
            assertionFailure()
            throw ErrorReason.urlCreationFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET" // or "POST", etc.
        
        if let headers {
            headers.forEach {
                request.setValue($0.value, forHTTPHeaderField: $0.key)
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
    
    public struct HeaderParam {
        let key: String
        let value: String
    }
    
    public enum HeaderParamCase: Hashable {
        case custom(key: String, value: String)
        case acceptLanguage(value: String)
        case contentType(value: String?)
        
        var key: String {
            switch self {
            case .acceptLanguage:
                return "Accept-Language"
            case .contentType:
                return "Content-Type"
            case .custom(let key, _):
                return key
            }
        }
        
        var value: String {
            switch self {
            case .acceptLanguage(let value):
                return value
            case .contentType(let value):
                return value ?? "application/json"
            case .custom(_, let value):
                return value
            }
        }
    }
}
