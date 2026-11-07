import Foundation
import CoreGraphics

/// Adds weekday labels only when a single, complete header row and one shift
/// per column make the relationship unambiguous. Other cells remain editable.
enum RosterTextLayout {
    struct Cell {
        let text: String
        let bounds: CGRect
    }

    static func text(from cells: [Cell]) -> String {
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let headers = cells.enumerated().compactMap { index, cell -> (index: Int, day: String)? in
            let text = cell.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard let day = weekdays.first(where: { text == $0 || text == String($0.prefix(3)) }) else { return nil }
            return (index, day)
        }
        guard headers.count == 7, Set(headers.map(\.day)).count == 7 else {
            return cells.map(\.text).joined(separator: "\n")
        }
        let headerY = headers.map { cells[$0.index].bounds.midY }
        guard (headerY.max()! - headerY.min()!) < 0.05 else {
            return cells.map(\.text).joined(separator: "\n")
        }
        let sorted = headers.sorted { cells[$0.index].bounds.midX < cells[$1.index].bounds.midX }
        var assignments: [Int: [Int]] = [:]
        for (index, cell) in cells.enumerated() where NightDraftParser.extractTimes(from: cell.text.lowercased()).count == 2 {
            guard cell.bounds.maxY < headerY.min()!,
                  let column = sorted.indices.min(by: {
                      abs(cells[sorted[$0].index].bounds.midX - cell.bounds.midX) <
                      abs(cells[sorted[$1].index].bounds.midX - cell.bounds.midX)
                  }) else { continue }
            let center = cells[sorted[column].index].bounds.midX
            let left = column == 0 ? 0 : (cells[sorted[column - 1].index].bounds.midX + center) / 2
            let right = column == 6 ? 1 : (cells[sorted[column + 1].index].bounds.midX + center) / 2
            guard cell.bounds.minX >= left, cell.bounds.maxX <= right else { continue }
            assignments[column, default: []].append(index)
        }
        var output = cells.map(\.text)
        for (column, indices) in assignments where indices.count == 1 {
            let index = indices[0]
            output[index] = "\(sorted[column].day.capitalized) \(cells[index].text)"
        }
        return output.joined(separator: "\n")
    }
}
