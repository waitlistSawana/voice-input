import AppKit
import VoiceInputCore

@MainActor
public final class SettingsViewController: NSViewController {
    public typealias TestConnectionAction = @Sendable (LLMConfiguration) async -> Result<Void, Error>

    public struct Dependencies {
        public let settingsStore: SettingsStore
        public let onTestConnection: TestConnectionAction

        public init(
            settingsStore: SettingsStore,
            onTestConnection: @escaping TestConnectionAction = { config in
                await LLMRefiner().testConnection(config: config)
            }
        ) {
            self.settingsStore = settingsStore
            self.onTestConnection = onTestConnection
        }
    }

    private let dependencies: Dependencies

    let apiBaseURLField = NSTextField(string: "")
    let apiKeyField = NSSecureTextField(string: "")
    let modelField = NSTextField(string: "")
    let testButton = NSButton(title: "Test", target: nil, action: nil)
    let saveButton = NSButton(title: "Save", target: nil, action: nil)

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = rootView
        buildInterface()
        loadStoredValues()
    }

    private func buildInterface() {
        let titleLabel = NSTextField(labelWithString: "LLM Refinement")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: "Configure an OpenAI-compatible endpoint for transcript refinement.")
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureTextField(apiBaseURLField, placeholder: "https://example.com/v1")
        configureTextField(apiKeyField, placeholder: "API key")
        configureTextField(modelField, placeholder: "gpt-4.1-mini")

        testButton.target = self
        testButton.action = #selector(testConnectionAction)
        testButton.bezelStyle = .rounded

        saveButton.target = self
        saveButton.action = #selector(saveAction)
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let baseURLRow = makeRow(title: "API Base URL", field: apiBaseURLField)
        let apiKeyRow = makeRow(title: "API Key", field: apiKeyField)
        let modelRow = makeRow(title: "Model", field: modelField)

        let formStack = NSStackView(views: [baseURLRow, apiKeyRow, modelRow])
        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.spacing = 12
        formStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [testButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let outerStack = NSStackView(views: [titleLabel, subtitleLabel, formStack, buttonRow])
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 14
        outerStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: view.topAnchor),
            outerStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            apiBaseURLField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            apiKeyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            modelField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320)
        ])
    }

    private func configureTextField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func makeRow(title: String, field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        return row
    }

    private func loadStoredValues() {
        let configuration = dependencies.settingsStore.llmConfiguration
        apiBaseURLField.stringValue = configuration.baseURL
        apiKeyField.stringValue = configuration.apiKey
        modelField.stringValue = configuration.model
    }

    private func currentConfiguration() -> LLMConfiguration {
        LLMConfiguration(
            baseURL: apiBaseURLField.stringValue,
            apiKey: apiKeyField.stringValue,
            model: modelField.stringValue
        )
    }

    @objc func saveAction() {
        dependencies.settingsStore.llmConfiguration = currentConfiguration()
    }

    @objc func testConnectionAction() {
        let configuration = currentConfiguration()
        let testConnection = dependencies.onTestConnection
        testButton.isEnabled = false

        Task { [weak self] in
            _ = await testConnection(configuration)
            await MainActor.run {
                self?.testButton.isEnabled = true
            }
        }
    }
}
