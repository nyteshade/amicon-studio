#if os(macOS)
import Foundation
import Combine

/// Snapshot-based undo/redo for the value-type `IconProject`. Each entry is a
/// copy of the project struct; the embedded image `Data` is copy-on-write, so
/// snapshots share image bytes until an image actually changes — keeping memory
/// reasonable. `sync(_:)` is driven from a top-level `.onChange`.
final class UndoHistory: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [IconProject] = []
    private var redoStack: [IconProject] = []
    private var current: IconProject?
    private var applying = false
    private let limit = 50

    /// Record a transition to `project` (no-op while applying an undo/redo).
    func sync(_ project: IconProject) {
        if applying { current = project; return }
        if let prev = current, prev != project {
            undoStack.append(prev)
            if undoStack.count > limit { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        current = project
        refresh()
    }

    func undo(_ project: inout IconProject) {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(project)
        applying = true; project = prev; current = prev; applying = false
        refresh()
    }

    func redo(_ project: inout IconProject) {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        applying = true; project = next; current = next; applying = false
        refresh()
    }

    private func refresh() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }
}
#endif
