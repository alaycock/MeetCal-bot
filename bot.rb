#!/usr/bin/ruby

# Forked from Spenser Jones' original reddit bot, but with improved parsing and an automated updating system.
# Plus, he took his version down, so I guess this replaces it. 
#
# Author: Adam Laycock
# Published: May 2, 2012
#

require 'open-uri'
require 'json'
require 'ruby_reddit_api'
require 'chronic'
require 'parseconfig'
require 'net/http'
require 'uri'
require 'yaml'
require './markdown-calendar.rb'

# Get the configuration for the server authentication and request
config = ParseConfig.new('serverInfo.conf')
config.get_value('server_id')

# Get the header and footer to put before and after the calendar
description_file = ""
File.open('description.conf').each_line{ |s|
  description_file << s
}
description_before = description_file.match(/\*\*\*HEADER_START\*\*\*(.*)\*\*\*HEADER_END\*\*\*/mx)[1]
description_after = description_file.match(/\*\*\*FOOTER_START\*\*\*(.*)\*\*\*FOOTER_END\*\*\*/mx)[1]
bad_title_message = description_file.match(/\*\*\*HARASS_MESSAGE_START\*\*\*(.*)\*\*\*HARASS_MESSAGE_END\*\*\*/mx)[1]

@tentative = []
@invalids = []

# Stats information for output/logging
post_limit = config.get_value('post_limit').to_i
parse_successful = 0
parse_failure = 0
invalid_title = 0
title_format_1 = 0
title_format_2 = 0
title_format_3 = 0
user_info_message = 0
link_generated = 0
run_again = false

# The number of days ahead of time before the post is in the past (if it's May, and a post was made for April, it will show up
# as April next year, so if the post is more than X days in the future, assume it's actually for the past)
days_before_actually_past = 180

#Open the file of previous events
file = File.open("eventList.yaml", "rb")
previousEvents = file.read

@events = YAML::load(previousEvents)
#@events = {}

reddit = Reddit::Api.new
posts = reddit.browse(config.get_value('subreddit_name'), { :limit => post_limit })

# For each post in the subreddit...
posts.each { |post|
  # Parse the format of the input data
  link = post.url

  # You should pretty much kill yourself before you try to understand this.
  # It parses for [event][location][date][time] OR [event][location][date & time] OR [event][date & time] and captures the info from them.
  # I would have loved to use /\A(?:\[([^\[\]]*)\]\s?){2,4}[^\[\]]*\z/, but apparently you can't capture while identifying repetition ({2,4} part)
  title = post.title.match(/(?:(?:\A\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?[^\[\]]*\z)|(?:\A\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?[^\[\]]*\z)|(?:\A\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?[^\[\]]*\z))/).to_a

  # Identify which title it is
  if title[1] != nil
    title_format_1 += 1
    eventName = title[1]
    timeString = title[3] + ' at ' + title[4]
    locationString = title[2]
  elsif title[5] != nil
    title_format_2 += 1
    eventName = title[5]
    timeString = title[7]
    locationString = title[6]
  elsif title[8] != nil
    title_format_3 += 1
    eventName = title[8]
    timeString = title[9]
    locationString = "tentative"
  end

  if title.length > 0

    begin

    # Fix some of the formatting that commonly occurs
    timeString = timeString.gsub(/\,/, "")
    timeString = timeString.gsub(/\-/, " at ")
    timeString = timeString.gsub(/\@/, " at ")

    eventTime = Chronic.parse(timeString)
    if eventTime.nil? == false
      if(Date.today + days_before_actually_past < eventTime.to_date)
        eventTime = Date.parse(Chronic.parse(timeString, :context => :past).to_s)	
      end
      date = eventTime.to_date
      
      # Find out if the event exists yet
      exists = false
      @events.each { |day|
        day[1].each { |event|
          if(event[5] == post.title)
            exists = true
          end
        }
      }
      # Hit up the google API to get shortened URLs
      if(@events[date].nil? || !exists )
        uri = URI.parse('https://www.googleapis.com/urlshortener/v1/url?key=AIzaSyCPe8jm5qxaNhIvFAWjojE-gqZRdLvb9mQ')
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        req = Net::HTTP::Post.new(uri.path)
        req["Content-Type"] = "application/json"
        req.body = {"longUrl" => link, "key" => "AIzaSyCPe8jm5qxaNhIvFAWjojE-gqZRdLvb9mQ"}.to_json
        res = http.request(req)
        link = JSON.parse(res.body)["id"]
        link_generated += 1
      end
      event = [eventName, locationString, timeString, eventTime, link, post.title]

      if(link != nil)
        @events[date] = [] if @events[date].nil?
        if (!exists)
          @events[date].push event
	end
        parse_successful += 1
      else
        run_again = true
        puts "WARNING: Event could not be added because a shortened URL could not be generated. Please run the script again."
      end
    else
      parse_failure += 1
      print "WARNING: Bad parse on -- " + post.title + "\n"
      @invalids.push post.id
    end
    rescue ArgumentError
      puts "Error occurred on " + post.title + ", continuing"
    end
  else
    invalid_title += 1
    title = post.title.match(/.*\[(.*)\].*/).to_a
    if title.length > 0
      print "WARNING: Bad title on -- " + post.title + "\n"
      @invalids.push post.id
    end
  end
}

