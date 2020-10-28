class Mp4File

  require_relative './isobmff'
  include BaseMedia

  def boxes() @root.boxes end # alias

  def initialize(f, size)
    @root = BaseMedia::Box_no_fields.new('_root')
    @root.parse(f, size, -1)
  end

  def to_s
    s = ''
    @root.payload.each do |b|
      s += "#{b.to_s}\n"
    end
    s
  end

end # class Mp4File
