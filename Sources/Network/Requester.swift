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
        headers: [HeaderParam]? = nil
    ) async throws -> (data: Data, urlResponse: URLResponse) {
        guard let url = URL(string: urlString) else {
            assertionFailure()
            throw ErrorReason.urlCreationFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        computedHeaders(headers).forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.headerField)
        }
        print("[NETWORK] - \(String(describing: request.allHTTPHeaderFields))")
        return try await _shared.data(for: request)
    }
    
    private static func computedHeaders(_ headers: [HeaderParam]?) -> [HeaderParam] {
        let mandatoryHeaders: [HeaderParam] = [
            .contentType(value: .none)
        ]
        guard let headers else {
            return mandatoryHeaders
        }
        return headers + mandatoryHeaders
    }
}

extension Requester {
    
    public enum ErrorReason: Error {
        case dataCorrupted
        case urlCreationFailed
        case noInternetConnection
    }
    
    public enum HeaderParam: Hashable {
        case custom(headerField: String, value: String)
        case acceptLanguage(value: String)
        case contentType(value: String? = nil)
        
        var headerField: String {
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
