//
//  File.swift
//  Alfy
//
//  Created by albert vila on 29/5/25.
//

import Foundation

public struct Requester {
    
    private static var _shared: URLSession = {
        URLSession.shared
    }()
    
    public static func request(
        _ urlString: String,
        headers: [HeaderParam]? = nil
    ) async throws -> (data: Data, urlResponse: URLResponse) {
        
        let _request = try buildRequest(urlString, headers: headers)
        return try await _shared.data(for: _request)
    }
    
    public static func request<D: Decodable>(
        _ urlString: String,
        headers: [HeaderParam]? = nil
    ) async throws -> D {
        
        let _request = try buildRequest(urlString, headers: headers)
        let (data, urlResponse) = try await _shared.data(for: _request)
        
        if !(200..<300).contains((urlResponse as! HTTPURLResponse).statusCode) {
            assert((urlResponse as! HTTPURLResponse).statusCode != 204)
            throw ErrorReason.generic(statusCode: (urlResponse as! HTTPURLResponse).statusCode)
        }
        
        do {
            return try JSONDecoder().decode(D.self, from: data)
        } catch {
            if case DecodingError.keyNotFound(_, let context) = error {
                assertionFailure(context.debugDescription)
            } else {
                assertionFailure(
                    "\(error.localizedDescription)\n\(String(data: data, encoding: .utf8) ?? "no data")"
                )
            }
            throw error
        }
    }
}

extension Requester {
    private static func buildRequest(_ urlString: String, headers: [HeaderParam]?) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            assertionFailure()
            throw ErrorReason.urlCreationFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        computedHeaders(headers).forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.headerField)
        }
        print("Alfy - [NETWORK] - \(String(describing: request.allHTTPHeaderFields))")
        return request
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
        case generic(statusCode: Int)
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
