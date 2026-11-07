import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var store = NightStore()
    @State private var access = LifetimeAccess()
    @State private var tab = "roster"

    var body: some View {
        Group {
            if !store.loaded {
                ContentUnavailableView("Opening local records", systemImage: "internaldrive",
                    description: Text("Your roster and pay settings stay on this device."))
            } else if store.recoveryRequired {
                RecoveryView()
            } else if !store.data.preferences.onboardingComplete {
                WelcomeView()
            } else {
                TabView(selection: $tab) {
                    Tab(value: "roster") { NavigationStack { ConfirmView() } } label: {
                        Label("Roster", systemImage: "checklist")
                    }
                    Tab(value: "estimate") { NavigationStack { EstimateView() } } label: {
                        Label("Estimate", systemImage: "banknote")
                    }
                    Tab(value: "compare") { NavigationStack { CompareView() } } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                    Tab(value: "settings") { NavigationStack { SettingsView() } } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .environment(store)
        .environment(access)
        .task { await access.observe() }
        .tint(NightTheme.accent)
        .task { store.load(context) }
        .alert("Couldn't complete that change", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

#Preview {
    ContentView().modelContainer(for: [NightSnapshot.self], inMemory: true)
}
