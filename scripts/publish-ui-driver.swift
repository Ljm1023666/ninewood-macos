#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

func ninewoodApp() -> NSRunningApplication? {
    var seen = Set<pid_t>()
    var candidates: [NSRunningApplication] = []
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.tothetomorrow.ninewood-macos")
        + NSWorkspace.shared.runningApplications.filter({
            ($0.localizedName ?? "").lowercased().contains("ninewood")
                && !($0.localizedName ?? "").lowercased().contains("helper")
        })
    {
        guard !app.isTerminated, seen.insert(app.processIdentifier).inserted else { continue }
        candidates.append(app)
    }
    // Prefer a process that currently owns an on-screen window (skip stuck SX debug shells).
    let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    let info = (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []
    let pidsWithWindows = Set(info.compactMap { w -> pid_t? in
        let owner = (w[kCGWindowOwnerName as String] as? String ?? "").lowercased()
        guard owner.contains("ninewood") else { return nil }
        guard let b = w[kCGWindowBounds as String] as? [String: Any],
              let width = b["Width"] as? CGFloat,
              let height = b["Height"] as? CGFloat,
              width >= 500, height >= 400 else { return nil }
        return w[kCGWindowOwnerPID as String] as? pid_t
    })
    if let live = candidates.first(where: { pidsWithWindows.contains($0.processIdentifier) }) {
        return live
    }
    // Newest non-Xcode-debug-looking process as fallback
    return candidates
        .sorted { $0.processIdentifier > $1.processIdentifier }
        .first
}

func findByIdentifier(_ idExact: String) -> AXUIElement? {
    guard let app = ninewoodApp() else { return nil }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var found: AXUIElement?
    walk(appEl) { el in
        if (axAttr(el, "AXIdentifier" as CFString) ?? "") == idExact {
            found = el
            return true
        }
        return false
    }
    return found
}

func activate() {
    ninewoodApp()?.activate(options: [.activateAllWindows])
    Thread.sleep(forTimeInterval: 0.8)
}

func windowID() -> CGWindowID? {
    let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
    var best: (CGWindowID, Double)?
    for w in info {
        let owner = (w[kCGWindowOwnerName as String] as? String ?? "").lowercased()
        guard owner.contains("ninewood") else { continue }
        guard let id = w[kCGWindowNumber as String] as? CGWindowID,
              let b = w[kCGWindowBounds as String] as? [String: Any],
              let width = b["Width"] as? CGFloat,
              let height = b["Height"] as? CGFloat else { continue }
        if width < 500 || height < 400 { continue }
        let area = Double(width * height)
        if best == nil || area > best!.1 { best = (id, area) }
    }
    return best?.0
}

func capture(to path: String) {
    guard let id = windowID() else {
        fputs("capture: no window\n", stderr)
        exit(2)
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-l\(id)", path]
    try! p.run()
    p.waitUntilExit()
    print("captured \(path) id=\(id)")
}

func axChildren(_ el: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
          let arr = ref as? [AXUIElement] else { return [] }
    return arr
}

func axAttr(_ el: AXUIElement, _ key: CFString) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, key, &ref) == .success else { return nil }
    if let s = ref as? String { return s }
    return nil
}

func axRole(_ el: AXUIElement) -> String? {
    axAttr(el, kAXRoleAttribute as CFString)
}

func axHasPress(_ el: AXUIElement) -> Bool {
    var actionsRef: CFArray?
    AXUIElementCopyActionNames(el, &actionsRef)
    let acts = (actionsRef as? [String]) ?? []
    return acts.contains(kAXPressAction as String) || acts.contains("AXPress")
}

func walk(_ root: AXUIElement, limit: Int = 12000, visit: (AXUIElement) -> Bool) {
    var queue = [root]
    var n = 0
    while !queue.isEmpty && n < limit {
        let el = queue.removeFirst()
        n += 1
        if visit(el) { return }
        queue.append(contentsOf: axChildren(el))
    }
}

func blob(of el: AXUIElement) -> String {
    [
        axAttr(el, kAXTitleAttribute as CFString) ?? "",
        axAttr(el, kAXDescriptionAttribute as CFString) ?? "",
        axAttr(el, "AXIdentifier" as CFString) ?? "",
        axAttr(el, kAXPlaceholderValueAttribute as CFString) ?? "",
        axAttr(el, kAXHelpAttribute as CFString) ?? "",
    ].joined(separator: " ")
}

/// Prefer exact AXIdentifier match; then title/desc contains; any pressable role.
func findPressable(idExact: String? = nil, textContains: String? = nil) -> AXUIElement? {
    guard let app = ninewoodApp() else { return nil }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var byId: AXUIElement?
    var byText: AXUIElement?
    walk(appEl) { el in
        let identifier = axAttr(el, "AXIdentifier" as CFString) ?? ""
        if let idExact, identifier == idExact {
            byId = el
            return true
        }
        guard axHasPress(el) else { return false }
        if byText == nil, let needle = textContains {
            let b = blob(of: el)
            if b.contains(needle) {
                byText = el
            }
        }
        return false
    }
    return byId ?? byText
}

