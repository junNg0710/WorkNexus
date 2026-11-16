import Foundation

/// Ported from: lib/core/util/zentao_labels.dart
/// Display labels for ZenTao's coded fields (severity / bug type / task type / resolution). They fall back to
/// the raw code when unknown.
public func zentaoSeverityLabel(_ severity: Int?) -> String? {
    switch severity { case 1: "Critical"; case 2: "Major"; case 3: "Minor"; case 4: "Trivial"; default: nil }
}

private let bugTypes: [(String, String)] = [
    ("codeerror", "Code error"), ("config", "Config"), ("install", "Installation"), ("security", "Security"),
    ("performance", "Performance"), ("standard", "Standard"), ("automation", "Automation"),
    ("designdefect", "Design defect"), ("interface", "Interface"), ("designchange", "Design change"),
    ("others", "Others"),
]
/// The stock ZenTao bug type codes, in ZenTao's own order.
public var zentaoBugTypeCodes: [String] { bugTypes.map(\.0) }

private func capitalized(_ code: String) -> String { code.prefix(1).uppercased() + code.dropFirst() }

public func zentaoBugTypeLabel(_ type: String?) -> String? {
    let code = type?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    if code.isEmpty { return nil }
    return bugTypes.first { $0.0 == code }?.1 ?? capitalized(code)
}

private let taskTypes: [String: String] = [
    "design": "Design", "devel": "Development", "request": "Feature request", "test": "Testing",
    "study": "Research", "discuss": "Discussion", "ui": "UI", "affair": "Transaction", "misc": "Misc",
]

public func zentaoTaskTypeLabel(_ type: String?) -> String? {
    let code = type?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    if code.isEmpty { return nil }
    return taskTypes[code] ?? capitalized(code)
}

private let resolutions: [(String, String)] = [
    ("bydesign", "By design"), ("duplicate", "Duplicate"), ("external", "External"), ("fixed", "Fixed"),
    ("notrepro", "Irreproducible"), ("willnotfix", "Won't fix"), ("postponed", "Postponed"),
    ("tostory", "Converted to story"),
]
/// The stock ZenTao bug resolution codes, in ZenTao's own order.
public var zentaoResolutionCodes: [String] { resolutions.map(\.0) }

public func zentaoResolutionLabel(_ resolution: String?) -> String? {
    let trimmed = resolution?.trimmingCharacters(in: .whitespaces) ?? ""
    if trimmed.isEmpty { return nil }
    return resolutions.first { $0.0 == trimmed.lowercased() }?.1 ?? trimmed
}

/// A human-readable file size (`39124123` -> `37.3 MB`). Nil/negative -> nil.
public func formatFileSize(_ bytes: Int?) -> String? {
    guard let bytes, bytes >= 0 else { return nil }
    if bytes < 1024 { return "\(bytes) B" }
    let units = ["KB", "MB", "GB", "TB"]
    var size = Double(bytes) / 1024
    var unit = 0
    while size >= 1024 && unit < units.count - 1 { size /= 1024; unit += 1 }
    let rounded = size >= 100 ? String(format: "%.0f", size) : String(format: "%.1f", size)
    return "\(rounded) \(units[unit])"
}
