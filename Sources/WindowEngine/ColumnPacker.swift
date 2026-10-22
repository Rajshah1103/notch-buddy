import CoreGraphics
import Foundation

public enum PackItem<Element: Hashable>: Hashable {
    case header(String)
    case entry(Element)
}

public struct PackedColumns<Element: Hashable> {
    public let columns: [[PackItem<Element>]]
    /// Entries that did not fit. The UI shows "N more" instead of scrolling.
    public let overflow: Int
}

/// Flows items down fixed-height columns so a list is always fully visible, never scrolled.
/// When a group is split across columns, its heading is repeated so no column is ever anonymous.
public enum ColumnPacker {
    public static func pack<Element: Hashable>(
        _ items: [PackItem<Element>],
        columnHeight: CGFloat, headerCost: CGFloat, rowCost: CGFloat, maxColumns: Int
    ) -> PackedColumns<Element> {
        func cost(_ column: [PackItem<Element>]) -> CGFloat {
            column.reduce(0) { total, item in
                if case .header = item { return total + headerCost }
                return total + rowCost
            }
        }

        var columns: [[PackItem<Element>]] = [[]]
        var section: String?

        for item in items {
            switch item {
            case .header(let title):
                section = title
                // A heading needs room for at least one row below it.
                if cost(columns[columns.count - 1]) + headerCost + rowCost > columnHeight { columns.append([]) }
                columns[columns.count - 1].append(item)
            case .entry:
                if cost(columns[columns.count - 1]) + rowCost > columnHeight {
                    columns.append([])
                    if let section { columns[columns.count - 1].append(.header(continued(section))) }
                }
                columns[columns.count - 1].append(item)
            }
        }

        columns = columns.filter { !$0.isEmpty }
        guard columns.count > maxColumns else { return PackedColumns(columns: columns, overflow: 0) }

        var kept = Array(columns.prefix(maxColumns))
        var overflow = columns.dropFirst(maxColumns).joined().filter { if case .entry = $0 { true } else { false } }.count

        // Make room for the "N more" row at the bottom of the last visible column.
        let last = maxColumns - 1
        while cost(kept[last]) + rowCost > columnHeight, !kept[last].isEmpty {
            if case .entry = kept[last].removeLast() { overflow += 1 }
        }
        if case .header = kept[last].last { kept[last].removeLast() }
        return PackedColumns(columns: kept, overflow: overflow)
    }

    private static func continued(_ title: String) -> String {
        title.hasSuffix("(cont.)") ? title : "\(title) (cont.)"
    }
}
