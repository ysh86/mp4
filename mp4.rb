class Mp4File

  require_relative './isobmff'
  include BaseMedia

  attr_reader :payload
  attr_reader :boxes

  def initialize(f, size)
    @payload = BaseMedia::parse_boxes(f, size)
    @boxes = {}
    @payload.each do |b|
      @boxes[b.type.to_sym] = b
    end
  end

  def to_s
    s = ''
    @payload.each do |b|
      s += "#{b.to_s}\n"
    end
    s
  end

  class BaseMedia::Box_udta < BaseMedia::Box_no_fields
  end

end # class Mp4File
