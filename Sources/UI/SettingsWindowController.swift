import AppKit

@MainActor
public final class SettingsWindowController: NSWindowController {
    public typealias RootViewControllerFactory = @MainActor (SettingsViewController.Dependencies) -> NSViewController

    private static func makeDefaultRootViewController(
        _ dependencies: SettingsViewController.Dependencies
    ) -> NSViewController {
        SettingsViewController(dependencies: dependencies)
    }

    public init(
        dependencies: SettingsViewController.Dependencies,
        rootViewControllerFactory: RootViewControllerFactory? = nil
    ) {
        let factory = rootViewControllerFactory ?? Self.makeDefaultRootViewController
        let window = NSWindow(contentViewController: factory(dependencies))
        window.title = "Settings"
        window.styleMask.insert([.closable, .miniaturizable, .titled])
        window.setContentSize(NSSize(width: 520, height: 320))
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
