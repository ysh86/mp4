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

  # from 1904/1/1 to 1970/1/1
  MAC2UNIX = 2082844800

  def self.parse_boxes(f, size, depth=0)
    boxes = Array.new

    start_pos = f.tell
    while (f.tell - start_pos < size && f.eof? == false)
      self.parse_box(f, depth) do |b|
        #puts b.to_s # debug
        boxes.push b
      end
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
      box = Class.const_get("#{self.name}::Box_#{type}").new(type)
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
    def template()
      if self.class::TEMPLATE.length > 1
        self.class::TEMPLATE[@version]
      else
        self.class::TEMPLATE[0]
      end
    end

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
      fields_template.each do |t|
        field_sym  = t.keys[0]
        field_size = t.values[0][0]
        field_type = t.values[0][1]
        field_num  = t.values[0][2]
        t.values[0].push(box_offset)

        if field_size == :EOB
          field_size = @size - box_offset
        end
        if field_num == :EOB
          field_num = (@size - box_offset) / field_size
        end

        field = nil
        if field_num == 1
          if field_type != :NN
            field = f.read(field_size).unpack(field_type)[0]
            box_offset += field_size
          else
            # 64bit network byte order
            fields = f.read(field_size).unpack("N")
            field = (fields[0] << 32) + fields[1]
            box_offset += field_size
          end
        else
          field = Array.new(field_num)
          field_num.times do |i|
            field[i] = f.read(field_size).unpack(field_type)[0]
            box_offset += field_size
          end
        end

        self.instance_variable_set("@" + field_sym.to_s, field)
        self.class.send(:attr_reader, field_sym)
      end

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
        @payload.each do |b|
          s += "\n#{b.to_s}"
        end
      end

      s
    end
  end

  class Box_no_fields < Box
    attr_reader :boxes
    def parse_payload(f)
      @payload = BaseMedia::parse_boxes(f, @size, @depth+1)
      @boxes = {}
      @payload.each do |b|
        s = b.type.to_sym
        if @boxes.has_key? s
          t = @boxes[s]
          if t.class == Array
            @boxes[s].push(b)
          else
            @boxes[s] = [t,b]
          end
        else
          @boxes[s] = b
        end
      end
      @dirty = false
    end
  end


  class Box_ftyp < Box
    TEMPLATE = [[
      {:major_brand       => [4, "a*", 1   ]},
      {:minor_version     => [4, "N" , 1   ]},
      {:compatible_brands => [4, "a*", :EOB]},
    ]]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "major_brand       : #{@major_brand}"
      s += "\n " + " " * @depth + "minor_version     : #{@minor_version}"
      @compatible_brands.each do |i|
        s += "\n " + " " * @depth + "compatible_brands : #{i}"
      end
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
      {:creation_time     => [4, "N", 1]},
      {:modification_time => [4, "N", 1]},
      {:timescale         => [4, "N", 1]},
      {:duration          => [4, "N", 1]},
      {:rate              => [4, "N", 1]},
      {:volume            => [2, "n", 1]},
      {:reserved16        => [2, "n", 1]},
      {:reserved32        => [4, "N", 2]},
      {:matrix            => [4, "N", 9]},
      {:pre_defined       => [4, "N", 6]},
      {:next_track_ID     => [4, "N", 1]},
      ],
      # Version 1
      [
      {:creation_time     => [8, :NN, 1]},
      {:modification_time => [8, :NN, 1]},
      {:timescale         => [4, "N", 1]},
      {:duration          => [8, :NN, 1]},
      {:rate              => [4, "N", 1]},
      {:volume            => [2, "n", 1]},
      {:reserved16        => [2, "n", 1]},
      {:reserved32        => [4, "N", 2]},
      {:matrix            => [4, "N", 9]},
      {:pre_defined       => [4, "N", 6]},
      {:next_track_ID     => [4, "N", 1]},
      ],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "creation_time     : #{Time.at(@creation_time-MAC2UNIX).strftime("%F %T %z")}"
      s += "\n " + " " * @depth + "modification_time : #{Time.at(@modification_time-MAC2UNIX).strftime("%F %T %z")}"
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
      {:creation_time     => [4, "N", 1]},
      {:modification_time => [4, "N", 1]},
      {:track_ID          => [4, "N", 1]},
      {:reserved          => [4, "N", 1]},
      {:duration          => [4, "N", 1]},
      {:reserved32        => [4, "N", 2]},
      {:layer             => [2, "n", 1]},
      {:alternate_group   => [2, "n", 1]},
      {:volume            => [2, "n", 1]},
      {:reserved16        => [2, "n", 1]},
      {:matrix            => [4, "N", 9]},
      {:width             => [4, "N", 1]},
      {:height            => [4, "N", 1]},
      ],
      # Version 1
      [
      {:creation_time     => [8, :NN, 1]},
      {:modification_time => [8, :NN, 1]},
      {:track_ID          => [4, "N", 1]},
      {:reserved          => [4, "N", 1]},
      {:duration          => [8, :NN, 1]},
      {:reserved32        => [4, "N", 2]},
      {:layer             => [2, "n", 1]},
      {:alternate_group   => [2, "n", 1]},
      {:volume            => [2, "n", 1]},
      {:reserved16        => [2, "n", 1]},
      {:matrix            => [4, "N", 9]},
      {:width             => [4, "N", 1]},
      {:height            => [4, "N", 1]},
      ],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "creation_time     : #{Time.at(@creation_time-MAC2UNIX).strftime("%F %T %z")}"
      s += "\n " + " " * @depth + "modification_time : #{Time.at(@modification_time-MAC2UNIX).strftime("%F %T %z")}"
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
      {:creation_time     => [4, "N", 1]},
      {:modification_time => [4, "N", 1]},
      {:timescale         => [4, "N", 1]},
      {:duration          => [4, "N", 1]},
      {:language          => [2, "n", 1]},
      {:pre_defined       => [2, "n", 1]},
      ],
      # Version 1
      [
      {:creation_time     => [8, :NN, 1]},
      {:modification_time => [8, :NN, 1]},
      {:timescale         => [4, "N", 1]},
      {:duration          => [8, :NN, 1]},
      {:language          => [2, "n", 1]},
      {:pre_defined       => [2, "n", 1]},
      ],
    ]

    def lang2ascii(l)
      "#{((l>>10)|0x60).chr}#{(((l>>5)&31)|0x60).chr}#{((l&31)|0x60).chr}"
    end

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "creation_time     : #{Time.at(@creation_time-MAC2UNIX).strftime("%F %T %z")}"
      s += "\n " + " " * @depth + "modification_time : #{Time.at(@modification_time-MAC2UNIX).strftime("%F %T %z")}"
      s += "\n " + " " * @depth + "timescale         : #{@timescale}"
      s += "\n " + " " * @depth + "duration          : #{@duration}"
      s += "\n " + " " * @depth + "language          : #{lang2ascii(@language)}"
      s += "\n " + " " * @depth + "pre_defined       : #{@pre_defined}"
    end
  end

  class Box_hdlr < Box
    TEMPLATE = [
      # Version 0
      [
      {:pre_defined  => [4, "N" , 1   ]},
      {:handler_type => [4, "a*", 1   ]},
      {:reserved     => [4, "N" , 3   ]},
      {:name         => [:EOB, "Z*", 1]},
      ],
      # dummy
      [],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "pre_defined     : #{@pre_defined}"
      s += "\n " + " " * @depth + "handler_type    : #{@handler_type}"
      s += "\n " + " " * @depth + "reserved        : #{@reserved.map{|i| "0x#{i.to_s(16)}"}.join(',')}"
      s += "\n " + " " * @depth + "name            : #{@name}"
      s
    end
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

  class Box_meta < Box
    def parse_payload(f)
      parse_full_box(f)
      @payload = BaseMedia::parse_boxes(f, @size, @depth+1)
      @dirty   = false
    end
  end

  class Box_udta < Box_no_fields
  end


  class Box_moof < Box_no_fields
  end

  class Box_mvex < Box_no_fields
  end

  class Box_trex < Box
    TEMPLATE = [
      # Version 0
      [
      {:track_ID                 => [4, "N", 1]},
      {:default_sample_description_index => [4, "N", 1]},
      {:default_sample_duration  => [4, "N", 1]},
      {:default_sample_size      => [4, "N", 1]},
      {:default_sample_flags     => [4, "N", 1]},
      ],
      # dummy
      [
      {:track_ID          => [4, "N", 1]},
      ],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "track_ID                         : #{@track_ID}"
      s += "\n " + " " * @depth + "default_sample_description_index : #{@default_sample_description_index}"
      s += "\n " + " " * @depth + "default_sample_duration          : #{@default_sample_duration}"
      s += "\n " + " " * @depth + "default_sample_size              : #{@default_sample_size}"
      s += "\n " + " " * @depth + "default_sample_flags             : #{@default_sample_flags}"
    end
  end

  class Box_sidx < Box
    TEMPLATE = [
      # Version 0
      [
      {:reference_ID               => [4, "N", 1]},
      {:timescale                  => [4, "N", 1]},
      {:earliest_presentation_time => [4, "N", 1]},
      {:first_offset               => [4, "N", 1]},
      {:reserved                   => [2, "n", 1]},
      {:reference_count            => [2, "n", 1]},
      {:references                 => [4, "N*", :EOB]},
      ],
      # Version 1
      [
      {:reference_ID               => [4, "N", 1]},
      {:timescale                  => [4, "N", 1]},
      {:earliest_presentation_time => [4, :NN, 1]},
      {:first_offset               => [4, :NN, 1]},
      {:reserved                   => [2, "n", 1]},
      {:reference_count            => [2, "n", 1]},
      {:references                 => [4, "N*", :EOB]},
      ],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "reference_ID               : #{@reference_ID}"
      s += "\n " + " " * @depth + "timescale                  : #{@timescale}"
      s += "\n " + " " * @depth + "earliest_presentation_time : #{@earliest_presentation_time}"
      s += "\n " + " " * @depth + "first_offset               : #{@first_offset}"
      s += "\n " + " " * @depth + "reserved                   : #{@reserved}"
      s += "\n " + " " * @depth + "reference_count            : #{@reference_count}"
    end
  end

  class Box_mfhd < Box
    TEMPLATE = [
      # Version 0
      [
      {:sequence_number     => [4, "N", 1]},
      ],
      # dummy
      [
      {:sequence_number     => [4, "N", 1]},
      ],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "sequence_number : #{@sequence_number}"
    end
  end

  class Box_traf < Box_no_fields
  end

  class Box_tfhd < Box
    TEMPLATE = [
      # Version 0
      [
      {:track_ID                 => [4, "N", 1]},
      # all the following are optional fields
      #{:base_data_offset         => [8, :NN, 1]},
      #{:sample_description_index => [4, "N", 1]},
      {:default_sample_duration  => [4, "N", 1]},
      #{:default_sample_size      => [4, "N", 1]},
      #{:default_sample_flags     => [4, "N", 1]},
      ],
      # dummy
      [
      {:track_ID          => [4, "N", 1]},
      ],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "track_ID                : #{@track_ID}"
      s += "\n " + " " * @depth + "default_sample_duration : #{@default_sample_duration}"
    end
  end

  class Box_tfdt < Box
    TEMPLATE = [
      # Version 0
      [
      {:baseMediaDecodeTime => [4, "N", 1]},
      ],
      # Version 1
      [
      {:baseMediaDecodeTime => [8, :NN, 1]},
      ],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "baseMediaDecodeTime : #{@baseMediaDecodeTime}"
    end
  end

  class Box_trun < Box
    TEMPLATE = [
      # Version 0
      [
      {:sample_count => [4, "N", 1]},
      # the following are optional fields
      {:data_offset => [4, "N", 1]},
      #{:first_sample_flags => [4, "N", 1]},
      # all fields in the following array are optional
      {:samples => [4, "N*", :EOB]},
      ],
      # Version 1
      [
      {:sample_count => [4, "N", 1]},
      # the following are optional fields
      {:data_offset => [4, "N", 1]},
      #{:first_sample_flags => [4, "N", 1]},
      # all fields in the following array are optional
      {:samples => [4, "N*", :EOB]},
      ],
    ]

    def fields_to_s(s)
      s += "\n " + " " * @depth + "FullBox version : #{@version}"
      s += "\n " + " " * @depth + "FullBox flags   : #{@flags.join(', ')}"
      s += "\n " + " " * @depth + "sample_count : #{@sample_count}"
      s += "\n " + " " * @depth + "data_offset  : 0x#{@data_offset.to_s(16)}"
    end
  end

end # module BaseMedia
