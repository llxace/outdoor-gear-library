import SwiftUI
import AppKit

@main struct OutdoorGearApp: App {
    @StateObject private var libraries = UserLibraries()
    @State private var showLaunchAnimation = true
    private var store: GearStore { libraries.store }
    private var appearance: GearAppearance { GearAppearance(rawValue: store.inventory.settings.appearance) ?? .system }
    var body: some Scene {
        WindowGroup("户外装备库") {
            ZStack {
                NativeLibrary().environmentObject(store).environmentObject(libraries).id(libraries.selectedID)
                    .frame(minWidth: 1040, minHeight: 660)
                    .disabled(showLaunchAnimation)
                if showLaunchAnimation {
                    LaunchSplash {
                        withAnimation(.easeOut(duration: 0.32)) { showLaunchAnimation = false }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .background(LaunchWindowChrome(hidden: showLaunchAnimation))
            .toolbar(showLaunchAnimation ? .hidden : .visible, for: .windowToolbar)
            .preferredColorScheme(appearance.scheme).tint(GearDesign.controls).accentColor(GearDesign.controls)
            .onAppear { NSApp.appearance = appearance.native }
            .onChange(of: store.inventory.settings.appearance) { _ in NSApp.appearance = appearance.native }
        }.defaultSize(width: 1320, height: 860)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("导入 Excel…") {
                        NotificationCenter.default.post(name: Notification.Name("ImportExcel"), object: nil)
                    }.keyboardShortcut("i", modifiers: [.command]).disabled(!store.ready)
                    Button("导入 CSV / TSV…") { store.importCSV() }.disabled(!store.ready)
                    Button("导出完整字段 CSV…") { store.exportCSV() }.disabled(!store.ready)
                    Divider()
                    Button("保存完整备份…") { store.exportBackup() }.disabled(!store.ready)
                    Button("恢复备份…") { store.importBackup() }.disabled(!store.ready)
                }
            }
        Settings {
            LibraryPreferences().environmentObject(store).environmentObject(libraries).id(libraries.selectedID)
                .preferredColorScheme(appearance.scheme)
                .tint(GearDesign.controls).accentColor(GearDesign.controls)
        }
    }
}

private struct LaunchWindowChrome: NSViewRepresentable {
    let hidden: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { context.coordinator.apply(hidden: hidden, to: window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        context.coordinator.apply(hidden: hidden, to: window)
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var originalStyleMask: NSWindow.StyleMask?
        private var originalTitleVisibility: NSWindow.TitleVisibility?
        private var originalTitlebarTransparency: Bool?
        private var originalToolbarVisibility: Bool?
        private var originalButtonVisibility: [(NSWindow.ButtonType, Bool)] = []

        func apply(hidden: Bool, to window: NSWindow) {
            if self.window !== window {
                self.window = window
                originalStyleMask = window.styleMask
                originalTitleVisibility = window.titleVisibility
                originalTitlebarTransparency = window.titlebarAppearsTransparent
                originalToolbarVisibility = window.toolbar?.isVisible
                originalButtonVisibility = [
                    .closeButton, .miniaturizeButton, .zoomButton, .toolbarButton,
                ].compactMap { type in
                    window.standardWindowButton(type).map { (type, !$0.isHidden) }
                }
            }

            if hidden {
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.toolbar?.isVisible = false
                for (type, _) in originalButtonVisibility {
                    window.standardWindowButton(type)?.isHidden = true
                }
            } else {
                if let originalStyleMask { window.styleMask = originalStyleMask }
                if let originalTitlebarTransparency { window.titlebarAppearsTransparent = originalTitlebarTransparency }
                if let originalTitleVisibility { window.titleVisibility = originalTitleVisibility }
                if let originalToolbarVisibility { window.toolbar?.isVisible = originalToolbarVisibility }
                for (type, wasVisible) in originalButtonVisibility {
                    window.standardWindowButton(type)?.isHidden = !wasVisible
                }
            }
        }
    }
}

private struct LaunchSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = false
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            GearDesign.background.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(GearDesign.accent.opacity(0.16), lineWidth: 1)
                        .frame(width: 102, height: 102)
                    Circle()
                        .trim(from: 0, to: reveal ? 1 : 0.08)
                        .stroke(GearDesign.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 102, height: 102)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(GearDesign.accent)
                        .scaleEffect(reveal || reduceMotion ? 1 : 0.82)
                }
                .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("户外装备库")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("让每一次出发，都有迹可循")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .opacity(reveal || reduceMotion ? 1 : 0)
                .offset(y: reveal || reduceMotion ? 0 : 6)

                if !reduceMotion {
                    ProgressView().controlSize(.small).tint(GearDesign.accent)
                        .padding(.top, 4).opacity(reveal ? 0.75 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("户外装备库，正在启动")
        .task {
            if reduceMotion {
                reveal = true
            } else {
                withAnimation(.easeInOut(duration: 0.9)) { reveal = true }
            }

            do {
                try await Task.sleep(nanoseconds: reduceMotion ? 350_000_000 : 1_250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}
