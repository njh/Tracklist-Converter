$:.unshift(File.join(File.dirname(__FILE__),'..','lib'))

require 'rubygems'
require 'bundler'

Bundler.require(:default, :test)

unless RUBY_VERSION =~ /^1\.8/
  SimpleCov.start
end

RSpec.configure do |config|
  config.mock_framework = :mocha
end

def fixture(filename)
  File.join(File.dirname(__FILE__),'fixtures',filename)
end

def fixture_data(filename)
  File.read(fixture(filename))
end
