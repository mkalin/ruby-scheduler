#!/usr/bin/ruby

## The short version:
#
# Classes with even partially overlapping times go into the same ScheduleSet. (A 
# student presumably cannot take two courses that overlap.) ScheduleSets then are
# ordered by size, with the big ones coming first. 
#
# ScheduleSets, once built, are assigned to ExamSlots. At present, there are four
# exam slots per day: three during the day and one in the evening. There's some ad hoc
# logic to handle ad hoc cases.
# 
# The output indicates which classes (defined by start-end times) occur in which
# ExamSlots.

require 'time'

## data structures
@course_times          = []
@schedule_sets         = []
@assigned_to_set       = {}
@exam_slots            = {}
@evening_schedule_sets = {}

## output file
@outfileName
@outfile

class ScheduleSet
  attr_accessor :name, :members, :st, :ft, :dow, :scheduled, :slot

  def initialize(name, st, ft, dow)
    @name      = name
    @st        = st
    @ft        = ft
    @dow       = dow
    @members   = []
    @scheduled = false
    @slot      = nil
  end

  def add_member(member)
    @members << member if !members.include? member
  end

  def schedule(slot)
    @scheduled = true
    @slot = slot
  end

  def scheduled?
    @scheduled
  end
  
  def to_s
    string = "\n" + @name + "\n" 
    string += "From:    #{@st}\n"
    string += "To:      #{@ft}\n"
    string += "On:      #{@dow}"
    string += "\n"
    string += "In slot: " + ((slot.nil?) ? '?' : @slot.name) + "\n"
    members.each do |member|
      string += '   ' + member + "\n"
    end
    string
  end
end

class ExamSlot
  attr_accessor :name, :time, :dow, :set, :filled, :evening
  
  def initialize(name, dow, time, eve)
    @name      = name 
    @dow       = dow
    @time      = time 
    @evening   = eve
    @set       = nil
    @filled    = (evening?) ? true : false # evening slots are filled automatically
  end

  def evening?
    @evening
  end

  def filled?
    @filled
  end

  def assign(set)
    @set = set
    @filled = true
    set.schedule self
  end

  def to_s
    string = "\n" + @name + "\n"
    string += "Set of classes assigned to this slot:\n"
    string += "(The set, named after a day/time, includes all classes that overlap.)\n"
    string += "#{set.to_s}" if !@set.nil?
    string += ";;;;;;;;\n"
    string
  end
end
#;;;;

FILE_NAME = 'classTimes.dat' 

def read_data_from_infile
  infile_name = ARGV[0] || FILE_NAME
  infile = File.new(infile_name, 'r')

  ## Generate simulated course offerings at specified times, with randomly
  #  many offerings for each time.
  letters = %w(M T W R F S) # 'R' for ThuRsday
  infile.each do |record|
    record.chomp!
    record.strip!

    # Generates this pattern: 
    #   08:00AM-09:00AM!M
    #   08:00AM-09:00AM!MT
    #   08:00AM-09:00AM!MTW
    #   ...
    # and places each course in a list, which in turn goes into
    # a global list.
    set = []
    i = 1
    letters.each do |letter|
      temp = record + '!' + letter
      set << temp
      j = i
      i.upto(letters.length - 1) do 
        temp += letters[j]
        j += 1
        set << temp
      end
      i += 1
    end
    set.uniq!
    set.sort!
    @course_times << set
  end
  infile.close

  @course_times.flatten!
  @course_times.uniq!
  @course_times.sort! {|c1, c2| c1.split('!')[1] <=> c2.split('!')[1]}
end

def bad_split?(two_parts)
  two_parts[0].nil? || two_parts[0].to_s.empty? || two_parts[1].nil? || two_parts[1].empty?
end

def get_parts(member) 
  st = ft = dow = ''
  empty = [st, ft, dow]

  parts = member.split '!'
  return empty if bad_split? parts

  times = parts[0].split '-'
  return empty if bad_split? times
  
  st = times[0]
  ft = times[1]
  dow = parts[1]
  
  [st, ft, dow]
end

def overlaps?(s_s, s_f, c_s, c_f) 
  s_start  = Time.parse(s_s) # set start
  s_finish = Time.parse(s_f) # set finish
  c_start  = Time.parse(c_s) # course start
  c_finish = Time.parse(c_f) # course finish

  (c_start  >= s_start && c_start  <= s_finish) ||
  (c_finish >= s_start && c_finish <= s_finish)
end

def one_day_per_week?(dow, st)    # Once a week with exam at that time
  return false if dow.length > 1
  return true if dow =~ /^S/     # Saturday only courses treated as night courses

  Time.parse(st) >= Time.parse('05:30PM')
end

def assign_to_schedule_set(course)
  (st, ft, dow) = get_parts course

  if one_day_per_week?(dow, st)
    set = @evening_schedule_sets[dow]
    set.add_member course
    @assigned_to_set[course] = set
  else
    regex = Regexp.new('[' + dow + ']')
    @schedule_sets.each do |set|    
      if set.dow.length > 1   &&            # Prevent 'evening' sets from capturing everything
         regex.match(set.dow) &&            # Must have overlapping day
         overlaps?(set.st, set.ft, st, ft)  # Must have overlapping times
        set.add_member course
        @assigned_to_set[course] = set
        return
      end
    end
  end
