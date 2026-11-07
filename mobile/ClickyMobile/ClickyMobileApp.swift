import SwiftUI

@main
struct ClickyMobileApp: App {
    var body: some Scene {
        WindowGroup {
            CompanionView()
                .preferredColorScheme(.dark)
        }
    }
}
