#!/usr/bin/ruby

require 'track'
require 'tracklist'

class TracklistConverter < Sinatra::Base
  set :public_folder, File.dirname(__FILE__) + '/public'

  helpers do
    include Rack::Utils
    alias_method :h, :escape_html

    def link_to(title, url=nil, attr={})
      url = title if url.nil?
      attr.merge!('href' => url.to_s)
      attr_str = attr.keys.map {|k| "#{h k}=\"#{h attr[k]}\""}.join(' ')
      "<a #{attr_str}>#{h title}</a>"
    end

    def nl2p(text)
      paragraphs = text.to_s.split(/[\n\r]+/)
      paragraphs.map {|para| "<p>#{para}</p>"}.join
    end
  end

  get '/' do
    headers 'Cache-Control' => 'public,max-age=3600'
    erb :index
  end

  post '/process' do
    @tracks = Tracklist::Format::SimpleText.parse( params['text'] )
    @output = Tracklist::Format::FieldedText.export( @tracks )
    erb :output
  end

end
