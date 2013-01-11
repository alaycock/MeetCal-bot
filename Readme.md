#MeetupCal-bot#
##Intro##
This bot is for retrieving posts from Reddit, parsing them, and then generating a calendar that automatically gets uploaded to the site. An example of it can be seen on the [Calgary Social Club](http://www.reddit.com/r/calgarysocialclub).

##Requirements##
 * Ruby 1.9.3
 * Ruby gems - open-uri, json, rubit_reddit_api, chronic, parseconfig

##Setup##
 * Configure the two files serverInfo.conf and description.conf
 * serverInfo.conf information should be copied from /r/subreddit/about/edit except for the username and password.
 * description.conf should include the text that preceeds and subseeds the calendar.

##Usage##

 > ruby bot.rb

 * That's it! As long as there are no errors, you should be good to go. This is definitely equivalent to pre-alpha software,
so you may get errors along the way. You should probably have an understanding of ruby before you try to use this. The 
code is super messy but it gets the job done.
