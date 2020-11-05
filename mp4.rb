class Mp4File

  require_relative './isobmff'
  include BaseMedia

  # alias
  def boxes() @root.boxes end
  def to_s() @root.to_s end

  def initialize(f, size)
    @root = BaseMedia::Box_no_fields.new('_root')
    @root.parse(f, size, -1)
  end

end # class Mp4File
