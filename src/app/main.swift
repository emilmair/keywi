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
        popover.contentSize = NSSize(width: 320, height: 360)
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
    private let mappingsText = NSTextField(wrappingLabelWithString: "")
    private var serviceIsRunning = false
    private var serviceChangeInProgress = false
    private var serviceRefreshID = 0

    init(delegate: AppDelegate) { appDelegate = delegate; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 360))
        root.wantsLayer = true
        view = root

        let title = NSTextField(labelWithString: "Keywi")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.frame = NSRect(x: 16, y: 322, width: 180, height: 26)
        root.addSubview(title)

        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.frame = NSRect(x: 246, y: 320, width: 58, height: 28)
        root.addSubview(quit)

        let subtitle = NSTextField(labelWithString: "Keyboard mappings")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 16, y: 294, width: 280, height: 18)
        root.addSubview(subtitle)

        serviceStatus.frame = NSRect(x: 16, y: 260, width: 190, height: 20)
        root.addSubview(serviceStatus)

        serviceButton.frame = NSRect(x: 218, y: 254, width: 86, height: 28)
        serviceButton.target = self
        serviceButton.action = #selector(toggleService(_:))
        serviceButton.isEnabled = false
        root.addSubview(serviceButton)

        serviceFeedback.frame = NSRect(x: 16, y: 224, width: 288, height: 26)
        serviceFeedback.font = .systemFont(ofSize: 11)
        serviceFeedback.textColor = .systemRed
        serviceFeedback.maximumNumberOfLines = 2
        serviceFeedback.isHidden = true
        root.addSubview(serviceFeedback)

        let separator = NSBox(frame: NSRect(x: 16, y: 218, width: 288, height: 1))
        separator.boxType = .separator
        root.addSubview(separator)

        mappingsText.frame = NSRect(x: 16, y: 16, width: 288, height: 194)
        mappingsText.font = .systemFont(ofSize: 14)
        mappingsText.textColor = .labelColor
        mappingsText.lineBreakMode = .byWordWrapping
        mappingsText.maximumNumberOfLines = 0
        root.addSubview(mappingsText)

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .keywiMappingsChanged, object: nil)
        refresh()
    }

    @objc private func refresh() {
        guard let app = appDelegate else { return }
        app.loadMappings()
        let mappings = app.mappingsForDisplay
        if let error = app.mappingLoadError {
            mappingsText.stringValue = "Could not read mappings: \(error)"
        } else if mappings.isEmpty {
            mappingsText.stringValue = "No mappings configured"
        } else {
            mappingsText.stringValue = mappings.map { "\(app.keyLabel($0.source))    →    \(app.keyLabel($0.destination))" }.joined(separator: "\n")
        }

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

    @objc private func toggleService(_ sender: Any?) {
        guard let app = appDelegate, !serviceChangeInProgress else { return }
        let shouldRun = !serviceIsRunning
        serviceChangeInProgress = true
        serviceRefreshID += 1
        serviceFeedback.stringValue = ""
        serviceFeedback.isHidden = true
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
                    self.serviceFeedback.stringValue = failure
                    self.serviceFeedback.isHidden = false
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
