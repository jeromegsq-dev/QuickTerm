import AppKit
import SwiftTerm

/// Sits between a terminal view and SwiftTerm's default delegate to refuse
/// what terminal output must not be able to trigger on its own.
///
/// Anything printed in a terminal is untrusted: a remote host over ssh, a
/// file shown with `cat`, the body of a `curl` response.
final class TerminalGuard: TerminalViewDelegate {
    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]

    private weak var view: LocalProcessTerminalView?

    init(view: LocalProcessTerminalView) {
        self.view = view
    }

    // MARK: - Refused or restricted

    /// OSC 52 query: would hand the clipboard (passwords, tokens) to whatever is printing.
    func clipboardRead(source: TerminalView) -> Data? {
        nil
    }

    /// OSC 52 write: would let output silently replace what the user pastes next.
    func clipboardCopy(source: TerminalView, content: Data) {}

    /// Links carry a target chosen by the output. Web and mail only: no
    /// `file:` (launches apps and scripts) and no custom app schemes.
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(),
              Self.linkSchemes.contains(scheme)
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Forwarded unchanged

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        view?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        view?.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        view?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        view?.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        view?.scrolled(source: source, position: position)
    }

    func bell(source: TerminalView) {
        view?.bell(source: source)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        view?.iTermContent(source: source, content: content)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        view?.rangeChanged(source: source, startY: startY, endY: endY)
    }
}
