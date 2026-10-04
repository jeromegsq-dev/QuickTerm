import AppKit
import Darwin
import SwiftTerm

/// One shell session and its terminal view.
final class TerminalTab {
    let view = LocalProcessTerminalView(frame: .zero)
    /// The view only holds its delegate weakly.
    private let outputGuard: TerminalGuard

    init(delegate: LocalProcessTerminalViewDelegate, directory: String) {
        outputGuard = TerminalGuard(view: view)
        view.terminalDelegate = outputGuard
        view.processDelegate = delegate
        view.autoresizingMask = [.width, .height]
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeForegroundColor = NSColor(white: 0.93, alpha: 1)
        view.nativeBackgroundColor = NSColor(white: 0.04, alpha: 1)
        // The card paints the tint, so margins and tab bar match the terminal.
        view.backgroundOpacity = 0
        view.caretColor = .systemGreen
        view.optionAsMetaKey = true
        // Always-visible scroll bar: the overlay style has a 6 pt knob and a dead track.
        view.scrollerStyle = .legacy
        // GPU glyph renderer; SwiftTerm keeps CoreGraphics if Metal can't start.
        do {
            try view.setUseMetal(true)
        } catch {
            NSLog("QuickTerm: Metal renderer unavailable, using CoreGraphics (%@)", "\(error)")
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let name = (shell as NSString).lastPathComponent
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        environment.append("TERM_PROGRAM=QuickTerm")
        environment.append("SHELL=\(shell)")
        view.startProcess(
            executable: shell,
            environment: environment,
            execName: "-\(name)",  // login shell
            currentDirectory: directory
        )
    }

    /// True at the prompt; false while a program (vim, less, claude…) owns the terminal.
    var shellIsForeground: Bool {
        foregroundProgram == nil
    }

    /// The running program's name, or the shell's current folder at the prompt.
    var title: String {
        if let program = foregroundProgram { return program }
        guard let directory = workingDirectory else { return "shell" }
        return directory == NSHomeDirectory() ? "~" : (directory as NSString).lastPathComponent
    }

    var workingDirectory: String? {
        guard let process = view.process, process.running else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(process.shellPid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    private var foregroundProgram: String? {
        guard let process = view.process, process.running else { return nil }
        let foreground = tcgetpgrp(process.childfd)
        guard foreground > 0, foreground != process.shellPid else { return nil }
        var name = [CChar](repeating: 0, count: 256)
        guard proc_name(foreground, &name, UInt32(name.count)) > 0 else { return nil }
        return String(cString: name)
    }
}
