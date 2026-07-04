import SwiftUI

@main
struct RightMenuApp: App {
    var body: some Scene {
        MenuBarExtra("RightMenu", systemImage: "contextualmenu.and.cursorarrow") {
            Button("Open Settings") {
                // Settings UI will be added with the Xcode app target.
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

