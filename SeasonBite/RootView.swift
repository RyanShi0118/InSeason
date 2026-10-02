import SeasonBiteKit
import SwiftUI

struct RootView: View {
    @State private var store = MealStore()

    var body: some View {
        NavigationStack {
            if let plan = store.plan {
                TodayView(plan: plan)
            } else {
                ContentUnavailableView(
                    "Couldn't load today's meal",
                    systemImage: "exclamationmark.triangle",
                    description: Text(store.errorMessage ?? "")
                )
            }
        }
        .environment(store)
    }
}
