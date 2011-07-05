$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'emailyak'

spec = Gem::Specification.new do |s|
  s.name = 'emailyak'
  s.version = EmailYak.version
  s.summary = 'Ruby bindings for the EmailYak API'
  s.description = 'Enable your app to send and receive email'
  s.author = 'Greg Brockman'
  s.email = 'gdb@gregbrockman.com'
  s.homepage = 'https://github.com/gdb/emailyak-ruby'
  s.require_paths = %w{lib}

  s.add_dependency('json')
  s.add_dependency('rest-client')

  s.files = %w{
    lib/emailyak.rb
    lib/data/ca-certificates.crt
  }
end
