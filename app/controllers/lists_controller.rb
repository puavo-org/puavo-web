class ListsController < ApplicationController

  # GET /users/:school_id/lists
  def index

    @lists = List.all.select do |list|
      list.school_id.to_s == @school.puavoId.to_s &&
        (!list.downloaded || params[:downloaded] )
    end

    respond_to do |format|
      format.html
    end
  end

  # POST /users/:school_id/lists/:id
  def download
    @list = List.by_id(params[:id])

    @users_by_group = {}

    @list.users.each do |user_id|
      user = User.find(user_id)
      if params[:list][:generate_password] == "true"
        user.set_generated_password
      else
        user.new_password = params[:list][:new_password]
      end

      user.save!

      # FIXME Use Group if new_group_management? is true
      group = user.roles.first

      @users_by_group[group.displayName] ||= []
      @users_by_group[group.displayName].push(user)
    end

    pdf = Prawn::Document.new( :skip_page_creation => true, :page_size => 'A4')

    pdf.start_new_page
    pdf.font "Times-Roman"
    pdf.font_size = 12
    start_page_number = pdf.page_number

    @users_by_group.each do |group_name, users|
      # Sort users by sn + givenName
      users = users.sort{|a,b| a.sn + a.givenName <=> b.sn + a.givenName }

      pdf.text "\n"

      users_of_page_count = 0
      users.each do |user|
        pdf.indent(300) do
          pdf.text "#{t('activeldap.attributes.user.displayName')}: #{user.displayName}"
          pdf.text "#{t('activeldap.attributes.user.uid')}: #{user.uid}"
          pdf.text "#{t('activeldap.attributes.user.password')}: #{user.new_password}\n\n\n"

          users_of_page_count += 1
          if users_of_page_count > 10 && user != users.last
            users_of_page_count = 0
            pdf.start_new_page
          end
        end
        pdf.repeat start_page_number..pdf.page_number do
          pdf.draw_text "#{ current_organisation.name }, #{ @school.displayName }, #{ group_name }",
          :at => pdf.bounds.top_left
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
                  :disposition => 'inline' )
      end

    end
  end
end
