import StrategyContent

enum StrategyContentMetadata {
    static let developmentDisclosure = "开发演示数据"
    static let modelAuthoredDisclosure = "非求解器产出，已人工审核"
    static let unverifiedDisclosure = "未经策略审核"
    static let retiredDisclosure = "已停用内容"
    static let unknownProvenanceDisclosure = "内容来源未知"
    static let reviewedContentAvailableDisclosure = "已安装已审核策略内容"
    static let reviewedContentUnavailableDisclosure = "未安装已审核策略内容"

    /// Disclosure is a function of the review status.
    ///
    /// This used to compare against the development pack's ID, which
    /// distinguished anything only while exactly one kind of unreviewed content
    /// existed. With a second kind shipping, an ID comparison would leave
    /// `unverifiedDraft` content unlabelled — the single outcome the status was
    /// introduced to prevent.
    static func disclosure(
        forReviewStatus reviewStatus: ReviewStatus,
        origin: ContentOrigin
    ) -> String? {
        // Origin is checked before review status. A human sign-off says someone
        // looked; it does not say the numbers came from a solver, and
        // implicit-contracts.md constrains where strategy truth originates.
        // Letting `reviewed` return nil put model-authored frequencies on
        // screen with no provenance at all -- a weaker disclosure than the
        // unverified path, which at least says nobody checked.
        if origin == .generativeModel {
            return modelAuthoredDisclosure
        }

        return switch reviewStatus {
        case .testFixture: developmentDisclosure
        case .unverifiedDraft: unverifiedDisclosure
        case .retired: retiredDisclosure
        case .reviewed: nil
        }
    }
}

enum StrategyContentAvailability: Equatable {
    case developmentFixtureAvailable
    case unverifiedContentAvailable
    /// Reviewed by a human, but authored by a model rather than solved.
    case modelAuthoredContentAvailable
    case reviewedContentAvailable
    case reviewedContentUnavailable

    var canStartTraining: Bool {
        switch self {
        case .developmentFixtureAvailable,
             .unverifiedContentAvailable,
             .modelAuthoredContentAvailable,
             .reviewedContentAvailable:
            true
        case .reviewedContentUnavailable:
            false
        }
    }

    var disclosureText: String {
        switch self {
        case .developmentFixtureAvailable:
            StrategyContentMetadata.developmentDisclosure
        case .unverifiedContentAvailable:
            StrategyContentMetadata.unverifiedDisclosure
        case .modelAuthoredContentAvailable:
            StrategyContentMetadata.modelAuthoredDisclosure
        case .reviewedContentAvailable:
            StrategyContentMetadata.reviewedContentAvailableDisclosure
        case .reviewedContentUnavailable:
            StrategyContentMetadata.reviewedContentUnavailableDisclosure
        }
    }
}
