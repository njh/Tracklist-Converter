module Tracklist::Format::SimpleText

  def self.parse(text)
    tracks = []
    current_feature = nil
  
    text.split(/\n/).each do |line|
      ##break if too_many_entries_reached?
      line.strip!
      
      next if line =~ /^#/
      
      if line.empty? or line == '=END='
        current_feature = nil
        next
      elsif line =~ /^=(.*)=$/
        current_feature = $1
        next
      elsif line =~ /^(\d{1,2}[:.]\d{1,2}[:.]?(\d{1,2})?\s+)?(.*) [–-] (.*) ?\((.*?)\)$/
        tracks << Track.new(
          :start_time => $1,
          :performer => $3,
          :track_title => $4.strip,
          :record_label => $5
        )
      elsif line =~ /^(\d{1,2}[:.]\d{1,2}[:.]?(\d{1,2})?\s+)?(.*) [–-] (.*)$/
        tracks << Track.new(
          :start_time => $1,
          :performer => $3,
          :track_title => $4
        )
      end
    end
    
    return tracks
  end
  
  
  def self.export(tracks)
    text = ''
    tracks.each do |track|
      text += "#{track.performer} - #{track.track_title}\n"
    end
    text
  end
end