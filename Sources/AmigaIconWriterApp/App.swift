#if os(macOS)
import SwiftUI

@main
struct AmigaIconWriterApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: IconProjectDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
#else
// AmigaIconWriterApp is a macOS/SwiftUI target. On other platforms (e.g. Linux
// CI building the whole package) provide a trivial entry point so the target
// still has a `main`. Use the `amigaicon` CLI or AmigaIconKit directly there.
@main struct AmigaIconWriterApp {
    static func main() {
        print("AmigaIconWriterApp requires macOS. Use the `amigaicon` CLI on this platform.")
    }
}
#endif
