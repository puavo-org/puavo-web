# frozen_string_literal: true

module Mountpoint
  attr_accessor :fs, :path, :mountpoint, :options

  def fs
    @fs = parse_mountpoint('fs') if @fs.nil?
    @fs
  end

  def path
    @path = parse_mountpoint('path') if @path.nil?
    @path
  end

  def mountpoint
    @mountpoint = parse_mountpoint('mountpoint') if @mountpoint.nil?
    @mountpoint
  end

  def options
    @options = parse_mountpoint('options') if @options.nil?
    @options
  end

  def puavoMountpoint=(args)
    # Reset cache
    @fs = nil
    @path = nil
    @mountpoint = nil
    @options = nil

    set_attribute('puavoMountpoint', args)
  end

  private

  def parse_mountpoint(field)
    Array(self.puavoMountpoint).map do |mount|
      JSON.parse(mount)[field]
    end
  end

  def set_puavo_mountpoint
    new_mountpoint_values = []

    self.fs.each_index do |index|
      next if fs[index].empty? && path[index].empty? && mountpoint[index].empty? && options[index].empty?

      new_mountpoint_values.push(
        {
          'fs' => fs[index],
          'path' => path[index],
          'mountpoint' => mountpoint[index],
          'options' => options[index]
        }.to_json
      )
    end

    self.puavoMountpoint = new_mountpoint_values
  end
end
