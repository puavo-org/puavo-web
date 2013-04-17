class RolesNotFound < StandardError; end

class RenameGroupsController < ApplicationController

  def new
    begin
      # Detect class range
      @roles = @school.roles.select do |r|
        r.displayName.match(/\d+/) && !r.displayName.match(/poistuvat/)
      end.sort do |a,b|
        a.displayName <=> b.displayName
      end

      raise RolesNotFound if @roles.empty?
      
      @class_numbers = @roles.map{ |r| r.displayName.match(/\d+/)[0].to_i }
      
      @first_class_number = @class_numbers.min
      
      @last_class_number = @class_numbers.max
      
      if (@last_class_number - @first_class_number + 1) == @class_numbers.uniq.count
        @all_class_found = true
      else
        @all_class_found = false
      end
      
      @first_class_roles = @roles.select{ |r| r.displayName.match(/\d+/)[0].to_i == @first_class_number }
      
      @groups = @school.groups.select do |g|
        g.displayName.match(/\d+/) && !g.displayName.match(/poistuvat/)
      end.sort do |a,b|
        a.displayName <=> b.displayName
      end
      
      @group_class_numbers = @groups.map{ |g| g.displayName.match(/\d+/)[0].to_i }
      @first_group_class_number = @group_class_numbers.min
      @last_group_class_number = @group_class_numbers.max
      
      @first_class_groups = @groups.select{ |r| r.displayName.match(/\d+/)[0].to_i == @first_group_class_number }
    rescue RolesNotFound
      flash[:alert] = t('flash.school.roles_not_found')
      redirect_to school_path(@school)
    end
  end

  def create
    params[:role_display_name].each_index do |index|
      unless params[:role_display_name][index].empty?
        role = Role.find(params[:role_puavo_id][index])
        role.displayName = params[:role_display_name][index]
        role.save!
      end
    end

    params[:new_roles].each do |role_name|
      unless role_name.empty?
        r = Role.new(:displayName => role_name,
                     :puavoSchool => @school.dn )
        r.save!
      end
    end

    params[:group_display_name].each_index do |index|
      unless params[:group_display_name][index].empty?
        group = Group.find(params[:group_puavo_id][index])
        group.displayName = params[:group_display_name][index]
        group.save!
      end
    end

    params[:new_groups_cn].each_index do |index|
      if !params[:new_groups_display_name][index].empty? && !params[:new_groups_cn][index].empty?
        g = Group.new(:displayName => params[:new_groups_display_name][index],
                      :cn => params[:new_groups_cn][index],
                      :puavoSchool => @school.dn )
        g.save!
      end
    end

    respond_to do |format|
      format.html { redirect_to( roles_path(@school) ) }
    end
  end
end
