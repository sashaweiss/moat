import AppKit

/// Shows the selected session's terminal. Each workspace's terminal is kept
/// while another is selected, so it keeps its contents.
final class SessionContentViewController: NSViewController {
    private let model: SessionsModel
    private var terminalViewControllers: [String: TerminalViewController] = [:]

    init(model: SessionsModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            await showSelection()
        }
    }

    /// Shows the selected workspace's terminal, whenever the selection
    /// changes.
    private func showSelection() async {
        let selections = Observations { @MainActor [model] in
            model.selectedWorkspace
        }
        for await workspace in selections {
            show(workspace: workspace)
        }
    }

    private func show(workspace: String?) {
        for child in children {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        guard let workspace else {
            return
        }

        let terminalViewController = terminalViewControllers[workspace]
            ?? TerminalViewController(workspace: workspace, model: model)
        terminalViewControllers[workspace] = terminalViewController
        addChild(terminalViewController)

        let terminal = terminalViewController.view
        terminal.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminal)
        NSLayoutConstraint.activate([
            // Below the title bar, which the content extends beneath.
            terminal.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
            ),
            terminal.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}
