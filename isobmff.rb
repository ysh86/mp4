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
    attr_reader :dirty

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
        t.values[0].push(box_offset) # TODO: これダメ。[0][3] 固定でいい？バージョン混ざるとダメか。

        if field_size == :EOB
          field_size = @size - box_offset
        end
        shall_be_array = false
        if field_num == :EOB
          field_num = (@size - box_offset) / field_size
          shall_be_array = true
        end

        field = nil
        if field_num == 1 && !shall_be_array
          case field_type
          when :NN
            # network byte order unsigned 64bit
            fields = f.read(field_size).unpack("N2")
            field = (fields[0] << 32) + fields[1]
            box_offset += field_size
          when :NNq
            # network byte order signed 64bit
            fields = f.read(field_size).unpack("N2")
            field = ((fields[0] << 32) + fields[1]).pack("q").unpack("q")[0]
            box_offset += field_size
          when :Nl
            # network byte order signed 32bit
            field = f.read(field_size).unpack("N").pack("l").unpack("l")[0]
            box_offset += field_size
          when :ns
            # network byte order signed 16bit
            field = f.read(field_size).unpack("n").pack("s").unpack("s")[0]
            box_offset += field_size
          else
            field = f.read(field_size).unpack(field_type)[0]
            box_offset += field_size
          end
        else
          field = Array.new(field_num)
          field_num.times do |i|
            field[i] = f.read(field_size).unpack(field_type)[0]
            box_offset += field_size
          end
        end

        self.instance_variable_set("@#{field_sym.to_s}", field)
        self.class.send(:attr_reader, field_sym)
      end

      f.seek(@size - box_offset, IO::SEEK_CUR)
      @dirty   = false
    end

    def parse_full_box(f)
      @version = f.read(1).unpack("C")[0]
      @flags   = f.read(3).unpack("C3")

      @size   = @size - 4
      @offset = @offset + 4
    end

    def header_to_s(s)
      if @depth >= 0
        s << ' ' * @depth << ((self.class == Box) ? '?' : '') << "#{@type} : #{@size}, 0x#{@offset.to_s(16)}, #{@dirty}"
      else
        s << "#{@type} : #{@size}"
      end
      s << "\n"
    end

    def fields_to_s(s)
      # do nothing
    end

    def payload_to_s(s)
      if @payload.class == Array
        @payload.each do |b|
          b.box_to_s(s)
        end
      end
    end

    def box_to_s(s)
      header_to_s(s)
      fields_to_s(s)
      payload_to_s(s)
    end

    def to_s
      s = ''
      box_to_s(s)
      s
    end
  end

  class Box_no_fields < Box
    attr_reader :payload, :boxes
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
      s << " " * (1 + @depth) << "major_brand       : #{@major_brand}" << "\n"
      s << " " * (1 + @depth) << "minor_version     : #{@minor_version}" << "\n"
      @compatible_brands.each do |i|
        s << " " * (1 + @depth) << "compatible_brands : #{i}" << "\n"
      end
    end
  end

  class Box_mdat < Box
    def parse_payload(f)
      f.seek(@size, IO::SEEK_CUR)
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
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "creation_time     : #{Time.at(@creation_time-MAC2UNIX).strftime("%F %T %z")}" << "\n"
      s << " " * (1 + @depth) << "modification_time : #{Time.at(@modification_time-MAC2UNIX).strftime("%F %T %z")}" << "\n"
      s << " " * (1 + @depth) << "timescale         : #{@timescale}" << "\n"
      s << " " * (1 + @depth) << "duration          : #{@duration}" << "\n"
      s << " " * (1 + @depth) << "rate              : 0x#{@rate.to_s(16)}" << "\n"
      s << " " * (1 + @depth) << "volume            : 0x#{@volume.to_s(16)}" << "\n"
      s << " " * (1 + @depth) << "reserved16        : #{@reserved16}" << "\n"
      s << " " * (1 + @depth) << "reserved32        : #{@reserved32.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "matrix            : #{@matrix.map{|i| "0x#{i.to_s(16)}"}.join(',')}" << "\n"
      s << " " * (1 + @depth) << "pre_defined       : #{@pre_defined.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "next_track_ID     : #{@next_track_ID}" << "\n"
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
      {:layer             => [2, :ns, 1]},
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
      {:layer             => [2, :ns, 1]},
      {:alternate_group   => [2, "n", 1]},
      {:volume            => [2, "n", 1]},
      {:reserved16        => [2, "n", 1]},
      {:matrix            => [4, "N", 9]},
      {:width             => [4, "N", 1]},
      {:height            => [4, "N", 1]},
      ],
    ]

    def fields_to_s(s)
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "creation_time     : #{Time.at(@creation_time-MAC2UNIX).strftime("%F %T %z")}" << "\n"
      s << " " * (1 + @depth) << "modification_time : #{Time.at(@modification_time-MAC2UNIX).strftime("%F %T %z")}" << "\n"
      s << " " * (1 + @depth) << "track_ID          : #{@track_ID}" << "\n"
      s << " " * (1 + @depth) << "reserved          : #{@reserved}" << "\n"
      s << " " * (1 + @depth) << "duration          : #{@duration}" << "\n"
      s << " " * (1 + @depth) << "reserved32        : #{@reserved32.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "layer             : #{@layer}" << "\n"
      s << " " * (1 + @depth) << "alternate_group   : #{@alternate_group}" << "\n"
      s << " " * (1 + @depth) << "volume            : 0x#{@volume.to_s(16)}" << "\n"
      s << " " * (1 + @depth) << "reserved16        : #{@reserved16}" << "\n"
      s << " " * (1 + @depth) << "matrix            : #{@matrix.map{|i| "0x#{i.to_s(16)}"}.join(',')}" << "\n"
      s << " " * (1 + @depth) << "width             : #{@width /65536.0}" << "\n"
      s << " " * (1 + @depth) << "height            : #{@height/65536.0}" << "\n"
    end
  end

  class Box_edts < Box_no_fields
  end

  class Box_elst < Box
    TEMPLATE = [
      # Version 0
      [
      {:entry_count         => [4, "N", 1]},
      {:segment_duration    => [4, "N", 1]},
      {:media_time          => [4, :Nl, 1]},
      {:media_rate_integer  => [2, "n", 1]},
      {:media_rate_fraction => [2, "n", 1]},
      {:entries             => [1, "C", :EOB]},
      ],
      # Version 1
      [
      {:entry_count         => [4, "N", 1]},
      {:segment_duration    => [8, :NN, 1]},
      {:media_time          => [8, :NNq, 1]},
      {:media_rate_integer  => [2, "n", 1]},
      {:media_rate_fraction => [2, "n", 1]},
      {:entries             => [1, "C", :EOB]},
      ],
    ]

    def fields_to_s(s)
      i = 0
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "entry_count     : #{@entry_count}" << "\n"
      s << " " * (1 + @depth) << "[#{i}] segment_duration    : #{@segment_duration}" << "\n"
      s << " " * (1 + @depth) << "[#{i}] media_time          : #{@media_time}" << "\n"
      s << " " * (1 + @depth) << "[#{i}] media_rate_integer  : #{@media_rate_integer}" << "\n"
      s << " " * (1 + @depth) << "[#{i}] media_rate_fraction : #{@media_rate_fraction}" << "\n"

      p = 0
      for i in 1...@entry_count
        if @version == 1
          fields = @entries[p...p+8].pack("C*").unpack("N2")
          segment_duration = (fields[0] << 32) + fields[1]
          p += 8
          fields = @entries[p...p+8].pack("C*").unpack("N2")
          media_time = ((fields[0] << 32) + fields[1]).pack("q").unpack("q")[0]
          p += 8
        else
          segment_duration = @entries[p...p+4].pack("C*").unpack("N")[0]
          p += 4
          media_time = @entries[p...p+4].pack("C*").unpack("N").pack("l").unpack("l")[0]
          p += 4
        end
        media_rate_integer = @entries[p...p+2].pack("C*").unpack("n")[0]
        media_rate_fraction = @entries[p+2...p+4].pack("C*").unpack("n")[0]
        p += 4

        s << " " * (1 + @depth) << "[#{i}] segment_duration    : #{segment_duration}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] media_time          : #{media_time}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] media_rate_integer  : #{media_rate_integer}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] media_rate_fraction : #{media_rate_fraction}" << "\n"
      end
    end
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
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "creation_time     : #{Time.at(@creation_time-MAC2UNIX).strftime("%F %T %z")}" << "\n"
      s << " " * (1 + @depth) << "modification_time : #{Time.at(@modification_time-MAC2UNIX).strftime("%F %T %z")}" << "\n"
      s << " " * (1 + @depth) << "timescale         : #{@timescale}" << "\n"
      s << " " * (1 + @depth) << "duration          : #{@duration}" << "\n"
      s << " " * (1 + @depth) << "language          : #{lang2ascii(@language)}" << "\n"
      s << " " * (1 + @depth) << "pre_defined       : #{@pre_defined}" << "\n"
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
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "pre_defined     : #{@pre_defined}" << "\n"
      s << " " * (1 + @depth) << "handler_type    : #{@handler_type}" << "\n"
      s << " " * (1 + @depth) << "reserved        : #{@reserved.map{|i| "0x#{i.to_s(16)}"}.join(',')}" << "\n"
      s << " " * (1 + @depth) << "name            : #{@name}" << "\n"
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

  # TODO: meta
  class Box_metaa < Box_no_fields
    def parse_payload(f)
      parse_full_box(f)
      super(f)
    end
  end
  # TODO: udta
  class Box_udtaa < Box_no_fields
  end


  class Box_styp < Box_ftyp
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
      {:references                 => [4*3, "N3", :EOB]},
      ],
      # Version 1
      [
      {:reference_ID               => [4, "N", 1]},
      {:timescale                  => [4, "N", 1]},
      {:earliest_presentation_time => [8, :NN, 1]},
      {:first_offset               => [8, :NN, 1]},
      {:reserved                   => [2, "n", 1]},
      {:reference_count            => [2, "n", 1]},
      {:references                 => [4, "N", :EOB]},
      ],
    ]

    def fields_to_s(s)
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "reference_ID               : #{@reference_ID}" << "\n"
      s << " " * (1 + @depth) << "timescale                  : #{@timescale}" << "\n"
      s << " " * (1 + @depth) << "earliest_presentation_time : #{@earliest_presentation_time}" << "\n"
      s << " " * (1 + @depth) << "first_offset               : #{@first_offset}" << "\n"
      s << " " * (1 + @depth) << "reserved                   : #{@reserved}" << "\n"
      s << " " * (1 + @depth) << "reference_count            : #{@reference_count}" << "\n"
      for i in 0...@reference_count
        reference_type = @references[i*3+0] >> 31
        referenced_size = @references[i*3+0] & 0x7fffffff
        subsegment_duration = @references[i*3+1]
        starts_with_sap = @references[i*3+2] >> 31
        sap_type = (@references[i*3+2] >> 28) & 7
        sap_delta_time = @references[i*3+2] & 0x0fffffff

        s << " " * (1 + @depth) << "[#{i}] reference_type      : #{reference_type}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] referenced_size     : #{referenced_size}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] subsegment_duration : #{subsegment_duration}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] starts_with_SAP     : #{starts_with_sap}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] SAP_type            : #{sap_type}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] SAP_delta_time      : #{sap_delta_time}" << "\n"
      end
    end
  end

  class Box_moof < Box_no_fields
  end

  class Box_mvex < Box_no_fields
  end

  class Box_mehd < Box
    TEMPLATE = [
      # Version 0
      [
      {:fragment_duration => [4, "N", 1]},
      ],
      # Version 1
      [
      {:fragment_duration => [8, :NN, 1]},
      ],
    ]

    def fields_to_s(s)
      s << " " * (1 + @depth) << "fragment_duration : #{@fragment_duration}" << "\n"
    end
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
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "track_ID                         : #{@track_ID}" << "\n"
      s << " " * (1 + @depth) << "default_sample_description_index : #{@default_sample_description_index}" << "\n"
      s << " " * (1 + @depth) << "default_sample_duration          : #{@default_sample_duration}" << "\n"
      s << " " * (1 + @depth) << "default_sample_size              : #{@default_sample_size}" << "\n"
      s << " " * (1 + @depth) << "default_sample_flags             : #{sprintf("0x%08x",@default_sample_flags)}" << "\n"
      s << " " * (1 + @depth) << "  is_leading                     : #{(@default_sample_flags>>26)&3}" << "\n"
      s << " " * (1 + @depth) << "  sample_depends_on              : #{(@default_sample_flags>>24)&3}" << "\n"
      s << " " * (1 + @depth) << "  sample_is_depended_on          : #{(@default_sample_flags>>22)&3}" << "\n"
      s << " " * (1 + @depth) << "  sample_has_redundancy          : #{(@default_sample_flags>>20)&3}" << "\n"
      s << " " * (1 + @depth) << "  sample_padding_value           : #{(@default_sample_flags>>17)&7}" << "\n"
      s << " " * (1 + @depth) << "  sample_is_non_sync_sample      : #{(@default_sample_flags>>16)&1}" << "\n"
      s << " " * (1 + @depth) << "  sample_degradation_priority    : #{@default_sample_flags&0xffff}" << "\n"
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
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "sequence_number : #{@sequence_number}" << "\n"
    end
  end

  class Box_traf < Box_no_fields
  end

  class Box_tfhd < Box
    TEMPLATE = [
      # Version 0
      [
      {:track_ID                 => [4, "N", 1]},
      {:optional_fields          => [1, "C", :EOB]},
      # all the following are optional fields
      #{:base_data_offset         => [8, :NN, 1]},
      #{:sample_description_index => [4, "N", 1]},
      #{:default_sample_duration  => [4, "N", 1]},
      #{:default_sample_size      => [4, "N", 1]},
      #{:default_sample_flags     => [4, "N", 1]},
      ],
      # dummy
      [
      {:track_ID          => [4, "N", 1]},
      ],
    ]

    def fields_to_s(s)
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "track_ID                 : #{@track_ID}" << "\n"

      p = 0
      if (@flags[2] & 0x01) != 0
        fields = @optional_fields[p...p+8].pack("C*").unpack("N2")
        base_data_offset = (fields[0] << 32) + fields[1]
        p += 8
        s << " " * (1 + @depth) << "base_data_offset         : #{base_data_offset}" << "\n"
      end
      if (@flags[2] & 0x02) != 0
        sample_description_index = @optional_fields[p...p+4].pack("C*").unpack("N")[0]
        p += 4
        s << " " * (1 + @depth) << "sample_description_index : #{sample_description_index}" << "\n"
      end
      if (@flags[2] & 0x08) != 0
        default_sample_duration = @optional_fields[p...p+4].pack("C*").unpack("N")[0]
        p += 4
        s << " " * (1 + @depth) << "default_sample_duration  : #{default_sample_duration}" << "\n"
      end
      if (@flags[2] & 0x10) != 0
        default_sample_size = @optional_fields[p...p+4].pack("C*").unpack("N")[0]
        p += 4
        s << " " * (1 + @depth) << "default_sample_size      : #{default_sample_size}" << "\n"
      end
      if (@flags[2] & 0x20) != 0
        default_sample_flags = @optional_fields[p...p+4].pack("C*").unpack("N")[0]
        p += 4
        s << " " * (1 + @depth) << "default_sample_flags     : #{sprintf("0x%08x",default_sample_flags)}" << "\n"
        s << " " * (1 + @depth) << "  is_leading                     : #{(default_sample_flags>>26)&3}" << "\n"
        s << " " * (1 + @depth) << "  sample_depends_on              : #{(default_sample_flags>>24)&3}" << "\n"
        s << " " * (1 + @depth) << "  sample_is_depended_on          : #{(default_sample_flags>>22)&3}" << "\n"
        s << " " * (1 + @depth) << "  sample_has_redundancy          : #{(default_sample_flags>>20)&3}" << "\n"
        s << " " * (1 + @depth) << "  sample_padding_value           : #{(default_sample_flags>>17)&7}" << "\n"
        s << " " * (1 + @depth) << "  sample_is_non_sync_sample      : #{(default_sample_flags>>16)&1}" << "\n"
        s << " " * (1 + @depth) << "  sample_degradation_priority    : #{default_sample_flags&0xffff}" << "\n"
        end
      if (@flags[0] & 0x01) != 0
        s << " " * (1 + @depth) << "duration-is-empty" << "\n"
      end
      if (@flags[0] & 0x02) != 0
        s << " " * (1 + @depth) << "default-base-is-moof" << "\n"
      end
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
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "baseMediaDecodeTime : #{@baseMediaDecodeTime}" << "\n"
    end
  end

  class Box_trun < Box
    TEMPLATE = [
      # Version 0
      [
      {:sample_count => [4, "N", 1]},
      # the following are optional fields
      #{:data_offset => [4, :Nl, 1]},
      #{:first_sample_flags => [4, "N", 1]},
      # all fields in the following array are optional
      {:samples => [4, "N", :EOB]},
      ],
      # Version 1
      [
      {:sample_count => [4, "N", 1]},
      # the following are optional fields
      #{:data_offset => [4, :Nl, 1]},
      #{:first_sample_flags => [4, "N", 1]},
      # all fields in the following array are optional
      {:samples => [4, "N", :EOB]},
      ],
    ]

    def fields_to_s(s)
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "sample_count       : #{@sample_count}" << "\n"

      p = 0
      if (@flags[2] & 0x01) != 0
        data_offset = @samples[p...p+1].pack("l").unpack("l")[0]
        p += 1
        s << " " * (1 + @depth) << "data_offset        : #{data_offset}" << "\n"
      end
      if (@flags[2] & 0x04) != 0
        first_sample_flags = @samples[p]
        p += 1
        s << " " * (1 + @depth) << "first_sample_flags : #{sprintf("0x%08x",first_sample_flags)}" << "\n"
        s << " " * (1 + @depth) << "  is_leading                     : #{(first_sample_flags>>26)&3}" << "\n"
        s << " " * (1 + @depth) << "  sample_depends_on              : #{(first_sample_flags>>24)&3}" << "\n"
        s << " " * (1 + @depth) << "  sample_is_depended_on          : #{(first_sample_flags>>22)&3}" << "\n"
        s << " " * (1 + @depth) << "  sample_has_redundancy          : #{(first_sample_flags>>20)&3}" << "\n"
        s << " " * (1 + @depth) << "  sample_padding_value           : #{(first_sample_flags>>17)&7}" << "\n"
        s << " " * (1 + @depth) << "  sample_is_non_sync_sample      : #{(first_sample_flags>>16)&1}" << "\n"
        s << " " * (1 + @depth) << "  sample_degradation_priority    : #{first_sample_flags&0xffff}" << "\n"
      end

      @sample_count.times do |i|
        if (@flags[1] & 0x01) != 0
          sample_duration = @samples[p]
          p += 1
        else
          sample_duration = 'default'
        end
        if (@flags[1] & 0x02) != 0
          sample_size = @samples[p]
          p += 1
        else
          sample_size = 'default'
        end
        if (@flags[1] & 0x04) != 0
          sample_flags = sprintf("0x%08x",@samples[p])
          p += 1
        else
          sample_flags = 'default'
        end
        if (@flags[1] & 0x08) != 0
          if @version == 0
            sample_composition_time_offset = @samples[p]
          else
            sample_composition_time_offset = @samples[p...p+1].pack("l").unpack("l")[0]
          end
          p += 1
        else
          sample_composition_time_offset = 'default'
        end
        s << " " * (1 + @depth) << "[#{i}] #{sample_duration},#{sample_size},#{sample_flags},#{sample_composition_time_offset}" << "\n"
      end
    end
  end

  class Box_mfra < Box_no_fields
  end

  class Box_tfra < Box
    TEMPLATE = [
      # Version 0
      [
      {:track_ID               => [4, "N", 1]},
      {:length_size            => [4, "N", 1]},
      {:number_of_entry        => [4, "N", 1]},
      {:entries                => [1, "C", :EOB]},
      ],
      # Version 1
      [
      {:track_ID               => [4, "N", 1]},
      {:length_size            => [4, "N", 1]},
      {:number_of_entry        => [4, "N", 1]},
      {:entries                => [1, "C", :EOB]},
      ],
    ]

    def fields_to_s(s)
      size_of_traf_num = (@length_size >> 4) & 3
      size_of_trun_num = (@length_size >> 2) & 3
      size_of_sample_num = (@length_size & 3)

      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "track_ID        : #{@track_ID}" << "\n"
      s << " " * (1 + @depth) << "size_of_traf_num   : #{size_of_traf_num}" << "\n"
      s << " " * (1 + @depth) << "size_of_trun_num   : #{size_of_trun_num}" << "\n"
      s << " " * (1 + @depth) << "size_of_sample_num : #{size_of_sample_num}" << "\n"
      s << " " * (1 + @depth) << "number_of_entry    : #{@number_of_entry}" << "\n"

      p = 0
      for i in 0...@number_of_entry
        if @version == 1
          fields = @entries[p...p+8].pack("C*").unpack("N2")
          pts_in_media_timescale = (fields[0] << 32) + fields[1]
          p += 8
          fields = @entries[p...p+8].pack("C*").unpack("N2")
          moof_offset = (fields[0] << 32) + fields[1]
          p += 8
        else
          pts_in_media_timescale = @entries[p...p+4].pack("C*").unpack("N")[0]
          p += 4
          moof_offset = @entries[p...p+4].pack("C*").unpack("N")[0]
          p += 4
        end

        traf_number = @entries[p]
        p += 1
        for i in 0...size_of_traf_num
          traf_number = (traf_number << 8) + @entries[p]
          p += 1
        end

        trun_number = @entries[p]
        p += 1
        for i in 0...size_of_trun_num
          trun_number = (trun_number << 8) + @entries[p]
          p += 1
        end

        sample_delta = @entries[p]
        p += 1
        for i in 0...size_of_sample_num
          sample_delta = (sample_delta << 8) + @entries[p]
          p += 1
        end

        s << " " * (1 + @depth) << "[#{i}] time(sync pts)        : #{pts_in_media_timescale}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] moof_offset           : #{moof_offset}" << "\n"
        s << " " * (1 + @depth) << "[#{i}] traf,trun,sample_delta: #{traf_number},#{trun_number},#{sample_delta}" << "\n"
      end
    end
  end

  class Box_mfro < Box
    TEMPLATE = [
      # Version 0
      [
      {:parent_size     => [4, "N", 1]},
      ],
      # dummy
      [
      {:parent_size     => [4, "N", 1]},
      ],
    ]

    def fields_to_s(s)
      s << " " * (1 + @depth) << "FullBox version : #{@version}" << "\n"
      s << " " * (1 + @depth) << "FullBox flags   : #{@flags.join(', ')}" << "\n"
      s << " " * (1 + @depth) << "parent_size     : #{@parent_size}" << "\n"
    end
  end

end # module BaseMedia
