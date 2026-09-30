import AppKit
import ViewerBridge

@MainActor
final class ViewerWindow {
    let window: NSWindow
    let openButton: NSButton

    init(readiness: ViewerReadiness) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DICOM Viewer"
        window.minSize = NSSize(width: 760, height: 500)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ViewerMainWindow")

        openButton = NSButton(title: "열기…", target: nil, action: nil)
        openButton.bezelStyle = .rounded
        openButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        openButton.imagePosition = .imageLeading
        openButton.isEnabled = readiness.canOpenDicom
        openButton.toolTip = "영상 열기 기능을 준비하고 있습니다."

        let root = NSView()
        window.contentView = root
        let sidebar = makeSidebar()
        let divider = NSBox()
        divider.boxType = .separator
        let main = NSView()
        [sidebar, divider, main].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview($0)
        }

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 240),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            main.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            main.topAnchor.constraint(equalTo: root.topAnchor),
            main.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        installMainContent(in: main)
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSView()
        let title = label("검사 목록", size: 14, weight: .semibold)
        let empty = label("아직 열린 검사가 없습니다.", size: 12, color: .secondaryLabelColor)
        [title, empty].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview($0)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -20),
            title.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 24),
            empty.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            empty.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            empty.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
        ])
        return sidebar
    }

    private func installMainContent(in main: NSView) {
        let title = label("영상", size: 14, weight: .semibold)
        let viewport = NSView()
        viewport.wantsLayer = true
        viewport.layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
        viewport.layer?.cornerRadius = 10
        viewport.setAccessibilityLabel("영상 영역: 열린 영상 없음")
        let status = label("영상 없음", size: 11, color: .secondaryLabelColor)
        [title, openButton, viewport, status].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            main.addSubview($0)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: main.topAnchor, constant: 24),
            openButton.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -24),
            openButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            viewport.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 20),
            viewport.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20),
            viewport.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 24),
            viewport.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -16),
            status.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 24),
            status.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -16),
        ])

        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        image.contentTintColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        image.translatesAutoresizingMaskIntoConstraints = false
        let emptyTitle = label("열린 영상이 없습니다.", size: 19, weight: .medium, color: .white)
        emptyTitle.alignment = .center
        let explanation = label("영상 열기 기능을 준비하고 있습니다.", size: 13, color: NSColor(calibratedWhite: 0.65, alpha: 1))
        explanation.alignment = .center
        let emptyContent = NSStackView(views: [image, emptyTitle, explanation])
        emptyContent.orientation = .vertical
        emptyContent.alignment = .centerX
        emptyContent.spacing = 12
        emptyContent.translatesAutoresizingMaskIntoConstraints = false
        viewport.addSubview(emptyContent)
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 42),
            image.heightAnchor.constraint(equalToConstant: 42),
            emptyContent.centerXAnchor.constraint(equalTo: viewport.centerXAnchor),
            emptyContent.centerYAnchor.constraint(equalTo: viewport.centerYAnchor),
            emptyContent.widthAnchor.constraint(lessThanOrEqualTo: viewport.widthAnchor, constant: -48),
        ])
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        return field
    }
}
