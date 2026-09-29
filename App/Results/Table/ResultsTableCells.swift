import AppKit
import DedupCore

/// A text cell. Values that differ from the rest of the group get a tinted background.
final class TextCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("TextCell")

    private let label = NSTextField(labelWithString: "")
    private var differs = false

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, isNumeric: Bool, differs: Bool) {
        label.stringValue = text
        label.alignment = isNumeric ? .right : .left
        label.font = isNumeric ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) : .systemFont(ofSize: NSFont.systemFontSize)
        label.toolTip = text.isEmpty ? nil : text
        if differs != self.differs {
            self.differs = differs
            needsDisplay = true
        }
        setAccessibilityLabel(differs ? "\(text), differs from the other copies" : text)
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { if differs { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard differs else { return }
        let tint = backgroundStyle == .emphasized
            ? NSColor.white.withAlphaComponent(0.25)
            : NSColor.systemYellow.withAlphaComponent(0.3)
        tint.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
    }
}

/// The tick box that marks a copy for removal.
final class MarkCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("MarkCell")

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var trackID: Track.ID = 0
    private var onToggle: ((Track.ID) -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.setAccessibilityLabel("Mark for removal")
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)
        NSLayoutConstraint.activate([
            checkbox.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isMarked: Bool {
        get { checkbox.state == .on }
        set { checkbox.state = newValue ? .on : .off }
    }

    func configure(trackID: Track.ID, isMarked: Bool, onToggle: @escaping (Track.ID) -> Void) {
        self.trackID = trackID
        self.isMarked = isMarked
        self.onToggle = onToggle
    }

    @objc private func toggled() {
        onToggle?(trackID)
    }
}

/// The ▶ column: a speaker on the copy in the player, and a play or pause
/// button on the row under the pointer. The button is there on every row,
/// even when it shows nothing, so a click in the cell always works.
final class PlayCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("PlayCell")

    private let button = NSButton()
    private var onClick: (() -> Void)?
    private(set) var isCurrent = false
    private(set) var isPlaying = false

    var isHovered = false {
        didSet { if isHovered != oldValue { refresh() } }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(clicked)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 20),
            button.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(isCurrent: Bool, isPlaying: Bool, isHovered: Bool, onClick: @escaping () -> Void) {
        self.isCurrent = isCurrent
        self.isPlaying = isPlaying
        self.isHovered = isHovered
        self.onClick = onClick
        refresh()
    }

    func update(isCurrent: Bool, isPlaying: Bool) {
        guard isCurrent != self.isCurrent || isPlaying != self.isPlaying else { return }
        self.isCurrent = isCurrent
        self.isPlaying = isPlaying
        refresh()
    }

    /// The symbol the button shows, if any.
    var symbolName: String? {
        switch (isCurrent, isHovered) {
        case (true, false): isPlaying ? "speaker.wave.2.fill" : "speaker.fill"
        case (true, true): isPlaying ? "pause.fill" : "play.fill"
        case (false, true): "play.fill"
        case (false, false): nil
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { refresh() }
    }

    private func refresh() {
        button.image = symbolName.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        button.contentTintColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor
            : isCurrent ? .controlAccentColor : .secondaryLabelColor
        button.setAccessibilityLabel(isCurrent && isPlaying ? "Pause" : "Play")
    }

    @objc private func clicked() {
        onClick?()
    }
}

/// The full-width row above each group: a disclosure button, the track, and
/// how many copies there are, how confident the match is and why.
final class GroupHeaderView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("GroupHeader")

    private let disclosure = NSButton(title: "", target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let warning = NSStackView()
    /// Called with true when Option is held, meaning every group.
    private var onToggle: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier

        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.onOff)
        disclosure.target = self
        disclosure.action = #selector(disclosureClicked)
        disclosure.setAccessibilityLabel("Show copies")

        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemOrange
        let warningLabel = NSTextField(labelWithString: "Every copy is marked for removal")
        warningLabel.textColor = .systemOrange
        warning.orientation = .horizontal
        warning.spacing = 4
        warning.addArrangedSubview(icon)
        warning.addArrangedSubview(warningLabel)
        warning.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [disclosure, titleLabel, detailLabel, spacer, warning])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, detail: String, isExpanded: Bool, everyCopyMarked: Bool, onToggle: @escaping (Bool) -> Void) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        self.isExpanded = isExpanded
        self.everyCopyMarked = everyCopyMarked
        self.onToggle = onToggle
        setAccessibilityLabel("\(title), \(detail)")
    }

    var isExpanded: Bool {
        get { disclosure.state == .on }
        set { disclosure.state = newValue ? .on : .off }
    }

    var everyCopyMarked: Bool {
        get { !warning.isHidden }
        set { warning.isHidden = !newValue }
    }

    @objc private func disclosureClicked() {
        onToggle?(NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
    }

    /// Clicking anywhere on the header shows or hides the group, as the button does.
    override func mouseDown(with event: NSEvent) {
        onToggle?(event.modifierFlags.contains(.option))
    }
}

/// Paints each group's rows in one of two alternating colours, so groups
/// read as bands, and header rows in a colour of their own.
final class BandRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("BandRow")

    var band = 0 {
        didSet { if band != oldValue { needsDisplay = true } }
    }

    var isHeader = false {
        didSet { if isHeader != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isHeader {
            // A faint wash of the text colour, so headers stand apart in light and dark mode.
            NSColor.controlBackgroundColor.setFill()
            bounds.fill()
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            bounds.fill()
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        } else {
            let colours = NSColor.alternatingContentBackgroundColors
            colours[band % colours.count].setFill()
            dirtyRect.fill()
        }
    }
}
