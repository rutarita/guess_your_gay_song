require "json"
require "colorize"

module GuessYourGaySong
  VERSION = "0.1.0"

  struct MusicData
    include JSON::Serializable

    FFPROBE_TAGS_OPTIONS     = {"-output_format", "json=c=1", "-show_entries", "stream_tags:format_tags"}
    FFPROBE_DURATION_OPTIONS = {"-output_format", "json=c=1", "-show_entries", "packet=duration_time"}
    property path : String
    property title : String
    property artist : String
    property album : String?
    property year : String?
    property genre : String?

    def initialize(@path : String, @title : String, @artist : String, @album : String? = nil, @year : String? = nil, @genre : String? = nil)
    end

    private def self.parse_date(date : String) : String
      splat = date.split('-')
      splat[0]
    end

    private def self.try_get(from : JSON::Any, key : String) : String?
      (from[key]? || from[key.downcase]? || from[key.upcase]? || from[key.titleize]?).try &.to_s
    end

    def self.from_file(path : String | Path)
      # @@ffprobe_options[-1] = path.to_s
      json = String.build do |io|
        # Process.run("ffprobe", @@ffprobe_options, output: io)
        Process.run("ffprobe", FFPROBE_TAGS_OPTIONS + {path.to_s}, output: io)
      end
      # io = IO::Memory.new
      parsed = JSON.parse json
      # puts parsed
      format_tags = parsed["format"]?
      if tags = format_tags && format_tags["tags"]?
        date_tag = try_get(tags, "date")
        time = parse_date date_tag if date_tag
        self.new(
          path.to_s,
          try_get(tags, "title") || raise("Impossible title"),
          try_get(tags, "artist") || raise("Impossible artist"),
          try_get(tags, "album"),
          time,
          try_get(tags, "genre")
        )
      elsif tags = parsed["streams"][0]["tags"]?
        date_tag = try_get(tags, "date")
        time = parse_date date_tag if date_tag
        self.new(
          path.to_s,
          try_get(tags, "title") || raise("Impossible title"),
          try_get(tags, "artist") || raise("Impossible artist"),
          try_get(tags, "album"),
          time,
          try_get(tags, "genre")
        )
      end
    end

    def to_s
      "#{@title} - #{@album} - #{@artist} [#{@year}] (#{@genre})"
    end

    def duration : Float64
      json = String.build do |io|
        Process.run("ffprobe", FFPROBE_DURATION_OPTIONS + {@path}, output: io)
      end
      parsed = JSON.parse(json)
      begin
        packets = parsed["packets"]
        first_packet = packets[0]["duration_time"]? ? packets[1] : packets[1]
        first_packet["duration_time"].to_s.to_f * packets.size + packets[-1]["duration_time"].to_s.to_f
      rescue
        puts packets.try &.[0]
        puts packets.try &.[1]
        puts packets.try &.[-1]
        exit 1
      end
    end

    def ==(other : MusicData) : Bool
      @title == other.title && @artist == other.@artist
    end

    def ==(other)
      false
    end

    VERSION_OF_TRACK_REGEX = /^((?:\(.*\))?[^(]*)(?: \((.*)\))?$/

    def base_track : String
      if data = VERSION_OF_TRACK_REGEX.match(@title)
        data[1]
      else
        raise "Incorrect track somehow or a bug"
      end
    end

    def same_base_track?(other : MusicData) : Bool
      @artist == other.artist && base_track.downcase == other.base_track.downcase
    end

    def matches?(title_sub : String, artist_sub : String? = nil, album_sub : String? = nil)
      count = 1 + (artist_sub ? 1 : 0) + (album_sub ? 1 : 0)
      count -= 1 if @title.downcase.includes?(title_sub.downcase)
      count -= 1 if artist_sub && @artist.downcase.includes?(artist_sub.downcase)
      count -= 1 if album_sub && @album.try &.downcase.includes?(album_sub.downcase)
      count == 0
    end
  end

  class MusicLibrary
    @list : Array(MusicData)
    @artist_index : Hash(String, Array(MusicData))

    getter list
    getter artist_index

    MUSIC_FILE_EXTENSIONS = {".opus", ".mp3", ".flac", ".ogg", ".m4a"}

    def initialize
      @list = [] of MusicData
      @artist_index = {} of String => Array(MusicData)
    end

    def self.is_music_file(name : String) : Bool
      MUSIC_FILE_EXTENSIONS.each do |ext|
        return true if name.ends_with? ext
      end
      false
    end

    def add_entry(entry : MusicData)
      artist = entry.artist
      @list << entry
      (@artist_index[artist] ||= [] of MusicData) << entry
    end

    # TODO: Make ts multithreaded concurrent idk to make it faster
    def scan_dir(path : String | Path)
      path = Path.new(path)
      Dir.each_child(path) do |child|
        child_path = path.join(child)
        if Dir.exists? child_path
          scan_dir child_path
        else
          if self.class.is_music_file child
            begin
              if entry = MusicData.from_file child_path
                add_entry entry
              else
                puts "Failed to parse #{child_path}"
              end
            rescue e
              puts "Error while parsing #{child_path}: #{e}"
            end
          end
        end
      end
    end

    def to_json(json)
      @artist_index.to_json(json)
    end

    def from_json(string_or_io : String | IO)
      json = JSON.parse(string_or_io)
      json.as_h.each_key do |artist|
        json[artist].as_a.each do |entry|
          add_entry(MusicData.from_json(entry.to_json))
        end
        # puts "Loaded #{artist}"
      end
    end

    def self.from_json(string_or_io : String | IO) : self
      library = self.new
      library.from_json string_or_io
      library
    end

    def filter_by_artists(artists : Enumerable(String)) : Array(MusicData)
      results = [] of MusicData
      artists.each do |artist|
        results.concat(@artist_index[artist])
      end
      results
    end
  end

  struct Record
    include JSON::Serializable
    include Comparable(Record)

    property score : Int32
    property seconds : Int64
    property date : Time

    def initialize(@score : Int32, time : Time::Span, @date : Time)
      @seconds = time.total_seconds.to_i64
    end

    def <=>(other : Record)
      @score <=> other.score
    end

    def to_s
      local_date = date.to_local
      time = @seconds.seconds
      String.build do |io|
        io << score
        io << " in "
        if time.hours > 0
          io << time.hours.to_s(precision: 2)
          io << ':'
        end
        io << time.minutes.to_s(precision: 2)
        io << ':'
        io << time.seconds.to_s(precision: 2)
        io << " on "
        io << local_date.year.to_s(precision: 4)
        io << '-'
        io << local_date.month.to_s(precision: 2)
        io << '-'
        io << local_date.day.to_s(precision: 2)
        io << ' '
        io << local_date.hour.to_s(precision: 2)
        io << ':'
        io << local_date.minute.to_s(precision: 2)
        io << ':'
        io << local_date.second.to_s(precision: 2)
      end
    end

    def to_s(io)
      io << to_s
    end
  end

  class Game
    CONFIG_DIR_NAME = "guess_your_gay_song"
    CONFIG_PATH     = {% if flag?(:win32) %}
                        Path[ENV["LOCALAPPDATA"]] / CONFIG_DIR_NAME
                      {% else %}
                        if env_conf = ENV["XDG_CONFIG_HOME"]?
                          Path[env_conf] / CONFIG_DIR_NAME
                        else
                          Path.home / Path[".config", CONFIG_DIR_NAME]
                        end
                      {% end %}
    INDEX_PATH      = CONFIG_PATH / "index.json"
    SCOREBOARD_PATH = CONFIG_PATH / "scoreboard.json"

    TITLE          = "Guess Your Gay Song".colorize :cyan
    MENU_SELECTION = {
      "fp"   => "Free play with all tracks",
      "fpa"  => "Free play only with tracks from artist(s)",
      "sp"   => "Survival play with all artists",
      "spa"  => "Survival play with tracks from artist(s)",
      "scr"  => "Scoreboard",
      "rei!" => "Re-index all music (hella slow)",
      "op"   => "Options",
      "q"    => "Quit",
    }

    GAMEPLAY_SELECTION = {
      "p"    => "Play the sound again",
      "g"    => "Guess the track title",
      "h"    => "Get a hint",
      "r"    => "Choose another fragment",
      "rev!" => "Reveal the answer",
      "q!"   => "Quit to the main menu",
    }

    FFPLAY_OPTIONS = ["-autoexit", "-nodisp"]

    SCORED_ROUNDS = 10

    @library : MusicLibrary

    @scoreboard : Hash(String, Array(Record)) = {} of String => Array(Record)
    @scoreboard_all : Array(Record) = [] of Record
    # current gameplay variables
    @current_artists : Array(String) = [] of String
    @all_artists_mode : Bool = false
    @survival_mode : Bool = false
    @lives : Int32 = 0
    @score : Int32 = 0
    @wrong_guesses : Int32 = 0
    @guesses : Int32 = 0
    @reveals_used : Int32 = 0
    @hints_used : Int32 = 0
    @rerolls_used : Int32 = 0

    # game options
    @listen_length : Float64 = 2.0
    @amount_of_hints : Int32 = 3
    @start_score : Int32 = 0
    @start_lives : Int32 = 10
    @correct_guess_reward : Int32 = 500
    @hint_penalty : Int32 = -200
    @reroll_penalty : Int32 = -150
    @reveal_penalty : Int32 = -1000
    @wrong_guess_penalty : Int32 = -50

    def initialize
      @library = MusicLibrary.new
    end

    private def display_scoreboard_entries(entries : Array(Record))
      entries.each_with_index do |entry, i|
        puts "#{i + 1}: #{entry.to_s}"
      end
    end

    private def show_all_scoreboard : Void
      @scoreboard_all.sort!
      @scoreboard_all.each_with_index do |entry, i|
        puts "#{i + 1}: #{entry.to_s}"
      end
      print "Press enter to continue..."
      gets
    end

    private def show_artists_scoreboard : Void
      choices = {} of String => String
      @scoreboard.each_key do |key|
        choices[key] = ""
      end
      choices["%exit"] = ""
      chosen_artist = prompt_player(choices, false, true)
      unless chosen_artist || chosen_artist == "%exit"
        puts "Okay then"
        return
      end
      puts "Top records for #{chosen_artist}:"
      display_scoreboard_entries @scoreboard[chosen_artist]
    end

    private def scoreboard_menu : Void
      puts "All(1) or specific artists(2)?"
      case gets.try &.downcase
      when "1", "all"
        show_all_scoreboard
      when "2", "artists", "artist"
        show_artists_scoreboard
      end
      print "Press Enter to continue..."
      gets
    end

    private def save_scoreboard
      path = Path.home.join(SCOREBOARD_PATH)
      Dir.mkdir_p(path.dirname)
      File.open(path, "w") do |f|
        {"all" => @scoreboard_all, "artists" => @scoreboard}.to_json(f)
      end
    end

    private def load_scoreboard
      begin
        json = JSON.parse(File.read(SCOREBOARD_PATH))
        @scoreboard_all = Array(Record).from_json(json["all"].to_json)
        @scoreboard = Hash(String, Array(Record)).from_json(json["artists"].to_json)
      rescue
        # don't do anything as its non critical
      end
    end

    private def add_new_record_all(record : Record)
      @scoreboard_all << record
      @scoreboard_all.sort!
      save_scoreboard
    end

    private def add_new_record_artist(artist : String, record : Record)
      (@scoreboard[artist] ||= [] of Record) << record
      @scoreboard[artist].sort!
      save_scoreboard
    end

    private def prompt_player_multi_choice(options : Hash(String, String), exact_match : Bool = true, no_values : Bool = false, multi : Bool = true) : Array(String)
      prompt = String.build do |io|
        idx = 1
        options.each_key do |key|
          io << idx
          io << ". "
          io << key
          unless no_values
            io << ": "
            io << options[key]
          end
          io << '\n'
          idx += 1
        end
      end
      puts prompt
      print "Enter 1-#{options.size} or a key#{"(s) separated by '|'" if multi}: "
      chosen_keys = [] of String
      if input = gets
        input.split('|').each do |query|
          if idx = /^[1-9][0-9]*$/.match(query) && query.to_i
            if choice = options.keys[idx - 1]?
              chosen_keys << choice
            end
          else
            query = query.downcase
            options.keys.each do |key|
              chosen_keys << key if exact_match ? key.downcase == query : key.downcase.includes?(query)
            end
            chosen_keys
          end
        end
      end
      chosen_keys
    end

    private def prompt_player(options : Hash(String, String), exact_match : Bool = true, no_values : Bool = false) : String?
      prompt_player_multi_choice(options, exact_match, no_values, false)[0]?
    end

    def load_index
      elapsed_time = Time.measure do
        begin
          File.open(INDEX_PATH) do |f|
            @library.from_json(f)
          end
        rescue e
          puts "No index file found! Please create one by selecting 'rei' option in main menu!".colorize :red
          return
        end
      end
      finished_in = elapsed_time.total_seconds.to_s
      puts "Finished loading in #{finished_in[0..(finished_in.index!('.') + 2)]} seconds"
    end

    def create_index
      print "Enter path to directory to index: "
      path = gets
      unless path
        puts "Okay, then"
        return
      end
      path = Path[path]
      unless Dir.exists?(path)
        raise "#{path} is not a directory or doesn't exist!"
      end
      @library.list.clear
      @library.artist_index.clear
      @library.scan_dir(path)
      Dir.mkdir_p(INDEX_PATH.dirname)
      File.open(INDEX_PATH, "w") do |f|
        @library.to_json(f)
      end
    end

    def start_game
      load_index
      load_scoreboard
      game_loop
    end

    def game_loop
      loop do
        menu
      end
    end

    private def reset_gameplay_values
      @lives = @start_lives
      @score = @start_score
      @wrong_guesses = 0
      @guesses = 0
      @reveals_used = 0
      @hints_used = 0
      @rerolls_used = 0
    end

    private def game_over(gameplay_time : Time::Span)
      puts
      puts "Game Over!".colorize :red
      current_gameplay_stats
      if @all_artists_mode
        print "Would you like to add it as a record for all artists? (y/n): "
        if gets == "y"
          record = Record.new(
            @score,
            gameplay_time,
            Time.utc
          )
          add_new_record_all record
        else
          puts "Okay then"
        end
      else
        @current_artists.sort!
        scoreboard_entry = String.build do |io|
          @current_artists[0...-1].each do |artist|
            io << artist
            io << '|'
          end
          io << @current_artists[-1]
        end
        print "Would you like to add it as a record for #{scoreboard_entry}? (y/n): "
        if gets == "y"
          record = Record.new(
            @score,
            gameplay_time,
            Time.utc
          )
          add_new_record_artist scoreboard_entry, record
        else
          puts "Okay then"
        end
      end
    end

    private def menu
      puts TITLE
      puts "Version #{VERSION}"
      answer = prompt_player(MENU_SELECTION)
      return unless answer
      keys = MENU_SELECTION.keys
      case answer
      when keys[0]
        @all_artists_mode = true
        @survival_mode = false
        reset_gameplay_values
        while play(@library.list)
        end
      when keys[1]
        @all_artists_mode = false
        @survival_mode = false
        chosen_artists = choose_artists avaliable_artists
        reset_gameplay_values
        while play(
                @library.filter_by_artists(chosen_artists)
              )
        end
      when keys[2]
        # all artists survival
        @all_artists_mode = true
        @survival_mode = true
        reset_gameplay_values
        elapsed_time = Time.measure do
          SCORED_ROUNDS.times { break unless play(@library.list) }
        end
        game_over elapsed_time
      when keys[3]
        # artists survival
        @all_artists_mode = false
        @survival_mode = true
        @current_artists = choose_artists avaliable_artists
        reset_gameplay_values
        selected_music = @library.filter_by_artists(@current_artists)
        elapsed_time = Time.measure do
          SCORED_ROUNDS.times { break unless play(selected_music) }
        end
        game_over elapsed_time
      when keys[4]
        scoreboard_menu
      when keys[5]
        create_index
      when keys[6]
        puts "Options!"
      when keys[7]
        exit 0
      end
    end

    private def avaliable_artists
      @library.artist_index.keys
    end

    private def choose_artists(from : Array(String), finish_command : String = "begin") : Array(String)
      options = {} of String => String
      chosen_artists = [] of String
      from.each do |key|
        options[key] = ""
      end
      finish_command = "%#{finish_command}"
      options[finish_command] = ""
      options["%clear"] = ""
      options["%list"] = ""
      loop do
        loop do
          answer = prompt_player_multi_choice(options, false, true)
          if answer.size <= 1 && answer[0][0] == '%'
            case answer[0]
            when finish_command
              break
            when "%list"
              puts "Chosen artists:".colorize :green
              chosen_artists.each do |artist|
                puts artist
              end
              print "Press Enter to continue..."
              gets
            end
          else
            answer.each do |artist|
              chosen_artists << artist if artist && !chosen_artists.includes?(artist)
            end
          end
        end
        puts "Chosen artists:".colorize :green
        chosen_artists.each do |artist|
          puts artist
        end
        print "Are you sure you want to start playing with these artists? (y/n): "
        return chosen_artists if gets == "y"
      end
    end

    private def generate_ffplay_options(path : String, start_seek : Float64, duration : Float64) : Array(String)
      options = FFPLAY_OPTIONS.clone
      options << "-ss"
      options << start_seek.to_s
      options << "-t"
      options << duration.to_s
      options << path
      options
    end

    HINT_TYPES = [:year, :first_letter, :artist, :album, :genre, :length, :title_length]

    private def generate_hint(music_data : MusicData, t : Symbol) : String
      case t
      when :year
        "This song was released in #{music_data.year}"
      when :first_letter
        "First letter of this track is '#{music_data.title[0]}'"
      when :artist
        "This track was released by '#{music_data.artist}'"
      when :album
        "This song is a part of album titled '#{music_data.album}'"
      when :genre
        "This track has following genre(s): #{music_data.genre}"
      when :length
        "Length of this track is #{music_data.duration.seconds}"
      when :title_length
        "Length of title of this track is #{music_data.title.size}"
      else
        raise "Invalid symbol used, this is a bug"
      end
    end

    private def generate_hints(music_data : MusicData) : Array(String)
      hints = [] of String
      available = HINT_TYPES.shuffle
      available.delete(:genre) unless music_data.genre
      available.delete(:year) unless music_data.year
      available.delete(:album) unless music_data.album
      music_data.album.try do |album|
        available.delete(:album) if album.downcase == music_data.title.downcase
      end
      Math.min(@amount_of_hints, available.size).times do
        hint = available.pop
        hints << generate_hint(music_data, hint)
      end
      hints
    end

    private def print_hints(hints : Array(String), amount : Int32)
      puts "Hints:".colorize(:yellow)
      puts "None currently, use 'h' option to reveal up to #{@amount_of_hints} hints." if amount == 0
      amount.times do |i|
        puts "#{i + 1}: #{hints[i]}"
      end
      puts
    end

    private def ffplay(options : Array(String))
      status = Process.run("ffplay", options)
      if status.exit_code != 0
        raise "ffplay exited with nonzero exit code. reason: #{status.exit_reason}"
      end
    end

    private def guess_title(right_song : MusicData, music_list : Array(MusicData)) : Bool
      print "Search query (syntax is title|artist|album, album and artist - optional including pipes)\n: "
      if answer = gets
        answer = answer.split('|')
        title_query = answer[0]
        artist_query = answer[1]?
        album_query = answer[2]?
        matching_songs = music_list.select do |entry|
          entry.matches?(title_query, artist_query, album_query)
        end
        if matching_songs.size == 0
          puts "No songs found!".colorize(:red)
          return false
        end
        matching_songs.each_with_index do |entry, i|
          puts "#{i + 1}. #{entry.title} - #{entry.artist}"
        end
        print "Enter index of the song you think is right: "
        begin
          if index = gets
            if matching_songs[index.to_i - 1].same_base_track?(right_song)
              return true
            else
              puts "Wrong guess!".colorize :red
              @wrong_guesses += 1
              @score += @wrong_guess_penalty
              @lives -= 1 if @survival_mode
            end
          end
        rescue
          puts "Invalid index"
        end
      end
      false
    end

    private def current_gameplay_stats(show_lives : Bool = true)
      puts "Lives left: #{@lives}/#{@start_lives}".colorize(:red) if @survival_mode & show_lives
      puts "Your score is: #{@score.colorize :blue}"
      puts "Correct guesses: #{@guesses.colorize :green}"
      puts "Wrong guesses: #{@wrong_guesses.colorize(@wrong_guesses == 0 ? :light_green : :yellow)}"
      puts "Hints used: #{@hints_used.colorize :cyan}"
      puts "Rerolls used: #{@rerolls_used.colorize :light_blue}"
      puts "Times answer revealed: #{@reveals_used.colorize(@reveals_used == 0 ? :light_magenta : :red)}"
    end

    # return false from this if player needs to return to menu
    def play(music_list : Array(MusicData))
      if music_list.empty?
        puts "What are you even supposed to listen to?"
        return
      end
      random_song = music_list[rand(0...music_list.size)]
      duration = random_song.duration
      random_start = rand(0.0..(duration - @listen_length))
      options = generate_ffplay_options(random_song.path, random_start, @listen_length)
      hints = generate_hints(random_song)
      revealed_hints = 0
      ffplay options
      loop do
        print_hints(hints, revealed_hints)
        puts "Score: #{@score.colorize :blue}"
        puts "Lives left: #{@lives}/#{@start_lives}".colorize(:red) if @survival_mode
        answer = prompt_player GAMEPLAY_SELECTION
        next unless answer
        keys = GAMEPLAY_SELECTION.keys
        case answer
        when "p"
          ffplay options
        when "g"
          if guess_title(random_song, music_list)
            @score += @correct_guess_reward
            @guesses += 1
            puts
            puts "Congratulations!".colorize :green
            puts "You guessed right!"
            puts "The song is #{random_song.title} by #{random_song.artist} from album #{random_song.album} released in #{random_song.year}"
            if @score < 0
              puts "You got damaged for 1 live for having negative score!".colorize :red
              @lives -= 1
              return false if @survival_mode && @lives <= 0
            end
            current_gameplay_stats
            print "Enter q if you want to quit to the menu or press enter to continue: "
            return gets != "q"
          end
        when "h"
          if revealed_hints < hints.size
            revealed_hints += 1
            @score += @hint_penalty
            @hints_used += 1
          else
            puts "Every hint has been revealed already!".colorize :red
          end
        when "r"
          random_start = rand(0.0..(duration - @listen_length))
          options = generate_ffplay_options(random_song.path, random_start, @listen_length)
          puts "New fragment chosen".colorize :blue
          @score += @reroll_penalty
          @rerolls_used += 1
          ffplay options
        when "rev!"
          if @survival_mode
            puts "No reveal allowed in survival mode!".colorize :red
          else
            @score += @reveal_penalty
            @reveals_used += 1
            puts "The song is #{random_song.title} by #{random_song.artist} from album #{random_song.album} released in #{random_song.year}"
            current_gameplay_stats
            print "Enter q if you want to quit to the menu or press enter to continue: "
            return gets != "q"
          end
        when "q!"
          return false
        end
        return false if @survival_mode && @lives <= 0
      end
    end
  end
end

