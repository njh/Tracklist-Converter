module SegmentBatch

class SegmentBatchLine
  TOKEN_SIMILARITY_THRESHOLD = 0.55
  ATTRIBUTES = {
    :speech => ['speech'],
    :feature_title => ['feature title'],
    :artist => [
      'artist','performed by','performer','composer','contributor','arranger','soloist',
      'conductor','ensemble','organ','orchestra','lyrics','lyricist','vocals','words',
      'music','words/music','tune','director','director of music','choir', 
    ],
    :catalogue_number => ['catalogue number','catalog number','cat','catalogue no','prefix'],
    :record_label => ['record label','label'],
    :music_code => ['music_code'],
    :publisher => ['publisher'],
    :release_title => ['release title','release','album','album title','cd'],
    :offset => ['offset'],
    :synopsis => ['synopsis','details','notes'],
    :duration => ['track duration','duration'],
    :track_number => ['track number','track','tracks','track numbers','track no'],
    :track_title => ['track title','title','name'],
    :ignore_and_error_on => ['start time'],
  }
  
  has_no_table
  column :data, :string
  column :field, :string
  column :token, :string
  column :line_number, :integer
  
  attr_accessor :status
  attr_accessor :message
  
  def self.identify_token(token)
    return nil if token.blank?
    
    # check for a perfect match without expensive string comparisons
    query = token.downcase.gsub(' ','_').to_sym
    return query if ATTRIBUTES.has_key? query
    
    query = token.downcase
    field, score = nil, 0
    ATTRIBUTES.keys.each do |key|
      similarity = ATTRIBUTES[key].map { |s| query.similarity(s) }.max
      field, score = key, similarity if similarity > score
    end
    score > TOKEN_SIMILARITY_THRESHOLD ? field : nil
  end
  
  def self.fix_title_case(string)
    (string==string.upcase) ? string.titleize.gsub(/(\w)?Bbc(\w)?/, "#{$1}BBC#{$2}").gsub(/'[A-z]/) { |m| m.downcase } : string
  end
  
  def initialize(attributes = {})
    super
    
    self.field = field.to_sym unless (field.blank? or field.kind_of? Symbol)
    self.field = SegmentBatchLine.identify_token(token) if (field.nil? or ATTRIBUTES[field].nil?)

    if field and field != :ignore_and_error_on
      # was the field matched perfectly or did we guess?
      self.status = ATTRIBUTES[field].include?(token.downcase) ? :ok : :warning
      
      if (field == :artist or field == :track_title or field == :release_title)
        self.data = $1 if data =~ /^["`'‘](.*?)["`'’]$/
        self.data = SegmentBatchLine.fix_title_case(data)
      end
    else
      self.status = :error
    end
  end
  
  def token_symbol
    token.blank? ? nil : token.downcase.gsub(' ','_').to_sym
  end
  
  def to_s
    token_or_field = token.blank? ? field : token
    token_or_field.blank? ? data : "#{token_or_field.to_s.titleize}: #{data}"
  end
end

class SegmentBatchEntry
  has_no_table
  column :position
  column :version_pid
  has_many :lines, :class_name => 'SegmentBatchLine'
  
  def self.factory(attributes)
    if (attributes[:lines].find { |l| l.field == :speech })
      SpeechSegmentBatchEntry.new(attributes)
    else
      MusicSegmentBatchEntry.new(attributes)
    end
  end
  
  def line_attributes=(line_attributes)
    line_attributes.each do |attributes|
      lines.build(attributes)
    end
  end
  
  def to_segment_event
    Pips3::SegmentEvent.new(to_segment_event_hash)
  end
  
  def to_s
    lines.join("\n")
  end
  
  def to_hash(ignore_invalid=false)
    attributes = {}
    lines.each { |l| attributes[l.field] ||= l.data unless (l.field.nil? or l.status==:invalid) }
    attributes
  end
  
  def feature_title
    feature_title = lines.detect { |l| l.field == :feature_title }
    feature_title.data if feature_title
  end
  
  
  def music_code_data
    music_code_data = lines.detect { |l| l.field == :music_code }
    music_code_data.data if music_code_data
  end
  
  def artist_lines
    lines.select { |l| l.field == :artist }
  end
  
  def synopsis_lines
    lines.select { |l| l.field == :synopsis }
  end
  
  def visible_lines  
    lines.select { |l| (l.field != :artist and l.field != :feature_title) }
  end
  
  def hidden_lines  
    lines.select { |l| l.field == :feature_title }
  end
end

class SpeechSegmentBatchEntry < SegmentBatch::SegmentBatchEntry
  def to_segment_event_hash(ignore_invalid=false)
    attributes = to_hash(ignore_invalid)
    HashWithIndifferentAccess.new(
      :title => attributes[:feature_title],
      :offset => attributes[:offset],
      :version_pid => version_pid,
      :segment_attributes=>{
        :duration => attributes[:duration],
        :short_synopsis => attributes[:speech],
        :title => attributes[:track_title],
        :pit_segment_attributes=>{
          :type => 'SpeechSegment',
        },
      }
    )
  end
  
  def segment_type
    'speech'
  end
end

class MusicSegmentBatchEntry < SegmentBatch::SegmentBatchEntry
  column :primary_artist_index
  
  def initialize(attributes = {})
    super
    self.primary_artist_index ||= 0
  end
  
  validates_presence_of :artist, :message => "No primary artist defined (required)"
  validates_presence_of :track_title, :message => "No track defined (required)"
  
  def validate
    begin
      segment_event = to_segment_event
      segment_event.valid?
      if segment_event.errors.on(:offset)
        offset = lines.detect { |l| l.field == :offset }
        offset.status = :invalid
        offset.message = "Offset #{segment_event.errors.on(:offset)}"
      end
    
      if segment_event.segment.errors.on(:duration)
        duration = lines.detect { |l| l.field == :duration }
        duration.status = :invalid
        duration.message = "Duration #{segment_event.segment.errors.on(:duration)}"
      end

      if (synopsis and synopsis.size > 2000)
        synopsis_lines.each { |line| line.status = :exceeds_content_length }
      end
    rescue ArgumentError => e
      if e.kind_of?(Pips3::OffsetArgumentError)
        offset = lines.detect { |l| l.field == :offset }
        unless offset.nil?
          offset.status = :invalid
          offset.message = e.message
        end
      end

      if e.kind_of?(Pips3::DurationArgumentError)
        duration = lines.detect { |l| l.field == :duration }
        unless duration.nil?
          duration.status = :invalid
          duration.message = e.message
        end
      end
    end
  end
  
  def artist_details
    additional_artist_lines = (artist_lines - [artist_lines[primary_artist_index.to_i]])
    details = additional_artist_lines.map { |line| line.to_s }
    details.empty? ? nil : details.join("\n")
  end
  
  def music_code_id
    if music_code_data.nil?
      return nil
    else
      music_code = ProgrammeInfo::MusicCode.find_by_code(music_code_data)
      if music_code.blank?
        return nil
      else
        return music_code.music_code_id
      end
    end
  end
  
  def segment_type
    'music'
  end
  
  def synopsis
    strings = ([artist_details] + synopsis_lines.map { |l| l.data }).compact
    strings.empty? ? nil : strings.join("\n")
  end
  
  def track_title
    to_hash[:track_title]
  end
  
  def artist
    artist_line = artist_lines[primary_artist_index.to_i]
    artist_line.nil? ? nil : artist_line.data
  end
  
  def to_segment_event_hash(ignore_invalid=false)
    attributes = to_hash(ignore_invalid)
    HashWithIndifferentAccess.new(
      :title => attributes[:feature_title],
      :offset => attributes[:offset],
      :version_pid => version_pid,
      :segment_attributes=>{
        :duration => attributes[:duration],
        :long_synopsis => synopsis,
        :pit_segment_attributes=>{
          :type => 'MusicSegment',
          :track_title => attributes[:track_title],
          :publisher => attributes[:publisher],
          :record_label => attributes[:record_label],
          :release_title => attributes[:release_title],
          :track_number => attributes[:track_number],
          :catalogue_number => attributes[:catalogue_number],
          :music_code_id => music_code_id,
          :primary_contributor_attributes =>{
            :name => artist,
          }
        },
      }
    )
  end
end

class SegmentBatch
  has_no_table
  column :version_pid
  has_many :entries, :class_name => 'SegmentBatchEntry'
  
  def validate
    errors.add(:text, "no entries submitted") if entries.empty?
    errors.add(:text, "too many entries submitted (maximum is 50)") if @too_many_entries
    errors.add(:text_file, "must be in a plain text format") if @file_type_error
  end
  
  # FIXME: entries are always validated for some reason
  def valid_ignoring_entries?
    valid?
    error_attributes = []
    errors.each { |a, m| error_attributes << a }
    ((errors.on(:entries) and error_attributes.uniq.size==1) or errors.empty?)
  end
  
  attr_accessor :text
  def text=(text)
    @text = text
    parse(text)
  end
  
  attr_accessor :text_file
  def text_file=(file_data)
    if file_data.nil? || file_data.size == 0
      string = nil
    elsif file_data.is_a?(StringIO)
      file_data.rewind
      string = file_data.read
    elsif (file_data.content_type == 'text/plain')
      string = file_data.open { |f| f.read }
    else
      @file_type_error = true
    end
    self.text = string
  end
  
  def version_pid=(version_pid)
    super
    entries.each { |e| e.version_pid = version_pid }
  end
  
  def entry_attributes=(entry_attributes)
    entry_attributes.sort { |a,b| a.first.to_i <=> b.first.to_i }.each do |stuff|
      position, attributes = stuff
      if (attributes[:line_attributes].find{ |l| l[:field] == 'speech' })
        entries << SpeechSegmentBatchEntry.new(attributes.merge(:position => position))
      else
        entries << MusicSegmentBatchEntry.new(attributes.merge(:position => position))
      end
    end
  end
  
  def error_legend
    valid?
    error_fields = []
    entries.each do |entry| 
      error_fields << :multiple_artists if (entry.artist_lines.size > 1)
      error_fields << (entry.lines.map { |l| l.status }.uniq)
    end
    (error_fields.flatten.uniq - [:ok, :error]).sort
  end
  
  def to_segment_events
    entries.map do |entry|
      entry.valid? ? entry.to_segment_event : nil
    end.compact
  end
  
  def to_segment_event_hashes
    entries.map do |entry|
      entry.valid? ? entry.to_segment_event_hash(true) : nil
    end.compact
  end
  
  def parse(text)
    entries.clear
    return if text.blank?
    
    # determine whether input is simple (line per track) or fielded
    field_separator_count = text.gsub(/\d+:\d+:?(\d+)?/,'').split(/:/).size - 1
    line_numbers = text.split("\n").size
    average = field_separator_count / line_numbers.to_f
    
    if (text=~/^Single programme export from \w+ system/)
      parse_proteus(text)
    elsif (average < 0.5)
      parse_simple(text)
    else
      parse_fielded(text)
    end
  end
  
  protected
  
  def parse_simple(text)
    entry = MusicSegmentBatchEntry.new(:version_pid => version_pid, :position => entries.to_a.size+1)
    current_feature = nil
    text.split(/\n/).each do |line|
      break if too_many_entries_reached?
      line.strip!
      
      if line.empty?
        current_feature = nil
        next
      end
      
      if line =~ /^=(.*)=$/
        current_feature = $1
      elsif line =~ /^(\d{1,2}[:.]\d{1,2}[:.]?(\d{1,2})?\s+)?(.*) [–-] (.*) ?\((.*?)\)$/
        offset, artist, track_title, record_label = $1, $3, $4.strip, $5
      elsif line =~ /^(\d{1,2}[:.]\d{1,2}[:.]?(\d{1,2})?\s+)?(.*) [–-] (.*)$/
        offset, artist, track_title = $1, $3, $4
      end
      
      lines = []
      if (artist and track_title)
        lines << SegmentBatchLine.new(:token => 'feature title', :data => current_feature) unless current_feature.nil?
        lines << SegmentBatchLine.new(:token => 'artist', :data => artist)
        lines << SegmentBatchLine.new(:token => 'track title', :data => track_title)
        lines << SegmentBatchLine.new(:token => 'offset', :data => offset.strip) unless offset.nil?
        lines << SegmentBatchLine.new(:token => 'record label', :data => record_label) unless record_label.nil?
      elsif line !~ /^=(.*)=$/ # not a feature title
        lines << SegmentBatchLine.new(:token => 'feature title', :data => current_feature) unless current_feature.nil?
        lines << SegmentBatchLine.new(:token => 'speech', :data => line)
      end
      entries << SegmentBatchEntry.factory(:position => entries.to_a.size+1, :version_pid => version_pid, :lines => lines) if lines.any?
    end
  end
  
  def parse_proteus(text)
    text.split(/\n/).each do |line|
      line.strip!
      next if line.empty?
      next if line =~ /\d+:\d+ \w+ +Week: \d+ \d+ Status:/
      
      array = line.split(/\s{2,}/)
      if (array.size > 1)
        track_title, artist, release_title, record_label = array
        lines = []
        lines << SegmentBatchLine.new(:token => 'artist', :data => artist)
        lines << SegmentBatchLine.new(:token => 'track title', :data => track_title)
        lines << SegmentBatchLine.new(:token => 'release title', :data => release_title) unless release_title.nil?
        lines << SegmentBatchLine.new(:token => 'record label', :data => record_label) unless record_label.nil?
        entries << SegmentBatchEntry.factory(:position => entries.to_a.size+1, :version_pid => version_pid, :lines => lines) if lines.any?
      end
    end
  end
  
  def parse_fielded(text)
    linenumber = -1
    
    lines = []
    text.split(/\n/).each do |line|
      break if too_many_entries_reached?
      line = line.strip
      linenumber += 1
      if line.any?
        # We expect lines in the form "field: data", so we split on the colon
        token, data = line.split(/:/, 2).map{ |value| value.strip }
        if data.nil?
          # It's possible the user may have forgotten the colon, so the line is in the form "field data"
          # As a recovery mechanism, we split on the first whitespace, and see if we get a recognisable token
          token, data = line.split(/\s/, 2).map{ |value| value.strip }
          token, data = nil, line.strip if SegmentBatchLine.identify_token(token).nil?
        end
        lines << SegmentBatchLine.new(:line_number => linenumber, :token => token, :data => data)
      elsif lines.any?
        entries << SegmentBatchEntry.factory(:position => entries.to_a.size+1, :version_pid => version_pid, :lines => lines)
        lines = []
      end
      break if entries.size >= 50
    end
    entries << SegmentBatchEntry.factory(:position => entries.to_a.size+1, :version_pid => version_pid, :lines => lines) if lines.any?
  end
  
  def too_many_entries_reached?
    @too_many_entries = entries.size >= 50
  end
  
end
end
