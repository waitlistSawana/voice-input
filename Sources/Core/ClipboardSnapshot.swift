import AppKit
import Foundation

public enum ClipboardSnapshotFlavor: Equatable, Sendable {
    case data(Data)
    case string(String)
}

public struct ClipboardSnapshot: Equatable, Sendable {
    public var items: [[String: ClipboardSnapshotFlavor]]

    public init(items: [[String: ClipboardSnapshotFlavor]] = []) {
        self.items = items
    }
}

extension ClipboardSnapshot {
    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            var snapshotItem: [String: ClipboardSnapshotFlavor] = [:]
            for pasteboardType in item.types {
                if let data = item.data(forType: pasteboardType) {
                    snapshotItem[pasteboardType.rawValue] = .data(data)
                    continue
                }

                if let string = item.string(forType: pasteboardType) {
                    snapshotItem[pasteboardType.rawValue] = .string(string)
                }
            }
            return snapshotItem
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let itemsToWrite = items.map { snapshotItem -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()

            for (typeName, flavor) in snapshotItem {
                let pasteboardType = NSPasteboard.PasteboardType(typeName)
                switch flavor {
                case let .data(data):
                    pasteboardItem.setData(data, forType: pasteboardType)
                case let .string(string):
                    pasteboardItem.setString(string, forType: pasteboardType)
                }
            }

            return pasteboardItem
        }

        pasteboard.writeObjects(itemsToWrite)
    }
}
