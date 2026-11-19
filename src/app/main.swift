import AppKit
import Foundation

// HID keyboard usage IDs used by hidutil. Values match the names accepted by the CLI.
struct Key: Hashable {
    let name: String
    let label: String
    let usage: UInt64
}

let keys: [Key] = {
    let names = ["a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z"]
    let labels = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    var result = zip(names, labels).enumerated().map { i, pair in Key(name: pair.0, label: pair.1, usage: UInt64(0x04 + i)) }
    let rest: [(String, String, UInt64)] = [
        ("1","1",0x1e),("2","2",0x1f),("3","3",0x20),("4","4",0x21),("5","5",0x22),("6","6",0x23),("7","7",0x24),("8","8",0x25),("9","9",0x26),("0","0",0x27),
        ("return","Return",0x28),("escape","Escape",0x29),("backspace","Delete",0x2a),("tab","Tab",0x2b),("space","Space",0x2c),("minus","-",0x2d),("equals","=",0x2e),("open_bracket","[",0x2f),("closed_bracket","]",0x30),("backslash","\\",0x31),("semicolon",";",0x33),("quote","'",0x34),("grave_accent","`",0x35),("comma",",",0x36),("period",".",0x37),("slash","/",0x38),("caps_lock","Caps Lock",0x39),
        ("f1","F1",0x3a),("f2","F2",0x3b),("f3","F3",0x3c),("f4","F4",0x3d),("f5","F5",0x3e),("f6","F6",0x3f),("f7","F7",0x40),("f8","F8",0x41),("f9","F9",0x42),("f10","F10",0x43),("f11","F11",0x44),("f12","F12",0x45),
        ("insert","Insert",0x49),("home","Home",0x4a),("page_up","Page Up",0x4b),("delete","Forward Delete",0x4c),("end","End",0x4d),("page_down","Page Down",0x4e),("arrow_right","Right Arrow",0x4f),("arrow_left","Left Arrow",0x50),("arrow_down","Down Arrow",0x51),("arrow_up","Up Arrow",0x52),
        ("left_control","Left Control",0xe0),("left_shift","Left Shift",0xe1),("left_alt","Left Option",0xe2),("left_command","Left Command",0xe3),("right_control","Right Control",0xe4),("right_shift","Right Shift",0xe5),("right_alt","Right Option",0xe6),("right_command","Right Command",0xe7)
    ]
    result += rest.map { Key(name: $0.0, label: $0.1, usage: $0.2) }
    return result
}()

