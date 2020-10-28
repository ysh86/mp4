#!/usr/bin/env ruby

require_relative './mp4'

def glob_files(files, argv)
  argv.each do |path|
    case File.ftype path
    when "directory"
      Dir.foreach(path) do |file|
        # TODO ちょーーーいまいち
        glob_files files, [File.join(path, file)] if file !~ /^\.\.?$/
      end
    when "file"
      files << path if path =~ /\.(mp4|mov|f4v)$/i
    end
  end
end

# unix to mac time
def fix_time(f, box)
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

files = []
glob_files(files, ARGV[0..-1])

files.each do |file|
  File.open(file, "r+b") do |f|
    mp4_file = Mp4File.new(f, File::size(f.path))

    puts file
    if false
      fix_time f, mp4_file.boxes[:moov].boxes[:mvhd]
      fix_time f, mp4_file.boxes[:moov].boxes[:trak][0].boxes[:tkhd]
      fix_time f, mp4_file.boxes[:moov].boxes[:trak][1].boxes[:tkhd]
      fix_time f, mp4_file.boxes[:moov].boxes[:trak][0].boxes[:mdia].boxes[:mdhd]
      fix_time f, mp4_file.boxes[:moov].boxes[:trak][1].boxes[:mdia].boxes[:mdhd]
    else
      puts mp4_file.to_s
    end
  end
end
