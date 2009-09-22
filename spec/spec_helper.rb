ENV['RACK_ENV'] = 'test'

require File.expand_path(File.join(File.dirname(__FILE__), "..", "init"))

require "spec"
require "webrat"
require "rack/test"

Webrat.configure { |config| config.mode = :sinatra }

module Bithug
  module TestMethods

    def app
      Bithug::Routes
    end

    def logged_in
      user, password = "user", "password"
      app.auth_agent.register user, password
      basic_auth user, password
    end

  end
end

Spec::Runner.configure do |conf|
  conf.include Webrat::Methods
  conf.include Rack::Test::Methods
  conf.include Bithug::TestMethods
end
