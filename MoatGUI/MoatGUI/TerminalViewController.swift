import AppKit
import MoatKit
import SwiftTerm

/// A terminal hosting a `Session` in a given workspace, passing along user
/// input. Contents are preserved after a session stops, and input is ignored
/// until another session starts.
final class TerminalViewController: NSViewController, TerminalViewDelegate {
    private let workspace: Workspace
    private let model: SessionsModel
    private let terminalView = TerminalView(frame: .zero)

    /// The session being shown, if one has started.
    private var session: Session?

    init(workspace: Workspace, model: SessionsModel) {
        self.workspace = workspace
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        terminalView.terminalDelegate = self
        view = terminalView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            await showSessions()
        }
    }

    /// Shows each session started for `workspace`, as it starts.
    private func showSessions() async {
        let sessions = Observations { @MainActor [model, workspace] in
            model.localSession(workspace: workspace)
        }
        for await session in sessions {
            guard let session, session !== self.session else {
                continue
            }
            self.session = session
            // The session may have started at a different size.
            let dimensions = terminalView.terminalDimensions
            session.resize(
                TerminalSize(columns: dimensions.cols, rows: dimensions.rows),
            )
            // A session only starts once the previous one has exited, so this
            // shows all of one session's output before the next one's.
            await showOutput(session: session)
        }
    }

    private func showOutput(session: Session) async {
        do {
            for try await chunk in session.outputStream {
                terminalView.feed(byteArray: chunk)
            }
        } catch {
            Logger.warn("Couldn't read output for \(workspace): \(error)")
        }
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard let session else {
            return
        }
        switch session.state {
        case .running:
            session.write(data)
        case .stopping, .exited, .signaled, .failed:
            break
        }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        session?.resize(TerminalSize(columns: newCols, rows: newRows))
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
