import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage: Int = 0
    private let pages = OnboardingPage.all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("dropTo")
                    .font(.title3.bold())
                    .foregroundStyle(.blue)

                Spacer()

                if pages[currentPage].showsSkip {
                    Button("Skip", action: completeOnboarding)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 10) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color(.systemGray2) : Color(.systemGray5))
                        .frame(width: index == currentPage ? 28 : 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            .padding(.top, 10)

            Button {
                if currentPage < pages.count - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    completeOnboarding()
                }
            } label: {
                Text(pages[currentPage].buttonTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .frame(minWidth: 170)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(Color(.systemBackground))
    }

    private func completeOnboarding() {
        onComplete()
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 390)
                .padding(.horizontal, 20)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 12) {
                Text(page.title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            Spacer(minLength: 12)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
