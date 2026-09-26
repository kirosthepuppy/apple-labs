import AppKit
import Combine
import SwiftUI

@main
enum Main {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = LauncherModel()
    let router = Router()
    let accounts = AccountStore()
    lazy var library = GameLibrary(supportURL: model.supportURL)
    private var subscriptions: Set<AnyCancellable> = []
    private var mainWindow: NSWindow?
    private var linkWindow: NSWindow?
    private var handledLink = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        // Registered before launch finishes so a cold start from a link gets it.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.refreshStatus()
        model.onRobloxExit = { [weak self] in
            self?.library.refresh()
            // Keep saved sign-ins fresh, and finish adding a new account.
            self?.accounts.autoSave()
        }
        if model.robloxRunning { accounts.refresh() } else { accounts.autoSave() }
        model.$uiScale
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] scale in self?.fitWindow(to: scale) }
            .store(in: &subscriptions)
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch {
            showMainWindow()
        } else {
            // Launched to open a link: wait briefly for it before falling back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, !self.handledLink else { return }
                self.showMainWindow()
            }
        }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let link = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        handledLink = true
        library.lookUpLinkGame(link: link)
        if let mainWindow, mainWindow.isVisible {
            mainWindow.makeKeyAndOrderFront(nil)
            model.launch(url: link)
        } else {
            showLinkWindow()
            model.launch(url: link, quitAfter: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.cancel()
        return .terminateNow
    }

    // MARK: - Windows

    func showMainWindow() {
        linkWindow?.close()
        linkWindow = nil
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1140, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Roblox Bootstrapper"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            window.contentViewController = NSHostingController(
                rootView: RootView()
                    .environmentObject(model)
                    .environmentObject(router)
                    .environmentObject(library)
                    .environmentObject(accounts))
            window.setFrameAutosaveName("LauncherWindow")
            window.isReleasedWhenClosed = false
            window.delegate = self
            if !window.setFrameUsingName("LauncherWindow") { window.center() }
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Keeps the window at least as big as the interface needs at `scale`.
    private func fitWindow(to scale: Double) {
        guard let window = mainWindow else { return }
        let minimum = NSSize(width: RootView.minimumSize.width * scale, height: RootView.minimumSize.height * scale)
        window.contentMinSize = minimum
        let content = window.contentRect(forFrameRect: window.frame).size
        guard content.width < minimum.width || content.height < minimum.height else { return }
        let size = NSSize(width: max(content.width, minimum.width), height: max(content.height, minimum.height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.midX - frame.width / 2, y: window.frame.maxY - frame.height)
        if let visible = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.maxX - frame.width, visible.minX))
            frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.maxY - frame.height, visible.minY))
        }
        window.setFrame(frame, display: true, animate: true)
    }

    private func showLinkWindow() {
        guard linkWindow == nil else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 170),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Roblox Bootstrapper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.contentViewController = NSHostingController(
            rootView: LinkLaunchView()
                .environmentObject(model)
                .environmentObject(library))
        window.isReleasedWhenClosed = false
        window.center()
        linkWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appName = "Roblox Bootstrapper"

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: appName, action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let view = NSMenu(title: "View")
        for (title, key, action) in [("Zoom In", "=", #selector(zoomIn)), ("Zoom Out", "-", #selector(zoomOut)),
                                     ("Actual Size", "0", #selector(actualSize))] {
            view.addItem(withTitle: title, action: action, keyEquivalent: key).target = self
        }
        main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = view

        let go = NSMenu(title: "Go")
        for page in Page.allCases {
            let item = go.addItem(withTitle: page.title, action: #selector(goToPage(_:)), keyEquivalent: String(page.shortcut))
            item.target = self
            item.representedObject = page.rawValue
        }
        main.addItem(withTitle: "Go", action: nil, keyEquivalent: "").submenu = go

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        NSApp.windowsMenu = window

        return main
    }

    @objc private func zoomIn() { model.zoom(by: 0.05) }
    @objc private func zoomOut() { model.zoom(by: -0.05) }
    @objc private func actualSize() { model.uiScale = 1 }

    @objc private func goToPage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let page = Page(rawValue: raw) else { return }
        showMainWindow()
        router.go(page)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
