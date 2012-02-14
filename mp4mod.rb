#!/usr/bin/env ruby

############### func ##############

def Mp4GetAtom (input)
  # unpack は配列を返すので [0] が必要！！
  size = input.read(4).unpack("N")[0]
  type = input.read(4)

  if (size == 1)
    size = input.read(8)
    size = (size[0] << 56) + (size[1] << 48) + (size[2] << 40) + (size[3] << 32) +
           (size[4] << 24) + (size[5] << 16) + (size[6] <<  8) +  size[7] - 8
  elsif (size == 0)
    size = File::size(input.path) - input.tell + 8
  end

  return size - 8, type
end


#------------------ top -------------------#

def Mp4Atom_moov (input, size, depth)
  depth.times do print " " end
  print "moov : #{size}\n"
  Mp4ParseAtoms(input, size, depth + 1)
  print "\n"
end

def Mp4Atom_mdat (input, size, depth)
  depth.times do print " " end
  print "mdat : #{size}\n"
  input.seek(input.tell + size, 0)
  print "\n"
end


#------------------ moov -------------------#

def Mp4Atom_mvhd (input, size, depth)
  depth.times do print " " end
  # size == 100 のはず
  print "mvhd : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_iods (input, size, depth)
  depth.times do print " " end
  print "iods : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_trak (input, size, depth)
  depth.times do print " " end
  print "trak : #{size}\n"
  Mp4ParseAtoms(input, size, depth + 1)
end


#------------------ trak -------------------#

def Mp4Atom_tkhd (input, size, depth)
  depth.times do print " " end
  print "tkhd : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_mdia (input, size, depth)
  depth.times do print " " end
  print "mdia : #{size}\n"
  Mp4ParseAtoms(input, size, depth + 1)
end


#------------------ mdia -------------------#

def Mp4Atom_mdhd(input, size, depth)
  depth.times do print " " end
  print "mdhd : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_hdlr(input, size, depth)
  depth.times do print " " end
  print "hdlr : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_minf(input, size, depth)
  depth.times do print " " end
  print "minf : #{size}\n"
  Mp4ParseAtoms(input, size, depth + 1)
end


#------------------ minf -------------------#

def Mp4Atom_vmhd(input, size, depth)
  depth.times do print " " end
  print "vmhd : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_smhd(input, size, depth)
  depth.times do print " " end
  print "smhd : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_dinf(input, size, depth)
  depth.times do print " " end
  print "dinf : #{size}\n"
  Mp4ParseAtoms(input, size, depth + 1)
end

def Mp4Atom_stbl(input, size, depth)
  depth.times do print " " end
  print "stbl : #{size}\n"
  Mp4ParseAtoms(input, size, depth + 1)
end


#------------------ dinf -------------------#

def Mp4Atom_dref(input, size, depth)
  depth.times do print " " end
  print "dref : #{size}\n"
  input.seek(input.tell + size, 0)
end

#------------------ stbl -------------------#

def Mp4Atom_stts(input, size, depth)
  depth.times do print " " end
  print "stts : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_ctts(input, size, depth)
  depth.times do print " " end
  print "ctts : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_stss(input, size, depth)
  depth.times do print " " end
  print "stss : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_stsd(input, size, depth)
  depth.times do print " " end
  print "stsd : #{size}\n"

  #input.seek(input.tell + size, 0)
  # 詳細情報表示 (MP4 File Format 6.3.17.1)
  v_f = input.read(4).unpack("N")[0]          # version:8, flags:24
  size -= 4
  entry_count = input.read(4).unpack("N")[0]  # entry-count:32
  size -= 4
  depth.times do print " " end
  print " entry-count = #{entry_count}\n"
  entry_count.times do                        # SampleEntry x entry-count
    Mp4ParseAtoms(input, size, depth + 1)
  end
end

def Mp4Atom_stsz(input, size, depth)
  depth.times do print " " end
  print "stsz : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_stsc(input, size, depth)
  depth.times do print " " end
  print "stsc : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_stco(input, size, depth)
  depth.times do print " " end
  print "stco : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_stsh(input, size, depth)
  depth.times do print " " end
  print "stsh : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_stdp(input, size, depth)
  depth.times do print " " end
  print "stdp : #{size}\n"
  input.seek(input.tell + size, 0)
end

