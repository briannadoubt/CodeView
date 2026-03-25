#if os(macOS)
import CodeViewDemoSupport
import SwiftUI

@main
struct CodeViewDemoMacOSApp: App {
    var body: some Scene {
        WindowGroup("CodeView Demo") {
            DemoDiffSurface()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowResizability(.contentSize)
    }
}
#endif
