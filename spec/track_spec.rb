require File.dirname(__FILE__) + "/spec_helper.rb"
require 'track'

describe Track do
  it "should allow you to store and retrieve the track title" do
    expect(Track.new(:track_title => 'foo').track_title).to eq('foo')
  end
end
