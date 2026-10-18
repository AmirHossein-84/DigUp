import Foundation
#if os(Windows)
import WinSDK
#endif

/// The commands an app runs as its helpers (`index-service`, `worker`, `search-service`, `download-model`,
/// `estimate --json`) end when the app does. They stop when their stdin closes, but only between jobs, and `estimate`
/// reads no stdin at all: after a quit, a force quit or a crash, one could go on walking folders or sit in a file for
/// minutes with no one listening. On a Mac the kernel says when the parent exits; on Linux it's checked every second
/// (`prctl` can't be called from Swift); on Windows, a background thread waits on the parent process handle.
///
/// It exits with `_exit`, as a kill would: there's no one to report to, and a job cut short is simply done again
/// (SQLite keeps the index whole; the next helper clears the scratch folder).
enum ParentWatch {
    #if os(macOS)
    nonisolated(unsafe) private static var source: DispatchSourceProcess?
    #endif

    static func start(parentPid: Int32? = nil) {
        #if os(macOS)
        let parent = parentPid ?? getppid()
        guard parent > 1 else { _exit(0) }   // launchd took it in: the app is gone already
        if parentPid != nil, getppid() != parent { _exit(0) }   // parent exited before helper started
        let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit,
                                                      queue: .global(qos: .userInitiated))
        source.setEventHandler { _exit(0) }
        source.resume()
        self.source = source
        if parentPid != nil, getppid() != parent { _exit(0) }   // cover the gap
        #elseif os(Linux)
        let parent = parentPid ?? getppid()
        guard parent > 1 else { _exit(0) }
        Thread.detachNewThread {
            while (parentPid == nil ? getppid() == parent : kill(parent, 0) == 0) {
                Thread.sleep(forTimeInterval: 1)
            }
            _exit(0)
        }
        #elseif os(Windows)
        let targetPid = parentPid.map(DWORD.init) ?? parentProcessId()
        guard let pid = targetPid, pid > 1 else { return }
        guard let handle = OpenProcess(DWORD(SYNCHRONIZE), false, pid), handle != INVALID_HANDLE_VALUE else {
            _exit(0)
        }
        let handleValue = UInt(bitPattern: handle)
        Thread.detachNewThread {
            guard let handle = HANDLE(bitPattern: handleValue) else { _exit(0) }
            defer { CloseHandle(handle) }
            WaitForSingleObject(handle, INFINITE)
            _exit(0)
        }
        #endif
    }

    #if os(Windows)
    private static func parentProcessId() -> DWORD? {
        let currentPid = GetCurrentProcessId()
        let snapshot = CreateToolhelp32Snapshot(DWORD(TH32CS_SNAPPROCESS), 0)
        guard let snapshot, snapshot != INVALID_HANDLE_VALUE else { return nil }
        defer { CloseHandle(snapshot) }
        var entry = PROCESSENTRY32W()
        entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
        guard Process32FirstW(snapshot, &entry) else { return nil }
        repeat {
            if entry.th32ProcessID == currentPid {
                return entry.th32ParentProcessID
            }
        } while Process32NextW(snapshot, &entry)
        return nil
    }
    #endif
}
