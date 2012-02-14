#!/usr/bin/env ruby

=begin
############### 関数 ##############

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
=end


############### Class ##############
class Mp4Box
  attr_reader :type, :size, :offset, :depth
  attr_reader :version, :flags
  attr_reader :payload, :dirty
  
  MAC2UNIX = 2082844800
  TEMPLATE = [[]]
  
  def self.create_instance_of(classname, *init_args)
    classname.split("::").inject(Object){ |oldclass, name| oldclass.const_get(name) }.new(*init_args)
  end
  
  def self.parseBoxes(f, len, depth)
    boxes = Array.new
    
    start_pos = f.tell
    while (f.tell - start_pos < len && f.eof? == false)
      self.parse(f, depth) { |b|
        boxes.push b
      }
    end

    if f.tell - start_pos != len
      pos = f.tell
      STDERR.print "Error! #{boxes.last.type}, #{pos} - #{start_pos} != #{len}\n"
      exit(1) # TODO 例外だよね
    end
    
    boxes
  end
  
  def self.parse(f, depth)
    size = f.read(4).unpack("N")[0]
    type = f.read(4).unpack("a4")[0]

    if size == 1
      size = f.read(8).unpack("C*")
      size = (size[0] << 56) + (size[1] << 48) + (size[2] << 40) + (size[3] << 32) +
             (size[4] << 24) + (size[5] << 16) + (size[6] <<  8) +  size[7] - 8
    elsif size == 0
      # TODO File::size がやだなー。他に方法はないか？IO:: のみに依存としたい。
      size = File::size(f.path) - f.tell + 8
    end
    
    begin
      # TODO Box class の定義を入れ子にして、自分の Scope 内しか探さないようにすれば、Box の依存チェックもついでにできるか？
      box = create_instance_of("Mp4Box_#{type}", type, size-8, f.tell, depth, f)
    rescue
      # TODO type が ASCII じゃなかったらエラーで止めるか？
      box = self.new(type, size-8, f.tell, depth, f)
    end
    
    yield box
  end
  
  def initialize(type, size, offset, depth, f)
    @type    = type
    @size    = size
    @offset  = offset
    @depth   = depth
    
    @version = 0
    @flags   = 0
    
    @payload = nil
    @dirty   = true
    
    parsePayload f
  end
  
  def fullBox(f)
    @version = f.read(1).unpack("C")[0]
    @flags   = f.read(3).unpack("C3")
    
    @size   = @size - 4
    @offset = @offset + 4
  end

  def parsePayload(f)
    elem_template = nil
    if self.class::TEMPLATE.length > 1
      fullBox(f)
      elem_template = self.class::TEMPLATE[@version]
    else
      elem_template = self.class::TEMPLATE[0]
    end
    
    box_offset = 0
    elem_template.each { |t|
      elem_name = t.keys[0]
      elem_size = t.values[0][0]
      elem_type = t.values[0][1]
      elem_num  = t.values[0][2]
      
      if elem_num == :EOB
        elem_num = (@size - box_offset) / elem_size
      end
      
      # TODO elem_type = :NN 非対応！
      elem = nil
      if elem_num == 1
        elem = f.read(elem_size).unpack(elem_type)[0]
        box_offset += elem_size
      else
        elem = Array.new(elem_num)
        elem_num.times { |i|
          elem[i] = f.read(elem_size).unpack(elem_type)[0]
          box_offset += elem_size
        }
      end
      
      self.instance_variable_set(elem_name, elem)
    }
    
    # TODO @payload に保存するか skip するか？
    f.seek(@size - box_offset, IO::SEEK_CUR)
    @payload = nil
    @dirty   = false
  end
  
  def fields_to_s(s)
    # do nothing
    s
  end
  
  def to_s
    unknown = (self.class == Mp4Box) ? '*' : ''
    
    s = " " * @depth + unknown + "#{@type} : #{@size}, 0x#{@offset.to_s(16)}, #{@dirty}"
    
    # TODO テンプレートに応じて自動出力もいいけど、可読性を上げるなら独自に書き出した方がいいね。timestamp とかね。
    # TODO いや、基本自動出力で、個別対応したいものだけ独自だよね
    s = fields_to_s(s)
    
    if @payload.class == Array
      @payload.each { |b|
        s += "\n#{b.to_s}"
      }
    end
    
    s
  end
end


class Mp4Box_ftyp < Mp4Box
  TEMPLATE = [[
    {:@major_brand       => [4, "a*", 1   ]},
    {:@minor_version     => [4, "N" , 1   ]},
    {:@compatible_brands => [4, "a*", :EOB]},
  ]]
  
  def fields_to_s(s)
    s += "\n " + " " * @depth + "major_brand       : #{@major_brand}"
    s += "\n " + " " * @depth + "minor_version     : #{@minor_version}"
    @compatible_brands.each { |i|
      s += "\n " + " " * @depth + "compatible_brands : #{i}"
    }
    s
  end
