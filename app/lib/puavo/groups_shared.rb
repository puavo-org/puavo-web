# Shared stuff between GroupsController and GroupMassOperationsController

module Puavo
  module GroupsShared
    # Changes the group's type
    def self.set_type(group, type)
      group.puavoEduGroupType = type
      group.save!
      true
    rescue StandardError => e
      false
    end

    # Remove all users from a group (don't delete them, just remove them from the group)
    def self.remove_all_members(group)
      members = group.members
      ok = true

      members.each do |m|
        begin
          group.remove_user(m)
        rescue StandardError => e
          puts "===> Could not remove member #{m.uid} from group #{group.cn}: #{e}"
          ok = false
        end
      end

      ok
    end

    # Lock or unlock members
    def self.lock_members(group, lock)
      count = 0

      group.members.each do |u|
        begin
          if lock
            # Lock
            unless u.puavoLocked
              u.puavoLocked = true
              u.save
              count += 1
            end
          else
            # Unlock
            if u.puavoLocked
              u.puavoLocked = nil
              u.save
              count += 1
            end
          end
        rescue StandardError => e
          puts "====> Could not lock/unlock group member #{u.uid} in group #{group.cn}: #{e}"
        end
      end

      return count
    end

    # Mark (or unmark) group members for deletion. Returns the number of users updated.
    def self.mark_members_for_deletion(group, mark)
      now = Time.now.utc
      count = 0

      group.members.each do |u|
        begin
          if mark
            # Mark for deletion
            if u.puavoRemovalRequestTime.nil?
              u.puavoRemovalRequestTime = now
              u.puavoLocked = true
              u.save
              count += 1
            end
          else
            # Remove deletion mark
            if u.puavoRemovalRequestTime
              u.puavoRemovalRequestTime = nil
              u.save
              count += 1
            end
          end
        rescue StandardError => e
          puts "====> Could not mark/unmark group member #{u.uid} from group #{group.cn}: #{e}"
        end
      end

      return count
    end
  end
end
