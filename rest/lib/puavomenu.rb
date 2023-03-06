# Generates the per-device Puavomenu menudata for the computed "puavomenu" attribute

require 'json'

module Puavo
  module Puavomenu
    def self.generate_puavomenu_data(device)
      organisation = device.organisation.puavomenu_data.nil? ? {} : JSON.parse(device.organisation.puavomenu_data)
      school = device.school.puavomenu_data.nil? ? {} : JSON.parse(device.school.puavomenu_data)
      device = device.puavomenu_data.nil? ? {} : JSON.parse(device.puavomenu_data)

      final = {}

      # Merge programs
      programs = {}

      organisation.fetch('programs', {}).each do |pid, src|
        programs[pid] = merge_hashes(src, {})
      end

      school.fetch('programs', {}).each do |pid, src|
        programs[pid] = merge_hashes(src, programs.fetch(pid, {}))
      end

      device.fetch('programs', {}).each do |pid, src|
        programs[pid] = merge_hashes(src, programs.fetch(pid, {}))
      end

      final['programs'] = programs unless programs.empty?

      # Merge menus
      menus = {}

      organisation.fetch('menus', {}).each do |mid, src|
        menus[mid] = merge_hashes(src, {})
      end

      school.fetch('menus', {}).each do |mid, src|
        menus[mid] = merge_hashes(src, menus.fetch(mid, {}))
      end

      device.fetch('menus', {}).each do |mid, src|
        menus[mid] = merge_hashes(src, menus.fetch(mid, {}))
      end

      final['menus'] = menus unless menus.empty?

      # Merge categories
      categories = {}

      organisation.fetch('categories', {}).each do |cid, src|
        categories[cid] = merge_hashes(src, {})
      end

      school.fetch('categories', {}).each do |cid, src|
        categories[cid] = merge_hashes(src, categories.fetch(cid, {}))
      end

      device.fetch('categories', {}).each do |cid, src|
        categories[cid] = merge_hashes(src, categories.fetch(cid, {}))
      end

      final['categories'] = categories unless categories.empty?

      final
    end

    # A more intelligent version of plain Hash.merge. Allows values to be removed,
    # skips nil values, and supports "partial" merges when the value actually is
    # a hash.
    def self.merge_hashes(src, dst)
      src.each do |key, value|
        if !dst.include?(key) && !value.nil?
          # New non-nil value
          dst[key] = value
        elsif value.nil?
          # Delete
          dst.delete(key)
        else
          # Update/merge existing
          if value.is_a?(Hash) && dst[key].is_a?(Hash)
            # Single-level hash merging is enough for us, as the only place where we merge
            # hashes are with translation strings and those only go one level deep
            dst[key].merge!(value).compact!
          else
            dst[key] = value
          end
        end
      end

      dst
    end
  end
end
