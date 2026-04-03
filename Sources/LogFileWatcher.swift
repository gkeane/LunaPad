import Foundation

/// Watches a file for writes using kqueue (DispatchSource) and calls onChange on the main queue.
final class LogFileWatcher {
    private var source: DispatchSourceFileSystemObject?

    init?(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        src.setEventHandler(handler: onChange)
        src.setCancelHandler { close(fd) }
        src.resume()
        self.source = src
    }

    deinit {
        source?.cancel()
    }
}
