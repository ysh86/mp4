#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

ARGV.each do |arg|
  File.open(arg, "rb") do |f|
    raw_data = f.read.unpack("C*")
    mdat_pos = -1
    raw_data[0...(raw_data.size - 3)].each_index do |i|
      if raw_data[i] == 0x6D && raw_data[i+1] == 0x64 && raw_data[i+2] == 0x61 && raw_data[i+3] == 0x74
        mdat_pos = i - 4
      end
    end
    puts "#{arg}, #{raw_data.size}, 0x#{mdat_pos.to_s(16)}"
    if mdat_pos > 0
      File.open("#{arg}.mp4", "wb") do |fw|
        fw.write raw_data[0...mdat_pos].pack("C*")
      end
    end
  end
end
