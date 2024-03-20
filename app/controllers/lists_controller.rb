require 'set'

class ListsController < ApplicationController
  include Puavo::Integrations     # request ID generation
  include PasswordsPdfHelper      # PDF generation

  # GET /users/:school_id/lists
  def index
    # List all non-downloaded lists in this school
    @lists = List.all.select do |list|
      (list.school_id.to_s == @school.puavoId.to_s) && (!list.downloaded || params[:downloaded])
    end

    groups = list_groups(school.dn.to_s)

    # Load user data and the best group for every user on every list. Find each user only once.
    # Deleted/invalid users get a placeholder entry that does not mess up sorting.
    @list_members = {}

    @lists.each do |list|
      list.users.each do |id|
        next if @list_members.include?(id)
        @list_members[id] = get_user_and_group(id, groups)
      end

      # Sort the users alphabetically, ignoring letter case
      list.users.sort! { |a, b| @list_members[a][:sort] <=> @list_members[b][:sort] }
    end

    # Sort the lists by creation date, newest first
    @lists.sort! { |a, b| a.created_at <=> b.created_at }.reverse!

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
    request_id = generate_synchronous_call_id()

    list = List.by_id(params[:id])

    groups = list_groups(@school.dn.to_s)
    users = []

    # Set the new passwords
    randomize_password = params[:list][:generate_password] == 'true'
    new_password = params[:new_password]

    list.users.each do |id|
      plain_user = get_user_and_group(id, groups)
      next if plain_user[:missing]

      # Ungrouped users need some "marker", otherwise grouping will break in the generated PDF.
      # The PDF generator is the same used in the new users mass import/update tool, so
      # we use its translation strings.
      plain_user[:group] = t('new_import.pdf.no_group') if plain_user[:group].nil?

      user = User.find(id)

      if randomize_password
        user.set_generated_password
        plain_user[:password] = user.new_password
      else
        user.set_password(new_password)
        plain_user[:password] = new_password
      end

      begin
        user.save!
      rescue StandardError => e
        logger.error("[#{request_id}] #{e}")
        flash[:alert] = t('.password_changing_failed', request_id: request_id)
        redirect_to lists_path(@school)
        return
      end

      users << plain_user
    end

    # Sort the users
    users.sort! do |a, b|
      [a[:group], a[:first], a[:last]] <=>
      [b[:group], b[:first], b[:last]]
    end

    # Generate the PDF
    filename_timestamp, pdf = PasswordsPdfHelper.generate_pdf(users, current_organisation.name)
    filename = "#{current_organisation.organisation_key}_#{@school.cn}_#{filename_timestamp}.pdf"

    # Hide the list (it will be automatically deleted eventually)
    list.downloaded = true
    #list.save

    respond_to do |format|
      format.pdf do
        send_data(pdf.render, filename: filename, type: 'application/pdf', disposition: 'attachment')
      end
    end
  rescue StandardError => e
    logger.error("[#{request_id}] #{e}")
    flash[:alert] = t('.password_changing_failed', request_id: request_id)
    redirect_to lists_path(@school)
    return
  end

  def download_as_csv
    list = List.by_id(params[:id])

    data = %w[puavoid first_name last_name username roles group].join(',')
    data += "\n"

    groups = list_groups(@school.dn.to_s)

    list.users.each do |id|
      user = get_user_and_group(id, groups)
      next if user[:missing]    # we have no data for missing users

      data += [
        id, user[:first], user[:last], user[:uid], user[:roles].join(';'), user[:group]
      ].join(',') + "\n"
    end

    filename = "#{current_organisation.organisation_key}_#{@school.cn}_#{Time.now.strftime("%Y%m%d_%H%M%S")}.csv"

    send_data(data, filename: filename, type: 'text/csv', disposition: 'attachment')
  end

private
  # Extracts puavoId from a DN. Returns -1 if failed.
  PUAVOID_MATCHER = /puavoId=(\d+)/.freeze

  def puavoid_from_dn(dn)
    match = dn.to_s.match(PUAVOID_MATCHER)
    match ? match[1].to_i : -1
  rescue StandardError
    -1
  end

  # Makes a list of groups and their members in the specified school
  def list_groups(school_dn)
    Group.search_as_utf8(
      filter: "(&(objectClass=puavoEduGroup)(puavoSchool=#{Net::LDAP::Filter.escape(school_dn.to_s)}))",
      attributes: ['displayName', 'puavoEduGroupType', 'member']
    ).collect do |_, raw_group|
      {
        name: raw_group['displayName'][0],
        type: raw_group.fetch('puavoEduGroupType', [nil])[0],
        members: Array(raw_group['member'] || []).map { |dn| puavoid_from_dn(dn) }.to_set.freeze
      }
    end.freeze
  end

  # Raw searches for the specified user, and fills in their information and the best group
  def get_user_and_group(puavoid, groups)
    raw_user = User.search_as_utf8(
      filter: "(puavoId=#{Net::LDAP::Filter.escape(puavoid.to_s)})",
      attributes: ['uid', 'givenName', 'sn', 'puavoEduPersonAffiliation']
    )

    if raw_user.nil? || raw_user.empty?
      # Return a placeholder so that sorting will work without hacks
      return {
        missing: true,
        sort: ''
      }
    end

    raw_user = raw_user[0][1]

    user = {
      missing: false,
      uid: raw_user['uid'][0],
      first: raw_user['givenName'][0],
      last: raw_user['sn'][0],
      roles: Array(raw_user['puavoEduPersonAffiliation'] || []),
      sort: "#{raw_user['givenName'][0]} #{raw_user['sn'][0]}".downcase,    # used when sorting the list
      group: nil
    }

    best = PasswordsPdfHelper.find_best_group(puavoid, groups)
    user[:group] = best[:name] if best

    user
  end
end
