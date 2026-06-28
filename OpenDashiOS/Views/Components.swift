import SwiftUI

enum OpenDashTheme {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.05)
    static let surface = Color(red: 0.09, green: 0.10, blue: 0.10)
    static let elevated = Color(red: 0.13, green: 0.14, blue: 0.13)
    static let gold = Color(red: 0.95, green: 0.65, blue: 0.24)
    static let green = Color(red: 0.27, green: 0.78, blue: 0.50)
    static let red = Color(red: 0.93, green: 0.34, blue: 0.30)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let textMuted = Color.white.opacity(0.42)
}

struct ScreenTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(OpenDashTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(OpenDashTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OpenDashCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OpenDashTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(OpenDashTheme.textMuted)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(OpenDashTheme.textPrimary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(OpenDashTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenDashTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.black)
        .background(OpenDashTheme.gold)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SecondaryButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(OpenDashTheme.textPrimary)
        .background(OpenDashTheme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EmptyState: View {
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(OpenDashTheme.gold)
            Text(title)
                .font(.headline)
                .foregroundStyle(OpenDashTheme.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(OpenDashTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func openDashScreenBackground() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OpenDashTheme.background.ignoresSafeArea())
    }
}

extension Double {
    var currencyText: String {
        formatted(.currency(code: "INR"))
    }
}
