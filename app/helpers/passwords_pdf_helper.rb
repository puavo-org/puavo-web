# A helper module/method for generating PDFs that contain a list of users, grouped by
# their primary group, and their new passwords.

module PasswordsPdfHelper
  # We list only one group for every user, so if the user is in multiple groups, try to select
  # the best one. These are the group priorities.
  GROUP_PRIORITY = {
    'teaching group' => 5,
    'year class' => 4,
    'course group' => 3,
    'administrative group' => 2,
    'archive users' => 1,
    'other groups' => 0,
    nil => -1,
  }.freeze

  def self.get_group_priorities
    GROUP_PRIORITY
  end

  # Find the best group for the specified user
  def self.find_best_group(puavoid, groups)
    best = nil

    groups.each do |group|
      next unless group[:members].include?(puavoid)

      if best.nil? || GROUP_PRIORITY[group[:type]] > GROUP_PRIORITY[group[:type]]
        best = group
      end
    end

    best
  end

  # Generate the PDF for zero or more users
  def self.generate_pdf(users, organisation_name)
    # Figure out the total page count. Each teaching group gets its own page (or pages).
    # I determined empirically that 18 users per page is more or less the maximum.
    # If you put more, the final user can get split across two pages.
    users_per_page = 18
    num_pages = 0
    current_page = 0

    grouped_users = users.chunk { |u| u[:group] }

    grouped_users.each do |group_name, group_users|
      num_pages += group_users.each_slice(users_per_page).count
    end

    now = Time.now
    header_timestamp = now.strftime('%Y-%m-%d %H:%M:%S')
    filename_timestamp = now.strftime('%Y%m%d_%H%M%S')

    pdf = Prawn::Document.new(skip_page_creation: true, page_size: 'A4')
    Prawn::Fonts::AFM.hide_m17n_warning = true

    # Use a proper Unicode font
    pdf.font_families['unicodefont'] = {
      normal: {
        font: 'Regular',
        file: Pathname.new(Rails.root.join('app', 'assets', 'stylesheets', 'font', 'FreeSerif.ttf')),
      }
    }

    if users.count == 0
      pdf.start_new_page()
      pdf.font('unicodefont')
      pdf.font_size(12)
      pdf.draw_text(I18n.t('new_import.pdf.no_users'), at: pdf.bounds.top_left)

      return filename_timestamp, pdf
    end

    grouped_users.each do |group_name, group_users|
      group_users.each_slice(users_per_page).each_with_index do |block, _|
        pdf.start_new_page()

        pdf.font('unicodefont')
        pdf.font_size(18)
        header_text = organisation_name
        header_text += ", #{group_name}" if group_name && group_name.length > 0
        pdf.text(header_text)

        pdf.font('unicodefont')
        pdf.font_size(12)
        pdf.draw_text("(#{I18n.t('new_import.pdf.page')} #{current_page + 1}/#{num_pages}, #{header_timestamp})",
                      at: [(pdf.bounds.right - 160), 0])
        pdf.text("\n")

        current_page += 1

        block.each do |u|
          pdf.font('unicodefont')
          pdf.font_size(12)

          pdf.text("#{u[:last]}, #{u[:first]} (#{u[:uid]})")

          if u[:password]
            pdf.font('Courier')
            pdf.text(u[:password])
          end

          pdf.text("\n")
        end
      end
    end

    return filename_timestamp, pdf
  end
end
