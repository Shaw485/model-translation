import AppKit
import SwiftUI
import Carbon
import ApplicationServices

private struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }
    func restore(_ pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { values in
            let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

@MainActor
final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { AppDelegate.shared?.hideResult() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    let store = AppStore()
    private var mainWindow: NSWindow!
    private var resultPanel: NSPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var selectionTask: Task<Void, Never>?
    private var outsideMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        mainWindow.title = "CmdETranslate"
        mainWindow.contentView = NSHostingView(rootView: RootView(store: store))
        mainWindow.isReleasedWhenClosed = false
        mainWindow.setFrameAutosaveName("CmdETranslateMainV2")
        mainWindow.center()
        resultPanel = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 88), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        resultPanel.title = "CmdETranslate · 译文"
        resultPanel.contentView = NSHostingView(rootView: FloatingResultView(store: store))
        resultPanel.isReleasedWhenClosed = false
        resultPanel.delegate = self
        resultPanel.isFloatingPanel = true; resultPanel.level = .floating
        resultPanel.hidesOnDeactivate = false
        resultPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "译"
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "打开 CmdETranslate", action: #selector(showMain), keyEquivalent: ""); open.target = self
        let result = menu.addItem(withTitle: "显示上次译文浮窗", action: #selector(showLastResult), keyEquivalent: ""); result.target = self
        let glossary = menu.addItem(withTitle: "专业词库…", action: #selector(showGlossary), keyEquivalent: ""); glossary.target = self
        let settings = menu.addItem(withTitle: "模型设置…", action: #selector(showSettings), keyEquivalent: ""); settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "选中文字后按 ⌘E", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        registerHotKey()
        showMain()
    }
    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu(title: "CmdETranslate")
        app.addItem(withTitle: "关于 CmdETranslate", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let result = app.addItem(withTitle: "显示译文浮窗", action: #selector(showLastResult), keyEquivalent: ""); result.target = self
        app.addItem(.separator())
        app.addItem(withTitle: "退出 CmdETranslate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showMain(); return true }
    func applicationDidBecomeActive(_ notification: Notification) { store.refreshPermissions() }
    func applicationWillTerminate(_ notification: Notification) {
        selectionTask?.cancel(); store.cancel()
        removeDismissMonitors()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
    @objc func showMain() { hideResult(); mainWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); store.refreshPermissions() }
    @objc private func showGlossary() { store.tab = "glossary"; showMain() }
    @objc private func showSettings() { store.tab = "settings"; showMain() }
    @objc private func showLastResult() { showResult() }
    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func registerHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if eventHandler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var keyID = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &keyID)
                guard status == noErr, keyID.signature == OSType(0x434D4445), keyID.id == 1 else { return OSStatus(eventNotHandledErr) }
                Task { @MainActor in AppDelegate.shared?.translateSelection() }
                return noErr
            }, 1, &type, nil, &eventHandler)
            guard status == noErr else { store.hotkeyStatus = "快捷键监听失败（\(status)）"; return }
        }
        let id = EventHotKeyID(signature: OSType(0x434D4445), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_E), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        store.hotkeyStatus = status == noErr ? "⌘E 已就绪" : "⌘E 注册失败（\(status)），可能被其他应用占用"
    }
    private func showResult() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let size = resultPanel.frame.size
        let x = min(max(mouse.x + 12, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(mouse.y - size.height - 10, visible.minY + 8), visible.maxY - size.height - 8)
        resultPanel.setFrameOrigin(NSPoint(x: x, y: y))
        resultPanel.makeKeyAndOrderFront(nil)
        resultPanel.orderFrontRegardless()
        installDismissMonitors()
    }
    func resizeResult(height: CGFloat) {
        guard let panel = resultPanel else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: 360, height: height)
        panel.setFrame(frame, display: true)
    }

    func hideResult() {
        resultPanel?.orderOut(nil)
        removeDismissMonitors()
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === resultPanel { removeDismissMonitors() }
    }
    private func removeDismissMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
    }
    private func installDismissMonitors() {
        removeDismissMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            // Global events belong to another app. Hide without consuming that app's click.
            MainActor.assumeIsolated { self?.hideResult() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                guard let self, self.resultPanel.isVisible else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.hideResult(); return true }
                } else if event.window !== self.resultPanel { self.hideResult() }
                return false
            }
            return consume ? nil : event
        }
    }
    private func translateSelection() {
        guard selectionTask == nil else { return }
        store.refreshPermissions()
        guard store.accessibilityGranted else {
            store.failSelection("请在系统设置 → 隐私与安全性 → 辅助功能中开启 CmdETranslate。也可以在主窗口粘贴翻译。")
            showResult(); return
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { store.failSelection("无法确定要取词的应用。"); showResult(); return }
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            store.translate(); showResult(); return
        }
        let axApp = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.4)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = unsafeBitCast(focused, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(element, 0.4)
            var role: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &role)
            if role as? String == kAXSecureTextFieldSubrole { store.failSelection("密码输入框不支持取词。"); showResult(); return }
            var selection: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selection) == .success,
               let text = selection as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.translate(text); showResult(); return
            }
        }
        selectionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.selectionTask = nil }
            do { try await Task.sleep(nanoseconds: 140_000_000) } catch { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier else {
                self.store.failSelection("取词时应用发生切换，请重新选择文字后按 ⌘E。"); self.showResult(); return
            }
            let pb = NSPasteboard.general, snapshot = ClipboardSnapshot(NSPasteboard.general)
            let before = pb.changeCount
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else {
                self.store.failSelection("无法读取选中文字，请在主窗口粘贴。"); self.showResult(); return
            }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            for _ in 0..<12 {
                do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
                if pb.changeCount != before {
                    let text = pb.string(forType: .string)
                    snapshot.restore(pb)
                    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.store.translate(text) }
                    else { self.store.failSelection("未读取到文字，请选中文字后重试。") }
                    self.showResult(); return
                }
            }
            self.store.failSelection("这个应用未提供选中文字，请复制原文后在主窗口粘贴翻译。")
            self.showResult()
        }
    }
}

@main
struct CmdETranslateMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