end

def create_schedule_sets
  read_data_from_infile
  puts "Working :)\n"

  @course_times.each do |member|
    (st, ft, dow) = get_parts(member)
    name = 'Set-' + member
    set = ScheduleSet.new(name, st, ft, dow)
    @schedule_sets << set
    @assigned_to_set[member] = nil
    @evening_schedule_sets[dow] = set if one_day_per_week?(set.dow, set.st)
  end
  puts "Done creating schedule sets..."
end

def populate_schedule_sets
  # Sort on the days field so that, e.g., 08:30AM-09:30AM!M < 08:00AM-09:00AM!MWF
  @schedule_sets.sort! {|s1, s2| s1.name.split('!')[1] <=> s2.name.split('!')[1]}

  # For each schedule set, iterate through the course list and any course
  # that overlaps on days and times.
  @course_times.each do |course|
    assign_to_schedule_set course if !@assigned_to_set[course]
  end
  puts "Done populating schedule sets..."
end

def dump_schedule_sets
  @schedule_sets.each do |member|
    puts "\n" + member.to_s
  end
  puts ';;;;;'
end

def create_exam_slots
  all_days = %w(M T W R F S)
  days     = %w(M T W R F)   # ThuRsday
  slots    = %w(_d1 _d2 _d3) # 3 slots per day + evening slot _e

  # Create evening slots
  all_days.each do |day|
    slot_name = day + '_e'
    name = 'ExamSlot-' + slot_name
    @exam_slots[name] = ExamSlot.new(name, day, slot_name, true)
  end

  # Generate the rest
  days.each do |day|
    slots.each do |slot|
      d = day + slot
      n = 'ExamSlot-' + d
      @exam_slots[n] = ExamSlot.new(n, day, d, false)
    end
  end
end

def assign_one_day_a_week_sets
  slots = @exam_slots.values.map {|slot| (slot.evening?) ? slot : nil} 
  slots.delete nil
  sets = @evening_schedule_sets.values
  sets.delete nil
  
  sets.each do |set|
    slots.each do |slot|
      if set.dow == slot.dow
        slot.assign set
        break
      end 
    end
  end
end

def pick_schedule_set
  open = @schedule_sets.map {|set| (!set.scheduled?) ? set : nil}
  open.delete nil
  open[rand(open.length)] # nil if open is empty
end

def pick_slot
  open = @exam_slots.values.map {|slot| (!slot.filled? && !slot.evening?) ? slot : nil}
  open.delete nil
  open[rand(open.length)] # nil if open is empty
end

def create_schedule
  # Handle the one-day-a-week classes first
  assign_one_day_a_week_sets

  # For all remaining schedule sets, assign each to a regular slot.
  while true
    set = pick_schedule_set
    break if set.nil? 
    
    slot = pick_slot   
    break if slot.nil? 

    slot.evening = true if one_day_per_week?(set.dow, set.st) 
    slot.assign set
  end
end

def dump_schedule
  exam_slot_count = 0
  scheduled_classes_count = 0

  @outfileName = "schedule-" + Time.now.to_s[0,19].gsub(/\s+/, "-") + ".dat"
  @outfile = File.new(@outfileName, "w")

  keys = @exam_slots.keys.sort
  keys.each do |key|
    puts @exam_slots[key].to_s
    @outfile.puts(@exam_slots[key].to_s)
  end
  puts "\nThat's it, folks!"
end

def dump_stats
  slots = @exam_slots.values.map {|slot| (slot.filled?) ? slot : nil}
  slots.delete nil
  slots.sort! {|s1, s2| s1.name <=> s2.name}

  puts ";;;;;;;;\n\n"
  @outfile.puts( ";;;;;;;;\n\n")

  puts "Total course offerings: #{@course_times.size}"
  @outfile.puts("Total course offerings: #{@course_times.size}")
  puts
  @outfile.puts
  puts "Slots used:             #{slots.size}"
  @outfile.puts("Slots used:             #{slots.size}")

  total = 0
  slots.each do |slot|
    puts slot.name
    @outfile.puts(slot.name)
    total += slot.set.members.size if !slot.set.nil?
  end
  puts
  @outfile.puts
  puts "Total sets in slots:                          #{total}"
  @outfile.puts("Total sets in slots:                          #{total}")
  puts "Total schedule sets (one per class offering): #{@schedule_sets.size}"
  @outfile.puts("Total schedule sets (one per class offering): #{@schedule_sets.size}")
end

## Run
create_schedule_sets    # a unique times/days pair distinguishes each set
populate_schedule_sets  # add 'overlapping' courses to the appropriate schedule sets
dump_schedule_sets

create_exam_slots
create_schedule
dump_schedule 

## Set flag to false if the additional statistics are not wanted.
flag = true
dump_stats if flag

puts("\n### The schedule has been written to the output file: #{@outfileName}.\n\n")
