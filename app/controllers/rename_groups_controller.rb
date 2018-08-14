class RolesNotFound < StandardError; end

class RenameGroupsController < ApplicationController

  def new
    begin
      @do_only_groups = new_group_management?(@school)

      # Detect class range
      @roles = []

      if !@do_only_groups
        @roles = @school.roles.select do |r|
          r.displayName.match(/\d+/) && !r.displayName.match(/poistuvat/)
        end.sort do |a,b|
          a.displayName <=> b.displayName
        end
      end

      unless @roles.empty?
        @class_numbers = @roles.map{ |r| r.displayName.match(/\d+/)[0].to_i }
        @first_class_number = @class_numbers.min
        @last_class_number = @class_numbers.max

        if (@last_class_number - @first_class_number + 1) == @class_numbers.uniq.count
          @all_class_found = true
        else
          @all_class_found = false
        end

        @first_class_roles = @roles.select{ |r| r.displayName.match(/\d+/)[0].to_i == @first_class_number }
      end

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
      end

      raise RolesNotFound if @roles.empty? && @groups.empty?
    rescue RolesNotFound
      flash[:alert] = t('flash.school.no_roles_nor_groups')
      redirect_to school_path(@school)
    end
  end

  def create
    @do_only_groups = new_group_management?(@school)

    if !@do_only_groups && !params[:do_roles] && !params[:do_groups]
      flash[:notice] = "Et valinnut rooleja ja/tai ryhmiä mitä käsitellä"
      redirect_to new_rename_groups_path(@school)
      return
    end

    num_roles_renamed = 0
    num_groups_renamed = 0

    if params[:do_roles] && !@do_only_groups
      params[:role_display_name]&.each_index do |index|
        unless params[:role_display_name][index].empty?
          role = Role.find(params[:role_puavo_id][index])
          role.displayName = params[:role_display_name][index]
          role.save!
          num_roles_renamed += 1
        end
      end

      params[:new_roles]&.each do |role_name|
        unless role_name.empty?
          r = Role.new(:displayName => role_name,
                       :puavoSchool => @school.dn )
          r.save!
        end
      end
    end

    if params[:do_groups] || @do_only_groups
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
                        :puavoSchool => @school.dn )
          g.save!
        end
      end
    end

    if @do_only_groups
      flash[:notice] = "Nimetty #{num_groups_renamed} ryhmä(ä) uudelleen."
    else
      flash[:notice] = "Nimetty #{num_roles_renamed} rooli(a) ja #{num_groups_renamed} ryhmä(ä) uudelleen."
    end

    respond_to do |format|
      format.html { redirect_to( school_path(@school) ) }
    end
  end
end
