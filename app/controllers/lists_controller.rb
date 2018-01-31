class ListsController < ApplicationController

  # GET /users/:school_id/lists
  def index

    @lists = List.all.select do |list|
      list.school_id.to_s == @school.puavoId.to_s &&
        (!list.downloaded || params[:downloaded] )
    end

    @users_by_id = {}
    @lists.each do |list|
      count = 1
      list.users.each do |user_id|
        begin
          user = User.find(user_id)
        rescue ActiveLdap::EntryNotFound
          puts "Can't find user by ID #{user_id}, maybe the user has been deleted? Ignoring..."
          next
        end

        @users_by_id[user_id] = user

        # UI needs only first 10 users
        break if count > 10
        count += 1
      end
    end

    respond_to do |format|
      format.html
    end
  end

  # POST /users/:school_id/lists/:id
  def download
    @list = List.by_id(params[:id])

    if new_group_management?(@school)
      # /v3/schools/:school_id/teaching_groups
      @teaching_groups = rest_proxy.get("/v3/schools/#{ @school.puavoId }/teaching_groups").parse or []
      @teaching_groups_by_username = {}
      @teaching_groups.each do |group|
        group["member_usernames"].each do |username|
          @teaching_groups_by_username[username] = group
        end
      end
    end

    @users_by_group = {}

    @list.users.each do |user_id|
      begin
        user = User.find(user_id)
      rescue ActiveLdap::EntryNotFound
        puts "Can't find user by ID #{user_id}, maybe the user has been deleted? Ignoring..."
        next
      end

      if params[:list][:generate_password] == "true"
        user.set_generated_password
      else
        user.new_password = params[:list][:new_password]
      end

      user.save!

      if new_group_management?(@school)
        group = {}
        if Array(user.puavoEduPersonAffiliation).include?("student")
          group = @teaching_groups_by_username[user.uid]
        else
          group["name"] = I18n.t("puavoEduPersonAffiliation_teacher")
        end
        @users_by_group[group["name"]] ||= []
        @users_by_group[group["name"]].push(user)
      else
        group = user.roles.first
        @users_by_group[group.displayName] ||= []
        @users_by_group[group.displayName].push(user)
      end
    end

    pdf = Prawn::Document.new( :skip_page_creation => true, :page_size => 'A4')

    @users_by_group.each do |group_name, users|
      # Sort users by sn + givenName
      users = users.sort{|a,b| a.sn + a.givenName <=> b.sn + a.givenName }

      pdf.start_new_page
      pdf.font "Times-Roman"
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
      @school.cn + "_" + Time.now.strftime("%Y%m%d") + ".pdf"

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
