import AppKit

// A titled window that closes itself when Escape (or ⌘.) is pressed.
final class EscapeClosingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

// A simple settings window for managing destinations without hand-editing JSON.
// Left: a list of destinations. Right: a form to edit the selected one.
final class SettingsController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: Store
    private let prefs = Preferences.shared
    private var items: [Destination] = []

    private var window: NSWindow?
    private var tableView: NSTableView!

    // Form controls.
    private let nameField = NSTextField()
    private let kindPopup = NSPopUpButton()
    private let pathField = NSTextField()
    private let browseButton = NSButton()
    private let appsPopup = NSPopUpButton()
    private var installedApps: [InstalledApp] = []
    private let serviceLabel = NSTextField(labelWithString: "Service:")
    private let servicePopup = NSPopUpButton()
    private let moveCheckbox = NSButton(checkboxWithTitle: "Move files instead of copying", target: nil, action: nil)
    private let iconField = NSTextField()
    private let iconBrowseButton = NSButton()
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enabled (show in palette)", target: nil, action: nil)
    private var acceptsCheckboxes: [String: NSButton] = [:]
    private let acceptsOrder = ["any", "image", "video", "audio", "pdf", "text", "folder", "other"]

    private let kindTitles = ["Folder", "App", "Script", "Share"]
    private let kindValues: [DestinationKind] = [.folder, .app, .script, .share]
    private let serviceTitles = ["AirDrop", "Messages", "Mail", "Notes", "Reminders"]

    init(store: Store) {
        self.store = store
        super.init()
    }

    // MARK: - Show

    func show() { show(selecting: 0) }

    /// Open the manager with the first destination of `category` selected, so the
    /// category row in Preferences jumps straight to the relevant entries.
    func show(category: DestinationCategory) {
        let firstMatch = store.destinations.firstIndex(where: { category.matches($0) }) ?? 0
        show(selecting: firstMatch)
    }

    private func show(selecting row: Int) {
        items = store.destinations
        if window == nil { buildWindow() }
        applyAppearance()
        tableView.reloadData()
        if !items.isEmpty {
            let safeRow = items.indices.contains(row) ? row : 0
            tableView.selectRowIndexes(IndexSet(integer: safeRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(safeRow)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    /// Match the window to the app's Appearance preference. (A standard window
    /// otherwise just follows the system, so "Light" had no effect in dark mode.)
    private func applyAppearance() {
        switch prefs.appearance {
        case "Light": window?.appearance = NSAppearance(named: .aqua)
        case "Dark":  window?.appearance = NSAppearance(named: .darkAqua)
        default:      window?.appearance = nil   // Clear → follow the system
        }
    }

    // MARK: - Build UI

    private func buildWindow() {
        let win = EscapeClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Quick_Drop — Destinations"
        win.delegate = self
        win.isReleasedWhenClosed = false
        let content = win.contentView!

        // Destination list (left).
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 56, width: 230, height: 388))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.height]

        let table = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dest"))
        col.width = 210
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 28
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        scroll.documentView = table
        self.tableView = table
        content.addSubview(scroll)

        // Add / Remove segmented control (bottom-left).
        let seg = NSSegmentedControl(labels: ["+", "–"], trackingMode: .momentary, target: self, action: #selector(addRemoveClicked))
        seg.frame = NSRect(x: 16, y: 18, width: 84, height: 26)
        seg.autoresizingMask = [.maxXMargin]
        content.addSubview(seg)

        // Edit-as-JSON escape hatch (opens destinations.json in the default editor).
        let editJSON = NSButton(frame: NSRect(x: 108, y: 18, width: 110, height: 26))
        editJSON.title = "Edit JSON…"
        editJSON.bezelStyle = .rounded
        editJSON.target = self
        editJSON.action = #selector(editJSONClicked)
        editJSON.autoresizingMask = [.maxXMargin]
        content.addSubview(editJSON)

        // Reload from disk (picks up external edits to destinations.json).
        let reload = NSButton(frame: NSRect(x: 226, y: 18, width: 90, height: 26))
        reload.title = "Reload"
        reload.bezelStyle = .rounded
        reload.target = self
        reload.action = #selector(reloadClicked)
        reload.autoresizingMask = [.maxXMargin]
        content.addSubview(reload)

        // Right-hand form.
        let formX: CGFloat = 264
        let labelX: CGFloat = formX
        let fieldX: CGFloat = formX + 88
        let fieldW: CGFloat = 312

        func addLabel(_ text: String, y: CGFloat) {
            let l = NSTextField(labelWithString: text)
            l.frame = NSRect(x: labelX, y: y, width: 84, height: 18)
            l.alignment = .right
            content.addSubview(l)
        }

        addLabel("Name:", y: 408)
        nameField.frame = NSRect(x: fieldX, y: 404, width: fieldW, height: 24)
        content.addSubview(nameField)

        addLabel("Kind:", y: 372)
        kindPopup.frame = NSRect(x: fieldX, y: 368, width: 160, height: 26)
        kindPopup.addItems(withTitles: kindTitles)
        kindPopup.target = self
        kindPopup.action = #selector(kindChanged)
        content.addSubview(kindPopup)

        addLabel("Path:", y: 336)
        pathField.frame = NSRect(x: fieldX, y: 332, width: fieldW - 92, height: 24)
        content.addSubview(pathField)
        browseButton.frame = NSRect(x: fieldX + fieldW - 84, y: 330, width: 84, height: 26)
        browseButton.title = "Browse…"
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browsePath)
        content.addSubview(browseButton)

        // Installed-apps picker (shown only for the App kind), same row as Path.
        installedApps = InstalledApps.all()
        appsPopup.frame = NSRect(x: fieldX, y: 330, width: fieldW, height: 26)
        appsPopup.addItems(withTitles: installedApps.map { $0.name })
        appsPopup.target = self
        appsPopup.action = #selector(appSelected)
        content.addSubview(appsPopup)

        serviceLabel.frame = NSRect(x: labelX, y: 300, width: 84, height: 18)
        serviceLabel.alignment = .right
        content.addSubview(serviceLabel)
        servicePopup.frame = NSRect(x: fieldX, y: 296, width: 160, height: 26)
        servicePopup.addItems(withTitles: serviceTitles)
        servicePopup.target = self
        servicePopup.action = #selector(serviceChanged)
        content.addSubview(servicePopup)

        moveCheckbox.frame = NSRect(x: fieldX, y: 264, width: fieldW, height: 20)
        content.addSubview(moveCheckbox)

        addLabel("Icon:", y: 228)
        iconField.frame = NSRect(x: fieldX, y: 224, width: fieldW - 92, height: 24)
        iconField.placeholderString = "Optional custom icon (png/icns)"
        content.addSubview(iconField)
        iconBrowseButton.frame = NSRect(x: fieldX + fieldW - 84, y: 222, width: 84, height: 26)
        iconBrowseButton.title = "Browse…"
        iconBrowseButton.bezelStyle = .rounded
        iconBrowseButton.target = self
        iconBrowseButton.action = #selector(browseIcon)
        content.addSubview(iconBrowseButton)

        // Enabled toggle.
        enabledCheckbox.frame = NSRect(x: fieldX, y: 192, width: fieldW, height: 20)
        content.addSubview(enabledCheckbox)

        // Accepted file types (which file kinds make this destination appear).
        addLabel("Accepts:", y: 162)
        let colW: CGFloat = 78
        for (i, cat) in acceptsOrder.enumerated() {
            let row = i / 4, col = i % 4
            let title = cat == "any" ? "Any" : FileCategory.label(cat)
            let cb = NSButton(checkboxWithTitle: title, target: self, action: #selector(acceptsChanged(_:)))
            cb.frame = NSRect(x: fieldX + CGFloat(col) * colW, y: 142 - CGFloat(row) * 24, width: colW, height: 20)
            content.addSubview(cb)
            acceptsCheckboxes[cat] = cb
        }

        // Save button (bottom-right).
        let save = NSButton(frame: NSRect(x: 680 - 16 - 120, y: 18, width: 120, height: 28))
        save.title = "Save"
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.target = self
        save.action = #selector(saveClicked)
        save.autoresizingMask = [.minXMargin]
        content.addSubview(save)

        self.window = win
    }

    // MARK: - Table data

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("destCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            let iv = NSImageView(frame: NSRect(x: 4, y: 4, width: 20, height: 20))
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.identifier = NSUserInterfaceItemIdentifier("icon")
            c.addSubview(iv)
            c.imageView = iv
            let tf = NSTextField(labelWithString: "")
            tf.frame = NSRect(x: 30, y: 4, width: 170, height: 20)
            c.addSubview(tf)
            c.textField = tf
            c.identifier = id
            return c
        }()
        let dest = items[row]
        cell.imageView?.image = dest.icon
        cell.imageView?.alphaValue = dest.isEnabled ? 1.0 : 0.4
        cell.textField?.stringValue = dest.isEnabled ? dest.name : "\(dest.name)  (disabled)"
        cell.textField?.textColor = dest.isEnabled ? .labelColor : .tertiaryLabelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        loadFormFromSelection()
    }

    @objc private func rowClicked() { loadFormFromSelection() }

    // MARK: - Form <-> model

    private func loadFormFromSelection() {
        let row = tableView.selectedRow
        guard items.indices.contains(row) else { return }
        let d = items[row]
        nameField.stringValue = d.name
        if let kindIndex = kindValues.firstIndex(of: d.kind) {
            kindPopup.selectItem(at: kindIndex)
        }
        pathField.stringValue = d.path
        iconField.stringValue = d.iconPath ?? ""
        moveCheckbox.state = (d.moveOnDrop ?? false) ? .on : .off
        if let service = d.service,
           let idx = serviceTitles.firstIndex(where: { $0.lowercased() == service.lowercased() }) {
            servicePopup.selectItem(at: idx)
        }
        if d.kind == .app, let appIdx = installedApps.firstIndex(where: { $0.path == d.path }) {
            appsPopup.selectItem(at: appIdx)
            nameField.stringValue = installedApps[appIdx].name
        }

        enabledCheckbox.state = d.isEnabled ? .on : .off
        let acc = d.accepts ?? []
        let isAny = acc.isEmpty || acc.contains("any")
        acceptsCheckboxes["any"]?.state = isAny ? .on : .off
        for (key, box) in acceptsCheckboxes where key != "any" {
            box.state = acc.contains(key) ? .on : .off
        }

        updateFieldVisibility()
    }

    @objc private func acceptsChanged(_ sender: NSButton) {
        // "Any" is mutually exclusive with the specific categories.
        if acceptsCheckboxes["any"] === sender {
            if sender.state == .on {
                for (key, box) in acceptsCheckboxes where key != "any" { box.state = .off }
            }
        } else if sender.state == .on {
            acceptsCheckboxes["any"]?.state = .off
        }
    }

    @objc private func appSelected() {
        let idx = appsPopup.indexOfSelectedItem
        guard installedApps.indices.contains(idx) else { return }
        // App destinations always take the app's name (the name field is locked).
        nameField.stringValue = installedApps[idx].name
    }

    @objc private func serviceChanged() {
        // Share destinations take the service's name (the name field is locked).
        if selectedKind == .share {
            nameField.stringValue = servicePopup.titleOfSelectedItem ?? nameField.stringValue
        }
    }

    private var selectedKind: DestinationKind {
        kindValues[kindPopup.indexOfSelectedItem]
    }

    @objc private func kindChanged() { updateFieldVisibility() }

    private func updateFieldVisibility() {
        let kind = selectedKind
        let isShare = kind == .share
        let isFolder = kind == .folder
        let isApp = kind == .app

        // App kind uses the installed-apps picker instead of a free path field.
        appsPopup.isHidden = !isApp
        pathField.isHidden = isShare || isApp
        browseButton.isHidden = isShare || isApp
        serviceLabel.isHidden = !isShare
        servicePopup.isHidden = !isShare
        moveCheckbox.isHidden = !isFolder

        // Only Script destinations have a freely-editable name; Folder/App/Share
        // names are derived (folder name / app name / service name) and locked.
        let lockName = (kind != .script)
        nameField.isEnabled = !lockName
        nameField.isEditable = !lockName
        if isApp {
            let idx = appsPopup.indexOfSelectedItem
            if installedApps.indices.contains(idx) {
                nameField.stringValue = installedApps[idx].name
            }
        } else if isShare {
            nameField.stringValue = servicePopup.titleOfSelectedItem ?? nameField.stringValue
        } else if isFolder {
            nameField.stringValue = (pathField.stringValue as NSString).lastPathComponent
        }

        // Only Script destinations allow a custom icon; everything else uses the
        // automatic icon (app / folder / service).
        let allowCustomIcon = (kind == .script)
        iconField.isEnabled = allowCustomIcon
        iconField.isEditable = allowCustomIcon
        iconBrowseButton.isEnabled = allowCustomIcon
        iconField.placeholderString = allowCustomIcon
            ? "Optional custom icon (png/icns)"
            : "Uses the automatic icon"
    }

    @objc private func saveClicked() {
        let row = tableView.selectedRow
        let kind = selectedKind
        let serviceKey = serviceTitles[max(0, servicePopup.indexOfSelectedItem)].lowercased()

        // Resolve the path: apps come from the installed-apps picker.
        var path = pathField.stringValue
        var name = nameField.stringValue
        if kind == .app {
            let idx = appsPopup.indexOfSelectedItem
            if installedApps.indices.contains(idx) {
                path = installedApps[idx].path
                name = installedApps[idx].name          // always the app's name
            }
        } else if kind == .share {
            path = ""
            name = servicePopup.titleOfSelectedItem ?? name   // service name
        } else if kind == .folder {
            name = (path as NSString).lastPathComponent  // folder's own name
        }

        // Only Script destinations allow a custom icon.
        let allowCustomIcon = (kind == .script)
        let iconPath = (allowCustomIcon && !iconField.stringValue.isEmpty) ? iconField.stringValue : nil

        // Accepted file types ("Any" or none → nil = accepts everything).
        var accepts: [String]? = nil
        if acceptsCheckboxes["any"]?.state != .on {
            let chosen = acceptsOrder.filter { $0 != "any" && acceptsCheckboxes[$0]?.state == .on }
            accepts = chosen.isEmpty ? nil : chosen
        }

        let d = Destination(
            name: name.isEmpty ? "Untitled" : name,
            kind: kind,
            path: path,
            moveOnDrop: kind == .folder ? (moveCheckbox.state == .on) : nil,
            iconPath: iconPath,
            service: kind == .share ? serviceKey : nil,
            enabled: enabledCheckbox.state == .on,
            accepts: accepts
        )

        if items.indices.contains(row) {
            items[row] = d
        } else {
            items.append(d)
        }
        store.replaceAll(items)
        tableView.reloadData()
        Destination.notify(title: "Quick_Drop", body: "Saved \(items.count) destinations.")
        window?.close()
    }

    @objc private func addRemoveClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let new = Destination(name: "New Folder", kind: .folder,
                                  path: home.appendingPathComponent("Desktop").path,
                                  moveOnDrop: false, iconPath: nil)
            items.append(new)
            store.replaceAll(items)
            tableView.reloadData()
            let last = items.count - 1
            tableView.selectRowIndexes(IndexSet(integer: last), byExtendingSelection: false)
        } else {
            let row = tableView.selectedRow
            guard items.indices.contains(row) else { return }
            items.remove(at: row)
            store.replaceAll(items)
            tableView.reloadData()
        }
    }

    @objc private func editJSONClicked() {
        store.openConfigInEditor()
    }

    @objc private func reloadClicked() {
        store.load()
        items = store.destinations
        tableView.reloadData()
        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        Destination.notify(title: "Quick_Drop", body: "Reloaded \(items.count) destinations.")
    }

    /// Re-apply the appearance preference to the open window (called live when the
    /// Appearance popup changes in Preferences).
    func refreshAppearance() {
        guard window != nil else { return }
        applyAppearance()
    }

    // MARK: - Browse panels

    @objc private func browsePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pathField.stringValue = url.path
            // Refresh the derived (locked) folder name from the new path.
            updateFieldVisibility()
        }
    }

    @objc private func browseIcon() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            iconField.stringValue = url.path
        }
    }
}
