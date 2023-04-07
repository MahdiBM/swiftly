import Foundation

public protocol UnixShell {
    /// Detects if a shell "exists". Users have multiple shells, so an "eager"
    /// heuristic should be used, assuming shells exist if any traces do.
    func doesExist() -> Bool
    /// Gives all rcfiles of a given shell that Swiftly is concerned with.
    /// Used primarily in checking rcfiles for cleanup.
    func rcFiles() -> [URL]
    /// RC files that should be written to.
    func updateRcs() -> [URL]
    /// The env script.
    func envScript() -> ShellScript
    /// The source string to trigger the env script.
    func sourceString() throws -> String
}

extension UnixShell {
    func envScript() -> ShellScript {
        return .default
    }

    func sourceString() throws -> String {
        return #". "\#(Utils.swiftlyHomeDirectory)/env""#
    }
}

public func get_available_shells() -> [UnixShell] {
    [Posix(), Bash(), Zsh()].filter { $0.doesExist() }
}

struct Posix: UnixShell {
    func doesExist() -> Bool {
        true
    }

    func rcFiles() -> [URL] {
        [Utils.userHomeDirectory.map { $0.appendingPathComponent(".profile") }].compactMap { $0 }
    }

    func updateRcs() -> [URL] {
        // Write to .profile even if it doesn't exist. It's the only rc in the
        // POSIX spec so it should always be set up.
        return rcFiles()
    }
}

struct Bash: UnixShell {
    func doesExist() -> Bool {
        !updateRcs().isEmpty
    }

    func rcFiles() -> [URL] {
        return [".bash_profile", ".bash_login", ".bashrc"]
            .compactMap({ Utils.userHomeDirectory?.appendingPathComponent($0) })
    }

    func updateRcs() -> [URL] {
        return rcFiles().filter { $0.isFileURL }
    }
}

struct Zsh: UnixShell {
    static func zdotdir() throws -> URL {
        if let shell = Utils.env("SHELL"), shell.contains("zsh") {
            if let dir = Utils.env("ZDOTDIR"), !dir.isEmpty {
                return URL(fileURLWithPath: dir)
            } else {
                throw ShellError.zshSetupFailed
            }
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh") 
            process.arguments = ["-c", "'echo $ZDOTDIR'"]

            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                return URL(fileURLWithPath: output)
            } else {
                throw ShellError.zshSetupFailed
            }
        }
    }

    func doesExist() -> Bool {
        return Utils.env("SHELL")?.contains("zsh") == true || Utils.findCmd("zsh") != nil
    }

    func rcFiles() -> [URL] {
        return [try? Zsh.zdotdir(), Utils.userHomeDirectory]
            .compactMap { $0 }
            .map { $0.appendingPathComponent(".zshenv") }
    }

    func updateRcs() -> [URL] {
        let newRC = [Utils.userHomeDirectory?.appendingPathComponent(".zshenv")].compactMap { $0 }
        return rcFiles().filter { $0.isFileURL } + newRC
    }
}

public struct ShellScript {
    public let name: String
    public let content: String

    static var `default`: ShellScript {
        let fm = FileManager.default
        let current = FileManager.default.currentDirectoryPath
        let path = current + "/Sources/Shell/env.sh"
        guard let data = fm.contents(atPath: path) else {
            #warning("better error handling")
            fatalError()
        }
        let content = String(data: data, encoding: .utf8)!
        return ShellScript(name: "env", content: content)
    } 
}

enum ShellError: Error {
    case zshSetupFailed
}

enum Utils {
    static var userHomeDirectory: URL? {
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var swiftlyHomeDirectory: String {
        #warning("what is the current? are we going to change it since we're using this env script?")
        fatalError()
    }

    static func findCmd(_ cmd: String) -> URL? {
        return env("PATH")?
            .components(separatedBy: ":")
            .first(where: { $0.split(separator: "/").last?.elementsEqual(cmd) == true })
            .map { URL(fileURLWithPath: $0) }
    }

    static func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }
}