import SeasonBiteKit
import SwiftUI

struct RootView: View {
    @State private var result: Result<MealPlan, Error>?

    var body: some View {
        NavigationStack {
            switch result {
            case .success(let plan):
                TodayView(plan: plan)
            case .failure(let error):
                ContentUnavailableView(
                    "Couldn't load today's meal",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            case nil:
                ProgressView()
            }
        }
        .task {
            result = Result { try MealPlanLoader.loadSample() }
        }
    }
}
