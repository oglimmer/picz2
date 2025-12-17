import Foundation

// MARK: - App Configuration

enum AppConfiguration {
    private static let isProduction = true
    private static let productionBaseURL = "https://picz2.oglimmer.com"
    private static let developmentBaseURL = "http://192.168.178.118:8080"

    static var baseURL: String {
        isProduction ? productionBaseURL : developmentBaseURL
    }

    static var apiBaseURL: URL {
        URL(string: baseURL)!
    }

    static var uploadEndpoint: String {
        "\(baseURL)/api/upload"
    }
}