@events = Hash[@events.sort]
File.open('eventList.yaml', 'w') {|f| f.write(YAML::dump(@events)) }

description_string = description_before + "\n\n"

# Generate calendar
cal = MarkdownCalendar.new(@events)
description_string << cal.render

# Generate upcoming events
description_string << "\n\n## Upcoming Events\n\n"
@events.each { |date|
  date_formatted = date[0].strftime('%b %d')
  date[1].each { |event|
    if date[0] >= Date.today
      dateString = event[3].to_time
      if event[1] == "tentative"
        description_string << '* [' + date_formatted + ' - ' + event[0] + ' @ ' + event[3].strftime('%l:%M%p') + '](' + event[4] + ")\n"
      else
        description_string << '* [' + date_formatted + ' - ' + event[0] + ' @ ' + event[1] + ' @ ' + event[3].strftime('%l:%M %p') + '](' + event[4] + ")\n"
      end
    end
  }
}
description_string << "\n\n" + description_after

# Log in to CSC_bot
uri = URI('http://www.reddit.com/api/login/' + config.get_value('bot_username'))
req = Net::HTTP::Post.new(uri.path)
req.set_form_data('api_type' => 'json', 'user' => config.get_value('bot_username'), 'passwd' => config.get_value('bot_password'))

res = Net::HTTP.start(uri.hostname, uri.port) do |http|
  http.request(req)
end

# Identify errors
body = JSON.parse(res.body)["json"]
if (body["errors"] == [])
  session = body["data"]["cookie"]
  modhash = body["data"]["modhash"]
else
  puts "FATAL ERROR: Could not login"
end

=begin
# Harass the ingrates who try to title things thing, but do it wrong
@invalids.each{ |link|
  shortID = link.match(/.._(.*)/)[1]

  # Get all the comments for each malformed title's post
  uri = URI('http://www.reddit.com/comments/' + shortID + '.json')
  req = Net::HTTP::Get.new(uri.path)
  res = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(req)
  end

  # If the url is bad, check if CSC_bot has already posted a comment in the thread (uses a regex to match it's own username)
  # not the most robust way, but there hasn't been any issues.
  if(res.body.match(/.*#{ config.get_value('bot_username') }.*/).to_a.length == 0)

    # If it hasn't post a comment telling them that the post has a bad title
    uri = URI('http://www.reddit.com/api/comment/')
    req = Net::HTTP::Post.new(uri.path)
    req['cookie'] = "reddit_session= " + session
    req.set_form_data('api_type' => 'json', 'parent' => link, 'text' => bad_title_message, 'uh' => modhash)

    res = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end
    body = JSON.parse(res.body)["json"]

    # This operation might make Reddit mad at you on the first run. Lots of comments will be hit, and reddit doesn't like lots of requests at once.
    if (body["errors"] != [])
      print "FATAL ERROR: Posting comment and: " + body["errors"].to_s
    else
      user_info_message += 1
    end
  end
}
=end



# Update the subreddit description
uri = URI('http://www.reddit.com/api/site_admin')
req = Net::HTTP::Post.new(uri.path)
req['cookie'] = "reddit_session= " + session
req.set_form_data('api_type' => 'json',
		'allow_top' => config.get_value('allow_top'),
		'css_on_cname' => config.get_value('css_on_cname'),
		'description' => description_string,
		'header_title' => config.get_value('header_title'),	
		'lang' => config.get_value('language'),
		'link_type' => config.get_value('link_type'),
		'name' => config.get_value('subbreddit_name'),
		'over_18' => config.get_value('over_18'),
		'show_cname_sidebar' => config.get_value('show_cname_sidebar'),
		'show_media' => config.get_value('show_media'),
		'sr' => config.get_value('subreddit_thing'),
		'title' => config.get_value('page_title'),
		'type' => config.get_value('subreddit_privacy'),
		'domain' => config.get_value('domain'),
		'wikimode' => config.get_value('wikimode'),
		'uh' => modhash)

res = Net::HTTP.start(uri.hostname, uri.port) do |http|
  http.request(req)
end

# Generate report
body = JSON.parse(res.body)["json"]
if (body["errors"] != [])
  print "\n\nFATAL ERROR: " + body["errors"].to_s
elsif (run_again)
  print "\n\nWARNING: Calendar was generated, but not all events could be added, please run the script again\n"
else
  print "\n\nNo errors occured\n"
  print parse_successful.to_s + "/" + post_limit.to_s + " posts were successfully added to the calendar\n"
  print parse_failure.to_s + " posts failed to parse (see warnings above)\n"
  print invalid_title.to_s + " posts had a title that could not be parsed\n\n"
  print user_info_message.to_s + " messages were sent to users because of an invalid title\n"
  print link_generated.to_s + " shortened links were generated\n\n"
  print title_format_1.to_s + " posts had the format [EVENT][LOCATION][DATE][TIME]\n"
  print title_format_2.to_s + " posts had the format [EVENT][LOCATION][DATE & TIME]\n"
  print title_format_3.to_s + " posts had the format [EVENT][DATE & TIME]\n"
end
