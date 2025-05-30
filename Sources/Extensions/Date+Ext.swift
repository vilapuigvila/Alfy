//
//  File.swift
//  Alfy
//
//  Created by albert vila on 29/5/25.
//

import Foundation

extension Date {
    
    /// Returns true if the two given dates fall on the same day in the current calendar.
    public func areDatesInSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    /// Returns a new Date by adding the specified number of milliseconds to self.
    public func adding(millis: Int) -> Date {
        return Calendar.current.date(byAdding: .nanosecond, value: millis, to: self)!
    }
    
    /// Returns a new Date by adding the specified number of seconds to self.
    public func adding(seconds: Int) -> Date {
        return Calendar.current.date(byAdding: .second, value: seconds, to: self)!
    }
    
    /// Returns a new Date by adding the specified number of minutes to self.
    public func adding(minutes: Int) -> Date {
        return Calendar.current.date(byAdding: .minute, value: minutes, to: self)!
    }
    
    /// Returns a new Date by adding the specified number of hours to self.
    public func adding(hours: Int) -> Date {
        return Calendar.current.date(byAdding: .hour, value: hours, to: self)!
    }
    
    /// Returns a new Date by adding the specified number of days to self.
    public func adding(days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: self)!
    }
    
    /// Returns a new Date by adding the specified hours and minutes to self.
    public func adding(hours: Int, minutes: Int) -> Date {
        return (Calendar.current.date(byAdding: .hour, value: hours, to: self)?.adding(minutes: minutes))!
    }
    
    /// Returns a new Date by adding the specified hours, minutes, and seconds to self.
    public func adding(hours: Int, minutes: Int, seconds: Int) -> Date {
        return (Calendar.current.date(byAdding: .hour, value: hours, to: self)?.adding(minutes: minutes).adding(seconds: seconds))!
    }
    
    /// Returns the difference in hours between self and the current date/time.
    public var differenceInHoursFromNow: Int {
        return Calendar.current.dateComponents([.hour], from: self, to: Date()).hour ?? 0
    }
    
    /// Returns the difference in seconds between self and the current date/time.
    public var differenceInSecondsFromNow: Int {
        return Calendar.current.dateComponents([.second], from: self, to: Date()).second ?? 0
    }
}
