
require_relative "./meta_menu"

class PuavoMenu < MetaMenu

  # SCHOOL
  child do
    title { t('layouts.application.school') }
    link { school_path(@school) }
    active_on SchoolsController
    active_on Schools::ExternalServicesController
    owners_only { false }

    child do
      title { t('schools.menu.dashboard') }
      link { school_path(@school) }
      active_on SchoolsController
      active_on_action "show", "edit"
      owners_only { false }
    end

    child do
      title { t('schools.menu.admins') }
      link { admins_school_path(@school) }
      active_on_action "admins"
      owners_only { true }
      hide_when { not current_user.organisation_owner? }
    end

    child do
      title { t('schools.menu.wlan') }
      link { wlan_school_path(@school) }
      active_on_action "wlan"
      active_on_action "wlan_update"
      owners_only { false }
    end

    child do
      title { t('external_services.title') }
      link { schools_external_services_path(@school) }
      owners_only { false }
      active_on Schools::ExternalServicesController
    end
  end

  # USERS
  child do
    title { t('layouts.application.users')  }
    link { users_path(@school) }
    active_on UsersController
    active_on ListsController
    active_on ImportToolController
    active_on NewImportController
    owners_only { false }

    child do
      title { t('link.users') }
      link { users_path(@school) }
      owners_only { false }
      active_on UsersController
    end

    child do
      title { t('import_tool.import') }
      link { import_tool_path(@school) }
      active_on ImportToolController
      owners_only { true }
      # XXX: Feature switch!
      hide_when { !current_user.organisation_owner? }
    end

    child do
      title { t('link.new_import') }
      link { new_import_path(@school) }
      active_on NewImportController
      owners_only { false }
      hide_when { !current_user.organisation_owner? && !can_schooladmin_do_this?(current_user.uid, :import_users) }
    end

    child do
      title { t('link.lists') }
      link { lists_path(@school) }
      owners_only { false }
      active_on ListsController
    end
  end

  # GROUPS
  child do
    title { t('link.groups')  }
    link { groups_path(@school) }
    active_on GroupsController
    owners_only { false }

    child do
      title { t('link.groups') }
      link { groups_path(@school) }
      active_on GroupsController
      active_on_action 'index'
      active_on_action 'show'
      active_on_action 'edit'
      active_on_action 'create'
      active_on_action 'update'
      owners_only { false }
    end

    child do
      title { t('link.group_members_mass_edit') }
      link { group_members_mass_edit_path(@school) }
      active_on GroupsController
      active_on_action 'members_mass_edit'
      owners_only { true }
      hide_when { !current_user.organisation_owner? }
    end

    child do
      title { t('link.find_groupless_users') }
      link { find_groupless_users_path(@school) }
      active_on GroupsController
      active_on_action 'find_groupless_users'
      owners_only { false }
    end
  end

  # DEVICES
  child do
    title { t('layouts.application.devices') }
    link { "/devices/#{ @school.id }/devices" } # FIXME
    active_on DevicesController
    active_on ImageStatisticsController
    active_on PrinterPermissionsController
    owners_only { false }

    child do
      title { t('link.devices') }
      link { devices_path(@school) }
      active_on DevicesController
      owners_only { false }
    end

    child do
      title { t('link.image_statistics') }
      link { school_image_statistics_path(@school) }
      active_on ImageStatisticsController
      owners_only { false }
    end

    child do
      title { t('link.printer_permissions') }
      link { printer_permissions_path(@school) }
      active_on PrinterPermissionsController
      owners_only { false }
    end
  end

end