end

class Mp4Box_mdat < Mp4Box
  def parsePayload(f)
    f.seek(@size, IO::SEEK_CUR)
    @payload = nil
    @dirty   = false
  end
end

# TODO ただの入れ物
class Mp4Box_moov < Mp4Box
  def parsePayload(f)
    @payload = Mp4Box.parseBoxes(f, @size, @depth+1)
    @dirty = false
  end
end

class Mp4Box_mvhd < Mp4Box
  TEMPLATE = [
    # Version 0
    [
    {:@creation_time     => [4, "N", 1]},
    {:@modification_time => [4, "N", 1]},
    {:@timescale         => [4, "N", 1]},
    {:@duration          => [4, "N", 1]},
    {:@rate              => [4, "N", 1]},
    {:@volume            => [2, "n", 1]},
    {:@reserved16        => [2, "n", 1]},
    {:@reserved32        => [4, "N", 2]},
    {:@matrix            => [4, "N", 9]},
    {:@pre_defined       => [4, "N", 6]},
    {:@next_track_ID     => [4, "N", 1]},
    ],
    # Version 1
    [
    {:@creation_time     => [8, :NN, 1]},
    {:@modification_time => [8, :NN, 1]},
    {:@timescale         => [4, "N", 1]},
    {:@duration          => [8, :NN, 1]},
    {:@rate              => [4, "N", 1]},
    {:@volume            => [2, "n", 1]},
    {:@reserved16        => [2, "n", 1]},
    {:@reserved32        => [4, "N", 2]},
    {:@matrix            => [4, "N", 9]},
    {:@pre_defined       => [4, "N", 6]},
    {:@next_track_ID     => [4, "N", 1]},
    ],
  ]
  
  def fields_to_s(s)
    s += "\n " + " " * @depth + "FullBox version : #{@version}"
    s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
    s += "\n " + " " * @depth + "creation_time     : #{Time.at(@creation_time-MAC2UNIX).to_s}"
    s += "\n " + " " * @depth + "modification_time : #{Time.at(@modification_time-MAC2UNIX).to_s}"
    s += "\n " + " " * @depth + "timescale         : #{@timescale}"
    s += "\n " + " " * @depth + "duration          : #{@duration}"
    s += "\n " + " " * @depth + "rate              : 0x#{@rate.to_s(16)}"
    s += "\n " + " " * @depth + "volume            : 0x#{@volume.to_s(16)}"
    s += "\n " + " " * @depth + "reserved16        : #{@reserved16}"
    s += "\n " + " " * @depth + "reserved32        : #{@reserved32.join(', ')}"
    s += "\n " + " " * @depth + "matrix            : #{@matrix.map{|i| "0x#{i.to_s(16)}"}.join(',')}"
    s += "\n " + " " * @depth + "pre_defined       : #{@pre_defined.join(', ')}"
    s += "\n " + " " * @depth + "next_track_ID     : #{@next_track_ID}"
  end
end

# TODO 以下、ただの入れ物
class Mp4Box_trak < Mp4Box
  def parsePayload(f)
    @payload = Mp4Box.parseBoxes(f, @size, @depth+1)
    @dirty = false
  end
end

class Mp4Box_edts < Mp4Box
  def parsePayload(f)
    @payload = Mp4Box.parseBoxes(f, @size, @depth+1)
    @dirty = false
  end
end

class Mp4Box_mdia < Mp4Box
  def parsePayload(f)
    @payload = Mp4Box.parseBoxes(f, @size, @depth+1)
    @dirty = false
  end
end

class Mp4Box_minf < Mp4Box
  def parsePayload(f)
    @payload = Mp4Box.parseBoxes(f, @size, @depth+1)
    @dirty = false
  end
end

class Mp4Box_dinf < Mp4Box
  def parsePayload(f)
    @payload = Mp4Box.parseBoxes(f, @size, @depth+1)
    @dirty = false
  end
end

class Mp4Box_stbl < Mp4Box
  def parsePayload(f)
    @payload = Mp4Box.parseBoxes(f, @size, @depth+1)
    @dirty = false
  end
end

# TODO ここだ！
class Mp4Box_stsdd < Mp4Box
  def parsePayload(f)
    @payload = Mp4Box.parseBoxes(f, @size, @depth+1)
    @dirty = false
  end
end


class Mp4File
  def initialize(f, len)
    @boxes = Mp4Box.parseBoxes(f, len, 0)
  end

  def to_s
    s = ""
    @boxes.each { |b|
      s += "#{b.to_s}\n"
    }
    s
  end
end

############### Main ##############

if ARGV.length == 0
  STDERR.print "usage: mp4mod.rb <MP4 file>\n"
  exit(1)
end

File.open(ARGV[0], "rb") { |f|
  mp4_file = Mp4File.new(f, File::size(f.path))
  puts mp4_file.to_s
}
