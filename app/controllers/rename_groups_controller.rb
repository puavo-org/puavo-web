class GroupsNotFound < StandardError; end

class RenameGroupsController < ApplicationController

  def new
    begin
      # Detect class range
      @groups = @school.groups.select do |g|
        g.displayName.match(/\d+/) && !g.displayName.match(/poistuvat/)
      end.sort do |a,b|
        a.displayName <=> b.displayName
      end

      unless @groups.empty?
        @group_class_numbers = @groups.map{ |g| g.displayName.match(/\d+/)[0].to_i }
        @first_group_class_number = @group_class_numbers.min
        @last_group_class_number = @group_class_numbers.max

        if (@last_group_class_number - @first_group_class_number + 1) == @group_class_numbers.uniq.count
          @all_group_class_found = true
        else
          @all_group_class_found = false
        end

        @first_class_groups = @groups.select{ |r| r.displayName.match(/\d+/)[0].to_i == @first_group_class_number }

        # pre-check the new abbreviations
        @new_group_name_already_used = false

        @first_class_groups.each do |g|
          new_name = increase_numeric_value_of_string(g.cn)

          unless Group.all.select{|g| g.cn == new_name }.empty?
            @new_group_name_already_used = true
          end
        end
      end

      raise GroupsNotFound if @groups.empty?
    rescue GroupsNotFound
      flash[:alert] = t('flash.school.no_groups')
      redirect_to school_path(@school)
    end
  end

  def create
    # don't duplicate group abbreviations
    Array(params[:new_groups_cn] || []).each do |new_cn|
      unless Group.all.select{|g| g.cn == new_cn.to_s }.empty?
        flash[:alert] = t('flash.rename_groups.abbreviation_already_in_use')
        redirect_to new_rename_groups_path(@school)
        return
      end
    end

    num_groups_renamed = 0

    params[:group_display_name]&.each_index do |index|
      unless params[:group_display_name][index].empty?
        group = Group.find(params[:group_puavo_id][index])
        group.displayName = params[:group_display_name][index]
        group.save!
        num_groups_renamed += 1
      end
    end

    params[:new_groups_cn]&.each_index do |index|
      if !params[:new_groups_display_name][index].empty? && !params[:new_groups_cn][index].empty?
        g = Group.new(:displayName => params[:new_groups_display_name][index],
                      :cn => params[:new_groups_cn][index],
                      :puavoSchool => @school.dn,
                      :puavoEduGroupType => "teaching group")
        g.save!
      end
    end

    flash[:notice] = t('flash.rename_groups.complete', :count => num_groups_renamed)

    respond_to do |format|
      format.html { redirect_to( school_path(@school) ) }
    end
  end

  private
    # this exists in view helpers, but of course it's not usable here
    # without copy-pasting it...
    def increase_numeric_value_of_string(value)
      match_data = value.match(/\d+/)
      return value + "1" if match_data.nil?
      number_length = match_data[0].length
      number = match_data[0].to_i + 1
      return value.sub(/\d+/, ("%0#{number_length}d" % number))
    end
end
