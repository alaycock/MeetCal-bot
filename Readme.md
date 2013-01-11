#MeetupCal-bot#
##Intro##
This bot is for retrieving posts from Reddit, parsing them, and then generating a calendar that automatically gets uploaded to the site. An example of it can be seen on the [Calgary Social Club](http://www.reddit.com/r/calgarysocialclub).

##Setup & Configuration##
 * Install Ruby 1.9.3 (other version may work, but I haven't tried them, and are unsupported) and RubyGems.
 * Download this project.
 * Use the following command:

 > gem install open-uri json ruby_reddit_api chronic parseconfig

 * Configure the bot in serverInfo.conf and description.conf. Details about all the parameters are included in serverInfo.conf, and description.conf just contains the strings that will be the headers and footers that surround the calendar.
 * Run the program using:

 > ruby bot.rb

 * If it works as planned, set up an automated schedule to run the update however often you'd like.
