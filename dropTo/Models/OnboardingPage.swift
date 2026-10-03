import Foundation

struct OnboardingPage: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let showsSkip: Bool
}

extension OnboardingPage {
    static let all: [OnboardingPage] = [
        OnboardingPage(
            imageName: "onboarding-illustration-1",
            title: "Your important photos\ndeserve a place.",
            subtitle: "Slides, whiteboards, and notes shouldn't get buried in your camera roll.",
            buttonTitle: "Continue",
            showsSkip: true
        ),
        OnboardingPage(
            imageName: "onboarding-illustration-2",
            title: "Create the album first.",
            subtitle: "Take photos from inside an album, and they'll go exactly where they belong, no sorting later.",
            buttonTitle: "Continue",
            showsSkip: true
        ),
        OnboardingPage(
            imageName: "onboarding-illustration-3",
            title: "Turn dates in photos\ninto Calendar events.",
            subtitle: "Tap a detected date, review the details, then add it to your Calendar.",
            buttonTitle: "Create your first album",
            showsSkip: false
        )
    ]
}
