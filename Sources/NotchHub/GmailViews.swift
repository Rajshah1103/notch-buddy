import GmailKit
import NotchCore
import SwiftUI

private let gmailRed = Color(red: 0.92, green: 0.26, blue: 0.21)

/// Header chip: how many unread messages are in the inbox.
struct GmailChip: View {
    @ObservedObject var model: GmailModel
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "envelope.fill").font(.system(size: 10, weight: .bold))
                if let snapshot = model.snapshot {
                    Text(snapshot.unread > 99 ? "99+" : "\(snapshot.unread)")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    if snapshot.unread > 0 { Circle().fill(gmailRed).frame(width: 6, height: 6) }
                } else if model.state != .loading, model.state != .ready {
                    Text("Set up").font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
            }
            .foregroundStyle(isOpen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(isOpen ? Theme.fillSelected : (hovering ? Theme.fillHover : Theme.fillQuiet)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerHover { hovering = $0 }
        .help("Gmail")
        .accessibilityLabel(model.snapshot.map { "Gmail, \($0.unread) unread" } ?? "Gmail, not connected")
        .accessibilityHint("Shows your newest unread messages")
    }
}

struct GmailPanel: View {
    @ObservedObject var model: GmailModel
    let notch: NotchState

    var body: some View {
        switch model.state {
        case .loading:
            Notice(symbol: "envelope", title: "Loading Gmail…", detail: nil)
        case .needsSetup:
            Setup(model: model, notch: notch)
        case .needsSignIn(let note):
            SignIn(model: model, note: note)
        case .signingIn:
            Notice(symbol: "safari", title: "Finish signing in in your browser", detail: "Pick your Google account and allow read-only access.")
        case .ready:
            if let snapshot = model.snapshot {
                Inbox(model: model, snapshot: snapshot, notch: notch)
            } else if let error = model.error {
                Notice(symbol: "wifi.exclamationmark", title: error.message, detail: "It will retry on its own.")
            } else {
                Notice(symbol: "envelope", title: "Loading Gmail…", detail: nil)
            }
        }
    }
}

// MARK: - Inbox

private struct Inbox: View {
    @ObservedObject var model: GmailModel
    let snapshot: GmailSnapshot
    let notch: NotchState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill").foregroundStyle(gmailRed)
                Text("Unread").font(.system(size: 15, weight: .semibold))
                Text("\(snapshot.unread) in \(snapshot.email)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let error = model.error {
                    Label(error.message, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange)
                }
                Button("Open Gmail") { open(inboxURL); notch.collapse() }.buttonStyle(.link).font(.system(size: 12))
                Button("Disconnect") { model.disconnect() }.buttonStyle(.link).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    if snapshot.messages.isEmpty {
                        Text("Inbox zero").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(snapshot.messages) { message in
                        MessageRow(message: message) {
                            open(URL(string: "https://mail.google.com/mail/?authuser=\(snapshot.email)#inbox/\(message.id)"))
                            notch.collapse()
                        }
                    }
                    ForEach(model.older) { message in
                        MessageRow(message: message) {
                            open(URL(string: "https://mail.google.com/mail/?authuser=\(snapshot.email)#inbox/\(message.id)"))
                            notch.collapse()
                        }
                    }
                    if model.hasMore {
                        // Reaching the end of the list asks for the next page.
                        Text("Loading more…").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 28)
                            .id(model.older.count)       // a fresh row after each page, so it fires again
                            .onAppear { model.loadMore() }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
    }

    private var inboxURL: URL? { URL(string: "https://mail.google.com/mail/?authuser=\(snapshot.email)#inbox") }
    private func open(_ url: URL?) { if let url { LinkOpener.open(url, for: "gmail") } }
}

private struct MessageRow: View {
    let message: GmailMessage
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(gmailRed).frame(width: 7, height: 7).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.from).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(message.subject).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let date = message.date {
                    Text(RelativeTime.ago(date)).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering ? Theme.fillHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pointerHover { hovering = $0 }
        .accessibilityLabel("\(message.from), \(message.subject)")
        .accessibilityHint("Opens the message in Gmail")
    }
}

// MARK: - Setting up

private struct Setup: View {
    @ObservedObject var model: GmailModel
    let notch: NotchState
    @FocusState private var focused: Bool

    private var ready: Bool {
        !model.draftClientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.draftSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text("Connect Gmail").font(.system(size: 17, weight: .semibold))
            Text("See your newest unread mail from the notch. Paste the Client ID and secret of a \u{201C}Desktop app\u{201D} OAuth client from your own Google Cloud project, or paste the JSON file Google lets you download to fill both at once. They stay in your Keychain, and the app can only read.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 540)
            VStack(spacing: 8) {
                TextField("Client ID", text: $model.draftClientID).textFieldStyle(.roundedBorder).focused($focused)
                    // Pasting Google's downloaded JSON here fills both fields at once.
                    .onChange(of: model.draftClientID) { _, text in if text.contains("{") { model.absorb(pasted: text) } }
                SecureField("Client secret", text: $model.draftSecret).textFieldStyle(.roundedBorder).onSubmit(connect)
            }
            .frame(width: 420)
            HStack(spacing: 14) {
                Button("Save and sign in", action: connect).disabled(!ready)
                Button("Open Google Cloud credentials") {
                    if let url = URL(string: "https://console.cloud.google.com/apis/credentials") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link).font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .onAppear {
            notch.setTyping(true)
            DispatchQueue.main.async { focused = true }
        }
        .onDisappear { notch.setTyping(false) }
        .onKeyPress(.escape) { notch.collapse(); return .handled }
    }

    private func connect() {
        guard ready else { return }
        model.saveClient(id: model.draftClientID, secret: model.draftSecret)
    }
}

private struct SignIn: View {
    @ObservedObject var model: GmailModel
    let note: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text("Sign in to Gmail").font(.system(size: 17, weight: .semibold))
            if let note { Text(note).font(.system(size: 12)).foregroundStyle(.orange) }
            Text("Opens Google in your browser. Notch Hub asks only to read your mail.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 14) {
                Button("Sign in with Google") { model.signIn() }.keyboardShortcut(.defaultAction)
                Button("Use a different client") { model.disconnect() }.buttonStyle(.link).font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }
}

private struct Notice: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text(title).font(.system(size: 14, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}