struct Mapping: Codable, Equatable { let source: UInt64; let destination: UInt64 }

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    fileprivate var mappings: [Mapping] = []
    fileprivate var mappingLoadError: String?
    private let agentURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.emilmair.keywi.plist")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keywi")
        statusItem.button?.toolTip = "Keywi"
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 440)
        loadMappings()
        popover.contentViewController = KeywiViewController(delegate: self)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) } else {
            loadMappings()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NotificationCenter.default.post(name: .keywiMappingsChanged, object: nil)
        }
    }

    func addMapping(source: Key, destination: Key) throws {
        guard source.usage != destination.usage else { throw NSError(domain: "Keywi", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose two different keys."]) }
        mappings.removeAll { $0.source == source.usage }
        mappings.append(Mapping(source: source.usage, destination: destination.usage))
        try applyMappings()
    }

    func updateMapping(_ mapping: Mapping, source: Key, destination: Key) throws {
        guard source.usage != destination.usage else { throw NSError(domain: "Keywi", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose two different keys."]) }
        guard let index = mappings.firstIndex(of: mapping) else {
            throw NSError(domain: "Keywi", code: 5, userInfo: [NSLocalizedDescriptionKey: "This mapping no longer exists."])
        }
        guard !mappings.enumerated().contains(where: { $0.offset != index && $0.element.source == source.usage }) else {
            throw NSError(domain: "Keywi", code: 6, userInfo: [NSLocalizedDescriptionKey: "A source key can only have one mapping."])
        }
        mappings[index] = Mapping(source: source.usage, destination: destination.usage)
        try applyMappings()
    }

    func removeMapping(_ mapping: Mapping) throws { mappings.removeAll { $0 == mapping }; try applyMappings() }
    func clearMappings() throws { mappings = []; try applyMappings() }
    func keyLabel(_ usage: UInt64) -> String { keys.first { $0.usage == usage }?.label ?? String(format: "0x%llX", usage) }
    var serviceRunning: Bool { launchctl(["print", serviceTarget]).0 == 0 }

    private var serviceTarget: String { "gui/\(getuid())/com.emilmair.keywi" }
    @discardableResult private func launchctl(_ arguments: [String]) -> (Int32, String) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl"); process.arguments = arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        do { try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "") }
        catch { return (1, error.localizedDescription) }
    }
    func setServiceRunning(_ running: Bool) throws {
        if running {
            if !FileManager.default.fileExists(atPath: agentURL.path) {
                let json = try mappingJSON()
                try writeLaunchAgent(json)
            }
            let result = launchctl(["bootstrap", "gui/\(getuid())", agentURL.path])
            guard result.0 == 0 || serviceRunning else { throw NSError(domain: "Keywi", code: Int(result.0), userInfo: [NSLocalizedDescriptionKey: result.1]) }
        } else {
            let result = launchctl(["bootout", serviceTarget])
            guard result.0 == 0 || !serviceRunning else { throw NSError(domain: "Keywi", code: Int(result.0), userInfo: [NSLocalizedDescriptionKey: result.1]) }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .keywiMappingsChanged, object: nil)
        }
    }

    fileprivate func loadMappings() {
        guard FileManager.default.fileExists(atPath: agentURL.path) else {
            mappings = []
            mappingLoadError = nil
            return
        }
        do {
            let data = try Data(contentsOf: agentURL)
            let plistObject = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard let plist = plistObject as? [String: Any],
                  let arguments = plist["ProgramArguments"] as? [String],
                  let json = arguments.last,
                  let jsonData = json.data(using: .utf8) else {
                throw NSError(domain: "Keywi", code: 2, userInfo: [NSLocalizedDescriptionKey: "The LaunchAgent plist has no readable mapping arguments."])
            }
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
            guard let payload = jsonObject as? [String: Any],
                  let saved = payload["UserKeyMapping"] as? [Any] else {
                throw NSError(domain: "Keywi", code: 3, userInfo: [NSLocalizedDescriptionKey: "The LaunchAgent plist has no UserKeyMapping list."])
            }
            mappings = saved.compactMap { entry in
                guard let item = entry as? [String: Any],
                      let source = (item["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value,
                      let destination = (item["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value else { return nil }
                return Mapping(source: source & 0x0FFFFFFF, destination: destination & 0x0FFFFFFF)
            }
            mappingLoadError = nil
        } catch {
            mappings = []
            mappingLoadError = error.localizedDescription
        }
    }

    private func applyMappings() throws {
        let jsonString = try mappingJSON()
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil"); process.arguments = ["property", "--set", jsonString]
        let errors = Pipe(); process.standardError = errors; try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "Keywi", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "hidutil could not apply these mappings."]) }
        try installLaunchAgent(jsonString)
        NotificationCenter.default.post(name: .keywiMappingsChanged, object: nil)
    }

    private func mappingJSON() throws -> String {
        let payload = mappings.map { ["HIDKeyboardModifierMappingSrc": NSNumber(value: 0x700000000 | $0.source), "HIDKeyboardModifierMappingDst": NSNumber(value: 0x700000000 | $0.destination)] }
        let json = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": payload], options: [.fragmentsAllowed])
        return String(data: json, encoding: .utf8)!
    }

    private func installLaunchAgent(_ json: String) throws {
        let wasRunning = serviceRunning
        if wasRunning { try setServiceRunning(false) }
        try writeLaunchAgent(json)
        if wasRunning { try setServiceRunning(true) }
    }

    private func writeLaunchAgent(_ json: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["Label": "com.emilmair.keywi", "ProgramArguments": ["/usr/bin/hidutil", "property", "--set", json], "RunAtLoad": true]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentURL, options: .atomic)
    }
}

extension Notification.Name { static let keywiMappingsChanged = Notification.Name("KeywiMappingsChanged") }

final class KeywiViewController: NSViewController {
    private weak var appDelegate: AppDelegate?
    private let serviceStatus = NSTextField(labelWithString: "Checking service…")
    private let serviceButton = NSButton(title: "Start", target: nil, action: nil)
    private let serviceFeedback = NSTextField(wrappingLabelWithString: "")
    private let mappingsSeparator = NSBox()
    private let mappingsScrollView = NSScrollView()
    private let mappingsDocumentView = FlippedView(frame: .zero)
    private let addMappingButton = NSButton(title: "+ Add Mapping", target: nil, action: nil)
    private var hasDraftMapping = false
    private var draftSource: UInt64?
    private var draftDestination: UInt64?
    private var serviceIsRunning = false
    private var serviceChangeInProgress = false
    private var serviceRefreshID = 0

    init(delegate: AppDelegate) { appDelegate = delegate; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 440))
        root.wantsLayer = true
        view = root

        let title = NSTextField(labelWithString: "Keywi")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.frame = NSRect(x: 16, y: 402, width: 180, height: 26)
        root.addSubview(title)

        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.frame = NSRect(x: 246, y: 400, width: 58, height: 28)
        root.addSubview(quit)

        serviceStatus.frame = NSRect(x: 16, y: 368, width: 190, height: 20)
        root.addSubview(serviceStatus)

        serviceButton.frame = NSRect(x: 218, y: 362, width: 86, height: 28)
        serviceButton.target = self
        serviceButton.action = #selector(toggleService(_:))
        serviceButton.isEnabled = false
        root.addSubview(serviceButton)

        serviceFeedback.frame = NSRect(x: 16, y: 332, width: 288, height: 26)
        serviceFeedback.font = .systemFont(ofSize: 11)
        serviceFeedback.textColor = .systemRed
        serviceFeedback.maximumNumberOfLines = 2
        serviceFeedback.isHidden = true
        root.addSubview(serviceFeedback)

        mappingsSeparator.boxType = .separator
        root.addSubview(mappingsSeparator)

        mappingsScrollView.frame = NSRect(x: 16, y: 54, width: 288, height: 236)
        mappingsScrollView.hasVerticalScroller = true
        mappingsScrollView.autohidesScrollers = true
        mappingsScrollView.borderType = .noBorder
        mappingsScrollView.drawsBackground = false
        mappingsScrollView.documentView = mappingsDocumentView
        root.addSubview(mappingsScrollView)

        addMappingButton.frame = NSRect(x: 16, y: 16, width: 288, height: 30)
        addMappingButton.target = self
        addMappingButton.action = #selector(beginAddingMapping(_:))
        root.addSubview(addMappingButton)
        layoutMappingsArea()

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .keywiMappingsChanged, object: nil)
        refresh()
    }

    @objc private func refresh() {
        guard let app = appDelegate else { return }
        app.loadMappings()
        if let error = app.mappingLoadError {
            showFeedback("Could not read mappings: \(error)")
        }
        renderMappings()

        guard !serviceChangeInProgress else { return }
        serviceRefreshID += 1
        let refreshID = serviceRefreshID
        serviceStatus.stringValue = "Checking service…"
        serviceStatus.textColor = .secondaryLabelColor
        serviceButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak app] in
            let running = app?.serviceRunning ?? false
            DispatchQueue.main.async {
                guard let self, self.serviceRefreshID == refreshID, !self.serviceChangeInProgress else { return }
                self.serviceIsRunning = running
                self.serviceStatus.stringValue = running ? "● Service running" : "○ Service stopped"
                self.serviceStatus.textColor = running ? .systemGreen : .secondaryLabelColor
                self.serviceButton.title = running ? "Stop" : "Start"
                self.serviceButton.isEnabled = true
            }
        }
    }

    private func renderMappings() {
        guard let app = appDelegate else { return }
        mappingsDocumentView.subviews.forEach { $0.removeFromSuperview() }

        let mappings = app.mappingsForDisplay
        let rowCount = mappings.count + (hasDraftMapping ? 1 : 0)
        let headerHeight: CGFloat = 24
        let rowHeight: CGFloat = 32
        let contentSize = mappingsScrollView.contentSize
        let documentHeight = max(contentSize.height, headerHeight + CGFloat(max(rowCount, 1)) * rowHeight)
        let documentWidth = contentSize.width
        mappingsDocumentView.frame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)

        let fromHeader = NSTextField(labelWithString: "From")
        fromHeader.frame = NSRect(x: 0, y: 2, width: 110, height: 18)
        fromHeader.textColor = .secondaryLabelColor
        mappingsDocumentView.addSubview(fromHeader)

        let toHeader = NSTextField(labelWithString: "To")
        toHeader.frame = NSRect(x: 130, y: 2, width: 110, height: 18)
        toHeader.textColor = .secondaryLabelColor
        mappingsDocumentView.addSubview(toHeader)

        if mappings.isEmpty && !hasDraftMapping {
            let emptyLabel = NSTextField(labelWithString: "No mappings configured")
            emptyLabel.frame = NSRect(x: 0, y: headerHeight + 4, width: documentWidth, height: 20)
            emptyLabel.textColor = .secondaryLabelColor
            mappingsDocumentView.addSubview(emptyLabel)
        }

        for (index, mapping) in mappings.enumerated() {
            addMappingRow(index: index, source: mapping.source, destination: mapping.destination, isDraft: false, mappings: mappings)
        }
        if hasDraftMapping {
            addMappingRow(index: mappings.count, source: draftSource, destination: draftDestination, isDraft: true, mappings: mappings)
            addMappingButton.isEnabled = false
        } else {
            addMappingButton.isEnabled = true
        }
    }

    private func addMappingRow(index: Int, source: UInt64?, destination: UInt64?, isDraft: Bool, mappings: [Mapping]) {
        guard let app = appDelegate else { return }
        let rowY = CGFloat(24 + index * 32)

        var sourceOptions = keys.filter { key in
            (destination.map { key.usage != $0 } ?? true) && !mappings.enumerated().contains { otherIndex, mapping in
                otherIndex != index && mapping.source == key.usage
            }
        }
        if let source, !sourceOptions.contains(where: { $0.usage == source }) {
            sourceOptions.insert(Key(name: "", label: app.keyLabel(source), usage: source), at: 0)
        }

        var destinationOptions = keys.filter { key in source.map { key.usage != $0 } ?? true }
        if let destination, !destinationOptions.contains(where: { $0.usage == destination }) {
            destinationOptions.insert(Key(name: "", label: app.keyLabel(destination), usage: destination), at: 0)
        }

        let sourcePopup = makeKeyPopup(options: sourceOptions, selected: source, placeholder: isDraft ? "From…" : nil, role: "mapping.source", row: index)
        sourcePopup.frame = NSRect(x: 0, y: rowY + 3, width: 110, height: 26)
        mappingsDocumentView.addSubview(sourcePopup)

        let arrow = NSTextField(labelWithString: "→")
        arrow.alignment = .center
        arrow.frame = NSRect(x: 112, y: rowY + 7, width: 16, height: 18)
        arrow.textColor = .secondaryLabelColor
        mappingsDocumentView.addSubview(arrow)

        let destinationPopup = makeKeyPopup(options: destinationOptions, selected: destination, placeholder: isDraft ? "To…" : nil, role: "mapping.destination", row: index)
        destinationPopup.frame = NSRect(x: 130, y: rowY + 3, width: 110, height: 26)
        mappingsDocumentView.addSubview(destinationPopup)

        let removeButton = NSButton(title: "−", target: self, action: #selector(removeMapping(_:)))
        removeButton.tag = index
        removeButton.toolTip = isDraft ? "Cancel new mapping" : "Remove mapping"
        removeButton.frame = NSRect(x: 244, y: rowY + 3, width: 26, height: 26)
        mappingsDocumentView.addSubview(removeButton)
    }

    private func makeKeyPopup(options: [Key], selected: UInt64?, placeholder: String?, role: String, row: Int) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        if let placeholder {
            popup.addItem(withTitle: placeholder)
            popup.lastItem?.representedObject = NSNull()
        }
        for key in options {
            popup.addItem(withTitle: key.label)
            popup.lastItem?.representedObject = NSNumber(value: key.usage)
        }
        if let selected, let index = options.firstIndex(where: { $0.usage == selected }) {
            popup.selectItem(at: index + (placeholder == nil ? 0 : 1))
        } else if placeholder != nil {
            popup.selectItem(at: 0)
        }
        popup.identifier = NSUserInterfaceItemIdentifier(role)
        popup.tag = row
        popup.target = self
        popup.action = #selector(mappingSelectionChanged(_:))
        return popup
    }

    @objc private func beginAddingMapping(_ sender: Any?) {
        guard !hasDraftMapping else { return }
        hasDraftMapping = true
        draftSource = nil
        draftDestination = nil
        clearFeedback()
        renderMappings()
        scrollMappingsToBottom()
    }

    @objc private func mappingSelectionChanged(_ sender: NSPopUpButton) {
        guard let app = appDelegate,
              let role = sender.identifier?.rawValue,
              let usage = (sender.selectedItem?.representedObject as? NSNumber)?.uint64Value else { return }
        let index = sender.tag
        if index < app.mappingsForDisplay.count {
            let current = app.mappingsForDisplay[index]
            let source = role == "mapping.source" ? usage : current.source
            let destination = role == "mapping.destination" ? usage : current.destination
            applyMapping(current, source: source, destination: destination)
            return
        }

        guard hasDraftMapping, index == app.mappingsForDisplay.count else { return }
        if role == "mapping.source" { draftSource = usage }
        if role == "mapping.destination" { draftDestination = usage }
        if let source = draftSource, let destination = draftDestination {
            let sourceKey = keys.first { $0.usage == source } ?? Key(name: "", label: app.keyLabel(source), usage: source)
            let destinationKey = keys.first { $0.usage == destination } ?? Key(name: "", label: app.keyLabel(destination), usage: destination)
            do {
                try app.addMapping(source: sourceKey, destination: destinationKey)
                hasDraftMapping = false
                draftSource = nil
                draftDestination = nil
                clearFeedback()
                renderMappings()
            } catch {
                app.loadMappings()
                showFeedback(error.localizedDescription)
                renderMappings()
            }
        } else {
            renderMappings()
        }
    }

    private func applyMapping(_ current: Mapping, source: UInt64, destination: UInt64) {
        guard let app = appDelegate else { return }
        let sourceKey = keys.first { $0.usage == source } ?? Key(name: "", label: app.keyLabel(source), usage: source)
        let destinationKey = keys.first { $0.usage == destination } ?? Key(name: "", label: app.keyLabel(destination), usage: destination)
        do {
            try app.updateMapping(current, source: sourceKey, destination: destinationKey)
            clearFeedback()
        } catch {
            app.loadMappings()
            showFeedback(error.localizedDescription)
            renderMappings()
        }
    }

    @objc private func removeMapping(_ sender: NSButton) {
        guard let app = appDelegate else { return }
        if hasDraftMapping && sender.tag == app.mappingsForDisplay.count {
            hasDraftMapping = false
            draftSource = nil
            draftDestination = nil
            renderMappings()
            return
        }
        let mappings = app.mappingsForDisplay
        guard mappings.indices.contains(sender.tag) else { return }
        do {
            try app.removeMapping(mappings[sender.tag])
            clearFeedback()
        } catch {
            app.loadMappings()
            showFeedback(error.localizedDescription)
            renderMappings()
        }
    }

    private func showFeedback(_ message: String) {
        serviceFeedback.stringValue = message
        serviceFeedback.isHidden = false
        layoutMappingsArea()
    }

    private func clearFeedback() {
        serviceFeedback.stringValue = ""
        serviceFeedback.isHidden = true
        layoutMappingsArea()
    }

    private func layoutMappingsArea() {
        let separatorY: CGFloat = serviceFeedback.isHidden ? 354 : 326
        mappingsSeparator.frame = NSRect(x: 16, y: separatorY, width: 288, height: 1)
        mappingsScrollView.frame = NSRect(x: 16, y: 54, width: 288, height: separatorY - 8 - 54)
        if mappingsDocumentView.frame.height < mappingsScrollView.contentSize.height {
            mappingsDocumentView.frame.size.height = mappingsScrollView.contentSize.height
        }
    }

    private func scrollMappingsToBottom() {
        let documentHeight = mappingsDocumentView.frame.height
        let visibleHeight = mappingsScrollView.contentView.bounds.height
        mappingsScrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, documentHeight - visibleHeight)))
        mappingsScrollView.reflectScrolledClipView(mappingsScrollView.contentView)
    }

    @objc private func toggleService(_ sender: Any?) {
        guard let app = appDelegate, !serviceChangeInProgress else { return }
        let shouldRun = !serviceIsRunning
        serviceChangeInProgress = true
        serviceRefreshID += 1
        clearFeedback()
        serviceButton.isEnabled = false
        serviceButton.title = shouldRun ? "Starting…" : "Stopping…"
        serviceStatus.stringValue = shouldRun ? "Starting service…" : "Stopping service…"
        serviceStatus.textColor = .secondaryLabelColor

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak app] in
            var failure: String?
            do {
                guard let app else { throw NSError(domain: "Keywi", code: 4, userInfo: [NSLocalizedDescriptionKey: "Keywi is unavailable."]) }
                try app.setServiceRunning(shouldRun)
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.serviceChangeInProgress = false
                if let failure {
                    self.showFeedback(failure)
                }
                self.refresh()
            }
        }
    }
}

extension AppDelegate { var mappingsForDisplay: [Mapping] { mappings } }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
