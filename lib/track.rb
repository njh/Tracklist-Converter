class Track < Doodle
  has :catalogue_number, :default => nil
  has :record_label, :default => nil
  has :release_title, :default => nil
  has :track_number, :default => nil
  has :track_title

  has :start_time, :default => nil
  has :duration, :default => nil

  # Contributors
  has :arranger, :default => nil
  has :choir, :default => nil
  has :composer, :default => nil
  has :conductor, :default => nil
  has :director, :default => nil
  has :ensemble, :default => nil
  has :orchestra, :default => nil
  has :performer, :default => nil
  
  # FIXME: must have at least one performer or composer

  # Less used
  has :bbc_music_code, :default => nil
  has :publisher, :default => nil
  has :synopsis, :default => nil

end
