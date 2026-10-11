import SwiftUI
import AppKit

@MainActor
final class AudioPlayerAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let windowFrameDefaultsKey = "AudioPlayerMainWindowFrame.v1"
    static var pendingExternalFileURLs: [URL] = []
    static var externalFileOpenHandler: (([URL]) -> Void)?

    let appController = AppController()
    private var mainWindow: NSWindow?

    func applicationDidBecomeActive(_ notification: Notification) {
        appController.handleApplicationDidBecomeActive()
    }

    func applicationWillResignActive(_ notification: Notification) {
        appController.handleApplicationWillResignActive()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rootView = MainView(appController: appController)
            .environment(appController)

        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )

        window.title = "Audio Player"
        window.contentView = hostingView
        window.minSize = NSSize(width: 1100, height: 700)
        window.delegate = self
        restoreWindowFrame(for: window)
        window.makeKeyAndOrderFront(nil)
        mainWindow = window

        NSApp.activate(ignoringOtherApps: true)

        AudioPlayerAppDelegate.externalFileOpenHandler = { [weak self] urls in
            guard let self else { return }
            for url in urls {
                self.handleExternalFileOpen(url)
            }
        }
    }

    private func restoreWindowFrame(for window: NSWindow) {
        let defaults = UserDefaults.standard
        let frame: NSRect
        if let storedFrame = defaults.string(forKey: Self.windowFrameDefaultsKey) {
            frame = NSRectFromString(storedFrame)
        } else if let legacyFrame = defaults.string(forKey: "NSWindow Frame AudioPlayerMainWindow") {
            // NSWindow's legacy autosave value is eight space-separated numbers,
            // not the NSStringFromRect format used by this explicit store.
            let values = legacyFrame.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            guard values.count >= 4 else {
                window.center()
                return
            }
            frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
        } else {
            window.center()
            return
        }

        var frameToRestore = frame
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width >= window.minSize.width,
              frame.height >= window.minSize.height else {
            window.center()
            return
        }

        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.visibleFrame.intersects(frame) })
            ?? NSScreen.main else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        frameToRestore.size.width = min(max(frameToRestore.width, window.minSize.width), visibleFrame.width)
        frameToRestore.size.height = min(max(frameToRestore.height, window.minSize.height), visibleFrame.height)
        frameToRestore.origin.x = min(
            max(frameToRestore.origin.x, visibleFrame.minX),
            visibleFrame.maxX - frameToRestore.width
        )
        frameToRestore.origin.y = min(
            max(frameToRestore.origin.y, visibleFrame.minY),
            visibleFrame.maxY - frameToRestore.height
        )
        window.setFrame(frameToRestore, display: false)
        saveWindowFrame(window)
    }

    private func saveWindowFrame(_ window: NSWindow?) {
        guard let window, !window.isMiniaturized else { return }
        UserDefaults.standard.set(
            NSStringFromRect(window.frame),
            forKey: Self.windowFrameDefaultsKey
        )
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrame(notification.object as? NSWindow)
    }

    func windowDidMove(_ notification: Notification) {
        saveWindowFrame(notification.object as? NSWindow)
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowFrame(notification.object as? NSWindow)
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveWindowFrame(mainWindow)
        UserDefaults.standard.synchronize()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        deliverExternalFiles(urls)
    }

    private func deliverExternalFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if let handler = Self.externalFileOpenHandler {
            handler(urls)
        } else {
            Self.pendingExternalFileURLs.append(contentsOf: urls)
        }
    }

    private func handleExternalFileOpen(_ url: URL) {
        appController.handleExternalFileOpen(url)
        mainWindow?.makeKeyAndOrderFront(nil)
    }
}

@main
struct AudioPlayerApp: App {
    @NSApplicationDelegateAdaptor(AudioPlayerAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
