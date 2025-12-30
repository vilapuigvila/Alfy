//
//  File.swift
//  Alfy
//
//  Created by albert vila on 30/12/25.
//

import Foundation

extension Data {
    
    public var prettyPrintedJSON: NSString {
        if let object = try? JSONSerialization.jsonObject(with: self, options: []),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
            let prettyPrintedString = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
            return prettyPrintedString
                
        } else if let prettyPrintedString = NSString(data: self, encoding: String.Encoding.utf8.rawValue) {
            return prettyPrintedString
        } else {
            return "⚠️ Data can't be serialized for log, maybe no JSON response?)"
        }
    }
    
    public var toDictionary: [String: Any]? {
        guard let json = try? JSONSerialization
            .jsonObject(with: self, options: .mutableContainers) as? [String: Any] else {
            return nil
        }
        return json
    }
}