def Mp4Atom_mp4v(input, size, depth)
  depth.times do print " " end
  print "mp4v : #{size}\n"

  #input.seek(input.tell + size, 0)
  # 詳細情報表示 (MP4 File Format 6.3.17.1)
  reserved = input.read(78)
  size -= 78
  Mp4ParseAtoms(input, size, depth + 1)   # ESDAtom
end

def Mp4Atom_mp4a(input, size, depth)
  depth.times do print " " end
  print "mp4a : #{size}\n"

  #input.seek(input.tell + size, 0)
  # 詳細情報表示 (MP4 File Format 6.3.17.1)
  reserved = input.read(28)
  size -= 28
  Mp4ParseAtoms(input, size, depth + 1)   # ESDAtom
end

def Mp4Atom_esds(input, size, depth)
  depth.times do print " " end
  print "esds : #{size}\n"

  input.seek(input.tell + size, 0)
  ## 詳細情報表示 (MP4 File Format 6.3.17.1)
  ##v_f = input.read(4).unpack("N")[0]          # version:8, flags:24
  ##size -= 4
  ##Mp4ParseDescriptor(input, size, depth + 1)
end


def Mp4Atom_unknown (input, type, size, depth)
  depth.times do print " " end
  print "unknown(#{type}) : #{size}\n"
  input.seek(input.tell + size, 0)
end


def Mp4ParseAtoms (input, length, depth)
  start_pos = input.tell
  while (input.tell - start_pos < length && input.eof? == false)
    atom_data_size, atom_type = Mp4GetAtom(input)
    case atom_type
    when "moov"
      Mp4Atom_moov(input, atom_data_size, depth)
    when "mdat"
      Mp4Atom_mdat(input, atom_data_size, depth)
    when "mvhd"
      Mp4Atom_mvhd(input, atom_data_size, depth)
    when "iods"
      Mp4Atom_iods(input, atom_data_size, depth)
    when "trak"
      Mp4Atom_trak(input, atom_data_size, depth)
    when "tkhd"
      Mp4Atom_tkhd(input, atom_data_size, depth)
    when "mdia"
      Mp4Atom_mdia(input, atom_data_size, depth)
    when "mdhd"
      Mp4Atom_mdhd(input, atom_data_size, depth)
    when "hdlr"
      Mp4Atom_hdlr(input, atom_data_size, depth)
    when "minf"
      Mp4Atom_minf(input, atom_data_size, depth)
    when "vmhd"
      Mp4Atom_vmhd(input, atom_data_size, depth)
    when "smhd"
      Mp4Atom_smhd(input, atom_data_size, depth)
    when "dinf"
      Mp4Atom_dinf(input, atom_data_size, depth)
    when "stbl"
      Mp4Atom_stbl(input, atom_data_size, depth)
    when "dref"
      Mp4Atom_dref(input, atom_data_size, depth)
    when "stts"
      Mp4Atom_stts(input, atom_data_size, depth)
    when "ctts"
      Mp4Atom_ctts(input, atom_data_size, depth)
    when "stss"
      Mp4Atom_stss(input, atom_data_size, depth)
    when "stsd"
      Mp4Atom_stsd(input, atom_data_size, depth)
    when "stsz"
      Mp4Atom_stsz(input, atom_data_size, depth)
    when "stsc"
      Mp4Atom_stsc(input, atom_data_size, depth)
    when "stco"
      Mp4Atom_stco(input, atom_data_size, depth)
    when "stsh"
      Mp4Atom_stsh(input, atom_data_size, depth)
    when "stdp"
      Mp4Atom_stdp(input, atom_data_size, depth)
    when "mp4v"
      Mp4Atom_mp4v(input, atom_data_size, depth)
    when "mp4a"
      Mp4Atom_mp4a(input, atom_data_size, depth)
    when "esds"
      Mp4Atom_esds(input, atom_data_size, depth)
    else
      Mp4Atom_unknown(input, atom_type, atom_data_size, depth)
    end
  end

  if (input.tell - start_pos != length)
    pos = input.tell
    print "Error! #{pos} - #{start_pos} != #{length}\n"
    exit(1)
  end
end


############### Main ##############

if (ARGV.length > 0)
  input_file = File.open(ARGV.shift, "rb")
  input_file.binmode
else
  print "usage: mp4check.rb <MP4 file>\n"
  exit(1)
end

Mp4ParseAtoms(input_file, File::size(input_file.path), 0)
exit(0)
