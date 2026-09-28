import SwiftUI

/// Nearest point (by date) to a target — for chart hover snapping.
func nearestByDate<T>(_ items: [T], to target: Date, date: (T) -> Date) -> T? {
    items.min { abs(date($0).timeIntervalSince(target)) < abs(date($1).timeIntervalSince(target)) }
}
