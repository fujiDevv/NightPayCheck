import SwiftUI

enum NightTheme {
    static let pageInset: CGFloat = 20
    static let cardInset: CGFloat = 20
    static let sectionGap: CGFloat = 24
    static let ink = Color(white: 0.07)
    static let paper = Color(white: 0.94)
    static let accent = Color(uiColor: .label)

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : Color(white: 0.965)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.12) : .white
    }
}

struct NightPage<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var maxWidth: CGFloat = 680
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 720 && !typeSize.isAccessibilitySize
            ScrollView {
                VStack(alignment: .leading, spacing: NightTheme.sectionGap) { content }
                    .padding(.horizontal, NightTheme.pageInset).padding(.top, 16).padding(.bottom, 32)
                    .frame(maxWidth: wide ? 900 : maxWidth).frame(maxWidth: .infinity)
            }
        }
        .background(NightTheme.canvas(scheme).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .tint(NightTheme.accent)
    }
}

struct NightSection<Content: View, Header: View, Footer: View>: View {
    @Environment(\.colorScheme) private var scheme
    var content: Content
    var header: Header
    var footer: Footer
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content(); self.header = header(); self.footer = footer()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header.font(.system(.subheadline, design: .default, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: .infinity, alignment: .leading).padding(NightTheme.cardInset)
                .background(NightTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.primary.opacity(0.045), lineWidth: 1) }
            footer.font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6)
        }
    }
}

extension NightSection where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) { self.init(content: content, header: { EmptyView() }, footer: { EmptyView() }) }
}
extension NightSection where Header == Text, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) { self.init(content: content, header: { Text(title) }, footer: { EmptyView() }) }
}
extension NightSection where Header == Text {
    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { Text(title) }, footer: footer)
    }
}

struct NightCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NightTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 22))
    }
}

func hoursText(_ minutes: Int) -> String {
    "\(minutes / 60)h \(minutes % 60)m"
}

struct NightOwl: View {
    let height: CGFloat

    var body: some View {
        Image(decorative: "NightOwl")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

struct NightPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .background(Color.primary, in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct NightPeriodPicker: View {
    @Environment(\.timeZone) private var timeZone
    @Binding var date: Date
    let period: DateInterval
    @State private var choosing = false

    private var periodLabel: String {
        let formatter = DateIntervalFormatter()
        formatter.timeZone = timeZone
        formatter.dateTemplate = "MMMdyyyy"
        return formatter.string(from: period.start, to: period.end.addingTimeInterval(-1))
    }

    var body: some View {
        Button { choosing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar").frame(width: 40, height: 40)
                    .background(.primary.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pay period").font(.caption).foregroundStyle(.secondary)
                    Text(periodLabel)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Image(systemName: "chevron.down").font(.caption.bold())
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $choosing) {
            NavigationStack {
                ScrollView {
                    DatePicker("Choose a date in the pay period", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                }
                .navigationTitle("Choose a pay period").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { choosing = false } }
            }.presentationDetents([.medium, .large])
        }
    }
}

struct NightSettingsGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(minHeight: 44)
        }
    }
}
