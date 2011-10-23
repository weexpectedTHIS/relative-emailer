require 'net/smtp'
require 'erb'
require 'yaml'
require_relative 'lib/flickraw.rb'

# Load Config
config_file_path = '~/.relative_emailer.yml'
raise "Config file missing: #{config_file_path}" unless File.exists?(File.expand_path(config_file_path))
CONFIG = YAML.load_file(File.expand_path(config_file_path))
CURRENT_DIR = File.dirname(__FILE__)

FlickRaw.api_key = CONFIG['flickr_api_key']
FlickRaw.shared_secret = CONFIG['flickr_shared_secret']

subject = ARGV.index('-subject') ? ARGV[ARGV.index('-subject') + 1] : 'Daily Flickr Digest'
username_info = flickr.people.findByUsername :username => CONFIG['flickr_username']
user_id = username_info['id']
user_info = flickr.people.getInfo :user_id => username_info['id']
photos_url = user_info['photosurl']

pics = flickr.people.getPublicPhotos :user_id => user_id, :extras => 'date_upload,url_l,media'

pics = pics.map do |pic|
  time = Time.at(pic['dateupload'].to_i)
  {
    :url => "#{photos_url}#{pic['id']}",
    :src => pic['url_l'],
    :title => pic['title'],
    :uploaded_date => Time.new(time.year, time.month, time.day),
    :video => pic['media'] == 'video'
  }
end

days = ARGV.index('-days') ? ARGV[ARGV.index('-days') + 1].to_i : CONFIG['default_days']
tomorrow = Time.now + 24 * 60 * 60
ending = Time.new(tomorrow.year, tomorrow.month, tomorrow.day)
beginning = ending - days * 24 * 60 * 60

pics_by_date = {}

pics.each do |pic|
  if (beginning <= pic[:uploaded_date]) && (pic[:uploaded_date] < ending)
    pics_by_date[pic[:uploaded_date]] ||= []
    pics_by_date[pic[:uploaded_date]] << pic
  end
end

unless ARGV.include?('-dry')
  template = ERB.new File.new(CURRENT_DIR + "/email.html.erb").read, nil, "%"
  msg = template.result(binding)
  
  smtp = Net::SMTP.new 'smtp.gmail.com', 587
  smtp.enable_starttls
  
  smtp.start('gmail.com', CONFIG['gmail_from'], CONFIG['gmail_password'], :plain) do |smtp|
    smtp.send_message msg, CONFIG['gmail_from'], CONFIG['email_to']
  end
end
output = pics_by_date.keys.sort.reverse.map do |date|
  date.strftime('%A, %B %e') + "\n" +
  pics_by_date[date].map do |pic|
    "  #{pic[:title]}#{' VIDEO' if pic[:video]}"
  end.join("\n")
end.join("\n")
puts output
puts "Subject: #{subject}"
puts "Days: #{days}"
puts "Days with pictures: #{pics_by_date.keys.size}"
puts "Pictures: #{pics_by_date.values.flatten.select{|p| !p[:video]}.size}"
puts "Videos: #{pics_by_date.values.flatten.select{|p| p[:video]}.size}"
puts "Total: #{pics_by_date.values.flatten.size}"
if ARGV.include?('-dry')
  puts "DRY RUN, NO EMAILS SENT"
else
  puts "EMAILS SENT TO: #{CONFIG['email_to'].join(', ')}"
end
