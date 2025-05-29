//
//  File.swift
//  Alfy
//
//  Created by albert vila on 29/5/25.
//

import Foundation

extension Date {
    
    public func areDatesInSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    public func adding(millis: Int) -> Date {
        return Calendar.current.date(byAdding: .nanosecond, value: millis, to: self)!
    }
    public func adding(seconds: Int) -> Date {
        return Calendar.current.date(byAdding: .second, value: seconds, to: self)!
    }
    public func adding(minutes: Int) -> Date {
        return Calendar.current.date(byAdding: .minute, value: minutes, to: self)!
    }
    public func adding(hours: Int) -> Date {
        return Calendar.current.date(byAdding: .hour, value: hours, to: self)!
    }
    public func adding(days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: self)!
    }
    public func adding(hours: Int, minutes: Int) -> Date {
        return (Calendar.current.date(byAdding: .hour, value: hours, to: self)?.adding(minutes: minutes))!
    }
    public func adding(hours: Int, minutes: Int, seconds: Int) -> Date {
        return (Calendar.current.date(byAdding: .hour, value: hours, to: self)?.adding(minutes: minutes).adding(seconds: seconds))!
    }
}
