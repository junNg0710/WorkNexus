/// Ported from: lib/shared/board/domain/value_objects/paging_policy.dart
/// Tickets per page of a column's view: enough to fill a column, small enough that the board shows up quickly.
public let kPagedViewPageSize = 50
/// Pages a filtered board fetches per load, side by side.
public let kFilteredPagesPerLoad = 4
/// How many loads in a row a filtered column fetches by itself while they add no visible card.
public let kMaxDryLoads = 2
