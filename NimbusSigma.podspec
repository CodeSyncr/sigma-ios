Pod::Spec.new do |s|
  s.name         = "NimbusSigma"
  s.version      = "2.1.0"
  s.summary      = "Sigma spreadsheets from Nimbus Cloud, edited natively inside your iOS app."
  s.description  = <<-DESC
    A native spreadsheet editor for iOS: Sigma's own engine (formulas, formats, charts) running
    in JavaScriptCore, with a UIKit grid, a SwiftUI format bar, Swift Charts and Vani AI. Opens
    a sheet from a signed link your server mints and saves every change back to Nimbus Cloud.
  DESC
  s.homepage     = "https://github.com/CodeSyncr/sigma-ios"
  s.license      = { :type => "Commercial", :file => "LICENSE" }
  s.author       = "CodeSyncr"
  s.source       = { :git => "https://github.com/CodeSyncr/sigma-ios.git", :tag => s.version.to_s }

  s.ios.deployment_target = "16.0"
  s.osx.deployment_target = "13.0"
  s.swift_versions = ["5.10"]

  s.source_files = "Sources/NimbusSigma/**/*.swift"
  s.frameworks = "SwiftUI", "JavaScriptCore", "Charts"
end
