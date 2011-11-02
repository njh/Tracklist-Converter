module Tracklist::Format::FieldedText

  def self.export_track(track)
    text = ''
    track.doodle.key_values.each do |key,value|
      unless value.nil? or value.empty?
        text += "#{key}: #{value}\n";
      end
    end
    return text
  end

  def self.export(tracks)
    text = ''
    tracks.each do |track|
      text += self.export_track(track) + "\n"
    end
    return text
  end
  
end