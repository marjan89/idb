import Foundation
import Darwin

/// Run a shell command and return (exitCode, stdout, stderr)
@discardableResult
func shell(_ command: String, timeout: TimeInterval = 30) -> (code: Int32, out: String, err: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        return (-1, "", error.localizedDescription)
    }

    // Enforce timeout — kill process if it exceeds the limit
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler {
        if process.isRunning {
            process.terminate()
            usleep(500_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    timer.resume()

    process.waitUntilExit()
    timer.cancel()

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

    let timedOut = process.terminationReason == .uncaughtSignal
    return (
        process.terminationStatus,
        String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        timedOut ? "Timed out after \(Int(timeout))s" :
            (String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    )
}

// MARK: - posix_spawn with POSIX_SPAWN_SETSID

/// Spawn a process in a new session (no controlling terminal).
/// `/dev/tty` is inaccessible to the child — `readpassphrase()` falls back to stderr/stdin.
/// Returns the child PID. Use `waitpid()` to collect exit status.
func spawnDetached(
    executable: String,
    arguments: [String],
    stdoutFd: Int32,
    stderrFd: Int32,
    stdinFd: Int32 = STDIN_FILENO
) throws -> pid_t {
    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }

    // POSIX_SPAWN_SETSID = 0x0400 on macOS — new session, no controlling tty
    var flags: Int16 = 0
    posix_spawnattr_getflags(&attr, &flags)
    flags |= Int16(0x0400)  // POSIX_SPAWN_SETSID
    posix_spawnattr_setflags(&attr, flags)

    var fileActions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }

    posix_spawn_file_actions_adddup2(&fileActions, stdinFd, STDIN_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, stdoutFd, STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, stderrFd, STDERR_FILENO)

    let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { argv.forEach { $0.map { free($0) } } }

    var pid: pid_t = 0
    let result = posix_spawn(&pid, executable, &fileActions, &attr, argv, environ)
    guard result == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(result))
    }
    return pid
}

/// Run a command in a detached session (no /dev/tty) and capture output.
/// Used for codesign tests where we need to prevent readpassphrase() from prompting.
@discardableResult
func shellDetached(_ command: String, timeout: TimeInterval = 10) -> (code: Int32, out: String, err: String) {
    let outPipe = Pipe()
    let errPipe = Pipe()
    let devNull = open("/dev/null", O_RDONLY)
    defer { if devNull >= 0 { close(devNull) } }

    let pid: pid_t
    do {
        pid = try spawnDetached(
            executable: "/bin/bash",
            arguments: ["-c", command],
            stdoutFd: outPipe.fileHandleForWriting.fileDescriptor,
            stderrFd: errPipe.fileHandleForWriting.fileDescriptor,
            stdinFd: devNull >= 0 ? devNull : STDIN_FILENO
        )
    } catch {
        return (-1, "", error.localizedDescription)
    }

    // Close write ends in parent so reads get EOF
    outPipe.fileHandleForWriting.closeFile()
    errPipe.fileHandleForWriting.closeFile()

    // Timeout via SIGKILL
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now() + timeout)
    var didTimeout = false
    timer.setEventHandler {
        didTimeout = true
        kill(pid, SIGKILL)
    }
    timer.resume()

    var status: Int32 = 0
    waitpid(pid, &status, 0)
    timer.cancel()

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

    let exitCode = (status & 0x7f) == 0 ? Int32((status >> 8) & 0xff) : -1
    return (
        exitCode,
        String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
        didTimeout ? "Timed out after \(Int(timeout))s" :
            (String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    )
}

/// Read a password from /dev/tty with echo disabled.
func readPassword(prompt: String) -> String? {
    guard let tty = fopen("/dev/tty", "r+") else { return nil }
    defer { fclose(tty) }

    let fd = fileno(tty)
    var orig = termios()
    tcgetattr(fd, &orig)

    var noEcho = orig
    noEcho.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(fd, TCSANOW, &noEcho)

    fputs(prompt, tty)

    var buf = [CChar](repeating: 0, count: 256)
    fgets(&buf, Int32(buf.count), tty)

    tcsetattr(fd, TCSANOW, &orig)
    fputs("\n", tty)

    let str = String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    return str.isEmpty ? nil : str
}
