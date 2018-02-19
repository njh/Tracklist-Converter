require File.dirname(__FILE__) + "/spec_helper.rb"
require 'track'

describe Track do
  let(:track) {
    Track.new(:performer => 'Jamie XX', :track_title => 'Loud Places')
  }

  it "should allow you to retrieve track_title" do
    expect(track.track_title).to eq('Loud Places')
  end

  it "should allow you to retrieve the performer" do
    expect(track.performer).to eq('Jamie XX')
  end

  it "should allow you to change the track_title" do
    track.track_title = 'The Rest Is Noise'
    expect(track.track_title).to eq('The Rest Is Noise')
  end
end
