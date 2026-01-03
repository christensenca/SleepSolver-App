//
//  AppConfiguration.swift
//  SleepSolver
//
//  Created by GitHub Copilot
//

import Foundation

struct AppConfiguration {
    // MARK: - Legal Documents
    
    /// Terms of Service URL - Update this single location to change across the entire app
    static let termsOfServiceURL = "https://sleepsolver.io/terms-of-service"
    
    /// Privacy Policy URL - Update this single location to change across the entire app
    static let privacyPolicyURL = "https://sleepsolver.io/privacy-policy"
    
    // MARK: - App Information
    
    /// App version from bundle
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    /// Build number from bundle
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    /// Full version string combining version and build
    static var fullVersionString: String {
        "\(appVersion) (\(buildNumber))"
    }
}
