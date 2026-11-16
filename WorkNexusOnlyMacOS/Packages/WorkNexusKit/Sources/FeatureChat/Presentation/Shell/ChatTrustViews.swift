import CoreDomain
import AppKit
import CoreUI
import SwiftUI

/// The whole chat view while the chat server's certificate is unconfirmed: chat cannot connect before then, so a list and
/// thread would only sit empty; this says why and leads to the confirmation.
/// Ported from: lib/features/chat/presentation/widgets/chat_trust_gate.dart
struct ChatTrustGate: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let host: String

    var body: some View {
        VStack(spacing: theme.spacing.s12) {
            Image(systemName: "lock.shield").font(.system(size: theme.sizes.icon24 * 2)).foregroundStyle(theme.colors.tx3)
            Text(shellString("chatTrustGateTitle", "Confirm the chat server to start chatting"))
                .font(theme.typography.titleSm).foregroundStyle(theme.colors.tx)
            Text(shellString("chatTrustGateBody", "{host} uses its own certificate. Confirm it once and chat connects; until then, chat stays off.", ["host": host]))
                .font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2).multilineTextAlignment(.center)
            AppButton(shellString("chatReviewCertificate", "Review certificate"), systemImage: "checkmark.shield", kind: .primary) {
                model.showTrust = true
            }
        }
        .frame(maxWidth: theme.sizes.dialogSm).padding(theme.spacing.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Trust-on-first-use: explains why the chat server's self-signed certificate needs confirming, shows it, and pins its
/// fingerprint when the user accepts. Chat cannot connect until then.
/// Ported from: lib/features/chat/presentation/widgets/chat_trust_dialog.dart
struct ChatTrustDialog: View {
    @Environment(\.appTheme) private var theme
    let model: ChatShellModel
    let request: (host: String, fingerprint: String, subject: String, issuer: String)
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        AppDialogFrame(title: shellString("chatTrustTitle", "Confirm the chat server"), leadingIcon: "lock.shield",
                       maxWidth: theme.sizes.dialogMd, onClose: { model.showTrust = false }) {
            FitOrScroll(maxHeight: theme.sizes.dialogLg) {
                VStack(alignment: .leading, spacing: theme.spacing.s20) {
                    Text(shellString("chatTrustBody", "{host} secures chat with its own (self-signed) certificate, not one your system already trusts, so WorkNexus checks with you once before connecting.", ["host": request.host]))
                        .font(theme.typography.paragraph).foregroundStyle(theme.colors.tx2)
                    ChatTrustReasons()
                    ChatCertificateCard(host: request.host, subject: request.subject, issuer: request.issuer, fingerprint: request.fingerprint)
                    if let error { AppInlineNote(error, isError: true) }
                }
                .padding(.horizontal, theme.spacing.s24).padding(.bottom, theme.spacing.s24)
            }
        } actions: {
            Spacer(minLength: 0)
            AppButton(shellString("chatTrustLater", "Not now"), kind: .ghost) { model.showTrust = false }.disabled(busy)
            AppButton(shellString("chatTrustAction", "Trust and connect"), systemImage: "checkmark.shield", kind: .primary) {
                busy = true; error = nil
                Task { error = await model.trust(fingerprint: request.fingerprint); busy = false }
            }
            .disabled(busy)
        }
    }
}

/// "Why am I asked?": what confirming the chat server's certificate does, so the step reads as protection.
/// Ported from: lib/features/chat/presentation/widgets/chat_trust_reasons.dart
struct ChatTrustReasons: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            Text(shellString("chatTrustWhy", "Why am I asked?")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
            ReasonRow("clock.arrow.circlepath", shellString("chatTrustWhyOnce", "Only once. WorkNexus remembers this exact certificate and connects on its own after that."))
            ReasonRow("exclamationmark.shield", shellString("chatTrustWhyChange", "If it ever changes unexpectedly, you are asked again instead of being connected silently. A changed certificate can mean someone is intercepting the connection."))
            ReasonRow("person.badge.shield.checkmark", shellString("chatTrustWhyCheck", "Not sure? Ask your ZenTao administrator to confirm the fingerprint below."))
        }
    }
}

private struct ReasonRow: View {
    @Environment(\.appTheme) private var theme
    let icon: String, text: String
    init(_ icon: String, _ text: String) { self.icon = icon; self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s8) {
            Image(systemName: icon).font(.system(size: theme.sizes.icon14)).foregroundStyle(theme.colors.accent)
            Text(text).font(theme.typography.paragraph).foregroundStyle(theme.colors.tx).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The certificate the chat server presented: who it is for, who issued it and its SHA-256 fingerprint, copyable.
/// Ported from: lib/features/chat/presentation/widgets/chat_certificate_card.dart
struct ChatCertificateCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.toasts) private var toasts
    let host: String, subject: String, issuer: String, fingerprint: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s8) {
            CertField(label: shellString("chatTrustServer", "Server"), value: host)
            CertField(label: shellString("chatTrustSubject", "Issued to"), value: ChatShellLabels.certificateName(subject))
            CertField(label: shellString("chatTrustIssuer", "Issued by"), value: ChatShellLabels.certificateName(issuer))
            HStack {
                Text(shellString("chatTrustFingerprint", "SHA-256 fingerprint")).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
                Spacer(minLength: 0)
                AppIconButton("doc.on.doc", help: shellString("chatTrustCopyFingerprint", "Copy fingerprint")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(fingerprint, forType: .string)
                    toasts?.show(shellString("chatTrustFingerprintCopied", "Fingerprint copied"))
                }
            }
            Text(ChatShellLabels.fingerprintLines(fingerprint)).font(theme.typography.mono).foregroundStyle(theme.colors.tx)
                .textSelection(.enabled)
        }
        .padding(theme.spacing.s14).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.panel2, in: RoundedRectangle(cornerRadius: theme.radii.md))
        .overlay(RoundedRectangle(cornerRadius: theme.radii.md).stroke(theme.colors.line, lineWidth: theme.borders.hairline))
    }
}

private struct CertField: View {
    @Environment(\.appTheme) private var theme
    let label: String, value: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s2) {
            Text(label).font(theme.typography.label).foregroundStyle(theme.colors.tx2)
            Text(value).font(theme.typography.body).foregroundStyle(theme.colors.tx).textSelection(.enabled)
        }
    }
}
