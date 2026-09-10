import SwiftUI

// Remaining placeholder destination (Categories editor arrives in a later pass).

struct CategoriesView: View {
    var body: some View {
        ContentUnavailableView("Categories", systemImage: "tag",
                               description: Text("Full category management arrives soon. Starter categories are seeded and editable from Review."))
            .navigationTitle("Categories")
    }
}
