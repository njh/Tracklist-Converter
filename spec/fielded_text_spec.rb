require File.dirname(__FILE__) + "/spec_helper.rb"
require 'tracklist'

describe Tracklist::Format::FieldedText do
  it "should allow you to store and retrieve the track title" do
    track = Track.new(
      :performer => 'Performer',
      :track_title => 'Title'
    )

    expect(Tracklist::Format::FieldedText.export_track(track)).to eq(
      "track_title: Title\n"+
      "performer: Performer\n"
    )
  end
end
