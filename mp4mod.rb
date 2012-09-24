#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

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


module BaseMedia
  MAC2UNIX = 2082844800

  def self.create_instance_of(classname, *init_args)
    classname.split("::").inject(Object){ |oldclass, name| oldclass.const_get(name) }.new(*init_args)
  end

    
  def self.parse_boxes(f, size, depth)
    boxes = Array.new
    
    start_pos = f.tell
    while (f.tell - start_pos < size && f.eof? == false)
      self.parse_box(f, depth) { |b|
        boxes.push b
      }
    end

    if f.tell - start_pos != size
      pos = f.tell
      STDERR.print "Error! #{boxes.last.type}, #{pos} - #{start_pos} != #{size}\n"
      exit(1) # TODO 例外だよね
    end
    
    boxes
  end

  def self.parse_box(f, depth)
    size = f.read(4).unpack("N")[0]
    type = f.read(4).unpack("a4")[0]

    if size == 1
      size = f.read(8).unpack("C*")
      size = (size[0] << 56) + (size[1] << 48) + (size[2] << 40) + (size[3] << 32) +
             (size[4] << 24) + (size[5] << 16) + (size[6] <<  8) +  size[7] - 8 - 8
    elsif size == 0
      # TODO File::size がやだなー。他に方法はないか？IO:: のみに依存としたい。
      size = File::size(f.path) - f.tell
    else
      size -= 8
    end
    
    begin
      # TODO type が ASCII じゃなかったらエラーで止めるか？汚染文字列だから危険だよね？
      box = create_instance_of("#{self.name}::Box_#{type}", type)
    rescue
      box = Box.new(type)
    end

    box.parse(f, size, depth)
    
    yield box
  end
    

  class Box
    attr_reader :type
    attr_reader :size, :offset, :depth
    attr_reader :version, :flags
    attr_reader :payload, :dirty
    
    TEMPLATE = [[]]
    
    def initialize(type)
      @type    = type

      @size    = 0
      @offset  = 0
      @depth   = 0
      
      @version = 0
      @flags   = 0
      
      @payload = nil
      @dirty   = true
    end
    
    def parse(f, size, depth)
      @size    = size
      @offset  = f.tell
      @depth   = depth
      
      parse_payload f
    end

    def parse_payload(f)
      fileds_template = nil
      if self.class::TEMPLATE.length > 1
        parse_full_box(f)
        fields_template = self.class::TEMPLATE[@version]
      else
        fields_template = self.class::TEMPLATE[0]
      end
      
      box_offset = 0
      fields_template.each { |t|
        field_name = t.keys[0]
        field_size = t.values[0][0]
        field_type = t.values[0][1]
        field_num  = t.values[0][2]
        
        if field_num == :EOB
          field_num = (@size - box_offset) / field_size
        end
        
        # TODO field_type = :NN 非対応！
        field = nil
        if field_num == 1
          field = f.read(field_size).unpack(field_type)[0]
          box_offset += field_size
        else
          field = Array.new(field_num)
          field_num.times { |i|
            field[i] = f.read(field_size).unpack(field_type)[0]
            box_offset += field_size
          }
        end
        
        self.instance_variable_set(field_name, field)
      }
      
      # TODO @payload に保存するか skip するか？
      f.seek(@size - box_offset, IO::SEEK_CUR)
      @payload = nil
      @dirty   = false
    end
    
    def parse_full_box(f)
      @version = f.read(1).unpack("C")[0]
      @flags   = f.read(3).unpack("C3")
      
      @size   = @size - 4
      @offset = @offset + 4
    end
  
    def fields_to_s(s)
      # do nothing
      s
    end
    
    def to_s
      unknown = (self.class == Box) ? '?' : ''
      
      s = ' ' * @depth + unknown + "#{@type} : #{@size}, 0x#{@offset.to_s(16)}, #{@dirty}"
      
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
  
  class Box_no_fields < Box
    def parse_payload(f)
      @payload = BaseMedia::parse_boxes(f, @size, @depth+1)
      @dirty = false
    end
  end


  class Box_ftyp < Box
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
  
  class Box_mdat < Box
    def parse_payload(f)
      f.seek(@size, IO::SEEK_CUR)
      @payload = nil
      @dirty   = false
    end
  end
  
  class Box_moov < Box_no_fields
  end
  
  class Box_mvhd < Box
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
  
  class Box_trak < Box_no_fields
  end
  
  class Box_tkhd < Box
    TEMPLATE = [
      # Version 0
      [
      {:@creation_time     => [4, "N", 1]},
      {:@modification_time => [4, "N", 1]},
      {:@track_ID          => [4, "N", 1]},
      {:@reserved          => [4, "N", 1]},
      {:@duration          => [4, "N", 1]},
      {:@reserved32        => [4, "N", 2]},
      {:@layer             => [2, "n", 1]},
      {:@alternate_group   => [2, "n", 1]},
      {:@volume            => [2, "n", 1]},
      {:@reserved16        => [2, "n", 1]},
      {:@matrix            => [4, "N", 9]},
      {:@width             => [4, "N", 1]},
      {:@height            => [4, "N", 1]},
      ],
      # Version 1
      [
      {:@creation_time     => [8, :NN, 1]},
      {:@modification_time => [8, :NN, 1]},
      {:@track_ID          => [4, "N", 1]},
      {:@reserved          => [4, "N", 1]},
      {:@duration          => [8, :NN, 1]},
      {:@reserved32        => [4, "N", 2]},
      {:@layer             => [2, "n", 1]},
      {:@alternate_group   => [2, "n", 1]},
      {:@volume            => [2, "n", 1]},
      {:@reserved16        => [2, "n", 1]},
      {:@matrix            => [4, "N", 9]},
      {:@width             => [4, "N", 1]},
      {:@height            => [4, "N", 1]},
      ],
    ]
    
    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "creation_time     : #{Time.at(@creation_time-MAC2UNIX).to_s}"
      s += "\n " + " " * @depth + "modification_time : #{Time.at(@modification_time-MAC2UNIX).to_s}"
      s += "\n " + " " * @depth + "track_ID          : #{@track_ID}"
      s += "\n " + " " * @depth + "reserved          : #{@reserved}"
      s += "\n " + " " * @depth + "duration          : #{@duration}"
      s += "\n " + " " * @depth + "reserved32        : #{@reserved32.join(', ')}"
      s += "\n " + " " * @depth + "layer             : #{@layer}"
      s += "\n " + " " * @depth + "alternate_group   : #{@alternate_group}"
      s += "\n " + " " * @depth + "volume            : 0x#{@volume.to_s(16)}"
      s += "\n " + " " * @depth + "reserved16        : #{@reserved16}"
      s += "\n " + " " * @depth + "matrix            : #{@matrix.map{|i| "0x#{i.to_s(16)}"}.join(',')}"
      s += "\n " + " " * @depth + "width             : #{@width /65536.0}"
      s += "\n " + " " * @depth + "height            : #{@height/65536.0}"
    end
  end
  
  class Box_edts < Box_no_fields
  end
  
  class Box_mdia < Box_no_fields
  end
  
  class Box_mdhd < Box
    TEMPLATE = [
      # Version 0
      [
      {:@creation_time     => [4, "N", 1]},
      {:@modification_time => [4, "N", 1]},
      {:@timescale         => [4, "N", 1]},
      {:@duration          => [4, "N", 1]},
      {:@language          => [2, "n", 1]},
      {:@pre_defined       => [2, "n", 1]},
      ],
      # Version 1
      [
      {:@creation_time     => [8, :NN, 1]},
      {:@modification_time => [8, :NN, 1]},
      {:@timescale         => [4, "N", 1]},
      {:@duration          => [8, :NN, 1]},
      {:@language          => [2, "n", 1]},
      {:@pre_defined       => [2, "n", 1]},
      ],
    ]

    def lang2ascii(l)
      "#{((l>>10)|0x60).chr}#{(((l>>5)&31)|0x60).chr}#{((l&31)|0x60).chr}"
    end

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "creation_time     : #{Time.at(@creation_time-MAC2UNIX).to_s}"
      s += "\n " + " " * @depth + "modification_time : #{Time.at(@modification_time-MAC2UNIX).to_s}"
      s += "\n " + " " * @depth + "timescale         : #{@timescale}"
      s += "\n " + " " * @depth + "duration          : #{@duration}"
      s += "\n " + " " * @depth + "language          : #{lang2ascii(@language)}"
      s += "\n " + " " * @depth + "pre_defined       : #{@pre_defined}"
    end
  end
  
  class Box_hdlr < Box
    # TODO ココ
  end
  
  class Box_minf < Box_no_fields
  end
  
  class Box_vmhd < Box
    # TODO ココ
  end
  
  class Box_smhd < Box
    # TODO ココ
  end
  
  class Box_dinf < Box_no_fields
  end
  
  class Box_dref < Box
    # TODO ココ
  end
  
  class Box_stbl < Box_no_fields
  end
  
  class Box_stsdd < Box_no_fields
    # TODO ここだ！
  end
end
  

class Mp4File
  include BaseMedia

  def initialize(f, size)
    @boxes = BaseMedia::parse_boxes(f, size, 0)
  end

  def to_s
    s = ''
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
