enum StrategyContentMetadata {
    static let developmentFixturePackID = "cash-6max-100bb-dev"
    static let developmentDisclosure = "开发演示数据"
    static let reviewedContentAvailableDisclosure = "已安装已审核策略内容"
    static let reviewedContentUnavailableDisclosure = "未安装已审核策略内容"

    static func disclosure(forStrategyPackID strategyPackID: String)
        -> String?
    {
        strategyPackID == developmentFixturePackID
            ? developmentDisclosure
            : nil
    }
}

enum StrategyContentAvailability: Equatable {
    case developmentFixtureAvailable
    case reviewedContentAvailable
    case reviewedContentUnavailable

    var canStartTraining: Bool {
        switch self {
        case .developmentFixtureAvailable, .reviewedContentAvailable:
            true
        case .reviewedContentUnavailable:
            false
        }
    }

    var disclosureText: String {
        switch self {
        case .developmentFixtureAvailable:
            StrategyContentMetadata.developmentDisclosure
        case .reviewedContentAvailable:
            StrategyContentMetadata.reviewedContentAvailableDisclosure
        case .reviewedContentUnavailable:
            StrategyContentMetadata.reviewedContentUnavailableDisclosure
        }
    }
}
