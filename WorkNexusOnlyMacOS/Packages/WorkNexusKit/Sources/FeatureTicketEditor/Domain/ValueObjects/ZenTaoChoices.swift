import CoreDomain

/// Ported from: lib/features/ticket_editor/domain/value_objects/zentao_choices.dart
/// ZenTao's fixed choices (its language lists, which its form pages do not send), labelled as ZenTao's English UI
/// labels them. A value a server has customised is still shown, by its key.
public enum ZenTaoChoices {
    public static let bugTypes: [FormOption] = [
        FormOption(value: "codeerror", label: "Code Error"),
        FormOption(value: "config", label: "Configuration"),
        FormOption(value: "install", label: "Installation"),
        FormOption(value: "security", label: "Security"),
        FormOption(value: "performance", label: "Performance"),
        FormOption(value: "standard", label: "Standard Specification"),
        FormOption(value: "automation", label: "Test Script"),
        FormOption(value: "designdefect", label: "Design Defect"),
        FormOption(value: "others", label: "Others"),
    ]

    public static let osList: [FormOption] = [
        FormOption(value: "all", label: "All"),
        FormOption(value: "windows", label: "Windows"),
        FormOption(value: "win11", label: "Windows 11"),
        FormOption(value: "win10", label: "Windows 10"),
        FormOption(value: "win8", label: "Windows 8"),
        FormOption(value: "win7", label: "Windows 7"),
        FormOption(value: "winxp", label: "Windows XP"),
        FormOption(value: "osx", label: "Mac OS"),
        FormOption(value: "android", label: "Android"),
        FormOption(value: "ios", label: "IOS"),
        FormOption(value: "linux", label: "Linux"),
        FormOption(value: "ubuntu", label: "Ubuntu"),
        FormOption(value: "chromeos", label: "Chrome OS"),
        FormOption(value: "fedora", label: "Fedora"),
        FormOption(value: "unix", label: "Unix"),
        FormOption(value: "others", label: "Others"),
    ]

    public static let browserList: [FormOption] = [
        FormOption(value: "all", label: "All"),
        FormOption(value: "chrome", label: "Chrome"),
        FormOption(value: "edge", label: "Edge"),
        FormOption(value: "ie", label: "IE series"),
        FormOption(value: "ie11", label: "IE11"),
        FormOption(value: "ie10", label: "IE10"),
        FormOption(value: "ie9", label: "IE9"),
        FormOption(value: "ie8", label: "IE8"),
        FormOption(value: "firefox", label: "Firefox series"),
        FormOption(value: "opera", label: "Opera series"),
        FormOption(value: "safari", label: "Safari"),
        FormOption(value: "360", label: "360 series"),
        FormOption(value: "qq", label: "QQ series"),
        FormOption(value: "other", label: "Others"),
    ]

    public static let taskTypes: [FormOption] = [
        FormOption(value: "design", label: "Design"),
        FormOption(value: "devel", label: "Development"),
        FormOption(value: "request", label: "Feature Request"),
        FormOption(value: "test", label: "Test"),
        FormOption(value: "study", label: "Research"),
        FormOption(value: "discuss", label: "Discussion"),
        FormOption(value: "ui", label: "UI"),
        FormOption(value: "affair", label: "Transaction"),
        FormOption(value: "misc", label: "Misc"),
    ]

    public static let taskStatuses: [FormOption] = [
        FormOption(value: "wait", label: "Waiting"),
        FormOption(value: "doing", label: "Doing"),
        FormOption(value: "done", label: "Done"),
        FormOption(value: "pause", label: "Paused"),
        FormOption(value: "cancel", label: "Cancelled"),
        FormOption(value: "closed", label: "Closed"),
    ]

    /// ZenTao's title colours (the web form's swatches), as `#rrggbb`.
    public static let titleColors = ["#3da7f5", "#75c941", "#2dbdb2", "#797ec9", "#ffaf38", "#ff4e3e"]

    /// `options` with `value` added (by its key) when a server uses a value the list does not have, so it still
    /// shows and is kept.
    public static func withValue(_ options: [FormOption], _ value: String) -> [FormOption] {
        value.isEmpty || options.contains(where: { $0.value == value }) ? options : options + [FormOption(value: value, label: value)]
    }
}
