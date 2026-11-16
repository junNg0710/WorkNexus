import CoreDomain
import CoreTools
import CoreUI
import SwiftUI

/// Ported from: lib/app/shell/workspace_breadcrumb{,_trigger}.dart — the trail on the left of the title bar:
/// `[badge] Workspace ▾ / Tool / Section / Scope`. The workspace opens the switcher; the tool and the section are links
/// back up the trail; the scope is the open product / project / repository (its name, from `ToolModule.scopeTitle`).
struct WorkspaceBreadcrumb: View {
    @Environment(\.appTheme) private var theme
    let model: ShellModel
    @State private var switcherOpen = false

    var body: some View {
        HStack(spacing: theme.spacing.s2) {
            if let ws = model.workspace {
                WorkspaceBreadcrumbTrigger(workspace: ws, isOpen: switcherOpen) { switcherOpen.toggle() }
                    .popover(isPresented: $switcherOpen, arrowEdge: .bottom) {
                        WorkspaceSwitcherPopover(model: model) { switcherOpen = false }.environment(\.appTheme, theme)
                    }
            }
            trail
        }
        .lineLimit(1)
    }

    @ViewBuilder private var trail: some View {
        if let id = model.nav.state.miniAppId {
            segment(appString("miniApps", "Mini apps"), link: nil)
            segment(model.host.miniAppName(id) ?? appString("miniApps", "Mini apps"), link: nil)
        } else {
            switch model.nav.state.rail {
            case .workspace:
                segment(ShellSections.label(ShellSections.workspace, model.nav.state.workspaceSection), link: nil)
            case .settings:
                segment(appString("settings", "Settings"), link: nil)
                segment(ShellSections.label(ShellSections.settings, model.nav.state.settingsSection), link: nil)
            case .chat:
                if let provider = model.chatAccount?.providerType { TrailLogo(provider: provider) }
                segment(appString("chat", "Chat"), link: nil)
            case .account(let id):
                if let account = model.account(id), let tool = model.registry.module(for: account.providerType) {
                    AccountTrail(model: model, account: account, tool: tool)
                }
            }
        }
    }

    private func segment(_ title: String, link: (() -> Void)?) -> some View {
        BreadcrumbSegment(title: title, link: link)
    }
}

/// The tool's logo at the head of its trail, so a ZenTao place says so at a glance.
private struct TrailLogo: View {
    @Environment(\.appTheme) private var theme
    let provider: ProviderType
    var body: some View { BrandLogoBadge(provider, size: 16).padding(.leading, theme.spacing.s6) }
}

/// `/ Tool / Section / Scope` of an account place.
private struct AccountTrail: View {
    let model: ShellModel
    let account: Account
    let tool: any ToolModule

    var body: some View {
        let location = model.nav.location(for: account.id)
        let several = model.accounts.filter { $0.providerType == account.providerType }.count > 1
        let section = tool.sections.first { $0.id == location.section }
        let hasScope = !(location.scopeId ?? "").isEmpty
        TrailLogo(provider: account.providerType)
        BreadcrumbSegment(title: several ? account.handle : account.providerType.displayName,
                          link: { model.nav.select(.account(account.id)) })
        BreadcrumbSegment(title: section.map { appString($0.label, $0.label.capitalized) } ?? location.section.rawValue,
                          link: hasScope ? { model.nav.setScope(nil, accountId: account.id) } : nil)
        if hasScope {
            ScopeTitleSegment(tool: tool, account: account, location: location)
        }
    }
}

/// The scope's name as the tool streams it, the raw id until it arrives.
private struct ScopeTitleSegment: View {
    let tool: any ToolModule
    let account: Account
    let location: ToolLocation
    @State private var title: String?

    var body: some View {
        BreadcrumbSegment(title: title ?? location.scopeId ?? "", link: nil)
            .task(id: "\(account.id)|\(location.section.rawValue)|\(location.scopeId ?? "")") {
                title = nil
                guard let stream = tool.scopeTitle(account: account, location: location) else { return }
                for await t in stream { title = t }
            }
    }
}

/// One `/ label` of the trail; a link (secondary text, hover tint) when it can go back up, else the strong current label.
struct BreadcrumbSegment: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let link: (() -> Void)?

    var body: some View {
        Text("/").font(theme.typography.caption).foregroundStyle(theme.colors.tx3).padding(.horizontal, theme.spacing.s4)
        if let link {
            HoverSurface(onTap: link, cornerRadius: theme.radii.sm) {
                Text(title).font(theme.typography.body).foregroundStyle(theme.colors.tx2)
                    .padding(.horizontal, theme.spacing.s4)
            }
        } else {
            Text(title).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
        }
    }
}

/// The clickable workspace chip at the head of the trail.
struct WorkspaceBreadcrumbTrigger: View {
    @Environment(\.appTheme) private var theme
    let workspace: Workspace
    let isOpen: Bool
    let onTap: () -> Void

    var body: some View {
        HoverSurface(onTap: onTap, selected: isOpen, height: theme.sizes.control32, cornerRadius: theme.radii.sm) {
            HStack(spacing: theme.spacing.s8) {
                WorkspaceBadge(Color(argb: UInt32(truncatingIfNeeded: workspace.colorValue)), workspace.shortCode, iconKey: workspace.iconKey)
                Text(workspace.name).font(theme.typography.bodyStrong).foregroundStyle(theme.colors.tx)
                Image(systemName: "chevron.down").font(.system(size: theme.sizes.icon12)).foregroundStyle(theme.colors.tx2)
            }
            .padding(.horizontal, theme.spacing.s8)
        }
    }
}
