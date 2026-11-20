/// Ported from: lib/features/chat/presentation/widgets/chat_profile_details.dart
import CoreDomain
import CoreUI
import SwiftUI

/// The Contact and Work sections: what chat knows of the person, completed by the tracker's profile once it answers. Empty
/// fields are left out, and so is a section with nothing to show.
struct ChatProfileDetails: View {
    let user: ChatUser?; let profile: ChatProfileModel.Load<PersonProfile>?

    private struct Row: Identifiable { let icon: String; let label: String; let value: String; var id: String { label } }

    private var contacts: [Row] {
        let p = profile?.value
        let all: [(String, String, String?)] = [
            ("envelope", shellString("chatEmail", "Email"), user?.email ?? p?.email),
            ("iphone", shellString("chatMobile", "Mobile"), user?.mobile ?? p?.mobile),
            ("phone", shellString("chatPhone", "Phone"), user?.phone ?? p?.phone),
            ("message", appString("profileWechat", "WeChat"), p?.wechat),
            ("number", appString("profileSlack", "Slack"), p?.slack),
            ("video", appString("profileSkype", "Skype"), p?.skype),
            ("ellipsis.message", appString("profileWhatsapp", "WhatsApp"), p?.whatsapp),
            ("at", appString("profileQq", "QQ"), p?.qq),
            ("paperplane", appString("profileDingding", "DingDing"), p?.dingding),
        ]
        return all.compactMap { icon, label, value in
            let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : Row(icon: icon, label: label, value: v)
        }
    }

    private var work: [Row] {
        guard let p = profile?.value else { return [] }
        var out: [Row] = []
        if let d = p.department { out.append(Row(icon: "building.2", label: appString("profileDepartment", "Department"), value: d)) }
        if let j = p.joined { out.append(Row(icon: "calendar.badge.checkmark", label: appString("profileJoined", "Joined"), value: Self.date(j, time: false))) }
        if let l = p.lastLogin { out.append(Row(icon: "clock.arrow.circlepath", label: appString("profileLastLogin", "Last Login"), value: Self.date(l, time: true))) }
        if let a = p.address { out.append(Row(icon: "mappin.and.ellipse", label: appString("profileAddress", "Address"), value: a)) }
        return out
    }

    private static func date(_ d: Date, time: Bool) -> String { d.formatted(date: .abbreviated, time: time ? .shortened : .omitted) }

    var body: some View {
        let contacts = contacts, work = work
        let loading = profile?.isLoading ?? false, failed = profile?.failed ?? false
        if !contacts.isEmpty || loading {
            ChatProfileSection(title: shellString("chatProfileContact", "Contact")) {
                if contacts.isEmpty { ChatProfileLoadingRows() }
                ForEach(contacts) { ChatProfileInfoRow(icon: $0.icon, label: $0.label, value: $0.value, copyable: true) }
            }
        }
        // The skeleton shows once: under Contact while that is empty too.
        if !work.isEmpty || (loading && !contacts.isEmpty) || (failed && contacts.isEmpty) {
            ChatProfileSection(title: shellString("chatProfileOrganisation", "Work")) {
                ForEach(work) { ChatProfileInfoRow(icon: $0.icon, label: $0.label, value: $0.value) }
                if work.isEmpty && loading { ChatProfileLoadingRows() }
                if work.isEmpty && !loading { ChatProfileNote(text: shellString("chatProfileLoadFailed", "Couldn't load this right now"), isError: true) }
            }
        }
    }
}
