# Native layer of rotide.dm on macOS: windows (one Flutter engine each), the shell material, the menu bar, the Dock,
# the application icon, the web view of the preview, panels, printing and PDF.
Pod::Spec.new do |s|
  s.name             = 'rotide_native'
  s.version          = '0.1.0'
  s.summary          = 'Native layer of rotide.dm on macOS.'
  s.homepage         = 'https://github.com/workedErnesto'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'rotide.dm' => 'rotide.dm' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.frameworks       = 'AppKit', 'WebKit', 'UniformTypeIdentifiers'
  s.platform         = :osx, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.9'
end
