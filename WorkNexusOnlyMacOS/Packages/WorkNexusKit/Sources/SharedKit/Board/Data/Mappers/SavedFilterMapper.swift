import CoreDomain
import Foundation

/// Ported from: lib/shared/board/data/mappers/saved_filter_mapper.dart
/// JSON (de)serialization for the board's filter presets. `workspaceId` is deliberately not persisted (it is the
/// board's scope, not a criterion). Unknown enum names (saved by a newer build) are dropped rather than failing.
public enum SavedFilterMapper {
    public static func encode(_ f: FilterState) -> String {
        let obj: [String: Any] = [
            "savedView": f.savedView.rawValue,
            "providers": f.providers.map(\.rawValue).sorted(),
            "accountIds": f.accountIds.sorted(), "projectIds": f.projectIds.sorted(),
            "statuses": f.statuses.map(\.rawValue).sorted(), "priorities": f.priorities.map(\.rawValue).sorted(),
            "severities": f.severities.sorted(), "assignees": f.assignees.sorted(), "reviewers": f.reviewers.sorted(),
            "bugTypes": f.bugTypes.sorted(), "resolutions": f.resolutions.sorted(),
            "zentaoStatuses": f.zentaoStatuses.sorted(), "resolvers": f.resolvers.sorted(),
            "reporters": f.reporters.sorted(), "confirmations": f.confirmations.sorted(),
            "modules": f.modules.sorted(), "search": f.search,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ json: String) -> FilterState {
        guard let map = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return FilterState() }
        var f = FilterState()
        f.savedView = savedView(map["savedView"])
        f.providers = enumSet(map["providers"])
        f.accountIds = stringSet(map["accountIds"]); f.projectIds = stringSet(map["projectIds"])
        f.statuses = enumSet(map["statuses"]); f.priorities = enumSet(map["priorities"])
        f.severities = Set(list(map["severities"]).compactMap { ($0 as? Int) ?? Int("\($0)") })
        f.assignees = stringSet(map["assignees"]); f.reviewers = stringSet(map["reviewers"])
        f.bugTypes = stringSet(map["bugTypes"]); f.resolutions = stringSet(map["resolutions"])
        f.zentaoStatuses = stringSet(map["zentaoStatuses"]); f.resolvers = stringSet(map["resolvers"])
        f.reporters = stringSet(map["reporters"]); f.confirmations = stringSet(map["confirmations"])
        f.modules = stringSet(map["modules"])
        f.search = (map["search"] as? String) ?? ""
        return f
    }

    /// "mine" (the ZenTao boards' view before "Related to me" took its place) opens as Related to me.
    private static func savedView(_ raw: Any?) -> SavedView {
        guard let name = raw.map({ "\($0)" }), let v = SavedView(rawValue: name) else { return .all }
        return v == .mine ? .related : v
    }
    private static func list(_ raw: Any?) -> [Any] { (raw as? [Any]) ?? [] }
    private static func stringSet(_ raw: Any?) -> Set<String> { Set(list(raw).map { "\($0)" }) }
    private static func enumSet<T: RawRepresentable & Hashable>(_ raw: Any?) -> Set<T> where T.RawValue == String {
        Set(list(raw).compactMap { T(rawValue: "\($0)") })
    }
}
