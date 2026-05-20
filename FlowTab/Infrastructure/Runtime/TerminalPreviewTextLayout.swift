import Foundation

struct TerminalPreviewCellRun: Equatable {
    var text: String
    let column: Int
    let columnWidth: Int
}

enum TerminalPreviewTextLayout {
    private static let tabStopWidth = 8

    static func displayLines(from logicalLines: [String]) -> [String] {
        logicalLines.map(displayLine)
    }

    static func softWrappedLines(
        from logicalLines: [String],
        columnCount: Int,
        maxRows: Int
    ) -> [String] {
        let columns = max(1, columnCount)
        var visualLines: [String] = []
        visualLines.reserveCapacity(maxRows)

        for line in logicalLines {
            appendSoftWrappedLine(
                line,
                columnCount: columns,
                maxRows: maxRows,
                to: &visualLines
            )
        }

        return visualLines
    }

    static func columnCount(for line: String) -> Int {
        var columns = 0
        for character in displayLine(line) {
            columns += columnWidth(for: character)
        }
        return columns
    }

    static func cellRuns(in line: String, maxColumns: Int) -> [TerminalPreviewCellRun] {
        var runs: [TerminalPreviewCellRun] = []
        var column = 0

        for character in displayLine(line) {
            let width = columnWidth(for: character)
            guard width > 0 else {
                appendZeroWidthCharacter(character, to: &runs)
                continue
            }
            guard column < maxColumns else { break }
            defer { column += width }
            guard character != " " else { continue }

            runs.append(
                TerminalPreviewCellRun(
                    text: String(character),
                    column: column,
                    columnWidth: min(width, maxColumns - column)
                )
            )
        }

        return runs
    }

    private static func displayLine(_ line: String) -> String {
        let strippedLine = strippingTerminalControlSequences(from: line)
        var displayLine = ""
        var columns = 0

        for character in strippedLine {
            if character == "\t" {
                let spaces = columnsToNextTabStop(from: columns)
                displayLine += String(repeating: " ", count: spaces)
                columns += spaces
                continue
            }

            let width = columnWidth(for: character)
            guard width > 0 else {
                if shouldAttachToPreviousCell(character), !displayLine.isEmpty {
                    displayLine.append(character)
                }
                continue
            }
            displayLine.append(character)
            columns += width
        }

        return displayLine
    }

    private static func appendSoftWrappedLine(
        _ line: String,
        columnCount: Int,
        maxRows: Int,
        to visualLines: inout [String]
    ) {
        let displayLine = displayLine(line)
        guard !displayLine.isEmpty else {
            appendVisualLine("", maxRows: maxRows, to: &visualLines)
            return
        }

        var currentRow = ""
        var currentColumns = 0
        for character in displayLine {
            let width = columnWidth(for: character)
            guard width > 0 else {
                if shouldAttachToPreviousCell(character), !currentRow.isEmpty {
                    currentRow.append(character)
                }
                continue
            }
            if currentColumns > 0, currentColumns + width > columnCount {
                appendVisualLine(currentRow, maxRows: maxRows, to: &visualLines)
                currentRow = ""
                currentColumns = 0
            }
            currentRow.append(character)
            currentColumns += width
            if currentColumns >= columnCount {
                appendVisualLine(currentRow, maxRows: maxRows, to: &visualLines)
                currentRow = ""
                currentColumns = 0
            }
        }

        if !currentRow.isEmpty {
            appendVisualLine(currentRow, maxRows: maxRows, to: &visualLines)
        }
    }

    private static func appendVisualLine(
        _ line: String,
        maxRows: Int,
        to visualLines: inout [String]
    ) {
        visualLines.append(line)
        if visualLines.count > maxRows {
            visualLines.removeFirst(visualLines.count - maxRows)
        }
    }

    private static func appendZeroWidthCharacter(
        _ character: Character,
        to runs: inout [TerminalPreviewCellRun]
    ) {
        guard shouldAttachToPreviousCell(character), !runs.isEmpty else { return }
        runs[runs.count - 1].text.append(character)
    }

