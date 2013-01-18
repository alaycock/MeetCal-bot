require 'date'

class MarkdownCalendar
  def initialize(events = {})
    @events = events
  end

  def render
    cal_string = ""
    cal_string << "Sun|Mon|Tue|Wed|Thu|Fri|Sat\n"
    6.times { |i| cal_string << ':-----------:|'}
    cal_string << ':-----------:'

    cal_string << "\n"
    today = Date.today
    start_date = Date.new(today.year, today.month, 1)
    start_date = Date.new(today.year, today.month - 1, -start_date.wday) if start_date.wday != 0 && start_date.month != 1
	start_date = Date.new(today.year-1, 12, -start_date.wday) if start_date.wday != 0 && start_date.month == 1
    end_date = Date.new(today.year, today.month, -1)
    end_date = Date.new(today.year, today.month + 1, 6 - end_date.wday) if end_date.wday != 6
    start_date.upto(end_date) { |date|
      cal_string << '~~' if date < today
      cal_string << '**' if date == today
      events = @events[date]
      if events.nil?
        cal_string << date.day.to_s
      else
        superscript = 0
        events.each { |event|
          cal_string << '[' + (superscript == 0 ? date.day.to_s : '^' + superscript.to_s) + '](' + event.link + ')'
          superscript += 1
        }
      end
      cal_string << '**' if date == today
      cal_string << '~~' if date < today
      if date.wday == 6
        cal_string << "\n"
      else
        cal_string << '|'
      end
    }
    return cal_string
  end
end
