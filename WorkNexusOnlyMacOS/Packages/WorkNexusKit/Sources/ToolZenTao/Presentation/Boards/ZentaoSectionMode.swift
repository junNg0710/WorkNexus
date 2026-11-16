/// Ported from: lib/tools/zentao/presentation/sections/zentao_{bugs,tasks}_section.dart (`modes`, view mode resolution)
import CoreDomain
import CoreTools
import Foundation

enum ZentaoSectionMode {
    /// The bug board's modes, in its order, so both boards read alike.
    static let modes = [ToolViewMode(id: "board", label: "viewBoard", systemImage: "rectangle.split.3x1"),
                        ToolViewMode(id: "list", label: "viewList", systemImage: "list.bullet")]

    /// The location's view mode, else the one remembered in the settings, else the board.
    static func mode(_ location: ToolLocation, _ section: SectionID, settings: AppSettings) -> ViewModeID {
        location.viewModes[section] ?? settings.viewModes[section.rawValue].map { ViewModeID($0) } ?? "board"
    }
}
