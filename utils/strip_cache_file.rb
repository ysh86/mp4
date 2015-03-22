#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

ARGV.each do |arg|
  File.open(arg, "rb") do |f|
    raw_data = f.read.unpack("C*")
    payload_size =
      (raw_data[raw_data.size - 4] << 24) + 
      (raw_data[raw_data.size - 3] << 16) + 
      (raw_data[raw_data.size - 2] << 8) + 
      (raw_data[raw_data.size - 1] << 0);
    puts "#{arg}, #{raw_data.size}, #{payload_size}"
    File.open("#{arg}.mp4", "wb") do |fw|
      fw.write raw_data[0...payload_size].pack("C*")
    end
  end
end