func findAndPress(idExact: String? = nil, textContains: String? = nil) -> Bool {
    guard let btn = findPressable(idExact: idExact, textContains: textContains) else { return false }
    if axHasPress(btn) {
        return AXUIElementPerformAction(btn, kAXPressAction as CFString) == .success
    }
    // Disabled / non-pressable: click center of frame
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(btn, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(btn, kAXSizeAttribute as CFString, &sizeRef) == .success
    else { return false }
    var point = CGPoint.zero
    var size = CGSize.zero
    // AXValueGetValue needs AXValue
    if CFGetTypeID(posRef!) == AXValueGetTypeID() {
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
    }
    if CFGetTypeID(sizeRef!) == AXValueGetTypeID() {
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
    }
    let x = point.x + size.width / 2
    let y = point.y + size.height / 2
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
    let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
    return true
}

func findFocusAndType(identifier: String, text: String) -> Bool {
    guard let f = findByIdentifier(identifier) ?? {
        guard let app = ninewoodApp() else { return nil as AXUIElement? }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var field: AXUIElement?
        walk(appEl) { el in
            let role = axRole(el) ?? ""
            let isField = role.contains("Text")
            guard isField else { return false }
            let b = blob(of: el)
            if b.contains("composer") || b.contains("发布整理") || b.contains("说点") {
                field = el
                return true
            }
            return false
        }
        return field
    }() else { return false }

    AXUIElementSetAttributeValue(f, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    Thread.sleep(forTimeInterval: 0.3)
    // SwiftUI TextField 常忽略 AXValue 写入；用 Cmd+A + 粘贴驱动 @State 绑定
    let pb = NSPasteboard.general
    let previous = pb.string(forType: .string)
    pb.clearContents()
    pb.setString(text, forType: .string)
    let src = CGEventSource(stateID: .hidSystemState)
    func key(_ vk: CGKeyCode, flags: CGEventFlags = []) {
        let down = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    key(0, flags: .maskCommand) // A select all
    Thread.sleep(forTimeInterval: 0.05)
    key(9, flags: .maskCommand) // V paste
    Thread.sleep(forTimeInterval: 0.45)
    if let previous {
        pb.clearContents()
        pb.setString(previous, forType: .string)
    }
    return true
}

func pressReturn() {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

func dumpInteresting() {
    guard let app = ninewoodApp() else { return }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var lines: [String] = []
    walk(appEl) { el in
        let role = axRole(el) ?? ""
        let id = axAttr(el, "AXIdentifier" as CFString) ?? ""
        let title = axAttr(el, kAXTitleAttribute as CFString) ?? ""
        let desc = axAttr(el, kAXDescriptionAttribute as CFString) ?? ""
        let press = axHasPress(el)
        if id.contains("publish") || (press && role.contains("Button") && (!desc.isEmpty || !title.isEmpty)) {
            lines.append("\(role) id=\(id) title=\(title) desc=\(desc) press=\(press)")
        }
        return false
    }
    print(lines.joined(separator: "\n"))
}

func axExists(idExact: String) -> Bool {
    guard let app = ninewoodApp() else { return false }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var found = false
    walk(appEl) { el in
        if (axAttr(el, "AXIdentifier" as CFString) ?? "") == idExact {
            found = true
            return true
        }
        return false
    }
    return found
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    fputs("usage: publish-ui-driver.swift <hubCTA|demandSend|dump|capture|exists> [png|id]\n", stderr)
    exit(1)
}

activate()

switch cmd {
case "dump":
    dumpInteresting()
case "exists":
    guard let id = args.dropFirst().first else { exit(1) }
    print(axExists(idExact: id) ? "exists \(id)" : "missing \(id)")
    if !axExists(idExact: id) { exit(5) }
case "hubCTA":
    let ok = findAndPress(idExact: "publish-hub-start-ai")
        || findAndPress(textContains: "开始用 AI 整理")
    print(ok ? "pressed hub CTA" : "hub CTA not found")
    var landed = false
    for _ in 0..<10 {
        Thread.sleep(forTimeInterval: 0.35)
        landed = axExists(idExact: "publish-workspace-demand")
            || axExists(idExact: "publish-workspace-service")
        if landed { break }
    }
    print(landed ? "navigated to workspace" : "still on hub / unknown")
    if let out = args.dropFirst().first { capture(to: out) }
    if !(ok && landed) { exit(3) }
case "demandSend":
    let typed = findFocusAndType(
        identifier: "publish-ws-composer",
        text: "Need AC repair in Pudong budget 200-350 offline today"
    )
    print(typed ? "typed into composer" : "composer not found")
    Thread.sleep(forTimeInterval: 0.4)
    // Prefer Return-to-send (matches product); fallback to send button
    pressReturn()
    Thread.sleep(forTimeInterval: 0.5)
    let sent = findAndPress(idExact: "publish-ws-send")
        || findAndPress(textContains: "发送")
        || typed // Return already attempted
    print(sent ? "pressed send/return" : "send not found")
    Thread.sleep(forTimeInterval: 1.8)
    let filled = findByIdentifier("publish-ws-field-title") != nil
    print(filled ? "title field present" : "title field missing")
    if let out = args.dropFirst().first { capture(to: out) }
    if !typed { exit(4) }
case "capture":
    guard let out = args.dropFirst().first else { exit(1) }
    capture(to: out)
default:
    fputs("unknown\n", stderr)
    exit(1)
}
