import SwiftUI

struct JoinServerView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            List {
                ForEach(state.runtimes) { runtime in
                    NavigationLink(value: runtime.id) {
                        ServerRow(runtime: runtime)
                    }
                }
            }
            .overlay {
                if state.runtimes.isEmpty {
                    ContentUnavailableView(
                        "No Servers",
                        systemImage: "network.slash",
                        description: Text("Add a Sanctuary-compatible server in the Launcher tab.")
                    )
                }
            }
            .navigationTitle("Join Server")
            .navigationDestination(for: UUID.self) { id in
                if let runtime = state.runtime(with: id) {
                    ServerDetailView(runtime: runtime)
                }
            }
        }
    }
}
