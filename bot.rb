#!/usr/bin/ruby
#
# Author: Adam Laycock
# Published: May 2, 2012
#
# TODO:
#	- Refactor this like crazy, this is super ugly code. Break functions down, make new files.
#	- Remove unnecessary dependancies. ruby_reddit_api has only one use and I could do without it.
#

require 'json'
require 'ruby_reddit_api'
require 'chronic'
require 'parseconfig'
require 'net/http'
require 'uri'
require 'yaml'
require './markdown-calendar.rb'

config = ParseConfig.new('serverInfo.conf')

description_data = ""
File.open('description.conf').each_line{ |s|
	description_data << s
}

description_before = description_data.match(/\*\*\*HEADER_START\*\*\*(.*)\*\*\*HEADER_END\*\*\*/mx)[1]
description_after = description_data.match(/\*\*\*FOOTER_START\*\*\*(.*)\*\*\*FOOTER_END\*\*\*/mx)[1]

# Stats information for output/logging
post_limit = config.get_value('post_limit').to_i

#For the final statistics
parse_successful = 0
parse_failure = 0
invalid_title = 0
user_info_message = 0
link_generated = 0
run_again = false

# The number of days ahead of time before the post is in the past (if it's May, and a post was made for April, it will show up
# as April next year, so if the post is more than X days in the future, assume it's actually for the past).
days_before_actually_past = 180

#Open the file of previous events
file = File.open("eventList.yaml", "rb")
previousEvents = file.read

@invalidEvents = []

reddit = Reddit::Api.new
posts = reddit.browse(config.get_value('subreddit_name'), { :limit => post_limit })

class Event
	attr_reader :name, :location, :timeString, :time, :title, :link
	attr_writer :name, :location, :timeString, :time, :title, :link
	
	def initialize(_name, _location, _timeString, _postTitle, _link)
		@name = _name
		@location = _location
		@timeString = _timeString
		@title = _postTitle
		@link = _link
		
		cleanTimeString
		
		@time = Chronic.parse(@timeString)
	end
	
	def cleanTimeString
		@timeString = @timeString.gsub(/\,/, "")
		@timeString = @timeString.gsub(/ to .*/, "")
		@timeString = @timeString.gsub(/ (un)?til.*/, "")
		@timeString = @timeString.gsub(/\-.*/, "")
		@timeString = @timeString.gsub(/\@/, " at ")
	end
end

def parseTitle(rawPost) 
	parsedTitle = rawPost.title.match(/(?:\A\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?\[([^\[\]]*)\]\s?[^\[\]]*\z)/).to_a
	if parsedTitle != []
		return Event.new(
						parsedTitle[1],
						parsedTitle[3] + ' at ' + parsedTitle[4],
						parsedTitle[2],
						rawPost.title,
						rawPost.url)
	end
	return false
end


@events = YAML::load(previousEvents)
if !@events
	@events = {}
end

# For each post in the subreddit...
posts.each { |post|
	eventData = parseTitle(post)
	
	if eventData
	
		begin

			if eventData.time.nil? == false
				if(Date.today + days_before_actually_past < eventData.time.to_date)
					eventData.time = Date.parse(Chronic.parse(eventData.timeString, :context => :past).to_s)
				end
				date = eventData.time.to_date
				
				# Find out if the event exists yet
				exists = false
				@events.each { |day|
				
					puts "\n\n" + day.to_s
					day[1].each { |event|
					
						puts "\n\n" + event.to_s
						if(event.title == eventData.title)
							exists = true
						end
					}
				}
				
#				# Hit up the google API to get shortened URLs
#				if(@events[date].nil? || !exists )
#					uri = URI.parse('https://www.googleapis.com/urlshortener/v1/url?key=AIzaSyCPe8jm5qxaNhIvFAWjojE-gqZRdLvb9mQ')
#					http = Net::HTTP.new(uri.host, uri.port)
#					http.use_ssl = true
#					http.verify_mode = OpenSSL::SSL::VERIFY_NONE
#					req = Net::HTTP::Post.new(uri.path)
#					req["Content-Type"] = "application/json"
#					req.body = {"longUrl" => eventData.link, "key" => "AIzaSyCPe8jm5qxaNhIvFAWjojE-gqZRdLvb9mQ"}.to_json
#					res = http.request(req)
#					eventData.link = JSON.parse(res.body)["id"]
#					link_generated += 1
#				end

				if(eventData.link != nil)
					if (!exists)
						@events[date] = [] if @events[date].nil?
						@events[date].push eventData
					end
					parse_successful += 1
				else
					run_again = true
					puts "WARNING: Event could not be added because a shortened URL could not be generated. Please run the script again."
				end
			else
				parse_failure += 1
				print "WARNING: Bad parse on -- " + post.title + "\n"
				@invalidEvents.push post.id
			end
			rescue ArgumentError
				puts "Error occurred on " + post.title + ", continuing"
			end
		else
			invalid_title += 1
			title = post.title.match(/.*\[(.*)\].*/).to_a
		if title.length > 0
			print "WARNING: Bad title on -- " + post.title + "\n"
			@invalidEvents.push post.id
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
			dateString = event.time.to_time
			description_string << '* [' + date_formatted + ' - ' + event.name + ' @ ' + event.location + ' @ ' + event.time.strftime('%l:%M %p') + '](' + event.link + ")\n"
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

# Update the subreddit description
uri = URI('http://www.reddit.com/api/site_admin')
req = Net::HTTP::Post.new(uri.path)
req['cookie'] = "reddit_session= " + session

req.set_form_data(
		'api_type' => 'json',
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
end