    private static func columnsToNextTabStop(from column: Int) -> Int {
        tabStopWidth - (column % tabStopWidth)
    }

    private static func columnWidth(for character: Character) -> Int {
        let visibleScalars = character.unicodeScalars.filter {
            !isZeroWidthScalar($0) && !isControlScalar($0)
        }
        guard !visibleScalars.isEmpty else { return 0 }
        return visibleScalars.contains(where: isWideTerminalScalar) ? 2 : 1
    }

    private static func shouldAttachToPreviousCell(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(isCombiningMarkScalar)
    }

    private static func strippingTerminalControlSequences(from line: String) -> String {
        let scalars = line.unicodeScalars
        var output = String()
        var index = scalars.startIndex

        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar.value == 0x1B {
                index = indexAfterEscapeSequence(startingAt: index, in: scalars)
                continue
            }
            if isControlScalar(scalar), scalar.value != 0x09 {
                index = scalars.index(after: index)
                continue
            }
            output.unicodeScalars.append(scalar)
            index = scalars.index(after: index)
        }

        return output
    }

    private static func indexAfterEscapeSequence(
        startingAt start: String.UnicodeScalarView.Index,
        in scalars: String.UnicodeScalarView
    ) -> String.UnicodeScalarView.Index {
        var index = scalars.index(after: start)
        guard index < scalars.endIndex else { return index }
        let introducer = scalars[index].value

        switch introducer {
        case 0x5B:
            return indexAfterCSISequence(startingAt: scalars.index(after: index), in: scalars)
        case 0x5D:
            return indexAfterStringControlSequence(startingAt: scalars.index(after: index), in: scalars)
        case 0x50, 0x5E, 0x5F, 0x58:
            return indexAfterStringControlSequence(startingAt: scalars.index(after: index), in: scalars)
        default:
            index = scalars.index(after: index)
            return index
        }
    }

    private static func indexAfterCSISequence(
        startingAt start: String.UnicodeScalarView.Index,
        in scalars: String.UnicodeScalarView
    ) -> String.UnicodeScalarView.Index {
        var index = start
        while index < scalars.endIndex {
            let value = scalars[index].value
            index = scalars.index(after: index)
            if value >= 0x40, value <= 0x7E {
                break
            }
        }
        return index
    }

    private static func indexAfterStringControlSequence(
        startingAt start: String.UnicodeScalarView.Index,
        in scalars: String.UnicodeScalarView
    ) -> String.UnicodeScalarView.Index {
        var index = start
        while index < scalars.endIndex {
            let value = scalars[index].value
            if value == 0x07 {
                return scalars.index(after: index)
            }
            if value == 0x1B {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next].value == 0x5C {
                    return scalars.index(after: next)
                }
            }
            index = scalars.index(after: index)
        }
        return index
    }

    private static func isControlScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F:
            return true
        default:
            return false
        }
    }

    private static func isZeroWidthScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x180B...0x180E,
             0x200B...0x200F,
             0x202A...0x202E,
             0x2060...0x206F,
             0xFE00...0xFE0F,
             0xFEFF,
             0xE0100...0xE01EF:
            return true
        default:
            return isCombiningMarkScalar(scalar)
        }
    }

    private static func isCombiningMarkScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0300...0x036F,
             0x1AB0...0x1AFF,
             0x1DC0...0x1DFF,
             0x20D0...0x20FF,
             0xFE20...0xFE2F:
            return true
        default:
            return false
        }
    }

    private static func isWideTerminalScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,
             0x2329...0x232A,
             0x2E80...0xA4CF,
             0xAC00...0xD7A3,
             0xF900...0xFAFF,
             0xFE10...0xFE19,
             0xFE30...0xFE6F,
             0xFF00...0xFF60,
             0xFFE0...0xFFE6,
             0x1F300...0x1FAFF:
            return true
        default:
            return false
        }
    }
}
