
import AppKit
import os
import IOKit.hid

class KeyRemapper {
    static func remapKeys(srcKey: UInt64, destKey: UInt64) {
        let mapping: [[String: UInt64]] = [
            [kIOHIDKeyboardModifierMappingSrcKey: srcKey,
             kIOHIDKeyboardModifierMappingDstKey: destKey]
        ]
        
        let system = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = IOHIDEventSystemClientCopyServices(system)
        
        for service in services as! [IOHIDServiceClient] {
            if IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0 {
                IOHIDServiceClientSetProperty(service, kIOHIDUserKeyUsageMapKey as CFString, mapping as CFArray)
            }
        }
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(0)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let window = NSWindow()
    let windowDelegate = WindowDelegate()
    let srcKeyField = NSTextField(frame: NSRect(x: 20, y: 150, width: 200, height: 24))
    let destKeyField = NSTextField(frame: NSRect(x: 20, y: 100, width: 200, height: 24))
    let remapButton = NSButton(frame: NSRect(x: 20, y: 50, width: 200, height: 30))
    
    func populateMainMenu() {
        let mainMenu = NSMenu()
        
        let appMenu = NSMenu(title: "Keywi")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        window.delegate = windowDelegate
        window.setContentSize(NSSize(width: 300, height: 250))
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.title = "Key Remapper"
        window.makeKeyAndOrderFront(nil)
        
        populateMainMenu()
        
        srcKeyField.placeholderString = "Source Key Code (Hex or Decimal)"
        srcKeyField.isSelectable = true
        srcKeyField.isEditable = true
        
        destKeyField.placeholderString = "Destination Key Code (Hex or Decimal)"
        destKeyField.isSelectable = true
        destKeyField.isEditable = true
        
        remapButton.title = "Remap Keys"
        remapButton.target = self
        remapButton.action = #selector(remapKeys)
        
        window.contentView?.addSubview(srcKeyField)
        window.contentView?.addSubview(destKeyField)
        window.contentView?.addSubview(remapButton)
    }
    
    @objc func remapKeys() {
		print("test")
        func parseKeyCode(_ input: String) -> UInt64? {
            var formattedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
            if formattedInput.lowercased().hasPrefix("0x") {
                formattedInput.removeFirst(2) // Remove "0x"
            }
            return UInt64(formattedInput, radix: 16) ?? UInt64(formattedInput)
        }
        
        guard let srcKey = parseKeyCode(srcKeyField.stringValue),
              let destKey = parseKeyCode(destKeyField.stringValue) else {
            return
        }
        
        KeyRemapper.remapKeys(srcKey: srcKey, destKey: destKey)

    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// try with 0x700000039 (caps lock) and 0x7000000E3 (command)
// issue: this only works with modifier keys. there  seems to be no swift native solution to map
// normal keys permanently