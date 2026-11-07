import SwiftUI

struct WelcomeView: View {
    @Environment(NightStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var preferences = PayPreferences()
    @State private var configuring = false

    var body: some View {
        NavigationStack {
            NightPage {
                if configuring {
                    Text("Your pay cycle").font(.largeTitle.bold())
                    Text("Choose the first day of a biweekly pay period. You can adjust these settings later.")
                        .foregroundStyle(.secondary)
                    NightSection {
                        Text("Week starts").font(.subheadline.weight(.semibold))
                        Picker("Week starts", selection: $preferences.weekAnchorMonday) {
                            Text("Monday").tag(true)
                            Text("Sunday").tag(false)
                        }.pickerStyle(.segmented)
                        Divider()
                        LabeledContent("Time zone") {
                            Picker("Time zone", selection: $preferences.timeZoneID) {
                                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { id in
                                    Text(id.replacingOccurrences(of: "_", with: " ")).tag(id)
                                }
                            }.labelsHidden()
                        }
                        DatePicker("Period starts", selection: $preferences.periodAnchor, displayedComponents: .date)
                            .environment(\.timeZone, TimeZone(identifier: preferences.timeZoneID) ?? .current)
                    }
                    NightSection("Check your pay rules") {
                        Text("This estimate uses biweekly USD pay, Saturday/Sunday premiums, and weekly overtime after 40 hours at 1.5× base. Daily overtime, holiday rates, bonuses and blended overtime rates are outside this estimate.")
                    }
                } else {
                    HStack { Spacer(); NightOwl(height: 186); Spacer() }
                        .padding(.vertical, 24)
                        .background(NightTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 28))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Check your\nnight shift pay.").font(.largeTitle.bold())
                        Text("Estimate your gross pay from your roster, then compare it with your payslip.")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    Label("Your shifts and rates stay on this device.", systemImage: "lock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if configuring {
                        preferences.onboardingComplete = true
                        store.update {
                            $0.preferences = preferences
                            $0.rates.weekStartsOn = preferences.weekAnchorMonday ? 2 : 1
                        }
                    } else { configuring = true }
                } label: {
                    Label(configuring ? "Open my roster" : "Set up pay cycle", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                }.buttonStyle(NightPrimaryButton())
                    .accessibilityIdentifier(configuring ? "startCheck" : "onboardingContinue")
                    .padding().frame(maxWidth: 600).background(NightTheme.canvas(scheme))
            }
            .navigationTitle("NightPayCheck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if configuring {
                    ToolbarItem(placement: .topBarLeading) { Button("Back") { configuring = false } }
                }
            }
        }.onAppear { preferences = store.data.preferences }
    }
}
