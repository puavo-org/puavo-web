module Mountpoint
  attr_accessor :fs

  def fs
    if @fs.nil?
      @fs = parse_mountpoint("fs")
    end
    @fs
  end

  private

  def parse_mountpoint(field)
    Array(self.puavoMountpoint).map do |mount|
      JSON.parse(mount)[field]
    end

  end

  def set_puavo_mountpoint
    self.fs.each_index do |index|
      self.puavoMountpoint = Array(self.puavoMountpoint) + [{ "fs" => fs[index] }.to_json]
    end
  end
end
