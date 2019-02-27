class ListsController < ApplicationController

  # GET /users/:school_id/lists
  def index

    @lists = List.all.select do |list|
      list.school_id.to_s == @school.puavoId.to_s &&
        (!list.downloaded || params[:downloaded] )
    end

    @users_by_id = {}
    @lists.each do |list|
      list.users.each do |user_id|
        begin
          user = User.find(user_id)
        rescue ActiveLdap::EntryNotFound
          puts "Can't find user by ID #{user_id}, maybe the user has been deleted? Ignoring..."
          next
        end

        @users_by_id[user_id] = user
      end
    end

    @lists.each do |li|
      missing_users = false

      li.users.each do |u|
        unless @users_by_id.include?(u)
          missing_users = true
          break
        end
      end

      # don't try to sort broken lists
      next if missing_users

      li.users.sort! do |u_a, u_b|
        (@users_by_id[u_a].givenName + @users_by_id[u_a].sn).downcase <=>
        (@users_by_id[u_b].givenName + @users_by_id[u_b].sn).downcase
      end
    end

    @lists.sort{|a, b| a.created_at <=> b.created_at}.reverse!

    @password_requirements = password_requirements

    respond_to do |format|
      format.html
    end
  end

  # DELETE /users/:school_id/lists/:id/
  def delete
    @list = List.by_id(params[:id])

    if @list.nil?
      flash[:alert] = t('.invalid_list')
      redirect_to lists_path(@school)
      return
    end

    begin
      @list.downloaded = true
      @list.save
    rescue
      flash[:alert] = t('.deletion_failed')
      redirect_to lists_path(@school)
      return
    end

    flash[:notice] = t('.deleted')

    respond_to do |format|
      format.html { redirect_to lists_path(@school) }
    end
  end

  # POST /users/:school_id/lists/:id
  def download
    @list = List.by_id(params[:id])

    # First group users by their group or role. Filter out missing users.
    @users_by_group = {}

    @list.users.each do |user_id|
      begin
        user = User.find(user_id)
      rescue ActiveLdap::EntryNotFound
        # This can happen if a user is deleted after they were imported
        # but before the list is downloaded. The lists are maintained
        # separately, so their contents are not updated.
        puts "Can't find user by ID #{user_id}, maybe the user has been deleted? Ignoring..."
        next
      end

      # group users by their group or role
      group_name = "<?>"

      if new_group_management?(@school)
        # prioritise groups over roles
        if Array(user.puavoEduPersonAffiliation).include?("student")
          grp = user.teaching_group

          if grp.nil? || grp.empty?
            # teaching group is not set, use the first group then
            if user.groups && user.groups.first
              group_name = user.groups.first.displayName
            end
          else
            group_name = user.teaching_group["name"]
          end
        else
          # assume that users who aren't students are teachers...
          group_name = I18n.t("puavoEduPersonAffiliation_teacher")
        end
      else
        # If the user has no roles, then get groups, doesn't matter as
        # long as they're grouped *somehow*...

        if user.roles && user.roles.first
          # have a role
          group_name = user.roles.first.displayName
        elsif user.teaching_group
          # no role, try the teaching group
          group_name = user.teaching_group["name"]
        elsif user.groups && user.groups.first
          # no role, no teaching group, use the first group
          group_name = user.groups.first["name"]
        end
      end

      @users_by_group[group_name] ||= []
      @users_by_group[group_name].push(user)
    end

    # All users have been grouped now, so actually change their passwords
    @users_by_group.each do |group, users|
      users.each do |u|
        if params[:list][:generate_password] == "true"
          u.set_generated_password
        else
          u.new_password = params[:list][:new_password]
        end

        u.save!
      end
    end

    # Then generate a PDF containing the new passwords
    pdf = Prawn::Document.new( :skip_page_creation => true, :page_size => 'A4')

    # Use a proper Unicode font, not the built-in PDF fonts
    font_file = Pathname.new(Rails.root.join('app', 'assets', 'stylesheets', 'font', 'FreeSerif.ttf'))
    pdf.font_families["unicodefont"] = { :normal => { :file => font_file, :font => "Regular" } }

    @users_by_group.each do |group_name, users|
      # Sort users by sn + givenName
      users = users.sort do |a,b|
        (a.givenName + a.sn).downcase <=> (b.givenName + b.sn).downcase
      end

      pdf.start_new_page
      pdf.font "unicodefont"
      pdf.font_size = 12
      pdf.draw_text "#{ current_organisation.name }, #{ @school.displayName }, #{ group_name }",
        :at => pdf.bounds.top_left
      pdf.text "\n"

      users_of_page_count = 0
      users.each do |user|
        pdf.indent(300) do
          pdf.text "#{t('activeldap.attributes.user.displayName')}: #{user.displayName}"
          pdf.text "#{t('activeldap.attributes.user.uid')}: #{user.uid}"
          pdf.text "#{t('activeldap.attributes.user.password')}: #{user.new_password}\n\n\n"
        end
        users_of_page_count += 1
        if users_of_page_count > 10 && user != users.last
          users_of_page_count = 0
          pdf.start_new_page
          pdf.draw_text "#{ current_organisation.name }, #{ @school.displayName }, #{ group_name }",
            :at => pdf.bounds.top_left
          pdf.text "\n"
        end
      end

    end

    filename = current_organisation.organisation_key + "_" +
      @school.cn + "_" + Time.now.strftime("%Y%m%d_%H%M%S") + ".pdf"

    @list.downloaded = true
    @list.save

    respond_to do |format|
      format.pdf do
        send_data(
                  pdf.render,
                  :filename => filename,
                  :type => 'application/pdf',
                  :disposition => 'attachment' )
      end

    end
  end
end
