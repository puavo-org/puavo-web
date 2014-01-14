module Mountpoint
  attr_accessor :fs, :path, :mountpoint, :options

  def fs
    if @fs.nil?
      @fs = parse_mountpoint("fs")
    end
    @fs
  end

  def path
    if @path.nil?
      @path = parse_mountpoint("path")
    end
    @path
  end

  def mountpoint
    if @mountpoint.nil?
      @mountpoint = parse_mountpoint("mountpoint")
    end
    @mountpoint
  end

  def options
    if @options.nil?
      @options = parse_mountpoint("options")
    end
    @options
  end

  private

  def parse_mountpoint(field)
    Array(self.puavoMountpoint).map do |mount|
      JSON.parse(mount)[field]
    end

  end

  def set_puavo_mountpoint
    self.fs.each_index do |index|
      self.puavoMountpoint = Array(self.puavoMountpoint) +
        [{ "fs" => fs[index],
           "path" => path[index],
           "mountpoint" => mountpoint[index],
           "options" => options[index] }.to_json]
    end
  end
end
