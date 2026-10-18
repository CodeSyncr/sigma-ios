Pod::Spec.new do |s|
  s.name         = "NimbusSigma"
  s.version      = "1.0.0"
  s.summary      = "Sigma spreadsheets from Nimbus Cloud, editable inside your iOS app."
  s.description  = <<-DESC
    The Sigma spreadsheet editor in SwiftUI and UIKit: open a sheet from a signed link your
    server mints, edit it with formulas, formatting and charts, and get the .xlsx or CSV back.
    Changes save to Nimbus Cloud as people type.
  DESC
  s.homepage     = "https://github.com/CodeSyncr/sigma-ios"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = "CodeSyncr"
  s.source       = { :git => "https://github.com/CodeSyncr/sigma-ios.git", :tag => s.version.to_s }

  s.ios.deployment_target = "15.0"
  s.osx.deployment_target = "12.0"
  s.swift_versions = ["5.10"]

  s.source_files = "Sources/NimbusSigma/**/*.swift"
  s.frameworks = "WebKit", "SwiftUI"
end
