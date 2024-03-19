#
# Be sure to run `pod lib lint GADUtil.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'GADUtil'
  s.version          = '1.0.4'
  s.summary          = 'Google admobile Util'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
  Google admobile Util
                       DESC

  s.homepage         = 'https://github.com/yj9294/GADUtil'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Nico' => 'nicoyang.mason@gmail.com' }
  s.source           = { :git => 'https://github.com/yj9294/GADUtil.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '15.0'

  s.source_files = 'GADUtil/Classes/**/*'
  
  # s.resource_bundles = {
  #   'GADUtil' => ['GADUtil/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
   s.frameworks = 'UIKit', 'MapKit'
   s.dependency 'Google-Mobile-Ads-SDK'
   s.static_framework = true
end
