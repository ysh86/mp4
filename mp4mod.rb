#!/usr/bin/env ruby

require_relative './mp4'

def glob_files(argv)
  files = []
  argv.each do |path|
    case File.ftype path
    when "directory"
      files.concat Dir.glob(File.join(path, "**", "*.{mp4,mov,f4v,cmfa,cmfv,m4s}"))
    when "file"
      files << path if path =~ /\.(mp4|mov|f4v|cmfa|cmfv|m4s)$/i
    end
  end
  files
end

# unix to mac time
def fix_header_time(f, box)
  if box.version == 0
    format = "N"
  else
    format = "Q>"
  end
  # creation_time
  puts "#{box.type}: from #{Time.at(box.creation_time-BaseMedia::MAC2UNIX).strftime("%F %T %z")} to #{Time.at(box.creation_time).strftime("%F %T %z")}"
  f.seek box.offset + box.template[0].values[0][3]
  f.write [box.creation_time + BaseMedia::MAC2UNIX].pack(format)
  # modification_time
  puts "#{box.type}: from #{Time.at(box.modification_time-BaseMedia::MAC2UNIX).strftime("%F %T %z")} to #{Time.at(box.modification_time).strftime("%F %T %z")}"
  f.seek box.offset + box.template[1].values[0][3]
  f.write [box.modification_time + BaseMedia::MAC2UNIX].pack(format)
end

############### Main ##############
if ARGV.length == 0
  STDERR.puts "usage: mp4mod.rb <files> ..."
  exit(1)
end

glob_files(ARGV[0..-1]).each do |file|
  puts '----------------------------------------------------'
  puts file
  puts '----------------------------------------------------'
  File.open(file, "r+b") do |f|
    mp4_file = Mp4File.new(f, File::size(f.path))
    if false
      fix_header_time f, mp4_file.boxes[:moov].boxes[:mvhd]
      fix_header_time f, mp4_file.boxes[:moov].boxes[:trak][0].boxes[:tkhd]
      fix_header_time f, mp4_file.boxes[:moov].boxes[:trak][1].boxes[:tkhd]
      fix_header_time f, mp4_file.boxes[:moov].boxes[:trak][0].boxes[:mdia].boxes[:mdhd]
      fix_header_time f, mp4_file.boxes[:moov].boxes[:trak][1].boxes[:mdia].boxes[:mdhd]
    elsif false
      # mod edit list
      box = mp4_file.boxes[:moov].boxes[:trak].boxes[:edts].boxes[:elst]
      if box.version == 1
        format = "Q>"
      else
        format = "N"
      end
      orig = box.segment_duration
      mod = 0
      puts "#{box.type}.segment_duration: from #{orig} to #{mod}"
      f.seek box.offset + box.template[1].values[0][3]
      f.write [mod].pack(format)
      break

      # mod fMP4 tfdt baseMediaDecodeTime
      #mp4_file.boxes[:moof].each do |moof|
      moof = mp4_file.boxes[:moof]

        box = moof.boxes[:traf].boxes[:tfdt]
        if box.version == 1
          format = "Q>"
        else
          format = "N"
        end

        orig = box.baseMediaDecodeTime
        mod = orig + 65520
        puts "#{box.type}.baseMediaDecodeTime: from #{orig} to #{mod}"
        f.seek box.offset + box.template[0].values[0][3]
        f.write [mod].pack(format)
      #end
    else
      mp4_file.box_to_s(STDOUT)
    end
  end
end
