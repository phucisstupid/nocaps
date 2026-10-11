import Darwin
import Foundation

@discardableResult
func restartAppAfterExit(
    of processIdentifier: pid_t, bundleURL: URL,
    openerURL: URL = URL(fileURLWithPath: "/usr/bin/open")
) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
        "-c",
        """
        attempts=0
        while kill -0 "$1" 2>/dev/null; do
            [ "$attempts" -lt 100 ] || exit 1
            attempts=$((attempts + 1))
            /bin/sleep 0.1
        done
        exec "$2" -n "$3"
        """,
        "NoCaps restart", String(processIdentifier), openerURL.path, bundleURL.path,
    ]
    process.standardInput = FileHandle.nullDevice
    try process.run()
    return process
}
