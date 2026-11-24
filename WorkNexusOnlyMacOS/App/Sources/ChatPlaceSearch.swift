import CoreUI
import FeatureChat
import Foundation
import SharedKit
import SwiftUI

/// The title bar's search on the Chat page: chats by name and their stored messages. Each hit shows its chat's picture
/// and the words searched where they were found; a "Show all" row lists every match; clicked while empty, the field
/// offers the last searches and the chats last active. A hit opens the chat (at the message).
@MainActor
enum ChatPlaceSearch {
    static func make(chat: ChatWiring, accountId: String, isDemo: Bool) -> PlaceSearch {
        let finder = ChatGlobalSearch(repository: chat.repository, accountId: accountId)
        // A demo run keeps its searches apart from the installed app's.
        let recent = ChatRecentSearches(accountId: accountId, defaults: isDemo ? UserDefaults(suiteName: "com.worknexus.macos.demo") ?? .standard : .standard)
        return PlaceSearch(
            placeholder: appString("chatGlobalSearchHint", "Search chats and messages…"),
            scopes: ChatSearchChoices.kinds.map { PlaceSearchScope(id: $0.id, title: $0.title) },
            options: [PlaceSearchOption(id: "period", icon: "calendar.badge.clock", help: appString("chatSearchPeriod", "Time range"),
                                        choices: ChatSearchChoices.periods.map { PlaceSearchScope(id: $0.id, title: $0.title) })],
            note: appString("chatSearchLocalNote", "Searches what is stored on this Mac. Narrow it with from:name, in:chat, has:file or \"exact words\"."),
            suggestions: {
                let section = appString("chatSearchRecent", "Recent searches")
                var hits = recent.all.map { PlaceSearchHit(id: "recent:\($0)", section: section, icon: "clock.arrow.circlepath", title: $0, action: .fill($0)) }
                if !hits.isEmpty {
                    hits.append(PlaceSearchHit(id: "recent.clear", section: section, icon: "trash", title: appString("chatSearchClearRecent", "Clear recent searches"),
                                               action: .open { recent.clear() }))
                }
                let found = await finder.recent()
                return hits + found.chats.map { row($0, found, section: appString("chatSearchRecentChats", "Recent chats"), chat, accountId) }
            }, remember: { recent.add($0) }, search: { request in
                let found = await finder.search(request.query, kind: ChatSearchChoices.kind(request.scope), since: ChatSearchChoices.since(request.options["period"]),
                                                all: request.all)
                // A filter being typed: the names it could take come first.
                var hits = found.offers.map { offer in
                    PlaceSearchHit(id: "offer:\(offer.id)", section: offer.userId != nil ? appString("chatSearchSentBy", "Sent by") : appString("chatSearchInChat", "In chat"),
                                   icon: "line.3.horizontal.decrease", title: offer.title, subtitle: offer.subtitle,
                                   leading: avatar(chatGid: offer.chatGid, userId: offer.userId, found), action: .fill(offer.query))
                }
                hits += section(found.chats, found.chatCount, "chats", appString("chatGlobalSearchChats", "Chats"), appString("chatSearchAllChats", "Show all {count} chats"), found, chat, accountId)
                hits += section(found.people, found.peopleCount, "people", appString("chatSearchPeopleHeading", "People"), appString("chatSearchAllPeople", "Show all {count} people"), found, chat, accountId)
                // Narrowed to a kind, they are listed under its name (files under "Files").
                let heading = ChatSearchChoices.kinds.first { $0.id == request.scope && $0.id != ChatSearchChoices.allKinds }?.title
                hits += section(found.messages, found.messageCount, "messages", heading ?? appString("chatGlobalSearchMessages", "Messages"),
                                appString("chatSearchAllResults", "Show all {count} results"), found, chat, accountId, capped: found.messagesCapped)
                return hits
            })
    }

    /// The hits of one kind under their heading, with a "Show all" row while more match than are listed.
    private static func section(_ list: [ChatSearchHit], _ count: Int, _ kind: String, _ title: String, _ showAll: String, _ found: ChatSearchResults,
                                _ chat: ChatWiring, _ accountId: String, capped: Bool = false) -> [PlaceSearchHit] {
        var hits = list.map { row($0, found, section: title, chat, accountId) }
        if count > list.count {
            hits.append(PlaceSearchHit(id: "all.\(kind)", section: title, icon: "",
                                       title: showAll.replacingOccurrences(of: "{count}", with: "\(count)\(capped ? "+" : "")"), action: .showAll))
        }
        return hits
    }

    private static func row(_ hit: ChatSearchHit, _ found: ChatSearchResults, section: String, _ chat: ChatWiring, _ accountId: String) -> PlaceSearchHit {
        // A message can be searched on inside its chat, where older history can be loaded too.
        let words = ChatSearchChoices.words(found.terms)
        let further = hit.kind == .message && !words.isEmpty
            ? PlaceSearchHit.Extra(icon: "text.magnifyingglass", help: appString("chatSearchInThisChat", "Search in this chat")) {
                chat.events.open(chatGid: hit.chatGid, searching: words)
            } : nil
        return PlaceSearchHit(id: hit.id, section: section, icon: hit.kind == .person ? "person" : hit.kind == .chat ? "bubble.left.and.bubble.right" : "text.bubble",
                              title: hit.title, lead: hit.sender.map { "\($0): " } ?? "", subtitle: hit.subtitle, detail: hit.when,
                              marks: found.terms, marksTitle: hit.kind != .message,
                              leading: avatar(chatGid: hit.kind == .person ? nil : hit.chatGid, userId: hit.userId, found), extra: further,
                              action: .open { open(hit, chat, accountId) })
    }

    /// A chat's picture, or a person's.
    private static func avatar(chatGid: String?, userId: Int?, _ found: ChatSearchResults) -> AnyView? {
        if let userId { return AnyView(ChatSearchAvatar(userId: userId, users: found.users)) }
        return chatGid.flatMap { found.conversations[$0] }.map { AnyView(ChatSearchAvatar(chat: $0, users: found.users)) }
    }

    /// A message opens its chat at it, a chat opens, a person opens the one-to-one chat with them (made on first use).
    private static func open(_ hit: ChatSearchHit, _ chat: ChatWiring, _ accountId: String) {
        if let userId = hit.userId, hit.kind == .person {
            Task { @MainActor in
                if case .success(let gid) = await OpenDirectChat(chat.repository)(accountId: accountId, userId: userId) { chat.events.open(chatGid: gid) }
            }
        } else if let id = hit.serverId { chat.events.open(chatGid: hit.chatGid, jumpTo: id) } else { chat.events.open(chatGid: hit.chatGid) }
    }
}
